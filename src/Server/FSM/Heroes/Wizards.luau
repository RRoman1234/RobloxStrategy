-- ServerScriptService/FSM/Heroes/Wizards
-- Архимаг поглощает выделенных юнитов рядом. Счётчики лежат в атрибутах героя: Abs_<ТипЮнита>.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Faction = require(ReplicatedStorage:WaitForChild("Factions"):WaitForChild("Registry")).Get("Wizards")
local Absorb = Faction.Hero.Absorb

local Wizards = { Abilities = {} }

local function total(hero)
	local n = 0
	for unitName in Absorb.Effects do
		n += hero:GetAttribute("Abs_" .. unitName) or 0
	end
	return n
end

-- Уровень эффекта = поглощённые // Step; уровень 0 = эффекта нет
local function recalc(ctx, hero)
	for unitName, effect in Absorb.Effects do
		local count = hero:GetAttribute("Abs_" .. unitName) or 0
		for attr, values in effect do
			local level = math.min(count // Absorb.Step, #values)
			local value = level > 0 and values[level] or nil
			if attr == "SpeedMult" then
				ctx.setSpeedMult(hero, value or 1)
			else
				hero:SetAttribute(attr, value)
			end
		end
	end
end

function Wizards.Abilities.Q(ctx, player, hero, units)
	local milCount = player.leaderstats.MilitaryCount
	local heroPos = hero:GetPivot().Position
	local count, taken = total(hero), 0

	for _, unit in units do
		if count >= Absorb.Capacity then break end
		local def = Faction.Units[unit.Name]
		if def and Absorb.Effects[unit.Name] and (unit:GetPivot().Position - heroPos).Magnitude <= Absorb.Range then
			local key = "Abs_" .. unit.Name
			hero:SetAttribute(key, (hero:GetAttribute(key) or 0) + 1)
			count += 1
			taken += 1
			milCount.Value += def.Slots -- слот остаётся занятым: Destroying юнита его вернёт
			unit:Destroy()
		end
	end

	if taken == 0 then return ctx.deny(player, "Выделите юнитов рядом с героем") end
	recalc(ctx, hero)
end

-- Смерть героя: поглощённые высыпаются вокруг (их слоты всё это время были заняты)
function Wizards.OnSummon(ctx, player, hero)
	hero.Destroying:Connect(function()
		local pos = hero:GetPivot().Position
		local released = {}
		for unitName in Absorb.Effects do
			released[unitName] = hero:GetAttribute("Abs_" .. unitName) or 0
		end

		task.defer(function()
			if not player.Parent then return end
			for unitName, n in released do
				for _ = 1, n do
					ctx.spawnUnit(player, unitName, pos + Vector3.new(math.random(-10, 10), 0, math.random(-10, 10)))
				end
			end
		end)
	end)
end

return Wizards
