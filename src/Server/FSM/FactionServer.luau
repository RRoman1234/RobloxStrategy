-- ServerScriptService/FSM/FactionServer
-- Серверная логика фракций: создание юнитов, стройка, призыв героя, доход добытчиков.
-- Всё, что отличает фракции, лежит в Factions/<Id>/Faction (данные) и FSM/Heroes/<Id> (механика героя).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Factions = ReplicatedStorage:WaitForChild("Factions")
local Registry = require(Factions:WaitForChild("Registry"))
local Base = require(Factions:WaitForChild("Base"))
local setValue = Base.SetValue

local MAX_SPAWN_DISTANCE = 60 -- как далеко от здания клиент может просить заспавнить юнита

local FactionServer = {}

local function getFolder(name)
	local f = workspace:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = workspace
	end
	return f
end

local function findBuilding(playerName, buildingName)
	local folder = workspace:FindFirstChild("Buildings")
	if not folder then return nil end
	for _, b in folder:GetChildren() do
		local owner = b:FindFirstChild("Owner")
		if b.Name == buildingName and owner and owner.Value == playerName then
			return b
		end
	end
end

-- Любая база игрока (Нексус или Застава у Королевства)
local function findBase(playerName)
	local player = Players:FindFirstChild(playerName)
	local bases = Registry.Of(player).Bases
	local folder = workspace:FindFirstChild("Buildings")
	if not folder then return nil end
	for _, b in folder:GetChildren() do
		local owner = b:FindFirstChild("Owner")
		if bases[b.Name] and owner and owner.Value == playerName then return b end
	end
end

