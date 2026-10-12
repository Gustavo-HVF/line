--!nonstrict
-- Interface do hub multiplayer (painel lateral direito):
--   * lista das salas que o jogador pode ver (nome, dono, jogadores/máximo, privacidade, botão Entrar);
--   * "Criar servidor": janela com nome, privacidade (Pública/Só amigos) e máximo de jogadores;
--   * painel da minha sala: membros, "Iniciar partida" (só o dono), "Convidar amigos" e "Sair da sala";
--   * "Voltar ao menu" (Hub_Leave + onBack).
-- O painel pode ser escondido para andar pelo hub. Atualiza com Party_Update e Party_GetList (ao abrir).
-- Os avisos de teleporte (Menu_TeleportStatus) são tratados pelo TeleportOverlay, igual ao menu.
--
--   HubUI.Open(onBack: () -> ())
--   HubUI.Close()
--   HubUI.IsOpen(): boolean

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local UIKit = require(ReplicatedStorage.Shared.UI.UIKit)

local LobbyUIUtil = require(script.Parent.LobbyUIUtil)

local HubUI = {}

local player = Players.LocalPlayer
local Theme = UIKit.Theme

local PANEL_WIDTH = 380
local HEADER_HEIGHT = 44
local FOOTER_HEIGHT = 46
local ACTION_COOLDOWN = 0.6 -- o servidor aceita 1 pedido a cada 0,5 s por remote
local START_BUTTON_LOCK = 3

local isOpen = false
local collapsed = false
local onBackCallback: (() -> ())? = nil
local latestPayload = nil
local updateCounter = 0
local actionCooldownUntil = 0
local remotesConnected = false

local ui = nil -- elementos da interface (criados no primeiro Open)

-- Utilidades ------------------------------------------------------------------------------------------

local function safeText(value: any, fallback: string): string
	if type(value) == "string" and value ~= "" then
		return value
	end
	return fallback
end

local function tryAction(action: () -> ())
	local now = os.clock()
	if now < actionCooldownUntil then
		return
	end
	actionCooldownUntil = now + ACTION_COOLDOWN
	action()
end

local function clearDynamic(container: Instance)
	for _, child in container:GetChildren() do
		if child:GetAttribute("Dynamic") then
			child:Destroy()
		end
	end
end

local function privacyChip(privacy: string, props: { [string]: any }): Frame
	local isPublic = privacy ~= "friends"
	local chip = UIKit.Create("Frame", {
		Name = "Privacidade",
		BackgroundColor3 = isPublic and Theme.Success or Theme.Info,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(104, 24),
	}) :: Frame
	for key, value in props do
		if key ~= "Parent" then
			chip[key] = value
		end
	end
	UIKit.Corner(chip, UDim.new(1, 0))
	local icon = UIKit.Frame({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 7, 0.5, 0),
		Size = UDim2.fromOffset(15, 15),
		Parent = chip,
	})
	if isPublic then
		LobbyUIUtil.GlobeIcon(icon, 15, Theme.Text)
	else
		LobbyUIUtil.PeopleIcon(icon, 15, Theme.Text)
	end
	UIKit.Label({
		Text = isPublic and "Pública" or "Só amigos",
		Font = Theme.BoldFont,
		TextSize = 14,
		TextWrapped = false,
		Position = UDim2.fromOffset(26, 0),
		Size = UDim2.new(1, -30, 1, 0),
		Parent = chip,
	})
	chip.Parent = props.Parent
	return chip
end

local function countMembers(party): number
	return type(party.members) == "table" and #party.members or 0
end

-- Ações ---------------------------------------------------------------------------------------------------

local function joinParty(partyId: string)
	tryAction(function()
		Net.event(Net.Names.Party_Join):FireServer(partyId)
	end)
end

local function leaveParty()
	tryAction(function()
		Net.event(Net.Names.Party_Leave):FireServer()
	end)
end

local function startMatch()
	if not ui then
		return
	end
	tryAction(function()
		local button = ui.startButton
		UIKit.SetButtonEnabled(button, false)
		button.Text = "Iniciando…"
		Net.event(Net.Names.Party_Start):FireServer()
		task.delay(START_BUTTON_LOCK, function()
			if button.Parent then
				button.Text = "Iniciar partida"
				UIKit.SetButtonEnabled(button, true)
			end
		end)
	end)
end

