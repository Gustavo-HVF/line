--!nonstrict
-- Tela de configurações do lobby (somente cliente).
--   SettingsUI.Open(onClose)   abre o painel com as abas "Áudio" e "Gráficos"
--   SettingsUI.Close()         fecha, devolve a câmera ao CFrame/CameraType de antes e chama onClose
--
-- Aba Áudio: painel no centro; sliders aplicam o volume ao vivo (soltar "Efeitos" toca um clique de exemplo).
-- Aba Gráficos: a tela escurece, a câmera passa para workspace.LobbyMarkers.DemoCamera (sala de demonstração,
-- com o boneco do jogador) e a tela clareia; o painel vai para a lateral direita (~38% da largura, fundo
-- translúcido). Cada mudança passa por SettingsClient.Set → GraphicsApplier, então a sala muda NA HORA.
-- Ao voltar para Áudio ou fechar, a mesma transição preta devolve a câmera ao que era.
-- A interface é construída uma vez e reaproveitada nas próximas aberturas.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local UIKit = require(ReplicatedStorage.Shared.UI.UIKit)
local SettingsSchema = require(ReplicatedStorage.Shared.Settings.SettingsSchema)
local SettingsClient = require(ReplicatedStorage.Shared.Settings.SettingsClient)

local SettingsUI = {}

local Theme = UIKit.Theme

local GUI_NAME = "Configuracoes"
local DISPLAY_ORDER = 40
local CAMERA_BIND = "SettingsDemoCamera"
local CAMERA_PRIORITY = Enum.RenderPriority.Last.Value -- depois de qualquer outra câmera
local RETURN_TIME = 0.9
local CLOSE_RETURN_TIME = 0.6
local DEMO_FOV = 70
local FADE_IN = 0.35 -- tela preta da transição para a sala de gráficos (e de volta)
local FADE_HOLD = 0.15
local FADE_OUT = 0.45
local DEMO_WAIT = 3 -- s esperando o marcador DemoCamera aparecer
local LAYOUT_TWEEN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MARKER_DISTANCES = { 100, 200, 400, 800, 1500 } -- placas da pista da sala de demonstração

-- Textos -------------------------------------------------------------------------------------------

local SHADOW_TEXT = {
	off = "Desligadas: nada faz sombra e a sala fica mais clara e “chapada”. "
		.. "Impacto no desempenho: o menor de todos; boa escolha para celulares fracos.",
	low = "Baixas: só o sol faz sombra, com bordas suaves. Objetos pequenos e as luzes (lustre, luminárias e a "
		.. "luz da janela) ficam sem sombra. Impacto no desempenho: médio, bom equilíbrio.",
	high = "Altas: sombras nítidas do sol e de todas as luzes. Repare na grade da janela desenhada no chão e nas "
		.. "sombras das colunas e do lustre. Impacto no desempenho: o maior, pesa na placa de vídeo.",
}

local TEXTURE_TEXT = "Ligada: tijolo, madeira, mármore, tecido, tapete, grama e granito viram plástico liso, e "
	.. "decalques e detalhes pintados somem (repare nas paredes, no sofá, no tapete e no quadro). "
	.. "Economiza memória de vídeo e ajuda aparelhos mais fracos; o visual fica mais simples."

local PRELOAD_TEXT = "Na tela de carregamento da partida, a câmera passa por todas as áreas do mapa para carregar "
	.. "as texturas e preparar materiais e shaders antes de você jogar. O carregamento fica mais longo, mas o "
	.. "jogo trava menos quando você entra num lugar novo. O Roblox compila os shaders sozinho de qualquer "
	.. "jeito: o jogo só antecipa esse trabalho. (Não muda nada nesta sala; vale para a partida.)"

local INTRO_TEXT = "Olhe a sala ao lado: cada mudança aparece na hora. Pela janela, a pista tem marcos a "
	.. "100, 200, 400, 800 e 1500 studs para você ver a distância de renderização."

