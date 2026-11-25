-- StarterPlayerScripts/HeroEffects
-- Визуал героев целиком на клиенте (не влияет на хитбоксы и выделение):
--  Жрецы: кольцо ауры (цвет = текущий обет) вокруг Первосвященника и Херувимов + подпись «Благодать N / Обет».
--  Волшебники: шары вокруг Архимага, по цвету и количеству = уровни эффектов поглощённых юнитов.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Registry = require(ReplicatedStorage:WaitForChild("Factions"):WaitForChild("Registry"))

local unitsFolder = workspace:WaitForChild("Units")
local fxFolder = Instance.new("Folder")
fxFolder.Name = "HeroEffects"
fxFolder.Parent = workspace

local ORB_RADIUS = 3.5
local MAX_LEVEL = 5

local tracked = {} -- [model] = { faction, ring, drop, label, orbs, sig }

local function newPart(shape, size, transparency)
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.Material = Enum.Material.Neon
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- лучи выделения и команд проходят сквозь эффекты
	part.CanTouch = false
	part.CastShadow = false
	return part
end

local function clear(e)
	if e.ring then e.ring:Destroy() end
	for _, orb in e.orbs do orb:Destroy() end
end

local function getLabel(model, root, e)
	if e.label then return e.label end

	local gui = Instance.new("BillboardGui")
	gui.Name = "HeroInfo" -- лежит в корне модели: туман войны скрывает его вместе с героем
	gui.Size = UDim2.fromOffset(220, 46)
	gui.StudsOffset = Vector3.new(0, 7, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = root

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextSize = 18
	label.Font = Enum.Font.SourceSansBold
	label.TextStrokeTransparency = 0.4
	label.Parent = gui

	gui.Parent = root
	e.label = label
	return label
end

local function updateAura(model, root, e, t, visible)
	local aura = e.faction.Hero.Aura
	local radius = model:GetAttribute("AuraRadius")

	if not (aura and radius and visible) then
		if e.ring then e.ring.Parent = nil end
		if e.label then e.label.Parent.Enabled = false end
		return
	end

	local vow = model:GetAttribute("AuraVow")
	local vowDef = vow and e.faction.Hero.Vow[vow]
	local color = vowDef and vowDef.Color or aura.Color

	if not e.ring then
		local cf, size = model:GetBoundingBox()
		e.drop = root.Position.Y - (cf.Y - size.Y / 2) - 0.1 -- высота корня над землёй
		e.ring = newPart(Enum.PartType.Cylinder, Vector3.new(0.2, 1, 1), 0.8)
	end

	local ring = e.ring
	ring.Color = color
	ring.Size = Vector3.new(0.2, radius * 2, radius * 2)
	ring.Transparency = 0.82 + 0.06 * math.sin(t * 3)
	ring.CFrame = CFrame.new(root.Position.X, root.Position.Y - e.drop, root.Position.Z) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = fxFolder

	if model.Name == "Hero" then
		local label = getLabel(model, root, e)
		local text = `Благодать {model:GetAttribute("AuraLevel") or 1}`
		if vowDef then
			local left = math.max(0, math.ceil((model:GetAttribute("VowEnd") or 0) - workspace:GetServerTimeNow()))
			text ..= `\nОбет: {vowDef.Title} {left}с`
		end
		label.Text = text
		label.TextColor3 = color
		label.Parent.Enabled = true
	end
end

local function updateOrbs(model, root, e, t, visible)
	local absorb = e.faction.Hero.Absorb
	if not absorb then return end

	if not e.names then
		e.names = {}
		for name in absorb.Effects do table.insert(e.names, name) end
		table.sort(e.names)
	end

	local levels, parts = {}, {}
	for i, name in e.names do
		local count = model:GetAttribute("Abs_" .. name) or 0
		levels[name] = math.min(count // absorb.Step, MAX_LEVEL)
		parts[i] = levels[name]
	end

	-- Шары пересоздаём только когда поменялись уровни эффектов
	local sig = table.concat(parts, ",")
	if sig ~= e.sig then
		e.sig = sig
		for _, orb in e.orbs do orb:Destroy() end
		table.clear(e.orbs)

		for _, name in e.names do
			for _ = 1, levels[name] do
				local orb = newPart(Enum.PartType.Ball, Vector3.new(0.7, 0.7, 0.7), 0.1)
				orb.Color = absorb.Colors[name]
				orb.Parent = fxFolder
				table.insert(e.orbs, orb)
			end
		end
	end

	local n = #e.orbs
	for i, orb in e.orbs do
		local a = t * 1.2 + (i / n) * math.pi * 2
		orb.Position = root.Position + Vector3.new(
			math.cos(a) * ORB_RADIUS,
			1 + math.sin(t * 2 + i) * 0.4,
			math.sin(a) * ORB_RADIUS
		)
		orb.Transparency = visible and 0.1 or 1
	end
end

local function track(model)
	if model.Name == "Hero" or model.Name == "Cherub" then
		tracked[model] = { orbs = {} }
	end
end

unitsFolder.ChildAdded:Connect(track)
for _, model in unitsFolder:GetChildren() do track(model) end

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for model, e in tracked do
		if not model.Parent then
			clear(e)
			tracked[model] = nil
			continue
		end

		local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if not root then continue end

		e.faction = e.faction or Registry.OfUnit(model)
		local visible = root.LocalTransparencyModifier < 1 -- герой не в тумане войны
		updateAura(model, root, e, t, visible)
		if model.Name == "Hero" then updateOrbs(model, root, e, t, visible) end
	end
end)
