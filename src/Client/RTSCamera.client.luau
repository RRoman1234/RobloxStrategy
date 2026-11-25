local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local camera = workspace.CurrentCamera
local localPlayer = Players.LocalPlayer -- ДОБАВЛЕНО: Ссылка на локального игрока

-- === НАСТРОЙКИ КАМЕРЫ ===
local MOVE_SPEED = 60        
local ZOOM_SPEED = 6         
local MIN_ZOOM = 20          
local MAX_ZOOM = 50        
local CAMERA_ANGLE = -60    
local CAMERA_ROTATION = 45  

local EDGE_ZONE_PERCENT = 0.01
local DRAG_SENSITIVITY = 0.04  

-- === ТЕКУЩЕЕ СОСТОЯНИЕ ===
local targetPosition = Vector3.new(0, 0, 0) 
local currentZoom = MAX_ZOOM

local movementInput = { W = 0, A = 0, S = 0, D = 0 }

local isDragging = false
local dragStartMousePos = Vector2.new()
local dragStartTargetPos = Vector3.new()

-- === ИНИЦИАЛИЗАЦИЯ ===
camera.CameraType = Enum.CameraType.Scriptable

-- Функция для поворота вектора движения под угол камеры
local function rotateVector(vec)
	local cf = CFrame.Angles(0, math.rad(CAMERA_ROTATION), 0)
	return cf * vec
end

-- ==================================
-- ФОКУСИРОВКА НА НЕКСУСЕ ПРИ СТАРТЕ 
-- ==================================
local function focusOnMyNexus()
	if not localPlayer:GetAttribute("Faction") then
		localPlayer:GetAttributeChangedSignal("Faction"):Wait()
	end

	local buildingsFolder = workspace:WaitForChild("Buildings", 10)
	if not buildingsFolder then return end

	-- Делаем до 20 попыток с паузой в 0.5с (на случай, если сервер выдает Owner с задержкой)
	for attempt = 1, 20 do
		for _, building in ipairs(buildingsFolder:GetChildren()) do
			local ownerTag = building:FindFirstChild("Owner")

			if building.Name == "Nexus" and ownerTag and ownerTag.Value == localPlayer.Name then
				local primaryPart = building.PrimaryPart or building:FindFirstChildWhichIsA("BasePart")

				if primaryPart then
					-- переносим точку привязки камеры на Нексус!
					targetPosition = primaryPart.Position
					print("🎯 Камера успешно сфокусирована на Нексусе игрока: " .. localPlayer.Name)
					return
				end
			end
		end
		task.wait(0.5) -- Ждем полсекунды перед следующей проверкой
	end
end

-- Запускаем фокус в отдельном потоке, чтобы не блочить загрузку скрипта
task.spawn(focusOnMyNexus)

-- === ОБРАБОТКА ВВОДА ===
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.Up then movementInput.W = -1 end
	if input.KeyCode == Enum.KeyCode.Down then movementInput.S = 1 end
	if input.KeyCode == Enum.KeyCode.Left then movementInput.A = -1 end
	if input.KeyCode == Enum.KeyCode.Right then movementInput.D = 1 end

	if input.UserInputType == Enum.UserInputType.MouseButton3 then
		isDragging = true
		dragStartMousePos = UserInputService:GetMouseLocation()
		dragStartTargetPos = targetPosition
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Up then movementInput.W = 0 end
	if input.KeyCode == Enum.KeyCode.Down then movementInput.S = 0 end
	if input.KeyCode == Enum.KeyCode.Left then movementInput.A = 0 end
	if input.KeyCode == Enum.KeyCode.Right then movementInput.D = 0 end

	if input.UserInputType == Enum.UserInputType.MouseButton3 then
		isDragging = false
	end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		currentZoom = math.clamp(currentZoom - (input.Position.Z * ZOOM_SPEED), MIN_ZOOM, MAX_ZOOM)
	end

	if input.UserInputType == Enum.UserInputType.MouseMovement and isDragging then
		local currentMousePos = UserInputService:GetMouseLocation()
		local delta = currentMousePos - dragStartMousePos

		local dragFactor = currentZoom * DRAG_SENSITIVITY * 0.02

		local rawDragVector = Vector3.new(delta.X * dragFactor, 0, delta.Y * dragFactor)
		targetPosition = dragStartTargetPos - rotateVector(rawDragVector)
	end
end)

-- === ОБНОВЛЕНИЕ КАМЕРЫ ===
RunService.RenderStepped:Connect(function(deltaTime)
	local moveVector = Vector3.new(0, 0, 0)

	if not isDragging then
		local rawMoveVector = Vector3.new(movementInput.A + movementInput.D, 0, movementInput.W + movementInput.S)

		local mousePos = UserInputService:GetMouseLocation()
		local viewportSize = camera.ViewportSize
		local screenCenter = viewportSize / 2

		local edgeX = viewportSize.X * EDGE_ZONE_PERCENT
		local edgeY = viewportSize.Y * EDGE_ZONE_PERCENT

		local inLeftEdge = mousePos.X <= edgeX
		local inRightEdge = mousePos.X >= viewportSize.X - edgeX
		local inTopEdge = mousePos.Y <= edgeY
		local inBottomEdge = mousePos.Y >= viewportSize.Y - edgeY

		if inLeftEdge or inRightEdge or inTopEdge or inBottomEdge then
			local directionFromCenter = (mousePos - screenCenter)
			local edgeMoveDirection = Vector3.new(directionFromCenter.X, 0, directionFromCenter.Y).Unit
			rawMoveVector = rawMoveVector + edgeMoveDirection
		end

		if rawMoveVector.Magnitude > 0 then
			rawMoveVector = rawMoveVector.Unit
			local rotatedMoveVector = rotateVector(rawMoveVector)
			targetPosition = targetPosition + (rotatedMoveVector * MOVE_SPEED * deltaTime)
		end
	end

	local newCameraCFrame = CFrame.new(targetPosition) 
		* CFrame.Angles(0, math.rad(CAMERA_ROTATION), 0)
		* CFrame.Angles(math.rad(CAMERA_ANGLE), 0, 0)
		* CFrame.new(0, 0, currentZoom)

	camera.CFrame = newCameraCFrame
	camera.Focus = CFrame.new(targetPosition)
end)