local ROBLOX_NOTE = "O Roblox também ajusta a qualidade gráfica do aparelho (menu do Roblox › Configurações). "
	.. "Em qualidade baixa ele mesmo encurta a distância de visão; estas opções se somam a isso."

local AUDIO_HINT = "Cada volume é multiplicado pelo Geral. Solte o controle de Efeitos para ouvir um exemplo."

-- Disposição do painel: no centro (Áudio) ou na lateral direita (Gráficos, com a sala aparecendo).
local LAYOUTS = {
	center = {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.new(0.92, 0, 0.88, 0),
		maxSize = Vector2.new(560, 640),
		minSize = Vector2.new(0, 0),
		panelTransparency = 0.05,
		cardTransparency = 0.1,
		overlayTransparency = 0.45,
	},
	side = {
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -10, 0.5, 0),
		size = UDim2.new(0.38, 0, 1, -20),
		maxSize = Vector2.new(560, math.huge),
		minSize = Vector2.new(280, 0),
		panelTransparency = 0.3,
		cardTransparency = 0.35,
		overlayTransparency = 1,
	},
}

-- Estado -------------------------------------------------------------------------------------------

local ui = nil -- elementos da interface (construída uma vez)
local session = nil -- sessão aberta: câmera salva, onClose, aba atual...
local applyingLocal = false -- true enquanto esta tela chama SettingsClient.Set

-- Câmera -------------------------------------------------------------------------------------------

local cameraAnimation = nil
local cameraBound = false

local function easeInOut(t: number): number
	if t < 0.5 then
		return 4 * t * t * t
	end
	return 1 - (-2 * t + 2) ^ 3 / 2
end

-- Curva de Bézier com um arco para cima (sobrevoa o lobby em vez de atravessar as construções).
local function evaluate(animation, eased: number): CFrame
	local p0, p2 = animation.from.Position, animation.to.Position
	local p1 = (p0 + p2) / 2 + Vector3.new(0, animation.arc, 0)
	local u = 1 - eased
	local position = p0 * (u * u) + p1 * (2 * u * eased) + p2 * (eased * eased)
	local rotation = animation.from.Rotation:Lerp(animation.to.Rotation, eased)
	return CFrame.new(position) * rotation
end

local function stopCameraAnimation()
	cameraAnimation = nil
	if cameraBound then
		cameraBound = false
		RunService:UnbindFromRenderStep(CAMERA_BIND)
	end
end

local function onRenderStep()
	local animation = cameraAnimation
	local camera = workspace.CurrentCamera
	if not animation or not camera then
		return
	end
	local alpha = 1
	if animation.duration > 0 then
		alpha = math.clamp((os.clock() - animation.start) / animation.duration, 0, 1)
	end
	local eased = easeInOut(alpha)
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	camera.CFrame = evaluate(animation, eased)
	camera.FieldOfView = animation.fromFov + (animation.toFov - animation.fromFov) * eased
	if alpha >= 1 and not animation.hold then
		stopCameraAnimation()
		if animation.onDone then
			animation.onDone()
		end
	end
end

-- hold = true: ao chegar, continua segurando a câmera no destino (outra câmera não "rouba" a vista).
local function startCameraAnimation(target: CFrame, duration: number, toFov: number, hold: boolean, onDone)
	local camera = workspace.CurrentCamera
	if not camera then
		if onDone then
			onDone()
		end
		return
	end
	local from = camera.CFrame
	local distance = (target.Position - from.Position).Magnitude
	cameraAnimation = {
		from = from,
		to = target,
		start = os.clock(),
		duration = if distance < 0.05 then math.min(duration, 0.2) else duration,
		arc = if distance > 60 then math.min(distance * 0.12, 140) else 0,
		fromFov = camera.FieldOfView,
		toFov = toFov,
		hold = hold,
		onDone = onDone,
	}
	if not cameraBound then
		cameraBound = true
		RunService:BindToRenderStep(CAMERA_BIND, CAMERA_PRIORITY, onRenderStep)
	end
end

-- Tela preta da transição (fica atrás do painel de configurações, que continua visível).
local fadeFrame: Frame? = nil
local fadeToken = 0

