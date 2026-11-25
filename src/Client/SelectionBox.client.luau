local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local workspace = game:GetService("Workspace")

local selectionEvent = ReplicatedStorage:WaitForChild("SelectionAreaEvent")
local FactionInput = require(script.Parent:WaitForChild("FactionInput"))
local camera = workspace.CurrentCamera

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SelectionGui"
screenGui.IgnoreGuiInset = true
screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local selectionBox = Instance.new("Frame")
selectionBox.BackgroundColor3 = Color3.new(0, 1, 0)
selectionBox.BackgroundTransparency = 0.8
selectionBox.BorderColor3 = Color3.new(0, 1, 0)
selectionBox.BorderSizePixel = 1
selectionBox.Visible = false
selectionBox.Parent = screenGui

local isSelecting = false
local startWorldPos = nil 
local startMousePos = nil 

-- Функция для получения идеальных координат мыши (с учетом панели Roblox)
local function getAbsoluteScreenPos(worldPos)
	local viewPos, onScreen = camera:WorldToViewportPoint(worldPos)
	local inset = GuiService:GetGuiInset()
	return Vector2.new(viewPos.X, viewPos.Y + inset.Y), onScreen
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isSelecting = true
		startMousePos = UserInputService:GetMouseLocation()

		local inset = GuiService:GetGuiInset()
		local ray = camera:ViewportPointToRay(startMousePos.X, startMousePos.Y - inset.Y)
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000)

		if hit then
			startWorldPos = hit.Position
		else
			local distance = -ray.Origin.Y / ray.Direction.Y
			startWorldPos = ray.Origin + ray.Direction * distance
		end

		selectionBox.Size = UDim2.new(0, 0, 0, 0)
	end
end)

RunService.RenderStepped:Connect(function()
	if isSelecting and startWorldPos then
		local currentMousePos = UserInputService:GetMouseLocation()
		local screenStartPos, _ = getAbsoluteScreenPos(startWorldPos)

		if (currentMousePos - startMousePos).Magnitude > 10 then
			local minX = math.min(screenStartPos.X, currentMousePos.X)
			local minY = math.min(screenStartPos.Y, currentMousePos.Y)
			local maxX = math.max(screenStartPos.X, currentMousePos.X)
			local maxY = math.max(screenStartPos.Y, currentMousePos.Y)

			selectionBox.Position = UDim2.new(0, minX, 0, minY)
			selectionBox.Size = UDim2.new(0, maxX - minX, 0, maxY - minY)
			selectionBox.Visible = true
		else
			selectionBox.Visible = false
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and isSelecting then
		isSelecting = false
		selectionBox.Visible = false
		if FactionInput.ConsumeClick() then return end -- клик ушёл на стройку/продажу

		local endPos = UserInputService:GetMouseLocation()
		local isClick = (endPos - startMousePos).Magnitude <= 10

		local screenStartPos, _ = getAbsoluteScreenPos(startWorldPos)
		local minX = math.min(screenStartPos.X, endPos.X)
		local minY = math.min(screenStartPos.Y, endPos.Y)
		local maxX = math.max(screenStartPos.X, endPos.X)
		local maxY = math.max(screenStartPos.Y, endPos.Y)

		local isShiftPressed = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)

		selectionEvent:Fire(Vector2.new(minX, minY), Vector2.new(maxX, maxY), isClick, endPos, isShiftPressed)
	end
end)