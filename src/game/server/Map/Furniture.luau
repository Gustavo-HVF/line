--!nonstrict
-- Biblioteca de móveis e objetos feitos de parts.
-- Convenção: `cf` é o centro da base do objeto no piso; a FRENTE do objeto aponta para o -Z local
-- e as costas (lado que encosta na parede) ficam no +Z local.
-- Móveis grandes recebem a tag Destructible; objetos pequenos são LooseProp (a part raiz fica ancorada
-- e as demais partes ficam soldadas nela, para o objeto inteiro voar junto quando um evento o soltar).

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)

local Furniture = {}

local M = Enum.Material
local D = Kit.D
local L = Kit.L
local GHOST = { Ghost = true }
local GHOST_NO_SHADOW = { Ghost = true, NoShadow = true }

local VERTICAL = CFrame.Angles(0, 0, math.rad(90))

-- Bloco com deslocamento local (x, y, z) a partir de `cf`.
local function B(ctx, parent, name, cf, x, y, z, sx, sy, sz, color, material, tags, extra): BasePart
	return Kit.box(ctx, parent, name, cf * CFrame.new(x, y, z), Vector3.new(sx, sy, sz), color, material, tags, extra)
end

-- Cilindro em pé com deslocamento local.
local function C(ctx, parent, name, cf, x, y, z, height, diameter, color, material, tags, extra): BasePart
	return Kit.cylinderAlong(
		ctx,
		parent,
		name,
		cf * CFrame.new(x, y, z) * VERTICAL,
		height,
		diameter,
		color,
		material,
		tags,
		extra
	)
end

Furniture.B = B
Furniture.C = C

-- Mesas e assentos -------------------------------------------------------------------

-- Mesa com tampo e dois cavaletes. Retorna o tampo.
function Furniture.Table(
	ctx,
	parent,
	cf: CFrame,
	w: number,
	d: number,
	h: number,
	color: Color3,
	material: Enum.Material?
)
	local mat = material or M.Wood
	local top = B(ctx, parent, "Tampo", cf, 0, h - 0.3, 0, w, 0.6, d, color, mat, D)
	local inset = math.min(1.2, w * 0.15)
	for _, side in { -1, 1 } do
		B(ctx, parent, "Cavalete", cf, side * (w / 2 - inset), (h - 0.6) / 2, 0, 0.7, h - 0.6, d * 0.7, color, mat, D)
	end
	return top
end

-- Mesinha redonda solta (LooseProp).
function Furniture.SideTable(ctx, parent, cf: CFrame, diameter: number, h: number, color: Color3)
	local top = C(ctx, parent, "Mesinha", cf, 0, h - 0.15, 0, 0.3, diameter, color, M.Wood, L)
	local leg = C(ctx, parent, "Pe", cf, 0, (h - 0.3) / 2, 0, h - 0.3, 0.6, color, M.Wood)
	Kit.weldTo(top, { leg })
	return top
end

-- Cadeira (LooseProp): assento, encosto e duas laterais.
function Furniture.Chair(ctx, parent, cf: CFrame, color: Color3, seatColor: Color3?)
	local seat = B(ctx, parent, "Cadeira", cf, 0, 1.8, 0, 2, 0.35, 2, seatColor or color, M.Fabric, L)
	local back = B(ctx, parent, "Encosto", cf, 0, 3.25, 0.85, 2, 2.6, 0.3, color, M.Wood)
	local left = B(ctx, parent, "Lateral", cf, -0.85, 0.82, 0, 0.25, 1.65, 1.8, color, M.Wood)
	local right = B(ctx, parent, "Lateral", cf, 0.85, 0.82, 0, 0.25, 1.65, 1.8, color, M.Wood)
	Kit.weldTo(seat, { back, left, right })
	return seat
end

-- Banquinho redondo (LooseProp).
function Furniture.Stool(ctx, parent, cf: CFrame, color: Color3, height: number?)
	local h = height or 2.2
	local seat = C(ctx, parent, "Banquinho", cf, 0, h - 0.2, 0, 0.4, 1.6, color, M.Wood, L)
	local leg = C(ctx, parent, "Pe", cf, 0, (h - 0.4) / 2, 0, h - 0.4, 0.5, Palette.Iron, M.Metal)
	Kit.weldTo(seat, { leg })
	return seat
end

-- Poltrona (LooseProp).
function Furniture.Armchair(ctx, parent, cf: CFrame, color: Color3)
	local base = B(ctx, parent, "Poltrona", cf, 0, 0.9, 0, 3, 1.8, 3, color, M.Fabric, L)
	local back = B(ctx, parent, "Encosto", cf, 0, 2.9, 1.15, 3, 2.4, 0.7, color, M.Fabric)
	local left = B(ctx, parent, "Braco", cf, -1.3, 2.1, 0, 0.5, 0.8, 3, color, M.Fabric)
	local right = B(ctx, parent, "Braco", cf, 1.3, 2.1, 0, 0.5, 0.8, 3, color, M.Fabric)
	Kit.weldTo(base, { back, left, right })
	return base
end

-- Sofá grande (Destructible).
function Furniture.Sofa(ctx, parent, cf: CFrame, w: number, color: Color3)
	B(ctx, parent, "Sofa", cf, 0, 0.9, 0, w, 1.8, 3.2, color, M.Fabric, D)
	B(ctx, parent, "Encosto", cf, 0, 2.8, 1.2, w, 2.4, 0.8, color, M.Fabric, D)
	B(ctx, parent, "Braco", cf, -(w / 2 - 0.45), 2.05, -0.1, 0.9, 0.9, 3, color, M.Fabric, D)
	B(ctx, parent, "Braco", cf, w / 2 - 0.45, 2.05, -0.1, 0.9, 0.9, 3, color, M.Fabric, D)
end

-- Banco comprido (Destructible).
function Furniture.Bench(ctx, parent, cf: CFrame, w: number, color: Color3, material: Enum.Material?)
	local mat = material or M.Wood
	B(ctx, parent, "Banco", cf, 0, 1.75, 0, w, 0.5, 1.8, color, mat, D)
	B(ctx, parent, "Pe", cf, -(w / 2 - 0.6), 0.75, 0, 0.6, 1.5, 1.5, color, mat, D)
	B(ctx, parent, "Pe", cf, w / 2 - 0.6, 0.75, 0, 0.6, 1.5, 1.5, color, mat, D)
end