local function ensureFade(): Frame
	if fadeFrame and fadeFrame.Parent and fadeFrame.Parent.Parent then
		return fadeFrame
	end
	local gui = UIKit.ScreenGui("TransicaoGraficos", DISPLAY_ORDER - 1)
	fadeFrame = UIKit.Create("Frame", {
		Name = "Preto",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = gui,
	}) :: Frame
	return fadeFrame :: Frame
end

-- Escurece, executa `midAction` com a tela preta (troca a câmera) e clareia. onDone roda ao clarear.
local function fadeCut(midAction: () -> (), onDone: (() -> ())?)
	fadeToken += 1
	local token = fadeToken
	local frame = ensureFade()
	frame.Visible = true
	TweenService:Create(frame, TweenInfo.new(FADE_IN, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		BackgroundTransparency = 0,
	}):Play()
	task.delay(FADE_IN, function()
		local ok, err = pcall(midAction)
		if not ok then
			warn("[SettingsUI] Erro na transição da câmera: " .. tostring(err))
		end
		task.wait(FADE_HOLD)
		if token == fadeToken then
			TweenService:Create(frame, TweenInfo.new(FADE_OUT, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				BackgroundTransparency = 1,
			}):Play()
			task.delay(FADE_OUT, function()
				if token == fadeToken then
					frame.Visible = false
				end
			end)
		end
		if onDone then
			onDone()
		end
	end)
end

local function restoreSavedCamera(saved)
	local camera = workspace.CurrentCamera
	if not camera or not saved then
		return
	end
	camera.CFrame = saved.cframe
	camera.FieldOfView = saved.fov
	camera.CameraType = saved.cameraType
end

local function readDemoCFrame(): CFrame?
	local markers = workspace:FindFirstChild("LobbyMarkers")
	if not markers then
		return nil
	end
	local part = markers:FindFirstChild("DemoCamera")
	if part and part:IsA("BasePart") then
		return part.CFrame
	end
	-- Com streaming ligado a Part pode não ter chegado; o DemoRoom guarda o CFrame num atributo da pasta.
	local attribute = markers:GetAttribute("DemoCameraCFrame")
	if typeof(attribute) == "CFrame" then
		return attribute
	end
	return nil
end

local function waitDemoCFrame(timeout: number): CFrame?
	local deadline = os.clock() + timeout
	local result = readDemoCFrame()
	while not result and os.clock() < deadline do
		task.wait(0.1)
		result = readDemoCFrame()
	end
	return result
end

local function requestStreamingAround(position: Vector3)
	if not workspace.StreamingEnabled then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			Players.LocalPlayer:RequestStreamAroundAsync(position, 3)
		end)
		if not ok then
			warn("[SettingsUI] Não foi possível carregar a área da sala de demonstração: " .. tostring(err))
		end
	end)
end

-- Textos dinâmicos --------------------------------------------------------------------------------

local function visibleMarkersText(studs: number): string
	local visible = {}
	for _, distance in MARKER_DISTANCES do
		if distance <= studs then
			table.insert(visible, tostring(distance))
		end
	end
	if #visible == #MARKER_DISTANCES then
		return "todos os marcos, até o de 1500 studs"
	elseif #visible == 0 then
		return "nenhum marco"
	elseif #visible == 1 then
		return ("só o marco de %s studs"):format(visible[1])
	end
	local last = table.remove(visible)
	return ("os marcos de %s e %s studs"):format(table.concat(visible, ", "), last)
end

local function distanceText(index: number): string
	local studs = GameConfig.RENDER_DISTANCES[index] or GameConfig.RENDER_DISTANCES[3]
	local label = GameConfig.RENDER_DISTANCE_LABELS[index] or "?"
	return ("%s: cenários a mais de %d studs da câmera deixam de ser desenhados. Na pista lá fora aparecem %s. "):format(
		label,
		studs,
		visibleMarkersText(studs)
	) .. "Menor distância = mais FPS e menos memória; maior = você enxerga mais longe. O chão e o céu nunca somem."
