--!nonstrict
-- IA do Mosquito Gigante (voador, sem Humanoid). O corpo é ancorado e se move por CFrame (só a raiz
-- replica; o resto do corpo vai soldado). Comportamento:
--   * enxame: circula em volta do alvo, alguns studs acima da cabeça, cada um num raio/altura/sentido;
--   * rasante: com visão livre e perto, mergulha em linha reta até onde o alvo ESTAVA (dá para desviar);
--     se passar pelo jogador, pica (6 de dano) e deixa "febre" (1 de dano por segundo por 4 s, sem
--     acumular: uma nova picada só renova o tempo). No máximo 2 mosquitos mergulham no mesmo alvo;
--   * colisão barata: um raio por passo; encostou numa parede, desliza; preso por 1 s, atravessa;
--   * sem alvo: paira perto de onde nasceu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)

local CombatUtil = require(script.Parent.Parent.CombatUtil)
local Brain = require(script.Parent.Brain)
local Effects = require(script.Parent.Effects)

local MosquitoAI = {}

local ACCELERATION = 5 -- quão rápido a velocidade converge para a desejada (por segundo)
local DIVE_SPEED = 55
local IDLE_SPEED = 8
local APPROACH_DISTANCE = 24 -- além disto, voa direto para o alvo
local ORBIT_RADIUS_MIN, ORBIT_RADIUS_MAX = 7, 12
local ORBIT_HEIGHT_MIN, ORBIT_HEIGHT_MAX = 4, 8
local ORBIT_SPEED_MIN, ORBIT_SPEED_MAX = 1.1, 2.2 -- radianos por segundo
local DIVE_RANGE = 30
local DIVE_COOLDOWN_MIN, DIVE_COOLDOWN_MAX = 2.5, 5
local DIVE_MAX_TIME = 1.3
local DIVE_LEAD = 0.25 -- segundos de antecipação do movimento do alvo
local DIVE_OVERSHOOT = 3 -- passa um pouco do ponto mirado
local MAX_DIVERS_PER_TARGET = 2
local BITE_RADIUS = 3.2
local RETREAT_TIME = 0.7
local GROUND_CLEARANCE = 1.5
local GROUND_CHECK = 0.25
local WALL_MARGIN = 0.8
local STUCK_LIMIT = 1
local PHASE_TIME = 0.6
local BOB_SPEED = 9
local BOB_AMPLITUDE = 0.25
local FEVER_TICK = 1
local FEVER_DAMAGE = 1
local FEVER_TIME = 4
local FEVER_SOURCE = "Febre do Mosquito"
local BUZZ_CHANCE = 0.35 -- parte do enxame zumbe sem parar (som em loop preso no corpo)
local SPAWN_PUFF = Color3.fromRGB(110, 120, 90)

-- Quantos mosquitos estão mergulhando em cada jogador agora.
local divers: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
-- Febre de cada jogador: { untilTime }. Uma única thread por febre cuida do dano.
local fevers: { [Player]: { untilTime: number } } = setmetatable({}, { __mode = "k" }) :: any

-- Febre ------------------------------------------------------------------------------------------

local function giveFever(player: Player)
	local now = os.clock()
	local current = fevers[player]
	if current then
		-- Já está com febre: só renova o tempo (não acumula).
		current.untilTime = now + FEVER_TIME
		return
	end
	local entry = { untilTime = now + FEVER_TIME }
	fevers[player] = entry
	Effects.Notify(player, "A picada deu febre! Você vai perder um pouco de vida.", "warning", "febre", 8)
	task.spawn(function()
		while fevers[player] == entry do
			task.wait(FEVER_TICK)
			if
				fevers[player] ~= entry
				or os.clock() > entry.untilTime + 0.05
				or not player.Parent
				or not CombatUtil.IsPlayerAlive(player)
			then
				break
			end
			CombatUtil.DamagePlayer(player, FEVER_DAMAGE, FEVER_SOURCE)
		end
		if fevers[player] == entry then
			fevers[player] = nil
		end
	end)
end

-- Mergulhos --------------------------------------------------------------------------------------

local function releaseDive(npc)
	local memory = npc.memory
	local player: Player? = memory.divingOn
	memory.divingOn = nil
	if player then
		local count = (divers[player] or 1) - 1
		divers[player] = if count > 0 then count else nil
	end
end

local function startDive(npc, now: number, target: Player, targetRoot: BasePart)
	local memory = npc.memory
	local velocity = targetRoot.AssemblyLinearVelocity
	local aim = targetRoot.Position + Vector3.new(velocity.X, 0, velocity.Z) * DIVE_LEAD
	local offset = aim - memory.pos
	if offset.Magnitude < 1 then
		return
	end
	memory.state = "dive"
	memory.diveTo = aim + offset.Unit * DIVE_OVERSHOOT
	memory.diveEnd = now + DIVE_MAX_TIME
	memory.divingOn = target
	divers[target] = (divers[target] or 0) + 1
	Effects.Sound("Mosquito", memory.pos, { Volume = 0.7, PlaybackSpeed = 1.3, RollOffMaxDistance = 80 })
