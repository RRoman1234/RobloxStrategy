local Attacking = {}

local DEFAULT_DAMAGE = 25
local DEFAULT_RANGE = 5
local DEFAULT_COOLDOWN = 1
local DEFAULT_ANIM_LENGTH = 0.6
local CHASE_REFRESH = 0.25   -- как часто обновлять точку преследования
local TURN_SPEED = 14        -- скорость плавного разворота к цели
local FACING_DOT = 0.995     -- если уже смотрим почти на цель — не трогаем CFrame
local RETARGET_RADIUS = 40   -- радиус поиска следующей жертвы

-- Атрибут (бафф героя) перекрывает одноимённый Value-тег юнита
local function readNumber(unit, name, default)
	local attr = unit:GetAttribute(name)
	if attr then return attr end
	local value = unit:FindFirstChild(name)
	return value and value.Value or default
end

-- Урон с учётом брони цели: DamageTaken = множитель входящего урона (1 = без брони)
local function dealDamage(obj, health, amount)
	health.Value = math.max(0, health.Value - amount * (obj:GetAttribute("DamageTaken") or 1))
end

-- Всё, что не меняется за время боя с одной целью, считаем один раз
local function setTarget(fsm, unit, target)
	fsm.Target = target
	fsm.TargetHealth = target:FindFirstChild("Health")
	fsm.TargetPart = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
	fsm.AttackRange = readNumber(unit, "AttackRange", DEFAULT_RANGE)

	local _, size = target:GetBoundingBox()
	fsm.TargetRadius = math.max(size.X, size.Z) / 2

	fsm.IsAnimating = false
	fsm.Chasing = nil
	fsm.ChaseTimer = 0
	fsm.StateToken = (fsm.StateToken or 0) + 1 -- отменяем отложенный урон/анимацию по прошлой цели
end

-- Плавный разворот на месте (раньше CFrame перезаписывался каждый кадр)
local function faceTarget(root, targetPos, dt)
	local rootCF = root.CFrame
	local pos = rootCF.Position
	local flat = Vector3.new(targetPos.X - pos.X, 0, targetPos.Z - pos.Z)
	if flat.Magnitude < 0.01 then return end

	local dir = flat.Unit
	if rootCF.LookVector:Dot(dir) > FACING_DOT then return end

	local goal = CFrame.lookAt(pos, pos + dir)
	root.CFrame = rootCF:Lerp(goal, math.min(1, dt * TURN_SPEED))
end

function Attacking.OnEnter(fsm, unit, target)
	fsm.IsAggressive = true
	fsm:SetCollisionMode("Ghost") -- Теперь юниты проходят сквозь своих во время боя
	setTarget(fsm, unit, target)
end

-- Смена цели без полного Exit/Enter
function Attacking.OnRetarget(fsm, unit, target)
	setTarget(fsm, unit, target)
end

