--!nonstrict
-- Locomoção e percepção comuns aos NPCs terrestres (Humanoid):
--   * alvo: jogador vivo mais próximo no raio de aggro, com "memória" (só desiste além do leash) e
--     prioridade para quem acabou de atacar o NPC;
--   * linha de visão com cache curto;
--   * perseguição: com visão e perto → Humanoid:MoveTo direto (a cada ~0,3 s); senão, PathfindingService
--     (ComputeAsync em pcall, em outra thread, com limite de cálculos simultâneos) seguindo os waypoints;
--   * detecção de travamento: pula → recalcula o caminho → desvia para o lado;
--   * passeio sem alvo e animação procedural das pernas (Motor6D C0, ~8 Hz, só andando e perto de alguém).
-- Nada aqui cede (yield): tudo roda dentro do agendador do NPCService.

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local CombatUtil = require(script.Parent.Parent.CombatUtil)
local Effects = require(script.Parent.Effects)

local Brain = {}

local DIRECT_RANGE = 40 -- persegue direto (sem caminho) até esta distância, se estiver vendo o alvo
local DIRECT_MAX_DY = 7
local MOVE_REFRESH = 0.3
local TARGET_SCAN = 0.5
local LOS_CACHE = 0.3
local PROVOKE_TIME = 8 -- segundos em que quem atacou o NPC vira o alvo preferido
local SWITCH_MARGIN = 10 -- troca de alvo só se o novo estiver bem mais perto
local STUCK_INTERVAL = 1
local STUCK_MIN_MOVE = 1
local FORCE_PATH_TIME = 3
local SIDESTEP_TIME = 0.8
local PATH_RETRY_AFTER_FAIL = 1.5
local MAX_CONCURRENT_PATHS = 4
local GOAL_MOVED = 6 -- recalcula o caminho se o alvo andou mais que isto
local GAIT_INTERVAL = 0.12
local GAIT_NEAR = 80 -- só anima com jogador até esta distância
local GAIT_MIN_SPEED = 1.5
local MAX_GAIT_RATE = 13 -- radianos por segundo

local computing = 0

local function rootOf(player: Player?): BasePart?
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end
Brain.RootOf = rootOf

local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end
Brain.FlatDistance = flatDistance

local function flatUnit(vector: Vector3, fallback: Vector3?): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 1e-3 then
		return fallback or Vector3.new(0, 0, -1)
	end
	return flat.Unit
end
Brain.FlatUnit = flatUnit

-- Alvo ----------------------------------------------------------------------------------------------

-- Marca quem atacou o NPC (vira o alvo preferido por alguns segundos, mesmo fora do raio).
function Brain.Provoke(npc, player: Player?, now: number)
	if player and CombatUtil.IsPlayerAlive(player) then
		npc.provoker = player
		npc.provokedUntil = now + PROVOKE_TIME
		npc.nextTargetScan = 0
	end
end

-- Atualiza e devolve (alvo, raiz do alvo, distância 3D). Sem alvo: (nil, nil, math.huge).
function Brain.UpdateTarget(npc, now: number): (Player?, BasePart?, number)
	local def = npc.def
	local position = npc.root.Position
	local current: Player? = npc.target
	if current and (not current.Parent or not CombatUtil.IsPlayerAlive(current)) then
		current = nil
		npc.target = nil
	end

	if not current or now >= (npc.nextTargetScan or 0) then
		npc.nextTargetScan = now + TARGET_SCAN
		local chosen: Player? = nil
		local provoker: Player? = npc.provoker
		if provoker and now < (npc.provokedUntil or 0) and provoker.Parent and CombatUtil.IsPlayerAlive(provoker) then
			local provokerRoot = rootOf(provoker)
			if provokerRoot and (provokerRoot.Position - position).Magnitude <= def.leashRadius then
				chosen = provoker
			end
		end
		if not chosen then
			local nearest, nearestDistance = CombatUtil.GetNearestAlivePlayer(position, def.aggroRadius)
			local currentRoot = rootOf(current)
			if current and currentRoot then
				local currentDistance = (currentRoot.Position - position).Magnitude
				if currentDistance <= def.leashRadius and not (nearest and nearestDistance < currentDistance - SWITCH_MARGIN) then
					chosen = current
				else
					chosen = nearest
				end
			else
				chosen = nearest
			end
			if not chosen and def.persistent then
				chosen = CombatUtil.GetNearestAlivePlayer(position)
			end
		end
		if chosen ~= npc.target then
			npc.target = chosen
			npc.waypoints = nil
			npc.losUntil = nil
		end
	end

	local target: Player? = npc.target
	local targetRoot = rootOf(target)
	if not target or not targetRoot then
		npc.target = nil
		npc.targetDistance = math.huge
		return nil, nil, math.huge
	end
	local distance = (targetRoot.Position - position).Magnitude
	npc.targetDistance = distance
	return target, targetRoot, distance
