--!nonstrict
-- Entrada do cliente do LOBBY: menu principal.
--   * configurações do jogador (SettingsClient) em segundo plano;
--   * câmera cinematográfica no sótão (MenuCamera), velas tremulando (LobbyAmbience) e música do menu;
--   * botões "Jogar Solo", "Multiplayer" (hub com salas) e "Configurações" (SettingsUI);
--   * avisos do servidor (Notify) e status de teleporte (TeleportOverlay).
-- No menu o personagem fica escondido num cubículo atrás da câmera, com os controles desligados.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
-- Place único: no servidor da partida este menu não existe (quem roda é o GameClient).
if require(Shared:WaitForChild("PlaceMode")).Get() ~= "lobby" then
	return
end

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local UIKit = require(ReplicatedStorage.Shared.UI.UIKit)

local HubUI = require(script.Parent.HubUI)
local LobbyAmbience = require(script.Parent.LobbyAmbience)
local LobbyControls = require(script.Parent.LobbyControls)
local LobbyUIUtil = require(script.Parent.LobbyUIUtil)
local MenuCamera = require(script.Parent.MenuCamera)
local TeleportOverlay = require(script.Parent.TeleportOverlay)

local player = Players.LocalPlayer
local Theme = UIKit.Theme

local VERSION_TEXT = "Versão 0.1 · protótipo"
local CREDIT_TEXT = "Aventura original feita com Luau + Rojo"
local MUSIC_VOLUME = 0.5
local TOAST_KINDS = { info = true, warning = true, danger = true, success = true }
local SCENE_WAIT = 10 -- segundos esperando o cenário do menu chegar do servidor

local state = "loading" -- "loading" | "menu" | "busy" | "hub" | "settings"
local music: Sound? = nil

-- Configurações (áudio e gráficos) -------------------------------------------------------------------
task.spawn(function()
	local settingsFolder = Shared:WaitForChild("Settings", 10)
	local moduleScript = settingsFolder and settingsFolder:WaitForChild("SettingsClient", 10)
	if moduleScript and moduleScript:IsA("ModuleScript") then
		local ok, SettingsClient = pcall(require, moduleScript)
		if ok and type(SettingsClient) == "table" and type(SettingsClient.Init) == "function" then
			local initOk, err = pcall(SettingsClient.Init)
			if not initOk then
				warn("[MainMenu] Erro ao iniciar as configurações: " .. tostring(err))
			end
		else
			warn("[MainMenu] SettingsClient não pôde ser carregado: " .. tostring(SettingsClient))
		end
	else
		warn("[MainMenu] SettingsClient não encontrado; usando as configurações padrão.")
	end
end)

local settingsUI = nil
local function getSettingsUI()
	if settingsUI then
		return settingsUI
	end
	local moduleScript = script.Parent:FindFirstChild("SettingsUI") or script.Parent:WaitForChild("SettingsUI", 3)
	if moduleScript and moduleScript:IsA("ModuleScript") then
		local ok, result = pcall(require, moduleScript)
		if ok and type(result) == "table" and type(result.Open) == "function" then
			settingsUI = result
		else
			warn("[MainMenu] SettingsUI não pôde ser carregado: " .. tostring(result))
		end
	end
	return settingsUI
end

-- Interface ---------------------------------------------------------------------------------------------

local gui = UIKit.ScreenGui("MainMenu", 10)
LobbyUIUtil.UseSafeInsets(gui)

-- escurece o lado esquerdo para o texto ficar legível sobre o cenário
local vignette = UIKit.Create("Frame", {
	Name = "Vinheta",
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.new(0.62, 0, 1, 0),
	Parent = gui,
}) :: Frame
UIKit.Create("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.55, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	}),
	Parent = vignette,
})

local menu = UIKit.Create("CanvasGroup", {
	Name = "Menu",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 56, 0.5, 0),
	Size = UDim2.fromOffset(440, 470),
	GroupTransparency = 1,
	Visible = false,
	Parent = gui,
}) :: CanvasGroup
LobbyUIUtil.AutoScale(menu, 1100, 640, 0.7, 1.35)
-- folga para as bordas dos botões não serem cortadas pelo CanvasGroup
UIKit.Create("UIPadding", {
	PaddingLeft = UDim.new(0, 4),
	PaddingRight = UDim.new(0, 4),
	PaddingTop = UDim.new(0, 4),
	PaddingBottom = UDim.new(0, 4),
	Parent = menu,
})
local menuLayout = UIKit.ListLayout(menu, 10)
menuLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
menuLayout.VerticalAlignment = Enum.VerticalAlignment.Center