end

-- Componentes ---------------------------------------------------------------------------------------

local function textSize(normal: number): number
	if ui and ui.compact then
		return math.max(normal - 3, 12)
	end
	return normal
end

local function makeLabel(parent: Instance, text: string, order: number, props: { [string]: any }?): TextLabel
	local merged = {
		Text = text,
		TextSize = textSize(15),
		TextColor3 = Theme.TextMuted,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = order,
		Parent = parent,
	}
	if props then
		for key, value in props do
			merged[key] = value
		end
	end
	return UIKit.Label(merged)
end

local function makeCard(parent: Instance, order: number): Frame
	local card = UIKit.Create("Frame", {
		Name = "Cartao",
		BackgroundColor3 = Theme.PanelLight,
		BackgroundTransparency = LAYOUTS.center.cardTransparency,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -4, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
	}) :: Frame
	UIKit.Corner(card, UDim.new(0, 8))
	UIKit.Padding(card, 10)
	UIKit.ListLayout(card, 6)
	table.insert(ui.cards, card)
	return card
end

local function makeCardTitle(card: Instance, text: string)
	UIKit.Label({
		Text = text,
		Font = Theme.BoldFont,
		TextSize = textSize(19),
		TextColor3 = Theme.Gold,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 0,
		Parent = card,
	})
end

-- Botões lado a lado ocupando a largura toda (cabe no painel estreito do celular).
local function makeSegmented(parent: Instance, order: number, options, onPick)
	local holder = UIKit.Frame({
		Name = "Opcoes",
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = order,
		Parent = parent,
	})
	local layout = UIKit.ListLayout(holder, 6, true)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	local count = #options
	local gap = 6 * (count - 1) / count
	local buttons = {}
	local selected = nil

	local function render()
		for value, button in buttons do
			local isSelected = value == selected
			button.BackgroundColor3 = isSelected and Theme.Gold or Theme.WoodDark
			button.TextColor3 = isSelected and Theme.WoodDark or Theme.Text
		end
	end

	for index, option in options do
		local button = UIKit.Create("TextButton", {
			Name = tostring(option.Value),
			Text = option.Label,
			AutoButtonColor = false,
			Font = Theme.BoldFont,
			TextScaled = true,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Size = UDim2.new(1 / count, -gap, 1, 0),
			Parent = holder,
		}) :: TextButton
		UIKit.Corner(button, UDim.new(0, 6))
		UIKit.Create("UITextSizeConstraint", { MaxTextSize = textSize(17), MinTextSize = 9, Parent = button })
		UIKit.Create("UIPadding", {
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 4),
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
			Parent = button,
		})
		buttons[option.Value] = button
		button.Activated:Connect(function()
			if selected == option.Value then
				return
			end
			SoundUtil.Play("UIClick", { Volume = 0.4 })
			selected = option.Value
			render()
			onPick(option.Value)
		end)
	end

	return {
		Instance = holder,
		Set = function(value)
			selected = value
			render()
		end,
	}
end

local function makeTabButton(parent: Instance, text: string, order: number, onClick): TextButton
	local button = UIKit.Create("TextButton", {
		Name = text,
		Text = text,
		AutoButtonColor = false,
		Font = Theme.BoldFont,
		TextSize = textSize(20),
		BorderSizePixel = 0,
		LayoutOrder = order,
		Size = UDim2.new(0.5, -4, 1, 0),
		Parent = parent,
	}) :: TextButton
	UIKit.Corner(button, UDim.new(0, 8))
	UIKit.Stroke(button, Theme.WoodDark, 2)
	button.Activated:Connect(function()
		SoundUtil.Play("UIClick", { Volume = 0.4 })
		onClick()
	end)
	return button
end

-- Aplicar mudanças ----------------------------------------------------------------------------------

local function refreshDescriptions(settings)
	if not ui then
		return
	end
	ui.shadowDescription.Text = SHADOW_TEXT[settings.graphics.shadows] or ""
	ui.distanceDescription.Text = distanceText(settings.graphics.renderDistance)