end

-- Visão ---------------------------------------------------------------------------------------------

function Brain.EyePosition(npc): Vector3
	local eye = npc.rig.eye
	if eye and eye.Parent then
		return eye.Position
	end
	return npc.root.Position + Vector3.new(0, 1, 0)
end

-- Há linha de visão do "olho" do NPC até `point` (sem paredes no meio)? Resultado guardado por ~0,3 s.
function Brain.LineOfSight(npc, now: number, point: Vector3): boolean
	local cachedPoint: Vector3? = npc.losPoint
	if npc.losUntil and now < npc.losUntil and cachedPoint and (cachedPoint - point).Magnitude < 4 then
		return npc.losValue == true
	end
	local eye = Brain.EyePosition(npc)
	local result = workspace:Raycast(eye, point - eye, Effects.WorldParams())
	local visible = result == nil
	npc.losValue = visible
	npc.losPoint = point
	npc.losUntil = now + LOS_CACHE
	return visible
end

-- Movimento -----------------------------------------------------------------------------------------

function Brain.MoveTo(npc, position: Vector3, now: number)
	local humanoid: Humanoid? = npc.humanoid
	if not humanoid then
		return
	end
	humanoid:MoveTo(position)
	npc.lastMoveTo = now
	npc.lastGoal = position
end

-- Para no lugar (sem detecção de travamento).
function Brain.Stop(npc)
	local humanoid: Humanoid? = npc.humanoid
	if humanoid and npc.root.Parent then
		humanoid:MoveTo(npc.root.Position)
	end
	npc.wantsMove = false
	npc.waypoints = nil
	npc.lastGoal = nil
end

-- Vira o NPC (só no plano) para olhar `position`.
function Brain.Face(npc, position: Vector3)
	local root: BasePart = npc.root
	local here = root.Position
	local flat = Vector3.new(position.X - here.X, 0, position.Z - here.Z)
	if flat.Magnitude < 0.1 then
		return
	end
	root.CFrame = CFrame.lookAt(here, here + flat.Unit)
end

function Brain.IsGrounded(npc): boolean
	local humanoid: Humanoid? = npc.humanoid
	return humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
end

local function requestPath(npc, goal: Vector3, now: number)
	if npc.computing or computing >= MAX_CONCURRENT_PATHS then
		return
	end
	local path: Path? = npc.path
	if not path then
		local def = npc.def
		local ok, created = pcall(function()
			return PathfindingService:CreatePath({
				AgentRadius = def.agentRadius,
				AgentHeight = def.agentHeight,
				AgentCanJump = true,
				AgentCanClimb = false,
				WaypointSpacing = 4,
			})
		end)
		if not ok or not created then
			npc.lastPathTime = now
			return
		end
		path = created
		npc.path = created
	end
	npc.computing = true
	npc.lastPathTime = now
	computing += 1
	local start = npc.root.Position
	local activePath = path :: Path
	task.spawn(function()
		local ok = pcall(function()
			activePath:ComputeAsync(start, goal)
		end)
		computing -= 1
		npc.computing = false
		if not npc.alive then
			return
		end
		if ok and activePath.Status == Enum.PathStatus.Success then
			local waypoints = activePath:GetWaypoints()
			if #waypoints >= 2 then
				npc.waypoints = waypoints
				npc.waypointIndex = 2 -- o primeiro é o próprio ponto de partida
				npc.movingToIndex = 0
				npc.pathGoal = goal
				npc.pathFailedUntil = nil
				return
			end
		end
		-- Sem caminho: segue direto por um tempo (a detecção de travamento ajuda) e tenta de novo depois.
		npc.waypoints = nil
		npc.pathGoal = goal
		npc.pathFailedUntil = os.clock() + PATH_RETRY_AFTER_FAIL
	end)
