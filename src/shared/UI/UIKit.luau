--!nonstrict
-- Kit de interface com o tema do jogo (selva / madeira / ouro).
-- Toda a UI é criada por código, então todos os menus usam estas funções para ficar consistentes.
--
--   local gui = UIKit.ScreenGui("MainMenu", 10)
--   local panel = UIKit.Panel({ Size = UDim2.fromOffset(400, 300), Position = UDim2.fromScale(0.5, 0.5),
--                               AnchorPoint = Vector2.new(0.5, 0.5), Parent = gui })
--   UIKit.Button({ Text = "Jogar", OnClick = function() end, Parent = panel })

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local SoundUtil = require(script.Parent.Parent.Audio.SoundUtil)

local UIKit = {}

UIKit.Theme = {
	Background = Color3.fromRGB(14, 28, 18),
	Panel = Color3.fromRGB(28, 46, 30),
	PanelLight = Color3.fromRGB(42, 66, 42),
	Wood = Color3.fromRGB(92, 60, 32),
	WoodDark = Color3.fromRGB(58, 36, 18),
	Gold = Color3.fromRGB(222, 180, 70),
	GoldDark = Color3.fromRGB(150, 112, 34),
	Text = Color3.fromRGB(244, 234, 206),
	TextMuted = Color3.fromRGB(176, 170, 146),
	Danger = Color3.fromRGB(196, 58, 46),
	Success = Color3.fromRGB(70, 160, 80),
	Info = Color3.fromRGB(70, 130, 180),
	Warning = Color3.fromRGB(226, 150, 40),
	Overlay = Color3.fromRGB(0, 0, 0),

	TitleFont = Enum.Font.Fondamento,
	BodyFont = Enum.Font.BuilderSans,
	BoldFont = Enum.Font.BuilderSansBold,

	Corner = UDim.new(0, 10),
}

local Theme = UIKit.Theme

local BUTTON_STYLES = {
	primary = { bg = Theme.Gold, hover = Color3.fromRGB(240, 202, 96), text = Theme.WoodDark },
	secondary = { bg = Theme.Wood, hover = Color3.fromRGB(116, 78, 44), text = Theme.Text },
	danger = { bg = Theme.Danger, hover = Color3.fromRGB(220, 80, 66), text = Theme.Text },
	ghost = { bg = Theme.PanelLight, hover = Color3.fromRGB(56, 86, 56), text = Theme.Text },
}

-- Generic -----------------------------------------------------------------------

-- Cria uma instância aplicando propriedades e filhos.
function UIKit.Create(className: string, props: { [string]: any }?, children: { Instance }?): Instance
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				instance[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UIKit.Corner(parent: Instance, radius: UDim?): UICorner
	return UIKit.Create("UICorner", { CornerRadius = radius or Theme.Corner, Parent = parent }) :: UICorner
end

function UIKit.Stroke(parent: Instance, color: Color3?, thickness: number?): UIStroke
	return UIKit.Create("UIStroke", {
		Color = color or Theme.GoldDark,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	}) :: UIStroke
end

function UIKit.Padding(parent: Instance, px: number?): UIPadding
	local p = UDim.new(0, px or 12)
	return UIKit.Create("UIPadding", {
		PaddingTop = p,
		PaddingBottom = p,
		PaddingLeft = p,
		PaddingRight = p,
		Parent = parent,
	}) :: UIPadding
end

-- Layout vertical (ou horizontal) com espaçamento.
function UIKit.ListLayout(parent: Instance, padding: number?, horizontal: boolean?): UIListLayout
	return UIKit.Create("UIListLayout", {
		Padding = UDim.new(0, padding or 8),
		FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = parent,
	}) :: UIListLayout
end

local function applyProps(instance: Instance, props: { [string]: any }?, skip: { [string]: boolean })
	if not props then
		return
	end
	for key, value in props do
		if not skip[key] and key ~= "Parent" then
			instance[key] = value
		end
	end
end

-- Containers ------------------------------------------------------------------------

function UIKit.ScreenGui(name: string, displayOrder: number?): ScreenGui
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	return UIKit.Create("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 0,
		Parent = playerGui,
	}) :: ScreenGui
end

