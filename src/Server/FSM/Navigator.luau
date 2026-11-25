local PathfindingService = game:GetService("PathfindingService")

local Navigator = {}

local AGENT_RADII = { 3.5, 2 } -- сначала с большим запасом от углов, потом для узких проходов
local WAYPOINT_SPACING = 3
local WAYPOINT_REACH = 2        -- меньше, чтобы не срезать углы зданий
local STUCK_CHECK_INTERVAL = 0.5
local STUCK_MIN_DISTANCE = 0.5
local MAX_REPATHS = 2
local MOVETO_REFRESH = 3        -- Humanoid:MoveTo сам отменяется через 8 сек
local PATH_SKIP_SEARCH = 4

local blockParams = RaycastParams.new()
blockParams.FilterType = Enum.RaycastFilterType.Include

local function planarDistSq(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return dx * dx + dz * dz
end

-- Есть ли здание на прямой линии от from к to
local function lineBlocked(from, to)
	local buildings = workspace:FindFirstChild("Buildings")
	if not buildings then return false end
	blockParams.FilterDescendantsInstances = { buildings }
	return workspace:Raycast(from, to - from, blockParams) ~= nil
end

local function begin(fsm, target, usePath, resetStuck)
	local humanoid, root = fsm.Humanoid, fsm.Root

	fsm.NavTarget = target
	fsm.NavUsePath = usePath
	fsm.NavWaypoints = nil
	fsm.NavIndex = 0
	fsm.NavRefresh = 0
	fsm.NavFailed = false
	fsm.NavPending = false
	fsm.PathRequestId = (fsm.PathRequestId or 0) + 1

	if resetStuck then
		fsm.NavStuck = 0
		fsm.NavStuckPos = root and root.Position or Vector3.zero
	end

	if not humanoid or not root then return end

	local startPos = root.Position
	local blocked = usePath and lineBlocked(startPos, target)

	-- Идём сразу по прямой, только если на линии нет здания
	if not blocked then humanoid:MoveTo(target) end
	if not usePath then return end

	local requestId = fsm.PathRequestId
	fsm.NavPending = true

	task.spawn(function()
		local path
		for _, radius in AGENT_RADII do
			local candidate = PathfindingService:CreatePath({
				AgentRadius = radius,
				AgentHeight = 5,
				AgentCanJump = false,
				WaypointSpacing = WAYPOINT_SPACING,
			})
			local ok = pcall(candidate.ComputeAsync, candidate, startPos, target)
			if fsm.PathRequestId ~= requestId then return end -- пришла новая команда
			if ok and candidate.Status == Enum.PathStatus.Success then
				path = candidate
				break
			end
		end

		fsm.NavPending = false

		if not path then
			-- Пути нет: если прямая свободна, юнит уже идёт; иначе сдаёмся, а не лезем в здание
			if blocked then
				fsm.NavFailed = true
				if fsm.Humanoid and fsm.Root then fsm.Humanoid:MoveTo(fsm.Root.Position) end
			end
			return
		end

		local waypoints = path:GetWaypoints()
		local count = #waypoints
		if count < 2 then return end

		local currentRoot = fsm.Root
		if not currentRoot then return end
		local currentPos = currentRoot.Position

		local nearest, nearestSq = 1, math.huge
		for i = 1, math.min(count, PATH_SKIP_SEARCH) do
			local d = planarDistSq(currentPos, waypoints[i].Position)
			if d < nearestSq then nearest, nearestSq = i, d end
		end
		local startIndex = math.min(nearest + 1, count)

		fsm.NavWaypoints = waypoints
		fsm.NavIndex = startIndex
		fsm.NavRefresh = 0
		fsm.NavStuck = 0
		fsm.NavStuckPos = currentPos

		if fsm.Humanoid then fsm.Humanoid:MoveTo(waypoints[startIndex].Position) end
	end)
end

-- usePath=false: идти по прямой (частые drag-команды)
function Navigator.Start(fsm, target, usePath, resetStuck)
	fsm.NavRetries = 0
	begin(fsm, target, usePath, resetStuck)
end

-- Возвращает "arrived", "stuck" или nil (ещё идём)
function Navigator.Step(fsm, dt, finalReach)
	local humanoid, root, target = fsm.Humanoid, fsm.Root, fsm.NavTarget
	if not humanoid or not root or not target then return "stuck" end
	if fsm.NavFailed then return "stuck" end

	local pos = root.Position
	if planarDistSq(pos, target) <= finalReach * finalReach then return "arrived" end

	local waypoints = fsm.NavWaypoints
	if waypoints then
		local index = fsm.NavIndex
		local reach = index == #waypoints and finalReach or WAYPOINT_REACH
		if planarDistSq(pos, waypoints[index].Position) <= reach * reach then
			if index == #waypoints then return "arrived" end
			fsm.NavIndex = index + 1
			fsm.NavRefresh = 0
			humanoid:MoveTo(waypoints[index + 1].Position)
		end
	end

	-- Пока путь считается, юнит может стоять: это не застревание
	if fsm.NavPending then return nil end

	local refresh = fsm.NavRefresh + dt
	if refresh >= MOVETO_REFRESH then
		refresh = 0
		local current = fsm.NavWaypoints
		humanoid:MoveTo(current and current[fsm.NavIndex].Position or target)
	end
	fsm.NavRefresh = refresh

	-- Анти-застревание: пересчитываем путь с текущей позиции, а не прыгаем через угол
	local stuck = fsm.NavStuck + dt
	if stuck >= STUCK_CHECK_INTERVAL then
		stuck = 0
		local moved = (pos - fsm.NavStuckPos).Magnitude
		fsm.NavStuckPos = pos

		if moved < STUCK_MIN_DISTANCE then
			if fsm.NavUsePath and fsm.NavRetries < MAX_REPATHS then
				fsm.NavRetries += 1
				begin(fsm, target, true, false)
				return nil
			end
			return "stuck"
		end
	end
	fsm.NavStuck = stuck
	return nil
end

-- Вызывать в OnExit: отменяет незавершённый расчёт пути
function Navigator.Stop(fsm)
	fsm.PathRequestId = (fsm.PathRequestId or 0) + 1
	fsm.NavWaypoints = nil
	fsm.NavTarget = nil
	fsm.NavPending = false
end

return Navigator