end

local function followWaypoints(npc, now: number, goal: Vector3)
	local waypoints = npc.waypoints
	local position = npc.root.Position
	local feetY = position.Y - npc.feetOffset
	local reach = npc.def.waypointReach
	local index = npc.waypointIndex or 2
	while index <= #waypoints do
		local point = waypoints[index].Position
		if flatDistance(point, position) <= reach and math.abs(point.Y - feetY) < 5 then
			index += 1
		else
			break
		end
	end
	npc.waypointIndex = index
	if index > #waypoints then
		npc.waypoints = nil
		Brain.MoveTo(npc, goal, now)
		return
	end
	local waypoint = waypoints[index]
	if index ~= npc.movingToIndex or now - (npc.lastMoveTo or 0) >= 1 then
		npc.movingToIndex = index
		Brain.MoveTo(npc, waypoint.Position, now)
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			npc.humanoid.Jump = true
		end
	end
end

-- Verifica se o NPC está preso (quer andar e não sai do lugar) e reage em degraus.
function Brain.CheckStuck(npc, now: number)
	if now - (npc.stuckCheckTime or 0) < STUCK_INTERVAL then
		return
	end
	local position = npc.root.Position
	local last: Vector3? = npc.stuckCheckPos
	npc.stuckCheckTime = now
	npc.stuckCheckPos = position
	if not last or not npc.wantsMove then
		npc.stuckCount = 0
		return
	end
	if flatDistance(position, last) >= STUCK_MIN_MOVE then
		npc.stuckCount = 0
		return
	end
	local humanoid: Humanoid = npc.humanoid
	npc.stuckCount = (npc.stuckCount or 0) + 1
	if npc.stuckCount == 1 then
		humanoid.Jump = true
	elseif npc.stuckCount == 2 then
		humanoid.Jump = true
		npc.waypoints = nil
		npc.lastPathTime = -math.huge
		npc.pathFailedUntil = nil
		npc.forcePathUntil = now + FORCE_PATH_TIME
	else
		-- Desvia para um lado (e um pouco para trás) e tenta de novo.
		local look = npc.root.CFrame.LookVector
		local side = Vector3.new(-look.Z, 0, look.X)
		if npc.rng:NextNumber() < 0.5 then
			side = -side
		end
		Brain.MoveTo(npc, position + side * 6 - flatUnit(look) * 2, now)
		humanoid.Jump = true
		npc.sidestepUntil = now + SIDESTEP_TIME
		npc.waypoints = nil
		npc.stuckCount = 1
	end
end