-- Создаёт событие, если его нет в ReplicatedStorage (иначе клиент и сервер вечно ждут друг друга)
local function remote(name, class)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new(class or "RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

-- ctx: activeUnitFSMs, registerUnit, getOwnedUnits, isValidPosition, getGold, createHealthBar
-- Сюда же дописываются deny, spawnUnit, setSpeedMult, findBuilding для модулей героев.
function FactionServer.Init(ctx)
	local fsms = ctx.activeUnitFSMs
	local notifyEvent = remote("NotifyEvent") -- первым: клиентский Notify ждёт его при загрузке
	local createUnitEvent = remote("CreateUnitEvent")
	local buildEvent = remote("BuildCommandEvent")
	local spawnBuilding = remote("SpawnBuildingBindable", "BindableEvent")
	local function deny(player, text) notifyEvent:FireClient(player, text) end

	-- Скорость = базовая * множитель (бафы героев)
	local function setSpeedMult(unit, mult)
		if unit:GetAttribute("SpeedMult") == mult then return end
		unit:SetAttribute("SpeedMult", mult)
		local humanoid = unit:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		local base = unit:GetAttribute("BaseSpeed")
		if not base then
			base = humanoid.WalkSpeed
			unit:SetAttribute("BaseSpeed", base)
		end
		humanoid.WalkSpeed = base * mult
	end

	-- Создаёт юнита (или "Hero") фракции игрока. Золото и лимит армии списывает вызывающий.
	local function spawnUnit(player, unitName, position, slotCost, homeBase)
		local faction = Registry.Of(player)
		local def = unitName == "Hero" and faction.Hero or faction.Units[unitName]
		local template = faction.Template("Units", unitName)
		if not def or not template then
			warn("Нет шаблона юнита " .. unitName .. " у фракции " .. faction.Id)
			return nil
		end

		local unit = template:Clone()
		unit.Name = unitName
		Base.ApplyStats(unit, def.Stats)
		setValue(unit, "SlotCost", "IntValue", slotCost or def.Slots)
		setValue(unit, "Owner", "StringValue", player.Name)
		if homeBase then -- добытчик привязан к своей базе и возвращается на место добычи
			setValue(unit, "LinkedNexus", "ObjectValue", homeBase)
			setValue(unit, "HomePosition", "Vector3Value", position)
		end
		local look = homeBase and homeBase:GetPivot().Position -- добытчик сразу смотрит на свою базу
		unit:PivotTo(look and CFrame.lookAt(position, Vector3.new(look.X, position.Y, look.Z)) or CFrame.new(position))
		unit.Parent = getFolder("Units")
		ctx.registerUnit(unit)
		return unit
	end

	-- Стартовые добытчики по кругу у базы (та же раскладка, что у созданных вручную)
	local function spawnMiners(player, base, count)
		local faction = Registry.Of(player)
		local minerCount = base:FindFirstChild("MinerCount")
		for i = 1, count do
			if minerCount then minerCount.Value += 1 end
			local angle = ((minerCount and minerCount.Value or i) / faction.MinerLimit) * math.pi * 2
			local pos = base:GetPivot().Position + Vector3.new(math.cos(angle) * 12, 0, math.sin(angle) * 12)
			spawnUnit(player, "Miner", pos, nil, base)
		end
	end
	FactionServer.SpawnMiners = spawnMiners

	ctx.deny, ctx.spawnUnit, ctx.setSpeedMult, ctx.findBuilding = deny, spawnUnit, setSpeedMult, findBuilding

	-- Механика героев: по модулю на фракцию (Init / OnSummon / Abilities[клавиша])
	local Heroes = {}
	local heroFolder = script.Parent:WaitForChild("Heroes")
	for _, info in Registry.List do
		local module = heroFolder:FindFirstChild(info.Id)
		Heroes[info.Id] = module and require(module) or {}
		if Heroes[info.Id].Init then Heroes[info.Id].Init(ctx) end
	end

	-- 1. СОЗДАНИЕ ЮНИТА (Нексус: добытчик, Барак: боевые юниты)
	createUnitEvent.OnServerEvent:Connect(function(player, building, spawnPosition, unitName)
		if typeof(building) ~= "Instance" or typeof(spawnPosition) ~= "Vector3" or type(unitName) ~= "string" then return end
		if not ctx.isValidPosition(spawnPosition) then return end

		local faction = Registry.Of(player)
		local def = faction.Units[unitName]
		local owner = building:FindFirstChild("Owner")
		local fromOk = def and (building.Name == def.From or (unitName == "Miner" and faction.Bases[building.Name]))
		if not fromOk or not owner or owner.Value ~= player.Name then return end
		if (building:GetPivot().Position - spawnPosition).Magnitude > MAX_SPAWN_DISTANCE then return end
		if def.Requires and not findBuilding(player.Name, def.Requires) then
			return deny(player, "Сначала постройте: " .. (faction.Buildings[def.Requires].Title or def.Requires))
		end

		local template = faction.Template("Units", unitName)
		local stats = player:FindFirstChild("leaderstats")
		local gold = stats and stats:FindFirstChild("Gold")
		local milCount = stats and stats:FindFirstChild("MilitaryCount")
		local milLimit = stats and stats:FindFirstChild("MilitaryLimit")
		if not template or not gold or not milCount or not milLimit then return end

		local isMiner = def.Slots == 0
		local minerCount = building:FindFirstChild("MinerCount")
		if isMiner and minerCount and minerCount.Value >= faction.MinerLimit then
			return deny(player, "Достигнут лимит добытчиков")
		end
		if not isMiner and milCount.Value + def.Slots > milLimit.Value then
			return deny(player, "Не хватает лимита армии, постройте Казармы")
		end

		local costTag = template:FindFirstChild("Cost")
		local cost = def.Cost or (costTag and costTag.Value) or faction.DefaultCost
		if gold.Value < cost then return deny(player, "Не хватает золота: нужно " .. cost) end

		gold.Value -= cost
		milCount.Value += def.Slots
		if isMiner and minerCount then minerCount.Value += 1 end

		local pos
		if isMiner then
			local count = minerCount and minerCount.Value or 1
			local angle = (count / faction.MinerLimit) * math.pi * 2
			pos = building:GetPivot().Position + Vector3.new(math.cos(angle) * 12, 0, math.sin(angle) * 12)
		else
			pos = spawnPosition + Vector3.new((math.random() - 0.5) * 6, 0, (math.random() - 0.5) * 6)
		end

		spawnUnit(player, unitName, pos, nil, isMiner and building or nil)
	end)

	-- 2. КОМАНДА НА СТРОИТЕЛЬСТВО (рабочий идёт и строит, золото списывается сразу)
	buildEvent.OnServerEvent:Connect(function(player, unitsTable, targetPosition, buildingType)
		if type(unitsTable) ~= "table" or typeof(targetPosition) ~= "Vector3" or not ctx.isValidPosition(targetPosition) then return end

		local faction = Registry.Of(player)
		local def = faction.Buildings[buildingType]
		if not def then return end
		if def.Requires and not findBuilding(player.Name, def.Requires) then
			return deny(player, "Сначала постройте: " .. (faction.Buildings[def.Requires].Title or def.Requires))
		end

		local template = faction.Template("Buildings", buildingType .. "Template")
		local gold = ctx.getGold(player)
		if not template or not gold then return end
		if gold.Value < def.Cost then return deny(player, "Не хватает золота: нужно " .. def.Cost) end

		local _, size = template:GetBoundingBox()
		local pending = {}
		for _, fsm in fsms do
			if fsm.CurrentState == "Constructing" and fsm.BuildTarget then
				table.insert(pending, fsm.BuildTarget)
			end
		end

		if not faction.CanPlace(targetPosition, size, pending) then
			return deny(player, "Здесь нельзя строить: мало места")
		end

		for _, unit in ctx.getOwnedUnits(player, unitsTable) do
			if faction.Workers[unit.Name] then
				gold.Value -= def.Cost
				fsms[unit]:ChangeState("Constructing", targetPosition, buildingType, function()
					if gold.Parent then gold.Value += def.Cost end
				end)
				break
			end
		end
	end)

	-- 3. ФИЗИЧЕСКИЙ СПАВН ЗДАНИЯ (вызывается состоянием Constructing по окончании таймера)
	spawnBuilding.Event:Connect(function(worker, groundPosition, buildingType)
		local faction = Registry.OfUnit(worker)
		local def = faction.Buildings[buildingType]
		local template = faction.Template("Buildings", tostring(buildingType) .. "Template")
		if not def or not template then
			warn("Шаблон здания " .. tostring(buildingType) .. "Template не найден у фракции " .. faction.Id)
			return
		end

		local building = template:Clone()
		building.Name = buildingType
		Base.ApplyStats(building, def.Stats)
		local _, size = building:GetBoundingBox()
		building:PivotTo(CFrame.new(groundPosition + Vector3.new(0, size.Y / 2, 0)))

		local workerOwner = worker:FindFirstChild("Owner")
		local ownerName = workerOwner and workerOwner.Value or ""
		setValue(building, "Owner", "StringValue", ownerName)

		building.Parent = getFolder("Buildings")
		local isBase = faction.Bases[buildingType]
		if isBase then ctx.setupBase(building) else ctx.createHealthBar(building, true) end -- у базы свой счётчик добытчиков и полоска

		local player = Players:FindFirstChild(ownerName)
		local stats = player and player:FindFirstChild("leaderstats")
		local limit = stats and stats:FindFirstChild("MilitaryLimit")
		local bonus = def.Limit or 0
		if limit then limit.Value += bonus end

		building.Destroying:Connect(function()
			if limit then limit.Value = math.max(0, limit.Value - bonus) end
		end)

		local health = not isBase and building:FindFirstChild("Health")
		if health then
			health.Changed:Connect(function(hp)
				if hp > 0 or not building.Parent then return end
				local explosion = Instance.new("Explosion")
				explosion.Position = building:GetPivot().Position
				explosion.BlastPressure = 0
				explosion.DestroyJointRadiusPercent = 0
				explosion.Parent = workspace
				building:Destroy()
			end)
		end
	end)

	-- 4. ГЕРОЙ: призывается у Нексуса за золото при наличии нужного здания
	local function summonHero(player, free)
		local faction = Registry.Of(player)
		local heroDef = faction.Hero

		if player:GetAttribute("HasHero") then return deny(player, "Герой уже призван") end
		if os.clock() < (player:GetAttribute("HeroReadyAt") or 0) then return deny(player, "Герой ещё возрождается") end
		if not free and heroDef.Requires and not findBuilding(player.Name, heroDef.Requires) then
			return deny(player, "Сначала постройте: " .. (faction.Buildings[heroDef.Requires].Title or heroDef.Requires))
		end

		local stats = player:FindFirstChild("leaderstats")
		local gold = stats and stats:FindFirstChild("Gold")
		local milCount = stats and stats:FindFirstChild("MilitaryCount")
		local milLimit = stats and stats:FindFirstChild("MilitaryLimit")
		local nexus = findBase(player.Name)
		if not gold or not milCount or not milLimit or not nexus then return end

		if not free and milCount.Value + heroDef.Slots > milLimit.Value then return deny(player, "Не хватает лимита армии") end
		if not free and gold.Value < heroDef.Cost then return deny(player, "Не хватает золота: нужно " .. heroDef.Cost) end

		local hero = spawnUnit(player, "Hero", nexus:GetPivot().Position + Vector3.new(14, 0, 0), heroDef.Slots)
		if not hero then return end

		if not free then gold.Value -= heroDef.Cost end
		milCount.Value += heroDef.Slots
		player:SetAttribute("HasHero", true)
		hero.Destroying:Connect(function()
			player:SetAttribute("HasHero", nil)
			player:SetAttribute("HeroReadyAt", os.clock() + heroDef.Cooldown)
		end)

		local module = Heroes[faction.Id]
		if module.OnSummon then module.OnSummon(ctx, player, hero) end
	end

	FactionServer.SummonHero = summonHero -- ServerUnitManager зовёт её для героев, которые появляются со старта
	remote("SummonHeroEvent").OnServerEvent:Connect(function(player) summonHero(player, false) end)

	-- 4.1. СПОСОБНОСТИ ГЕРОЯ (нужен выделенный герой; клавиши описаны в Faction.Hero.Abilities)
	remote("HeroAbilityEvent").OnServerEvent:Connect(function(player, unitsTable, key)
		if type(unitsTable) ~= "table" or type(key) ~= "string" then return end

		local faction = Registry.Of(player)
		local ability = Heroes[faction.Id].Abilities and Heroes[faction.Id].Abilities[key]
		if not ability or not faction.Hero.Abilities[key] then return end

		local units = ctx.getOwnedUnits(player, unitsTable)
		for _, unit in units do
			if unit.Name == "Hero" then
				ability(ctx, player, unit, units)
				return
			end
		end
	end)

	-- 4.5. ПРОДАЖА ЗДАНИЯ (нужен выделенный рабочий)
	remote("SellBuildingEvent").OnServerEvent:Connect(function(player, unitsTable, building)
		if type(unitsTable) ~= "table" or typeof(building) ~= "Instance" then return end

		local faction = Registry.Of(player)
		local def = faction.Buildings[building.Name]
		local owner = building:FindFirstChild("Owner")
		if not def or building.Parent ~= workspace:FindFirstChild("Buildings") then return end
		if not owner or owner.Value ~= player.Name then return end
		if faction.Bases[building.Name] and ctx.countBases(player.Name) <= 1 then
			return deny(player, "Нельзя продать последнюю базу")
		end

		local worker
		for _, unit in ctx.getOwnedUnits(player, unitsTable) do
			if faction.Workers[unit.Name] then worker = unit break end
		end
		if not worker then return end

		fsms[worker]:ChangeState("Selling", building, function()
			if not building.Parent then return end -- уже продано другим рабочим
			local gold = ctx.getGold(player)
			if gold then gold.Value += math.floor(def.Cost * faction.SellRefund) end
			building:Destroy() -- Destroying сам вернёт бонус к лимиту армии
		end)
	end)

	-- 4.6. ОТМЕНА СТРОИТЕЛЬСТВА (OnExit состояния Constructing возвращает золото)
	remote("CancelBuildEvent").OnServerEvent:Connect(function(player, unitsTable)
		if type(unitsTable) ~= "table" then return end
		for _, unit in ctx.getOwnedUnits(player, unitsTable) do
			local fsm = fsms[unit]
			if fsm.CurrentState == "Constructing" then fsm:ChangeState("Idle") end
		end
	end)

	-- 5. ПАССИВНЫЙ ДОХОД ОТ ДОБЫТЧИКОВ
	task.spawn(function()
		while true do
			task.wait(Base.Defaults.IncomeInterval)

			local counts = {}
			for unit in fsms do
				local owner = unit.Name == "Miner" and unit:FindFirstChild("Owner")
				if owner and owner.Value ~= "" then
					counts[owner.Value] = (counts[owner.Value] or 0) + 1
				end
			end

			for name, n in counts do
				local player = Players:FindFirstChild(name)
				local gold = player and ctx.getGold(player)
				if gold then gold.Value += n * Registry.Of(player).MinerIncome end
			end
		end
	end)
end

return FactionServer
