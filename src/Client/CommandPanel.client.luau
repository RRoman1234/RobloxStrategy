local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Registry = require(ReplicatedStorage:WaitForChild("Factions"):WaitForChild("Registry"))
local FactionInput = require(script.Parent:WaitForChild("FactionInput"))
local Faction = Registry.Proxy(Players.LocalPlayer)
local getSelectedUnits = ReplicatedStorage:WaitForChild("GetSelectedUnitsFunction")
local getSelectedBuildings = ReplicatedStorage:WaitForChild("GetSelectedBuildingsFunction")

local PANEL_SIZE = 350
local PADDING = 8
local GAP = 6

local REFRESH = 0.1

-- === ИНТЕРФЕЙС: квадрат справа внизу ===
local gui = Instance.new("ScreenGui")
gui.Name = "CommandPanelGui"
gui.ResetOnSpawn = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.new(1, -10, 1, -10)
panel.Size = UDim2.fromOffset(PANEL_SIZE, PANEL_SIZE)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
panel.BackgroundTransparency = 0.2
panel.Visible = false
panel.Parent = gui

Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
Instance.new("UIStroke", panel).Color = Color3.fromRGB(255, 215, 0)
Instance.new("UIPadding", panel).PaddingTop = UDim.new(0, 8)

local pad = panel:FindFirstChildOfClass("UIPadding")
pad.PaddingLeft, pad.PaddingRight, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8)

local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0.5, -3, 0, 42)
grid.CellPadding = UDim2.fromOffset(6, 6)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = panel

-- === ДАННЫЕ: какие кнопки нужны для текущего выделения ===
local function alive(list)
	local out = {}
	for _, e in list do
		if e.Parent then table.insert(out, e) end
	end
	return out
end

local function unitCost(def, name)
	if def.Cost then return def.Cost end
	local template = Faction.Template("Units", name)
	local tag = template and template:FindFirstChild("Cost")
	return tag and tag.Value or Faction.DefaultCost
end

-- Цена улучшения ауры жрецов прямо на кнопке [F]
local function abilityExtra(key)
	local hero = Faction.Hero
	if hero.Aura then
		if key ~= "F" then return "" end
		local cost = hero.Aura.UpgradeCost[Players.LocalPlayer:GetAttribute("AuraLevel") or 1]
		return cost and `\n{cost}💰` or "\nМакс."
	end
	if hero.Treasury then -- Королевство: цены способностей на кнопках
		if key == "Q" then return `\n{hero.Treasury.DepositStep}💰` end
		if key == "F" then return `\n{hero.Dubbing.Cost}💰 за рыцаря` end
		if key == "G" then return `\n{hero.Hire.Cost}💰` end
	end
	return ""
end

local function collect()
	local entries = {}
	local units = alive(getSelectedUnits:Invoke())

	if #units > 0 and Faction.Workers[units[1].Name] then
		-- Рабочий строит или идёт строить: показываем только «Отменить»
		for _, u in units do
			if u:GetAttribute("Constructing") then
				return { { key = "C", text = "[C] Отменить", press = FactionInput.CancelBuild } }
			end
		end

		for name, b in Faction.Buildings do
			table.insert(entries, {
				key = b.Key,
				text = `[{b.Key}] {b.Title or name}\n{b.Cost}💰`,
				press = function() FactionInput.Press(b.Key) end,
			})
		end
		table.insert(entries, { key = "X", text = "[X] Продать здание", press = FactionInput.StartSell })
	else
		-- Герой выделен: показываем его способности
		for _, u in units do
			if u.Name == "Hero" then
				for key, title in Faction.Hero.Abilities do
					table.insert(entries, {
						key = key,
						text = `[{key}] {title}{abilityExtra(key)}`,
						press = function() FactionInput.UseAbility(key) end,
					})
				end
				break
			end
		end

		local seen = {}
		for _, building in alive(getSelectedBuildings:Invoke()) do
			if seen[building.Name] then continue end
			seen[building.Name] = true

			if Faction.Bases[building.Name] then
				table.insert(entries, {
					key = "R",
					text = `[R] {Faction.Hero.Title}\n{Faction.Hero.Cost}💰`,
					press = FactionInput.SummonHero,
				})
			end

			for key, unitName in Faction.Production[building.Name] or {} do
				table.insert(entries, {
					key = key,
					text = `[{key}] {Faction.Units[unitName].Title or unitName}\n{unitCost(Faction.Units[unitName], unitName)}💰`,
					press = function() FactionInput.Press(key) end,
				})
			end
		end
	end

	table.sort(entries, function(a, b) return a.key < b.key end)
	return entries