end

-- Atualiza todos os controles (sem disparar OnChanged) a partir das configurações.
local function refreshControls(settings)
	if not ui then
		return
	end
	local audio = settings.audio
	ui.sliders.master.Set(audio.master, true)
	ui.sliders.music.Set(audio.music, true)
	ui.sliders.effects.Set(audio.effects, true)
	ui.sliders.ambience.Set(audio.ambience, true)
	local graphics = settings.graphics
	ui.shadowChoice.Set(graphics.shadows)
	ui.textureToggle.Set(graphics.reducedTextures, true)
	ui.distanceChoice.Set(graphics.renderDistance)
	ui.preloadToggle.Set(graphics.preload, true)
	refreshDescriptions(settings)
end

-- Muda uma configuração e aplica na hora (SettingsClient sanitiza, aplica e salva com debounce).
local function commit(mutate: (any) -> ())
	local settings = SettingsClient.Get()
	mutate(settings)
	applyingLocal = true
	local ok, err = pcall(SettingsClient.Set, settings)
	applyingLocal = false
	if not ok then
		warn("[SettingsUI] Erro ao aplicar a configuração: " .. tostring(err))
	end
	refreshDescriptions(SettingsClient.Get())
end

-- Disposição e abas ---------------------------------------------------------------------------------

local function applyLayout(name: string, instant: boolean?)
	if not ui then
		return
	end
	local layout = LAYOUTS[name]
	ui.layoutName = name
	ui.sizeConstraint.MaxSize = layout.maxSize
	ui.sizeConstraint.MinSize = layout.minSize
	local panelGoal = {
		AnchorPoint = layout.anchor,
		Position = layout.position,
		Size = layout.size,
		BackgroundTransparency = layout.panelTransparency,
	}
	if instant then
		for key, value in panelGoal do
			ui.panel[key] = value
		end
		ui.overlay.BackgroundTransparency = layout.overlayTransparency
		for _, card in ui.cards do
			card.BackgroundTransparency = layout.cardTransparency
		end
		return
	end
	TweenService:Create(ui.panel, LAYOUT_TWEEN, panelGoal):Play()
	TweenService:Create(ui.overlay, LAYOUT_TWEEN, { BackgroundTransparency = layout.overlayTransparency }):Play()
	for _, card in ui.cards do
		TweenService:Create(card, LAYOUT_TWEEN, { BackgroundTransparency = layout.cardTransparency }):Play()
	end
end

local function renderTabs(tab: string)
	for name, button in ui.tabButtons do
		local selected = name == tab
		button.BackgroundColor3 = selected and Theme.Gold or Theme.Wood
		button.TextColor3 = selected and Theme.WoodDark or Theme.Text
	end
	ui.pages.audio.Visible = tab == "audio"
	ui.pages.graphics.Visible = tab == "graphics"
end

-- Câmera volta ao que era quando a tela abriu.
local function returnCamera(current, _duration: number, onDone)
	current.cameraToken += 1
	if not current.cameraAway then
		stopCameraAnimation()
		if onDone then
			onDone()
		end
		return
	end
	local saved = current.saved
	local token = current.cameraToken
	fadeCut(function()
		if current.cameraToken ~= token then
			return -- outra troca de aba começou durante o escurecer
		end
		stopCameraAnimation()
		restoreSavedCamera(saved)
		current.cameraAway = false
	end, onDone)
end

local function enterDemoCamera(current)
	current.cameraToken += 1
	local token = current.cameraToken
	task.spawn(function()
		local target = waitDemoCFrame(DEMO_WAIT)
		if session ~= current or current.closing or current.tab ~= "graphics" or current.cameraToken ~= token then
			return
		end
		if not target then
			-- Sem sala: o painel volta para o centro e as opções continuam funcionando.
			ui.demoMissing.Visible = true
			applyLayout("center")
			return
		end
		ui.demoMissing.Visible = false
		requestStreamingAround(target.Position)
		current.cameraAway = true
		fadeCut(function()
			if session ~= current or current.closing or current.tab ~= "graphics" or current.cameraToken ~= token then
				return
			end
			-- duração 0: corte seco escondido pela tela preta; "hold" mantém a câmera na sala
			startCameraAnimation(target, 0, DEMO_FOV, true, nil)
		end)
	end)
