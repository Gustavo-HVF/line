--!nonstrict
-- IA do Macaco: pequeno, rápido e saltitante. Persegue e morde de perto; de vez em quando (30%) corre até
-- um objeto solto (LooseProp) próximo, ergue acima da cabeça e arremessa num jogador (10 de dano ao
-- acertar). Sem ninguém por perto, "saqueia": derruba objetos soltos ao redor.

local Brain = require(script.Parent.Brain)
local Effects = require(script.Parent.Effects)
local Projectiles = require(script.Parent.Projectiles)

local MonkeyAI = {}

local THROW_CHECK_INTERVAL = 2.2
local THROW_CHANCE = 0.3
local THROW_MIN_DISTANCE = 10
local THROW_MAX_DISTANCE = 45
local THROW_SPEED = 45 -- define o tempo de voo (distância / velocidade)
local THROW_DAMAGE = 10
local PROP_SEARCH_RADIUS = 14
local PROP_MAX_SIZE = 6 -- tamanho máximo (magnitude do Size) de um objeto arremessável
local PICK_DISTANCE = 4.5
local FETCH_TIMEOUT = 3
local HOLD_TIME = 0.5
local HOP_CHANCE = 0.05 -- por decisão, enquanto persegue
local LOOT_RADIUS = 9
local LOOT_INTERVAL_MIN, LOOT_INTERVAL_MAX = 5, 9
local CHATTER_MIN, CHATTER_MAX = 5, 11
local SOURCE = "Macaco"
local SPAWN_LEAVES = Color3.fromRGB(70, 130, 50)

local function chatter(npc)
	Effects.Sound("Monkey", npc.root.Position, { Volume = 0.55, RollOffMaxDistance = 90 })
end

local function holdCFrame(npc, prop: BasePart): CFrame
	local height = npc.rig.topOffset + prop.Size.Y / 2 + 0.4
	return CFrame.new(npc.root.Position + Vector3.new(0, height, 0)) * prop.CFrame.Rotation
end

-- Larga o objeto (se estava segurando, ele cai) e libera a reserva.
local function releaseProp(npc)
	local memory = npc.memory
	local prop: BasePart? = memory.prop
	memory.prop = nil
	if prop then
		Effects.ReleaseClaim(prop)
		if memory.holding and prop.Parent then
			Effects.LaunchProp(prop, Vector3.new(0, -2, 0))
		end
	end
	memory.holding = false
end

local function pick(npc, prop: BasePart, now: number)
	local memory = npc.memory
	-- Ancorado enquanto está nas mãos: mover a raiz move o objeto inteiro (partes soldadas).
	prop.Anchored = true
	prop.CFrame = holdCFrame(npc, prop)
	memory.holding = true
	memory.state = "hold"
	memory.throwAt = now + HOLD_TIME
	Brain.Stop(npc)
	chatter(npc)
end

local function throw(npc, prop: BasePart, targetRoot: BasePart)
	local memory = npc.memory
	memory.prop = nil
	memory.holding = false
	local start = prop.Position
	local aim = targetRoot.Position
	local flight = math.clamp((aim - start).Magnitude / THROW_SPEED, 0.35, 1.1)
	-- Mira um pouco à frente de quem corre (dá para desviar parando ou mudando de direção).
	local lead = targetRoot.AssemblyLinearVelocity
	aim += Vector3.new(lead.X, 0, lead.Z) * flight * 0.5
	local velocity = Projectiles.BallisticVelocity(start, aim, flight)
	local launched = Effects.LaunchProp(prop, velocity)
	if launched then
		Projectiles.TrackProp(npc, launched, { damage = THROW_DAMAGE, source = SOURCE, lifetime = flight + 1 })
	end
	chatter(npc)
end

function MonkeyAI.Setup(npc, now: number)
	local memory = npc.memory
	local rng: Random = npc.rng
	memory.state = "chase"
	memory.nextThrowCheck = now + rng:NextNumber(1, THROW_CHECK_INTERVAL)
	memory.nextLoot = now + rng:NextNumber(2, LOOT_INTERVAL_MAX)
	memory.nextChatter = now + rng:NextNumber(1, CHATTER_MAX)
	Effects.Burst(npc.root.Position, SPAWN_LEAVES)