-- ornamento dourado
local ornament = UIKit.Frame({ Name = "Ornamento", Size = UDim2.fromOffset(220, 14), LayoutOrder = 1, Parent = menu })
local ornamentLine = UIKit.Create("Frame", {
	BackgroundColor3 = Theme.Gold,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 22, 0.5, 0),
	Size = UDim2.new(1, -22, 0, 2),
	Parent = ornament,
})
UIKit.Create("UIGradient", {
	Transparency = NumberSequence.new(0, 1),
	Parent = ornamentLine,
})
UIKit.Create("Frame", {
	BackgroundColor3 = Theme.Gold,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0, 9, 0.5, 0),
	Size = UDim2.fromOffset(10, 10),
	Rotation = 45,
	Parent = ornament,
})

local title = UIKit.Title(GameConfig.GAME_TITLE, {
	Name = "Titulo",
	TextSize = 58,
	TextColor3 = Color3.new(1, 1, 1), -- a cor vem do gradiente dourado
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Bottom,
	TextWrapped = true,
	TextStrokeTransparency = 0.5,
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	LayoutOrder = 2,
	Parent = menu,
})
UIKit.Create("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(Color3.fromRGB(255, 226, 140), Color3.fromRGB(196, 140, 46)),
	Parent = title,
})
UIKit.Label({
	Name = "Subtitulo",
	Text = GameConfig.GAME_SUBTITLE,
	TextSize = 21,
	TextColor3 = Theme.Text,
	TextTransparency = 0.15,
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	LayoutOrder = 3,
	Parent = menu,
})
UIKit.Frame({ Name = "Espaco", Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 4, Parent = menu })

local buttons = UIKit.Frame({
	Name = "Botoes",
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	LayoutOrder = 5,
	Parent = menu,
})
UIKit.ListLayout(buttons, 12)

local function menuButton(
	order: number,
	style: string,
	text: string,
	caption: string,
	drawIcon: (Instance, number, Color3) -> any,
	onClick: () -> ()
): TextButton
	local button = UIKit.Button({
		Name = text,
		Text = "",
		Style = style,
		Size = UDim2.new(1, 0, 0, 68),
		LayoutOrder = order,
		OnClick = onClick,
		Parent = buttons,
	})
	local color = button.TextColor3
	local icon = UIKit.Frame({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 18, 0.5, 0),
		Size = UDim2.fromOffset(34, 34),
		Parent = button,
	})
	drawIcon(icon, 34, color)
	UIKit.Label({
		Text = text,
		Font = Theme.BoldFont,
		TextSize = 25,
		TextColor3 = color,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(68, 9),
		Size = UDim2.new(1, -84, 0, 28),
		Parent = button,
	})
	UIKit.Label({
		Text = caption,
		TextSize = 15,
		TextColor3 = color,
		TextTransparency = 0.25,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(68, 38),
		Size = UDim2.new(1, -84, 0, 20),
		Parent = button,
	})
	return button
end

local footer = UIKit.Frame({
	Name = "Rodape",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 24, 1, -14),
	Size = UDim2.fromOffset(420, 40),
	Visible = false,
	Parent = gui,
})
LobbyUIUtil.AutoScale(footer, 1100, 640, 0.7, 1.2)
UIKit.Label({
	Text = VERSION_TEXT,
	Font = Theme.BoldFont,
	TextSize = 14,
	TextColor3 = Theme.TextMuted,
	TextTransparency = 0.2,
	TextWrapped = false,
	Size = UDim2.new(1, 0, 0, 18),
	Parent = footer,
})
UIKit.Label({
	Text = CREDIT_TEXT,
	TextSize = 13,
	TextColor3 = Theme.TextMuted,
	TextTransparency = 0.35,
	TextWrapped = false,
	Position = UDim2.fromOffset(0, 20),
	Size = UDim2.new(1, 0, 0, 18),
	Parent = footer,
})

-- cortina preta para as transições (começa fechada)
local curtainGui = UIKit.ScreenGui("LobbyCurtain", 55)
local curtain = UIKit.Create("Frame", {
	Name = "Cortina",
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	Parent = curtainGui,
}) :: Frame

local function setCurtain(closed: boolean, duration: number)
	if closed then
		curtain.Visible = true
	end
	local tween =
		TweenService:Create(curtain, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			BackgroundTransparency = closed and 0 or 1,
		})
	tween:Play()
	tween.Completed:Wait()
	if not closed and curtain.BackgroundTransparency >= 0.99 then
		curtain.Visible = false
	end
end

local function setMenuVisible(visible: boolean)
	UIKit.Fade(menu, visible, 0.35)
	footer.Visible = visible
	TweenService:Create(vignette, TweenInfo.new(0.35), { BackgroundTransparency = visible and 0 or 1 }):Play()
	if visible then
		menu.Position = UDim2.new(0, 30, 0.5, 0)
		TweenService:Create(menu, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, 56, 0.5, 0),
		}):Play()
	end
end

-- Música ----------------------------------------------------------------------------------------------------