local function inviteFriends()
	task.spawn(function()
		local okCheck, canInvite = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if not okCheck or not canInvite then
			UIKit.Toast("Não é possível enviar convites agora.", "warning")
			return
		end
		local ok, err = pcall(function()
			SocialService:PromptGameInvite(player)
		end)
		if not ok then
			warn("[HubUI] PromptGameInvite falhou: " .. tostring(err))
			UIKit.Toast("Não foi possível abrir os convites.", "warning")
		end
	end)
end

-- Janela "Criar servidor" -------------------------------------------------------------------------------

local function closeModal()
	if ui and ui.modal then
		ui.modal:Destroy()
		ui.modal = nil
	end
end

local function openCreateModal()
	if not ui or ui.modal then
		return
	end
	local blocker = LobbyUIUtil.Blocker(ui.gui, 0.45)
	blocker.Name = "CriarServidor"
	blocker.ZIndex = 20
	ui.modal = blocker

	local panel = UIKit.Panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = 20,
		Parent = blocker,
	})
	LobbyUIUtil.AutoScale(panel, 1100, 600, 0.6, 1.25)
	UIKit.ListLayout(panel, 10)

	UIKit.Title("Criar servidor", { TextSize = 32, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1, Parent = panel })
	UIKit.Label({ Text = "Nome da sala", TextSize = 17, LayoutOrder = 2, Parent = panel })
	local nameBox = UIKit.TextBox({
		PlaceholderText = ("Sala de %s"):format(player.DisplayName),
		MaxLength = GameConfig.PARTY_NAME_MAX,
		LayoutOrder = 3,
		Parent = panel,
	})
	local hint = UIKit.Label({
		TextSize = 15,
		TextColor3 = Theme.TextMuted,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 5,
		Parent = panel,
	})
	local function updateHint(privacy: string)
		hint.Text = privacy == "friends" and "Só os amigos do dono da sala conseguem ver e entrar."
			or "Qualquer jogador deste servidor pode ver e entrar."
	end
	local privacy = UIKit.Choice({
		Text = "Privacidade",
		Options = {
			{ Value = "public", Label = "Pública" },
			{ Value = "friends", Label = "Só amigos" },
		},
		Value = "public",
		LayoutOrder = 4,
		OnChanged = updateHint,
		Parent = panel,
	})
	updateHint("public")
	local maxPlayers = UIKit.Slider({
		Text = "Máx. de jogadores",
		Min = 1,
		Max = GameConfig.MAX_PARTY_SIZE,
		Step = 1,
		Value = GameConfig.MAX_PARTY_SIZE,
		Format = function(value)
			return tostring(math.floor(value + 0.5))
		end,
		LayoutOrder = 6,
		Parent = panel,
	})

	local buttons = UIKit.Frame({ Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 7, Parent = panel })
	UIKit.ListLayout(buttons, 12, true)
	UIKit.Button({
		Text = "Cancelar",
		Style = "ghost",
		Size = UDim2.new(0.5, -6, 1, 0),
		LayoutOrder = 1,
		OnClick = closeModal,
		Parent = buttons,
	})
	UIKit.Button({
		Text = "Criar",
		Style = "primary",
		Size = UDim2.new(0.5, -6, 1, 0),
		LayoutOrder = 2,
		OnClick = function()
			tryAction(function()
				Net.event(Net.Names.Party_Create):FireServer({
					name = nameBox.Text,
					privacy = privacy.Get(),
					maxPlayers = math.clamp(math.floor(maxPlayers.Get() + 0.5), 1, GameConfig.MAX_PARTY_SIZE),
				})
				closeModal()
			end)
		end,
		Parent = buttons,
	})
end

-- Renderização --------------------------------------------------------------------------------------------

local function partyRow(party, order: number, myPartyId: string?)
	local row = UIKit.Create("Frame", {
		Name = "Sala",
		BackgroundColor3 = Theme.PanelLight,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -8, 0, 80),
		LayoutOrder = order,
		Parent = ui.list,
	}) :: Frame
	row:SetAttribute("Dynamic", true)
	UIKit.Corner(row, UDim.new(0, 8))
	UIKit.Padding(row, 10)

	local count = countMembers(party)
	local maxPlayers = type(party.maxPlayers) == "number" and party.maxPlayers or GameConfig.MAX_PARTY_SIZE
	UIKit.Label({
		Text = safeText(party.name, "Sala"),
		Font = Theme.BoldFont,
		TextSize = 19,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -112, 0, 22),
		Parent = row,
	})
	UIKit.Label({
		Text = ("Dono: %s"):format(safeText(party.hostName, "?")),
		TextSize = 15,
		TextColor3 = Theme.TextMuted,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, -112, 0, 18),
		Parent = row,
	})
	UIKit.Label({
		Text = ("%d/%d jogadores"):format(count, maxPlayers),
		TextSize = 15,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, -112, 0, 18),
		Parent = row,
	})
	privacyChip(party.privacy, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Parent = row,
	})

	local isMine = party.id == myPartyId
	local isFull = count >= maxPlayers
	local button = UIKit.Button({
		Text = isMine and "Sua sala" or (isFull and "Cheia" or "Entrar"),
		Style = "primary",
		TextSize = 17,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.fromOffset(104, 30),
		OnClick = function()
			if type(party.id) == "string" then
				joinParty(party.id)
			end
		end,
		Parent = row,
	})
	if isMine or isFull then
		UIKit.SetButtonEnabled(button, false)
	end
