--!nonstrict
-- Câmera do jogador fora de jogo:
--   * eliminado (atributo Eliminated): segue um jogador vivo; botões ◀ ▶ e teclas Q / E trocam o alvo;
--     sem ninguém vivo, a câmera gira em volta do tabuleiro;
--   * ainda sem personagem (esperando nascer): a câmera gira devagar em volta do tabuleiro;
--   * jogando: devolve a câmera normal (Custom) para o próprio personagem.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local UIKit = require(ReplicatedStorage.Shared.UI.UIKit)

local Spectate = {}

local Theme = UIKit.Theme
local LocalPlayer = Players.LocalPlayer

local NEXT_ACTION = "SelvaEspectadorProximo"
local PREV_ACTION = "SelvaEspectadorAnterior"
local ORBIT_STEP = "SelvaOrbita"
local CHECK_INTERVAL = 0.5

local initialized = false
local mode: string? = nil -- "play" | "waiting" | "spectate"
local targetUserId: number? = nil
local orbitBound = false
local orbitWide = false
local orbitAngle = 0
local actionsBound = false
local hadCharacter = false -- quem nunca teve personagem (entrou depois do início) é só espectador
local ui: { [string]: any } = {}

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function aliveTargets(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player ~= LocalPlayer and not player:GetAttribute("Eliminated") and getHumanoid(player) then
			table.insert(list, player)
		end
	end
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	return list
end

-- Órbita ----------------------------------------------------------------------------------------

local function orbitFocus(): Vector3
	local boardFolder = workspace:FindFirstChild("Board")
	local boardModel = boardFolder and boardFolder:FindFirstChildOfClass("Model")
	if boardModel then
		return boardModel:GetPivot().Position
	end
	return GameConfig.ISLAND_CENTER + Vector3.new(0, GameConfig.GROUND_Y, 0)
end

local function orbitStep(deltaTime: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	orbitAngle += deltaTime * (orbitWide and 0.08 or 0.15)
	local radius = orbitWide and 70 or 12
	local height = orbitWide and 45 or 8
	local focus = orbitFocus()
	local eye = focus + Vector3.new(math.cos(orbitAngle) * radius, height, math.sin(orbitAngle) * radius)
	camera.CFrame = CFrame.lookAt(eye, focus)
end

local function startOrbit(wide: boolean)
	orbitWide = wide
	if orbitBound then
		return
	end
	orbitBound = true
	RunService:BindToRenderStep(ORBIT_STEP, Enum.RenderPriority.Camera.Value, orbitStep)
end

local function stopOrbit()
	if not orbitBound then
		return
	end
	orbitBound = false
	RunService:UnbindFromRenderStep(ORBIT_STEP)
end

-- Alvo do espectador --------------------------------------------------------------------------

local function refreshTarget()
	local camera = workspace.CurrentCamera
	local targets = aliveTargets()
	if #targets == 0 then
		targetUserId = nil
		ui.name.Text = "Ninguém vivo para assistir"
		startOrbit(true)
		return
	end
	local current = targets[1]
	for _, player in targets do
		if player.UserId == targetUserId then
			current = player
			break
		end
	end
	targetUserId = current.UserId
	stopOrbit()
	local humanoid = getHumanoid(current)
	if camera and humanoid then
		if camera.CameraType ~= Enum.CameraType.Custom then
			camera.CameraType = Enum.CameraType.Custom
		end
		if camera.CameraSubject ~= humanoid then
			camera.CameraSubject = humanoid
		end
	end
	ui.name.Text = ("Assistindo: %s"):format(current.DisplayName)
end

local function cycle(direction: number)
	if mode ~= "spectate" then
		return
	end
	local targets = aliveTargets()
	if #targets == 0 then
		refreshTarget()
		return
	end
	local index = 0
	for i, player in targets do
		if player.UserId == targetUserId then
			index = i
			break
		end
	end
	if index == 0 then
		index = 1
	else
		index = (index - 1 + direction) % #targets + 1
	end
	targetUserId = targets[index].UserId
	refreshTarget()
end

local function onAction(actionName: string, inputState: Enum.UserInputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	cycle(actionName == NEXT_ACTION and 1 or -1)
	return Enum.ContextActionResult.Sink
end

local function setActionsBound(bound: boolean)
	if bound == actionsBound then
		return
	end
	actionsBound = bound
	if bound then
		ContextActionService:BindAction(NEXT_ACTION, onAction, false, Enum.KeyCode.E, Enum.KeyCode.ButtonR1)
		ContextActionService:BindAction(PREV_ACTION, onAction, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
	else
		ContextActionService:UnbindAction(NEXT_ACTION)
		ContextActionService:UnbindAction(PREV_ACTION)
	end
end

-- Modos ------------------------------------------------------------------------------------------

local function setMode(newMode: string)
	if newMode == mode then
		return
	end
	mode = newMode
	stopOrbit()
	setActionsBound(false)
	ui.panel.Visible = false
	local camera = workspace.CurrentCamera

	if newMode == "play" then
		local humanoid = getHumanoid(LocalPlayer)
		if camera then
			camera.CameraType = Enum.CameraType.Custom
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
	elseif newMode == "waiting" then
		startOrbit(false)
	elseif newMode == "spectate" then
		ui.title.Text = hadCharacter and "Você foi eliminado" or "Modo espectador"
		if ui.reason.Text == "" then
			local reason = LocalPlayer:GetAttribute("LastDamageSource")
			ui.reason.Text = type(reason) == "string" and reason or ""
		end
		ui.panel.Visible = true
		setActionsBound(true)
		targetUserId = nil
		refreshTarget()
	end
end

local function evaluate()
	local character = LocalPlayer.Character
	if LocalPlayer:GetAttribute("Eliminated") == true then
		setMode("spectate")
		refreshTarget()
	elseif getHumanoid(LocalPlayer) then
		setMode("play")
	elseif not character or not character.Parent then
		setMode("waiting")
	end
	-- Personagem morto mas ainda não eliminado: mantém a câmera até o servidor confirmar.
end

local function build()
	local gui = UIKit.ScreenGui("Spectate", 8)
	local panel = UIKit.Panel({
		Name = "Espectador",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.fromOffset(440, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = 12,
		Visible = false,
		Parent = gui,
	})
	UIKit.ListLayout(panel, 6)
	local scale = Instance.new("UIScale")
	scale.Parent = panel

	ui.title = UIKit.Label({
		Text = "Você foi eliminado",
		Font = Theme.TitleFont,
		TextSize = 28,
		TextColor3 = Theme.Danger,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 1,
		Parent = panel,
	})
	ui.reason = UIKit.Label({
		Text = "",
		TextSize = 16,
		TextColor3 = Theme.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		Parent = panel,
	})

	local row = UIKit.Frame({ Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 3, Parent = panel })
	UIKit.Button({
		Text = "◀",
		Style = "ghost",
		Size = UDim2.fromOffset(56, 44),
		OnClick = function()
			cycle(-1)
		end,
		Parent = row,
	})
	ui.name = UIKit.Label({
		Text = "",
		Font = Theme.BoldFont,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(62, 0),
		Size = UDim2.new(1, -124, 1, 0),
		Parent = row,
	})
	UIKit.Button({
		Text = "▶",
		Style = "ghost",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(56, 44),
		OnClick = function()
			cycle(1)
		end,
		Parent = row,
	})
	UIKit.Label({
		Text = "Q / E (ou os botões) para trocar de jogador",
		TextSize = 15,
		TextColor3 = Theme.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 4,
		Parent = panel,
	})

	ui.gui = gui
	ui.panel = panel

	local function updateScale()
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
		scale.Scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.65, 1.1)
	end
	updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
end

function Spectate.Init()
	if initialized then
		return
	end
	initialized = true
	build()

	Net.event(Net.Names.Player_Eliminated).OnClientEvent:Connect(function(userId, reason)
		if userId == LocalPlayer.UserId and type(reason) == "string" then
			ui.reason.Text = reason
		end
	end)
	LocalPlayer:GetAttributeChangedSignal("Eliminated"):Connect(evaluate)
	hadCharacter = LocalPlayer.Character ~= nil
	LocalPlayer.CharacterAdded:Connect(function(character)
		hadCharacter = true
		-- Espera o Humanoid existir antes de decidir o modo.
		character:WaitForChild("Humanoid", 5)
		evaluate()
	end)

	local reason = LocalPlayer:GetAttribute("LastDamageSource")
	if type(reason) == "string" then
		ui.reason.Text = reason
	end

	evaluate()
	task.spawn(function()
		while ui.gui and ui.gui.Parent do
			task.wait(CHECK_INTERVAL)
			evaluate()
		end
	end)
end

return Spectate