end

local function selectTab(tab: string)
	local current = session
	if not current or current.closing or not ui then
		return
	end
	if current.tab == tab then
		return
	end
	current.tab = tab
	renderTabs(tab)
	ui.pages[tab].CanvasPosition = Vector2.zero
	if tab == "graphics" then
		applyLayout("side")
		enterDemoCamera(current)
	else
		applyLayout("center")
		returnCamera(current, RETURN_TIME, nil)
	end
end

-- "Restaurar padrão": volta ao padrão só a seção da aba aberta.
local function restoreDefaults()
	local current = session
	if not current then
		return
	end
	local defaults = SettingsSchema.Defaults()
	commit(function(settings)
		if current.tab == "graphics" then
			settings.graphics = defaults.graphics
		else
			settings.audio = defaults.audio
		end
	end)
	refreshControls(SettingsClient.Get())
	UIKit.Toast(
		current.tab == "graphics" and "Gráficos restaurados para o padrão." or "Áudio restaurado para o padrão.",
		"info",
		2.5
	)
end

-- Construção ----------------------------------------------------------------------------------------

local function buildAudioPage(page: ScrollingFrame)
	local settings = SettingsClient.Get()
	makeLabel(page, "Volume", 1, {
		Font = Theme.BoldFont,
		TextSize = textSize(19),
		TextColor3 = Theme.Gold,
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(1, 0, 0, 26),
	})

	local function slider(key: string, text: string, order: number)
		return UIKit.Slider({
			Name = "Volume " .. text,
			Text = text,
			Min = 0,
			Max = 1,
			Step = 0.01,
			Value = settings.audio[key],
			LayoutOrder = order,
			Parent = page,
			OnChanged = function(value)
				if key == "effects" and session then
					session.effectsDirty = true
				end
				commit(function(newSettings)
					newSettings.audio[key] = value
				end)
			end,
		})
	end

	ui.sliders = {
		master = slider("master", "Geral", 2),
		music = slider("music", "Música", 3),
		effects = slider("effects", "Efeitos", 4),
		ambience = slider("ambience", "Ambiente", 5),
	}
	makeLabel(page, AUDIO_HINT, 6)
end

local function buildGraphicsPage(page: ScrollingFrame)
	local settings = SettingsClient.Get()
	makeLabel(page, INTRO_TEXT, 1, { TextColor3 = Theme.Text })
	ui.demoMissing = makeLabel(
		page,
		"A sala de demonstração não está disponível agora, mas as opções continuam valendo.",
		2,
		{ TextColor3 = Theme.Warning, Visible = false }
	)

	-- Sombras
	local shadowCard = makeCard(page, 3)
	makeCardTitle(shadowCard, "Sombras")
	local shadowOptions = {}
	for _, option in SettingsSchema.SHADOW_OPTIONS do
		table.insert(shadowOptions, { Value = option, Label = SettingsSchema.SHADOW_LABELS[option] or option })
	end
	ui.shadowChoice = makeSegmented(shadowCard, 1, shadowOptions, function(value)
		commit(function(newSettings)
			newSettings.graphics.shadows = value
		end)
	end)
	ui.shadowChoice.Set(settings.graphics.shadows)
	ui.shadowDescription = makeLabel(shadowCard, "", 2)

	-- Redução de texturas
	local textureCard = makeCard(page, 4)
	ui.textureToggle = UIKit.Toggle({
		Name = "Reducao de texturas",
		Text = "Redução de texturas",
		Value = settings.graphics.reducedTextures,
		LayoutOrder = 0,
		Parent = textureCard,
		OnChanged = function(value)
			commit(function(newSettings)
				newSettings.graphics.reducedTextures = value
			end)
		end,
	})
	makeLabel(textureCard, TEXTURE_TEXT, 1)

	-- Distância de renderização
	local distanceCard = makeCard(page, 5)
	makeCardTitle(distanceCard, "Distância de renderização")
	local distanceOptions = {}
	for index, label in GameConfig.RENDER_DISTANCE_LABELS do
		table.insert(distanceOptions, { Value = index, Label = label })
	end
	ui.distanceChoice = makeSegmented(distanceCard, 1, distanceOptions, function(value)
		commit(function(newSettings)
			newSettings.graphics.renderDistance = value
		end)
	end)
	ui.distanceChoice.Set(settings.graphics.renderDistance)
	ui.distanceDescription = makeLabel(distanceCard, "", 2)

	-- Pré-carregar
	local preloadCard = makeCard(page, 6)
	ui.preloadToggle = UIKit.Toggle({
		Name = "Pre-carregar jogo",
		Text = "Pré-carregar jogo",
		Value = settings.graphics.preload,
		LayoutOrder = 0,
		Parent = preloadCard,
		OnChanged = function(value)
			commit(function(newSettings)
				newSettings.graphics.preload = value
			end)
		end,
	})
	makeLabel(preloadCard, PRELOAD_TEXT, 1)

	makeLabel(page, ROBLOX_NOTE, 7, { TextSize = textSize(14) })
	refreshDescriptions(settings)
