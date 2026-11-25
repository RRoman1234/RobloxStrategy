-- ServerScriptService/FSM/Heroes/Kingdom
-- Казна: атрибуты игрока Treasury / TreasuryCap (клиент рисует их в ResourceUI).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Faction = require(ReplicatedStorage:WaitForChild("Factions"):WaitForChild("Registry")).Get("Kingdom")
local T, Dub, Hire = Faction.Hero.Treasury, Faction.Hero.Dubbing, Faction.Hero.Hire

local Kingdom = { Abilities = {} }

local function ownerOf(model)
	local tag = model:FindFirstChild("Owner")
	return tag and tag.Value
end

local function step(ctx)
	local info = {}
	local function get(owner)
		info[owner] = info[owner] or { outposts = 0, heralds = 0, plunder = 0 }
		return info[owner]
	end

	for unit in ctx.activeUnitFSMs do
		local owner = ownerOf(unit)
		if owner then
			if unit.Name == "Herald" then get(owner).heralds += 1 end
			local loot = unit:GetAttribute("PlunderGold") -- Attacking копит добычу Конников
			if loot then
				get(owner).plunder += loot
				unit:SetAttribute("PlunderGold", nil)
			end
		end
	end

	local buildings = workspace:FindFirstChild("Buildings")
	if buildings then
		for _, b in buildings:GetChildren() do
			local owner = b.Name == "Outpost" and ownerOf(b)
			if owner then get(owner).outposts += 1 end
		end
	end

	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Faction") == "Kingdom" then
			local e = get(player.Name)
			local cap = T.BaseCap + e.outposts * T.PerOutpost + math.min(e.heralds, T.MaxHeralds) * T.PerHerald
			local amount = (player:GetAttribute("Treasury") or 0) + e.plunder
			if amount < cap then amount = math.min(cap, amount * (1 + T.Rate / 60)) end -- шаг = 1 секунда
			player:SetAttribute("Treasury", amount)
			player:SetAttribute("TreasuryCap", cap)
		end
	end
end

function Kingdom.Init(ctx)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(step, ctx)
			if not ok then warn("Kingdom treasury: " .. tostring(err)) end
		end
	end)
end

-- shortcut: со смертью Королевы казна только сгорает, врагу не достаётся (убийца не отслеживается), добавить, если понадобится
function Kingdom.OnSummon(ctx, player, hero)
	hero.Destroying:Connect(function()
		player:SetAttribute("Treasury", (player:GetAttribute("Treasury") or 0) * (1 - T.DeathLoss))
	end)
end

function Kingdom.Abilities.Q(ctx, player)
	local gold = ctx.getGold(player)
	local amount = player:GetAttribute("Treasury") or 0
	local free = (player:GetAttribute("TreasuryCap") or 0) - amount
	local deposit = gold and math.min(T.DepositStep, gold.Value, math.floor(free)) or 0
	if deposit <= 0 then return ctx.deny(player, "Казна заполнена или нет золота") end

	gold.Value -= deposit
	player:SetAttribute("Treasury", amount + deposit)
	player:SetAttribute("LastDepositAt", os.clock())
	player:SetAttribute("LockEnd", workspace:GetServerTimeNow() + T.LockTime)
end

function Kingdom.Abilities.E(ctx, player)
	local gold = ctx.getGold(player)
	local amount = player:GetAttribute("Treasury") or 0
	if not gold or amount < 1 then return ctx.deny(player, "Казна пуста") end

	local early = os.clock() - (player:GetAttribute("LastDepositAt") or -math.huge) < T.LockTime
	gold.Value += math.floor(amount * (early and 1 - T.EarlyLoss or 1))
	player:SetAttribute("Treasury", 0)
end

-- Посвящение: ближайшие Оруженосцы рядом с Королевой становятся Рыцарями
function Kingdom.Abilities.F(ctx, player, hero)
	local now = os.clock()
	if now < (player:GetAttribute("DubReadyAt") or 0) then return ctx.deny(player, "Посвящение ещё не готово") end

	local stats = player.leaderstats
	local gold, milCount, milLimit = stats.Gold, stats.MilitaryCount, stats.MilitaryLimit
	local heroPos = hero:GetPivot().Position
	local knight = Faction.Units.Knight
	local extra = knight.Slots - Faction.Units.Squire.Slots

	local squires = {}
	for unit in ctx.activeUnitFSMs do
		if unit.Name == "Squire" and ownerOf(unit) == player.Name
			and (unit:GetPivot().Position - heroPos).Magnitude <= Dub.Range then
			table.insert(squires, unit)
		end
	end

	local made = 0
	for _, squire in squires do
		if made >= Dub.Max or gold.Value < Dub.Cost or milCount.Value + extra > milLimit.Value then break end
		gold.Value -= Dub.Cost
		milCount.Value += knight.Slots
		ctx.spawnUnit(player, "Knight", squire:GetPivot().Position)
		squire:Destroy() -- Destroying вернёт слот Оруженосца
		made += 1
	end

	if made == 0 then return ctx.deny(player, "Нужны Оруженосцы рядом, золото и место в лимите") end
	player:SetAttribute("DubReadyAt", now + Dub.Cooldown)
	player:SetAttribute("DubReadyEnd", workspace:GetServerTimeNow() + Dub.Cooldown)
end

-- Наём: временные Рыцари без слотов армии
function Kingdom.Abilities.G(ctx, player, hero)
	local now = os.clock()
	if now < (player:GetAttribute("HireReadyAt") or 0) then return ctx.deny(player, "Наём ещё не готов") end

	local gold = ctx.getGold(player)
	if not gold or gold.Value < Hire.Cost then return ctx.deny(player, "Не хватает золота: нужно " .. Hire.Cost) end
	gold.Value -= Hire.Cost
	player:SetAttribute("HireReadyAt", now + Hire.Cooldown)
	player:SetAttribute("HireReadyEnd", workspace:GetServerTimeNow() + Hire.Cooldown)

	local base = hero:GetPivot().Position
	for i = 1, Hire.Count do
		local knight = ctx.spawnUnit(player, "Knight", base + Vector3.new((i - 2) * 6, 0, 8), 0)
		task.delay(Hire.Duration, function()
			if knight and knight.Parent then knight:Destroy() end
		end)
	end
end

return Kingdom