-- Quarto ---------------------------------------------------------------------------

-- Cama com cabeceira no +Z (encostada na parede).
function Furniture.Bed(ctx, parent, cf: CFrame, w: number, l: number, frameColor: Color3, sheetColor: Color3)
	B(ctx, parent, "Cama", cf, 0, 0.65, 0, w, 1.3, l, frameColor, M.Wood, D)
	B(ctx, parent, "Colchao", cf, 0, 1.7, 0, w - 0.4, 0.8, l - 0.4, Palette.White, M.Fabric, D)
	B(ctx, parent, "Coberta", cf, 0, 2.15, -l * 0.15, w - 0.1, 0.25, l * 0.62, sheetColor, M.Fabric, nil, GHOST)
	B(ctx, parent, "Travesseiro", cf, 0, 2.3, l / 2 - 1.2, w - 1.4, 0.5, 1.2, Palette.White, M.Fabric, nil, GHOST)
	B(ctx, parent, "Cabeceira", cf, 0, 2.5, l / 2 - 0.3, w + 0.2, 5, 0.6, frameColor, M.Wood, D)
	B(ctx, parent, "Peseira", cf, 0, 1.4, -l / 2 + 0.25, w + 0.2, 2.8, 0.5, frameColor, M.Wood, D)
end

-- Criado-mudo com abajur aceso opcional (LooseProp).
function Furniture.Nightstand(ctx, parent, cf: CFrame, color: Color3, withLamp: boolean?, lit: boolean?)
	local body = B(ctx, parent, "CriadoMudo", cf, 0, 1.25, 0, 2, 2.5, 1.8, color, M.Wood, L)
	if withLamp then
		local base = C(ctx, parent, "Abajur", cf, 0, 2.9, 0, 0.8, 0.6, Palette.Brass, M.Metal)
		local shade = C(ctx, parent, "Cupula", cf, 0, 3.75, 0, 0.9, 1.3, Palette.Parchment, M.Fabric)
		Kit.weldTo(body, { base, shade })
		if lit then
			Kit.light(shade, Palette.LightWarm, 12, 0.8)
		end
	end
	return body
end

-- Guarda-roupa alto (Destructible).
function Furniture.Wardrobe(ctx, parent, cf: CFrame, w: number, h: number, color: Color3)
	B(ctx, parent, "GuardaRoupa", cf, 0, h / 2, 0, w, h, 2.2, color, M.Wood, D)
	B(ctx, parent, "Fresta", cf, 0, h / 2, -1.11, 0.12, h - 1, 0.05, Palette.WoodDark, M.Wood, nil, GHOST_NO_SHADOW)
	B(ctx, parent, "Puxador", cf, -0.4, h / 2, -1.15, 0.2, 0.8, 0.12, Palette.Brass, M.Metal, nil, GHOST_NO_SHADOW)
	B(ctx, parent, "Puxador", cf, 0.4, h / 2, -1.15, 0.2, 0.8, 0.12, Palette.Brass, M.Metal, nil, GHOST_NO_SHADOW)
end

-- Cômoda com espelho (Destructible).
function Furniture.Dresser(ctx, parent, cf: CFrame, w: number, color: Color3)
	B(ctx, parent, "Comoda", cf, 0, 1.5, 0, w, 3, 1.8, color, M.Wood, D)
	B(ctx, parent, "Gavetas", cf, 0, 1.5, -0.91, w - 0.6, 0.12, 0.05, Palette.WoodDark, M.Wood, nil, GHOST_NO_SHADOW)
	B(ctx, parent, "Espelho", cf, 0, 5, 0.7, w * 0.6, 3.6, 0.2, Palette.Glass, M.Glass, nil, { Reflectance = 0.5 })
end

-- Estantes ---------------------------------------------------------------------------

-- Estante com 4 níveis. `fill`: "books" (padrão), "jars", "bottles", "scrolls", "fabric", "boxes", "empty".
function Furniture.Bookshelf(
	ctx,
	parent,
	cf: CFrame,
	w: number,
	h: number,
	depth: number,
	rng: Random,
	fill: string?,
	color: Color3?
)
	local wood = color or Palette.WoodDark
	B(ctx, parent, "Estante", cf, 0, h / 2, depth / 2 - 0.15, w, h, 0.3, wood, M.Wood, D)
	B(ctx, parent, "Lateral", cf, -(w / 2 - 0.2), h / 2, 0, 0.4, h, depth, wood, M.Wood, D)
	B(ctx, parent, "Lateral", cf, w / 2 - 0.2, h / 2, 0, 0.4, h, depth, wood, M.Wood, D)
	B(ctx, parent, "Topo", cf, 0, h - 0.2, 0, w, 0.4, depth, wood, M.Wood, D)
	local levels = 4
	local levelHeight = (h - 0.4) / levels
	local innerWidth = w - 0.8
	local kind = fill or "books"
	for level = 0, levels - 1 do
		local y0 = level * levelHeight
		B(ctx, parent, "Prateleira", cf, 0, y0 + 0.15, 0, w - 0.4, 0.3, depth, wood, M.Wood)
		local itemHeight = math.min(levelHeight - 0.7, 2.6)
		if kind == "books" then
			-- Dois blocos de livros por nível, com cores e alturas diferentes.
			local split = rng:NextNumber(0.35, 0.65)
			local leftWidth = innerWidth * split - 0.1
			local rightWidth = innerWidth * (1 - split) - 0.1
			local leftHeight = itemHeight * rng:NextNumber(0.75, 1)
			local rightHeight = itemHeight * rng:NextNumber(0.7, 1)
			B(
				ctx,
				parent,
				"Livros",
				cf,
				-innerWidth / 2 + leftWidth / 2,
				y0 + 0.3 + leftHeight / 2,
				0.05,
				leftWidth,
				leftHeight,
				depth - 0.5,
				Palette.pick(Palette.Books, rng),
				M.Fabric
			)
			if rng:NextNumber() < 0.85 then
				B(
					ctx,
					parent,
					"Livros",
					cf,
					innerWidth / 2 - rightWidth / 2,
					y0 + 0.3 + rightHeight / 2,
					0.05,
					rightWidth,
					rightHeight,
					depth - 0.5,
					Palette.pick(Palette.Books, rng),
					M.Fabric
				)
			end
		elseif kind == "jars" or kind == "bottles" then
			local count = 3
			for i = 1, count do
				local x = -innerWidth / 2 + (i - 0.5) * innerWidth / count
				local isJar = kind == "jars"
				C(
					ctx,
					parent,
					isJar and "Pote" or "Garrafa",
					cf,
					x,
					y0 + 0.3 + (isJar and 0.8 or 1),
					0,
					isJar and 1.6 or 2,
					isJar and 1.1 or 0.6,
					isJar and Palette.pick(Palette.Fabrics, rng) or Color3.fromRGB(40, 80, 40),
					M.Glass,
					L,
					{ Transparency = 0.15 }
				)
			end
		elseif kind == "scrolls" then
			Kit.cylinderAlong(
				ctx,
				parent,
				"Pergaminhos",
				cf * CFrame.new(0, y0 + 0.75, 0),
				innerWidth - 0.2,
				0.9,
				Palette.Parchment,
				M.Fabric
			)
		elseif kind == "fabric" then
			for i = 1, 2 do
				local x = (i == 1 and -1 or 1) * innerWidth / 4
				Kit.cylinderAlong(
					ctx,
					parent,
					"RoloDeTecido",
					cf * CFrame.new(x, y0 + 0.85, 0) * CFrame.Angles(0, math.rad(90), 0),
					depth - 0.4,
					1.1,
					Palette.pick(Palette.Fabrics, rng),
					M.Fabric,
					L
				)
			end
		elseif kind == "boxes" then
			local boxWidth = innerWidth / 2 - 0.2
			B(
				ctx,
				parent,
				"Caixa",
				cf,
				-innerWidth / 4,
				y0 + 0.3 + itemHeight * 0.4,
				0,
				boxWidth,
				itemHeight * 0.8,
				depth - 0.4,
				Palette.WoodLight,
				M.Cardboard,
				L
			)
		end
	end
