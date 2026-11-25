-- ReplicatedStorage/Factions/Registry
-- Какая фракция у игрока: атрибут "Faction" (его ставит сервер после выбора или из TeleportData лобби).
local Players = game:GetService("Players")

local Registry = {}

Registry.List = {
	{ Id = "Wizards", Title = "Волшебники", Hero = "Архимаг", Info = "Герой поглощает армию и растёт от её состава" },
	{ Id = "Priests", Title = "Жрецы", Hero = "Первосвященник", Info = "Слабый герой, армия сражается в его ауре" },
	{ Id = "Kingdom", Title = "Королевство", Hero = "Королева", Info = "Казна с процентами, мало юнитов, но элитных" },
}

local DEFAULT = "Wizards" -- пока фракция не выбрана, клиентский UI читает эту
local cache = {}

function Registry.Exists(id)
	for _, info in Registry.List do
		if info.Id == id then return true end
	end
	return false
end

function Registry.Get(id)
	if not Registry.Exists(id) then id = DEFAULT end
	if not cache[id] then
		cache[id] = require(script.Parent:WaitForChild(id):WaitForChild("Faction"))
	end
	return cache[id]
end

function Registry.Of(player)
	return Registry.Get(player and player:GetAttribute("Faction"))
end

-- Юнит или здание -> фракция его владельца
function Registry.OfUnit(model)
	local tag = model:FindFirstChild("Owner")
	return Registry.Of(tag and Players:FindFirstChild(tag.Value))
end

-- Таблица, которая при каждом обращении читает текущую фракцию игрока (для клиентских скриптов)
function Registry.Proxy(player)
	return setmetatable({}, {
		__index = function(_, key) return Registry.Of(player)[key] end,
	})
end

return Registry
