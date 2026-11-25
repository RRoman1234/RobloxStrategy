-- ServerScriptService/FSM/Heroes/Priests
-- Благодать: раз в 0.5 с пересчитываем баффы всех юнитов жреца. Бафф = атрибуты DamageMult / DamageTaken / SpeedMult.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Faction = require(ReplicatedStorage:WaitForChild("Factions"):WaitForChild("Registry")).Get("Priests")
local Aura, Vow = Faction.Hero.Aura, Faction.Hero.Vow
local TICK = 0.5

local Priests = { Abilities = {} }

local function posOf(model)
	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	return part and part.Position
end

local function heal(unit, amount)
	local hp, max = unit:FindFirstChild("Health"), unit:GetAttribute("MaxHealth")
	if hp and max and hp.Value > 0 then hp.Value = math.min(max, hp.Value + amount) end
end

local function apply(ctx, g)
	local hero = g.hero
	local L, heroPos, vow
	if hero then
		L = Aura.Levels[g.player:GetAttribute("AuraLevel") or 1]
		heroPos = posOf(hero)
		if os.clock() < (hero:GetAttribute("VowUntil") or 0) then vow = hero:GetAttribute("Vow") end
	end

	-- Источники ауры: герой и Херувимы, которые сами стоят в его ауре
	local sources, radiusOf = {}, {}
	if L and heroPos then
		table.insert(sources, { heroPos, L.Radius })
		radiusOf[hero] = L.Radius
		hero:SetAttribute("AuraLevel", g.player:GetAttribute("AuraLevel") or 1)
		for _, u in g.units do
			local p = u.Name == "Cherub" and posOf(u)
			if p and (p - heroPos).Magnitude <= L.Radius then
				table.insert(sources, { p, Aura.CherubRadius })
				radiusOf[u] = Aura.CherubRadius
			end
		end
	end

	local pos, inAura = {}, {}
	for _, u in g.units do
		local p = posOf(u)
		pos[u] = p
		if p then
			for _, s in sources do
				if (p - s[1]).Magnitude <= s[2] then inAura[u] = true break end
			end
		end
	end

	for _, u in g.units do
		local d, s, t = 1, 1, 1
		if inAura[u] then
			d, s, t = L.Damage, L.Speed, L.Taken
			t *= Aura.UnitBonus[u.Name] or 1
			local m = vow and Vow[vow]
			if m then
				d *= m.Damage or 1
				s *= m.Speed or 1
				t *= m.Taken or 1
			end
			if L.Regen then heal(u, (u:GetAttribute("MaxHealth") or 0) * L.Regen * TICK) end
		else
			d *= Aura.OutOfAura[u.Name] or 1
		end
		u:SetAttribute("DamageMult", d)
		u:SetAttribute("DamageTaken", t)
		ctx.setSpeedMult(u, s)
		u:SetAttribute("AuraRadius", radiusOf[u]) -- клиент рисует по ним кольцо (HeroEffects)
		u:SetAttribute("AuraVow", radiusOf[u] and vow or nil)
	end

	-- Целитель работает только внутри ауры и лечит только тех, кто тоже в ней
	for _, healer in g.units do
		if healer.Name == "Healer" and inAura[healer] then
			for _, u in g.units do
				if u ~= healer and inAura[u] and (pos[u] - pos[healer]).Magnitude <= Aura.HealRadius then
					heal(u, Aura.HealPerSecond * TICK)
				end
			end
		end
	end
end

function Priests.Init(ctx)
	task.spawn(function()
		while true do
			task.wait(TICK)

			local groups = {}
			for unit in ctx.activeUnitFSMs do
				local tag = unit:FindFirstChild("Owner")
				local player = tag and Players:FindFirstChild(tag.Value)
				if player and player:GetAttribute("Faction") == "Priests" then
					local g = groups[player] or { player = player, units = {} }
					groups[player] = g
					table.insert(g.units, unit)
					if unit.Name == "Hero" then g.hero = unit end
				end
			end

			for _, g in groups do
				local ok, err = pcall(apply, ctx, g)
				if not ok then warn("Priests aura: " .. tostring(err)) end
			end
		end
	end)
end

local function setVow(ctx, player, hero, name)
	local now = os.clock()
	if now < (hero:GetAttribute("VowReadyAt") or 0) then return ctx.deny(player, "Обет ещё не готов") end
	hero:SetAttribute("Vow", name)
	hero:SetAttribute("VowUntil", now + Vow.Duration)
	hero:SetAttribute("VowReadyAt", now + Vow.Cooldown)
	hero:SetAttribute("VowEnd", workspace:GetServerTimeNow() + Vow.Duration)
	hero:SetAttribute("VowReadyEnd", workspace:GetServerTimeNow() + Vow.Cooldown)
end

function Priests.Abilities.Q(ctx, player, hero) setVow(ctx, player, hero, "Fortitude") end
function Priests.Abilities.E(ctx, player, hero) setVow(ctx, player, hero, "Retribution") end

-- Уровень ауры лежит на игроке: смерть героя его не сбрасывает
function Priests.Abilities.F(ctx, player)
	local level = player:GetAttribute("AuraLevel") or 1
	local cost = Aura.UpgradeCost[level]
	if not cost then return ctx.deny(player, "Благодать уже максимальна") end

	local gold = ctx.getGold(player)
	if not gold or gold.Value < cost then return ctx.deny(player, "Не хватает золота: нужно " .. cost) end
	gold.Value -= cost
	player:SetAttribute("AuraLevel", level + 1)
end

return Priests
