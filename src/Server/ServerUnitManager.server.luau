local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local attackEvent = ReplicatedStorage:WaitForChild("AttackTargetEvent")
local moveEvent = ReplicatedStorage:WaitForChild("MoveUnitsEvent")

local FSMFolder = ServerScriptService:WaitForChild("FSM")
local StateMachine = require(FSMFolder:WaitForChild("StateMachine"))
local FactionServer = require(FSMFolder:WaitForChild("FactionServer"))
local Factions = ReplicatedStorage:WaitForChild("Factions")
local Registry = require(Factions:WaitForChild("Registry"))
local Base = require(Factions:WaitForChild("Base"))
local Faction = Base.Defaults -- общие значения: Workers, MinerLimit

local UNIT_SPACING = 5        -- расстояние между юнитами в построении
local MAX_COMMAND_UNITS = 200 -- защита от огромных таблиц от клиента

-- Состояния Humanoid, которые юнитам RTS не нужны (лишняя работа физики и микро-рывки)
local DISABLED_HUMANOID_STATES = {
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.Swimming,
}

-- 1. АВТО-ЗАГРУЗКА СОСТОЯНИЙ FSM
local loadedStates = {}
for _, module in ipairs(FSMFolder:WaitForChild("States"):GetChildren()) do
	if module:IsA("ModuleScript") then
		local success, result = pcall(require, module)
		if success and result then
			loadedStates[module.Name] = result
		else
			warn("❌ ОШИБКА в модуле " .. module.Name .. ": " .. tostring(result))
		end
	end
end

local activeUnitFSMs = {}
local playerFormations = {} -- [UserId] = { lastTarget = Vector3, dir = Vector3 }
local registeredGroups = {}

local function setupCollisionGroups(playerName)
	if registeredGroups[playerName] then return end
	registeredGroups[playerName] = true

	local solidGroup, ghostGroup = "Solid_" .. playerName, "Ghost_" .. playerName
	PhysicsService:RegisterCollisionGroup(solidGroup)
	PhysicsService:RegisterCollisionGroup(ghostGroup)
	PhysicsService:CollisionGroupSetCollidable(ghostGroup, ghostGroup, false)
	PhysicsService:CollisionGroupSetCollidable(ghostGroup, solidGroup, false)
end

local function getAdornPart(model)
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart") or model
end

local function createHealthBar(model, isBuilding)
	local health = model:FindFirstChild("Health")
	if not health then return end

	local maxHealth = health.Value
	local adornPart = getAdornPart(model)

	local bg = Instance.new("BillboardGui")
	bg.Name = "HealthBar"
	bg.Size = isBuilding and UDim2.new(4, 0, 0.5, 0) or UDim2.new(2.5, 0, 0.35, 0)
	bg.StudsOffset = isBuilding and Vector3.new(0, 8, 0) or Vector3.new(0, 4, 0)
	bg.AlwaysOnTop = true
	bg.MaxDistance = 150
	if adornPart:IsA("BasePart") then bg.Adornee = adornPart end

	local bgFrame = Instance.new("Frame")
	bgFrame.Size = UDim2.new(1, 0, 1, 0)
	bgFrame.BackgroundColor3 = Color3.new(1, 0, 0)
	bgFrame.Parent = bg

	local hpFrame = Instance.new("Frame")
	hpFrame.Name = "GreenBar"
	hpFrame.Size = UDim2.new(1, 0, 1, 0)
	hpFrame.BackgroundColor3 = Color3.new(0, 1, 0)
	hpFrame.BorderSizePixel = 0
	hpFrame.Parent = bgFrame

	bg.Parent = adornPart

	health.Changed:Connect(function(newHealth)
		hpFrame.Size = UDim2.new(math.clamp(newHealth / maxHealth, 0, 1), 0, 1, 0)
	end)
end

-- Сервер сам владеет физикой юнитов: иначе Roblox перекидывает их между сервером и игроками (рваное движение)
local function setServerOwnership(unitModel)
	local root = unitModel.PrimaryPart or unitModel:FindFirstChildWhichIsA("BasePart")
	if root and not root.Anchored then
		pcall(root.SetNetworkOwner, root, nil)
	end
end