end

-- Decoração ---------------------------------------------------------------------------

-- Tapete (sem colisão). borderColor opcional cria a faixa da borda.
function Furniture.Rug(ctx, parent, cf: CFrame, w: number, d: number, color: Color3, borderColor: Color3?)
	if borderColor then
		B(ctx, parent, "Tapete", cf, 0, 0.05, 0, w, 0.1, d, borderColor, M.Fabric, nil, GHOST_NO_SHADOW)
		B(ctx, parent, "Tapete", cf, 0, 0.07, 0, w - 1.4, 0.1, d - 1.4, color, M.Fabric, nil, GHOST_NO_SHADOW)
	else
		B(ctx, parent, "Tapete", cf, 0, 0.05, 0, w, 0.1, d, color, M.Fabric, nil, GHOST_NO_SHADOW)
	end
end

-- Lustre pendurado no teto. `ceiling` é o ponto do teto. Retorna a luz (range <= 0 = lustre apagado, sem luz).
function Furniture.Chandelier(
	ctx,
	parent,
	ceiling: Vector3,
	drop: number,
	diameter: number,
	range: number,
	shadows: boolean?,
	brightness: number?
): PointLight?
	local frame = CFrame.new(ceiling)
	C(ctx, parent, "Corrente", frame, 0, -drop / 2, 0, drop, 0.2, Palette.Iron, M.Metal, nil, GHOST_NO_SHADOW)
	C(ctx, parent, "Lustre", frame, 0, -drop, 0, 0.5, diameter, Palette.Gold, M.Metal, nil, GHOST_NO_SHADOW)
	local glow = Kit.ball(
		ctx,
		parent,
		"Brilho",
		ceiling - Vector3.new(0, drop - 0.6, 0),
		math.max(diameter * 0.35, 0.8),
		Palette.LightWarm,
		M.Neon,
		nil,
		GHOST_NO_SHADOW
	)
	if range <= 0 then
		return nil
	end
	return Kit.light(glow, Palette.LightWarm, range, brightness or 1.2, shadows)
end

-- Abajur de pé (LooseProp).
function Furniture.FloorLamp(ctx, parent, cf: CFrame, lit: boolean?)
	local base = C(ctx, parent, "Luminaria", cf, 0, 0.15, 0, 0.3, 1.4, Palette.Brass, M.Metal, L)
	local pole = C(ctx, parent, "Haste", cf, 0, 3, 0, 5.4, 0.25, Palette.Brass, M.Metal)
	local shade = C(ctx, parent, "Cupula", cf, 0, 6, 0, 1.3, 1.8, Palette.Parchment, M.Fabric)
	Kit.weldTo(base, { pole, shade })
	if lit then
		Kit.light(shade, Palette.LightWarm, 14, 0.9)
	end
	return base
end

-- Quadro na parede. `cf` fica na superfície da parede, com a frente para o -Z.
function Furniture.Painting(ctx, parent, cf: CFrame, w: number, h: number, rng: Random, frameColor: Color3?)
	B(ctx, parent, "Quadro", cf, 0, 0, -0.1, w, h, 0.2, frameColor or Palette.Gold, M.Wood, nil, GHOST_NO_SHADOW)
	local canvas = Palette.pick(Palette.Canvas, rng)
	B(ctx, parent, "Tela", cf, 0, 0, -0.22, w - 0.6, h - 0.6, 0.06, canvas, M.Fabric, nil, GHOST_NO_SHADOW)
	local motif = rng:NextInteger(1, 3)
	if motif == 1 then
		-- Paisagem: faixa de terra/mar na metade de baixo.
		B(
			ctx,
			parent,
			"Paisagem",
			cf,
			0,
			-(h - 0.6) / 4,
			-0.26,
			w - 0.6,
			(h - 0.6) / 2,
			0.04,
			Palette.pick(Palette.Canvas, rng),
			M.Fabric,
			nil,
			GHOST_NO_SHADOW
		)
	elseif motif == 2 then
		-- Retrato: silhueta oval.
		Kit.cylinderAlong(
			ctx,
			parent,
			"Retrato",
			cf * CFrame.new(0, 0, -0.27) * CFrame.Angles(0, math.rad(90), 0),
			0.04,
			math.min(w, h) * 0.55,
			Palette.pick(Palette.Canvas, rng),
			M.Fabric,
			nil,
			GHOST_NO_SHADOW
		)
	end
end

