local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer

-- Базовый радиус обзора для любого юнита или здания (в стадах)
local DEFAULT_VISION_RADIUS = 60
local UPDATE_INTERVAL = 0.2

-- Текущее состояние видимости каждой модели. Применяем изменения только когда состояние
-- действительно поменялось (раньше каждые 0.2с для каждого врага заново обходились все его детали).
local visibilityState = setmetatable({}, { __mode = "k" })
local trackedEntities = setmetatable({}, { __mode = "k" })

local function applyToInstance(inst, isVisible)
	if inst:IsA("BasePart") or inst:IsA("Decal") then
		inst.LocalTransparencyModifier = isVisible and 0 or 1
	elseif inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then
		if inst.Name ~= "SelectionGui" then
			inst.Enabled = isVisible
		end
	end
end

local function setModelVisibility(model, isVisible)
	if visibilityState[model] == isVisible then return end
	visibilityState[model] = isVisible

	for _, desc in ipairs(model:GetDescendants()) do
		applyToInstance(desc, isVisible)
	end

	-- Прячем стандартную полоску здоровья Roblox в тумане
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = isVisible
			and Enum.HumanoidDisplayDistanceType.Viewer
			or Enum.HumanoidDisplayDistanceType.None
	end
end

-- Всё, что появляется внутри скрытой модели позже (например, полоска ХП, которую сервер
-- создаёт уже после спавна), тоже нужно сразу спрятать
local function trackEntity(entity)
	if trackedEntities[entity] then return end
	trackedEntities[entity] = true

	entity.DescendantAdded:Connect(function(desc)
		if visibilityState[entity] == false then
			applyToInstance(desc, false)
		end
	end)
end

-- Буферы переиспользуются между тиками, чтобы не плодить таблицы
local friendPositions, friendRadiusSq = {}, {}
local enemyEntities, enemyPositions = {}, {}

local function collectEntities(folder, myName, state)
	if not folder then return end

	for _, entity in ipairs(folder:GetChildren()) do
		local ownerTag = entity:FindFirstChild("Owner")
		local part = entity.PrimaryPart or entity:FindFirstChildWhichIsA("BasePart")

		if ownerTag and part then
			if ownerTag.Value == myName then
				-- Свои объекты всегда видны (на случай, если Owner назначили уже после спавна)
				setModelVisibility(entity, true)

				local radiusTag = entity:FindFirstChild("VisionRadius")
				local radius = radiusTag and radiusTag.Value or DEFAULT_VISION_RADIUS

				state.friends += 1
				friendPositions[state.friends] = part.Position
				friendRadiusSq[state.friends] = radius * radius
			else
				state.enemies += 1
				enemyEntities[state.enemies] = entity
				enemyPositions[state.enemies] = part.Position
			end
		end
	end
end

local function updateFogOfWar()
	table.clear(friendPositions)
	table.clear(friendRadiusSq)
	table.clear(enemyEntities)
	table.clear(enemyPositions)

	local state = { friends = 0, enemies = 0 }
	collectEntities(workspace:FindFirstChild("Units"), localPlayer.Name, state)
	collectEntities(workspace:FindFirstChild("Buildings"), localPlayer.Name, state)

	-- Видит ли врага хоть кто-то из наших?
	for e = 1, state.enemies do
		local enemyPos = enemyPositions[e]
		local isVisible = false

		for f = 1, state.friends do
			local offset = friendPositions[f] - enemyPos
			if offset:Dot(offset) <= friendRadiusSq[f] then
				isVisible = true
				break
			end
		end

		setModelVisibility(enemyEntities[e], isVisible)
	end
end

-- Обновляем не каждый кадр, а 5 раз в секунду
local timeAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	timeAccumulator += dt
	if timeAccumulator >= UPDATE_INTERVAL then
		timeAccumulator = 0
		updateFogOfWar()
	end
end)

-- Мгновенно прячем чужих юнитов при их появлении в мире
local function onEntityAdded(entity)
	trackEntity(entity)
	setModelVisibility(entity, false)

	task.spawn(function()
		local ownerTag = entity:WaitForChild("Owner", 2)
		if ownerTag and ownerTag.Value == localPlayer.Name then
			setModelVisibility(entity, true)
		end
	end)
end

for _, folderName in ipairs({ "Units", "Buildings" }) do
	local folder = workspace:WaitForChild(folderName)
	folder.ChildAdded:Connect(onEntityAdded)

	-- Объекты, которые уже были в мире на момент запуска скрипта
	for _, entity in ipairs(folder:GetChildren()) do
		onEntityAdded(entity)
	end
end
