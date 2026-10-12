--!nonstrict
-- Animação procedural dos personagens R6 (somente cliente). Não usa assets de animação: cada cliente
-- calcula a pose de TODOS os personagens a partir da velocidade, do estado e do que estão segurando, e
-- escreve em Motor6D.Transform (que não replica). Assim todo mundo vê todo mundo animado.
--
--   R6Animator.Init()                          -- anima os personagens dos jogadores (idempotente)
--   R6Animator.Register(model, opts?): () -> () -- anima um modelo extra (ex.: boneco do menu)
--       opts.pose = "idle" | "menu"            -- "menu": parado, olhando em volta devagar
--   R6Animator.SetLocalClimbing(climbing)      -- o Movement avisa na hora (o atributo do servidor demora)
--
-- Poses: parado (respiração), andando, correndo (inclina e balança mais), no ar (subindo/caindo),
-- escalando (braços alternando acima da cabeça) e segurando uma ferramenta (braço direito à frente).
-- Eixos dos Motor6D do R6: ombros e quadris giram em Z (direito: + = para frente; esquerdo: + = para trás);
-- RootJoint/Neck: X + = inclina para frente, Z = para cima.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local R6Animator = {}

local RUN_SPEED = 20 -- acima disto (studs/s) a pose é de corrida
local WALK_STRIDE = 7.5 -- studs por ciclo de passo andando
local RUN_STRIDE = 11
local AIR_SPEED = 4 -- |velocidade vertical| acima disto = no ar
local SMOOTHING = 14
local HALF_PI = math.pi / 2

type Rig = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	joints: { [string]: Motor6D },
	pose: string,
	phase: number,
	current: { [string]: number },
	isLocal: boolean,
	airTime: number,
}

local rigs: { [Model]: Rig } = {}
local initialized = false
local localClimbing = false
local LocalPlayer = Players.LocalPlayer

local JOINT_NAMES = {
	rootJoint = { "HumanoidRootPart", "RootJoint" },
	neck = { "Torso", "Neck" },
	rightShoulder = { "Torso", "Right Shoulder" },
	leftShoulder = { "Torso", "Left Shoulder" },
	rightHip = { "Torso", "Right Hip" },
	leftHip = { "Torso", "Left Hip" },
}

-- Valores animados (todos suavizados).
local KEYS = { "rs", "ls", "rh", "lh", "lean", "bob", "neckPitch", "neckYaw" }

local function findJoints(model: Model): { [string]: Motor6D }?
	local joints = {}
	for key, path in JOINT_NAMES do
		local parent = model:FindFirstChild(path[1])
		local joint = parent and parent:FindFirstChild(path[2])
		if not joint or not joint:IsA("Motor6D") then
			return nil
		end
		joints[key] = joint
	end
	return joints
end

local function unregister(model: Model)
	local rig = rigs[model]
	if not rig then
		return
	end
	rigs[model] = nil
	for _, joint in rig.joints do
		if joint.Parent then
			joint.Transform = CFrame.identity
		end
	end
end

function R6Animator.Register(model: Model, opts: { [string]: any }?): () -> ()
	if rigs[model] then
		unregister(model)
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R6 or not root or not root:IsA("BasePart") then
		return function() end
	end
	local joints = findJoints(model)
	if not joints then
		return function() end
	end
	local current = {}
	for _, key in KEYS do
		current[key] = 0
	end
	rigs[model] = {
		model = model,
		humanoid = humanoid,
		root = root,
		joints = joints,
		pose = opts and opts.pose or "auto",
		phase = math.random() * math.pi * 2,
		current = current,
		isLocal = Players:GetPlayerFromCharacter(model) == LocalPlayer,
		airTime = 0,
	}
	local connection
	connection = model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			connection:Disconnect()
			unregister(model)
		end
	end)
	return function()
		connection:Disconnect()
		unregister(model)
	end
end

function R6Animator.SetLocalClimbing(climbing: boolean)
	localClimbing = climbing == true
end

-- Pose alvo ------------------------------------------------------------------------------------

local function isAirborne(rig: Rig, verticalSpeed: number): boolean
	if rig.isLocal then
		local state = rig.humanoid:GetState()
		return state == Enum.HumanoidStateType.Freefall
			or state == Enum.HumanoidStateType.Jumping
			or rig.humanoid.FloorMaterial == Enum.Material.Air
	end
	return math.abs(verticalSpeed) > AIR_SPEED
end