-- Lareira encostada na parede (+Z). `wallHeight` define a altura da coifa de tijolos.
function Furniture.Fireplace(ctx, parent, cf: CFrame, w: number, wallHeight: number, lit: boolean?, light: boolean?)
	local stone = Palette.Stone
	B(ctx, parent, "Lareira", cf, -(w / 2 - 0.7), 2.5, 0.2, 1.4, 5, 2, stone, M.Marble, D)
	B(ctx, parent, "Lareira", cf, w / 2 - 0.7, 2.5, 0.2, 1.4, 5, 2, stone, M.Marble, D)
	B(ctx, parent, "Cornija", cf, 0, 5.4, 0.1, w + 0.6, 0.8, 2.4, Palette.Marble, M.Marble, D)
	B(ctx, parent, "Fornalha", cf, 0, 2.2, 0.8, w - 2.8, 4.4, 0.6, Palette.Black, M.Slate)
	B(
		ctx,
		parent,
		"Base",
		cf,
		0,
		0.15,
		-0.6,
		w + 1.6,
		0.3,
		2.2,
		Palette.StoneDark,
		M.Slate,
		nil,
		{ CanCollide = false }
	)
	if wallHeight > 7 then
		B(
			ctx,
			parent,
			"Chamine",
			cf,
			0,
			5.8 + (wallHeight - 5.8) / 2,
			0.6,
			w - 1,
			wallHeight - 5.8,
			1.2,
			Palette.Brick,
			M.Brick,
			D
		)
	end
	if lit then
		local fire =
			B(ctx, parent, "Fogo", cf, 0, 0.9, 0.4, w - 3.6, 1.2, 0.8, Palette.Flame, M.Neon, nil, GHOST_NO_SHADOW)
		if light ~= false then
			Kit.light(fire, Palette.Flame, 16, 1.4)
		end
	end
end

-- Relógio de pêndulo (Destructible).
function Furniture.Clock(ctx, parent, cf: CFrame)
	B(ctx, parent, "Relogio", cf, 0, 3.6, 0, 2, 7.2, 1.4, Palette.WoodRed, M.Wood, D)
	Kit.cylinderAlong(
		ctx,
		parent,
		"Mostrador",
		cf * CFrame.new(0, 5.9, -0.71) * CFrame.Angles(0, math.rad(90), 0),
		0.1,
		1.5,
		Palette.Parchment,
		M.SmoothPlastic,
		nil,
		GHOST_NO_SHADOW
	)
	B(ctx, parent, "Pendulo", cf, 0, 2.6, -0.71, 0.8, 2.6, 0.08, Palette.Gold, M.Metal, nil, GHOST_NO_SHADOW)
end

-- Busto sobre pedestal.
function Furniture.Statue(ctx, parent, cf: CFrame, color: Color3?)
	local marble = color or Palette.Marble
	B(ctx, parent, "Pedestal", cf, 0, 1.75, 0, 2, 3.5, 2, Palette.StoneDark, M.Marble, D)
	B(ctx, parent, "Busto", cf, 0, 4.4, 0, 1.8, 1.8, 1.1, marble, M.Marble)
	Kit.ball(ctx, parent, "Cabeca", (cf * CFrame.new(0, 5.9, 0)).Position, 1.3, marble, M.Marble)
end

-- Vitrine com um objeto dentro.
function Furniture.DisplayCase(ctx, parent, cf: CFrame, rng: Random)
	B(ctx, parent, "Vitrine", cf, 0, 1.6, 0, 3, 3.2, 3, Palette.WoodDark, M.Wood, D)
	B(ctx, parent, "Vidro", cf, 0, 4.6, 0, 2.8, 2.8, 2.8, Palette.Glass, M.Glass, D, { Transparency = 0.6 })
	local kind = rng:NextInteger(1, 3)
	if kind == 1 then
		Kit.ball(ctx, parent, "Idolo", (cf * CFrame.new(0, 4.2, 0)).Position, 1.4, Palette.Gold, M.Metal, nil, GHOST)
	elseif kind == 2 then
		B(ctx, parent, "Mascara", cf, 0, 4.4, 0, 1.4, 1.8, 0.4, Palette.WoodRed, M.Wood, nil, GHOST)
	else
		C(ctx, parent, "Vaso", cf, 0, 4.3, 0, 1.6, 1.1, Palette.Terracotta, M.Slate, nil, GHOST)
	end
end

-- Máscara tribal na parede (`cf` na superfície da parede, frente para o -Z).
function Furniture.Mask(ctx, parent, cf: CFrame, rng: Random)
	local color = Palette.pick({ Palette.WoodRed, Palette.Wood, Palette.WoodLight }, rng)
	B(ctx, parent, "Mascara", cf, 0, 0, -0.25, 1.8, 2.6, 0.5, color, M.Wood, nil, GHOST_NO_SHADOW)
	B(ctx, parent, "Olho", cf, -0.45, 0.4, -0.52, 0.4, 0.3, 0.06, Palette.Black, M.SmoothPlastic, nil, GHOST_NO_SHADOW)
	B(ctx, parent, "Olho", cf, 0.45, 0.4, -0.52, 0.4, 0.3, 0.06, Palette.Black, M.SmoothPlastic, nil, GHOST_NO_SHADOW)
	B(ctx, parent, "Boca", cf, 0, -0.65, -0.52, 0.9, 0.25, 0.06, Palette.Black, M.SmoothPlastic, nil, GHOST_NO_SHADOW)
end

-- Cabeça de animal empalhada (troféu de caça), presa na parede.
function Furniture.TrophyHead(ctx, parent, cf: CFrame, rng: Random)
	B(ctx, parent, "Placa", cf, 0, 0, -0.15, 2.2, 2.8, 0.3, Palette.WoodDark, M.Wood, nil, GHOST_NO_SHADOW)
	local fur =
		Palette.pick({ Color3.fromRGB(150, 110, 60), Color3.fromRGB(110, 80, 50), Color3.fromRGB(70, 60, 54) }, rng)
	B(ctx, parent, "Cabeca", cf, 0, 0, -1.2, 1.5, 1.6, 1.9, fur, M.Fabric, nil, GHOST)
	B(ctx, parent, "Focinho", cf, 0, -0.35, -2.4, 0.9, 0.9, 0.8, fur, M.Fabric, nil, GHOST)
	for _, side in { -1, 1 } do
		Kit.box(
			ctx,
			parent,
			"Chifre",
			cf * CFrame.new(side * 0.8, 1.2, -1.2) * CFrame.Angles(0, 0, side * -0.5),
			Vector3.new(0.3, 1.6, 0.3),
			Palette.Parchment,
			M.SmoothPlastic,
			nil,
			GHOST_NO_SHADOW
		)
	end
