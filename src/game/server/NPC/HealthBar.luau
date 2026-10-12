--!nonstrict
-- Barra de vida dos NPCs: BillboardGui criado no servidor (replica para todos) com o nome do inimigo e a
-- barra colorida. Só muda propriedades quando a vida muda de verdade (pouca rede).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = require(ReplicatedStorage.Shared.UI.UIKit)

local HealthBar = {}
HealthBar.__index = HealthBar

local Theme = UIKit.Theme

local HIGH = Color3.fromRGB(86, 186, 74)
local MID = Color3.fromRGB(230, 186, 52)
local LOW = Color3.fromRGB(214, 62, 48)

local function colorFor(ratio: number): Color3
	if ratio >= 0.5 then
		return MID:Lerp(HIGH, (ratio - 0.5) * 2)
	end
	return LOW:Lerp(MID, ratio * 2)
end

export type HealthBar = {
	gui: BillboardGui,
	fill: Frame,
	ratio: number,
	Set: (self: any, health: number, maxHealth: number) -> (),
	Destroy: (self: any) -> (),
}

-- Cria a barra presa em `adornee`, `heightOffset` studs acima do centro dela.
function HealthBar.new(
	adornee: BasePart,
	displayName: string,
	heightOffset: number,
	maxDistance: number,
	boss: boolean?
): HealthBar
	local width = if boss then 170 else 116
	local barHeight = if boss then 10 else 8
	local gui = UIKit.Create("BillboardGui", {
		Name = "BarraDeVida",
		Adornee = adornee,
		Size = UDim2.fromOffset(width, barHeight + 20),
		StudsOffsetWorldSpace = Vector3.new(0, heightOffset, 0),
		AlwaysOnTop = false,
		LightInfluence = 0,
		MaxDistance = maxDistance,
		ClipsDescendants = false,
	}) :: BillboardGui

	UIKit.Create("TextLabel", {
		Name = "Nome",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 0),
		Font = Theme.BoldFont,
		Text = displayName,
		TextColor3 = if boss then Theme.Gold else Theme.Text,
		TextSize = if boss then 17 else 14,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.35,
		Parent = gui,
	})

	local back = UIKit.Create("Frame", {
		Name = "Fundo",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, -8, 0, barHeight),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Parent = gui,
	}) :: Frame
	UIKit.Corner(back, UDim.new(0, 4))
	UIKit.Stroke(back, if boss then Theme.Gold else Theme.WoodDark, 1)

	local fill = UIKit.Create("Frame", {
		Name = "Vida",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = HIGH,
		BorderSizePixel = 0,
		Parent = back,
	}) :: Frame
	UIKit.Corner(fill, UDim.new(0, 4))

	gui.Parent = adornee
	local self = setmetatable({ gui = gui, fill = fill, ratio = 1 }, HealthBar)
	return self :: any
end

function HealthBar:Set(health: number, maxHealth: number)
	local ratio = math.clamp((tonumber(health) or 0) / math.max(tonumber(maxHealth) or 1, 1), 0, 1)
	-- Arredonda para 1% para não replicar mudanças invisíveis.
	ratio = math.floor(ratio * 100 + 0.5) / 100
	if ratio == self.ratio then
		return
	end
	self.ratio = ratio
	self.fill.Size = UDim2.fromScale(ratio, 1)
	self.fill.BackgroundColor3 = colorFor(ratio)
	self.fill.Visible = ratio > 0
end

function HealthBar:Destroy()
	if self.gui then
		self.gui:Destroy()
	end
end

return HealthBar
