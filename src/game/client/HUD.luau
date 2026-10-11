--!nonstrict
-- HUD da partida: casa atual, estado do dado, quem carrega o tabuleiro, vivos/total, eventos ativos,
-- mensagem da fase, aviso de borda da ilha, contagem grande e telas de vitória/derrota.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local UIKit = require(ReplicatedStorage.Shared.UI.UIKit)

local HUD = {}

local Theme = UIKit.Theme
local LocalPlayer = Players.LocalPlayer
local UPDATE_INTERVAL = 0.2
local EDGE_COLOR = Color3.fromRGB(255, 84, 64)

local initialized = false
local ui: { [string]: any } = {}
local scales: { UIScale } = {}
local gameState = nil
local boardStatus = nil
local events: { [string]: { info: any, receivedAt: number, label: TextLabel } } = {}
local eventOrder = 0
local lastCountdown: number? = nil
local edgeVisible = false
local edgeTween: Tween? = nil

-- Validação dos payloads ------------------------------------------------------------------

local function num(value: any, default: number): number
	if type(value) == "number" and value == value then
		return value
	end
	return default
end

local function str(value: any): string?
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

-- Escala ------------------------------------------------------------------------------------

local function addScale(object: GuiObject)
	local scale = Instance.new("UIScale")
	scale.Parent = object
	table.insert(scales, scale)
end

local function updateScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local value = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.62, 1.15)
	for _, scale in scales do
		scale.Scale = value
	end
end

-- Construção -------------------------------------------------------------------------------

local function build()
	local gui = UIKit.ScreenGui("GameHUD", 5)
	ui.gui = gui

	-- Painel de informações (meio da lateral esquerda: longe do chat e dos botões do Roblox)
	local info = UIKit.Panel({
		Name = "Info",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(280, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = 12,
		Parent = gui,
	})
	local infoLayout = UIKit.ListLayout(info, 6)
	infoLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	addScale(info)

	ui.space = UIKit.Label({
		Name = "Casa",
		Text = ("Casa 0 de %d"):format(GameConfig.BOARD_SPACES),
		Font = Theme.TitleFont,
		TextSize = 24,
		TextColor3 = Theme.Gold,
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = 1,
		Parent = info,
	})
	local track = UIKit.Create("Frame", {
		Name = "Trilha",
		BackgroundColor3 = Theme.WoodDark,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 8),
		LayoutOrder = 2,
		Parent = info,
	}) :: Frame
	UIKit.Corner(track, UDim.new(1, 0))
	ui.spaceFill = UIKit.Create("Frame", {
		BackgroundColor3 = Theme.Gold,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = track,
	})
	UIKit.Corner(ui.spaceFill, UDim.new(1, 0))
	ui.dice = UIKit.Label({ Name = "Dado", Text = "Dado: —", TextSize = 18, LayoutOrder = 3, Parent = info })
	ui.carrier = UIKit.Label({
		Name = "Carregador",
		Text = "Tabuleiro: na mesa",
		TextSize = 18,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 4,
		Parent = info,
	})
	ui.alive = UIKit.Label({ Name = "Vivos", Text = "Vivos: —", TextSize = 18, LayoutOrder = 5, Parent = info })

	-- Eventos ativos (lado direito)
	local eventsPanel = UIKit.Panel({
		Name = "Eventos",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0.3, 0),
		Size = UDim2.fromOffset(290, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = 10,
		Visible = false,
		Parent = gui,
	})
	local eventsLayout = UIKit.ListLayout(eventsPanel, 6)
	eventsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	addScale(eventsPanel)
	UIKit.Label({
		Text = "Eventos ativos",
		Font = Theme.TitleFont,
		TextSize = 22,
		TextColor3 = Theme.Gold,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 0,
		Parent = eventsPanel,
	})
	ui.eventsPanel = eventsPanel

	-- Mensagem da fase (topo, centro)
	local banner = UIKit.Panel({
		Name = "Mensagem",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(560, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = 10,
		Visible = false,
		Parent = gui,
	})
	addScale(banner)
	ui.bannerText = UIKit.Label({
		Text = "",
		Font = Theme.BoldFont,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		Parent = banner,
	})
	ui.banner = banner

	-- Contagem grande (abaixo do centro, para não cobrir o enigma)
	local countdownHolder = UIKit.Frame({
		Name = "Contagem",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.76),
		Size = UDim2.fromOffset(500, 170),
		Visible = false,
		Parent = gui,
	})
	addScale(countdownHolder)
	ui.countdownNumber = UIKit.Label({
		Text = "",
		Font = Theme.TitleFont,
		TextSize = 110,
		TextColor3 = Theme.Gold,
		TextStrokeTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 128),
		Parent = countdownHolder,
	})
	ui.countdownPop = Instance.new("UIScale")
	ui.countdownPop.Parent = ui.countdownNumber
	ui.countdownText = UIKit.Label({
		Text = "As portas vão se abrir!",
		Font = Theme.BoldFont,
		TextSize = 26,
		TextStrokeTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 132),
		Size = UDim2.new(1, 0, 0, 34),
		Parent = countdownHolder,
	})
	ui.countdown = countdownHolder

	-- Aviso da borda da ilha
	local edge = UIKit.Label({
		Name = "AvisoBorda",
		Text = "Volte! A borda da ilha elimina!",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.66),
		Size = UDim2.fromOffset(640, 48),
		Font = Theme.BoldFont,
		TextSize = 34,
		TextColor3 = EDGE_COLOR,
		TextStrokeTransparency = 0.1,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = gui,
	})
	addScale(edge)
	ui.edge = edge

	-- Tela de fim (vitória / derrota)
	local endScreen = UIKit.Create("Frame", {
		Name = "Fim",
		BackgroundColor3 = Theme.Overlay,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	}) :: Frame
	local endContent = UIKit.Frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(760, 300),
		ZIndex = 11,
		Parent = endScreen,
	})
	addScale(endContent)
	ui.endTitle = UIKit.Title("", {
		TextSize = 96,
		Size = UDim2.new(1, 0, 0, 110),
		ZIndex = 11,
		Parent = endContent,
	})
	ui.endSubtitle = UIKit.Label({
		Text = GameConfig.GAME_TITLE,
		Font = Theme.TitleFont,
		TextSize = 30,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 116),
		Size = UDim2.new(1, 0, 0, 36),
		ZIndex = 11,
		Parent = endContent,
	})
	ui.endMessage = UIKit.Label({
		Text = "",
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 160),
		Size = UDim2.new(1, 0, 0, 60),
		ZIndex = 11,
		Parent = endContent,
	})
	ui.endTimer = UIKit.Label({
		Text = "",
		TextSize = 20,
		TextColor3 = Theme.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 226),
		Size = UDim2.new(1, 0, 0, 30),
		ZIndex = 11,
		Parent = endContent,
	})
	ui.endScreen = endScreen

	updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