end

local function memberRow(member, order: number, isHost: boolean)
	local row = UIKit.Create("Frame", {
		Name = "Membro",
		BackgroundColor3 = Theme.PanelLight,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 46),
		LayoutOrder = order,
		Parent = ui.members,
	}) :: Frame
	row:SetAttribute("Dynamic", true)
	UIKit.Corner(row, UDim.new(0, 8))

	local userId = type(member.userId) == "number" and member.userId or 0
	local avatar = UIKit.Create("ImageLabel", {
		BackgroundColor3 = Theme.WoodDark,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 7, 0.5, 0),
		Size = UDim2.fromOffset(34, 34),
		Image = userId > 0 and ("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48"):format(userId) or "",
		Parent = row,
	})
	UIKit.Corner(avatar, UDim.new(1, 0))

	local name = safeText(member.name, "Jogador")
	if userId == player.UserId then
		name ..= " (você)"
	end
	UIKit.Label({
		Text = name,
		Font = Theme.BoldFont,
		TextSize = 17,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(50, 0),
		Size = UDim2.new(1, isHost and -120 or -58, 1, 0),
		Parent = row,
	})
	if isHost then
		local badge = UIKit.Create("Frame", {
			BackgroundColor3 = Theme.Gold,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(58, 22),
			Parent = row,
		})
		UIKit.Corner(badge, UDim.new(1, 0))
		UIKit.Label({
			Text = "Dono",
			Font = Theme.BoldFont,
			TextSize = 14,
			TextColor3 = Theme.WoodDark,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			Parent = badge,
		})
	end
end

local function renderList(parties)
	ui.title.Text = "Salas"
	ui.listView.Visible = true
	ui.partyView.Visible = false
	clearDynamic(ui.list)
	for index, party in parties do
		partyRow(party, index, nil)
	end
	ui.listCount.Text = ("Salas abertas (%d)"):format(#parties)
	ui.emptyLabel.Visible = #parties == 0
end

local function renderParty(party)
	ui.title.Text = "Sua sala"
	ui.listView.Visible = false
	ui.partyView.Visible = true

	local count = countMembers(party)
	local maxPlayers = type(party.maxPlayers) == "number" and party.maxPlayers or GameConfig.MAX_PARTY_SIZE
	ui.partyName.Text = safeText(party.name, "Sala")
	ui.partyCount.Text = ("%d/%d jogadores"):format(count, maxPlayers)
	if ui.partyChip then
		ui.partyChip:Destroy()
	end
	ui.partyChip = privacyChip(party.privacy, {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(0, 32),
		Parent = ui.partyCard,
	})

	clearDynamic(ui.members)
	local isHost = party.hostUserId == player.UserId
	if type(party.members) == "table" then
		for index, member in party.members do
			if type(member) == "table" then
				memberRow(member, index, member.userId == party.hostUserId)
			end
		end
	end

	ui.startButton.Visible = isHost
	ui.waitingLabel.Visible = not isHost
	ui.partyStatus.Text = isHost and "Você é o dono: inicie quando todos estiverem prontos."
		or ("Aguardando %s iniciar a partida…"):format(safeText(party.hostName, "o dono"))
end

local function render()
	if not ui or not isOpen then
		return
	end
	local payload = type(latestPayload) == "table" and latestPayload or {}
	local parties = {}
	if type(payload.parties) == "table" then
		for _, party in payload.parties do
			if type(party) == "table" and type(party.id) == "string" then
				table.insert(parties, party)
			end
		end
	end
	local myPartyId = type(payload.myPartyId) == "string" and payload.myPartyId or nil
	local myParty = nil
	if myPartyId then
		for _, party in parties do
			if party.id == myPartyId then
				myParty = party
				break
			end
		end
	end
	if myParty then
		closeModal()
		renderParty(myParty)
	else
		renderList(parties)
	end
end

-- Construção ------------------------------------------------------------------------------------------------

local function setCollapsed(value: boolean, instant: boolean?)
	if not ui then
		return
	end
	collapsed = value
	local goal = value and UDim2.new(1, PANEL_WIDTH * 1.4, 0, ui.top) or UDim2.new(1, -16, 0, ui.top)
	if instant then
		ui.panel.Position = goal
	else
		TweenService:Create(ui.panel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = goal,
		}):Play()
	end
	ui.showButton.Visible = value
