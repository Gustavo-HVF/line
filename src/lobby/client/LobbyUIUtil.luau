--!nonstrict
-- Utilidades de interface do lobby (somente cliente):
--   * AutoScale: UIScale que acompanha o tamanho da tela (fica bom no PC e no celular);
--   * Spinner: anel girando com um dado no meio (sem imagens externas);
--   * Blocker: fundo escuro que bloqueia cliques nos botões de trás;
--   * ícones desenhados só com Frames (dado, pessoas, engrenagem, globo).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UIKit = require(ReplicatedStorage.Shared.UI.UIKit)

local LobbyUIUtil = {}

local Theme = UIKit.Theme

type ScaleEntry = {
	scale: UIScale,
	designWidth: number,
	designHeight: number,
	min: number,
	max: number,
	onChanged: ((number, Vector2) -> ())?,
}

local entries: { ScaleEntry } = {}
local cameraConnection: RBXScriptConnection? = nil
local viewportConnection: RBXScriptConnection? = nil

local function viewportSize(): Vector2
	local camera = workspace.CurrentCamera
	if camera and camera.ViewportSize.X > 1 and camera.ViewportSize.Y > 1 then
		return camera.ViewportSize
	end
	return Vector2.new(1280, 720)
end

local function computeScale(entry: ScaleEntry, viewport: Vector2): number
	return math.clamp(math.min(viewport.Y / entry.designHeight, viewport.X / entry.designWidth), entry.min, entry.max)
end

local function applyEntry(entry: ScaleEntry, viewport: Vector2)
	local value = computeScale(entry, viewport)
	entry.scale.Scale = value
	if entry.onChanged then
		task.spawn(entry.onChanged, value, viewport)
	end
end

local function refreshAll()
	local viewport = viewportSize()
	for index = #entries, 1, -1 do
		local entry = entries[index]
		if entry.scale.Parent == nil then
			table.remove(entries, index)
		else
			applyEntry(entry, viewport)
		end
	end
end

local function watchCamera()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshAll)
	end
end

-- Cria um UIScale em `target` com escala = tamanho da tela / tamanho de projeto (limitada a min..max).
-- onChanged(scale, viewport) é chamado sempre que a escala muda (para ajustar tamanhos que dependem da tela).
function LobbyUIUtil.AutoScale(
	target: GuiObject,
	designWidth: number,
	designHeight: number,
	minScale: number,
	maxScale: number,
	onChanged: ((number, Vector2) -> ())?
): UIScale
	if not cameraConnection then
		cameraConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			watchCamera()
			refreshAll()
		end)
		watchCamera()
	end
	local scale = Instance.new("UIScale")
	scale.Parent = target
	local entry: ScaleEntry = {
		scale = scale,
		designWidth = designWidth,
		designHeight = designHeight,
		min = minScale,
		max = maxScale,
		onChanged = onChanged,
	}
	table.insert(entries, entry)
	applyEntry(entry, viewportSize())
	return scale
end

-- Aparelho de toque sem teclado (celular/tablet).
function LobbyUIUtil.IsTouchOnly(): boolean
	local UserInputService = game:GetService("UserInputService")
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Altura da barra superior do Roblox (botões do menu do Roblox), em pixels.
function LobbyUIUtil.TopInset(): number
	local ok, inset = pcall(function()
		return GuiService.TopbarInset.Height
	end)
	if ok and type(inset) == "number" and inset > 0 then
		return inset
	end
	return 58
end

-- Evita que a interface fique embaixo de entalhes (notch) do celular.
function LobbyUIUtil.UseSafeInsets(gui: ScreenGui)
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
end

-- Fundo que cobre a tela inteira e engole os cliques.
function LobbyUIUtil.Blocker(parent: Instance, transparency: number?): TextButton
	return UIKit.Create("TextButton", {
		Name = "Bloqueio",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundColor3 = Theme.Overlay,
		BackgroundTransparency = transparency or 0.4,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	}) :: TextButton
end

local function circle(props: { [string]: any }): Frame
	local frame = UIKit.Create("Frame", {
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
	}) :: Frame
	for key, value in props do
		if key ~= "Parent" then
			frame[key] = value
		end
	end
	UIKit.Corner(frame, UDim.new(1, 0))
	frame.Parent = props.Parent
	return frame
end

-- Ícones ------------------------------------------------------------------------------------------------
-- Todos recebem um `parent` (normalmente um Frame quadrado transparente), o tamanho em pixels e a cor.