local function registerUnit(unitModel)
	if activeUnitFSMs[unitModel] then return end

	local startHealth = unitModel:FindFirstChild("Health")
	if startHealth then unitModel:SetAttribute("MaxHealth", startHealth.Value) end
	createHealthBar(unitModel, false)

	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local speedTag = unitModel:FindFirstChild("Speed")
		if speedTag then humanoid.WalkSpeed = speedTag.Value end
		for _, state in ipairs(DISABLED_HUMANOID_STATES) do
			humanoid:SetStateEnabled(state, false)
		end
	end

	setServerOwnership(unitModel)

	local owner = unitModel:FindFirstChild("Owner")
	local ownerName = owner and owner.Value or ""
	if ownerName ~= "" then setupCollisionGroups(ownerName) end

	local fsm = StateMachine.new(unitModel)
	for stateName, stateModule in pairs(loadedStates) do
		fsm:AddState(stateName, stateModule)
	end

	fsm:SetCollisionMode("Ghost")
	activeUnitFSMs[unitModel] = fsm
	fsm:ChangeState("Idle")

	-- Запоминаем параметры до того, как Roblox удалит детей модели
	local nexusLink = unitModel:FindFirstChild("LinkedNexus")
	local linkedNexus = nexusLink and nexusLink.Value or nil
	local isMiner = Faction.Workers[unitModel.Name] or nexusLink ~= nil
	local slotTag = unitModel:FindFirstChild("SlotCost")
	local slotCost = slotTag and slotTag.Value or 1

	-- Единая точка очистки: и смерть, и принесение в жертву
	unitModel.Destroying:Connect(function()
		local unitFSM = activeUnitFSMs[unitModel]
		activeUnitFSMs[unitModel] = nil
		if unitFSM then unitFSM:Destroy() end

		if isMiner then
			local currentLink = unitModel:FindFirstChild("LinkedNexus")
			local targetNexus = (currentLink and currentLink.Value) or linkedNexus

			if targetNexus and targetNexus.Parent then
				local mCount = targetNexus:FindFirstChild("MinerCount")
				if mCount and mCount.Value > 0 then mCount.Value -= 1 end
			else
				-- Резерв: привязка слетела или это стартовый рабочий
				local buildingsFolder = workspace:FindFirstChild("Buildings")
				if buildingsFolder then
					for _, b in ipairs(buildingsFolder:GetChildren()) do
						local mCount = b:FindFirstChild("MinerCount")
						local bOwner = b:FindFirstChild("Owner")
						if mCount and bOwner and bOwner.Value == ownerName and mCount.Value > 0 then
							mCount.Value -= 1
							break
						end
					end
				end
			end
		elseif ownerName ~= "" then
			-- Освобождаем лимит военных юнитов
			local currentSlotTag = unitModel:FindFirstChild("SlotCost")
			local freedSlots = (currentSlotTag and currentSlotTag.Value) or slotCost
			local p = Players:FindFirstChild(ownerName)
			local milCount = p and p:FindFirstChild("leaderstats") and p.leaderstats:FindFirstChild("MilitaryCount")
			if milCount then milCount.Value = math.max(0, milCount.Value - freedSlots) end
		end
	end)

	local health = unitModel:FindFirstChild("Health")
	if health then
		health.Changed:Connect(function(newHealth)
			if newHealth <= 0 and unitModel.Parent then
				unitModel:Destroy()
			end
		end)
	end
end

-- Сколько баз (Нексусы, у Королевства ещё Заставы) осталось у игрока
local function countBases(ownerName)
	local player = Players:FindFirstChild(ownerName)
	local folder = workspace:FindFirstChild("Buildings")
	if not player or not folder then return 0 end

	local bases, n = Registry.Of(player).Bases, 0
	for _, b in folder:GetChildren() do
		local owner = b:FindFirstChild("Owner")
		if bases[b.Name] and owner and owner.Value == ownerName then n += 1 end
	end
	return n
end

local function SetupNexusLogic(building)
	local health = building:FindFirstChild("Health")
	local ownerTag = building:FindFirstChild("Owner")

	local minerCount = Instance.new("IntValue")
	minerCount.Name = "MinerCount"
	minerCount.Parent = building

	createHealthBar(building, true)

	local adornPart = getAdornPart(building)

	local limitGui = Instance.new("BillboardGui")
	limitGui.Name = "LimitGui"
	limitGui.Size = UDim2.new(5, 0, 1.5, 0)
	limitGui.StudsOffset = Vector3.new(0, 10.5, 0)
	limitGui.AlwaysOnTop = true
	limitGui.MaxDistance = 150
	if adornPart:IsA("BasePart") then limitGui.Adornee = adornPart end

	local limitLabel = Instance.new("TextLabel")
	limitLabel.Name = "LimitLabel"
	limitLabel.Size = UDim2.new(1, 0, 1, 0)
	limitLabel.BackgroundTransparency = 1
	limitLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	limitLabel.TextStrokeTransparency = 0
	limitLabel.TextScaled = true
	limitLabel.Font = Enum.Font.SourceSansBold
	limitLabel.Text = "0/" .. Faction.MinerLimit
	limitLabel.Parent = limitGui

	limitGui.Parent = adornPart

	minerCount.Changed:Connect(function(val)
		limitLabel.Text = val .. "/" .. Faction.MinerLimit
	end)

	if health and ownerTag then
		health.Changed:Connect(function(newHealth)
			if newHealth <= 0 and building.Parent then
				local explosion = Instance.new("Explosion")
				explosion.Position = building:GetPivot().Position
				explosion.BlastPressure = 0
				explosion.DestroyJointRadiusPercent = 0
				explosion.Parent = workspace

				local defeatedName = ownerTag.Value
				building:Destroy()

				local defeatedPlayer = Players:FindFirstChild(defeatedName)
				if defeatedPlayer and countBases(defeatedName) == 0 then
					defeatedPlayer:Kick("Ваш Нексус уничтожен! Игра окончена.")
				end
			end
		end)
	end
