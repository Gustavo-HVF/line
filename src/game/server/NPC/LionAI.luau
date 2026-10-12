--!nonstrict
-- IA do Leão: persegue rápido, dá garradas fortes de perto (com empurrão) e, entre 10 e 25 studs com
-- visão livre, dá um BOTE (salto) a cada 4 s. Ruge ao nascer e de tempos em tempos (a câmera treme).
-- O bote usa AssemblyLinearVelocity na raiz (a física do leão é do servidor) e, durante o salto, o
-- WalkSpeed acompanha a velocidade do pulo para o controle do Humanoid não frear o leão no ar.

local CombatUtil = require(script.Parent.Parent.CombatUtil)
local Brain = require(script.Parent.Brain)
local Effects = require(script.Parent.Effects)

local LionAI = {}

local POUNCE_MIN, POUNCE_MAX = 10, 25
local POUNCE_COOLDOWN = 4
local POUNCE_UP = 40 -- velocidade vertical do bote (igual ao JumpPower do leão)
local POUNCE_MIN_SPEED, POUNCE_MAX_SPEED = 30, 85
local POUNCE_EXTRA_TIME = 0.35 -- tempo extra depois do pouso estimado
local POUNCE_HIT_RANGE = 8
local POUNCE_KNOCKBACK = 70
local CLAW_KNOCKBACK = 35
local ROAR_MIN, ROAR_MAX = 12, 20
local SOURCE = "Leão"
local SPAWN_DUST = Color3.fromRGB(196, 160, 100)

local function roar(npc)
	local position = npc.root.Position
	Effects.Sound("Roar", position, { Volume = 1, RollOffMaxDistance = 300 })
	Effects.Shake(position, 80, 0.6, 0.7)
end

local function endPounce(npc, now: number)
	local memory = npc.memory
	memory.state = "chase"
	memory.nextPounce = now + POUNCE_COOLDOWN
	if npc.humanoid then
		npc.humanoid.WalkSpeed = npc.def.walkSpeed
	end
end

local function startPounce(npc, now: number, targetRoot: BasePart)
	local memory = npc.memory
	local root: BasePart = npc.root
	local humanoid: Humanoid = npc.humanoid
	local lead = targetRoot.AssemblyLinearVelocity
	local predicted = targetRoot.Position + Vector3.new(lead.X, 0, lead.Z) * 0.3
	local offset = Vector3.new(predicted.X - root.Position.X, 0, predicted.Z - root.Position.Z)
	local distance = offset.Magnitude
	local direction = Brain.FlatUnit(offset, root.CFrame.LookVector)
	local airTime = 2 * POUNCE_UP / math.max(workspace.Gravity, 1)
	local horizontal = math.clamp((distance - 3) / airTime, POUNCE_MIN_SPEED, POUNCE_MAX_SPEED)

	Brain.Face(npc, predicted)
	humanoid.WalkSpeed = horizontal
	Brain.MoveTo(npc, root.Position + direction * (distance + 4), now)
	pcall(humanoid.ChangeState, humanoid, Enum.HumanoidStateType.Jumping)
	root.AssemblyLinearVelocity = direction * horizontal + Vector3.new(0, POUNCE_UP, 0)

	memory.state = "pounce"
	memory.pounceEnd = now + airTime + POUNCE_EXTRA_TIME
	memory.pounceHit = false
	npc.wantsMove = false
	roar(npc)
end

function LionAI.Setup(npc, now: number)
	local memory = npc.memory
	memory.state = "chase"
	memory.nextPounce = now + 2
	memory.nextRoar = now + npc.rng:NextNumber(ROAR_MIN * 0.5, ROAR_MAX * 0.5)
	Effects.Burst(npc.root.Position, SPAWN_DUST)
	roar(npc)
end

function LionAI.Think(npc, now: number, _dt: number): number?
	local memory = npc.memory
	local def = npc.def
	local target, targetRoot, distance = Brain.UpdateTarget(npc, now)

	if memory.state == "pounce" then
		if target and targetRoot and not memory.pounceHit and distance <= POUNCE_HIT_RANGE then
			memory.pounceHit = true
			CombatUtil.DamagePlayer(target, npc.damage, SOURCE)
			CombatUtil.Knockback(target, targetRoot.Position - npc.root.Position, POUNCE_KNOCKBACK)
		end
		if now < memory.pounceEnd then
			return 0.05
		end
		endPounce(npc, now)
	end

	if not target or not targetRoot then
		Brain.Wander(npc, now, 20)
		return def.idleInterval
	end

	if now >= memory.nextRoar then
		memory.nextRoar = now + npc.rng:NextNumber(ROAR_MIN, ROAR_MAX)
		roar(npc)
	end

	-- Garrada.
	if distance <= def.attackRange then
		if Brain.Melee(npc, now, target, targetRoot) then
			CombatUtil.Knockback(target, targetRoot.Position - npc.root.Position, CLAW_KNOCKBACK)
		end
		Brain.ChaseTo(npc, now, targetRoot.Position, true, def.attackRange * 0.7)
		return nil
	end

	-- Bote.
	local canSee: boolean? = nil
	local dy = targetRoot.Position.Y - npc.root.Position.Y
	if
		now >= memory.nextPounce
		and distance >= POUNCE_MIN
		and distance <= POUNCE_MAX
		and math.abs(dy) < 5
		and Brain.IsGrounded(npc)
	then
		canSee = Brain.LineOfSight(npc, now, targetRoot.Position)
		if canSee then
			startPounce(npc, now, targetRoot)
			return 0.05
		end
	end

	Brain.ChaseTo(npc, now, targetRoot.Position, canSee)
	return nil
end

function LionAI.Cleanup(_npc) end

return LionAI