end

function MonkeyAI.Think(npc, now: number, _dt: number): number?
	local memory = npc.memory
	local rng: Random = npc.rng
	local def = npc.def
	local target, targetRoot, distance = Brain.UpdateTarget(npc, now)

	-- Segurando um objeto acima da cabeça.
	if memory.state == "hold" then
		local prop: BasePart? = memory.prop
		if not prop or not prop.Parent then
			releaseProp(npc)
			memory.state = "chase"
		else
			prop.CFrame = holdCFrame(npc, prop)
			if targetRoot then
				Brain.Face(npc, targetRoot.Position)
			end
			if now >= memory.throwAt then
				if
					targetRoot
					and distance <= THROW_MAX_DISTANCE + 10
					and Brain.LineOfSight(npc, now, targetRoot.Position)
				then
					throw(npc, prop, targetRoot)
				else
					releaseProp(npc)
				end
				memory.state = "chase"
			end
			return 0.1
		end
	end

	-- Indo buscar um objeto.
	if memory.state == "fetch" then
		local prop: BasePart? = memory.prop
		if not prop or now >= memory.fetchUntil or not Effects.IsPropAvailable(prop, npc) then
			releaseProp(npc)
			memory.state = "chase"
		else
			local offset = prop.Position - npc.root.Position
			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= PICK_DISTANCE and math.abs(offset.Y) < 5 then
				pick(npc, prop, now)
				return 0.1
			end
			npc.wantsMove = true
			if now - (npc.lastMoveTo or 0) >= 0.3 then
				Brain.MoveTo(npc, prop.Position, now)
			end
			Brain.CheckStuck(npc, now)
			return nil
		end
	end

	if not target or not targetRoot then
		-- Saqueio: derruba um objeto solto por perto de vez em quando.
		if now >= memory.nextLoot then
			memory.nextLoot = now + rng:NextNumber(LOOT_INTERVAL_MIN, LOOT_INTERVAL_MAX)
			local prop = Effects.FindLooseProp(npc.root.Position, LOOT_RADIUS, PROP_MAX_SIZE, npc)
			if prop then
				local angle = rng:NextNumber(0, math.pi * 2)
				Effects.LaunchProp(prop, Vector3.new(math.cos(angle) * 14, 12, math.sin(angle) * 14))
				chatter(npc)
			end
		end
		Brain.Wander(npc, now, 18)
		return def.idleInterval
	end

	if now >= memory.nextChatter then
		memory.nextChatter = now + rng:NextNumber(CHATTER_MIN, CHATTER_MAX)
		chatter(npc)
	end

	-- Mordida de perto.
	if distance <= def.attackRange + 1 then
		Brain.Melee(npc, now, target, targetRoot)
		Brain.ChaseTo(npc, now, targetRoot.Position, true, def.attackRange * 0.6)
		return nil
	end

	-- Às vezes, pega algo para arremessar.
	if now >= memory.nextThrowCheck and distance >= THROW_MIN_DISTANCE and distance <= THROW_MAX_DISTANCE then
		memory.nextThrowCheck = now + THROW_CHECK_INTERVAL
		if rng:NextNumber() < THROW_CHANCE and Brain.LineOfSight(npc, now, targetRoot.Position) then
			local prop = Effects.FindLooseProp(npc.root.Position, PROP_SEARCH_RADIUS, PROP_MAX_SIZE, npc)
			if prop and Effects.ClaimProp(prop, npc) then
				memory.prop = prop
				memory.state = "fetch"
				memory.fetchUntil = now + FETCH_TIMEOUT
				return 0.1
			end
		end
	end

	Brain.ChaseTo(npc, now, targetRoot.Position)
	if Brain.IsGrounded(npc) and rng:NextNumber() < HOP_CHANCE then
		npc.humanoid.Jump = true
	end
	return nil
end

-- Morte ou remoção: solta o que estiver segurando.
function MonkeyAI.Cleanup(npc)
	releaseProp(npc)
end

return MonkeyAI
