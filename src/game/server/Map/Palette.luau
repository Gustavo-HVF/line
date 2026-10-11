--!nonstrict
-- Paleta de cores e materiais do mapa. Ajuste o visual da ilha, da mansão e dos jardins aqui.

local Palette = {}

local rgb = Color3.fromRGB

-- Ilha e mar -------------------------------------------------------------------
Palette.Grass = rgb(84, 124, 52)
Palette.GrassDark = rgb(62, 98, 40)
Palette.Sand = rgb(224, 202, 150)
Palette.SandWet = rgb(196, 172, 122)
Palette.Seabed = rgb(150, 138, 100)
Palette.DeepSea = rgb(12, 46, 64)
Palette.Water = rgb(34, 112, 150)
Palette.Rocks = { rgb(110, 106, 98), rgb(92, 90, 86), rgb(128, 120, 106), rgb(78, 76, 74) }

-- Vegetação --------------------------------------------------------------------
Palette.Leaves = { rgb(56, 108, 44), rgb(44, 92, 38), rgb(72, 126, 52), rgb(38, 80, 34), rgb(86, 132, 58) }
Palette.Hedge = { rgb(38, 82, 38), rgb(34, 74, 34), rgb(44, 90, 42), rgb(40, 78, 36) }
Palette.PalmLeaf = { rgb(70, 130, 50), rgb(60, 116, 44), rgb(82, 140, 58) }
Palette.Trunk = rgb(92, 66, 44)
Palette.PalmTrunk = rgb(140, 112, 78)
Palette.Vine = rgb(48, 98, 40)
Palette.Flowers = { rgb(214, 52, 66), rgb(242, 196, 60), rgb(232, 120, 170), rgb(250, 250, 240), rgb(230, 110, 40) }
Palette.Coconut = rgb(96, 70, 40)
Palette.Soil = rgb(78, 56, 38)

-- Mansão -----------------------------------------------------------------------
Palette.Brick = rgb(122, 62, 46)
Palette.BrickDark = rgb(96, 50, 38)
Palette.Trim = rgb(232, 224, 204)
Palette.Stone = rgb(150, 146, 136)
Palette.StoneDark = rgb(112, 108, 100)
Palette.Roof = rgb(56, 60, 68)
Palette.Plaster = rgb(214, 198, 166)
Palette.PlasterUpper = rgb(200, 186, 160)
Palette.Glass = rgb(176, 210, 220)
Palette.WoodDark = rgb(70, 44, 26)
Palette.Wood = rgb(112, 74, 42)
Palette.WoodLight = rgb(160, 118, 74)
Palette.WoodRed = rgb(120, 52, 36)
Palette.FloorWood = rgb(120, 82, 50)
Palette.FloorWoodLight = rgb(150, 108, 66)
Palette.Marble = rgb(228, 224, 214)
Palette.MarbleDark = rgb(70, 66, 64)
Palette.Tiles = rgb(206, 204, 196)
Palette.TilesBlue = rgb(150, 176, 190)
Palette.Gold = rgb(204, 164, 66)
Palette.Brass = rgb(176, 136, 62)
Palette.Iron = rgb(42, 42, 46)
Palette.Steel = rgb(120, 124, 130)
Palette.White = rgb(240, 238, 230)
Palette.Black = rgb(24, 22, 22)
Palette.Felt = rgb(30, 96, 54)
Palette.Leather = rgb(96, 58, 34)
Palette.Parchment = rgb(222, 204, 160)
Palette.Fabrics = {
	rgb(140, 36, 40),
	rgb(46, 74, 120),
	rgb(56, 98, 60),
	rgb(150, 110, 50),
	rgb(104, 58, 110),
	rgb(170, 150, 120),
}
Palette.Sheets = { rgb(236, 232, 218), rgb(214, 222, 236), rgb(236, 220, 214) }
Palette.Books = {
	rgb(128, 34, 30),
	rgb(36, 60, 104),
	rgb(40, 84, 52),
	rgb(122, 92, 40),
	rgb(70, 40, 72),
	rgb(150, 132, 100),
	rgb(30, 30, 34),
}
Palette.Canvas = {
	rgb(70, 110, 140),
	rgb(150, 120, 70),
	rgb(60, 100, 60),
	rgb(130, 60, 50),
	rgb(200, 170, 120),
	rgb(40, 50, 80),
}
Palette.Toys = { rgb(220, 60, 50), rgb(60, 120, 220), rgb(250, 200, 50), rgb(70, 170, 80) }

-- Estufa e exterior --------------------------------------------------------------
Palette.GreenhouseFrame = rgb(34, 70, 46)
Palette.GreenhouseGlass = rgb(196, 226, 214)
Palette.Path = rgb(128, 124, 116)
Palette.PathDark = rgb(108, 104, 98)
Palette.Terracotta = rgb(176, 96, 60)
Palette.Flame = rgb(255, 150, 50)
Palette.LightWarm = rgb(255, 200, 140)
Palette.LightCool = rgb(220, 236, 255)

-- Escolhe um item aleatório de uma lista.
function Palette.pick(list: { any }, rng: Random): any
	return list[rng:NextInteger(1, #list)]
end

-- Variação leve de uma cor (amount em 0..1 de brilho).
function Palette.vary(color: Color3, rng: Random, amount: number?): Color3
	local a = amount or 0.08
	local factor = 1 + rng:NextNumber(-a, a)
	return Color3.new(
		math.clamp(color.R * factor, 0, 1),
		math.clamp(color.G * factor, 0, 1),
		math.clamp(color.B * factor, 0, 1)
	)
end

return Palette
