local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local playerGui = localPlayer:WaitForChild("PlayerGui")

-- Создаем интерфейс на клиенте
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ResourceGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Контейнер для выравнивания в правом верхнем углу
local container = Instance.new("Frame")
container.Name = "ResourceContainer"
container.Size = UDim2.new(0, 160, 0, 100)
container.Position = UDim2.new(1, -185, 0, 25) -- Правый верхний угол (отступ 185 пикселей от правого края)
container.BackgroundTransparency = 1
container.Parent = screenGui

-- === ТЕКСТ ЗОЛОТА ===
local goldLabel = Instance.new("TextLabel")
goldLabel.Name = "GoldText"
goldLabel.Size = UDim2.new(1, 0, 0, 45)
goldLabel.Position = UDim2.new(0, 0, 0, 0)
goldLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
goldLabel.BackgroundTransparency = 0.2
goldLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
goldLabel.TextSize = 22
goldLabel.Font = Enum.Font.SourceSansBold
goldLabel.Text = "💰 ..."
goldLabel.Parent = container

local uiCorner1 = Instance.new("UICorner")
uiCorner1.CornerRadius = UDim.new(0, 8)
uiCorner1.Parent = goldLabel

local uiStroke1 = Instance.new("UIStroke")
uiStroke1.Color = Color3.fromRGB(255, 215, 0)
uiStroke1.Parent = goldLabel

-- === ТЕКСТ ЛИМИТА ВОЙСК ===
local limitLabel = Instance.new("TextLabel")
limitLabel.Name = "LimitText"
limitLabel.Size = UDim2.new(1, 0, 0, 45)
limitLabel.Position = UDim2.new(0, 0, 0, 55) -- Располагается под золотом
limitLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
limitLabel.BackgroundTransparency = 0.2
limitLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
limitLabel.TextSize = 22
limitLabel.Font = Enum.Font.SourceSansBold
limitLabel.Text = "⚔️ 0/0"
limitLabel.Parent = container

local uiCorner2 = Instance.new("UICorner")
uiCorner2.CornerRadius = UDim.new(0, 8)
uiCorner2.Parent = limitLabel

local uiStroke2 = Instance.new("UIStroke")
uiStroke2.Color = Color3.fromRGB(255, 100, 100)
uiStroke2.Parent = limitLabel

-- === ЛОГИКА ОБНОВЛЕНИЯ ===
local leaderstats = localPlayer:WaitForChild("leaderstats")
local gold = leaderstats:WaitForChild("Gold")
local militaryCount = leaderstats:WaitForChild("MilitaryCount")
local militaryLimit = leaderstats:WaitForChild("MilitaryLimit")

local function updateGoldDisplay()
	goldLabel.Text = "💰 " .. tostring(gold.Value)
end

local function updateLimitDisplay()
	limitLabel.Text = "⚔️ " .. tostring(militaryCount.Value) .. "/" .. tostring(militaryLimit.Value)
end

gold.Changed:Connect(updateGoldDisplay)
militaryCount.Changed:Connect(updateLimitDisplay)
militaryLimit.Changed:Connect(updateLimitDisplay)

updateGoldDisplay()
updateLimitDisplay()
-- === КАЗНА КОРОЛЕВСТВА ===
local treasuryLabel = limitLabel:Clone()
treasuryLabel.Name = "TreasuryText"
treasuryLabel.Position = UDim2.new(0, 0, 0, 110)
treasuryLabel.TextColor3 = Color3.fromRGB(120, 200, 255)
treasuryLabel.Visible = false
treasuryLabel.Parent = container

local function updateTreasuryDisplay()
	treasuryLabel.Visible = localPlayer:GetAttribute("Faction") == "Kingdom"
	treasuryLabel.Text = "🏦 " .. math.floor(localPlayer:GetAttribute("Treasury") or 0)
		.. "/" .. math.floor(localPlayer:GetAttribute("TreasuryCap") or 0)
end

for _, attr in { "Faction", "Treasury", "TreasuryCap" } do
	localPlayer:GetAttributeChangedSignal(attr):Connect(updateTreasuryDisplay)
end
updateTreasuryDisplay()
