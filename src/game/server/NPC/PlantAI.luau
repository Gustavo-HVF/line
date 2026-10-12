--!nonstrict
-- IA da Planta Carnívora (parada, sem Humanoid; usada pelo evento Cipós Carnívoros). A cabeça são duas
-- mandíbulas ancoradas animadas por tween:
--   * acompanha (vira a cabeça) o jogador que chegar a 18 studs;
--   * a 9 studs ou menos, a cada 1,2 s: abre bem a boca e fecha de repente. Se o jogador ainda estiver ao
--     alcance no instante em que ela fecha, leva 12 de dano e fica preso (WalkSpeed 4 por 1,5 s);
--   * sem ninguém por perto, só "mastiga" de vez em quando se houver jogador à vista (economiza rede).

local TweenService = game:GetService("TweenService")

local CombatUtil = require(script.Parent.Parent.CombatUtil)
local Brain = require(script.Parent.Brain)
local Effects = require(script.Parent.Effects)
local Rigs = require(script.Parent.Rigs)

local PlantAI = {}

local BITE_OPEN = 0.95 -- abertura máxima (radianos)
local OPEN_TIME = 0.18
local SNAP_DELAY = 0.24 -- do começo da abertura até a mordida
local SNAP_TIME = 0.07
local RECOVER_TIME = 0.35
local BITE_REACH_BONUS = 1.5 -- folga no instante da mordida
local TURN_TIME = 0.15
local TURN_THRESHOLD = 0.06 -- radianos: abaixo disto a cabeça não se mexe
local PITCH_MIN, PITCH_MAX = -0.6, 0.35
local CHOMP_MIN, CHOMP_MAX = 2.2, 4.2
local CHOMP_OPEN = 0.5
local CHOMP_NEAR = 45 -- só mastiga no ócio com jogador até esta distância
local HOLD_SPEED = 4
local HOLD_TIME = 1.5
local HOLD_JUMP = 0.2
local HOLD_KEY = "NpcPlantaCarnivora"
local SPAWN_LEAVES = Color3.fromRGB(70, 150, 60)

local function cancelTweens(npc)
	local tweens = npc.memory.tweens
	npc.memory.tweens = nil
	if tweens then
		for _, tween in tweens do
			tween:Cancel()
		end
	end
end

-- Leva as mandíbulas para (yaw, pitch, abertura) em `duration` segundos (0 = na hora).
local function setJaws(npc, yaw: number, pitch: number, open: number, duration: number, style: Enum.EasingStyle?)
	local memory = npc.memory
	local extras = npc.rig.extras
	local upper: BasePart? = extras.upperJaw
	local lower: BasePart? = extras.lowerJaw
	memory.yaw, memory.pitch, memory.open = yaw, pitch, open
	if not upper or not upper.Parent or not lower or not lower.Parent then
		return
	end
	cancelTweens(npc)
	local upperCFrame, lowerCFrame = Rigs.PlantJawCFrames(extras.base, yaw, pitch, open)
	if duration <= 0 then
		upper.CFrame = upperCFrame
		lower.CFrame = lowerCFrame
		return
	end
	local info = TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local upperTween = TweenService:Create(upper, info, { CFrame = upperCFrame })
	local lowerTween = TweenService:Create(lower, info, { CFrame = lowerCFrame })
	upperTween:Play()
	lowerTween:Play()
	memory.tweens = { upperTween, lowerTween }
end

local function headPosition(npc): Vector3
	local base: CFrame = npc.rig.extras.base
	return (base * CFrame.new(0, Rigs.PLANT_HEAD_Y, 0)).Position
end

-- Ângulos (relativos à base) para a cabeça olhar para `point`.
local function aimAngles(npc, point: Vector3): (number, number)
	local base: CFrame = npc.rig.extras.base
	local head = base * CFrame.new(0, Rigs.PLANT_HEAD_Y, 0)
	local localPoint = head:PointToObjectSpace(point)
	local horizontal = math.sqrt(localPoint.X * localPoint.X + localPoint.Z * localPoint.Z)
	if horizontal < 0.05 then
		return npc.memory.yaw, npc.memory.pitch
	end
	-- Frente = -Z local: girar `yaw` em Y leva (0, 0, -1) para (-sen yaw, 0, -cos yaw).
	local yaw = math.atan2(-localPoint.X, -localPoint.Z)
	local pitch = math.clamp(math.atan2(localPoint.Y, horizontal), PITCH_MIN, PITCH_MAX)
	return yaw, pitch
