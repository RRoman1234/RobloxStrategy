-- StarterPlayerScripts/FactionInput
-- Клиентская часть фракции: клавиши 1-6 (стройка / создание юнитов) и R (герой).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Registry = require(ReplicatedStorage:WaitForChild("Factions"):WaitForChild("Registry"))
local Notify = require(script.Parent:WaitForChild("Notify"))

local localPlayer = Players.LocalPlayer
local Faction = Registry.Proxy(localPlayer)
local camera = workspace.CurrentCamera
local getSelectedUnits = ReplicatedStorage:WaitForChild("GetSelectedUnitsFunction")
local getSelectedBuildings = ReplicatedStorage:WaitForChild("GetSelectedBuildingsFunction")
local createUnitEvent = ReplicatedStorage:WaitForChild("CreateUnitEvent")
local buildEvent = ReplicatedStorage:WaitForChild("BuildCommandEvent")
local summonHeroEvent = ReplicatedStorage:WaitForChild("SummonHeroEvent")
local sellEvent = ReplicatedStorage:WaitForChild("SellBuildingEvent")
local cancelBuildEvent = ReplicatedStorage:WaitForChild("CancelBuildEvent")
local abilityEvent = ReplicatedStorage:WaitForChild("HeroAbilityEvent")

local GREEN = Color3.fromRGB(60, 255, 80)
local RED = Color3.fromRGB(255, 60, 60)
local RED_HIGHLIGHT = Color3.fromRGB(255, 40, 40)

local KEYS = {} -- KeyCode -> "1".."6" (и цифры на нумпаде)
for i, name in { "One", "Two", "Three", "Four", "Five", "Six" } do
	KEYS[Enum.KeyCode[name]] = tostring(i)
	KEYS[Enum.KeyCode["Keypad" .. name]] = tostring(i)
end

local ghost, gapZone, buildType, buildPoint, canBuild, selling
local clickConsumed = false
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- === КРАСНЫЙ КУРСОР И ПОДСВЕТКА ДЛЯ РЕЖИМА ПРОДАЖИ ===
local cursorGui = Instance.new("ScreenGui")
cursorGui.Name = "SellCursorGui"
cursorGui.IgnoreGuiInset = true
cursorGui.ResetOnSpawn = false
cursorGui.DisplayOrder = 100
cursorGui.Parent = localPlayer:WaitForChild("PlayerGui")

local cursor = Instance.new("Frame")
cursor.AnchorPoint = Vector2.new(0.5, 0.5)
cursor.Size = UDim2.fromOffset(18, 18)
cursor.BackgroundColor3 = RED_HIGHLIGHT
cursor.Visible = false
cursor.Parent = cursorGui
Instance.new("UICorner", cursor).CornerRadius = UDim.new(1, 0)
Instance.new("UIStroke", cursor).Color = Color3.new(1, 1, 1)

local sellHighlight = Instance.new("Highlight")
sellHighlight.Enabled = false -- без цели не подсвечиваем ничего
sellHighlight.FillColor = RED_HIGHLIGHT
sellHighlight.OutlineColor = RED_HIGHLIGHT
sellHighlight.FillTransparency = 0.5
sellHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
sellHighlight.Parent = workspace

-- Своё продаваемое здание под курсором (или nil)
local function sellTarget()
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
	local model = hit and hit.Instance:FindFirstAncestorOfClass("Model")
	local owner = model and model:FindFirstChild("Owner")
	if model and Faction.Buildings[model.Name] and owner and owner.Value == localPlayer.Name
		and model.Parent == workspace:FindFirstChild("Buildings") then
		return model
	end
end

local FactionInput = {}

local function startPlacement(name)
	FactionInput.Cancel()
	buildType = name

	local template = Faction.Template("Buildings", name .. "Template")
	local size = template and template:GetExtentsSize() or Vector3.new(10, 10, 10)

	ghost = Instance.new("Part")
	ghost.Name = "GhostBuilding"
	ghost.Size = size
	ghost.Transparency = 0.5
	ghost.Color = GREEN
	ghost.Material = Enum.Material.SmoothPlastic
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.Parent = workspace

	gapZone = Instance.new("Part")
	gapZone.Name = "GapZoneIndicator"
	gapZone.Size = Vector3.new(size.X + Faction.BuildingGap * 2, 0.05, size.Z + Faction.BuildingGap * 2)
	gapZone.Transparency = 0.8
	gapZone.Color = GREEN
	gapZone.Anchored = true
	gapZone.CanCollide = false
	gapZone.Parent = ghost

	rayParams.FilterDescendantsInstances = { ghost, workspace:FindFirstChild("Units") }
