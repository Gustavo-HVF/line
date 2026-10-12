--!nonstrict
-- Corrida com estamina e escalada de paredes (somente cliente).
--   * Correr: segure Shift (PC), aperte L3 (controle) ou toque em "Correr" (celular, liga/desliga).
--     Gasta estamina; sem estamina, só volta a correr depois de recuperar um pouco.
--   * Escalar: olhe para uma parede e segure Pular. Sobe enquanto houver estamina; ao chegar no topo,
--     dá um impulso para subir na borda. Soltar o pulo ou acabar a estamina = cai.
--   * Barra de estamina logo abaixo da mira (some quando está cheia).
--
--   Movement.Enable(opts?)   opts.climb: boolean? (padrão true)
--   Movement.Disable()
--   Movement.GetStamina(): number  (0..100)
--
-- Velocidade: o servidor pode mudar o WalkSpeed (lentidão de eventos e NPCs). O valor que vem do servidor é
-- a base; correr multiplica a base, e personagem lento não corre.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local UIKit = require(ReplicatedStorage.Shared.UI.UIKit)

local FirstPerson = require(script.Parent.FirstPerson)
local R6Animator = require(script.Parent.R6Animator)

local Movement = {}

local SPRINT_ACTION = "SelvaCorrer"
local STAMINA_MAX = 100
local RUN_MULTIPLIER = 1.65
local MIN_RUN_BASE = 14 -- base menor que isto (lento) não corre
local RUN_DRAIN = 16 -- por segundo
local CLIMB_DRAIN = 20
local REGEN = 22
local REGEN_DELAY = 0.9
local RESUME_AT = 25 -- depois de esgotar, só volta a correr com isto
local MIN_TO_CLIMB = 8
local CLIMB_SPEED = 11
local CLIMB_SIDE_SPEED = 5
local CLIMB_STICK = 3
local WALL_REACH = 2.4
local JUMP_HOLD_WINDOW = 0.22
local MANTLE_UP = 30
local MANTLE_FORWARD = 12

local LocalPlayer = Players.LocalPlayer

local enabled = false
local climbAllowed = true
local stamina = STAMINA_MAX
local lastSpend = 0
local exhausted = false
local sprintHeld = false -- teclado: segurar
local sprintToggled = false -- celular/controle: liga/desliga
local running = false
local climbing = false
local climbNormal = Vector3.zero
local jumpRequestedAt = -math.huge
local baseSpeed = 16
local lastWrittenSpeed: number? = nil
local sentState = "none"
local connections: { RBXScriptConnection } = {}
local characterConnections: { RBXScriptConnection } = {}
local moveRemote: RemoteEvent? = nil

local ui = nil
local barVisible = false

-- Interface ----------------------------------------------------------------------------------------

local function ensureUI()
	if ui then
		return ui
	end
	local gui = UIKit.ScreenGui("Estamina", 4)
	local holder = UIKit.Create("CanvasGroup", {
		Name = "Barra",
		-- logo abaixo da mira: fica no campo de visão sem cobrir o painel da arma nem a barra de itens
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 70),
		Size = UDim2.fromOffset(190, 10),
		BackgroundColor3 = Color3.fromRGB(18, 22, 16),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Parent = gui,
	}) :: CanvasGroup
	UIKit.Corner(holder, UDim.new(1, 0))
	UIKit.Stroke(holder, Color3.fromRGB(222, 180, 70), 1)
	local fill = UIKit.Create("Frame", {
		Name = "Preenchimento",
		BackgroundColor3 = Color3.fromRGB(120, 200, 90),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	}) :: Frame
	UIKit.Corner(fill, UDim.new(1, 0))
	ui = { gui = gui, holder = holder, fill = fill }
	return ui
end

local function setBarVisible(visible: boolean)
	if visible == barVisible or not ui then
		return
	end
	barVisible = visible
	TweenService:Create(ui.holder, TweenInfo.new(if visible then 0.15 else 0.6), {
		GroupTransparency = if visible then 0 else 1,
	}):Play()
end

