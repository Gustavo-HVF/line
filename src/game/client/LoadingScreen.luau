--!nonstrict
-- Tela de carregamento da partida.
-- Espera o mapa ficar pronto (workspace MapReady) e, se o jogador deixou "Carregar jogo antecipadamente"
-- ligado nas configurações:
--   1. ContentProvider:PreloadAsync nas instâncias com assets do mapa, dos sons e do céu;
--   2. uma varredura de câmera por todas as regiões de workspace.Map.Regions (3–4 ângulos, 2 frames cada),
--      com o culling desligado, para o aparelho renderizar e compilar materiais e shaders AGORA — assim o
--      jogo não engasga quando o jogador entra num cômodo novo.
-- Sem pré-carregamento, só espera o mapa.

local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local SettingsSchema = require(ReplicatedStorage.Shared.Settings.SettingsSchema)
local UIKit = require(ReplicatedStorage.Shared.UI.UIKit)

local LoadingScreen = {}

local Theme = UIKit.Theme
local GUI_NAME = "LoadingScreen"
local PRELOAD_BATCH = 40
local FRAMES_PER_SHOT = 2
local SETTINGS_TIMEOUT = 9
local TIP_INTERVAL = 6

local TIPS = {
	"Carregue o tabuleiro nas costas para levá-lo de um cenário para outro.",
	"Cada nova jogada SOMA um evento aos que já estão acontecendo.",
	"O evento acontece onde o tabuleiro foi jogado. Escolha bem o lugar!",
	"Passar da borda da ilha elimina na hora. Fique longe da água!",
	"Procure armas na mansão, no labirinto e na estufa.",
	"O enigma do tabuleiro dá uma pista do que vai acontecer. Leia com atenção!",
	"Pedaços do cenário somem depois de um tempo para não pesar no aparelho.",
	"Todos andam com a MESMA peça: a vitória é do grupo inteiro.",
}

-- Classes que carregam assets (texturas, malhas, sons, partículas...).
local CONTENT_CLASSES = {
	Decal = true,
	Texture = true,
	MeshPart = true,
	SpecialMesh = true,
	SurfaceAppearance = true,
	ParticleEmitter = true,
	Beam = true,
	Trail = true,
	Sound = true,
	ImageLabel = true,
	ImageButton = true,
	Sky = true,
	Animation = true,
}

local current = nil -- elementos da tela atual

local function requireSettingsModule(name: string): any
	local settingsFolder = ReplicatedStorage.Shared:FindFirstChild("Settings")
	local moduleScript = settingsFolder and settingsFolder:WaitForChild(name, 5)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, moduleScript)
	if ok and type(result) == "table" then
		return result
	end
	return nil
end