end

local function startRetreat(npc, now: number)
	local memory = npc.memory
	releaseDive(npc)
	local rng: Random = npc.rng
	local angle = rng:NextNumber(0, math.pi * 2)
	memory.state = "retreat"
	memory.retreatTo = memory.pos + Vector3.new(math.cos(angle) * 8, rng:NextNumber(5, 8), math.sin(angle) * 8)
	memory.retreatEnd = now + RETREAT_TIME
	memory.nextDive = now + rng:NextNumber(DIVE_COOLDOWN_MIN, DIVE_COOLDOWN_MAX)
end

local function bite(npc, player: Player)
	CombatUtil.DamagePlayer(player, npc.damage, npc.def.displayName)
	giveFever(player)
	Effects.Sound("Mosquito", npc.memory.pos, { Volume = 0.8, PlaybackSpeed = 0.8, RollOffMaxDistance = 60 })
end

-- Movimento --------------------------------------------------------------------------------------

local function faceCFrame(position: Vector3, direction: Vector3): CFrame
	local look = direction
	if look.Magnitude < 1e-3 then
		return CFrame.new(position)
	end
	look = look.Unit
	if math.abs(look.Y) > 0.9 then
		-- Quase vertical: inclina sem perder a referência de "cima".
		local flat = Brain.FlatUnit(look)
		look = (flat + Vector3.new(0, math.sign(look.Y) * 2, 0)).Unit
	end
	return CFrame.lookAt(position, position + look)
end

-- Move a posição lógica em direção a `desired` com velocidade máxima `speed`, desviando de paredes.
local function fly(npc, now: number, dt: number, desired: Vector3, speed: number, keepAboveGround: boolean)
	local memory = npc.memory
	local pos: Vector3 = memory.pos
	local offset = desired - pos
	local distance = offset.Magnitude
	local wanted = Vector3.zero
	if distance > 0.05 then
		wanted = offset.Unit * math.min(speed, distance / math.max(dt, 1 / 30))
	end
	local accel = if memory.state == "dive" then ACCELERATION * 3 else ACCELERATION
	local velocity: Vector3 = memory.vel:Lerp(wanted, math.clamp(dt * accel, 0, 1))
	local move = velocity * dt
	local intended = move.Magnitude

	if intended > 1e-3 and now >= (memory.phaseUntil or 0) then
		local params = Effects.WorldParams()
		local hit = workspace:Raycast(pos, move.Unit * (intended + WALL_MARGIN), params)
		if hit then
			local normal = hit.Normal
			-- Desliza na superfície (tira o componente que entra na parede).
			local slide = move - normal * move:Dot(normal)
			velocity -= normal * math.min(velocity:Dot(normal), 0)
			if
				slide.Magnitude > 1e-3
				and not workspace:Raycast(pos, slide.Unit * (slide.Magnitude + WALL_MARGIN), params)
			then
				move = slide
			else
				move = Vector3.zero
			end
			-- Encostado demais: afasta um pouco.
			if (hit.Position - pos).Magnitude < WALL_MARGIN * 0.5 then
				move += normal * 0.2
			end
		end
	end

	-- Preso (quer andar e quase não sai do lugar): atravessa por um instante.
	if intended > 0.05 and move.Magnitude < intended * 0.2 then
		memory.stuckTime = (memory.stuckTime or 0) + dt
		if memory.stuckTime >= STUCK_LIMIT then
			memory.stuckTime = 0
			memory.phaseUntil = now + PHASE_TIME
		end
	else
		memory.stuckTime = 0
	end

	local nextPos = pos + move
	if keepAboveGround then
		if now - (memory.lastGroundCheck or 0) >= GROUND_CHECK then
			memory.lastGroundCheck = now
			local ground = Effects.Ground(nextPos, 40, 1)
			memory.groundY = if ground then ground.Y else nil
		end
		local groundY: number? = memory.groundY
		if groundY and nextPos.Y < groundY + GROUND_CLEARANCE then
			nextPos = Vector3.new(nextPos.X, groundY + GROUND_CLEARANCE, nextPos.Z)
		end
	end

	memory.pos = nextPos
	memory.vel = velocity
	return nextPos, move
end

-- Posiciona o corpo (posição lógica + balanço do voo). Sem direção útil, mantém para onde já olhava.
local function render(npc, now: number, faceDirection: Vector3)
	local memory = npc.memory
	local root: BasePart = npc.root
	local bob = math.sin(now * BOB_SPEED + memory.seed) * BOB_AMPLITUDE
	local direction = faceDirection
	if direction.Magnitude < 1e-3 then
		direction = memory.vel
	end
	if direction.Magnitude < 1e-3 then
		direction = root.CFrame.LookVector
	end
	root.CFrame = faceCFrame(memory.pos + Vector3.new(0, bob, 0), direction)
end

-- Ciclo ------------------------------------------------------------------------------------------