end

-- Vaso de planta (LooseProp).
function Furniture.PottedPlant(ctx, parent, cf: CFrame, size: number, rng: Random)
	local pot = C(ctx, parent, "Vaso", cf, 0, size * 0.3, 0, size * 0.6, size * 0.55, Palette.Terracotta, M.Slate, L)
	local foliage = Kit.ball(
		ctx,
		parent,
		"Folhagem",
		(cf * CFrame.new(0, size * 0.9, 0)).Position,
		size * 0.9,
		Palette.pick(Palette.Leaves, rng),
		M.LeafyGrass
	)
	Kit.weldTo(pot, { foliage })
	return pot
end

-- Vaso decorativo (LooseProp), opcionalmente com flores.
function Furniture.Vase(ctx, parent, cf: CFrame, h: number, color: Color3, rng: Random?)
	local vase = C(ctx, parent, "Vaso", cf, 0, h / 2, 0, h, h * 0.45, color, M.Marble, L)
	if rng then
		local flowers = Kit.ball(
			ctx,
			parent,
			"Flores",
			(cf * CFrame.new(0, h + 0.3, 0)).Position,
			h * 0.55,
			Palette.pick(Palette.Flowers, rng),
			M.Fabric
		)
		Kit.weldTo(vase, { flowers })
	end
	return vase
end

-- Livro solto (LooseProp).
function Furniture.Book(ctx, parent, cf: CFrame, rng: Random)
	return B(ctx, parent, "Livro", cf, 0, 0.2, 0, 1.4, 0.4, 1.9, Palette.pick(Palette.Books, rng), M.Fabric, L)
end

-- Garrafa (LooseProp).
function Furniture.Bottle(ctx, parent, cf: CFrame, color: Color3?)
	return C(
		ctx,
		parent,
		"Garrafa",
		cf,
		0,
		0.75,
		0,
		1.5,
		0.5,
		color or Color3.fromRGB(40, 80, 40),
		M.Glass,
		L,
		{ Transparency = 0.2 }
	)
end

-- Castiçal com vela acesa (sem luz própria).
function Furniture.Candle(ctx, parent, cf: CFrame)
	local base = C(ctx, parent, "Castical", cf, 0, 0.25, 0, 0.5, 0.8, Palette.Brass, M.Metal, L)
	local candle = C(ctx, parent, "Vela", cf, 0, 1, 0, 1, 0.35, Palette.White, M.SmoothPlastic)
	local flame = Kit.ball(
		ctx,
		parent,
		"Chama",
		(cf * CFrame.new(0, 1.65, 0)).Position,
		0.3,
		Palette.Flame,
		M.Neon,
		nil,
		GHOST_NO_SHADOW
	)
	Kit.weldTo(base, { candle, flame })
	return base
end

-- Caixote (LooseProp).
function Furniture.Crate(ctx, parent, cf: CFrame, size: Vector3, color: Color3?)
	return Kit.box(
		ctx,
		parent,
		"Caixote",
		cf * CFrame.new(0, size.Y / 2, 0),
		size,
		color or Palette.WoodLight,
		M.WoodPlanks,
		L
	)
end

-- Baú (LooseProp).
function Furniture.Chest(ctx, parent, cf: CFrame, color: Color3?)
	local wood = color or Palette.Wood
	local body = B(ctx, parent, "Bau", cf, 0, 0.9, 0, 3.2, 1.8, 2, wood, M.WoodPlanks, L)
	local lid = B(ctx, parent, "Tampa", cf, 0, 2, 0, 3.3, 0.4, 2.1, wood, M.Wood)
	local band =
		B(ctx, parent, "Faixa", cf, 0, 1.1, -1.02, 0.5, 2.1, 0.06, Palette.Brass, M.Metal, nil, GHOST_NO_SHADOW)
	Kit.weldTo(body, { lid, band })
	return body
end

-- Barril de pé ou deitado (LooseProp).
function Furniture.Barrel(ctx, parent, cf: CFrame, h: number, diameter: number, lying: boolean?)
	local axis
	if lying then
		axis = cf * CFrame.new(0, diameter / 2, 0)
	else
		axis = cf * CFrame.new(0, h / 2, 0) * VERTICAL
	end
	local body = Kit.cylinderAlong(ctx, parent, "Barril", axis, h, diameter, Palette.Wood, M.WoodPlanks, L)
	local ringA = Kit.cylinderAlong(
		ctx,
		parent,
		"Aro",
		axis * CFrame.new(h * 0.3, 0, 0),
		0.3,
		diameter + 0.1,
		Palette.Iron,
		M.Metal
	)
	local ringB = Kit.cylinderAlong(
		ctx,
		parent,
		"Aro",
		axis * CFrame.new(-h * 0.3, 0, 0),
		0.3,
		diameter + 0.1,
		Palette.Iron,
		M.Metal
	)
	Kit.weldTo(body, { ringA, ringB })
	return body
end

-- Saco de mantimentos (LooseProp).
function Furniture.Sack(ctx, parent, cf: CFrame, rng: Random)
	return Kit.box(
		ctx,
		parent,
		"Saco",
		cf * CFrame.new(0, 1, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi), rng:NextNumber(-0.15, 0.15)),
		Vector3.new(1.8, 2, 1.4),
		Palette.vary(Palette.Parchment, rng),
		M.Fabric,
		L
	)
end

-- Tambor decorativo (LooseProp).
function Furniture.Drum(ctx, parent, cf: CFrame, diameter: number, h: number, color: Color3?)
	local body = C(ctx, parent, "Tambor", cf, 0, h / 2, 0, h, diameter, color or Palette.WoodRed, M.Wood, L)
	local head = C(ctx, parent, "Pele", cf, 0, h + 0.05, 0, 0.12, diameter - 0.1, Palette.Parchment, M.Leather)
	local band = C(ctx, parent, "Faixa", cf, 0, h * 0.65, 0, 0.4, diameter + 0.08, Palette.Parchment, M.Fabric)
	Kit.weldTo(body, { head, band })
	return body
end

-- Ambientes específicos ---------------------------------------------------------------

