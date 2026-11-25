local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Registry = require(ReplicatedStorage:WaitForChild("Factions"):WaitForChild("Registry"))
local Navigator = require(script.Parent.Parent:WaitForChild("Navigator"))

local Constructing = {}

local REACH_DISTANCE = 4
local MOVETO_REFRESH = 3        -- Humanoid:MoveTo сам отменяется через 8 сек
local BAR_UPDATE_INTERVAL = 0.1 -- свойства GUI на сервере реплицируются, поэтому не обновляем их каждый кадр

local function createSite(fsm)
	-- Размер площадки = размер строящегося здания (раньше всегда брался размер барака)
	local template = Registry.OfUnit(fsm.Unit).Template("Buildings", fsm.BuildingTypeToBuild .. "Template")
	local size = template and select(2, template:GetBoundingBox()) or Vector3.new(10, 10, 10)

	local site = Instance.new("Part")
	site.Name = "ConstructionSite"
	site.Size = Vector3.new(size.X, 1, size.Z)
	site.Position = fsm.BuildTarget + Vector3.new(0, 0.5, 0)
	site.Anchored = true
	site.CanCollide = false
	site.CanQuery = false
	site.Transparency = 0.5
	site.Color = Color3.fromRGB(150, 150, 150)

	local bg = Instance.new("BillboardGui")
	bg.Size = UDim2.new(4, 0, 0.5, 0)
	bg.StudsOffset = Vector3.new(0, 4, 0)
	bg.AlwaysOnTop = true
	bg.Parent = site

	local bgFrame = Instance.new("Frame")
	bgFrame.Size = UDim2.fromScale(1, 1)
	bgFrame.BackgroundColor3 = Color3.new(0, 0, 0)
	bgFrame.Parent = bg

	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(0, 1)
	bar.BackgroundColor3 = Color3.new(1, 1, 0)
	bar.BorderSizePixel = 0
	bar.Parent = bgFrame

	site.Parent = workspace -- родитель в конце: всё реплицируется одним пакетом
	fsm.Site = site
	fsm.UIBar = bar
end

local function destroySite(fsm)
	if fsm.Site then
		fsm.Site:Destroy()
		fsm.Site = nil
	end
	fsm.UIBar = nil
end

-- onCancel вызывается, если стройка прервана до завершения (возврат золота)
function Constructing.OnEnter(fsm, unit, targetPos, buildingType, onCancel)
	unit:SetAttribute("Constructing", true) -- клиент по нему решает, показывать ли кнопку отмены
	fsm:SetCollisionMode("Ghost")
	fsm.BuildingTypeToBuild = buildingType or "Barracks"
	local faction = Registry.OfUnit(unit)
	local def = faction.Buildings[fsm.BuildingTypeToBuild]
	fsm.BuildDuration = def and def.BuildTime or faction.BuildTime

	fsm.BuildTarget = targetPos
	fsm.HasReached = false
	fsm.BuildTimer = 0
	fsm.BarTimer = 0
	fsm.MoveRefreshTimer = 0
	fsm.BuildCompleted = false
	fsm.BuildCancelCallback = onCancel

	Navigator.Start(fsm, targetPos, true, true)
	fsm:PlayAnimation("Walk")
end

function Constructing.OnUpdate(fsm, unit, dt)
	local root = fsm.Root
	if not root or not fsm.BuildTarget then return end

	if not fsm.HasReached then
		local result = Navigator.Step(fsm, dt, REACH_DISTANCE)
		if result == "arrived" then
			fsm.HasReached = true
			fsm:SetCollisionMode("Solid")
			Navigator.Stop(fsm)

			local humanoid = fsm.Humanoid
			if humanoid then humanoid:MoveTo(root.Position) end
			fsm:PlayAnimation("AttackNO")
			createSite(fsm)
		elseif result == "stuck" then
			fsm:ChangeState("Idle") -- OnExit вернёт золото
		end
		return
	end

	local timer = fsm.BuildTimer + dt
	fsm.BuildTimer = timer

	local bar = fsm.UIBar
	if bar then
		fsm.BarTimer += dt
		if fsm.BarTimer >= BAR_UPDATE_INTERVAL then
			fsm.BarTimer = 0
			bar.Size = UDim2.fromScale(math.clamp(timer / fsm.BuildDuration, 0, 1), 1)
		end
	end

	if timer >= fsm.BuildDuration then
		fsm.BuildCompleted = true
		destroySite(fsm)

		local bindable = ReplicatedStorage:FindFirstChild("SpawnBuildingBindable")
		if bindable then
			bindable:Fire(unit, fsm.BuildTarget, fsm.BuildingTypeToBuild)
		end

		fsm:ChangeState("Idle")
	end
end

function Constructing.OnExit(fsm)
	if fsm.Unit then fsm.Unit:SetAttribute("Constructing", nil) end
	Navigator.Stop(fsm)
	fsm:SetCollisionMode("Solid")
	destroySite(fsm)

	local callback = fsm.BuildCancelCallback
	fsm.BuildCancelCallback = nil
	if callback and not fsm.BuildCompleted then pcall(callback) end
	fsm.BuildTarget = nil

	-- Возврат добытчика на место добычи
	if fsm.Unit and fsm.Unit.Name == "Miner" then
		local homePos = fsm.Unit:FindFirstChild("HomePosition")
		if homePos then
			task.defer(function()
				fsm:ChangeState("Moving", homePos.Value, false)
			end)
		end
	end
end

return Constructing
