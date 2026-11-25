-- StarterPlayerScripts/FactionSelect
-- ЗАГЛУШКА выбора фракции. Когда появится плейс-лобби, он передаст TeleportData = { faction = "Wizards" },
-- сервер выставит атрибут Faction сразу, и это окно не покажется.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
if localPlayer:GetAttribute("Faction") then return end

local Registry = require(ReplicatedStorage:WaitForChild("Factions"):WaitForChild("Registry"))
local selectEvent = ReplicatedStorage:WaitForChild("SelectFactionEvent")

local gui = Instance.new("ScreenGui")
gui.Name = "FactionSelectGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 300
gui.Parent = localPlayer:WaitForChild("PlayerGui")

local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
bg.BackgroundTransparency = 0.1
bg.Parent = gui

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0.15, 0)
title.Size = UDim2.fromOffset(600, 50)
title.BackgroundTransparency = 1
title.Text = "Выберите фракцию"
title.TextColor3 = Color3.fromRGB(255, 215, 0)
title.TextSize = 36
title.Font = Enum.Font.SourceSansBold
title.Parent = bg

local row = Instance.new("Frame")
row.AnchorPoint = Vector2.new(0.5, 0.5)
row.Position = UDim2.fromScale(0.5, 0.5)
row.Size = UDim2.fromOffset(840, 240)
row.BackgroundTransparency = 1
row.Parent = bg

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, 20)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = row

for _, info in Registry.List do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(260, 240)
	btn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.TextSize = 20
	btn.Font = Enum.Font.SourceSansBold
	btn.TextWrapped = true
	btn.Text = `{info.Title}\n\nГерой: {info.Hero}\n\n{info.Info}`
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
	Instance.new("UIStroke", btn).Color = Color3.fromRGB(255, 215, 0)
	btn.Activated:Connect(function() selectEvent:FireServer(info.Id) end)
	btn.Parent = row
end

localPlayer:GetAttributeChangedSignal("Faction"):Connect(function() gui:Destroy() end)