local function updateBar()
	local view = ensureUI()
	local ratio = stamina / STAMINA_MAX
	view.fill.Size = UDim2.fromScale(math.max(ratio, 0.001), 1)
	local color
	if exhausted then
		color = Color3.fromRGB(200, 70, 50)
	elseif ratio < 0.3 then
		color = Color3.fromRGB(226, 150, 40)
	else
		color = Color3.fromRGB(120, 200, 90)
	end
	view.fill.BackgroundColor3 = color
	setBarVisible(stamina < STAMINA_MAX - 0.5 or running or climbing)
end

-- Estado replicado (para os outros verem a animação de escalada) ------------------------------------

local function sendState(state: string)
	if state == sentState then
		return
	end
	sentState = state
	local remote = moveRemote or Net.event(Net.Names.Char_MoveState)
	moveRemote = remote
	remote:FireServer(state)
end

local function setClimbing(value: boolean)
	if climbing == value then
		return
	end
	climbing = value
	R6Animator.SetLocalClimbing(value)
	FirstPerson.SetClimbing(value)
	sendState(if value then "climb" else "none")
end

-- Personagem ---------------------------------------------------------------------------------------

local function getCharacter(): (Model?, Humanoid?, BasePart?)
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function writeSpeed(humanoid: Humanoid, speed: number)
	if math.abs(humanoid.WalkSpeed - speed) > 0.01 then
		lastWrittenSpeed = speed
		humanoid.WalkSpeed = speed
	end
end

local function disconnectCharacter()
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
end

local function onCharacter(character: Model)
	disconnectCharacter()
	setClimbing(false)
	running = false
	stamina = STAMINA_MAX
	exhausted = false
	lastWrittenSpeed = nil
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or LocalPlayer.Character ~= character then
		return
	end
	baseSpeed = humanoid.WalkSpeed
	table.insert(
		characterConnections,
		humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			-- Valor diferente do que este script escreveu = veio do servidor (lentidão ou fim dela).
			if lastWrittenSpeed == nil or math.abs(humanoid.WalkSpeed - lastWrittenSpeed) > 0.01 then
				baseSpeed = humanoid.WalkSpeed
				lastWrittenSpeed = nil
			end
		end)
	)
end

-- Escalada -----------------------------------------------------------------------------------------

local function wallRay(character: Model, origin: Vector3, direction: Vector3): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	params.RespectCanCollide = true
	return workspace:Raycast(origin, direction, params)
end