end

-- true, если режим строительства или продажи был активен
function FactionInput.Cancel()
	local was = ghost ~= nil or selling == true
	selling = false
	cursor.Visible = false
	sellHighlight.Adornee = nil
	sellHighlight.Enabled = false
	UserInputService.MouseIconEnabled = true
	if ghost then
		ghost:Destroy()
		ghost, gapZone = nil, nil
	end
	return was
end

function FactionInput.StartSell()
	FactionInput.Cancel()
	selling = true
	cursor.Visible = true
	UserInputService.MouseIconEnabled = false
	rayParams.FilterDescendantsInstances = { workspace:FindFirstChild("Units") }
end

-- true один раз, если ЛКМ только что ушёл на стройку/продажу (выделение трогать не нужно)
function FactionInput.ConsumeClick()
	local was = clickConsumed
	clickConsumed = false
	return was
end

-- ЛКМ: ставим здание или продаём. true, если клик поглощён этими режимами.
function FactionInput.TryPlace()
	if selling then
		clickConsumed = true
		local target = sellTarget()
		FactionInput.Cancel()
		if target then sellEvent:FireServer(getSelectedUnits:Invoke(), target) end
		return true
	end

	if not ghost then return false end
	clickConsumed = true
	if canBuild and buildPoint then
		local pos, kind = buildPoint, buildType
		FactionInput.Cancel()
		buildEvent:FireServer(getSelectedUnits:Invoke(), pos, kind)
	else
		Notify.Show("Здесь нельзя строить: мало места")
	end
	return true
end

-- Каждый кадр: двигаем призрак здания / красный курсор за мышью
function FactionInput.Update()
	if selling then
		local mouse = UserInputService:GetMouseLocation()
		cursor.Position = UDim2.fromOffset(mouse.X, mouse.Y)
		local target = sellTarget()
		sellHighlight.Adornee = target
		sellHighlight.Enabled = target ~= nil
		return
	end

	if not ghost then return end

	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
	if not hit then return end

	buildPoint = hit.Position
	ghost.Position = buildPoint + Vector3.new(0, ghost.Size.Y / 2, 0)
	gapZone.Position = buildPoint + Vector3.new(0, 0.04, 0)

	canBuild = Faction.CanPlace(buildPoint, ghost.Size)
	local color = canBuild and GREEN or RED
	ghost.Color = color
	gapZone.Color = color
end

-- Призыв героя у Нексуса (условия проверяет сервер и сообщает через NotifyEvent)
function FactionInput.SummonHero()
	summonHeroEvent:FireServer()
end

-- Способность героя: работает, только если герой выделен
function FactionInput.UseAbility(key)
	local units = getSelectedUnits:Invoke()
	for _, u in units do
		if u.Name == "Hero" then
			abilityEvent:FireServer(units, key)
			return
		end
	end
end

-- key: "1".."6". Общая логика для клавиши и для кнопки панели
function FactionInput.Press(key)
	local units = getSelectedUnits:Invoke()
	if #units > 0 and units[1]:GetAttribute("Constructing") then return end
	if #units > 0 and Faction.Workers[units[1].Name] then
		local name = Faction.BuildingByKey[key]
		if name then startPlacement(name) end
		return
	end

	-- Выделены здания: клавиша создаёт юнита
	for _, building in getSelectedBuildings:Invoke() do
		local root = building.PrimaryPart
		local production = Faction.Production[building.Name]
		local unitName = root and production and production[key]
		if unitName then
			createUnitEvent:FireServer(building, root.Position + Vector3.new(5, 0, 0), unitName)
		end
	end
end

-- Отмена режима размещения и стройки у выделенных рабочих
function FactionInput.CancelBuild()
	FactionInput.Cancel()
	cancelBuildEvent:FireServer(getSelectedUnits:Invoke())
end

function FactionInput.HandleKey(input)
	if input.KeyCode == Enum.KeyCode.R then
		FactionInput.SummonHero()
		return
	end

	if input.KeyCode == Enum.KeyCode.X then
		local units = getSelectedUnits:Invoke()
		if #units > 0 and Faction.Workers[units[1].Name] then
			FactionInput.StartSell()
		end
		return
	end

	if input.KeyCode == Enum.KeyCode.C then
		FactionInput.CancelBuild()
		return
	end

	if Faction.Hero.Abilities[input.KeyCode.Name] then
		FactionInput.UseAbility(input.KeyCode.Name)
		return
	end

	local key = KEYS[input.KeyCode]
	if key then FactionInput.Press(key) end
end

return FactionInput