end

local function buildPage(name: string, parent: Instance): ScrollingFrame
	local page = UIKit.List({
		Name = name,
		Spacing = 10,
		Position = UDim2.fromOffset(0, 92),
		Size = UDim2.new(1, 0, 1, -92 - 60),
		Visible = false,
		Parent = parent,
	})
	UIKit.Create("UIPadding", {
		PaddingTop = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 10),
		Parent = page,
	})
	return page
end

local function buildUI()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	ui = {
		compact = viewport.Y < 520 or viewport.X < 760,
		cards = {},
		tabButtons = {},
		pages = {},
		connections = {},
		layoutName = "center",
	}

	local gui = UIKit.ScreenGui(GUI_NAME, DISPLAY_ORDER)
	gui.Enabled = false
	ui.gui = gui

	-- Fundo que escurece e bloqueia cliques nos menus de trás.
	ui.overlay = UIKit.Create("TextButton", {
		Name = "Fundo",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Overlay,
		BackgroundTransparency = LAYOUTS.center.overlayTransparency,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	}) :: TextButton

	local panel = UIKit.Panel({
		Name = "Painel",
		AnchorPoint = LAYOUTS.center.anchor,
		Position = LAYOUTS.center.position,
		Size = LAYOUTS.center.size,
		BackgroundTransparency = LAYOUTS.center.panelTransparency,
		Parent = gui,
	})
	ui.panel = panel
	ui.sizeConstraint = UIKit.Create("UISizeConstraint", {
		MaxSize = LAYOUTS.center.maxSize,
		MinSize = LAYOUTS.center.minSize,
		Parent = panel,
	}) :: UISizeConstraint

	UIKit.Title("Configurações", {
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = textSize(34),
		Parent = panel,
	})

	local tabs = UIKit.Frame({
		Name = "Abas",
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 38),
		Parent = panel,
	})
	UIKit.ListLayout(tabs, 8, true)
	ui.tabButtons.audio = makeTabButton(tabs, "Áudio", 1, function()
		selectTab("audio")
	end)
	ui.tabButtons.graphics = makeTabButton(tabs, "Gráficos", 2, function()
		selectTab("graphics")
	end)

	ui.pages.audio = buildPage("Audio", panel)
	ui.pages.graphics = buildPage("Graficos", panel)
	buildAudioPage(ui.pages.audio)
	buildGraphicsPage(ui.pages.graphics)

	local footer = UIKit.Frame({
		Name = "Rodape",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 50),
		Parent = panel,
	})
	UIKit.ListLayout(footer, 10, true)
	UIKit.Button({
		Name = "Restaurar",
		Text = "Restaurar padrão",
		Style = "ghost",
		TextSize = textSize(19),
		TextScaled = false,
		Size = UDim2.new(0.5, -5, 1, 0),
		LayoutOrder = 1,
		OnClick = restoreDefaults,
		Parent = footer,
	})
	UIKit.Button({
		Name = "Voltar",
		Text = "Voltar",
		Style = "primary",
		TextSize = textSize(20),
		Size = UDim2.new(0.5, -5, 1, 0),
		LayoutOrder = 2,
		OnClick = function()
			SettingsUI.Close()
		end,
		Parent = footer,
	})

	-- Configurações mudaram por fora (ex.: resposta do servidor chegou depois): atualiza os controles.
	table.insert(
		ui.connections,
		SettingsClient.Changed:Connect(function(settings)
			if applyingLocal or not ui or not ui.gui.Enabled then
				return
			end
			refreshControls(settings)
		end)
	)
	-- Soltou o slider de Efeitos: toca um clique de exemplo já com o volume novo.
	table.insert(
		ui.connections,
		UserInputService.InputEnded:Connect(function(input)
			local current = session
			if not current or not current.effectsDirty then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				current.effectsDirty = false
				SoundUtil.Play("UIClick", { Volume = 0.6 })
			end
		end)
	)
	-- Se a ScreenGui for destruída por fora, a próxima abertura reconstrói tudo.
	table.insert(
		ui.connections,
		gui.Destroying:Connect(function()
			local old = ui
			if old and old.gui == gui then
				for _, connection in old.connections do
					connection:Disconnect()
				end
				ui = nil
			end
		end)
	)
