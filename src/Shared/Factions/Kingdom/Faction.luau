-- ReplicatedStorage/Factions/Kingdom/Faction
-- Королевство. Казармы -> 4 простых юнита. Оружейная -> Рыцарский зал (юниты казны), Соколятня -> Гнездо грифонов (летуны).
-- Королева появляется со старта и ведёт казну с процентами.
return require(script.Parent.Parent.Base).new(script.Parent, {
	Nexus = { Stats = { Health = 1500 } },
	Bases = { Nexus = true, Outpost = true }, -- Застава заменяет дополнительные Нексусы

	Buildings = {
		Barracks   = { Key = "1", Title = "Казармы", Cost = 100, BuildTime = 20, Limit = 4, Stats = { Health = 500 } },
		Outpost    = { Key = "2", Title = "Застава", Cost = 300, BuildTime = 40, Limit = 2, Stats = { Health = 800 } }, -- база + потолок казны
		Armory     = { Key = "3", Title = "Оружейная", Cost = 150, BuildTime = 25, Requires = "Barracks", Stats = { Health = 400 } }, -- открывает Рыцарский зал
		KnightHall = { Key = "4", Title = "Рыцарский зал", Cost = 200, BuildTime = 30, Limit = 4, Requires = "Armory", Stats = { Health = 500 } },
		Mews       = { Key = "5", Title = "Соколятня", Cost = 150, BuildTime = 25, Requires = "Barracks", Stats = { Health = 400 } }, -- открывает Гнездо
		Aerie      = { Key = "6", Title = "Гнездо грифонов", Cost = 200, BuildTime = 30, Limit = 4, Requires = "Mews", Stats = { Health = 500 } },
	},

	Units = {
		-- Казармы: простые
		Squire = { -- Посвящение превращает его в Рыцаря
			From = "Barracks", Key = "1", Title = "Оруженосец", Slots = 1, Cost = 55,
			Stats = { Health = 120, Damage = 10, AttackRange = 5, AttackCooldown = 1, Speed = 16, CanAttack = "Ground", MovementType = "Ground" },
		},
		Pikeman = {
			From = "Barracks", Key = "2", Title = "Пикинёр", Slots = 1, Cost = 65,
			Stats = { Health = 150, Damage = 12, AttackRange = 6, AttackCooldown = 1.1, Speed = 14, CanAttack = "Ground", MovementType = "Ground" },
		},
		Archer = {
			From = "Barracks", Key = "3", Title = "Лучник", Slots = 1, Cost = 70,
			Stats = { Health = 85, Damage = 13, AttackRange = 24, AttackCooldown = 1.2, Speed = 15, CanAttack = "Both", MovementType = "Ground" },
		},
		Crossbowman = {
			From = "Barracks", Key = "4", Title = "Арбалетчик", Slots = 1, Cost = 85,
			Stats = { Health = 100, Damage = 22, AttackRange = 26, AttackCooldown = 2, Speed = 13, CanAttack = "Ground", MovementType = "Ground" },
		},

		-- Рыцарский зал: юниты, завязанные на казну
		Knight = {
			From = "KnightHall", Key = "1", Title = "Рыцарь", Slots = 3, Cost = 250,
			Stats = { Health = 650, Damage = 30, AttackRange = 5, AttackCooldown = 1.2, Speed = 14, CanAttack = "Ground", MovementType = "Ground" },
		},
		Horseman = { -- Plunder: доля урона по зданиям, которая идёт в казну
			From = "KnightHall", Key = "2", Title = "Конник", Slots = 2, Cost = 120,
			Stats = { Health = 170, Damage = 14, AttackRange = 5, AttackCooldown = 0.8, Speed = 26, Plunder = 0.15, CanAttack = "Ground", MovementType = "Ground" },
		},
		Herald = { -- каждый живой Герольд поднимает потолок казны
			From = "KnightHall", Key = "3", Title = "Герольд", Slots = 1, Cost = 90, Requires = "Outpost",
			Stats = { Health = 90, Speed = 15, CanAttack = "None", MovementType = "Ground" },
		},

		-- Гнездо грифонов: летуны
		Hawk = {
			From = "Aerie", Key = "1", Title = "Ястреб", Slots = 1, Cost = 80,
			Stats = { Health = 70, Damage = 8, AttackRange = 9, AttackCooldown = 0.8, Speed = 28, CanAttack = "Ground", MovementType = "Air" },
		},
		Griffon = {
			From = "Aerie", Key = "2", Title = "Грифонник", Slots = 3, Cost = 180,
			Stats = { Health = 200, Damage = 18, AttackRange = 10, AttackCooldown = 1, Speed = 22, CanAttack = "Both", MovementType = "Air" },
		},
		PegasusKnight = {
			From = "Aerie", Key = "3", Title = "Рыцарь на пегасе", Slots = 3, Cost = 230,
			Stats = { Health = 380, Damage = 28, AttackRange = 6, AttackCooldown = 1.2, Speed = 20, CanAttack = "Both", MovementType = "Air" },
		},
	},

	Hero = {
		Title = "Королева", Slots = 0, Cost = 150, StartsSpawned = true, Cooldown = 60, -- Cost = цена воскрешения; слоты армии не занимает
		Stats = { Health = 450, Damage = 14, AttackRange = 6, AttackCooldown = 1, Speed = 16, CanAttack = "Both" },
		Abilities = { Q = "Вложить в казну", E = "Забрать казну", F = "Посвящение", G = "Наём" },

		Treasury = {
			BaseCap = 300, PerOutpost = 200, PerHerald = 100, MaxHeralds = 3,
			Rate = 0.10,        -- рост в минуту, пока казна ниже потолка
			DepositStep = 100,
			LockTime = 120,     -- забрать раньше этого срока после вклада = штраф
			EarlyLoss = 0.15,
			DeathLoss = 0.5,    -- доля казны, сгорающая со смертью Королевы
		},
		Dubbing = { Cost = 130, Max = 3, Range = 25, Cooldown = 20 }, -- Оруженосцы рядом -> Рыцари
		Hire = { Cost = 250, Count = 3, Duration = 30, Cooldown = 60 }, -- временные Рыцари без слотов армии
	},
})
