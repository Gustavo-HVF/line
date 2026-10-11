--!nonstrict
-- Enigma do tabuleiro na tela: painel de "vidro" verde no centro, texto em efeito de máquina de escrever,
-- tambores e contagem até o evento. Some depois de ~8 s ou quando o evento começa.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local UIKit = require(ReplicatedStorage.Shared.UI.UIKit)

local RiddleUI = {}

local Theme = UIKit.Theme
local LocalPlayer = Players.LocalPlayer

local HIDE_AFTER = 8
local CHARS_PER_SECOND = 32
local FAR_FROM_BOARD = 80 -- longe assim, o tambor 3D do servidor não é ouvido: toca um local
local MAX_TEXT = 500

local GLASS_BG = Color3.fromRGB(8, 34, 16)
local GLASS_TEXT = Color3.fromRGB(120, 255, 140)
local GLASS_MUTED = Color3.fromRGB(150, 210, 160)

local initialized = false
local ui: { [string]: any } = {}
local token = 0
local visible = false

local function build()
	local gui = UIKit.ScreenGui("RiddleUI", 20)

	-- CanvasGroup só para o fade; o "vidro" fica num Frame interno (margem para a borda não ser cortada).
	local panel = UIKit.Create("CanvasGroup", {
		Name = "Enigma",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(640, 270),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Visible = false,
		Parent = gui,
	}) :: CanvasGroup
	local scale = Instance.new("UIScale")
	scale.Parent = panel

	local glass = UIKit.Create("Frame", {
		Name = "Vidro",
		Position = UDim2.fromOffset(5, 5),
		Size = UDim2.new(1, -10, 1, -10),
		BackgroundColor3 = GLASS_BG,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Parent = panel,
	}) :: Frame
	UIKit.Corner(glass, UDim.new(0, 16))
	UIKit.Stroke(glass, GLASS_TEXT, 3)
	UIKit.Padding(glass, 14)
	UIKit.Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 190, 160)),
		Parent = glass,
	})
	UIKit.ListLayout(glass, 8)

	UIKit.Label({
		Text = "O tabuleiro fala…",
		Font = Theme.TitleFont,
		TextSize = 22,
		TextColor3 = GLASS_MUTED,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
		Parent = glass,
	})
	ui.text = UIKit.Label({
		Name = "Texto",
		Text = "",
		Font = Theme.TitleFont,
		TextSize = 30,
		TextColor3 = GLASS_TEXT,
		TextStrokeColor3 = Color3.fromRGB(0, 50, 16),
		TextStrokeTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.new(1, 0, 0, 140),
		LayoutOrder = 2,
		Parent = glass,
	})
	UIKit.Create("UITextSizeConstraint", { MaxTextSize = 30, MinTextSize = 14, Parent = ui.text })
	ui.text.TextScaled = true
	ui.footer = UIKit.Label({
		Text = "",
		TextSize = 18,
		TextColor3 = GLASS_MUTED,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 3,
		Parent = glass,
	})
	ui.timer = UIKit.Label({
		Text = "",
		Font = Theme.BoldFont,
		TextSize = 20,
		TextColor3 = Theme.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 4,
		Parent = glass,
	})

	ui.gui = gui
	ui.panel = panel
	ui.scale = scale

	local function updateScale()
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
		scale.Scale = math.clamp(math.min(viewport.X / 1000, viewport.Y / 620), 0.55, 1.1)
	end
	updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
end

local function hide()
	token += 1
	if visible then
		visible = false
		UIKit.Fade(ui.panel, false, 0.4)
	end
end

-- Tambores locais só para quem está longe do tabuleiro (perto, o som 3D do servidor já toca).
local function playDrums()
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local boardFolder = workspace:FindFirstChild("Board")
	local boardModel = boardFolder and boardFolder:FindFirstChildOfClass("Model")
	if root and root:IsA("BasePart") and boardModel then
		if (boardModel:GetPivot().Position - root.Position).Magnitude <= FAR_FROM_BOARD then
			return
		end
	end
	SoundUtil.Play("Drums", { Volume = 0.45 })
end

local function show(payload)
	token += 1
	local myToken = token

	local text = payload.text
	local graphemes = utf8.len(text) or #text
	ui.text.Text = text
	ui.text.MaxVisibleGraphemes = 0

	local dice = {}
	local sum = 0
	for _, value in payload.dice do
		table.insert(dice, tostring(value))
		sum += value
	end
	if #dice > 0 then
		ui.footer.Text = ("Casa %d · Dados: %s = %d"):format(payload.space, table.concat(dice, " + "), sum)
	else
		ui.footer.Text = ("Casa %d"):format(payload.space)
	end

	visible = true
	UIKit.Fade(ui.panel, true, 0.3)
	playDrums()

	local shownAt = os.clock()
	local eventAt = shownAt + payload.countdown

	-- Máquina de escrever (MaxVisibleGraphemes não quebra acentos)
	task.spawn(function()
		local shown = 0
		local step = math.max(1, math.floor(CHARS_PER_SECOND / 30 + 0.5))
		while token == myToken and shown < graphemes do
			task.wait(1 / 30)
			shown = math.min(graphemes, shown + step)
			ui.text.MaxVisibleGraphemes = shown
		end
		if token == myToken then
			ui.text.MaxVisibleGraphemes = -1
		end
	end)

	-- Contagem até o evento e fechamento automático
	task.spawn(function()
		while token == myToken do
			local remaining = math.ceil(eventAt - os.clock())
			if remaining > 0 then
				ui.timer.Text = payload.isFirst and ("A partida começa em %ds"):format(remaining)
					or ("O evento começa em %ds"):format(remaining)
			else
				ui.timer.Text = "Começou!"
			end
			if os.clock() - shownAt >= HIDE_AFTER then
				hide()
				break
			end
			task.wait(0.2)
		end
	end)
end

local function onRiddle(payload)
	if type(payload) ~= "table" or type(payload.text) ~= "string" or payload.text == "" then
		return
	end
	local text = payload.text
	if #text > MAX_TEXT then
		local cut = utf8.offset(text, MAX_TEXT)
		text = cut and text:sub(1, cut - 1) or text:sub(1, MAX_TEXT)
	end
	local dice = {}
	if type(payload.dice) == "table" then
		for index, value in payload.dice do
			if type(index) == "number" and type(value) == "number" and index <= 12 then
				table.insert(dice, math.floor(value))
			end
		end
	end
	show({
		text = text,
		space = type(payload.space) == "number" and math.floor(payload.space) or 0,
		dice = dice,
		countdown = type(payload.countdown) == "number" and math.clamp(payload.countdown, 0, 60) or 5,
		isFirst = payload.isFirst == true,
	})
end

function RiddleUI.Init()
	if initialized then
		return
	end
	initialized = true
	build()
	Net.event(Net.Names.Board_Riddle).OnClientEvent:Connect(onRiddle)
	Net.event(Net.Names.Event_Started).OnClientEvent:Connect(function()
		hide()
	end)
end

return RiddleUI