function Attacking.OnUpdate(fsm, unit, dt)
	if fsm.IsAnimating then return end

	local target = fsm.Target
	local targetHealth = fsm.TargetHealth
	local targetPart = fsm.TargetPart

	-- ЕСЛИ ЦЕЛЬ УМЕРЛА ИЛИ ПРОПАЛА
	if not target or not target.Parent or not targetHealth or targetHealth.Value <= 0
		or not targetPart or not targetPart.Parent then

		local newEnemy = fsm:FindClosestEnemy(RETARGET_RADIUS)
		if newEnemy then
			fsm:ChangeState("Attacking", newEnemy) -- Нашли? Сразу бьем!
		else
			fsm:ChangeState("Idle") -- Не нашли? Стоим, но остаемся агрессивными
		end
		return
	end

	local root, humanoid = fsm.Root, fsm.Humanoid
	if not root then return end

	local myPos = root.Position
	local targetPos = targetPart.Position
	local effectiveRange = fsm.AttackRange + fsm.TargetRadius + 2

	local dx, dz = myPos.X - targetPos.X, myPos.Z - targetPos.Z
	local inRange = dx * dx + dz * dz <= effectiveRange * effectiveRange

	if inRange then
		-- Остановка выполняется один раз при входе в радиус, а не каждый кадр
		if fsm.Chasing ~= false then
			fsm.Chasing = false
			if humanoid then humanoid:MoveTo(myPos) end
			fsm:PlayAnimation("Idle")
		end

		faceTarget(root, targetPos, dt)

		local now = os.clock()
		local cooldown = readNumber(unit, "AttackCooldown", DEFAULT_COOLDOWN) / (unit:GetAttribute("AttackSpeedMult") or 1)

		if now - fsm.LastAttackTime >= cooldown then
			fsm.LastAttackTime = now
			fsm.IsAnimating = true

			local token = fsm.StateToken
			local damage = readNumber(unit, "Damage", DEFAULT_DAMAGE) * (unit:GetAttribute("DamageMult") or 1)
			local isBuilding = target.Parent == workspace:FindFirstChild("Buildings")

			fsm:PlayAnimation("AttackNO", true)
			local track = fsm.LoadedAnimations.AttackNO
			local animLength = (track and track.Length > 0) and track.Length or DEFAULT_ANIM_LENGTH

			-- Один поток вместо двух task.delay
			task.spawn(function()
				task.wait(animLength / 2)
				if fsm.StateToken ~= token then return end

				local aoeRadius = readNumber(unit, "AoERadius", 0)   -- 0 = обычная атака
				local aoeShare = readNumber(unit, "AoEShare", 1)     -- доля урона по соседям цели
				local hitPos = targetPart and targetPart.Position

				-- 1. Урон основной цели
				if targetHealth.Value > 0 then
					local dealt = damage * (isBuilding and readNumber(unit, "VsBuildings", 1) or 1)
					dealDamage(target, targetHealth, dealt)

					-- Вампиризм героя (Lifesteal = доля нанесённого урона)
					local lifesteal = unit:GetAttribute("Lifesteal")
					local ownHealth, maxHealth = unit:FindFirstChild("Health"), unit:GetAttribute("MaxHealth")
					if lifesteal and ownHealth and maxHealth and ownHealth.Value > 0 then
						ownHealth.Value = math.min(maxHealth, ownHealth.Value + dealt * lifesteal)
					end

					-- Добыча с вражеских зданий копится на юните, казна Королевства её забирает
					local plunder = readNumber(unit, "Plunder", 0)
					if isBuilding and plunder > 0 then
						unit:SetAttribute("PlunderGold", (unit:GetAttribute("PlunderGold") or 0) + dealt * plunder)
					end
				end

				-- 2. Урон по площади (AoE)
				if aoeRadius > 0 and hitPos then
					local myOwner = fsm.OwnerTag and fsm.OwnerTag.Value

					for _, folderName in ipairs({"Units", "Buildings"}) do
						local folder = workspace:FindFirstChild(folderName)
						if folder then
							for _, obj in ipairs(folder:GetChildren()) do
								if obj ~= target then -- Основной цели уже нанесли урон
									local otherOwner = obj:FindFirstChild("Owner")
									local h = obj:FindFirstChild("Health")

									if otherOwner and otherOwner.Value ~= myOwner and h and h.Value > 0 then
										local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
										if part and (part.Position - hitPos).Magnitude <= aoeRadius then
											dealDamage(obj, h, damage * aoeShare)
										end
									end
								end
							end
						end
					end
				end

				task.wait(animLength / 2)
				if fsm.StateToken ~= token then return end
				fsm.IsAnimating = false
				fsm:PlayAnimation("Idle")
			end)
		end
	else
		-- ПРЕСЛЕДОВАНИЕ
		if fsm.Chasing ~= true then
			fsm.Chasing = true
			fsm.ChaseTimer = 0 -- первая команда уходит сразу
			fsm:PlayAnimation("Walk")
		end

		-- MoveTo не нужно вызывать каждый кадр — достаточно несколько раз в секунду
		fsm.ChaseTimer -= dt
		if fsm.ChaseTimer <= 0 and humanoid then
			fsm.ChaseTimer = CHASE_REFRESH
			humanoid:MoveTo(targetPos)
		end
	end
end

function Attacking.OnExit(fsm)
	fsm:SetCollisionMode("Solid") -- Возвращаем плотность, когда бой окончен
	fsm.Target = nil
	fsm.TargetHealth = nil
	fsm.TargetPart = nil
	fsm.IsAnimating = false
	fsm.Chasing = nil
	fsm.StateToken = (fsm.StateToken or 0) + 1
end

return Attacking
