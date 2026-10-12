--!nonstrict
-- Overlay "Preparando a partida…" e o tratamento de Menu_TeleportStatus (o menu e o hub usam o mesmo).
--   "teleporting" → overlay com o anel girando e a mensagem do servidor;
--   "failed"      → fecha o overlay e mostra um aviso vermelho;
--   "studio"      → fecha o overlay e abre um painel explicando como testar a partida (botão OK).
--
--   TeleportOverlay.Init()
--   TeleportOverlay.Show(title?, message?, waitingReply?)  -- waitingReply: fecha sozinho se o servidor não responder
--   TeleportOverlay.Hide()
--   TeleportOverlay.IsVisible(): boolean
--   TeleportOverlay.StatusChanged: Signal (status, message)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local UIKit = require(ReplicatedStorage.Shared.UI.UIKit)

local LobbyUIUtil = require(script.Parent.LobbyUIUtil)

local TeleportOverlay = {}

TeleportOverlay.StatusChanged = Signal.new()

local Theme = UIKit.Theme
local DEFAULT_TITLE = "Preparando a partida…"
local REPLY_TIMEOUT = 12 -- pedido local sem nenhuma resposta do servidor
local CLOSE_BUTTON_DELAY = 40 -- teleporte demorando demais: deixa o jogador fechar o overlay

local initialized = false
local teleportGuiSet = false
local token = 0 -- invalida os temporizadores de um Show anterior

local ui = nil -- elementos da interface (criados sob demanda)

local function build()
	local gui = UIKit.ScreenGui("TeleportOverlay", 60)

	-- overlay de carregamento
	local overlay = LobbyUIUtil.Blocker(gui, 0.3)
	overlay.Visible = false
	local panel = UIKit.Panel({
		Name = "Painel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = 22,
		Parent = overlay,
	})
	LobbyUIUtil.AutoScale(panel, 1100, 640, 0.72, 1.3)
	UIKit.ListLayout(panel, 12)
	local spinner = LobbyUIUtil.Spinner(panel, 84, 1)
	local title = UIKit.Title(DEFAULT_TITLE, {
		TextSize = 32,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = panel,
	})
	local message = UIKit.Label({
		Text = "",
		TextSize = 18,
		TextColor3 = Theme.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Parent = panel,
	})
	local closeButton = UIKit.Button({
		Text = "Fechar",
		Style = "ghost",
		Size = UDim2.new(0.6, 0, 0, 42),
		TextSize = 19,
		Visible = false,
		LayoutOrder = 4,
		OnClick = function()
			TeleportOverlay.Hide()
		end,
		Parent = panel,
	})

	-- painel do Studio (teleporte desativado)
	local studio = LobbyUIUtil.Blocker(gui, 0.35)
	studio.Visible = false
	local studioPanel = UIKit.Panel({
		Name = "AvisoStudio",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = 22,
		Parent = studio,
	})
	LobbyUIUtil.AutoScale(studioPanel, 1100, 640, 0.6, 1.25)
	UIKit.ListLayout(studioPanel, 14)
	UIKit.Title("Teleporte indisponível", {
		TextSize = 32,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = studioPanel,
	})
	local studioMessage = UIKit.Label({
		Text = "",
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = studioPanel,
	})
	UIKit.Button({
		Text = "OK",
		Style = "primary",
		Size = UDim2.new(0.5, 0, 0, 46),
		LayoutOrder = 3,
		OnClick = function()
			studio.Visible = false
		end,
		Parent = studioPanel,
	})

	ui = {
		gui = gui,
		overlay = overlay,
		spinner = spinner,
		title = title,
		message = message,
		closeButton = closeButton,
		studio = studio,
		studioMessage = studioMessage,
	}
end

local function ensureBuilt()
	if not ui or not ui.gui.Parent then
		build()
	end
	return ui
end

-- Tela mostrada pelo Roblox durante o teleporte (no lugar da tela cinza padrão).
local function setTeleportGui()
	if teleportGuiSet then
		return
	end
	teleportGuiSet = true
	local screen = Instance.new("ScreenGui")
	screen.Name = "TeleporteTambores"
	screen.IgnoreGuiInset = true
	local background = UIKit.Create("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = screen,
	})
	UIKit.Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(28, 56, 32), Color3.fromRGB(6, 14, 8)),
		Parent = background,
	})
	local title = UIKit.Title(GameConfig.GAME_TITLE, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(0.9, 0, 0, 80),
		TextScaled = true,
		Parent = background,
	})
	UIKit.Create("UITextSizeConstraint", { MaxTextSize = 72, Parent = title })
	UIKit.Label({
		Text = "Entrando na selva…",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.45, 50),
		Size = UDim2.new(0.9, 0, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.TextMuted,
		TextSize = 22,
		Parent = background,
	})
	local ok, err = pcall(function()
		TeleportService:SetTeleportGui(screen)
	end)
	if not ok then
		warn("[TeleportOverlay] SetTeleportGui falhou: " .. tostring(err))
	end
end

function TeleportOverlay.Show(title: string?, message: string?, waitingReply: boolean?)
	local elements = ensureBuilt()
	token += 1
	local myToken = token
	elements.title.Text = title or DEFAULT_TITLE
	elements.message.Text = message or ""
	elements.closeButton.Visible = false
	elements.studio.Visible = false
	elements.overlay.Visible = true
	elements.spinner.SetActive(true)

	if waitingReply then
		task.delay(REPLY_TIMEOUT, function()
			if token == myToken and elements.overlay.Visible then
				TeleportOverlay.Hide()
				UIKit.Toast("O servidor não respondeu. Tente de novo.", "warning")
			end
		end)
	else
		task.delay(CLOSE_BUTTON_DELAY, function()
			if token == myToken and elements.overlay.Visible then
				elements.closeButton.Visible = true
			end
		end)
	end
end

function TeleportOverlay.Hide()
	token += 1
	if ui then
		ui.overlay.Visible = false
		ui.spinner.SetActive(false)
	end
end

function TeleportOverlay.IsVisible(): boolean
	return ui ~= nil and ui.overlay.Visible
end

local function showStudioNotice(message: string)
	local elements = ensureBuilt()
	TeleportOverlay.Hide()
	elements.studioMessage.Text = message
	elements.studio.Visible = true
end

local function onStatus(status: any, message: any)
	if type(status) ~= "string" then
		return
	end
	local text = type(message) == "string" and message or ""
	if status == "teleporting" then
		setTeleportGui()
		TeleportOverlay.Show(DEFAULT_TITLE, text, false)
	elseif status == "failed" then
		TeleportOverlay.Hide()
		UIKit.Toast(text ~= "" and text or "Não foi possível entrar na partida.", "danger", 6)
	elseif status == "studio" then
		showStudioNotice(text)
	else
		return
	end
	TeleportOverlay.StatusChanged:Fire(status, text)
end

-- Idempotente. Conecta Menu_TeleportStatus em segundo plano (o remote pode demorar a existir).
function TeleportOverlay.Init()
	if initialized then
		return
	end
	initialized = true
	task.spawn(function()
		Net.event(Net.Names.Menu_TeleportStatus).OnClientEvent:Connect(onStatus)
	end)
end

return TeleportOverlay