end

-- === ПРОВЕРКА КОМАНД ОТ КЛИЕНТА ===

local function isValidPosition(position)
	local magnitude = position.Magnitude
	return magnitude == magnitude and magnitude < 1e6 -- отсекаем NaN и inf
end

local function getGold(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild("Gold")
end

-- Только настоящие юниты игрока, не больше MAX_COMMAND_UNITS; у каждого гарантированно есть FSM
local function getOwnedUnits(player, unitsTable)
	local result = {}
	local unitsFolder = workspace:FindFirstChild("Units")
	if not unitsFolder then return result end

	for i = 1, math.min(#unitsTable, MAX_COMMAND_UNITS) do
		local unit = unitsTable[i]

		if typeof(unit) == "Instance" and unit.Parent == unitsFolder then
			local owner = unit:FindFirstChild("Owner")
			if owner and owner.Value == player.Name then
				registerUnit(unit) -- no-op, если уже зарегистрирован
				if activeUnitFSMs[unit] then
					table.insert(result, unit)
				end
			end
		end
	end

	return result
end

local pendingFactions = {} -- [Player] = слот-тег, пока игрок не выбрал фракцию
local selectFactionEvent = Instance.new("RemoteEvent")
selectFactionEvent.Name = "SelectFactionEvent"
selectFactionEvent.Parent = ReplicatedStorage

local function setOwner(model, name)
	local tag = model:FindFirstChild("Owner") or Instance.new("StringValue")
	tag.Name = "Owner"
	tag.Value = name
	tag.Parent = model
end

-- Заменяет заглушки слота (Нексус и стартовые юниты в workspace) на модели выбранной фракции
local function spawnFaction(player, factionId, slotTag)
	local faction = Registry.Get(factionId)
	player:SetAttribute("Faction", factionId)

	local buildings, units = workspace:FindFirstChild("Buildings"), workspace:FindFirstChild("Units")

	local base -- стартовый Нексус игрока
	for _, placeholder in (buildings and buildings:GetChildren() or {}) do
		local tag = placeholder:FindFirstChild("Owner")
		if tag and tag.Value == slotTag then
			local template = faction.Template("Buildings", "NexusTemplate")
			if template then
				local cf, size = placeholder:GetBoundingBox()
				local _, newSize = template:GetBoundingBox()
				local nexus = template:Clone()
				nexus.Name = "Nexus"
				Base.ApplyStats(nexus, faction.Nexus.Stats)
				nexus:PivotTo(CFrame.new(cf.X, cf.Y - size.Y / 2 + newSize.Y / 2, cf.Z) * cf.Rotation)
				setOwner(nexus, player.Name)
				placeholder:Destroy()
				nexus.Parent = buildings
				SetupNexusLogic(nexus)
				base = nexus
			else
				warn("Нет NexusTemplate у фракции " .. factionId .. ", оставляю заглушку")
				setOwner(placeholder, player.Name)
				SetupNexusLogic(placeholder)
				base = placeholder
			end
		end
	end

	for _, placeholder in (units and units:GetChildren() or {}) do
		local tag = placeholder:FindFirstChild("Owner")
		if tag and tag.Value == slotTag then placeholder:Destroy() end -- стартовых добытчиков создаёт FactionServer.SpawnMiners
	end

	if base and FactionServer.SpawnMiners then
		FactionServer.SpawnMiners(player, base, faction.StartMiners)
	end

	if faction.Hero.StartsSpawned and FactionServer.SummonHero then
		FactionServer.SummonHero(player, true) -- герой с первой секунды (Королева)
	end
end

-- Выбор фракции: сейчас шлёт заглушка FactionSelect, позже придёт из TeleportData лобби
selectFactionEvent.OnServerEvent:Connect(function(player, factionId)
	local slotTag = pendingFactions[player]
	if not slotTag or type(factionId) ~= "string" or not Registry.Exists(factionId) then return end
	pendingFactions[player] = nil
	spawnFaction(player, factionId, slotTag)
end)

-- 2. ВХОД ИГРОКА И НАЧАЛЬНЫЙ БАЛАНС
local totalPlayersJoined = 0

Players.PlayerAdded:Connect(function(player)
	totalPlayersJoined += 1
	local playerSlotTag = "Player" .. totalPlayersJoined

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	for name, value in { Gold = 200, MilitaryCount = 0, MilitaryLimit = 0 } do
		local v = Instance.new("IntValue")
		v.Name = name
		v.Value = value
		v.Parent = leaderstats
	end

	-- Фракцию либо передало лобби (TeleportData), либо игрок выберет в заглушке FactionSelect
	local teleportData = player:GetJoinData().TeleportData
	local picked = type(teleportData) == "table" and teleportData.faction
	if picked and Registry.Exists(picked) then
		spawnFaction(player, picked, playerSlotTag)
	else
		pendingFactions[player] = playerSlotTag
	end
end)

Players.PlayerRemoving:Connect(function(player)
	playerFormations[player.UserId] = nil
	pendingFactions[player] = nil

	if #Players:GetPlayers() == 0 then
		totalPlayersJoined = 0
	end
end)

-- 3. ДВИЖЕНИЕ И АТАКА
moveEvent.OnServerEvent:Connect(function(player, unitsTable, targetPosition, isDrag)
	if type(unitsTable) ~= "table" or typeof(targetPosition) ~= "Vector3" then return end
	if not isValidPosition(targetPosition) then return end

	local units = getOwnedUnits(player, unitsTable)
	local count = #units
	if count == 0 then return end

	isDrag = isDrag == true

	-- Направление построения определяется по движению точки назначения
	local formation = playerFormations[player.UserId]
	if not formation then
		formation = { lastTarget = targetPosition, dir = Vector3.zAxis }
		playerFormations[player.UserId] = formation
	end

	local delta = targetPosition - formation.lastTarget
	delta = Vector3.new(delta.X, 0, delta.Z)
	if delta.Magnitude > 0.5 then
		formation.dir = delta.Unit
	end
	formation.lastTarget = targetPosition

	local formationCFrame = CFrame.lookAt(targetPosition, targetPosition + formation.dir)
	local gridSize = math.ceil(math.sqrt(count))
	local centerOffset = (gridSize - 1) / 2

	for i, unit in ipairs(units) do
		local row = (i - 1) // gridSize
		local col = (i - 1) % gridSize
		local localOffset = Vector3.new(
			(col - centerOffset) * UNIT_SPACING,
			0,
			(row - centerOffset) * UNIT_SPACING
		)

		activeUnitFSMs[unit]:ChangeState("Moving", formationCFrame:PointToWorldSpace(localOffset), isDrag)
	end
end)

attackEvent.OnServerEvent:Connect(function(player, unitsTable, clickPosition)
	if type(unitsTable) ~= "table" or typeof(clickPosition) ~= "Vector3" then return end
	if not isValidPosition(clickPosition) then return end

	local units = getOwnedUnits(player, unitsTable)
	if #units == 0 then return end

	local targetEnemy = activeUnitFSMs[units[1]]:FindClosestEnemy(50, clickPosition)
	if not targetEnemy then return end

	for _, unit in ipairs(units) do
		activeUnitFSMs[unit]:ChangeState("Attacking", targetEnemy)
	end
end)

-- 4. ФРАКЦИЯ: создание юнитов, стройка, герой, доход
FactionServer.Init({
	activeUnitFSMs = activeUnitFSMs,
	registerUnit = registerUnit,
	getOwnedUnits = getOwnedUnits,
	isValidPosition = isValidPosition,
	getGold = getGold,
	createHealthBar = createHealthBar,
	setupBase = SetupNexusLogic,
	countBases = countBases,
})

-- Обновление FSM. pcall: ошибка в одном юните не обрывает цикл для остальных.
RunService.Heartbeat:Connect(function(dt)
	for unitModel, fsm in pairs(activeUnitFSMs) do
		local ok, err = pcall(fsm.Update, fsm, dt)
		if not ok and not fsm.ErrorLogged then
			fsm.ErrorLogged = true
			warn("❌ Ошибка FSM у " .. unitModel.Name .. " (" .. tostring(fsm.CurrentState) .. "): " .. tostring(err))
		end
	end
end)