local function buildGui()
	local gui = UIKit.ScreenGui(GUI_NAME, 200)

	local background = UIKit.Create("Frame", {
		Name = "Fundo",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	}) :: Frame
	UIKit.Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(28, 56, 32), Color3.fromRGB(6, 14, 8)),
		Parent = background,
	})

	local header = UIKit.Frame({
		Name = "Cabecalho",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.14),
		Size = UDim2.new(0.9, 0, 0, 130),
		Parent = background,
	})
	local title = UIKit.Title(GameConfig.GAME_TITLE, {
		Size = UDim2.new(1, 0, 0, 80),
		TextScaled = true,
		Parent = header,
	})
	UIKit.Create("UITextSizeConstraint", { MaxTextSize = 72, Parent = title })
	UIKit.Label({
		Text = GameConfig.GAME_SUBTITLE,
		Position = UDim2.fromOffset(0, 86),
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.TextMuted,
		TextSize = 22,
		Parent = header,
	})

	local panel = UIKit.Panel({
		Name = "Painel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -32),
		Size = UDim2.new(0.92, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = background,
	})
	UIKit.Create("UISizeConstraint", { MaxSize = Vector2.new(720, math.huge), Parent = panel })
	UIKit.ListLayout(panel, 8)

	local status = UIKit.Label({
		Name = "Status",
		Text = "Carregando…",
		Font = Theme.BoldFont,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
		Parent = panel,
	})

	local track = UIKit.Create("Frame", {
		Name = "Barra",
		BackgroundColor3 = Theme.WoodDark,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 14),
		LayoutOrder = 2,
		Parent = panel,
	}) :: Frame
	UIKit.Corner(track, UDim.new(1, 0))
	local fill = UIKit.Create("Frame", {
		Name = "Progresso",
		BackgroundColor3 = Theme.Gold,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = track,
	}) :: Frame
	UIKit.Corner(fill, UDim.new(1, 0))

	local detail = UIKit.Label({
		Name = "Detalhe",
		Text = "",
		TextSize = 16,
		TextColor3 = Theme.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 3,
		Parent = panel,
	})

	local note = UIKit.Label({
		Name = "Nota",
		Text = "Pré-carregando: a câmera passa por todos os cenários para compilar texturas e shaders agora. "
			.. "Assim o jogo não trava quando você entrar num lugar novo. "
			.. "(Dá para desligar em Configurações › Gráficos.)",
		TextSize = 15,
		TextColor3 = Theme.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		Visible = false,
		LayoutOrder = 4,
		Parent = panel,
	})

	local errorLabel = UIKit.Label({
		Name = "Erro",
		Text = "",
		TextSize = 16,
		TextColor3 = Theme.Danger,
		TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		Visible = false,
		LayoutOrder = 5,
		Parent = panel,
	})

	local tip = UIKit.Label({
		Name = "Dica",
		Text = "Dica: " .. TIPS[math.random(1, #TIPS)],
		TextSize = 17,
		TextColor3 = Theme.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = 6,
		Parent = panel,
	})

	return {
		gui = gui,
		background = background,
		header = header,
		panel = panel,
		status = status,
		fill = fill,
		detail = detail,
		note = note,
		errorLabel = errorLabel,
		tip = tip,
		progress = 0,
		alive = true,
	}
end

local function setStatus(text: string)
	if current then
		current.status.Text = text
	end
end

local function setDetail(text: string)
	if current then
		current.detail.Text = text
	end
end

local function setProgress(alpha: number)
	if not current then
		return
	end
	alpha = math.clamp(alpha, 0, 1)
	if math.abs(alpha - current.progress) < 0.002 then
		return
	end
	current.progress = alpha
	TweenService:Create(current.fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(alpha, 1) }):Play()
end

-- Instâncias com assets do mapa, dos sons e do céu.
local function collectContent(map: Instance): { Instance }
	local list = {}
	local count = 0
	for _, descendant in map:GetDescendants() do
		count += 1
		if count % 4000 == 0 then
			task.wait()
		end
		if CONTENT_CLASSES[descendant.ClassName] then
			table.insert(list, descendant)
		end
	end
	for _, descendant in SoundService:GetDescendants() do
		if descendant:IsA("Sound") then
			table.insert(list, descendant)
		end
	end
	for _, child in Lighting:GetChildren() do
		if child:IsA("Sky") then
			table.insert(list, child)
		end
	end
	return list
end

-- Posições de câmera: 3–4 ângulos por região + vistas gerais da ilha.
local function buildShots(map: Instance): { { cframe: CFrame, name: string } }
	local shots = {}
	local regions = map:FindFirstChild("Regions")
	if regions then
		for _, part in regions:GetDescendants() do
			if part:IsA("BasePart") then
				local regionName = part:GetAttribute("RegionName")
				local name = type(regionName) == "string" and regionName or part.Name
				local size, cframe = part.Size, part.CFrame
				local center = cframe.Position
				local horizontal = math.max(size.X, size.Z)
				local floorY = center.Y - size.Y / 2
				local big = horizontal > 80
				local angles = big and 4 or 3
				local eye
				if big then
					-- Áreas externas grandes: de cima, olhando para o chão em diagonal.
					eye = Vector3.new(center.X, floorY + math.clamp(horizontal * 0.2, 18, 70), center.Z)
				else
					-- Cômodos: do meio da sala, na altura dos olhos.
					eye = Vector3.new(center.X, floorY + math.clamp(size.Y * 0.45, 3, 8), center.Z)
				end
				for index = 0, angles - 1 do
					local angle = (index / angles) * math.pi * 2 + math.pi / 4
					local direction = cframe:VectorToWorldSpace(Vector3.new(math.cos(angle), 0, math.sin(angle)))
					local target
					if big then
						target = Vector3.new(center.X, floorY, center.Z) + direction * horizontal * 0.35
					else
						target = eye + direction * math.max(horizontal * 0.5, 4) - Vector3.new(0, 1.5, 0)
					end
					table.insert(shots, { cframe = CFrame.lookAt(eye, target), name = name })
				end
			end
		end
	end

	local center = GameConfig.ISLAND_CENTER + Vector3.new(0, GameConfig.GROUND_Y, 0)
	for index = 0, 3 do
		local angle = index * math.pi / 2 + math.pi / 4
		local eye = center
			+ Vector3.new(
				math.cos(angle) * GameConfig.ISLAND_RADIUS * 0.9,
				160,
				math.sin(angle) * GameConfig.ISLAND_RADIUS * 0.9
			)
		table.insert(shots, { cframe = CFrame.lookAt(eye, center), name = "Vista da ilha" })
	end
	return shots
end

local function readPreloadSetting(): boolean
	local SettingsClient = requireSettingsModule("SettingsClient")
	if SettingsClient and type(SettingsClient.Get) == "function" then
		local ok, settings = pcall(SettingsClient.Get)
		if
			ok
			and type(settings) == "table"
			and type(settings.graphics) == "table"
			and type(settings.graphics.preload) == "boolean"
		then
			return settings.graphics.preload
		end
	end
	return SettingsSchema.Defaults().graphics.preload
end

local function restoreCamera()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Custom
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

local function runPreload(map: Instance)
	local GraphicsApplier = requireSettingsModule("GraphicsApplier")
	local function setCulling(enabled: boolean)
		if GraphicsApplier and type(GraphicsApplier.SetCullingEnabled) == "function" then
			local ok, err = pcall(GraphicsApplier.SetCullingEnabled, enabled)
			if not ok then
				warn("[LoadingScreen] Erro ao mudar o culling: " .. tostring(err))
			end
		end
	end

	current.note.Visible = true
	setCulling(false)

	local ok, err = pcall(function()
		-- 1. Assets
		setStatus("Pré-carregando texturas e sons…")
		local assets = collectContent(map)
		local total = #assets
		for first = 1, total, PRELOAD_BATCH do
			local last = math.min(first + PRELOAD_BATCH - 1, total)
			local batch = table.move(assets, first, last, 1, {})
			pcall(function()
				ContentProvider:PreloadAsync(batch)
			end)
			setProgress(0.3 + 0.2 * last / total)
			setDetail(("Assets: %d/%d"):format(last, total))
		end
		setProgress(0.5)

		-- 2. Varredura de câmera (renderiza cada cenário para compilar materiais e shaders)
		setStatus("Pré-carregando os cenários…")
		local shots = buildShots(map)
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		-- O fundo fica translúcido para a "visita" aparecer atrás do painel.
		current.background.BackgroundTransparency = 0.45
		current.header.Visible = false
		for index, shot in shots do
			camera.CFrame = shot.cframe
			for _ = 1, FRAMES_PER_SHOT do
				RunService.RenderStepped:Wait()
			end
			setProgress(0.5 + 0.5 * index / #shots)
			setDetail(("Visitando: %s (%d/%d)"):format(shot.name, index, #shots))
		end
	end)
	if not ok then
		warn("[LoadingScreen] Erro no pré-carregamento: " .. tostring(err))
	end

	setCulling(true)
	restoreCamera()
	current.background.BackgroundTransparency = 0
	current.header.Visible = true
	setDetail("")
end

-- Fecha a tela imediatamente (usado se algo der errado).
function LoadingScreen.ForceClose()
	if current then
		current.alive = false
		current.gui:Destroy()
		current = nil
	end
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local leftover = playerGui and playerGui:FindFirstChild(GUI_NAME)
	if leftover then
		leftover:Destroy()
	end
	restoreCamera()
end

-- Mostra a tela e só retorna quando o jogo está pronto para jogar.
-- isSettingsReady: função opcional que diz se as configurações já chegaram do servidor.
function LoadingScreen.Run(isSettingsReady: (() -> boolean)?)
	current = buildGui()
	local screen = current

	-- Dicas trocando de tempos em tempos
	task.spawn(function()
		local index = math.random(1, #TIPS)
		while screen.alive do
			task.wait(TIP_INTERVAL)
			if not screen.alive then
				break
			end
			index = index % #TIPS + 1
			screen.tip.Text = "Dica: " .. TIPS[index]
		end
	end)

	-- 1. Jogo carregado
	if not game:IsLoaded() then
		setStatus("Carregando o jogo…")
		game.Loaded:Wait()
	end

	-- 2. Mapa construído pelo servidor
	local started = os.clock()
	while not workspace:GetAttribute("MapReady") do
		local elapsed = os.clock() - started
		setStatus(("Construindo a ilha… %ds"):format(math.floor(elapsed)))
		setProgress(0.3 * (1 - math.exp(-elapsed / 12)))
		task.wait(0.25)
	end
	local map = workspace:WaitForChild("Map", 15)
	local mapError = workspace:GetAttribute("MapError")
	if mapError then
		screen.errorLabel.Text = "O mapa principal não pôde ser construído (veja o Output do servidor). "
			.. "Um mapa reserva será usado."
		screen.errorLabel.Visible = true
	end
	setProgress(0.3)

	-- 3. Configurações do jogador (com limite de tempo)
	local waitStart = os.clock()
	while isSettingsReady and not isSettingsReady() and os.clock() - waitStart < SETTINGS_TIMEOUT do
		setStatus("Carregando suas configurações…")
		task.wait(0.1)
	end

	-- 4. Pré-carregamento (opcional)
	if map and readPreloadSetting() then
		runPreload(map)
	else
		setStatus("Quase lá…")
	end

	setStatus("Pronto!")
	setProgress(1)
	task.wait(0.35)

	-- Some com um fade
	screen.alive = false
	screen.panel.Visible = false
	screen.header.Visible = false
	local fade = TweenService:Create(screen.background, TweenInfo.new(0.6), { BackgroundTransparency = 1 })
	fade:Play()
	task.delay(0.65, function()
		screen.gui:Destroy()
	end)
	if current == screen then
		current = nil
	end
end

return LoadingScreen