-- Persegue `goal`. `canSee`: true = já se sabe que há visão; false = sem visão; nil = calcula.
-- `arrive`: a partir desta distância (XZ) o NPC só se ajeita (sem detecção de travamento).
function Brain.ChaseTo(npc, now: number, goal: Vector3, canSee: boolean?, arrive: number?)
	if not npc.humanoid then
		return
	end
	if now < (npc.sidestepUntil or 0) then
		return
	end
	local position = npc.root.Position
	local offset = goal - position
	local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
	npc.wantsMove = flat > (arrive or 0)

	local forcePath = now < (npc.forcePathUntil or 0)
	local direct = false
	if not forcePath and flat <= DIRECT_RANGE and math.abs(offset.Y) <= DIRECT_MAX_DY then
		if canSee == nil then
			direct = Brain.LineOfSight(npc, now, goal)
		else
			direct = canSee
		end
	end
	local pathFailed = npc.pathFailedUntil ~= nil and now < npc.pathFailedUntil

	if direct or (pathFailed and not forcePath) then
		-- Vendo o alvo (ou sem caminho calculável): vai reto; a detecção de travamento cuida do resto.
		npc.waypoints = nil
		local lastGoal: Vector3? = npc.lastGoal
		if now - (npc.lastMoveTo or 0) >= MOVE_REFRESH or not lastGoal or (lastGoal - goal).Magnitude > 3 then
			Brain.MoveTo(npc, goal, now)
		end
	else
		local waypoints = npc.waypoints
		local pathGoal: Vector3? = npc.pathGoal
		local stale = waypoints == nil
			or (npc.waypointIndex or 2) > #waypoints
			or (pathGoal ~= nil and (pathGoal - goal).Magnitude > GOAL_MOVED)
		if
			(stale or forcePath)
			and not npc.computing
			and now - (npc.lastPathTime or -math.huge) >= GameConfig.NPC_PATH_RECOMPUTE
		then
			requestPath(npc, goal, now)
		end
		if npc.waypoints then
			followWaypoints(npc, now, goal)
		elseif now - (npc.lastMoveTo or 0) >= MOVE_REFRESH then
			Brain.MoveTo(npc, goal, now)
		end
	end
	Brain.CheckStuck(npc, now)
end

-- Passeia perto de onde nasceu (sem caminho calculado: barato).
function Brain.Wander(npc, now: number, radius: number?)
	npc.wantsMove = false
	if now < (npc.nextWander or 0) then
		return
	end
	local rng: Random = npc.rng
	npc.nextWander = now + rng:NextNumber(3, 6)
	local range = radius or 16
	local angle = rng:NextNumber(0, math.pi * 2)
	local distance = rng:NextNumber(range * 0.3, range)
	local home: Vector3 = npc.home
	local candidate = home + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
	local ground = Effects.Ground(candidate, 30, 8)
	if ground then
		Brain.MoveTo(npc, ground, now)
	end
end

-- Ataque corpo a corpo com cooldown. Retorna true se acertou.
function Brain.Melee(npc, now: number, player: Player, targetRoot: BasePart, range: number?): boolean
	if now < (npc.nextAttack or 0) then
		return false
	end
	local def = npc.def
	local offset = targetRoot.Position - npc.root.Position
	if offset.Magnitude > (range or def.attackRange) or math.abs(offset.Y) > 6 then
		return false
	end
	npc.nextAttack = now + def.attackCooldown
	CombatUtil.DamagePlayer(player, npc.damage, def.displayName)
	return true
end

-- Animação ------------------------------------------------------------------------------------------

local function resetGait(gait)
	for _, joint in gait.joints do
		joint.motor.C0 = joint.base
	end
end

-- Balança as pernas enquanto anda (C0 dos Motor6D a ~8 Hz); parado ou longe de todos, volta ao normal.
function Brain.Animate(npc, now: number)
	local gait = npc.rig.gait
	if not gait or now - (npc.lastGait or 0) < GAIT_INTERVAL then
		return
	end
	local dt = math.min(now - (npc.lastGait or now), 0.3)
	npc.lastGait = now
	local root: BasePart = npc.root
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local near = (npc.targetDistance or math.huge) <= GAIT_NEAR
	if speed > GAIT_MIN_SPEED and near then
		local phase = (npc.gaitPhase or 0) + dt * math.min(speed * gait.rate, MAX_GAIT_RATE)
		npc.gaitPhase = phase % (math.pi * 2)
		for _, joint in gait.joints do
			local angle = npc.gaitPhase + joint.phase
			if joint.mode == "swing" then
				joint.motor.C0 = joint.base * CFrame.Angles(math.sin(angle) * joint.amp, 0, 0)
			else
				local lift = math.max(math.sin(angle), 0) * joint.lift
				joint.motor.C0 = joint.base * CFrame.new(0, lift, -math.cos(angle) * joint.stride)
			end
		end
		npc.gaitActive = true
	elseif npc.gaitActive then
		npc.gaitActive = false
		resetGait(gait)
	end
end

return Brain