-- Frame transparente (para organizar layout).
function UIKit.Frame(props: { [string]: any }?): Frame
	local frame = UIKit.Create("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}) :: Frame
	applyProps(frame, props, {})
	if props and props.Parent then
		frame.Parent = props.Parent
	end
	return frame
end

-- Painel com fundo, borda dourada e cantos arredondados.
function UIKit.Panel(props: { [string]: any }?): Frame
	local panel = UIKit.Create("Frame", {
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(400, 300),
	}) :: Frame
	UIKit.Corner(panel)
	UIKit.Stroke(panel)
	applyProps(panel, props, { Padding = true })
	if not (props and props.Padding == false) then
		UIKit.Padding(panel, props and props.Padding or 14)
	end
	if props and props.Parent then
		panel.Parent = props.Parent
	end
	return panel
end

-- Lista rolável com layout vertical e canvas automático.
function UIKit.List(props: { [string]: any }?): ScrollingFrame
	local list = UIKit.Create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Gold,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}) :: ScrollingFrame
	applyProps(list, props, { Spacing = true })
	UIKit.ListLayout(list, props and props.Spacing or 8)
	if props and props.Parent then
		list.Parent = props.Parent
	end
	return list
end

-- Texto -----------------------------------------------------------------------------

function UIKit.Label(props: { [string]: any }?): TextLabel
	local label = UIKit.Create("TextLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 24),
		Font = Theme.BodyFont,
		TextColor3 = Theme.Text,
		TextSize = 18,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}) :: TextLabel
	applyProps(label, props, {})
	if props and props.Parent then
		label.Parent = props.Parent
	end
	return label
end

function UIKit.Title(text: string, props: { [string]: any }?): TextLabel
	local merged = {
		Text = text,
		Font = Theme.TitleFont,
		TextSize = 40,
		TextColor3 = Theme.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 48),
		TextStrokeTransparency = 0.6,
	}
	if props then
		for k, v in props do
			merged[k] = v
		end
	end
	return UIKit.Label(merged)
end

-- Botões ----------------------------------------------------------------------------

-- props: Text, OnClick, Style ("primary"|"secondary"|"danger"|"ghost"), mais qualquer propriedade de TextButton.
function UIKit.Button(props: { [string]: any }): TextButton
	local style = BUTTON_STYLES[props.Style or "secondary"] or BUTTON_STYLES.secondary
	local button = UIKit.Create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = style.bg,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 48),
		Font = Theme.BoldFont,
		TextColor3 = style.text,
		TextSize = 22,
		Text = props.Text or "",
	}) :: TextButton
	UIKit.Corner(button, UDim.new(0, 8))
	UIKit.Stroke(button, Theme.WoodDark, 2)
	applyProps(button, props, { Style = true, OnClick = true, Text = true })

	local tweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	button.MouseEnter:Connect(function()
		TweenService:Create(button, tweenInfo, { BackgroundColor3 = style.hover }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, tweenInfo, { BackgroundColor3 = style.bg }):Play()
	end)
	if props.OnClick then
		button.Activated:Connect(function()
			if button:GetAttribute("Disabled") then
				return
			end
			SoundUtil.Play("UIClick", { Volume = 0.4 })
			props.OnClick()
		end)
	end
	if props.Parent then
		button.Parent = props.Parent
	end
	return button
end

-- Ativa/desativa um botão criado por UIKit.Button.
function UIKit.SetButtonEnabled(button: TextButton, enabled: boolean)
	button:SetAttribute("Disabled", not enabled)
	button.AutoButtonColor = false
	button.TextTransparency = enabled and 0 or 0.5
	button.BackgroundTransparency = enabled and 0 or 0.5
end

-- Controles -------------------------------------------------------------------------

export type Control<T> = {
	Instance: Frame,
	Get: () -> T,
	Set: (value: T, silent: boolean?) -> (),
}

local function controlRow(props: { [string]: any }, height: number): (Frame, TextLabel)
	local row = UIKit.Frame({
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = props.LayoutOrder or 0,
		Name = props.Name or props.Text or "Control",
	})
	local label = UIKit.Label({
		Text = props.Text or "",
		Size = UDim2.new(0.45, 0, 1, 0),
		TextSize = 18,
		Parent = row,
	})
	if props.Parent then
		row.Parent = props.Parent
	end
	return row, label
end