-- Face de dado com três pontos (contorno + pontos, funciona sobre qualquer fundo). Retorna a face.
function LobbyUIUtil.DiceIcon(parent: Instance, size: number, color: Color3): Frame
	local face = UIKit.Create("Frame", {
		Name = "Dado",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size * 0.8, size * 0.8),
		Rotation = -12,
		Parent = parent,
	}) :: Frame
	UIKit.Corner(face, UDim.new(0.24, 0))
	UIKit.Stroke(face, color, math.max(2, size / 13))
	for _, point in { 0.26, 0.5, 0.74 } do
		circle({
			BackgroundColor3 = color,
			Position = UDim2.fromScale(point, point),
			Size = UDim2.fromOffset(size * 0.16, size * 0.16),
			Parent = face,
		})
	end
	return face
end

-- Duas pessoas (a de trás mais clara).
function LobbyUIUtil.PeopleIcon(parent: Instance, size: number, color: Color3)
	local function person(x: number, scale: number, transparency: number)
		local head = size * 0.3 * scale
		circle({
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(x, 0, 0, size * (0.06 + (1 - scale) * 0.3)),
			Size = UDim2.fromOffset(head, head),
			Parent = parent,
		})
		local body = UIKit.Create("Frame", {
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(x, 0, 0, size * 0.96),
			Size = UDim2.fromOffset(size * 0.56 * scale, size * 0.4 * scale),
			Parent = parent,
		})
		UIKit.Corner(body, UDim.new(0.5, 0))
	end
	person(0.66, 0.82, 0.4)
	person(0.4, 1, 0)
end

-- Engrenagem: anel com dentes (o miolo fica vazado).
function LobbyUIUtil.GearIcon(parent: Instance, size: number, color: Color3)
	local teeth = 8
	for index = 0, teeth - 1 do
		local angle = index / teeth * math.pi * 2
		local radius = size * 0.36
		UIKit.Create("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(angle) * radius, 0.5, math.sin(angle) * radius),
			Size = UDim2.fromOffset(size * 0.2, size * 0.2),
			Rotation = math.deg(angle),
			Parent = parent,
		})
	end
	local ring = circle({
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size * 0.58, size * 0.58),
		Parent = parent,
	})
	UIKit.Stroke(ring, color, math.max(2, size * 0.14))
end

-- Globo (sala pública).
function LobbyUIUtil.GlobeIcon(parent: Instance, size: number, color: Color3)
	local thickness = math.max(1, size / 10)
	local outline = circle({
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size * 0.8, size * 0.8),
		Parent = parent,
	})
	UIKit.Stroke(outline, color, thickness)
	local meridian = circle({
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size * 0.34, size * 0.8),
		Parent = parent,
	})
	UIKit.Stroke(meridian, color, thickness)
	UIKit.Create("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size * 0.8, thickness),
		Parent = parent,
	})
end

-- Spinner ------------------------------------------------------------------------------------------------

export type Spinner = {
	Instance: Frame,
	SetActive: (active: boolean) -> (),
}

-- Anel dourado girando com um dado balançando no meio. Só anima enquanto ativo.
function LobbyUIUtil.Spinner(parent: Instance, size: number, layoutOrder: number?): Spinner
	local holder = UIKit.Frame({
		Name = "Spinner",
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = layoutOrder or 0,
		Parent = parent,
	})
	local ring = circle({
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size - 8, size - 8),
		Parent = holder,
	})
	local stroke = UIKit.Stroke(ring, Theme.Gold, math.max(3, size / 14))
	local gradient = UIKit.Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.45, 0.1),
			NumberSequenceKeypoint.new(0.55, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = stroke,
	}) :: UIGradient
	local dieHolder = UIKit.Frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size * 0.42, size * 0.42),
		Parent = holder,
	})
	local face = LobbyUIUtil.DiceIcon(dieHolder, size * 0.42, Theme.Gold)

	local connection: RBXScriptConnection? = nil
	local spinner = {} :: any
	spinner.Instance = holder
	function spinner.SetActive(active: boolean)
		if active and not connection then
			connection = RunService.RenderStepped:Connect(function(dt)
				gradient.Rotation = (gradient.Rotation + dt * 320) % 360
				face.Rotation = -12 + math.sin(os.clock() * 3) * 18
			end)
		elseif not active and connection then
			connection:Disconnect()
			connection = nil
		end
	end
	holder.Destroying:Connect(function()
		spinner.SetActive(false)
	end)
	return spinner
end

return LobbyUIUtil
