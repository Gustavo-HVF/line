--!nonstrict
-- IA da Aranha Gigante: corre atrás do jogador e morde de perto (12 de dano). De média distância, com
-- visão livre, para por um instante e CUSPE TEIA: uma bola branca em arco que, se acertar, deixa o
-- jogador lento (WalkSpeed 6 por 3 s). A lentidão usa os modificadores empilháveis (mesma chave = renova
-- o tempo, sem restaurar o valor errado quando outro efeito também está ativo).

local Brain = require(script.Parent.Brain)
local Effects = require(script.Parent.Effects)
local Projectiles = require(script.Parent.Projectiles)

local SpiderAI = {}

local SPIT_MIN, SPIT_MAX = 10, 45 -- distâncias em que cospe teia
local SPIT_WINDUP = 0.35 -- pausa antes de cuspir (aviso visual: a aranha para e encara)
local SPIT_COOLDOWN_MIN, SPIT_COOLDOWN_MAX = 4, 6.5
local SPIT_LEAD = 0.35 -- quanto da velocidade do alvo entra na mira
local WEB_SLOW_SPEED = 6
local WEB_SLOW_TIME = 3
local WEB_JUMP = 0.35 -- multiplicador de pulo enquanto está preso
local WEB_KEY = "NpcTeiaDeAranha"
local WEB_COLOR = Color3.fromRGB(240, 240, 236)
local HISS_MIN, HISS_MAX = 6, 12
local SPAWN_DUST = Color3.fromRGB(60, 52, 44)

local function hiss(npc)
	Effects.Sound("Spider", npc.root.Position, { Volume = 0.6, RollOffMaxDistance = 90 })
end

local function onWebHit(player: Player, _position: Vector3)
	Effects.Slow(player, WEB_KEY, WEB_SLOW_SPEED, WEB_SLOW_TIME, WEB_JUMP)
	Effects.Mark(player, "Teia", WEB_COLOR, WEB_SLOW_TIME)
	Effects.Notify(player, "Uma teia grudou em você! Você está mais lento.", "warning", "teia", 5)
end

local function mouthPosition(npc): Vector3
	local mouth: BasePart? = npc.rig.extras.mouth
	local root: BasePart = npc.root
	if mouth and mouth.Parent then
		return mouth.Position + root.CFrame.LookVector * 1.4
	end
	return root.Position + root.CFrame.LookVector * 2.5
end

local function spit(npc, now: number)
	local memory = npc.memory
	memory.state = "chase"
	memory.nextSpit = now + npc.rng:NextNumber(SPIT_COOLDOWN_MIN, SPIT_COOLDOWN_MAX)
	local targetRoot = Brain.RootOf(npc.target)
	if not targetRoot then
		return
	end
	local origin = mouthPosition(npc)
	local velocity = targetRoot.AssemblyLinearVelocity
	local distance = (targetRoot.Position - origin).Magnitude
	-- O voo leva ~distância/70 s: mira um pouco à frente de quem corre (dá para desviar mudando de direção).
	local flight = math.clamp(distance / 70, 0.25, 0.9)
	local aim = targetRoot.Position + Vector3.new(velocity.X, 0, velocity.Z) * flight * SPIT_LEAD
	Brain.Face(npc, aim)
	Projectiles.FireWeb(npc, origin, aim, onWebHit)
	hiss(npc)
end

function SpiderAI.Setup(npc, now: number)
	local memory = npc.memory
	memory.state = "chase"
	memory.nextSpit = now + npc.rng:NextNumber(2, 4)
	memory.nextHiss = now + npc.rng:NextNumber(1, HISS_MAX)
	Effects.Burst(npc.root.Position, SPAWN_DUST)
end

function SpiderAI.Think(npc, now: number, _dt: number): number?
	local memory = npc.memory
	local def = npc.def

	-- Preparando o cuspe: parada, encarando o alvo.
	if memory.state == "spit" then
		local targetRoot = Brain.RootOf(npc.target)
		if targetRoot then
			Brain.Face(npc, targetRoot.Position)
		end
		if now >= memory.spitAt then
			spit(npc, now)
		end
		return 0.05
	end

	local target, targetRoot, distance = Brain.UpdateTarget(npc, now)
	if not target or not targetRoot then
		Brain.Wander(npc, now, 14)
		return def.idleInterval
	end

	if now >= memory.nextHiss then
		memory.nextHiss = now + npc.rng:NextNumber(HISS_MIN, HISS_MAX)
		hiss(npc)
	end

	-- Mordida.
	if distance <= def.attackRange + 1 then
		Brain.Melee(npc, now, target, targetRoot)
		Brain.ChaseTo(npc, now, targetRoot.Position, true, def.attackRange * 0.6)
		return nil
	end

	-- Cuspe de teia.
	local canSee: boolean? = nil
	if now >= memory.nextSpit and distance >= SPIT_MIN and distance <= SPIT_MAX and Brain.IsGrounded(npc) then
		canSee = Brain.LineOfSight(npc, now, targetRoot.Position)
		if canSee then
			Brain.Stop(npc)
			Brain.Face(npc, targetRoot.Position)
			memory.state = "spit"
			memory.spitAt = now + SPIT_WINDUP
			return 0.05
		end
		-- Sem visão: tenta de novo daqui a pouco.
		memory.nextSpit = now + 1
	end

	Brain.ChaseTo(npc, now, targetRoot.Position, canSee)
	return nil
end

function SpiderAI.Cleanup(_npc) end

return SpiderAI