-- Piano de cauda (Destructible), teclado na frente (-Z).
function Furniture.GrandPiano(ctx, parent, cf: CFrame)
	local black = Palette.Black
	B(ctx, parent, "Piano", cf, 0, 2.8, 0.6, 5, 1.3, 6.4, black, M.SmoothPlastic, D, { Reflectance = 0.15 })
	Kit.box(
		ctx,
		parent,
		"Tampa",
		cf * CFrame.new(2.45, 3.45, 0.6) * CFrame.Angles(0, 0, math.rad(-35)) * CFrame.new(-2.5, 0, 0),
		Vector3.new(5, 0.15, 6.2),
		black,
		M.SmoothPlastic,
		nil,
		GHOST
	)
	B(ctx, parent, "Teclado", cf, 0, 2.95, -2.95, 4.8, 0.3, 1.1, Palette.White, M.SmoothPlastic)
	B(ctx, parent, "Teclas", cf, 0, 3.12, -2.75, 4.6, 0.12, 0.5, black, M.SmoothPlastic, nil, GHOST_NO_SHADOW)
	for _, offset in { Vector3.new(-2, 0, -2), Vector3.new(2, 0, -2), Vector3.new(0, 0, 3.2) } do
		B(ctx, parent, "Pe", cf, offset.X, 1.1, offset.Z, 0.6, 2.2, 0.6, black, M.SmoothPlastic)
	end
	B(ctx, parent, "BancoPiano", cf, 0, 1.6, -4.6, 2.6, 0.5, 1.2, black, M.Leather, L)
end

-- Mesa de bilhar com bolas e tacos soltos.
function Furniture.BilliardTable(ctx, parent, cf: CFrame, rng: Random)
	B(ctx, parent, "MesaDeBilhar", cf, 0, 2.5, 0, 9, 0.7, 5, Palette.WoodRed, M.Wood, D)
	B(ctx, parent, "Feltro", cf, 0, 2.53, 0, 8.2, 0.7, 4.2, Palette.Felt, M.Fabric, D)
	for _, x in { -3.6, 3.6 } do
		for _, z in { -1.8, 1.8 } do
			B(ctx, parent, "Pe", cf, x, 1.08, z, 0.9, 2.15, 0.9, Palette.WoodRed, M.Wood)
		end
	end
	local colors = { Palette.White, Color3.fromRGB(220, 40, 40), Color3.fromRGB(240, 200, 40), Palette.Black }
	for i, color in colors do
		Kit.ball(
			ctx,
			parent,
			"Bola",
			(cf * CFrame.new(-2 + i * 0.9 + rng:NextNumber(-0.3, 0.3), 3.15, rng:NextNumber(-1.2, 1.2))).Position,
			0.5,
			color,
			M.SmoothPlastic,
			L
		)
	end
	Kit.cylinderAlong(
		ctx,
		parent,
		"Taco",
		cf * CFrame.new(0.5, 3.1, 1) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0),
		6,
		0.25,
		Palette.WoodLight,
		M.Wood,
		L
	)
end

-- Banheira (Destructible) com água rasa.
function Furniture.Bathtub(ctx, parent, cf: CFrame)
	B(ctx, parent, "Banheira", cf, 0, 1.1, 0, 6, 2.2, 3, Palette.White, M.Marble, D)
	B(
		ctx,
		parent,
		"Agua",
		cf,
		0,
		2.21,
		0,
		5.2,
		0.05,
		2.2,
		Color3.fromRGB(120, 170, 200),
		M.SmoothPlastic,
		nil,
		{ Ghost = true, Transparency = 0.3 }
	)
	C(ctx, parent, "Torneira", cf, 0, 2.6, 1.2, 0.8, 0.3, Palette.Brass, M.Metal, nil, GHOST_NO_SHADOW)
end

-- Vaso sanitário.
function Furniture.Toilet(ctx, parent, cf: CFrame)
	B(ctx, parent, "Sanitario", cf, 0, 0.7, -0.2, 1.4, 1.4, 1.8, Palette.White, M.Marble, D)
	B(ctx, parent, "Caixa", cf, 0, 1.9, 0.75, 1.6, 1.8, 0.6, Palette.White, M.Marble, D)
	B(ctx, parent, "Assento", cf, 0, 1.45, -0.2, 1.3, 0.12, 1.6, Palette.WoodLight, M.Wood, nil, GHOST_NO_SHADOW)
end

-- Pia com espelho opcional (`mirrorHeight` = altura do centro do espelho).
function Furniture.Sink(ctx, parent, cf: CFrame, mirrorHeight: number?)
	B(ctx, parent, "Coluna", cf, 0, 1.3, 0.2, 0.9, 2.6, 0.9, Palette.White, M.Marble, D)
	B(ctx, parent, "Pia", cf, 0, 2.85, 0, 2.2, 0.6, 1.6, Palette.White, M.Marble, D)
	if mirrorHeight then
		B(
			ctx,
			parent,
			"Espelho",
			cf,
			0,
			mirrorHeight,
			0.85,
			2.2,
			2.8,
			0.15,
			Palette.Glass,
			M.Glass,
			nil,
			{ Ghost = true, Reflectance = 0.6 }
		)
	end
end

-- Balcão de cozinha (Destructible).
function Furniture.Counter(ctx, parent, cf: CFrame, w: number, color: Color3?, topColor: Color3?)
	B(ctx, parent, "Balcao", cf, 0, 1.5, 0, w, 3, 2.2, color or Palette.WoodLight, M.WoodPlanks, D)
	B(ctx, parent, "Tampo", cf, 0, 3.15, -0.05, w + 0.1, 0.3, 2.4, topColor or Palette.Marble, M.Marble, D)
end

-- Fogão a lenha de ferro (Destructible).
function Furniture.Stove(ctx, parent, cf: CFrame, wallHeight: number)
	B(ctx, parent, "Fogao", cf, 0, 1.6, 0, 4, 3.2, 2.4, Palette.Iron, M.Metal, D)
	B(ctx, parent, "Chapa", cf, 0, 3.25, 0, 4.1, 0.1, 2.5, Palette.Black, M.Metal, nil, GHOST_NO_SHADOW)
	B(ctx, parent, "Portinhola", cf, 0, 1.3, -1.21, 1.6, 1.1, 0.05, Palette.Flame, M.Neon, nil, GHOST_NO_SHADOW)
	C(ctx, parent, "Chamine", cf, 0, 3.2 + (wallHeight - 3.2) / 2, 0.7, wallHeight - 3.2, 0.9, Palette.Iron, M.Metal)
	C(ctx, parent, "Panela", cf, -1, 3.8, -0.2, 1, 1.3, Palette.Steel, M.Metal, L)
