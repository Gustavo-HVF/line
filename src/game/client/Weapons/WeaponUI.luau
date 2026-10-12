--!nonstrict
-- Interface das armas: mira (no centro ou seguindo o mouse), marcador de acerto, painel com o nome da
-- arma e a munição/cargas, aviso "Recarregando..." com barra de progresso e a dica do botão de recarga.
-- O painel fica embaixo, no centro, acima da barra de ferramentas do Roblox.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIKit = require(ReplicatedStorage.Shared.UI.UIKit)

local WeaponUI = {}

local Theme = UIKit.Theme

local CROSSHAIR_COLOR = Color3.fromRGB(255, 248, 230)
local HIT_COLOR = Color3.fromRGB(255, 92, 70)
local LOW_COLOR = Color3.fromRGB(255, 120, 90)
local ARM_LENGTH = 10
local ARM_THICKNESS = 2
local HIT_TIME = 0.18

local built = false
local ui: { [string]: any } = {}
local scales: { UIScale } = {}
local hitToken = 0
local reloadTween: Tween? = nil
local reloadActive = false

-- Construção --------------------------------------------------------------------------------------------

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

local function line(parent: Instance, name: string, size: UDim2, color: Color3, rotation: number?): Frame
	local frame = UIKit.Create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Rotation = rotation or 0,
		Parent = parent,
	}) :: Frame
	local stroke = UIKit.Stroke(frame, Color3.new(0, 0, 0), 1)
	stroke.Transparency = 0.45
	return frame
end

local function build()
	local gui = UIKit.ScreenGui("WeaponHUD", 6)
	ui.gui = gui

	-- Mira
	local crosshair = UIKit.Frame({
		Name = "Mira",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(72, 72),
		Visible = false,
		Parent = gui,
	})
	addScale(crosshair)
	line(crosshair, "Ponto", UDim2.fromOffset(4, 4), CROSSHAIR_COLOR)
	ui.arms = {
		top = line(crosshair, "Cima", UDim2.fromOffset(ARM_THICKNESS, ARM_LENGTH), CROSSHAIR_COLOR),
		bottom = line(crosshair, "Baixo", UDim2.fromOffset(ARM_THICKNESS, ARM_LENGTH), CROSSHAIR_COLOR),
		left = line(crosshair, "Esquerda", UDim2.fromOffset(ARM_LENGTH, ARM_THICKNESS), CROSSHAIR_COLOR),
		right = line(crosshair, "Direita", UDim2.fromOffset(ARM_LENGTH, ARM_THICKNESS), CROSSHAIR_COLOR),
	}
	ui.crosshair = crosshair

	-- Marcador de acerto (um "X" em volta da mira)
	local hit = UIKit.Frame({ Name = "Acerto", Size = UDim2.fromScale(1, 1), Visible = false, Parent = crosshair })
	for index, offset in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		local mark = line(hit, "Traco" .. index, UDim2.fromOffset(ARM_THICKNESS + 1, 9), HIT_COLOR)
		mark.Position = UDim2.new(0.5, offset.X * 9, 0.5, offset.Y * 9)
		mark.Rotation = if offset.X * offset.Y > 0 then -45 else 45
	end
	ui.hit = hit

	-- "Recarregando..." logo abaixo da mira
	ui.reloadText = UIKit.Label({
		Name = "Recarregando",
		Text = "Recarregando...",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.fromOffset(200, 24),
		Font = Theme.BoldFont,
		TextSize = 18,
		TextColor3 = Theme.Gold,
		TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = crosshair,
	})

	-- Painel da arma
	local panel = UIKit.Panel({
		Name = "PainelArma",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -84),
		Size = UDim2.fromOffset(240, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = 10,
		BackgroundTransparency = 0.2,
		Visible = false,
		Parent = gui,
	})
	addScale(panel)
	UIKit.ListLayout(panel, 4)
	ui.name = UIKit.Label({
		Name = "Nome",
		Font = Theme.BoldFont,
		TextSize = 18,
		TextColor3 = Theme.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 1,
		Parent = panel,
	})
	ui.count = UIKit.Label({
		Name = "Municao",
		Font = Theme.TitleFont,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 32),
		LayoutOrder = 2,
		Parent = panel,
	})
	local track = UIKit.Create("Frame", {
		Name = "BarraRecarga",
		BackgroundColor3 = Theme.WoodDark,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 6),
		LayoutOrder = 3,
		Visible = false,
		Parent = panel,
	}) :: Frame
	UIKit.Corner(track, UDim.new(1, 0))
	local fill = UIKit.Create("Frame", {
		BackgroundColor3 = Theme.Gold,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = track,
	}) :: Frame
	UIKit.Corner(fill, UDim.new(1, 0))
	ui.reloadTrack = track
	ui.reloadFill = fill
	ui.hint = UIKit.Label({
		Name = "Dica",
		TextSize = 14,
		TextColor3 = Theme.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 4,
		Visible = false,
		Parent = panel,
	})
	ui.panel = panel

	updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