end

local function build()
	local gui = UIKit.ScreenGui("HubUI", 10)
	LobbyUIUtil.UseSafeInsets(gui)

	local panel = UIKit.Panel({
		Name = "PainelSalas",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 64),
		Size = UDim2.fromOffset(PANEL_WIDTH, 560),
		BackgroundTransparency = 0.08,
		Parent = gui,
	})

	ui = { gui = gui, panel = panel, top = 64 }

	-- botão para mostrar o painel quando escondido
	local showButton = UIKit.Button({
		Name = "MostrarSalas",
		Text = "Salas",
		Style = "primary",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 64),
		Size = UDim2.fromOffset(120, 44),
		Visible = false,
		OnClick = function()
			setCollapsed(false)
		end,
		Parent = gui,
	})
	ui.showButton = showButton

	local function layout(scale: number)
		local top = LobbyUIUtil.TopInset() + 8
		local height = gui.AbsoluteSize.Y > 0 and gui.AbsoluteSize.Y or 720
		ui.top = top
		panel.Size = UDim2.fromOffset(PANEL_WIDTH, math.max(300, (height - top - 16) / scale))
		showButton.Position = UDim2.new(1, -16, 0, top)
		setCollapsed(collapsed, true)
	end
	local panelScale = LobbyUIUtil.AutoScale(panel, 1280, 720, 0.72, 1.2, function(scale)
		layout(scale)
	end)
	LobbyUIUtil.AutoScale(showButton, 1280, 720, 0.72, 1.2)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		layout(panelScale.Scale)
	end)

	-- cabeçalho
	ui.title = UIKit.Title("Salas", {
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -110, 0, 36),
		Parent = panel,
	})
	UIKit.Button({
		Text = "Esconder",
		Style = "ghost",
		TextSize = 16,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 2),
		Size = UDim2.fromOffset(100, 32),
		OnClick = function()
			setCollapsed(true)
		end,
		Parent = panel,
	})

	-- rodapé
	UIKit.Button({
		Text = "Voltar ao menu",
		Style = "secondary",
		TextSize = 19,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 42),
		OnClick = function()
			HubUI.GoBack()
		end,
		Parent = panel,
	})

	local body = UIKit.Frame({
		Name = "Corpo",
		Position = UDim2.fromOffset(0, HEADER_HEIGHT),
		Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + FOOTER_HEIGHT + 6)),
		Parent = panel,
	})

	-- lista de salas
	local listView = UIKit.Frame({ Name = "Lista", Parent = body })
	ui.listView = listView
	UIKit.Button({
		Text = "Criar servidor",
		Style = "primary",
		Size = UDim2.new(1, 0, 0, 46),
		OnClick = openCreateModal,
		Parent = listView,
	})
	ui.listCount = UIKit.Label({
		Text = "Salas abertas (0)",
		Font = Theme.BoldFont,
		TextSize = 16,
		TextColor3 = Theme.TextMuted,
		Position = UDim2.fromOffset(2, 56),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = listView,
	})
	ui.list = UIKit.List({
		Name = "Salas",
		Position = UDim2.fromOffset(0, 84),
		Size = UDim2.new(1, 0, 1, -84),
		Spacing = 8,
		Parent = listView,
	})
	ui.emptyLabel = UIKit.Label({
		Text = "Nenhuma sala aberta por enquanto.\nCrie a sua e chame os amigos!",
		TextSize = 17,
		TextColor3 = Theme.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 110),
		Size = UDim2.new(1, 0, 0, 60),
		Visible = false,
		Parent = listView,
	})

	-- minha sala (tudo numa lista rolável: cabe até em celular pequeno)
	local partyView = UIKit.List({ Name = "MinhaSala", Visible = false, Spacing = 8, Parent = body })
	ui.partyView = partyView
	local card = UIKit.Create("Frame", {
		Name = "Cartao",
		BackgroundColor3 = Theme.WoodDark,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -8, 0, 100),
		LayoutOrder = 1,
		Parent = partyView,
	}) :: Frame
	UIKit.Corner(card, UDim.new(0, 8))
	UIKit.Padding(card, 10)
	ui.partyCard = card
	ui.partyName = UIKit.Label({
		Font = Theme.BoldFont,
		TextSize = 21,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, 26),
		Parent = card,
	})
	ui.partyCount = UIKit.Label({
		TextSize = 16,
		TextWrapped = false,
		Position = UDim2.fromOffset(114, 32),
		Size = UDim2.new(1, -114, 0, 24),
		Parent = card,
	})
	ui.partyStatus = UIKit.Label({
		TextSize = 14,
		TextColor3 = Theme.TextMuted,
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	UIKit.Label({
		Text = "Jogadores",
		Font = Theme.BoldFont,
		TextSize = 16,
		TextColor3 = Theme.TextMuted,
		Size = UDim2.new(1, -10, 0, 22),
		LayoutOrder = 2,
		Parent = partyView,
	})
	ui.members = UIKit.Frame({
		Name = "Membros",
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Parent = partyView,
	})
	UIKit.ListLayout(ui.members, 6)
	local actions = UIKit.Frame({
		Name = "Acoes",
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 4,
		Parent = partyView,
	})
	UIKit.ListLayout(actions, 8)
	UIKit.Frame({ Name = "Espaco", Size = UDim2.new(1, 0, 0, 2), LayoutOrder = 0, Parent = actions })
	ui.startButton = UIKit.Button({
		Text = "Iniciar partida",
		Style = "primary",
		Size = UDim2.new(1, 0, 0, 42),
		LayoutOrder = 1,
		OnClick = startMatch,
		Parent = actions,
	})
	ui.waitingLabel = UIKit.Label({
		Text = "Só o dono da sala pode iniciar a partida.",
		TextSize = 15,
		TextColor3 = Theme.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 42),
		LayoutOrder = 1,
		Visible = false,
		Parent = actions,
	})
	UIKit.Button({
		Text = "Convidar amigos",
		Style = "secondary",
		TextSize = 19,
		Size = UDim2.new(1, 0, 0, 42),
		LayoutOrder = 2,
		OnClick = inviteFriends,
		Parent = actions,
	})
	UIKit.Button({
		Text = "Sair da sala",
		Style = "danger",
		TextSize = 19,
		Size = UDim2.new(1, 0, 0, 42),
		LayoutOrder = 3,
		OnClick = leaveParty,
		Parent = actions,
	})

	layout(panelScale.Scale)
end

-- Rede -------------------------------------------------------------------------------------------------------

local function connectRemotes()
	if remotesConnected then
		return
	end
	remotesConnected = true
	task.spawn(function()
		Net.event(Net.Names.Party_Update).OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then
				return
			end
			updateCounter += 1
			latestPayload = payload
			render()
		end)
	end)
