local StateMachine = {}
StateMachine.__index = StateMachine

local ENEMY_FOLDERS = { "Units", "Buildings" }
local ANIM_FADE_TIME = 0.15

local function getRoot(model)
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
end

function StateMachine.new(unitModel)
	local self = setmetatable({}, StateMachine)
	self.Unit = unitModel
	self.States = {}
	self.CurrentState = nil   -- имя текущего состояния
	self.CurrentModule = nil  -- модуль текущего состояния (чтобы не искать по таблице каждый кадр)
	self.StateToken = 0
	self.PathRequestId = 0
	self.LastAttackTime = 0

	-- Кэш ссылок, которые нужны состояниям каждый кадр
	self.Humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	self.Root = getRoot(unitModel)
	self.OwnerTag = unitModel:FindFirstChild("Owner")

	-- Анимации
	self.LoadedAnimations = {}
	self.CurrentAnimName = nil
	self.CurrentTrack = nil

	local animator = self.Humanoid and self.Humanoid:FindFirstChildOfClass("Animator")
	local animFolder = unitModel:FindFirstChild("Animations")
	if animator and animFolder then
		for _, anim in ipairs(animFolder:GetChildren()) do
			if anim:IsA("Animation") then
				self.LoadedAnimations[anim.Name] = animator:LoadAnimation(anim)
			end
		end
	end

	-- Коллизии: список частей кэшируется, а не собирается через GetDescendants при каждой смене режима
	self.CollisionMode = nil
	self.CollisionGroupName = nil
	self._parts = nil
	self._descendantConn = unitModel.DescendantAdded:Connect(function(desc)
		self._parts = nil
		if self.CollisionGroupName and desc:IsA("BasePart") then
			desc.CollisionGroup = self.CollisionGroupName
		end
	end)

	return self
end

-- Вызывается перед удалением юнита: даёт состоянию прибраться (стройплощадка, возврат золота и т.д.)
function StateMachine:Destroy()
	local module = self.CurrentModule
	self.CurrentModule = nil
	self.CurrentState = nil
	self.StateToken += 1
	self.PathRequestId += 1

	if module and module.OnExit then
		pcall(module.OnExit, self, self.Unit, nil)
	end

	if self._descendantConn then
		self._descendantConn:Disconnect()
		self._descendantConn = nil
	end
end

function StateMachine:PlayAnimation(animName, force)
	if not force and self.CurrentAnimName == animName then return end
	self.CurrentAnimName = animName

	local newTrack = self.LoadedAnimations[animName]
	local oldTrack = self.CurrentTrack

	-- Плавное смешивание вместо резкого Stop/Play всех треков подряд
	if oldTrack and oldTrack ~= newTrack then
		oldTrack:Stop(ANIM_FADE_TIME)
	end

	if newTrack then
		if force and newTrack.IsPlaying then
			newTrack:Stop(0)
		end
		newTrack:Play(ANIM_FADE_TIME)
	end

	self.CurrentTrack = newTrack
end

function StateMachine:AddState(stateName, stateModule)
	self.States[stateName] = stateModule
end

function StateMachine:ChangeState(stateName, ...)
	local newModule = self.States[stateName]
	if not newModule then
		warn("⚠️ Состояние " .. stateName .. " не найдено!")
		return
	end

	local currentModule = self.CurrentModule

	-- Повторный вход в то же состояние (новая точка назначения, новая цель):
	-- если состояние умеет, просто обновляем цель без полного Exit/Enter
	if currentModule == newModule and newModule.OnRetarget then
		newModule.OnRetarget(self, self.Unit, ...)
		return
	end

	if currentModule and currentModule.OnExit then
		currentModule.OnExit(self, self.Unit, stateName)
	end

	self.CurrentState = stateName
	self.CurrentModule = newModule

	if newModule.OnEnter then
		newModule.OnEnter(self, self.Unit, ...)
	end
end

function StateMachine:Update(dt)
	local module = self.CurrentModule
	if module and module.OnUpdate then
		module.OnUpdate(self, self.Unit, dt)
	end
end

function StateMachine:FindClosestEnemy(scanRadius, searchCenter)
	local ownerTag = self.OwnerTag or self.Unit:FindFirstChild("Owner")
	local myOwner = ownerTag and ownerTag.Value
	local center = searchCenter or (self.Root and self.Root.Position)
	if not center then return nil end

	-- Получаем цель, которую может атаковать этот юнит
	local canAttackTag = self.Unit:FindFirstChild("CanAttack")
	local myTargetType = canAttackTag and canAttackTag.Value or "Both"

	if myTargetType == "None" then return nil end -- Добытчики не ищут врагов

	local radius = scanRadius or math.huge
	local bestDistSq = radius * radius
	local closest = nil

	for _, folderName in ipairs(ENEMY_FOLDERS) do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			for _, obj in ipairs(folder:GetChildren()) do
				local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
				if part then
					local offset = part.Position - center
					local distSq = offset:Dot(offset)

					if distSq < bestDistSq then
						local otherOwner = obj:FindFirstChild("Owner")
						local health = obj:FindFirstChild("Health")

						if otherOwner and otherOwner.Value ~= myOwner and health and health.Value > 0 then
							-- Проверка типа цели (Земля/Воздух)
							local moveTypeTag = obj:FindFirstChild("MovementType")
							-- По умолчанию все считаются наземными
							local enemyType = moveTypeTag and moveTypeTag.Value or "Ground"

							if myTargetType == "Both" or myTargetType == enemyType then
								bestDistSq = distSq
								closest = obj
							end
						end
					end
				end
			end
		end
	end

	return closest
end

function StateMachine:SetCollisionMode(mode)
	if self.CollisionMode == mode then return end

	local ownerTag = self.OwnerTag or self.Unit:FindFirstChild("Owner")
	if not ownerTag or ownerTag.Value == "" then return end
	self.OwnerTag = ownerTag

	local groupName = mode .. "_" .. ownerTag.Value
	self.CollisionMode = mode
	self.CollisionGroupName = groupName

	if not self._parts then
		local parts = {}
		for _, desc in ipairs(self.Unit:GetDescendants()) do
			if desc:IsA("BasePart") then
				table.insert(parts, desc)
			end
		end
		self._parts = parts
	end

	for _, part in ipairs(self._parts) do
		part.CollisionGroup = groupName
	end
end

return StateMachine