local function startMusic()
	if music and music.Parent then
		TweenService:Create(music, TweenInfo.new(1.5), { Volume = MUSIC_VOLUME }):Play()
		return
	end
	music = SoundUtil.Play("MenuMusic", { Group = "Music", Looped = true, Volume = 0 })
	if music then
		TweenService:Create(music, TweenInfo.new(3), { Volume = MUSIC_VOLUME }):Play()
	end
end

local function fadeMusic(volume: number)
	if music and music.Parent then
		TweenService:Create(music, TweenInfo.new(1.5), { Volume = volume }):Play()
	end
end

-- Transições ------------------------------------------------------------------------------------------------

local function characterNear(position: Vector3, radius: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart") and (root.Position - position).Magnitude <= radius
end

local function waitForCharacterNear(position: Vector3, radius: number, timeout: number)
	local deadline = os.clock() + timeout
	while os.clock() < deadline and not characterNear(position, radius) do
		task.wait(0.05)
	end
end

local backToMenu

local function enterHub()
	if state ~= "menu" or TeleportOverlay.IsVisible() then
		return
	end
	state = "busy"
	setMenuVisible(false)
	setCurtain(true, 0.35)
	Net.event(Net.Names.Hub_Enter):FireServer()
	waitForCharacterNear(GameConfig.HUB_ORIGIN, 90, 3)
	MenuCamera.Stop()
	LobbyControls.SetEnabled(true)
	state = "hub"
	HubUI.Open(function()
		backToMenu()
	end)
	setCurtain(false, 0.5)
end

backToMenu = function()
	if state ~= "hub" then
		return
	end
	state = "busy"
	setCurtain(true, 0.35)
	LobbyControls.SetEnabled(false)
	MenuCamera.Start(true)
	waitForCharacterNear(GameConfig.MENU_AREA_ORIGIN + Vector3.new(0, 0, 30), 40, 1.5)
	setMenuVisible(true)
	state = "menu"
	setCurtain(false, 0.6)
end

local function playSolo()
	if state ~= "menu" or TeleportOverlay.IsVisible() then
		return
	end
	TeleportOverlay.Show("Preparando a partida…", "Abrindo o tabuleiro…", true)
	Net.event(Net.Names.Menu_RequestSolo):FireServer()
end

local function openSettings()
	if state ~= "menu" or TeleportOverlay.IsVisible() then
		return
	end
	state = "busy"
	local SettingsUI = getSettingsUI()
	if not SettingsUI then
		state = "menu"
		UIKit.Toast("As configurações ainda não estão disponíveis.", "warning")
		return
	end
	state = "settings"
	setMenuVisible(false)
	MenuCamera.Pause()

	local closed = false
	local function onClose()
		if closed then
			return
		end
		closed = true
		MenuCamera.Start(false)
		setMenuVisible(true)
		state = "menu"
	end
	local ok, err = pcall(SettingsUI.Open, onClose)
	if not ok then
		warn("[MainMenu] Erro ao abrir as configurações: " .. tostring(err))
		UIKit.Toast("Não foi possível abrir as configurações.", "danger")
		onClose()
	end
end

menuButton(1, "primary", "Jogar Solo", "Enfrente a selva sozinho", LobbyUIUtil.DiceIcon, playSolo)
menuButton(2, "secondary", "Multiplayer", "Crie uma sala ou entre na de alguém", LobbyUIUtil.PeopleIcon, enterHub)
menuButton(3, "ghost", "Configurações", "Áudio e gráficos", LobbyUIUtil.GearIcon, openSettings)

-- Rede ---------------------------------------------------------------------------------------------------------

TeleportOverlay.Init()
TeleportOverlay.StatusChanged:Connect(function(status)
	if status == "teleporting" then
		fadeMusic(0)
	else
		fadeMusic(MUSIC_VOLUME)
	end
end)

task.spawn(function()
	Net.event(Net.Names.Notify).OnClientEvent:Connect(function(text, kind)
		if type(text) ~= "string" or text == "" then
			return
		end
		UIKit.Toast(text, TOAST_KINDS[kind] and kind or "info")
	end)
end)

-- Início -------------------------------------------------------------------------------------------------------

LobbyControls.SetEnabled(false)
MenuCamera.Start(false)
LobbyAmbience.Start()

task.spawn(function()
	MenuCamera.WaitForMarker(SCENE_WAIT)
	local world = workspace:WaitForChild("LobbyWorld", SCENE_WAIT)
	if world then
		world:WaitForChild("MenuScene", SCENE_WAIT)
	end
	task.wait(0.3) -- deixa o cenário recém-chegado renderizar antes de abrir a cortina
	MenuCamera.PlayIntro()
	state = "menu"
	setMenuVisible(true)
	startMusic()
	setCurtain(false, 1.4)
end)
