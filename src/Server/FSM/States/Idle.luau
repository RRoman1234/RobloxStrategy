local Idle = {}

local SCAN_INTERVAL = 0.5 -- как часто агрессивный юнит ищет врагов
local SCAN_RADIUS = 30    -- радиус бдительности

function Idle.OnEnter(fsm, unit)
	fsm:PlayAnimation("Idle")

	-- Принудительно останавливаем юнита
	local humanoid, root = fsm.Humanoid, fsm.Root
	if humanoid and root then
		humanoid:MoveTo(root.Position)
	end

	-- Добытчик на месте добычи смотрит на свою базу
	local link, home = unit:FindFirstChild("LinkedNexus"), unit:FindFirstChild("HomePosition")
	local base = link and link.Value
	if root and base and base.Parent and home and Vector3.new(root.Position.X - home.Value.X, 0, root.Position.Z - home.Value.Z).Magnitude < 4 then
		local basePos = base:GetPivot().Position
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(basePos.X, root.Position.Y, basePos.Z))
	end

	-- Случайный сдвиг, чтобы сканы разных юнитов не выпадали на один и тот же кадр
	fsm.ScanTimer = math.random() * SCAN_INTERVAL
end

function Idle.OnUpdate(fsm, unit, dt)
	-- Сканируем ТОЛЬКО если юнит в состоянии Агро
	if not fsm.IsAggressive then return end

	local timer = (fsm.ScanTimer or 0) + dt
	if timer < SCAN_INTERVAL then
		fsm.ScanTimer = timer
		return
	end
	fsm.ScanTimer = 0

	local target = fsm:FindClosestEnemy(SCAN_RADIUS)
	if target then
		fsm:ChangeState("Attacking", target)
	end
end

return Idle