local function targetPose(rig: Rig, dt: number, now: number): { [string]: number }
	local t = {}
	for _, key in KEYS do
		t[key] = 0
	end

	if rig.pose == "menu" then
		t.rs = math.sin(now * 1.1) * 0.05
		t.ls = math.sin(now * 1.1 + 1) * 0.05
		t.bob = math.sin(now * 1.6) * 0.04
		t.neckYaw = math.sin(now * 0.37) * 0.35
		t.neckPitch = 0.12 + math.sin(now * 0.23) * 0.06
		return t
	end

	local velocity = rig.root.AssemblyLinearVelocity
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local climbing = if rig.isLocal then localClimbing else rig.model:GetAttribute("MoveState") == "climb"
	local holding = rig.model:FindFirstChildOfClass("Tool") ~= nil

	if climbing then
		rig.phase += dt * math.clamp(math.abs(velocity.Y) * 0.7 + 2, 2, 10)
		local swing = math.sin(rig.phase)
		local reach = math.pi - 0.35
		t.rs = reach + swing * 0.4
		t.ls = -reach + swing * 0.4
		t.rh = 0.55 + swing * 0.45
		t.lh = -0.55 + swing * 0.45
		t.lean = -0.08
		t.neckPitch = -0.35
		return t
	end

	local airborne = isAirborne(rig, velocity.Y)
	if airborne then
		rig.airTime += dt
	else
		rig.airTime = 0
	end

	if airborne and rig.airTime > 0.08 then
		if velocity.Y > 0 then
			-- subindo: braços para cima, uma perna dobrada à frente
			t.rs = 2.4
			t.ls = -2.4
			t.rh = 0.5
			t.lh = 0.3
		else
			-- caindo: braços abertos à frente, pernas soltas
			local flail = math.sin(now * 9) * 0.12
			t.rs = 1.3 + flail
			t.ls = -1.3 + flail
			t.rh = 0.25
			t.lh = -0.25
			t.lean = -0.1
		end
	elseif horizontal > 0.6 then
		local running = horizontal >= RUN_SPEED
		local stride = if running then RUN_STRIDE else WALK_STRIDE
		rig.phase += dt * (horizontal / stride) * math.pi * 2
		local amount = math.clamp(horizontal / 16, 0.35, 1)
		local legAmp = (if running then 1.0 else 0.6) * amount
		local armAmp = (if running then 1.05 else 0.55) * amount
		local swing = math.sin(rig.phase)
		t.rs = swing * armAmp + (if running then 0.25 else 0)
		t.ls = swing * armAmp - (if running then 0.25 else 0)
		t.rh = -swing * legAmp
		t.lh = -swing * legAmp
		t.lean = if running then 0.22 else 0.05
		t.bob = math.abs(math.cos(rig.phase)) * (if running then 0.32 else 0.14)
		t.neckPitch = if running then -0.12 else 0
	else
		-- parado: respiração
		t.rs = math.sin(now * 1.4) * 0.04
		t.ls = math.sin(now * 1.4) * 0.04
		t.bob = math.sin(now * 1.8) * 0.035
		t.neckPitch = math.sin(now * 0.5) * 0.03
	end

	if holding then
		t.rs = HALF_PI + t.rs * 0.1
	end
	return t
end

-- Aplicação ------------------------------------------------------------------------------------

local function apply(rig: Rig, dt: number, now: number)
	local target = targetPose(rig, dt, now)
	local alpha = 1 - math.exp(-SMOOTHING * dt)
	local c = rig.current
	for _, key in KEYS do
		c[key] += (target[key] - c[key]) * alpha
	end
	local j = rig.joints
	j.rightShoulder.Transform = CFrame.Angles(0, 0, c.rs)
	j.leftShoulder.Transform = CFrame.Angles(0, 0, c.ls)
	j.rightHip.Transform = CFrame.Angles(0, 0, c.rh)
	j.leftHip.Transform = CFrame.Angles(0, 0, c.lh)
	j.rootJoint.Transform = CFrame.new(0, 0, c.bob) * CFrame.Angles(c.lean, 0, 0)
	j.neck.Transform = CFrame.Angles(c.neckPitch, 0, c.neckYaw)
end

local function step(dt: number)
	local now = os.clock()
	for model, rig in rigs do
		if not model.Parent then
			rigs[model] = nil
		elseif rig.humanoid.Health > 0 and rig.root.Parent then
			apply(rig, math.min(dt, 0.1), now)
		end
	end
end

local function watchPlayer(player: Player)
	local function onCharacter(character: Model)
		task.spawn(function()
			-- As juntas podem chegar alguns frames depois do modelo.
			local torso = character:WaitForChild("Torso", 10)
			local root = character:WaitForChild("HumanoidRootPart", 10)
			if not torso or not root then
				return
			end
			torso:WaitForChild("Right Hip", 5)
			root:WaitForChild("RootJoint", 5)
			if character.Parent and player.Character == character then
				R6Animator.Register(character)
			end
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

function R6Animator.Init()
	if initialized then
		return
	end
	initialized = true
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	RunService.PreSimulation:Connect(step)
end

return R6Animator