function MosquitoAI.Setup(npc, now: number)
	local memory = npc.memory
	local rng: Random = npc.rng
	memory.state = "swarm"
	memory.pos = npc.root.Position
	memory.vel = Vector3.zero
	memory.hover = npc.root.Position
	memory.seed = rng:NextNumber(0, math.pi * 2)
	memory.orbitAngle = rng:NextNumber(0, math.pi * 2)
	memory.orbitRadius = rng:NextNumber(ORBIT_RADIUS_MIN, ORBIT_RADIUS_MAX)
	memory.orbitHeight = rng:NextNumber(ORBIT_HEIGHT_MIN, ORBIT_HEIGHT_MAX)
	memory.orbitSpeed = rng:NextNumber(ORBIT_SPEED_MIN, ORBIT_SPEED_MAX) * (if rng:NextNumber() < 0.5 then -1 else 1)
	memory.nextDive = now + rng:NextNumber(1.5, DIVE_COOLDOWN_MAX)
	memory.lastThink = now
	if rng:NextNumber() < BUZZ_CHANCE then
		SoundUtil.Play("Mosquito", {
			Parent = npc.root,
			Looped = true,
			Volume = 0.3,
			PlaybackSpeed = rng:NextNumber(0.9, 1.15),
			RollOffMaxDistance = 60,
		})
	end
	Effects.Burst(npc.root.Position, SPAWN_PUFF)
end

function MosquitoAI.Think(npc, now: number, _dt: number): number?
	local memory = npc.memory
	local def = npc.def
	-- O passo usa o tempo real desde o último passo (o agendador pode atrasar alguns frames).
	local dt = math.clamp(now - (memory.lastThink or now), 1 / 60, 0.25)
	memory.lastThink = now

	local target, targetRoot, distance = Brain.UpdateTarget(npc, now)

	-- Rasante em andamento.
	if memory.state == "dive" then
		local divingOn: Player? = memory.divingOn
		local diveRoot = Brain.RootOf(divingOn)
		local from: Vector3 = memory.pos
		local nextPos, move = fly(npc, now, dt, memory.diveTo, DIVE_SPEED, false)
		-- Passou perto de alguém no caminho? Pica.
		for _, player in CombatUtil.GetAlivePlayers() do
			local root = Brain.RootOf(player)
			if root then
				local point = root.Position
				local segment = nextPos - from
				local t = 0
				local lengthSq = segment:Dot(segment)
				if lengthSq > 1e-6 then
					t = math.clamp((point - from):Dot(segment) / lengthSq, 0, 1)
				end
				if (point - (from + segment * t)).Magnitude <= BITE_RADIUS then
					bite(npc, player)
					startRetreat(npc, now)
					render(npc, now, move)
					return 0.05
				end
			end
		end
		if (memory.diveTo - nextPos).Magnitude < 1.5 or now >= memory.diveEnd or not diveRoot then
			startRetreat(npc, now)
		end
		render(npc, now, move)
		return 0.05
	end

	-- Subindo depois do rasante.
	if memory.state == "retreat" then
		local _, move = fly(npc, now, dt, memory.retreatTo, def.walkSpeed, true)
		if now >= memory.retreatEnd then
			memory.state = "swarm"
		end
		local face = if targetRoot then Brain.FlatUnit(targetRoot.Position - memory.pos) else move
		render(npc, now, face)
		return 0.05
	end

	-- Sem alvo: paira perto de onde nasceu.
	if not target or not targetRoot then
		local hover: Vector3 = memory.hover
		local t = now * 0.6 + memory.seed
		local desired = hover + Vector3.new(math.cos(t) * 4, math.sin(t * 1.7) * 1.2, math.sin(t) * 4)
		local _, move = fly(npc, now, dt, desired, IDLE_SPEED, true)
		render(npc, now, Brain.FlatUnit(move, npc.root.CFrame.LookVector))
		return 0.1
	end

	-- Enxame em volta do alvo.
	local targetPosition = targetRoot.Position
	local desired: Vector3
	if distance > APPROACH_DISTANCE then
		desired = targetPosition + Vector3.new(0, memory.orbitHeight, 0)
	else
		memory.orbitAngle += memory.orbitSpeed * dt
		local angle = memory.orbitAngle
		desired = targetPosition
			+ Vector3.new(
				math.cos(angle) * memory.orbitRadius,
				memory.orbitHeight,
				math.sin(angle) * memory.orbitRadius
			)
	end
	fly(npc, now, dt, desired, def.walkSpeed, true)
	render(npc, now, targetPosition - memory.pos)

	if
		now >= memory.nextDive
		and distance <= DIVE_RANGE
		and (divers[target] or 0) < MAX_DIVERS_PER_TARGET
		and Brain.LineOfSight(npc, now, targetPosition)
	then
		startDive(npc, now, target, targetRoot)
	elseif now >= memory.nextDive then
		-- Não deu para mergulhar agora (sem visão ou já há mosquitos demais no alvo): tenta logo depois.
		memory.nextDive = now + 0.6
	end
	return 0.05
end

function MosquitoAI.Cleanup(npc)
	releaseDive(npc)
end

-- Fim da partida: ninguém continua com febre.
function MosquitoAI.ResetAll()
	table.clear(fevers)
	table.clear(divers)
end

return MosquitoAI