-- Interruptor liga/desliga. props: Text, Value, OnChanged(value), Parent, LayoutOrder
function UIKit.Toggle(props: { [string]: any }): Control<boolean>
	local row = controlRow(props, 40)
	local value = props.Value == true

	local track = UIKit.Create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(64, 30),
		BorderSizePixel = 0,
		Parent = row,
	}) :: TextButton
	UIKit.Corner(track, UDim.new(1, 0))
	UIKit.Stroke(track, Theme.WoodDark, 2)
	local knob = UIKit.Create("Frame", {
		Size = UDim2.fromOffset(24, 24),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Theme.Text,
		BorderSizePixel = 0,
		Parent = track,
	}) :: Frame
	UIKit.Corner(knob, UDim.new(1, 0))
	local stateLabel = UIKit.Label({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -74, 0.5, 0),
		Size = UDim2.fromOffset(110, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.TextMuted,
		TextSize = 16,
		Parent = row,
	})

	local function render(animated: boolean)
		local goalPos = value and UDim2.new(1, -27, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
		local goalColor = value and Theme.Success or Theme.WoodDark
		if animated then
			local info = TweenInfo.new(0.15)
			TweenService:Create(knob, info, { Position = goalPos }):Play()
			TweenService:Create(track, info, { BackgroundColor3 = goalColor }):Play()
		else
			knob.Position = goalPos
			track.BackgroundColor3 = goalColor
		end
		stateLabel.Text = value and "Ligado" or "Desligado"
	end
	render(false)

	local control = {} :: any
	control.Instance = row
	function control.Get()
		return value
	end
	function control.Set(newValue: boolean, silent: boolean?)
		value = newValue == true
		render(true)
		if not silent and props.OnChanged then
			props.OnChanged(value)
		end
	end
	track.Activated:Connect(function()
		SoundUtil.Play("UIClick", { Volume = 0.4 })
		control.Set(not value)
	end)
	return control
end

-- Controle deslizante. props: Text, Min, Max, Step, Value, OnChanged(value), Format(value)->string
function UIKit.Slider(props: { [string]: any }): Control<number>
	local row = controlRow(props, 44)
	local min, max = props.Min or 0, props.Max or 1
	local step = props.Step or 0.01
	local value = math.clamp(props.Value or min, min, max)
	local format = props.Format or function(v)
		return tostring(math.floor(v * 100 + 0.5)) .. "%"
	end

	local bar = UIKit.Create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -64, 0.5, 0),
		Size = UDim2.new(0.55, -70, 0, 10),
		BackgroundColor3 = Theme.WoodDark,
		BorderSizePixel = 0,
		Parent = row,
	}) :: TextButton
	UIKit.Corner(bar, UDim.new(1, 0))
	local fill = UIKit.Create("Frame", {
		BackgroundColor3 = Theme.Gold,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = bar,
	}) :: Frame
	UIKit.Corner(fill, UDim.new(1, 0))
	local knob = UIKit.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = Theme.Text,
		BorderSizePixel = 0,
		Parent = bar,
	}) :: Frame
	UIKit.Corner(knob, UDim.new(1, 0))
	UIKit.Stroke(knob, Theme.GoldDark, 2)
	local valueLabel = UIKit.Label({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(56, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 16,
		Parent = row,
	})

	local function render()
		local alpha = (max > min) and (value - min) / (max - min) or 0
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		valueLabel.Text = format(value)
	end
	render()

	local control = {} :: any
	control.Instance = row
	function control.Get()
		return value
	end
	function control.Set(newValue: number, silent: boolean?)
		local snapped = math.floor((math.clamp(newValue, min, max) - min) / step + 0.5) * step + min
		snapped = math.clamp(snapped, min, max)
		if snapped == value and silent then
			render()
			return
		end
		value = snapped
		render()
		if not silent and props.OnChanged then
			props.OnChanged(value)
		end
	end

	local dragging = false
	local function updateFromX(x: number)
		local absPos, absSize = bar.AbsolutePosition.X, bar.AbsoluteSize.X
		if absSize <= 0 then
			return
		end
		local alpha = math.clamp((x - absPos) / absSize, 0, 1)
		control.Set(min + alpha * (max - min))
	end
	bar.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			updateFromX(input.Position.X)
		end
	end)
	local changedConnection = UserInputService.InputChanged:Connect(function(input)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			updateFromX(input.Position.X)
		end
	end)
	local endedConnection = UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)
	-- Conexões globais: desconecta quando o controle for destruído (evita vazamento).
	row.Destroying:Connect(function()
		changedConnection:Disconnect()
		endedConnection:Disconnect()
	end)
	return control
end

