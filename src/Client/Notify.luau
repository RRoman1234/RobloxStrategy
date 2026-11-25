local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DURATION = 2

local gui = Instance.new("ScreenGui")
gui.Name = "NotifyGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 200
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0, 80)
label.Size = UDim2.fromOffset(420, 40)
label.BackgroundColor3 = Color3.fromRGB(120, 20, 20)
label.BackgroundTransparency = 0.2
label.TextColor3 = Color3.new(1, 1, 1)
label.TextSize = 20
label.Font = Enum.Font.SourceSansBold
label.Visible = false
label.Parent = gui
Instance.new("UICorner", label).CornerRadius = UDim.new(0, 8)

local Notify = {}
local token = 0

function Notify.Show(text)
	token += 1
	local mine = token
	label.Text = text
	label.Visible = true
	task.delay(DURATION, function()
		if token == mine then label.Visible = false end
	end)
end

ReplicatedStorage:WaitForChild("NotifyEvent").OnClientEvent:Connect(Notify.Show)

return Notify