end

-- === ОБНОВЛЕНИЕ: перестраиваем кнопки только при смене набора ===
-- === ПАНЕЛЬ ПОГЛОЩЁННЫХ (Волшебники): над основной панелью, только когда выбран герой ===
local EFFECT_TEXT = {
	DamageMult = function(v) return `урон +{math.round((v - 1) * 100)}%` end,
	DamageTaken = function(v) return `входящий урон -{math.round((1 - v) * 100)}%` end,
	AoERadius = function(v) return `радиус AoE {v}` end,
	AoEShare = function(v) return `AoE {math.round(v * 100)}% урона` end,
	SpeedMult = function(v) return `скорость +{math.round((v - 1) * 100)}%` end,
	AttackSpeedMult = function(v) return `атака +{math.round((v - 1) * 100)}%` end,
	Lifesteal = function(v) return `вампиризм {math.round(v * 100)}%` end,
}

local absPanel = Instance.new("Frame")
absPanel.AnchorPoint = Vector2.new(1, 1)
absPanel.Position = UDim2.new(1, -10, 1, -(PANEL_SIZE + 18))
absPanel.Size = UDim2.fromOffset(PANEL_SIZE, 0)
absPanel.AutomaticSize = Enum.AutomaticSize.Y
absPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
absPanel.BackgroundTransparency = 0.2
absPanel.Visible = false
absPanel.Parent = gui
Instance.new("UICorner", absPanel).CornerRadius = UDim.new(0, 8)
Instance.new("UIStroke", absPanel).Color = Color3.fromRGB(255, 215, 0)

local absPad = Instance.new("UIPadding", absPanel)
absPad.PaddingTop, absPad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
absPad.PaddingLeft, absPad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)

local absList = Instance.new("UIListLayout", absPanel)
absList.SortOrder = Enum.SortOrder.LayoutOrder
absList.Padding = UDim.new(0, 4)

local absSignature = ""

local function addAbsRow(order, text, color)
	local row = Instance.new("TextLabel")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.BackgroundTransparency = 1
	row.TextWrapped = true
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextSize = 16
	row.Font = Enum.Font.SourceSansBold
	row.TextColor3 = color
	row.Text = text
	row.Parent = absPanel
end