local function flatLook(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function isWall(result: RaycastResult?): boolean
	return result ~= nil and math.abs(result.Normal.Y) < 0.35
end

local function jumpHeld(): boolean
	return os.clock() - jumpRequestedAt < JUMP_HOLD_WINDOW
end

local function stepClimb(dt: number, character: Model, humanoid: Humanoid, root: BasePart)
	if not climbAllowed or humanoid.Sit or humanoid:GetState() == Enum.HumanoidStateType.Swimming then
		setClimbing(false)
		return
	end
	local look = flatLook(root)
	if not climbing then
		if not jumpHeld() or stamina < MIN_TO_CLIMB then
			return
		end
		local hit = wallRay(character, root.Position, look * WALL_REACH)
		if not isWall(hit) then
			return
		end
		climbNormal = Vector3.new(hit.Normal.X, 0, hit.Normal.Z).Unit
		setClimbing(true)
	end

	local intoWall = -climbNormal
	local chest = wallRay(character, root.Position, intoWall * (WALL_REACH + 0.6))
	if not isWall(chest) then
		-- passou do topo: um empurrãozinho para subir na borda
		root.AssemblyLinearVelocity = Vector3.new(0, MANTLE_UP * 0.6, 0) + intoWall * MANTLE_FORWARD
		setClimbing(false)
		return
	end
	climbNormal = Vector3.new(chest.Normal.X, 0, chest.Normal.Z).Unit
	local head = wallRay(character, root.Position + Vector3.new(0, 2.6, 0), intoWall * (WALL_REACH + 0.6))
	if not head then
		root.AssemblyLinearVelocity = Vector3.new(0, MANTLE_UP, 0) + intoWall * MANTLE_FORWARD
		setClimbing(false)
		return
	end
	if not jumpHeld() or stamina <= 0 then
		setClimbing(false)
		return
	end

	stamina = math.max(stamina - CLIMB_DRAIN * dt, 0)
	lastSpend = os.clock()
	if stamina <= 0 then
		exhausted = true
	end
	-- anda de lado ao longo da parede conforme o analógico
	local move = humanoid.MoveDirection
	local side = move - climbNormal * move:Dot(climbNormal)
	side = Vector3.new(side.X, 0, side.Z)
	local lateral = if side.Magnitude > 0.05
		then side.Unit * CLIMB_SIDE_SPEED * math.min(side.Magnitude, 1)
		else Vector3.zero
	root.AssemblyLinearVelocity = Vector3.new(0, CLIMB_SPEED, 0) + lateral + intoWall * CLIMB_STICK
end

-- Corrida ------------------------------------------------------------------------------------------

local function stepRun(dt: number, humanoid: Humanoid)
	local wants = sprintHeld or sprintToggled
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	if exhausted and stamina >= RESUME_AT then
		exhausted = false
	end
	running = wants and moving and not climbing and not exhausted and stamina > 0 and baseSpeed >= MIN_RUN_BASE
	if running then
		stamina = math.max(stamina - RUN_DRAIN * dt, 0)
		lastSpend = os.clock()
		if stamina <= 0 then
			exhausted = true
			sprintToggled = false
			running = false
		end
	elseif not climbing and os.clock() - lastSpend > REGEN_DELAY then
		stamina = math.min(stamina + REGEN * dt, STAMINA_MAX)
	end
	writeSpeed(humanoid, if running then baseSpeed * RUN_MULTIPLIER else baseSpeed)
end

local function step(dt: number)
	dt = math.min(dt, 0.1)
	local character, humanoid, root = getCharacter()
	if not character or not humanoid or not root then
		setClimbing(false)
		running = false
		return
	end
	stepClimb(dt, character, humanoid, root)
	stepRun(dt, humanoid)
	updateBar()
end

-- Entrada ------------------------------------------------------------------------------------------

local function onSprint(_name: string, inputState: Enum.UserInputState, input: InputObject)
	if input.UserInputType == Enum.UserInputType.Keyboard then
		sprintHeld = inputState == Enum.UserInputState.Begin
	elseif inputState == Enum.UserInputState.Begin then
		sprintToggled = not sprintToggled
	end
	-- Sink: o Shift não liga também a trava de câmera ("shift lock") do Roblox.
	return Enum.ContextActionResult.Sink
end

-- API ---------------------------------------------------------------------------------------------

function Movement.Enable(opts: { [string]: any }?)
	climbAllowed = not (opts and opts.climb == false)
	if enabled then
		return
	end
	enabled = true
	ensureUI()
	sprintHeld = false
	sprintToggled = false
	ContextActionService:BindAction(
		SPRINT_ACTION,
		onSprint,
		true,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift,
		Enum.KeyCode.ButtonL3
	)
	ContextActionService:SetTitle(SPRINT_ACTION, "Correr")
	table.insert(
		connections,
		UserInputService.JumpRequest:Connect(function()
			jumpRequestedAt = os.clock()
		end)
	)
	table.insert(connections, LocalPlayer.CharacterAdded:Connect(onCharacter))
	table.insert(connections, RunService.PreSimulation:Connect(step))
	if LocalPlayer.Character then
		task.spawn(onCharacter, LocalPlayer.Character)
	end
end

function Movement.Disable()
	if not enabled then
		return
	end
	enabled = false
	ContextActionService:UnbindAction(SPRINT_ACTION)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	disconnectCharacter()
	setClimbing(false)
	running = false
	sprintHeld = false
	sprintToggled = false
	local _, humanoid = getCharacter()
	if humanoid then
		writeSpeed(humanoid, baseSpeed)
	end
	lastWrittenSpeed = nil
	setBarVisible(false)
end

function Movement.GetStamina(): number
	return stamina
end

return Movement