end

-- Renderização ----------------------------------------------------------------------------

local function diceText(): (string, Color3)
	local status = boardStatus
	if not status then
		return "Dado: —", Theme.TextMuted
	end
	if status.rolling then
		return "Dado: rolando…", Theme.Gold
	end
	if status.locked then
		return "Dado: tabuleiro preso!", Theme.Danger
	end
	if status.cooldownEndsAt then
		local remaining = status.cooldownEndsAt - workspace:GetServerTimeNow()
		if remaining > 0 then
			return ("Dado: próxima jogada em %ds"):format(math.ceil(remaining)), Theme.TextMuted
		end
	end
	if status.canRoll then
		return "Dado: pronto para jogar!", Theme.Success
	end
	return "Dado: em espera", Theme.TextMuted
end

local function renderBoard()
	local status = boardStatus
	if not status then
		return
	end
	local text, color = diceText()
	ui.dice.Text = text
	ui.dice.TextColor3 = color
	if status.carrierUserId then
		if status.carrierUserId == LocalPlayer.UserId then
			ui.carrier.Text = "Tabuleiro: com você (T joga • G solta)"
			ui.carrier.TextColor3 = Theme.Gold
		else
			local player = Players:GetPlayerByUserId(status.carrierUserId)
			ui.carrier.Text = ("Tabuleiro: com %s"):format(player and player.DisplayName or "outro jogador")
			ui.carrier.TextColor3 = Theme.Text
		end
	else
		ui.carrier.Text = "Tabuleiro: no chão"
		ui.carrier.TextColor3 = Theme.Text
	end
	if gameState == nil then
		ui.space.Text = ("Casa %d de %d"):format(status.space, GameConfig.BOARD_SPACES)
	end
end

local function popCountdown()
	local pop = ui.countdownPop :: UIScale
	pop.Scale = 1.45
	TweenService:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function renderState()
	local state = gameState
	if not state then
		return
	end
	local total = math.max(state.totalSpaces, 1)
	ui.space.Text = ("Casa %d de %d"):format(state.space, total)
	ui.spaceFill.Size = UDim2.fromScale(math.clamp(state.space / total, 0, 1), 1)
	ui.alive.Text = ("Vivos: %d/%d"):format(state.alive, state.total)

	local phase = state.phase
	local isEnd = phase == "Victory" or phase == "Defeat"

	-- Mensagem da fase (não aparece durante o jogo, na contagem nem no fim)
	local showBanner = state.message ~= nil and phase ~= "Playing" and phase ~= "Countdown" and not isEnd
	ui.banner.Visible = showBanner
	if showBanner then
		ui.bannerText.Text = state.message
	end

	-- Contagem grande
	if phase == "Countdown" and state.countdown then
		ui.countdown.Visible = true
		ui.countdownNumber.Text = tostring(state.countdown)
		ui.countdownText.Text = state.message or "As portas vão se abrir!"
		if state.countdown ~= lastCountdown then
			lastCountdown = state.countdown
			popCountdown()
			SoundUtil.Play("Countdown", { Volume = 0.5 })
		end
	else
		ui.countdown.Visible = false
		lastCountdown = nil
	end

	-- Fim
	if isEnd then
		local victory = phase == "Victory"
		ui.endScreen.Visible = true
		ui.endTitle.Text = victory and "Vitória!" or "Derrota"
		ui.endTitle.TextColor3 = victory and Theme.Gold or Theme.Danger
		ui.endMessage.Text = victory and "O tabuleiro foi vencido!"
			or "Todos foram eliminados. A selva venceu desta vez…"
		if state.countdown then
			ui.endTimer.Text = ("Voltando ao lobby em %ds"):format(state.countdown)
		elseif state.message and state.message ~= ui.endMessage.Text then
			-- Ex.: "Voltando ao lobby…" ou o aviso de que no Studio não há teleporte.
			ui.endTimer.Text = state.message
		else
			ui.endTimer.Text = ""
		end
	else
		ui.endScreen.Visible = false
	end