-- Перестраиваем строки только когда поменялись счётчики Abs_<тип> на выделенном герое
local function updateAbsorbPanel()
	local hero
	for _, u in alive(getSelectedUnits:Invoke()) do
		if u.Name == "Hero" then hero = u break end
	end

	local absorb = hero and Faction.Hero.Absorb
	if not absorb then
		absPanel.Visible = false
		absSignature = ""
		return
	end

	local names = {}
	for name in absorb.Effects do table.insert(names, name) end
	table.sort(names, function(a, b) return Faction.Units[a].Key < Faction.Units[b].Key end)

	local counts, parts, total = {}, {}, 0
	for i, name in names do
		counts[name] = hero:GetAttribute("Abs_" .. name) or 0
		parts[i] = counts[name]
		total += counts[name]
	end

	local signature = table.concat(parts, ",")
	if signature == absSignature and absPanel.Visible then return end
	absSignature = signature

	for _, child in absPanel:GetChildren() do
		if child:IsA("TextLabel") then child:Destroy() end
	end

	addAbsRow(0, `Поглощено {total}/{absorb.Capacity}`, Color3.fromRGB(255, 215, 0))
	if total == 0 then
		addAbsRow(1, "Выделите юнитов рядом с героем и нажмите [Q]", Color3.fromRGB(180, 180, 180))
	end

	for i, name in names do
		local count = counts[name]
		if count > 0 then
			local level = math.min(count // absorb.Step, 5)
			local text = `{Faction.Units[name].Title} {count}`
			if level == 0 then
				text ..= ` (до эффекта ещё {absorb.Step - count})`
			else
				local effects = {}
				for attr, values in absorb.Effects[name] do
					table.insert(effects, EFFECT_TEXT[attr](values[math.min(level, #values)]))
				end
				table.sort(effects)
				text ..= ` · ур. {level}: {table.concat(effects, ", ")}`
			end
			addAbsRow(i, text, absorb.Colors[name])
		end
	end

	absPanel.Visible = true
end

-- === ПАНЕЛЬ ОБЕТОВ (Жрецы): над основной панелью, только когда выбран герой ===
local GREY, GREEN_TEXT, RED_TEXT = Color3.fromRGB(180, 180, 180), Color3.fromRGB(110, 255, 130), Color3.fromRGB(255, 120, 110)

local vowPanel = Instance.new("Frame")
vowPanel.AnchorPoint = Vector2.new(1, 1)
vowPanel.Position = UDim2.new(1, -10, 1, -(PANEL_SIZE + 18))
vowPanel.Size = UDim2.fromOffset(PANEL_SIZE, 0)
vowPanel.AutomaticSize = Enum.AutomaticSize.Y
vowPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
vowPanel.BackgroundTransparency = 0.2
vowPanel.Visible = false
vowPanel.Parent = gui
Instance.new("UICorner", vowPanel).CornerRadius = UDim.new(0, 8)
Instance.new("UIStroke", vowPanel).Color = Color3.fromRGB(255, 215, 0)

local vowPad = Instance.new("UIPadding", vowPanel)
vowPad.PaddingTop, vowPad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
vowPad.PaddingLeft, vowPad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)

local vowList = Instance.new("UIListLayout", vowPanel)
vowList.SortOrder = Enum.SortOrder.LayoutOrder
vowList.Padding = UDim.new(0, 4)

local function makeVowRow(order)
	local row = Instance.new("TextLabel")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.BackgroundTransparency = 1
	row.TextWrapped = true
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextSize = 16
	row.Font = Enum.Font.SourceSansBold
	row.Parent = vowPanel
	return row
end

local auraRow, vowRow, cooldownRow = makeVowRow(0), makeVowRow(1), makeVowRow(2)

-- Три строки создаются один раз, здесь только обновляется текст (таймеры идут каждую секунду)
local function updateVowPanel()
	local hero
	for _, u in alive(getSelectedUnits:Invoke()) do
		if u.Name == "Hero" then hero = u break end
	end

	local vows = hero and Faction.Hero.Vow
	if not vows then
		vowPanel.Visible = false
		return
	end

	local aura = Faction.Hero.Aura
	local level = Players.LocalPlayer:GetAttribute("AuraLevel") or 1
	local cost = aura.UpgradeCost[level]
	auraRow.Text = `Благодать {level}/{#aura.Levels}, радиус {aura.Levels[level].Radius}`
		.. (cost and `\nУлучшение [F]: {cost}💰` or "\nМаксимальный уровень")
	auraRow.TextColor3 = Color3.fromRGB(255, 215, 0)

	local now = workspace:GetServerTimeNow()
	local active = hero:GetAttribute("AuraVow")
	local left = math.ceil((hero:GetAttribute("VowEnd") or 0) - now)
	if active and left > 0 then
		vowRow.Text = `Активен: {vows[active].Title} {left}с`
		vowRow.TextColor3 = vows[active].Color
	else
		vowRow.Text = "Обет не активен"
		vowRow.TextColor3 = GREY
	end

	local cooldown = math.ceil((hero:GetAttribute("VowReadyEnd") or 0) - now)
	if cooldown > 0 then
		cooldownRow.Text = `Перезарядка обетов [Q] [E]: {cooldown}с`
		cooldownRow.TextColor3 = RED_TEXT
	else
		cooldownRow.Text = "Обеты готовы [Q] [E]"
		cooldownRow.TextColor3 = GREEN_TEXT
	end

	vowPanel.Visible = true
end

-- === ПАНЕЛЬ КОРОЛЕВСТВА: казна, цены и перезарядки, только когда выбрана Королева ===
local kingPanel = Instance.new("Frame")
kingPanel.AnchorPoint = Vector2.new(1, 1)
kingPanel.Position = UDim2.new(1, -10, 1, -(PANEL_SIZE + 18))
kingPanel.Size = UDim2.fromOffset(PANEL_SIZE, 0)
kingPanel.AutomaticSize = Enum.AutomaticSize.Y
kingPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
kingPanel.BackgroundTransparency = 0.2
kingPanel.Visible = false
kingPanel.Parent = gui
Instance.new("UICorner", kingPanel).CornerRadius = UDim.new(0, 8)
Instance.new("UIStroke", kingPanel).Color = Color3.fromRGB(255, 215, 0)

local kingPad = Instance.new("UIPadding", kingPanel)
kingPad.PaddingTop, kingPad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
kingPad.PaddingLeft, kingPad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)

local kingList = Instance.new("UIListLayout", kingPanel)
kingList.SortOrder = Enum.SortOrder.LayoutOrder
kingList.Padding = UDim.new(0, 4)

local function makeKingRow(order)
	local row = Instance.new("TextLabel")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.BackgroundTransparency = 1
	row.TextWrapped = true
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextSize = 16
	row.Font = Enum.Font.SourceSansBold
	row.Parent = kingPanel
	return row
end

local kingRows = { makeKingRow(0), makeKingRow(1), makeKingRow(2), makeKingRow(3) }

-- Секунд до конца перезарядки (endTime в серверном времени); 0 = готово
local function secondsLeft(endTime)
	return math.max(0, math.ceil((endTime or 0) - workspace:GetServerTimeNow()))
end

local function setKingRow(row, text, ready)
	row.Text = text
	row.TextColor3 = ready and GREEN_TEXT or RED_TEXT
end

local function updateKingPanel()
	local hero
	for _, u in alive(getSelectedUnits:Invoke()) do
		if u.Name == "Hero" then hero = u break end
	end

	local T = hero and Faction.Hero.Treasury
	if not T then
		kingPanel.Visible = false
		return
	end

	local me, dub, hire = Players.LocalPlayer, Faction.Hero.Dubbing, Faction.Hero.Hire
	local amount = math.floor(me:GetAttribute("Treasury") or 0)
	local cap = math.floor(me:GetAttribute("TreasuryCap") or 0)

	kingRows[1].Text = `Казна {amount}/{cap}, +{math.round(T.Rate * 100)}% в минуту\n[Q] вклад по {T.DepositStep}💰`
	kingRows[1].TextColor3 = Color3.fromRGB(255, 215, 0)

	local lock = secondsLeft(me:GetAttribute("LockEnd"))
	if amount > 0 and lock > 0 then
		setKingRow(kingRows[2], `[E] Забрать: штраф {math.round(T.EarlyLoss * 100)}% ещё {lock}с`, false)
	else
		setKingRow(kingRows[2], "[E] Забрать: без потерь", true)
	end

	local dubLeft = secondsLeft(me:GetAttribute("DubReadyEnd"))
	setKingRow(kingRows[3],
		`[F] Посвящение: {dub.Cost}💰 за рыцаря, до {dub.Max} шт.\n` .. (dubLeft > 0 and `перезарядка {dubLeft}с` or "готово"),
		dubLeft == 0)

	local hireLeft = secondsLeft(me:GetAttribute("HireReadyEnd"))
	setKingRow(kingRows[4],
		`[G] Наём: {hire.Cost}💰, {hire.Count} рыцаря на {hire.Duration}с\n` .. (hireLeft > 0 and `перезарядка {hireLeft}с` or "готово"),
		hireLeft == 0)

	kingPanel.Visible = true
end

local lastSignature = ""

local function rebuild(entries)
	for _, child in panel:GetChildren() do
		if child:IsA("TextButton") then child:Destroy() end
	end

	local n = #entries
	if n > 0 then
		local cols = math.ceil(math.sqrt(n))
		local rows = math.ceil(n / cols)
		local inner = PANEL_SIZE - PADDING * 2
		grid.CellSize = UDim2.fromOffset(
			math.floor((inner - GAP * (cols - 1)) / cols),
			math.floor((inner - GAP * (rows - 1)) / rows)
		)
	end

	for i, e in entries do
		local btn = Instance.new("TextButton")
		btn.LayoutOrder = i
		btn.Text = e.text
		btn.TextWrapped = true
		btn.TextSize = 18
		btn.Font = Enum.Font.SourceSansBold
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
		btn.Activated:Connect(e.press)
		btn.Parent = panel
	end

	panel.Visible = n > 0
end

while true do
	updateAbsorbPanel()
	updateVowPanel()
	updateKingPanel()
	local entries = collect()
	local parts = table.create(#entries)
	for i, e in entries do parts[i] = e.text end

	local signature = table.concat(parts, "|")
	if signature ~= lastSignature then
		lastSignature = signature
		rebuild(entries)
	end

	task.wait(REFRESH)
end