end

local function requestList()
	local counterAtRequest = updateCounter
	task.spawn(function()
		local ok, payload = pcall(function()
			return Net.func(Net.Names.Party_GetList):InvokeServer()
		end)
		if not ok then
			warn("[HubUI] Party_GetList falhou: " .. tostring(payload))
			return
		end
		-- uma atualização mais nova pode ter chegado enquanto esperávamos
		if type(payload) == "table" and updateCounter == counterAtRequest then
			latestPayload = payload
			render()
		end
	end)
end

-- API ----------------------------------------------------------------------------------------------------------

function HubUI.Open(onBack: () -> ())
	onBackCallback = onBack
	connectRemotes()
	if not ui or not ui.gui.Parent then
		build()
	end
	ui.gui.Enabled = true
	isOpen = true
	setCollapsed(false, true)
	render()
	requestList()
end

function HubUI.Close()
	isOpen = false
	closeModal()
	if ui then
		ui.gui.Enabled = false
	end
end

function HubUI.IsOpen(): boolean
	return isOpen
end

-- Volta ao menu: avisa o servidor (sai da sala e do hub), fecha o painel e chama o onBack do menu.
function HubUI.GoBack()
	if not isOpen then
		return
	end
	Net.event(Net.Names.Hub_Leave):FireServer()
	local callback = onBackCallback
	onBackCallback = nil
	HubUI.Close()
	if callback then
		task.spawn(callback)
	end
end

return HubUI