end

local function refreshEvents()
	local now = os.clock()
	local count = 0
	for _, entry in events do
		count += 1
		local info = entry.info
		local remaining = math.max(math.ceil(info.duration - (now - entry.receivedAt)), 0)
		entry.label.Text = ("%s\n%s · %ds"):format(info.name, info.regionName or "perto do tabuleiro", remaining)
	end
	ui.eventsPanel.Visible = count > 0
end

local function setEdgeWarning(visible: boolean)
	if visible == edgeVisible then
		return
	end
	edgeVisible = visible
	ui.edge.Visible = visible
	if edgeTween then
		edgeTween:Cancel()
		edgeTween = nil
	end
	if visible then
		ui.edge.TextTransparency = 0
		local tween = TweenService:Create(
			ui.edge,
			TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ TextTransparency = 0.65 }
		)
		edgeTween = tween
		tween:Play()
	end
end

local function updateEdge()
	local show = false
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and not LocalPlayer:GetAttribute("Eliminated") then
		local center = GameConfig.ISLAND_CENTER
		local distance = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z).Magnitude
		show = distance > GameConfig.ISLAND_RADIUS - GameConfig.EDGE_WARNING_DISTANCE
	end
	setEdgeWarning(show)
end

-- Remotes -----------------------------------------------------------------------------------

local function onGameState(payload)
	if type(payload) ~= "table" or type(payload.phase) ~= "string" then
		return
	end
	gameState = {
		phase = payload.phase,
		countdown = type(payload.countdown) == "number" and payload.countdown or nil,
		space = num(payload.space, 0),
		totalSpaces = num(payload.totalSpaces, GameConfig.BOARD_SPACES),
		alive = num(payload.alive, 0),
		total = num(payload.total, 0),
		message = str(payload.message),
	}
	renderState()
end

local function onBoardStatus(payload)
	if type(payload) ~= "table" then
		return
	end
	boardStatus = {
		carrierUserId = type(payload.carrierUserId) == "number" and payload.carrierUserId or nil,
		canRoll = payload.canRoll == true,
		cooldownEndsAt = type(payload.cooldownEndsAt) == "number" and payload.cooldownEndsAt or nil,
		space = num(payload.space, 0),
		locked = payload.locked == true,
		rolling = payload.rolling == true,
	}
	renderBoard()
end

local function onEventStarted(info)
	if type(info) ~= "table" or type(info.id) ~= "string" then
		return
	end
	local clean = {
		id = info.id,
		name = str(info.name) or str(info.eventId) or "Evento",
		regionName = str(info.regionName),
		duration = num(info.duration, 60),
	}
	local entry = events[clean.id]
	if entry then
		entry.info = clean
		entry.receivedAt = os.clock()
	else
		eventOrder += 1
		local label = UIKit.Label({
			Name = clean.id,
			Text = "",
			TextSize = 17,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			LayoutOrder = eventOrder,
			Parent = ui.eventsPanel,
		})
		events[clean.id] = { info = clean, receivedAt = os.clock(), label = label }
	end
	refreshEvents()
end

local function onEventEnded(instanceId)
	if type(instanceId) ~= "string" then
		return
	end
	local entry = events[instanceId]
	if entry then
		entry.label:Destroy()
		events[instanceId] = nil
	end
	refreshEvents()
end

-- API -----------------------------------------------------------------------------------------

function HUD.Init()
	if initialized then
		return
	end
	initialized = true
	build()

	Net.event(Net.Names.Game_State).OnClientEvent:Connect(onGameState)
	Net.event(Net.Names.Board_Status).OnClientEvent:Connect(onBoardStatus)
	Net.event(Net.Names.Event_Started).OnClientEvent:Connect(onEventStarted)
	Net.event(Net.Names.Event_Ended).OnClientEvent:Connect(onEventEnded)

	task.spawn(function()
		while ui.gui and ui.gui.Parent do
			renderBoard()
			refreshEvents()
			updateEdge()
			task.wait(UPDATE_INTERVAL)
		end
	end)
end

return HUD
