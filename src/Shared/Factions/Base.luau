-- ReplicatedStorage/Factions/Base
-- Общее для всех фракций: значения по умолчанию, шаблоны, проверка места под здание.
-- Фракция = папка с ModuleScript "Faction", который возвращает Base.new(script.Parent, { данные }).
local Base = {}

Base.Defaults = {
	BuildingGap = 3,
	MinerLimit = 12, -- добытчиков на один Нексус
	MinerIncome = 1, -- золота в секунду с добытчика (50-золотой добытчик окупается за ~50 с)
	IncomeInterval = 1,
	BuildTime = 15, -- секунд на стройку, если у здания нет своего BuildTime
	StartMiners = 4, -- добытчиков вокруг стартовой базы
	Bases = { Nexus = true }, -- здания-базы: создают добытчиков, потеря последней = поражение
	DefaultCost = 50, -- если у шаблона юнита нет значения Cost
	SellRefund = 0.5, -- доля цены здания, которую возвращаем при продаже
	Workers = { Miner = true }, -- Miner и добывает, и строит
}

function Base.SetValue(parent, name, class, value)
	local v = parent:FindFirstChild(name) or Instance.new(class)
	v.Name = name
	v.Value = value
	v.Parent = parent
end

-- Stats из данных фракции перекрывают значения в шаблоне модели (Health, Damage, Speed, CanAttack...)
function Base.ApplyStats(model, stats)
	if not stats then return end
	for name, value in stats do
		Base.SetValue(model, name, type(value) == "number" and "NumberValue" or "StringValue", value)
	end
end

function Base.new(folder, data)
	local F = table.clone(Base.Defaults)
	for k, v in data do F[k] = v end

	F.Id = folder.Name
	F.Name = folder.Name
	F.Nexus = F.Nexus or {}
	F.Units.Miner = F.Units.Miner or { From = "Nexus", Key = "1", Title = "Добытчик", Slots = 0, Cost = 50 }

	F.BuildingByKey = {} -- [key] = имя здания
	F.Production = {}    -- [здание][key] = имя юнита
	for name, b in F.Buildings do
		F.BuildingByKey[b.Key] = name
	end
	for name, u in F.Units do
		local slot = F.Production[u.From] or {}
		F.Production[u.From] = slot
		assert(slot[u.Key] == nil, `{F.Id}: клавиша {u.Key} у {u.From} занята`)
		assert(not u.Requires or F.Buildings[u.Requires], `{F.Id}: {name} требует неизвестное здание {u.Requires}`)
		slot[u.Key] = name
	end
	for base in F.Bases do -- на каждой базе добытчик создаётся под той же клавишей
		F.Production[base] = F.Production[base] or {}
		F.Production[base][F.Units.Miner.Key] = "Miner"
	end
	assert(not F.Hero.Requires or F.Buildings[F.Hero.Requires], `{F.Id}: герою нужно неизвестное здание`)

	-- kind: "Buildings" | "Units"
	function F.Template(kind, name)
		local f = folder:FindFirstChild(kind)
		return f and f:FindFirstChild(name)
	end

	-- Свободно ли место под здание size в точке position (одинаково для клиента и сервера).
	-- pendingTargets: точки, куда рабочие уже идут строить.
	function F.CanPlace(position, size, pendingTargets)
		local gap = F.BuildingGap
		local function blocked(center, other)
			return math.abs(position.X - center.X) < (size.X + other.X) / 2 + gap
				and math.abs(position.Z - center.Z) < (size.Z + other.Z) / 2 + gap
		end

		local buildings = workspace:FindFirstChild("Buildings")
		if buildings then
			for _, b in buildings:GetChildren() do
				if b:IsA("Model") then
					local cf, s = b:GetBoundingBox()
					if blocked(cf.Position, s) then return false end
				elseif b:IsA("BasePart") and blocked(b.Position, b.Size) then
					return false
				end
			end
		end

		for _, c in workspace:GetChildren() do
			if c.Name == "ConstructionSite" and c:IsA("BasePart") and blocked(c.Position, c.Size) then
				return false
			end
		end

		if pendingTargets then
			for _, target in pendingTargets do
				if blocked(target, size) then return false end
			end
		end

		return true
	end

	return F
end

return Base
