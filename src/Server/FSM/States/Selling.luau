local Navigator = require(script.Parent.Parent:WaitForChild("Navigator"))

local Selling = {}

local EDGE_MARGIN = 5   -- на сколько стадов от стены здания юнит останавливается
local ARRIVE_REACH = 2.5

-- Ближайшая к рабочему точка рядом со зданием (снаружи его габаритов)
local function edgePoint(building, from)
	local cf, size = building:GetBoundingBox()
	local half = size / 2
	local l = cf:PointToObjectSpace(from)
	local x = math.clamp(l.X, -half.X - EDGE_MARGIN, half.X + EDGE_MARGIN)
	local z = math.clamp(l.Z, -half.Z - EDGE_MARGIN, half.Z + EDGE_MARGIN)
	local world = cf:PointToWorldSpace(Vector3.new(x, 0, z))
	return Vector3.new(world.X, from.Y, world.Z)
end

-- onArrive вызывается, когда рабочий дошёл до здания
function Selling.OnEnter(fsm, unit, building, onArrive)
	fsm:SetCollisionMode("Ghost")
	fsm.SellBuilding = building
	fsm.SellCallback = onArrive

	local root = fsm.Root
	if root then Navigator.Start(fsm, edgePoint(building, root.Position), true, true) end
	fsm:PlayAnimation("Walk")
end

function Selling.OnUpdate(fsm, unit, dt)
	local building = fsm.SellBuilding
	if not building or not building.Parent then
		fsm:ChangeState("Idle") -- здание уже продано или разрушено
		return
	end

	local result = Navigator.Step(fsm, dt, ARRIVE_REACH)
	if result == "arrived" then
		local callback = fsm.SellCallback
		fsm.SellCallback = nil
		fsm:ChangeState("Idle")
		if callback then callback() end
	elseif result == "stuck" then
		fsm:ChangeState("Idle")
	end
end

function Selling.OnExit(fsm, unit, nextState)
	Navigator.Stop(fsm)
	fsm:SetCollisionMode("Solid")
	fsm.SellBuilding = nil
	fsm.SellCallback = nil

	-- После продажи добытчик возвращается на место добычи
	if nextState == "Idle" and fsm.Unit.Name == "Miner" then
		local homePos = fsm.Unit:FindFirstChild("HomePosition")
		if homePos then
			task.defer(function()
				if fsm.CurrentState == "Idle" then fsm:ChangeState("Moving", homePos.Value, false) end
			end)
		end
	end
end

return Selling