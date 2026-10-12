--!nonstrict
-- IA d'O Caçador: humanoide de blocos com rifle. Mantém distância (30 a 60 studs), recua se alguém chega
-- perto e atira de longe:
--   1. mira por 1,2 s com um laser vermelho travado na posição do alvo NO INÍCIO da mira (dá para desviar);
--   2. dispara: raio do cano até o ponto mirado (e além); o primeiro jogador no caminho leva 30 de dano;
--      parede quebrável no caminho leva um impacto (DestructionService); traço "tracer" para todos.
-- Persistente: sem ninguém no raio, vai atrás do jogador vivo mais próximo onde quer que esteja.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local PartBuilder = require(ReplicatedStorage.Shared.Util.PartBuilder)

local CombatUtil = require(script.Parent.Parent.CombatUtil)
local Brain = require(script.Parent.Brain)
local Effects = require(script.Parent.Effects)

local HunterAI = {}

local MIN_DISTANCE, MAX_DISTANCE = 30, 60
local SHOOT_RANGE = 95
local AIM_TIME = 1.2
local AIM_WARN_TIME = 0.8 -- o laser engrossa: o tiro está chegando
local SHOT_EXTRA_RANGE = 30
local MAX_SHOT_RANGE = 180
local RECOVER_TIME = 0.45
local FIRST_SHOT_DELAY = 2
local RETREAT_STEP = 16
local RETREAT_REPICK = 0.8
local STRAFE_STEP = 8
local STRAFE_SWITCH = 2.5
local ISLAND_SAFE_MARGIN = 25 -- não recua para fora da ilha
local WALL_FRACTURE_IMPULSE = 35
local LASER_COLOR = Color3.fromRGB(255, 30, 30)
local TRACER_COLOR = Color3.fromRGB(255, 214, 140)
local SOURCE = "O Caçador"

-- Laser ----------------------------------------------------------------------------------------------

local function clearLaser(npc)
	local laser = npc.memory.laser
	npc.memory.laser = nil
	if laser then
		for _, item in laser do
			if typeof(item) == "Instance" and item.Parent then
				item:Destroy()
			end
		end
	end
end

local function createLaser(npc, aimPoint: Vector3)
	clearLaser(npc)
	local muzzle: Attachment? = npc.rig.extras.muzzle
	if not muzzle or not muzzle.Parent then
		return
	end
	local finish = Instance.new("Attachment")
	finish.Name = "MiraDoCacador"
	finish.Parent = workspace.Terrain
	finish.WorldPosition = aimPoint

	local beam = Instance.new("Beam")
	beam.Name = "Laser"
	beam.Attachment0 = muzzle
	beam.Attachment1 = finish
	beam.Color = ColorSequence.new(LASER_COLOR)
	beam.Width0 = 0.12
	beam.Width1 = 0.12
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Transparency = NumberSequence.new(0.15)
	beam.Parent = muzzle.Parent

	local dot = PartBuilder.part({
		Name = "PontoVermelho",
		Color = LASER_COLOR,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanTouch = false,
		CastShadow = false,
	}) :: Part
	dot.CanQuery = false
	dot.Shape = Enum.PartType.Ball
	dot.Size = Vector3.new(0.7, 0.7, 0.7)
	dot.CFrame = CFrame.new(aimPoint)
	dot.Parent = Effects.Folder()

	npc.memory.laser = { finish, beam, dot }
	npc.memory.beam = beam
end

-- Tiro -----------------------------------------------------------------------------------------------

local function fire(npc, now: number)
	local memory = npc.memory
	local aimPoint: Vector3 = memory.aimPoint
	local muzzle: Attachment? = npc.rig.extras.muzzle
	local origin = if muzzle and muzzle.Parent then muzzle.WorldPosition else Brain.EyePosition(npc)
	local direction = aimPoint - origin
	if direction.Magnitude < 1 then
		direction = npc.root.CFrame.LookVector
	end
	local range = math.min(direction.Magnitude + SHOT_EXTRA_RANGE, MAX_SHOT_RANGE)
	local player, hitPosition, world = Effects.CastShot(origin, direction, range)
	if player then
		CombatUtil.DamagePlayer(player, npc.damage, SOURCE)
	elseif world and world.Instance then
		local destruction = Effects.GetDestruction()
		local hitPart = world.Instance
		if destruction and type(destruction.Fracture) == "function" and hitPart:IsA("BasePart") then
			local ok, err = pcall(destruction.Fracture, hitPart, world.Position, WALL_FRACTURE_IMPULSE)
			if not ok then
				warn("[HunterAI] Erro ao quebrar a parede atingida: " .. tostring(err))
			end
		end
	end
	Effects.Tracer(origin, hitPosition, TRACER_COLOR, 0.14)
	-- O som do tiro não passa pelo limite de repetição (cada tiro é importante para o jogador reagir).
	Effects.Sound("Gunshot", origin, { Volume = 0.9, RollOffMaxDistance = 400 })
	clearLaser(npc)
	memory.nextShot = now + npc.def.attackCooldown
	memory.state = "recover"
	memory.recoverUntil = now + RECOVER_TIME
end