-- Escolha entre opções (botões lado a lado).
-- props: Text, Options = { { Value = "high", Label = "Altas" }, ... }, Value, OnChanged(value)
function UIKit.Choice(props: { [string]: any }): Control<any>
	local row = controlRow(props, 40)
	local options = props.Options or {}
	local value = props.Value

	local holder = UIKit.Frame({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0.55, 0, 0, 32),
		Parent = row,
	})
	local layout = UIKit.ListLayout(holder, 4, true)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right

	local buttons = {}
	local control = {} :: any

	local function render()
		for optionValue, button in buttons do
			local selected = optionValue == value
			button.BackgroundColor3 = selected and Theme.Gold or Theme.WoodDark
			button.TextColor3 = selected and Theme.WoodDark or Theme.Text
		end
	end

	local count = math.max(#options, 1)
	for index, option in options do
		local button = UIKit.Create("TextButton", {
			Text = option.Label or tostring(option.Value),
			AutoButtonColor = false,
			Font = Theme.BoldFont,
			TextSize = 15,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Size = UDim2.new(1 / count, -4, 1, 0),
			Parent = holder,
		}) :: TextButton
		UIKit.Corner(button, UDim.new(0, 6))
		buttons[option.Value] = button
		button.Activated:Connect(function()
			SoundUtil.Play("UIClick", { Volume = 0.4 })
			control.Set(option.Value)
		end)
	end

	control.Instance = row
	function control.Get()
		return value
	end
	function control.Set(newValue: any, silent: boolean?)
		value = newValue
		render()
		if not silent and props.OnChanged then
			props.OnChanged(value)
		end
	end
	render()
	return control
end

-- Caixa de texto. props: Placeholder, Text, MaxLength, OnChanged(text)
function UIKit.TextBox(props: { [string]: any }): TextBox
	local box = UIKit.Create("TextBox", {
		BackgroundColor3 = Theme.WoodDark,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 40),
		Font = Theme.BodyFont,
		TextSize = 18,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.TextMuted,
		ClearTextOnFocus = false,
		Text = "",
	}) :: TextBox
	UIKit.Corner(box, UDim.new(0, 8))
	UIKit.Padding(box, 8)
	applyProps(box, props, { MaxLength = true, OnChanged = true })
	if props.MaxLength then
		-- Limita por caracteres (não bytes) para não cortar letras acentuadas no meio.
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local text = box.Text
			local length = utf8.len(text)
			if length and length > props.MaxLength then
				local cut = utf8.offset(text, props.MaxLength + 1)
				if cut then
					box.Text = string.sub(text, 1, cut - 1)
				end
			end
		end)
	end
	if props.OnChanged then
		box.FocusLost:Connect(function()
			props.OnChanged(box.Text)
		end)
	end
	if props.Parent then
		box.Parent = props.Parent
	end
	return box
end

-- Efeitos ---------------------------------------------------------------------------

-- Mostra/esconde um GuiObject com fade (usa CanvasGroup se for um).
function UIKit.Fade(gui: GuiObject, visible: boolean, duration: number?)
	local time = duration or 0.25
	if gui:IsA("CanvasGroup") then
		if visible then
			gui.GroupTransparency = 1
			gui.Visible = true
		end
		local tween = TweenService:Create(gui, TweenInfo.new(time), { GroupTransparency = visible and 0 or 1 })
		tween:Play()
		if not visible then
			tween.Completed:Once(function(state)
				if state == Enum.PlaybackState.Completed then
					gui.Visible = false
				end
			end)
		end
	else
		gui.Visible = visible
	end
end

local toastGui: ScreenGui? = nil
local toastList: Frame? = nil

-- Notificação temporária no topo da tela.
-- kind: "info" | "warning" | "danger" | "success"
function UIKit.Toast(text: string, kind: string?, duration: number?)
	if not toastGui or not toastGui.Parent then
		toastGui = UIKit.ScreenGui("Toasts", 100)
		toastList = UIKit.Frame({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 70),
			Size = UDim2.new(0, 520, 1, -70),
			Parent = toastGui,
		})
		UIKit.ListLayout(toastList :: Frame, 6)
	end
	local colors = {
		info = Theme.Info,
		warning = Theme.Warning,
		danger = Theme.Danger,
		success = Theme.Success,
	}
	local toast = UIKit.Create("CanvasGroup", {
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		GroupTransparency = 1,
		Parent = toastList,
	}) :: CanvasGroup
	UIKit.Corner(toast, UDim.new(0, 8))
	UIKit.Stroke(toast, colors[kind or "info"] or Theme.Info, 2)
	UIKit.Padding(toast, 10)
	UIKit.Label({
		Text = text,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 19,
		Parent = toast,
	})
	TweenService:Create(toast, TweenInfo.new(0.2), { GroupTransparency = 0 }):Play()
	task.delay(duration or 4, function()
		local tween = TweenService:Create(toast, TweenInfo.new(0.4), { GroupTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		toast:Destroy()
	end)
end

return UIKit
