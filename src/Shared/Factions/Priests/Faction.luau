-- ReplicatedStorage/Factions/Priests/Faction
-- Жрецы. Казармы -> 4 простых юнита. Часовня -> Монастырь (юниты ауры), Колокольня -> Чертог ангелов (летуны).
-- Хрупкий Первосвященник с аурой «Благодать», армия сражается рядом с ним.
return require(script.Parent.Parent.Base).new(script.Parent, {
	Nexus = { Stats = { Health = 1500 } },

	Buildings = {
		Barracks  = { Key = "1", Title = "Казармы", Cost = 100, BuildTime = 20, Limit = 4, Stats = { Health = 500 } },
		Chapel    = { Key = "2", Title = "Часовня", Cost = 150, BuildTime = 25, Requires = "Barracks", Stats = { Health = 400 } }, -- открывает Монастырь
		Monastery = { Key = "3", Title = "Монастырь", Cost = 200, BuildTime = 30, Limit = 4, Requires = "Chapel", Stats = { Health = 500 } },
		Belfry    = { Key = "4", Title = "Колокольня", Cost = 150, BuildTime = 25, Requires = "Barracks", Stats = { Health = 400 } }, -- открывает Чертог ангелов
		AngelHall = { Key = "5", Title = "Чертог ангелов", Cost = 200, BuildTime = 30, Limit = 4, Requires = "Belfry", Stats = { Health = 500 } },
		Nexus     = { Key = "6", Title = "Нексус", Cost = 400, BuildTime = 45, Stats = { Health = 1500 } }, -- дополнительная база
	},

	Units = {
		-- Казармы: простые
		Acolyte = {
			From = "Barracks", Key = "1", Title = "Послушник", Slots = 1, Cost = 50,
			Stats = { Health = 110, Damage = 10, AttackRange = 5, AttackCooldown = 1, Speed = 16, CanAttack = "Ground", MovementType = "Ground" },
		},
		Pilgrim = {
			From = "Barracks", Key = "2", Title = "Паломник", Slots = 1, Cost = 55,
			Stats = { Health = 80, Damage = 9, AttackRange = 18, AttackCooldown = 1.1, Speed = 16, CanAttack = "Ground", MovementType = "Ground" },
		},
		Guardian = {
			From = "Barracks", Key = "3", Title = "Страж веры", Slots = 1, Cost = 85,
			Stats = { Health = 260, Damage = 12, AttackRange = 5, AttackCooldown = 1.2, Speed = 13, CanAttack = "Ground", MovementType = "Ground" },
		},
		Inquisitor = {
			From = "Barracks", Key = "4", Title = "Инквизитор", Slots = 1, Cost = 80,
			Stats = { Health = 90, Damage = 14, AttackRange = 22, AttackCooldown = 1.3, Speed = 15, CanAttack = "Both", MovementType = "Ground" },
		},

		-- Монастырь: юниты, завязанные на ауру
		Templar = { -- в ауре получает ещё меньше урона (Aura.UnitBonus)
			From = "Monastery", Key = "1", Title = "Храмовник", Slots = 2, Cost = 120,
			Stats = { Health = 400, Damage = 14, AttackRange = 5, AttackCooldown = 1.2, Speed = 12, CanAttack = "Ground", MovementType = "Ground" },
		},
		Healer = { -- лечит только внутри ауры
			From = "Monastery", Key = "2", Title = "Целитель", Slots = 1, Cost = 110,
			Stats = { Health = 80, Speed = 15, CanAttack = "None", MovementType = "Ground" },
		},
		Trebuchet = { -- вне ауры бьёт втрое слабее (Aura.OutOfAura), по зданиям x2.5
			From = "Monastery", Key = "3", Title = "Святой требушет", Slots = 3, Cost = 200,
			Stats = { Health = 150, Damage = 60, AttackRange = 45, AttackCooldown = 3.5, Speed = 8, VsBuildings = 2.5, CanAttack = "Ground", MovementType = "Ground" },
		},

		-- Чертог ангелов: летуны
		Cherub = { -- летит впереди и «вытягивает» ауру (Aura.CherubRadius)
			From = "AngelHall", Key = "1", Title = "Херувим", Slots = 1, Cost = 100,
			Stats = { Health = 70, Damage = 8, AttackRange = 15, AttackCooldown = 1.2, Speed = 22, CanAttack = "Both", MovementType = "Air" },
		},
		Seraph = {
			From = "AngelHall", Key = "2", Title = "Серафим", Slots = 2, Cost = 140,
			Stats = { Health = 120, Damage = 18, AttackRange = 8, AttackCooldown = 0.9, Speed = 24, CanAttack = "Ground", MovementType = "Air" },
		},
		Archangel = {
			From = "AngelHall", Key = "3", Title = "Архангел", Slots = 3, Cost = 220,
			Stats = { Health = 320, Damage = 26, AttackRange = 14, AttackCooldown = 1.1, Speed = 18, CanAttack = "Both", MovementType = "Air" },
		},
	},

	Hero = {
		Title = "Первосвященник", Slots = 3, Cost = 300, Requires = "Monastery", Cooldown = 90,
		Stats = { Health = 350, Damage = 6, AttackRange = 6, AttackCooldown = 1.2, Speed = 15, CanAttack = "Both" },
		Abilities = { Q = "Обет: Стойкость", E = "Обет: Воздаяние", F = "Улучшить Благодать" },

		-- Damage/Speed - множители, Taken - множитель входящего урона (меньше = крепче)
		Aura = {
			Levels = {
				{ Radius = 25, Damage = 1.10, Speed = 1.05, Taken = 0.92 },
				{ Radius = 32, Damage = 1.10, Speed = 1.05, Taken = 0.92 },
				{ Radius = 32, Damage = 1.18, Speed = 1.10, Taken = 0.85 },
				{ Radius = 32, Damage = 1.18, Speed = 1.10, Taken = 0.85, Regen = 0.01 }, -- доля максимума HP в секунду
			},
			UpgradeCost = { 150, 250, 350 }, -- из уровня 1, 2, 3
			Color = Color3.fromRGB(255, 225, 120), -- кольцо ауры без обета
			CherubRadius = 18,
			HealRadius = 14,
			HealPerSecond = 8,
			UnitBonus = { Templar = 0.85 },  -- доп. множитель входящего урона в ауре
			OutOfAura = { Trebuchet = 0.3 }, -- множитель урона вне ауры
		},

		Vow = {
			Duration = 10, Cooldown = 40,
			Fortitude = { Title = "Стойкость", Color = Color3.fromRGB(80, 160, 255), Taken = 0.75, Speed = 0.85 },
			Retribution = { Title = "Воздаяние", Color = Color3.fromRGB(255, 80, 60), Damage = 1.25, Speed = 1.15, Taken = 1.10 },
		},
	},
})