local function startAim(npc, now: number, targetRoot: BasePart)
	local memory = npc.memory
	Brain.Stop(npc)
	if npc.humanoid then
		npc.humanoid.AutoRotate = false
	end
	memory.aimPoint = targetRoot.Position
	memory.aimStart = now
	memory.warned = false
	memory.state = "aim"
	Brain.Face(npc, memory.aimPoint)
	createLaser(npc, memory.aimPoint)
	Effects.Sound("Reload", npc.root.Position, { Volume = 0.7, RollOffMaxDistance = 120 })
end

-- Movimento ------------------------------------------------------------------------------------------

local function insideIsland(position: Vector3): boolean
	return Brain.FlatDistance(position, GameConfig.ISLAND_CENTER) <= GameConfig.ISLAND_RADIUS - ISLAND_SAFE_MARGIN
end

-- Ponto livre a `step` studs na direção `direction` (sem parede no meio e com chão). Ou nil.
local function freeSpot(npc, direction: Vector3, step: number): Vector3?
	local root: BasePart = npc.root
	local origin = root.Position
	local hit = workspace:Raycast(origin, direction * step, Effects.WorldParams())
	if hit then
		return nil
	end
	local candidate = origin + direction * step
	if not insideIsland(candidate) then
		return nil
	end
	return Effects.Ground(candidate, 14, 4)
end

local function rotate(direction: Vector3, angle: number): Vector3
	return (CFrame.Angles(0, angle, 0) * direction).Unit
end

local function retreat(npc, now: number, targetRoot: BasePart): boolean
	local memory = npc.memory
	local goal: Vector3? = memory.retreatGoal
	if goal and now < (memory.retreatUntil or 0) then
		npc.wantsMove = true
		if now - (npc.lastMoveTo or 0) >= 0.4 then
			Brain.MoveTo(npc, goal, now)
		end
		Brain.CheckStuck(npc, now)
		return true
	end
	local away = Brain.FlatUnit(npc.root.Position - targetRoot.Position, -npc.root.CFrame.LookVector)
	for _, angle in { 0, 0.7, -0.7, 1.4, -1.4 } do
		local spot = freeSpot(npc, rotate(away, angle), RETREAT_STEP)
		if spot then
			memory.retreatGoal = spot
			memory.retreatUntil = now + RETREAT_REPICK
			npc.wantsMove = true
			Brain.MoveTo(npc, spot, now)
			return true
		end
	end
	memory.retreatGoal = nil
	return false
end

local function strafe(npc, now: number, targetRoot: BasePart)
	local memory = npc.memory
	if now >= (memory.nextStrafeSwitch or 0) then
		memory.nextStrafeSwitch = now + STRAFE_SWITCH
		memory.strafeSign = -(memory.strafeSign or 1)
		local toTarget = Brain.FlatUnit(targetRoot.Position - npc.root.Position)
		local side = Vector3.new(-toTarget.Z, 0, toTarget.X) * memory.strafeSign
		local spot = freeSpot(npc, side, STRAFE_STEP) or freeSpot(npc, -side, STRAFE_STEP)
		if spot then
			Brain.MoveTo(npc, spot, now)
		end
	end
	npc.wantsMove = false
end

-- Ciclo ----------------------------------------------------------------------------------------------

function HunterAI.Setup(npc, now: number)
	local memory = npc.memory
	memory.state = "move"
	memory.nextShot = now + FIRST_SHOT_DELAY
	memory.strafeSign = if npc.rng:NextNumber() < 0.5 then 1 else -1
	memory.nextStrafeSwitch = now
	Effects.Burst(npc.root.Position, Color3.fromRGB(120, 100, 70))
end

function HunterAI.Think(npc, now: number, _dt: number): number?
	local memory = npc.memory
	local def = npc.def

	if memory.state == "aim" then
		Brain.Face(npc, memory.aimPoint)
		if not memory.warned and now - memory.aimStart >= AIM_WARN_TIME then
			memory.warned = true
			local beam: Beam? = memory.beam
			if beam and beam.Parent then
				beam.Width0 = 0.25
				beam.Width1 = 0.25
			end
		end
		if now - memory.aimStart >= AIM_TIME then
			fire(npc, now)
			return 0.1
		end
		return 0.05
	elseif memory.state == "recover" then
		if now < memory.recoverUntil then
			return 0.1
		end
		memory.state = "move"
		if npc.humanoid then
			npc.humanoid.AutoRotate = true
		end
	end

	local _target, targetRoot, distance = Brain.UpdateTarget(npc, now)
	if not targetRoot then
		Brain.Wander(npc, now, 20)
		return def.idleInterval
	end

	local canSee = Brain.LineOfSight(npc, now, targetRoot.Position)
	if canSee and distance <= SHOOT_RANGE and now >= memory.nextShot then
		startAim(npc, now, targetRoot)
		return 0.05
	end

	if distance < MIN_DISTANCE then
		if not retreat(npc, now, targetRoot) then
			strafe(npc, now, targetRoot)
		end
	elseif distance > MAX_DISTANCE or not canSee then
		memory.retreatGoal = nil
		Brain.ChaseTo(npc, now, targetRoot.Position, canSee)
	else
		memory.retreatGoal = nil
		strafe(npc, now, targetRoot)
	end
	return nil
end

function HunterAI.Cleanup(npc)
	clearLaser(npc)
	if npc.humanoid and npc.humanoid.Parent then
		npc.humanoid.AutoRotate = true
	end
end

return HunterAI