end

local function ensureBuilt()
	if built and ui.gui and ui.gui.Parent then
		return
	end
	built = true
	table.clear(scales)
	build()
end

-- API --------------------------------------------------------------------------------------------------

function WeaponUI.Init()
	ensureBuilt()
end

function WeaponUI.ShowWeapon(name: string)
	ensureBuilt()
	ui.name.Text = name
	ui.panel.Visible = true
end

function WeaponUI.HideWeapon()
	if not built then
		return
	end
	ui.panel.Visible = false
	WeaponUI.SetCrosshairVisible(false)
	WeaponUI.SetReloading(false)
	WeaponUI.SetHint(nil)
end

-- Texto grande do painel ("4 / 6", "3 cargas", "Corpo a corpo"). `low` pinta de vermelho.
function WeaponUI.SetCount(text: string, low: boolean?)
	ensureBuilt()
	ui.count.Text = text
	ui.count.TextColor3 = if low then LOW_COLOR else Theme.Text
	ui.count.TextSize = if #text > 10 then 22 else 30
end

function WeaponUI.SetHint(text: string?)
	ensureBuilt()
	ui.hint.Text = text or ""
	ui.hint.Visible = text ~= nil and text ~= ""
end

-- Mostra/esconde a mira; `gap` é a abertura dos traços (px), maior para a espingarda.
function WeaponUI.SetCrosshairVisible(visible: boolean, gap: number?)
	ensureBuilt()
	ui.crosshair.Visible = visible
	if gap then
		local arms = ui.arms
		arms.top.AnchorPoint = Vector2.new(0.5, 1)
		arms.top.Position = UDim2.new(0.5, 0, 0.5, -gap)
		arms.bottom.AnchorPoint = Vector2.new(0.5, 0)
		arms.bottom.Position = UDim2.new(0.5, 0, 0.5, gap)
		arms.left.AnchorPoint = Vector2.new(1, 0.5)
		arms.left.Position = UDim2.new(0.5, -gap, 0.5, 0)
		arms.right.AnchorPoint = Vector2.new(0, 0.5)
		arms.right.Position = UDim2.new(0.5, gap, 0.5, 0)
	end
end

-- nil = centro da tela; senão, a posição do mouse (coordenadas do viewport).
function WeaponUI.SetCrosshairPosition(position: Vector2?)
	ensureBuilt()
	if position then
		ui.crosshair.Position = UDim2.fromOffset(position.X, position.Y)
	else
		ui.crosshair.Position = UDim2.fromScale(0.5, 0.5)
	end
end

function WeaponUI.Hitmarker()
	ensureBuilt()
	hitToken += 1
	local token = hitToken
	ui.hit.Visible = true
	task.delay(HIT_TIME, function()
		if token == hitToken and ui.hit then
			ui.hit.Visible = false
		end
	end)
end

-- Liga o aviso de recarga com a barra enchendo em `duration` segundos (não reinicia se já estiver ligado).
function WeaponUI.SetReloading(active: boolean, duration: number?)
	if not built then
		return
	end
	if active == reloadActive then
		return
	end
	reloadActive = active
	if reloadTween then
		reloadTween:Cancel()
		reloadTween = nil
	end
	ui.reloadText.Visible = active
	ui.reloadTrack.Visible = active
	ui.reloadFill.Size = UDim2.fromScale(0, 1)
	if active then
		local tween = TweenService:Create(
			ui.reloadFill,
			TweenInfo.new(math.max(duration or 1, 0.05), Enum.EasingStyle.Linear),
			{ Size = UDim2.fromScale(1, 1) }
		)
		reloadTween = tween
		tween:Play()
	end
end

return WeaponUI