end

local function ensureUI()
	if ui and ui.gui and ui.gui.Parent then
		return
	end
	if ui then
		for _, connection in ui.connections do
			connection:Disconnect()
		end
		ui = nil
	end
	buildUI()
end

-- Termina na hora um fechamento que ainda estava animando a câmera.
local function finishClosingNow()
	local current = session
	if not current or not current.closing then
		return
	end
	stopCameraAnimation()
	if current.cameraAway then
		restoreSavedCamera(current.saved)
		current.cameraAway = false
	end
	session = nil
	if current.onClose and not current.closeCalled then
		current.closeCalled = true
		task.spawn(current.onClose)
	end
end

-- API pública ---------------------------------------------------------------------------------------

function SettingsUI.Open(onClose: (() -> ())?)
	if session and not session.closing then
		session.onClose = onClose
		return
	end
	finishClosingNow()

	if not SettingsClient.IsLoaded() then
		-- Idempotente: se o menu já iniciou, só espera o mesmo carregamento terminar.
		task.spawn(SettingsClient.Init)
	end
	ensureUI()

	local camera = workspace.CurrentCamera
	session = {
		onClose = onClose,
		tab = "audio",
		closing = false,
		closeCalled = false,
		cameraAway = false,
		cameraToken = 0,
		effectsDirty = false,
		saved = {
			cameraType = camera and camera.CameraType or Enum.CameraType.Custom,
			cframe = camera and camera.CFrame or CFrame.new(),
			fov = camera and camera.FieldOfView or DEMO_FOV,
		},
	}

	ui.demoMissing.Visible = false
	refreshControls(SettingsClient.Get())
	renderTabs("audio")
	ui.pages.audio.CanvasPosition = Vector2.zero
	applyLayout("center", true)
	ui.gui.Enabled = true
end

function SettingsUI.Close()
	local current = session
	if not current or current.closing then
		return
	end
	current.closing = true
	current.effectsDirty = false
	if ui then
		ui.gui.Enabled = false
	end
	-- Manda agora qualquer gravação que ainda estava no debounce.
	pcall(SettingsClient.Flush)

	returnCamera(current, CLOSE_RETURN_TIME, function()
		if session == current then
			session = nil
		end
		if current.onClose and not current.closeCalled then
			current.closeCalled = true
			task.spawn(current.onClose)
		end
	end)
end

function SettingsUI.IsOpen(): boolean
	return session ~= nil and not session.closing
end

return SettingsUI
