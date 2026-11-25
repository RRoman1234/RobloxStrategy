local Navigator = require(script.Parent.Parent:WaitForChild("Navigator"))

local Moving = {}

local FINAL_REACH = 1

function Moving.OnEnter(fsm, unit, targetPos, isDrag)
	fsm.IsAggressive = false
	fsm:SetCollisionMode("Ghost")
	fsm:PlayAnimation("Walk")
	-- При перетаскивании ПКМ (команды каждые ~0.15с) путь не считаем, идём напрямую
	Navigator.Start(fsm, targetPos, not isDrag, true)
end

-- Новая команда, пока юнит уже идёт: обновляем только цель
function Moving.OnRetarget(fsm, unit, targetPos, isDrag)
	fsm:PlayAnimation("Walk")
	Navigator.Start(fsm, targetPos, not isDrag, false)
end

function Moving.OnUpdate(fsm, unit, dt)
	if not fsm.NavTarget then
		fsm:ChangeState("Idle")
		return
	end
	if Navigator.Step(fsm, dt, FINAL_REACH) then
		fsm:ChangeState("Idle")
	end
end

function Moving.OnExit(fsm)
	Navigator.Stop(fsm)
	fsm:SetCollisionMode("Solid")
end

return Moving