end

-- Geladeira antiga.
function Furniture.Icebox(ctx, parent, cf: CFrame)
	B(ctx, parent, "Geladeira", cf, 0, 3, 0, 3, 6, 2.4, Palette.WoodLight, M.Wood, D)
	B(ctx, parent, "Puxador", cf, 1, 3.6, -1.25, 0.25, 1.4, 0.12, Palette.Brass, M.Metal, nil, GHOST_NO_SHADOW)
end

-- Escrivaninha com papéis (Destructible).
function Furniture.Desk(ctx, parent, cf: CFrame, color: Color3, rng: Random)
	B(ctx, parent, "Escrivaninha", cf, 0, 2.9, 0, 5.4, 0.4, 2.6, color, M.Wood, D)
	B(ctx, parent, "Gaveteiro", cf, -1.8, 1.35, 0, 1.6, 2.7, 2.4, color, M.Wood, D)
	B(ctx, parent, "Gaveteiro", cf, 1.8, 1.35, 0, 1.6, 2.7, 2.4, color, M.Wood, D)
	B(ctx, parent, "Papeis", cf, rng:NextNumber(-1, 1), 3.13, 0, 1.4, 0.06, 1.8, Palette.White, M.SmoothPlastic, L)
end

-- Globo terrestre de chão (LooseProp).
function Furniture.Globe(ctx, parent, cf: CFrame, diameter: number)
	local stand = C(ctx, parent, "Globo", cf, 0, 1.2, 0, 2.4, 1, Palette.WoodDark, M.Wood, L)
	local ball = Kit.ball(
		ctx,
		parent,
		"Esfera",
		(cf * CFrame.new(0, 2.4 + diameter / 2, 0)).Position,
		diameter,
		Color3.fromRGB(70, 110, 140),
		M.SmoothPlastic
	)
	Kit.weldTo(stand, { ball })
	return stand
end

-- Telescópio de latão num tripé (LooseProp), apontado para a frente (-Z).
function Furniture.Telescope(ctx, parent, cf: CFrame)
	local hub = B(ctx, parent, "Telescopio", cf, 0, 4.4, 0, 0.6, 0.6, 0.6, Palette.Brass, M.Metal, L)
	local parts = {}
	for i = 0, 2 do
		local angle = i * math.pi * 2 / 3
		table.insert(
			parts,
			Kit.box(
				ctx,
				parent,
				"Tripe",
				cf * CFrame.Angles(0, angle, 0) * CFrame.new(0, 2.2, -0.75) * CFrame.Angles(math.rad(19), 0, 0),
				Vector3.new(0.25, 4.6, 0.25),
				Palette.WoodDark,
				M.Wood
			)
		)
	end
	table.insert(
		parts,
		Kit.cylinderAlong(
			ctx,
			parent,
			"Tubo",
			cf * CFrame.new(0, 5.2, -0.6) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(35)),
			5,
			0.8,
			Palette.Brass,
			M.Metal
		)
	)
	Kit.weldTo(hub, parts)
	return hub
end

-- Cavalete de pintura com tela (LooseProp).
function Furniture.Easel(ctx, parent, cf: CFrame, rng: Random)
	local canvas = Kit.box(
		ctx,
		parent,
		"Tela",
		cf * CFrame.new(0, 4.4, 0.1) * CFrame.Angles(math.rad(10), 0, 0),
		Vector3.new(3.4, 3, 0.2),
		Palette.pick(Palette.Canvas, rng),
		M.Fabric,
		L
	)
	local parts = {}
	for _, side in { -1, 1 } do
		table.insert(
			parts,
			Kit.box(
				ctx,
				parent,
				"Perna",
				cf * CFrame.new(side * 1.1, 2.6, 0.3) * CFrame.Angles(math.rad(10), 0, side * math.rad(6)),
				Vector3.new(0.2, 5.4, 0.2),
				Palette.WoodLight,
				M.Wood
			)
		)
	end
	table.insert(
		parts,
		Kit.box(
			ctx,
			parent,
			"Perna",
			cf * CFrame.new(0, 2.5, 1.2) * CFrame.Angles(math.rad(-20), 0, 0),
			Vector3.new(0.2, 5.2, 0.2),
			Palette.WoodLight,
			M.Wood
		)
	)
	table.insert(parts, B(ctx, parent, "Apoio", cf, 0, 2.85, 0.05, 3, 0.25, 0.5, Palette.WoodLight, M.Wood))
	Kit.weldTo(canvas, parts)
	return canvas
end

-- Manequim de costura (LooseProp).
function Furniture.Mannequin(ctx, parent, cf: CFrame, color: Color3)
	local base = C(ctx, parent, "Manequim", cf, 0, 0.15, 0, 0.3, 1.6, Palette.WoodDark, M.Wood, L)
	local pole = C(ctx, parent, "Haste", cf, 0, 1.6, 0, 2.8, 0.3, Palette.WoodDark, M.Wood)
	local torso = B(ctx, parent, "Torso", cf, 0, 4, 0, 1.8, 2.4, 1.1, color, M.Fabric)
	Kit.weldTo(base, { pole, torso })
	return base
end

-- Cavalinho de balanço (LooseProp).
function Furniture.RockingHorse(ctx, parent, cf: CFrame, color: Color3)
	local body = B(ctx, parent, "Cavalinho", cf, 0, 2, 0, 1, 1.2, 3, color, M.Wood, L)
	local head = Kit.box(
		ctx,
		parent,
		"Cabeca",
		cf * CFrame.new(0, 3, -1.4) * CFrame.Angles(math.rad(-25), 0, 0),
		Vector3.new(0.8, 1.8, 0.9),
		color,
		M.Wood
	)
	local rockers = {}
	for _, side in { -0.45, 0.45 } do
		table.insert(rockers, B(ctx, parent, "Balanco", cf, side, 0.5, 0, 0.2, 0.4, 3.8, Palette.WoodDark, M.Wood))
		table.insert(rockers, B(ctx, parent, "Perna", cf, side, 1.05, 0, 0.25, 0.9, 1.6, color, M.Wood))
	end
	table.insert(rockers, head)
	Kit.weldTo(body, rockers)
	return body
end

