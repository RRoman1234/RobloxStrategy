local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Registry = require(ReplicatedStorage:WaitForChild("Factions"):WaitForChild("Registry"))
local FactionInput = require(script.Parent:WaitForChild("FactionInput"))

local attackEvent = ReplicatedStorage:WaitForChild("AttackTargetEvent")
local moveEvent = ReplicatedStorage:WaitForChild("MoveUnitsEvent")
local getSelectedUnitsFunction = ReplicatedStorage:WaitForChild("GetSelectedUnitsFunction")

local camera = workspace.CurrentCamera
local localPlayer = Players.LocalPlayer
local Faction = Registry.Proxy(localPlayer)

local COMMAND_COOLDOWN = 0.15  -- пауза между командами при удержании ПКМ
local DRAG_MIN_DELTA = 1.5     -- при удержании ПКМ шлём команду, только если курсор сдвинулся на столько стадов
local MAX_PEEL_ITERATIONS = 3  -- сколько своих юнитов "пробиваем" лучом, чтобы найти землю под ними

local isHoldingRMB = false
local lastCommandTime = 0
local lastMoveHitPos = nil -- последняя отправленная точка (для дедупликации drag-команд)

-- === МАРКЕР КЛИКА ===
local marker = Instance.new("Part")
marker.Name = "MoveMarker"
marker.Shape = Enum.PartType.Cylinder
marker.Material = Enum.Material.Neon
marker.Anchored = true
marker.CanCollide = false
marker.CanQuery = false
marker.CanTouch = false
marker.CastShadow = false
marker.Transparency = 1
marker.Size = Vector3.new(0.15, 1, 1)
marker.Parent = workspace

local markerTween = nil

local function showMarker(position, color)
	if markerTween then markerTween:Cancel() end

	marker.Color = color
	marker.Size = Vector3.new(0.15, 1, 1)
	marker.Transparency = 0.2
	marker.CFrame = CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))

	markerTween = TweenService:Create(marker, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, 4, 4),
		Transparency = 1,
	})
	markerTween:Play()
end

-- GetMouseLocation() — координаты viewport, поэтому ViewportPointToRay (ScreenPointToRay сдвигал клик на высоту панели)
local function raycastFromMouse(ignoreOwnUnits)
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local direction = ray.Direction * 1000

	if not ignoreOwnUnits then
		return workspace:Raycast(ray.Origin, direction)
	end

	-- Клик "сквозь" своих юнитов: цель движения — земля, а не макушка стоящего юнита
	local unitsFolder = workspace:FindFirstChild("Units")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}

	for _ = 1, MAX_PEEL_ITERATIONS do
		params.FilterDescendantsInstances = ignore
		local result = workspace:Raycast(ray.Origin, direction, params)
		if not result then return nil end

		local model = result.Instance:FindFirstAncestorOfClass("Model")
		local ownerTag = model and model:FindFirstChild("Owner")
		local isOwnUnit = ownerTag and ownerTag.Value == localPlayer.Name
			and unitsFolder and model.Parent == unitsFolder

		if not isOwnUnit then return result end
		table.insert(ignore, model)
	end

	return nil
end

local function sendMoveCommand(isDrag)
	local units = {}
	for _, u in getSelectedUnitsFunction:Invoke() do
		if not Faction.Workers[u.Name] then table.insert(units, u) end
	end
	if #units == 0 then return end

	local raycastResult = raycastFromMouse(true)
	if not raycastResult then return end

	local hitModel = raycastResult.Instance:FindFirstAncestorOfClass("Model")
	local hitPosition = raycastResult.Position
	local ownerTag = hitModel and hitModel:FindFirstChild("Owner")

	if ownerTag and ownerTag.Value ~= localPlayer.Name then
		-- Вражеский юнит/здание
		if not isDrag then
			local targetPart = hitModel.PrimaryPart or hitModel:FindFirstChildWhichIsA("BasePart")
			if targetPart then
				attackEvent:FireServer(units, targetPart.Position)
				showMarker(targetPart.Position, Color3.fromRGB(255, 60, 60))
			end
		end
	else
		-- При удержании ПКМ не засыпаем сервер одинаковыми командами, пока курсор стоит на месте
		if isDrag and lastMoveHitPos and (hitPosition - lastMoveHitPos).Magnitude < DRAG_MIN_DELTA then
			return
		end

		lastMoveHitPos = hitPosition
		moveEvent:FireServer(units, hitPosition, isDrag)

		if not isDrag then
			showMarker(hitPosition, Color3.fromRGB(80, 255, 120))
		end
	end

	lastCommandTime = os.clock()
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		FactionInput.TryPlace()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		if FactionInput.Cancel() then return end -- ПКМ отменяет стройку
		isHoldingRMB = true
		lastMoveHitPos = nil
		sendMoveCommand(false)
	elseif input.KeyCode == Enum.KeyCode.A then
		-- Атака по области
		local selected = getSelectedUnitsFunction:Invoke()
		local result = #selected > 0 and raycastFromMouse(true)
		if result then
			attackEvent:FireServer(selected, result.Position)
			showMarker(result.Position, Color3.fromRGB(255, 60, 60))
		end
	else
		FactionInput.HandleKey(input) -- клавиши 1-6 и R
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		isHoldingRMB = false
		lastMoveHitPos = nil
	end
end)

RunService.RenderStepped:Connect(function()
	if isHoldingRMB and os.clock() - lastCommandTime >= COMMAND_COOLDOWN then
		sendMoveCommand(true)
	end
	FactionInput.Update()
end)
