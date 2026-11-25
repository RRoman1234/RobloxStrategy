local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local workspace = game:GetService("Workspace")

local camera = workspace.CurrentCamera
local localPlayer = Players.LocalPlayer
local selectionEvent = ReplicatedStorage:WaitForChild("SelectionAreaEvent")
local getSelectedUnitsFunction = ReplicatedStorage:WaitForChild("GetSelectedUnitsFunction")
local getSelectedBuildingsFunction = ReplicatedStorage:WaitForChild("GetSelectedBuildingsFunction")

local selectedUnits = {}
local selectedBuildings = {}

getSelectedUnitsFunction.OnInvoke = function() return selectedUnits end
getSelectedBuildingsFunction.OnInvoke = function() return selectedBuildings end

local function removeSelectionVisuals(entity)
	local highlight = entity:FindFirstChild("SelectionHighlight")
	if highlight then 
		highlight:Destroy() 
	end
	-- Удаляем устаревший SelectionCircle, если он вдруг остался
	local circle = entity:FindFirstChild("SelectionCircle")
	if circle then 
		circle:Destroy() 
	end
end

local function clearSelection()
	for _, entity in ipairs(selectedUnits) do
		removeSelectionVisuals(entity)
	end
	for _, entity in ipairs(selectedBuildings) do
		removeSelectionVisuals(entity)
	end
	table.clear(selectedUnits)
	table.clear(selectedBuildings)
end

local function highlightEntity(entity, color, targetTable)
	if entity:FindFirstChild("SelectionHighlight") then return end
	if not entity.PrimaryPart then return end

	-- 3D Highlight для динамической обводки контура модели в пространстве
	local highlight = Instance.new("Highlight")
	highlight.Name = "SelectionHighlight"
	highlight.Adornee = entity
	highlight.OutlineColor = color
	highlight.OutlineTransparency = 0
	highlight.FillColor = color
	highlight.FillTransparency = 0.85
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = entity

	table.insert(targetTable, entity)
end

local function unhighlightEntity(entity, targetTable)
	removeSelectionVisuals(entity)
	local index = table.find(targetTable, entity)
	if index then
		table.remove(targetTable, index)
	end
end

-- Прямоугольник сущности на экране (от макушки до пяток, по всему bounding box)
local function getScreenRect(entity)
	local cframe, size = entity:GetBoundingBox()
	local half = size / 2

	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge
	local anyInFront = false

	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				local corner = cframe:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
				local viewPos = camera:WorldToViewportPoint(corner)
				if viewPos.Z > 0 then
					anyInFront = true
					minX = math.min(minX, viewPos.X)
					minY = math.min(minY, viewPos.Y)
					maxX = math.max(maxX, viewPos.X)
					maxY = math.max(maxY, viewPos.Y)
				end
			end
		end
	end

	if not anyInFront then return nil end
	return Vector2.new(minX, minY), Vector2.new(maxX, maxY)
end

local CLICK_PADDING = 20 -- небольшой запас в пикселях вокруг модели

selectionEvent.Event:Connect(function(minXY, maxXY, isClick, clickPos, isShiftPressed)
	if not isShiftPressed then
		clearSelection()
	end

	local searchGroups = {
		{folderName = "Units", color = Color3.new(1, 1, 1), targetTable = selectedUnits},
		{folderName = "Buildings", color = Color3.new(0, 1, 0), targetTable = selectedBuildings}
	}

	if isClick then
		local closestEntity = nil
		local minDistance = math.huge
		local selectedGroup = nil

		for _, group in ipairs(searchGroups) do
			local folder = workspace:FindFirstChild(group.folderName)
			if not folder then continue end

			for _, entity in ipairs(folder:GetChildren()) do
				local ownerTag = entity:FindFirstChild("Owner")
				if not ownerTag or ownerTag.Value ~= localPlayer.Name then continue end
				if not entity.PrimaryPart then continue end

				local rMin, rMax = getScreenRect(entity)
				if not rMin then continue end

				local inside = clickPos.X >= rMin.X - CLICK_PADDING and clickPos.X <= rMax.X + CLICK_PADDING
					and clickPos.Y >= rMin.Y - CLICK_PADDING and clickPos.Y <= rMax.Y + CLICK_PADDING

				if inside then
					-- при перекрытии выбираем ту, чей центр ближе к курсору
					local center = (rMin + rMax) / 2
					local dist = (center - clickPos).Magnitude
					if dist < minDistance then
						minDistance = dist
						closestEntity = entity
						selectedGroup = group
					end
				end
			end
		end

		if closestEntity and selectedGroup then
			if isShiftPressed and closestEntity:FindFirstChild("SelectionHighlight") then
				unhighlightEntity(closestEntity, selectedGroup.targetTable)
			else
				highlightEntity(closestEntity, selectedGroup.color, selectedGroup.targetTable)
			end
		end

		return
	end

	-- Выделение рамкой: центр модели на экране (середина между головой и ногами)
	for _, group in ipairs(searchGroups) do
		local folder = workspace:FindFirstChild(group.folderName)
		if not folder then continue end

		for _, entity in ipairs(folder:GetChildren()) do
			local ownerTag = entity:FindFirstChild("Owner")
			if not ownerTag or ownerTag.Value ~= localPlayer.Name then continue end
			if not entity.PrimaryPart then continue end

			local rMin, rMax = getScreenRect(entity)
			if not rMin then continue end

			local center = (rMin + rMax) / 2
			if center.X >= minXY.X and center.X <= maxXY.X and center.Y >= minXY.Y and center.Y <= maxXY.Y then
				highlightEntity(entity, group.color, group.targetTable)
			end
		end
	end

	if not isClick and #selectedUnits > 0 and #selectedBuildings > 0 then
		for _, entity in ipairs(selectedBuildings) do
			removeSelectionVisuals(entity)
		end
		table.clear(selectedBuildings)
	end
end)
