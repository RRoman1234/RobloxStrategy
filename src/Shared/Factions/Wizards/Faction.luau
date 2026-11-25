-- ReplicatedStorage/Factions/Wizards/Faction
-- Волшебники. Казармы -> 4 простых юнита. Библиотека -> Чертог чародеев (юниты героя), Обсерватория -> Небесная башня (летуны).
-- Архимаг поглощает юнитов Чертога: до 25, каждые 5 одного типа = +1 уровень его эффекта.
-- Модели рядом: Wizards/Buildings (<Имя>Template), Wizards/Units (Hero, Miner, <юнит>).
return require(script.Parent.Parent.Base).new(script.Parent, {
	Nexus = { Stats = { Health = 1500 } },

	Buildings = {
		Barracks    = { Key = "1", Title = "Казармы", Cost = 100, BuildTime = 20, Limit = 4, Stats = { Health = 500 } },
		Library     = { Key = "2", Title = "Библиотека", Cost = 150, BuildTime = 25, Requires = "Barracks", Stats = { Health = 400 } }, -- открывает Чертог
		ArcaneHall  = { Key = "3", Title = "Чертог чародеев", Cost = 200, BuildTime = 30, Limit = 4, Requires = "Library", Stats = { Health = 500 } },
		Observatory = { Key = "4", Title = "Обсерватория", Cost = 150, BuildTime = 25, Requires = "Barracks", Stats = { Health = 400 } }, -- открывает Башню
		SkyTower    = { Key = "5", Title = "Небесная башня", Cost = 200, BuildTime = 30, Limit = 4, Requires = "Observatory", Stats = { Health = 500 } },
		Nexus       = { Key = "6", Title = "Нексус", Cost = 400, BuildTime = 45, Stats = { Health = 1500 } }, -- дополнительная база
	},

	Units = {
		-- Казармы: простые
		Student = {
			From = "Barracks", Key = "1", Title = "Ученик", Slots = 1, Cost = 60,
			Stats = { Health = 100, Damage = 12, AttackRange = 22, AttackCooldown = 1, Speed = 16, CanAttack = "Both", MovementType = "Ground" },
		},
		Warden = {
			From = "Barracks", Key = "2", Title = "Страж", Slots = 1, Cost = 70,
			Stats = { Health = 240, Damage = 14, AttackRange = 5, AttackCooldown = 1.1, Speed = 14, CanAttack = "Ground", MovementType = "Ground" },
		},
		Wandbearer = {
			From = "Barracks", Key = "3", Title = "Жезлоносец", Slots = 1, Cost = 75,
			Stats = { Health = 90, Damage = 18, AttackRange = 24, AttackCooldown = 1.4, Speed = 15, CanAttack = "Ground", MovementType = "Ground" },
		},
		Scout = {
			From = "Barracks", Key = "4", Title = "Разведчик", Slots = 1, Cost = 45,
			Stats = { Health = 70, Damage = 8, AttackRange = 6, AttackCooldown = 0.7, Speed = 24, CanAttack = "Ground", MovementType = "Ground" },
		},

		-- Чертог чародеев: юниты, питающие Архимага
		Golem = {
			From = "ArcaneHall", Key = "1", Title = "Голем", Slots = 2, Cost = 130,
			Stats = { Health = 450, Damage = 18, AttackRange = 5, AttackCooldown = 1.4, Speed = 11, CanAttack = "Ground", MovementType = "Ground" },
		},
		Elementalist = {
			From = "ArcaneHall", Key = "2", Title = "Стихийник", Slots = 2, Cost = 140,
			Stats = { Health = 90, Damage = 24, AttackRange = 20, AttackCooldown = 1.8, Speed = 14, AoERadius = 6, CanAttack = "Ground", MovementType = "Ground" },
		},
		Spellbinder = {
			From = "ArcaneHall", Key = "3", Title = "Чародей", Slots = 2, Cost = 120,
			Stats = { Health = 110, Damage = 22, AttackRange = 20, AttackCooldown = 1.3, Speed = 15, CanAttack = "Both", MovementType = "Ground" },
		},

		-- Небесная башня: летуны
		Windwing = {
			From = "SkyTower", Key = "1", Title = "Ветрокрыл", Slots = 1, Cost = 90,
			Stats = { Health = 80, Damage = 10, AttackRange = 8, AttackCooldown = 0.7, Speed = 26, CanAttack = "Ground", MovementType = "Air" },
		},
		StormEagle = {
			From = "SkyTower", Key = "2", Title = "Грозовой орёл", Slots = 2, Cost = 150,
			Stats = { Health = 140, Damage = 20, AttackRange = 18, AttackCooldown = 1.2, Speed = 20, CanAttack = "Both", MovementType = "Air" },
		},
		Aeromancer = {
			From = "SkyTower", Key = "3", Title = "Аэромант", Slots = 2, Cost = 130,
			Stats = { Health = 85, Damage = 16, AttackRange = 22, AttackCooldown = 1.2, Speed = 18, CanAttack = "Both", MovementType = "Air" },
		},
	},

	Hero = {
		Title = "Архимаг", Slots = 3, Cost = 300, Requires = "ArcaneHall", Cooldown = 90,
		Stats = { Health = 700, Damage = 30, AttackRange = 14, AttackCooldown = 1, Speed = 15, CanAttack = "Both" },
		Abilities = { Q = "Поглотить армию" }, -- поглощает ВЫДЕЛЕННЫХ юнитов рядом с героем

		-- Эффекты только на самого героя. Массивы = значение на уровне 1..5 (рост замедляется: широкий набор конкурирует с глубоким).
		Absorb = {
			Capacity = 25, Step = 5, Range = 40,
			Colors = { -- цвет шара вокруг героя и строки в панели поглощённых
				Golem = Color3.fromRGB(190, 140, 90),
				Elementalist = Color3.fromRGB(255, 110, 40),
				Spellbinder = Color3.fromRGB(190, 120, 255),
			},
			Effects = {
				Golem        = { DamageTaken = { 0.90, 0.82, 0.75, 0.69, 0.65 } }, -- множитель входящего урона
				Elementalist = { AoERadius = { 4, 6, 8, 10, 12 }, AoEShare = { 0.3, 0.4, 0.5, 0.6, 0.7 } }, -- единственный AoE
				Spellbinder  = { DamageMult = { 1.15, 1.30, 1.42, 1.52, 1.60 }, AttackSpeedMult = { 1.06, 1.12, 1.17, 1.21, 1.25 } },
			},
		},
	},
})