-- Gramofone (LooseProp).
function Furniture.Gramophone(ctx, parent, cf: CFrame)
	local box = B(ctx, parent, "Gramofone", cf, 0, 0.6, 0, 1.8, 1.2, 1.8, Palette.WoodRed, M.Wood, L)
	local horn = Kit.cylinderAlong(
		ctx,
		parent,
		"Corneta",
		cf * CFrame.new(0, 2.1, -0.4) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(40)),
		2,
		1.6,
		Palette.Brass,
		M.Metal
	)
	Kit.weldTo(box, { horn })
	return box
end

-- Estante de partitura (LooseProp).
function Furniture.MusicStand(ctx, parent, cf: CFrame)
	local base = C(ctx, parent, "Estante", cf, 0, 0.1, 0, 0.2, 1.2, Palette.Iron, M.Metal, L)
	local pole = C(ctx, parent, "Haste", cf, 0, 2, 0, 3.8, 0.15, Palette.Iron, M.Metal)
	local plate = Kit.box(
		ctx,
		parent,
		"Partitura",
		cf * CFrame.new(0, 4.1, 0) * CFrame.Angles(math.rad(-20), 0, 0),
		Vector3.new(2, 1.5, 0.1),
		Palette.Parchment,
		M.SmoothPlastic
	)
	Kit.weldTo(base, { pole, plate })
	return base
end

-- Varal com roupas (sem colisão nas roupas).
function Furniture.ClothesLine(ctx, parent, cf: CFrame, length: number, rng: Random)
	for _, side in { -1, 1 } do
		B(ctx, parent, "Poste", cf, side * length / 2, 3.2, 0, 0.3, 6.4, 0.3, Palette.WoodDark, M.Wood)
	end
	Kit.cylinderAlong(
		ctx,
		parent,
		"Varal",
		cf * CFrame.new(0, 6.1, 0),
		length,
		0.1,
		Palette.Parchment,
		M.Fabric,
		nil,
		GHOST_NO_SHADOW
	)
	local count = math.max(2, math.floor(length / 3))
	for i = 1, count do
		local x = -length / 2 + (i - 0.5) * (length / count)
		B(
			ctx,
			parent,
			"Roupa",
			cf,
			x,
			4.9,
			0,
			1.8,
			2.3,
			0.1,
			Palette.pick(Palette.Sheets, rng),
			M.Fabric,
			nil,
			GHOST_NO_SHADOW
		)
	end
end

-- Tina de lavar roupa com água.
function Furniture.Washtub(ctx, parent, cf: CFrame)
	local tub = C(ctx, parent, "Tina", cf, 0, 1.1, 0, 2.2, 3, Palette.Steel, M.Metal, L)
	local water = C(
		ctx,
		parent,
		"Agua",
		cf,
		0,
		2.1,
		0,
		0.1,
		2.7,
		Color3.fromRGB(150, 180, 200),
		M.SmoothPlastic,
		nil,
		{ Transparency = 0.3 }
	)
	Kit.weldTo(tub, { water })
	water.CanCollide = false
	water.CanQuery = false
	water.CanTouch = false
	return tub
end

-- Móvel coberto por lençol (sótão).
function Furniture.Covered(ctx, parent, cf: CFrame, size: Vector3, rng: Random)
	return Kit.box(
		ctx,
		parent,
		"MovelCoberto",
		cf * CFrame.new(0, size.Y / 2, 0) * CFrame.Angles(0, rng:NextNumber(-0.1, 0.1), 0),
		size,
		Palette.vary(Palette.White, rng, 0.06),
		M.Fabric,
		D
	)
end

-- Planetário mecânico (decoração de mesa).
function Furniture.Orrery(ctx, parent, cf: CFrame)
	local sun = Kit.ball(ctx, parent, "Planetario", (cf * CFrame.new(0, 1.4, 0)).Position, 1, Palette.Gold, M.Metal, L)
	local rod = C(ctx, parent, "Haste", cf, 0, 0.7, 0, 1.4, 0.2, Palette.Brass, M.Metal)
	local arm = Kit.cylinderAlong(ctx, parent, "Braco", cf * CFrame.new(1.1, 1.4, 0), 2.2, 0.1, Palette.Brass, M.Metal)
	local planet = Kit.ball(
		ctx,
		parent,
		"Planeta",
		(cf * CFrame.new(2.2, 1.4, 0)).Position,
		0.5,
		Palette.Canvas[1],
		M.SmoothPlastic
	)
	Kit.weldTo(sun, { rod, arm, planet })
	return sun
end

-- Máquina de costura sobre a mesa (LooseProp).
function Furniture.SewingMachine(ctx, parent, cf: CFrame)
	local body = B(ctx, parent, "MaquinaDeCostura", cf, 0, 0.45, 0, 1.8, 0.9, 0.9, Palette.Black, M.Metal, L)
	local arm = B(ctx, parent, "Braco", cf, -0.5, 1.2, 0, 0.5, 0.8, 0.6, Palette.Black, M.Metal)
	local head = B(ctx, parent, "Cabecote", cf, 0.1, 1.45, 0, 1.6, 0.4, 0.6, Palette.Black, M.Metal)
	Kit.weldTo(body, { arm, head })
	return body
end

-- Lança/rifle pendurados (decoração da sala de troféus), `cf` na superfície da parede.
function Furniture.WallWeapons(ctx, parent, cf: CFrame)
	for _, side in { -1, 1 } do
		Kit.box(
			ctx,
			parent,
			"Lanca",
			cf * CFrame.new(0, 0, -0.2) * CFrame.Angles(0, 0, side * math.rad(35)),
			Vector3.new(0.25, 6, 0.25),
			Palette.WoodLight,
			M.Wood,
			nil,
			GHOST_NO_SHADOW
		)
	end
	B(ctx, parent, "Escudo", cf, 0, 0, -0.35, 1.6, 2.4, 0.3, Palette.WoodRed, M.Leather, nil, GHOST_NO_SHADOW)
end

-- Tapete de pele listrada.
function Furniture.SkinRug(ctx, parent, cf: CFrame)
	local orange = Color3.fromRGB(196, 120, 50)
	B(ctx, parent, "TapeteDePele", cf, 0, 0.06, 0, 4.5, 0.1, 7, orange, M.Fabric, nil, GHOST_NO_SHADOW)
	for i = -2, 2 do
		B(ctx, parent, "Listra", cf, 0, 0.12, i * 1.2, 4.2, 0.04, 0.35, Palette.Black, M.Fabric, nil, GHOST_NO_SHADOW)
	end
end

return Furniture