end

local function angleDelta(a: number, b: number): number
	return math.abs((a - b + math.pi) % (math.pi * 2) - math.pi)
end

local function snap(npc, now: number)
	local memory = npc.memory
	local def = npc.def
	memory.state = "recover"
	memory.recoverAt = now + RECOVER_TIME
	setJaws(npc, memory.yaw, memory.pitch, 0, SNAP_TIME, Enum.EasingStyle.Back)

	local player: Player? = memory.biteTarget
	memory.biteTarget = nil
	local targetRoot = Brain.RootOf(player)
	if not player or not targetRoot or not CombatUtil.IsPlayerAlive(player) then
		return
	end
	if (targetRoot.Position - headPosition(npc)).Magnitude > def.attackRange + BITE_REACH_BONUS then
		return -- desviou a tempo
	end
	CombatUtil.DamagePlayer(player, npc.damage, def.displayName)
	Effects.Slow(player, HOLD_KEY, HOLD_SPEED, HOLD_TIME, HOLD_JUMP)
	Effects.Notify(player, "Uma planta carnívora mordeu você e não quer soltar!", "danger", "planta", 6)
end

function PlantAI.Setup(npc, now: number)
	local memory = npc.memory
	memory.state = "idle"
	memory.yaw = 0
	memory.pitch = 0
	memory.open = Rigs.PLANT_REST_OPEN
	memory.nextChomp = now + npc.rng:NextNumber(1, CHOMP_MAX)
	Effects.Burst(npc.root.Position + Vector3.new(0, 2, 0), SPAWN_LEAVES)
end

function PlantAI.Think(npc, now: number, _dt: number): number?
	local memory = npc.memory
	local def = npc.def

	if memory.state == "bite" then
		-- Acompanha o alvo enquanto abre a boca.
		local targetRoot = Brain.RootOf(memory.biteTarget)
		if now >= memory.snapAt then
			snap(npc, now)
		elseif targetRoot then
			local yaw, pitch = aimAngles(npc, targetRoot.Position)
			if angleDelta(yaw, memory.yaw) > 0.25 then
				setJaws(npc, yaw, pitch, BITE_OPEN, math.max(memory.snapAt - now, 0.05))
			end
		end
		return 0.05
	elseif memory.state == "recover" then
		if now < memory.recoverAt then
			return 0.05
		end
		memory.state = "idle"
		setJaws(npc, memory.yaw, memory.pitch, Rigs.PLANT_REST_OPEN, 0.3)
	end

	local target, targetRoot = Brain.UpdateTarget(npc, now)
	if target and targetRoot then
		local point = targetRoot.Position
		local yaw, pitch = aimAngles(npc, point)
		local distance = (point - headPosition(npc)).Magnitude
		if distance <= def.attackRange and now >= (npc.nextAttack or 0) and Brain.LineOfSight(npc, now, point) then
			npc.nextAttack = now + def.attackCooldown
			memory.state = "bite"
			memory.biteTarget = target
			memory.snapAt = now + SNAP_DELAY
			setJaws(npc, yaw, pitch, BITE_OPEN, OPEN_TIME)
			return 0.05
		end
		if angleDelta(yaw, memory.yaw) > TURN_THRESHOLD or math.abs(pitch - memory.pitch) > TURN_THRESHOLD then
			setJaws(npc, yaw, pitch, Rigs.PLANT_REST_OPEN, TURN_TIME, Enum.EasingStyle.Linear)
		end
		return def.thinkInterval
	end

	-- Ócio: mastiga de vez em quando (só se houver alguém para ver).
	if now >= memory.nextChomp then
		memory.nextChomp = now + npc.rng:NextNumber(CHOMP_MIN, CHOMP_MAX)
		if CombatUtil.GetNearestAlivePlayer(npc.root.Position, CHOMP_NEAR) then
			setJaws(npc, memory.yaw, memory.pitch, CHOMP_OPEN, 0.25, Enum.EasingStyle.Sine)
			memory.state = "recover"
			memory.recoverAt = now + 0.3
			return 0.05
		end
	end
	return def.idleInterval
end

function PlantAI.Cleanup(npc)
	cancelTweens(npc)
	npc.memory.biteTarget = nil
end

return PlantAI
