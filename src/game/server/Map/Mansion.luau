--!nonstrict
-- Mansão de 2 andares (pé-direito 16) com 30 cômodos (15 por andar), dois corredores por andar,
-- escadaria principal no hall, escada de serviço nos fundos, biblioteca de pé-direito duplo com mezanino
-- e telhado de duas águas.
--
-- Planta (vista de cima, +Z = frente/fachada principal, +X = leste), células de 28 x 28:
--   Faixa F  (frente)   : 7 colunas de cômodos
--   Faixa C1 (corredor) : corredor principal (12 de largura)
--   Faixa M  (meio)     : 7 colunas de cômodos (a Sala de Jogos fica no centro)
--   Faixa C2 (corredor) : corredor dos fundos
--   Faixa B  (fundos)   : 7 colunas de cômodos
-- A estrutura (paredes, lajes, escadas, telhado) fica num Model que nunca é escondido;
-- os móveis de cada cômodo ficam em Models próprios com a tag CullChunk.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local Plants = require(script.Parent.Plants)
local Rooms = require(script.Parent.Rooms)
local StartRoom = require(script.Parent.StartRoom)

local Mansion = {}

local M = Enum.Material
local D = Kit.D
local I = Kit.I
local GHOST = { Ghost = true }

-- Dimensões ------------------------------------------------------------------------

local CENTER = GameConfig.MANSION_CENTER
local CX, CZ = CENTER.X, CENTER.Z
local CELL = 28
local COLS = 7
local STORY = 16
local SLAB = 1
local T_IN = 1
local T_EXT = 1.5
local HALF_W = COLS * CELL / 2 -- 98
local HALF_D = 54
local FLOOR = { [0] = GameConfig.GROUND_Y + 0.2, [1] = GameConfig.GROUND_Y + 0.2 + STORY }
local CEILING_TOP = FLOOR[1] + STORY -- topo da laje do teto
local ROOF_RISE = 22
local WALL_IN_HEIGHT = STORY - SLAB -- paredes internas vão do piso até a laje de cima
local STAIR_STEPS = 20 -- degraus de 0,8 stud de altura (jogadores e pathfinding sobem sem pular)

Mansion.Floor = FLOOR
Mansion.CeilingTop = CEILING_TOP

-- Faixas no eixo Z (relativas ao centro da mansão).
local BANDS = {
	F = { z0 = 26, z1 = 54 },
	C1 = { z0 = 14, z1 = 26 },
	M = { z0 = -14, z1 = 14 },
	C2 = { z0 = -26, z1 = -14 },
	B = { z0 = -54, z1 = -26 },
}
local BAND_ORDER = { "F", "C1", "M", "C2", "B" }
local ROOM_ROWS = { "F", "M", "B" }

-- Cômodos de cada célula. "@X" = vão (pé-direito duplo do cômodo X, sem laje).
local GRID = {
	[0] = {
		F = { "JardimInverno", "Musica", "Estar", "Hall", "Biblioteca", "Biblioteca", "Escritorio" },
		M = { "Adega", "Trofeus", "Bilhar", "Jogos", "Jantar", "Jantar", "Despensa" },
		B = { "Baile", "Baile", "Baile", "EscadaFundos", "Cozinha", "Cozinha", "Lavanderia" },
	},
	[1] = {
		F = { "Observatorio", "Pintura", "Costura", "@Hall", "@Biblioteca", "@Biblioteca", "Mapas" },
		M = { "Banheiro1", "Hospedes1", "Hospedes2", "Galeria", "Criancas", "Banheiro2", "Hospedes3" },
		B = { "QuartoPrincipal", "QuartoPrincipal", "Banheiro3", "@EscadaFundos", "Hospedes4", "Sotao", "Sotao" },
	},
}

-- Cômodos com pé-direito duplo (ocupam os dois andares).
local DOUBLE_HEIGHT = { Hall = true, Biblioteca = true, EscadaFundos = true }

-- Paredes paralelas ao eixo X (entre faixas). Uma especificação por coluna.
-- Strings: "wall" | "door" | "start" (porta da sala inicial). Tabelas: { kind, from, to, offset, height }
-- com posições relativas ao centro da célula. Uma lista de especificações cria várias aberturas na mesma célula.
local X_LINES = {
	{
		z = 26,
		specs = {
			[0] = { "door", "door", "door", { kind = "open", from = -5.5, to = 14 }, "door", "door", "door" },
			[1] = { "door", "door", "door", { kind = "railing", from = -5.5, to = 14 }, "door", "wall", "door" },
		},
	},
	{
		z = 14,
		specs = {
			[0] = { "door", "door", "door", "start", "door", "door", "door" },
			[1] = { "door", "door", "door", "door", "door", "door", "door" },
		},
	},
	{
		z = -14,
		specs = {
			[0] = { "door", "door", "door", "start", "door", "door", "door" },
			[1] = { "wall", "door", "door", "door", "door", "wall", "door" },
		},
	},
	{
		z = -26,
		specs = {
			[0] = { "door", "wall", "door", { kind = "door", offset = 6 }, "door", "wall", "door" },
			[1] = {
				"door",
				"wall",
				"door",
				-- Saída da escada dos fundos e a porta do patamar (logo acima da porta do térreo).
				{ { kind = "door", from = -13.5, to = -5.5, height = 10 }, { kind = "door", offset = 6 } },
				"door",
				"wall",
				"door",
			},
		},
	},
}

-- Paredes paralelas ao eixo Z (entre colunas), por faixa de cômodos. Índice k = parede entre a coluna k e k+1.
-- "none" = mesmo cômodo dos dois lados; "seal" = parede da sala inicial.
local Z_LINES = {
	-- Sem porta entre a Sala de Estar e o Hall: a escadaria principal encosta nessa parede.
	F = {
		[0] = { "door", "door", "wall", "door", "none", "door" },
		[1] = { "door", "wall", "wall", "wall", "none", "wall" },
	},
	M = {
		[0] = { "wall", "door", "seal", "seal", "none", "door" },
		[1] = { "door", "wall", "wall", "wall", "door", "wall" },
	},
	B = {
		[0] = { "none", "none", "wall", "door", "none", "door" },
		[1] = { "none", "door", "wall", "wall", "wall", "none" },
	},
}

-- Fachadas. Frente/fundos: uma especificação por coluna. Laterais: uma por faixa (F, C1, M, C2, B).
local FACADES = {
	front = {
		[0] = { "glassWall", "window", "window", "frontDoor", "tallWindow", "tallWindow", "window" },
		[1] = { "window", "window", "window", "bigWindow", "tallWindow", "tallWindow", "window" },
	},
	back = {
		[0] = { "window", "window", "window", "backDoor", "window", "window", "window" },
		[1] = { "window", "window", "window", "window", "window", "window", "window" },
	},
	west = {
		[0] = { "glassWall", "window", "smallWindow", "window", "window" },
		[1] = { "window", "window", "window", "window", "window" },
	},
	east = {
		[0] = { "window", "sideDoor", "smallWindow", "window", "window" },
		[1] = { "window", "window", "window", "window", "window" },
	},
}

-- Tipos de abertura (largura, altura do peitoril a partir do piso, altura do vão).
local OPENINGS = {
	door = { width = 6, bottom = 0, height = 9, kind = "door" },
	window = { width = 6, bottom = 3.5, height = 7, glass = true, sill = true, kind = "window" },
	smallWindow = { width = 4, bottom = 7, height = 4, glass = true, sill = true, kind = "window" },
	tallWindow = { width = 6, bottom = 2.5, height = 11, glass = true, sill = true, kind = "window" },
	bigWindow = { width = 10, bottom = 3, height = 9, glass = true, sill = true, kind = "window" },
	glassWall = { width = 20, bottom = 1.5, height = 12, glass = true, sill = true, mullions = 3, kind = "window" },
	frontDoor = { width = 8, bottom = 0, height = 11, frame = true, kind = "door" },
	backDoor = { width = 6, bottom = 0, height = 9, offset = 6, frame = true, kind = "door" },
	sideDoor = { width = 6, bottom = 0, height = 9, frame = true, kind = "door" },
}

-- Geometria auxiliar ---------------------------------------------------------------------

local function colX0(c: number): number
	return CX - HALF_W + (c - 1) * CELL
end

local function colX1(c: number): number
	return CX - HALF_W + c * CELL
end

local function colCenter(c: number): number
	return CX - HALF_W + (c - 0.5) * CELL
end

local function bandZ(band: string): (number, number)
	local b = BANDS[band]
	return CZ + b.z0, CZ + b.z1
end

-- Espessura da parede numa linha X (z relativo) ou Z (coluna de fronteira 0..7).
local function thicknessAtZ(zRel: number): number
	return math.abs(math.abs(zRel) - HALF_D) < 0.01 and T_EXT or T_IN
end

local function thicknessAtBoundary(k: number): number
	return (k == 0 or k == COLS) and T_EXT or T_IN
end

local function cellKey(story: number, row: string, col: number): string?
	local rowData = GRID[story][row]
	return rowData and rowData[col]
end

local function isVoid(key: string?): boolean
	return key ~= nil and string.sub(key, 1, 1) == "@"
end

-- Construtor de paredes -------------------------------------------------------------------

-- Constrói uma parede reta com aberturas (portas/janelas).
-- axis "X": parede ao longo do X na linha z = line; axis "Z": ao longo do Z na linha x = line.
-- a0/a1: início e fim ao longo do eixo. openings: lista com center/width/bottom/top (absolutos) e opções.
local function buildWall(
	ctx,
	parent,
	axis: string,
	line: number,
	a0: number,
	a1: number,
	y0: number,
	y1: number,
	openings,
	style
)
	local thickness = style.thickness
	local function piece(
		name: string,
		s0: number,
		s1: number,
		b0: number,
		b1: number,
		color,
		material,
		tags,
		depth,
		extra
	)
		if s1 - s0 < 0.05 or b1 - b0 < 0.05 then
			return nil
		end
		local mid = (s0 + s1) / 2
		local yc = (b0 + b1) / 2
		local cf, size
		if axis == "X" then
			cf = CFrame.new(mid, yc, line)
			size = Vector3.new(s1 - s0, b1 - b0, depth)
		else
			cf = CFrame.new(line, yc, mid)
			size = Vector3.new(depth, b1 - b0, s1 - s0)
		end
		return Kit.box(ctx, parent, name, cf, size, color, material, tags, extra)
	end
	local function wallPiece(s0, s1, b0, b1)
		local part = piece("Parede", s0, s1, b0, b1, style.color, style.material, style.tags, thickness)
		if part and style.collect then
			table.insert(style.collect, part)
		end
	end
	-- Posição deslocada para fora da parede (peitoris e molduras).
	local function outwardCF(s: number, y: number, distance: number): CFrame
		local normal = style.outward or Vector3.zero
		if axis == "X" then
			return CFrame.new(s, y, line) + normal * distance
		end
		return CFrame.new(line, y, s) + normal * distance
	end
	local function alongSize(along: number, height: number, depth: number): Vector3
		if axis == "X" then
			return Vector3.new(along, height, depth)
		end
		return Vector3.new(depth, height, along)
	end

	table.sort(openings, function(a, b)
		return a.center < b.center
	end)
	local cursor = a0
	for _, o in openings do
		local left = math.max(o.center - o.width / 2, a0)
		local right = math.min(o.center + o.width / 2, a1)
		wallPiece(cursor, left, y0, y1)
		wallPiece(left, right, math.min(o.top, y1), y1)
		wallPiece(left, right, y0, math.max(o.bottom, y0))
		if o.glass then
			piece("Vidro", left, right, o.bottom, math.min(o.top, y1), Palette.Glass, M.Glass, D, 0.3, {
				Transparency = 0.45,
				Reflectance = 0.1,
			})
			if o.mullions then
				local width = right - left
				for i = 1, o.mullions do
					local s = left + width * i / (o.mullions + 1)
					piece(
						"Caixilho",
						s - 0.2,
						s + 0.2,
						o.bottom,
						math.min(o.top, y1),
						Palette.Trim,
						M.Wood,
						nil,
						0.5,
						GHOST
					)
				end
				piece(
					"Caixilho",
					left,
					right,
					o.bottom + (o.top - o.bottom) * 0.62,
					o.bottom + (o.top - o.bottom) * 0.62 + 0.4,
					Palette.Trim,
					M.Wood,
					nil,
					0.5,
					GHOST
				)
			end
		end
		if o.sill and style.outward and o.bottom > y0 + 0.05 then
			local s = (left + right) / 2
			Kit.box(
				ctx,
				parent,
				"Peitoril",
				outwardCF(s, o.bottom - 0.2, thickness / 2 + 0.3),
				alongSize(right - left + 1, 0.4, 0.6),
				Palette.Trim,
				M.Wood,
				nil,
				GHOST
			)
		end
		if o.frame and style.outward then
			-- Moldura branca em volta da porta externa.
			for _, s in { left - 0.3, right + 0.3 } do
				Kit.box(
					ctx,
					parent,
					"Batente",
					outwardCF(s, (o.bottom + o.top) / 2, thickness / 2 + 0.1),
					alongSize(0.6, o.top - o.bottom, 0.3),
					Palette.Trim,
					M.Wood,
					nil,
					GHOST
				)
			end
			Kit.box(
				ctx,
				parent,
				"Batente",
				outwardCF((left + right) / 2, o.top + 0.4, thickness / 2 + 0.1),
				alongSize(right - left + 1.8, 0.8, 0.3),
				Palette.Trim,
				M.Wood,
				nil,
				GHOST
			)
		end
		cursor = right
	end
	wallPiece(cursor, a1, y0, y1)
end

-- Converte uma especificação de abertura em dados absolutos.
-- `cellMid` = centro da célula ao longo do eixo da parede; `floorY` = piso do andar.
local function resolveSpec(spec, cellMid: number, cellA: number, cellB: number, floorY: number, wallHeight: number)
	if type(spec) == "string" then
		if spec == "door" or spec == "start" then
			local o = OPENINGS.door
			return { center = cellMid, width = o.width, bottom = floorY, top = floorY + o.height, kind = spec }
		end
		local o = OPENINGS[spec]
		if o then
			local center = cellMid + (o.offset or 0)
			return {
				center = center,
				width = o.width,
				bottom = floorY + o.bottom,
				top = floorY + o.bottom + o.height,
				glass = o.glass,
				sill = o.sill,
				mullions = o.mullions,
				frame = o.frame,
				kind = o.kind,
			}
		end
		return nil
	end
	-- Tabela: aberturas com posição explícita.
	local from = spec.from and (cellMid + spec.from) or nil
	local to = spec.to and (cellMid + spec.to) or nil
	if spec.kind == "open" or spec.kind == "railing" then
		from = from or cellA
		to = to or cellB
		return {
			center = (from + to) / 2,
			width = to - from,
			bottom = floorY,
			top = floorY + wallHeight + 1,
			kind = spec.kind,
		}
	end
	local width, center
	if from and to then
		width = to - from
		center = (from + to) / 2
	else
		width = OPENINGS.door.width
		center = cellMid + (spec.offset or 0)
	end
	return {
		center = center,
		width = width,
		bottom = floorY,
		top = floorY + (spec.height or OPENINGS.door.height),
		kind = "door",
	}
end

-- Construção ------------------------------------------------------------------------------

function Mansion.Build(ctx)
	local root = ctx.map
	local structure = Kit.model("Mansão - Estrutura")
	local rng = ctx.random

	-- Aberturas registradas por andar (para os cômodos saberem onde estão portas e janelas).
	local openingsByStory = { [0] = {}, [1] = {} }
	-- Parts que lacram a sala inicial até as portas abrirem.
	local sealParts = {}
	local startDoorSlots = {}

	local function record(story: number, axis: string, line: number, o)
		local center
		if axis == "X" then
			center = Vector3.new(o.center, o.bottom, line)
		else
			center = Vector3.new(line, o.bottom, o.center)
		end
		table.insert(openingsByStory[story], {
			position = center,
			axis = axis,
			width = o.width,
			bottomY = o.bottom,
			topY = o.top,
			kind = (o.kind == "window") and "window" or "door",
		})
	end

	local interiorStyle = {
		[0] = { color = Palette.Plaster, material = M.Plaster, thickness = T_IN, tags = D },
		[1] = { color = Palette.PlasterUpper, material = M.Plaster, thickness = T_IN, tags = D },
	}

	-- 1) Pisos do térreo (indestrutíveis), um por cômodo e um por corredor.
	local floorDone = {}
	for _, row in ROOM_ROWS do
		for c = 1, COLS do
			local key = cellKey(0, row, c)
			if key and not floorDone[key] then
				floorDone[key] = true
				local c0, c1 = c, c
				while cellKey(0, row, c1 + 1) == key do
					c1 += 1
				end
				local z0, z1 = bandZ(row)
				local info = Rooms.Info[key]
				Kit.box(
					ctx,
					structure,
					"Piso",
					Vector3.new((colX0(c0) + colX1(c1)) / 2, FLOOR[0] - SLAB / 2, (z0 + z1) / 2),
					Vector3.new(colX1(c1) - colX0(c0), SLAB, z1 - z0),
					info.floorColor,
					info.floorMaterial,
					I
				)
			end
		end
	end
	for _, band in { "C1", "C2" } do
		local z0, z1 = bandZ(band)
		Kit.box(
			ctx,
			structure,
			"Piso",
			Vector3.new(CX, FLOOR[0] - SLAB / 2, (z0 + z1) / 2),
			Vector3.new(HALF_W * 2, SLAB, z1 - z0),
			Palette.FloorWood,
			M.WoodPlanks,
			I
		)
	end

	-- 2) Lajes do 2º andar (destrutíveis), uma por célula/trecho de corredor.
	local slabY = FLOOR[1] - SLAB / 2
	for _, band in BAND_ORDER do
		local z0, z1 = bandZ(band)
		for c = 1, COLS do
			local x0, x1 = colX0(c), colX1(c)
			local upperKey = cellKey(1, band, c)
			local material, color = M.WoodPlanks, Palette.FloorWood
			if upperKey and Rooms.Info[upperKey] then
				material = Rooms.Info[upperKey].floorMaterial
				color = Rooms.Info[upperKey].floorColor
			end
			if upperKey == "@EscadaFundos" then
				-- Patamar da escada dos fundos: só a parte leste (a escada ocupa a faixa oeste da célula).
				x0 = CX - 5.5
			end
			if not isVoid(upperKey) or upperKey == "@EscadaFundos" then
				local isStartCeiling = (band == "M" and cellKey(0, band, c) == "Jogos")
				local slab = Kit.box(
					ctx,
					structure,
					"Laje",
					Vector3.new((x0 + x1) / 2, slabY, (z0 + z1) / 2),
					Vector3.new(x1 - x0, SLAB, z1 - z0),
					color,
					material,
					isStartCeiling and I or D
				)
				if isStartCeiling then
					table.insert(sealParts, slab)
				end
			end
		end
	end

	-- Laje do teto do 2º andar (uma por faixa).
	for _, band in BAND_ORDER do
		local z0, z1 = bandZ(band)
		Kit.box(
			ctx,
			structure,
			"Teto",
			Vector3.new(CX, CEILING_TOP - SLAB / 2, (z0 + z1) / 2),
			Vector3.new(HALF_W * 2, SLAB, z1 - z0),
			Palette.PlasterUpper,
			M.Plaster
		)
	end

	-- 3) Paredes internas paralelas ao X.
	for _, xl in X_LINES do
		local line = CZ + xl.z
		for story = 0, 1 do
			local floorY = FLOOR[story]
			for c = 1, COLS do
				local spec = xl.specs[story][c]
				local a0 = (c == 1) and (colX0(c) + T_EXT / 2) or colX0(c)
				local a1 = (c == COLS) and (colX1(c) - T_EXT / 2) or colX1(c)
				local style = interiorStyle[story]
				local isStart = spec == "start"
				if isStart then
					style = table.clone(style)
					style.tags = I
					style.collect = sealParts
				end
				if type(spec) == "table" and spec.kind == "railing" then
					-- Sem parede: balaustrada na beira do vão, deixando livre a chegada da escada.
					local opening = resolveSpec(spec, colCenter(c), colX0(c), colX1(c), floorY, WALL_IN_HEIGHT)
					local from, to = opening.center - opening.width / 2, opening.center + opening.width / 2
					Kit.box(
						ctx,
						structure,
						"Balaustrada",
						Vector3.new((from + to) / 2, floorY + 1.6, line - 0.25),
						Vector3.new(to - from, 3.2, 0.5),
						Palette.WoodDark,
						M.Wood,
						D
					)
					record(story, "X", line, {
						center = colCenter(c),
						width = CELL,
						bottom = floorY,
						top = floorY + WALL_IN_HEIGHT,
						kind = "door",
					})
				else
					local openings = {}
					local specList = (type(spec) == "table" and spec[1] ~= nil) and spec or { spec }
					for _, item in specList do
						local opening = resolveSpec(item, colCenter(c), colX0(c), colX1(c), floorY, WALL_IN_HEIGHT)
						if opening then
							table.insert(openings, opening)
							record(story, "X", line, opening)
							if isStart then
								table.insert(startDoorSlots, {
									center = Vector3.new(opening.center, floorY, line),
									width = opening.width,
									height = opening.top - opening.bottom,
									-- O corredor fica do lado de fora da sala inicial (a porta abre para ele).
									outward = (xl.z > 0) and 1 or -1,
								})
							end
						end
					end
					buildWall(ctx, structure, "X", line, a0, a1, floorY, floorY + WALL_IN_HEIGHT, openings, style)
				end
			end
		end
	end

	-- 4) Paredes internas paralelas ao Z (entre colunas).
	for _, row in ROOM_ROWS do
		local z0, z1 = bandZ(row)
		for story = 0, 1 do
			local floorY = FLOOR[story]
			for k = 1, COLS - 1 do
				local spec = Z_LINES[row][story][k]
				if spec ~= "none" then
					local line = CX - HALF_W + k * CELL
					local style = interiorStyle[story]
					local height = WALL_IN_HEIGHT
					if story == 0 and isVoid(cellKey(1, row, k)) and isVoid(cellKey(1, row, k + 1)) then
						-- Vão dos dois lados: a parede sobe até o 2º andar para não sobrar fresta.
						height = STORY
					end
					if spec == "seal" then
						style = table.clone(style)
						style.tags = I
						style.collect = sealParts
					end
					local openings = {}
					if spec == "door" then
						local o = resolveSpec("door", (z0 + z1) / 2, z0, z1, floorY, height)
						table.insert(openings, o)
						record(story, "Z", line, o)
					end
					local a0 = (row == "B") and (z0 + T_EXT / 2) or z0
					local a1 = (row == "F") and (z1 - T_EXT / 2) or z1
					buildWall(ctx, structure, "Z", line, a0, a1, floorY, floorY + height, openings, style)
				end
			end
		end
	end

	-- 5) Fachadas (tijolo), com janelas de vidro destrutível.
	local exteriorStyle = { color = Palette.Brick, material = M.Brick, thickness = T_EXT, tags = D }
	for story = 0, 1 do
		local floorY = FLOOR[story]
		local wallTop = floorY + STORY
		for _, facade in { "front", "back" } do
			local zRel = facade == "front" and HALF_D or -HALF_D
			local line = CZ + zRel
			local style = table.clone(exteriorStyle)
			style.outward = Vector3.new(0, 0, facade == "front" and 1 or -1)
			for c = 1, COLS do
				local spec = FACADES[facade][story][c]
				local a0 = (c == 1) and (colX0(c) - T_EXT / 2) or colX0(c)
				local a1 = (c == COLS) and (colX1(c) + T_EXT / 2) or colX1(c)
				local openings = {}
				local o = resolveSpec(spec, colCenter(c), colX0(c), colX1(c), floorY, STORY)
				if o then
					table.insert(openings, o)
					record(story, "X", line, o)
				end
				buildWall(ctx, structure, "X", line, a0, a1, floorY, wallTop, openings, style)
			end
		end
		for _, facade in { "west", "east" } do
			local line = CX + (facade == "west" and -HALF_W or HALF_W)
			local style = table.clone(exteriorStyle)
			style.outward = Vector3.new(facade == "west" and -1 or 1, 0, 0)
			for index, band in BAND_ORDER do
				local z0, z1 = bandZ(band)
				local a0 = (band == "B") and (z0 + T_EXT / 2) or z0
				local a1 = (band == "F") and (z1 - T_EXT / 2) or z1
				local spec = FACADES[facade][story][index]
				local openings = {}
				local o = resolveSpec(spec, (z0 + z1) / 2, z0, z1, floorY, STORY)
				if o then
					table.insert(openings, o)
					record(story, "Z", line, o)
				end
				buildWall(ctx, structure, "Z", line, a0, a1, floorY, wallTop, openings, style)
			end
		end
	end

	-- 6) Escadas, balaústres e mezanino da biblioteca.
	local function buildStairs(name: string, xMin: number, xMax: number, zBase: number, zTop: number)
		local direction = (zTop > zBase) and 1 or -1
		local run = math.abs(zTop - zBase) / STAIR_STEPS
		local rise = STORY / STAIR_STEPS
		for i = 1, STAIR_STEPS do
			local zA = zBase + direction * run * (i - 1)
			local zB = zBase + direction * run * i
			local top = FLOOR[0] + rise * i
			Kit.box(
				ctx,
				structure,
				name,
				Vector3.new((xMin + xMax) / 2, (FLOOR[0] + top) / 2, (zA + zB) / 2),
				Vector3.new(xMax - xMin, top - FLOOR[0], run),
				(i % 2 == 0) and Palette.WoodDark or Palette.Wood,
				M.WoodPlanks,
				I
			)
		end
		-- Corrimão inclinado no lado aberto da escada, com três balaústres.
		local railX = xMax - 0.25
		local p0 = Vector3.new(railX, FLOOR[0] + 3.4, zBase)
		local p1 = Vector3.new(railX, FLOOR[1] + 3.4, zTop)
		local mid = (p0 + p1) / 2
		Kit.box(
			ctx,
			structure,
			"Corrimao",
			CFrame.lookAt(mid, p1),
			Vector3.new(0.45, 0.45, (p1 - p0).Magnitude),
			Palette.WoodDark,
			M.Wood,
			D
		)
		for _, i in { 1, 10, 19 } do
			local z = zBase + direction * run * (i - 0.5)
			local stepTop = FLOOR[0] + rise * i
			local railY = FLOOR[0] + 3.4 + rise * (i - 0.5)
			Kit.box(
				ctx,
				structure,
				"Balaustre",
				Vector3.new(railX, (stepTop + railY) / 2, z),
				Vector3.new(0.4, railY - stepTop, 0.4),
				Palette.WoodDark,
				M.Wood,
				D
			)
		end
	end
	-- Escadaria principal: no hall, encostada na parede oeste, subindo da frente para o corredor.
	buildStairs("Degrau", CX - 13.5, CX - 5.5, CZ + 50, CZ + 26)
	-- Escada dos fundos: subindo dos fundos para o corredor de serviço.
	buildStairs("Degrau", CX - 13.5, CX - 5.5, CZ - 50, CZ - 26)
	-- Guarda-corpo do patamar dos fundos (ao lado do vão da escada).
	Kit.box(
		ctx,
		structure,
		"Balaustrada",
		Vector3.new(CX - 5.25, FLOOR[1] + 1.6, (CZ - HALF_D + T_EXT / 2 + CZ - 27.2) / 2),
		Vector3.new(0.5, 3.2, (CZ - 27.2) - (CZ - HALF_D + T_EXT / 2)),
		Palette.WoodDark,
		M.Wood,
		D
	)

	-- Mezanino da biblioteca (faixa de 7 studs junto à parede do corredor).
	local libX0, libX1 = colX0(5), colX1(6)
	local mezzanineZ0, mezzanineZ1 = CZ + 26, CZ + 33
	Kit.box(
		ctx,
		structure,
		"Mezanino",
		Vector3.new((libX0 + libX1) / 2, slabY, (mezzanineZ0 + mezzanineZ1) / 2),
		Vector3.new(libX1 - libX0, SLAB, mezzanineZ1 - mezzanineZ0),
		Palette.FloorWood,
		M.WoodPlanks,
		D
	)
	Kit.box(
		ctx,
		structure,
		"Balaustrada",
		Vector3.new((libX0 + libX1) / 2, FLOOR[1] + 1.6, mezzanineZ1 - 0.25),
		Vector3.new(libX1 - libX0 - T_IN, 3.2, 0.5),
		Palette.WoodDark,
		M.Wood,
		D
	)
	for _, x in { libX0 + 7, (libX0 + libX1) / 2, libX1 - 7 } do
		Kit.cylinder(
			ctx,
			structure,
			"Coluna",
			Vector3.new(x, FLOOR[0] + (FLOOR[1] - SLAB - FLOOR[0]) / 2, mezzanineZ1 - 0.9),
			FLOOR[1] - SLAB - FLOOR[0],
			1.2,
			Palette.WoodDark,
			M.Wood
		)
	end

	-- 7) Acabamentos externos: rodapé de pedra, cornijas, telhado, chaminés e pórtico.
	local outerW = HALF_W * 2 + T_EXT
	local outerD = HALF_D * 2 + T_EXT
	for _, side in { -1, 1 } do
		Kit.box(
			ctx,
			structure,
			"Embasamento",
			Vector3.new(CX, FLOOR[0] - 0.1, CZ + side * HALF_D),
			Vector3.new(outerW + 0.6, 1, T_EXT + 0.6),
			Palette.StoneDark,
			M.Slate,
			I
		)
		Kit.box(
			ctx,
			structure,
			"Embasamento",
			Vector3.new(CX + side * HALF_W, FLOOR[0] - 0.1, CZ),
			Vector3.new(T_EXT + 0.6, 1, HALF_D * 2 - T_EXT - 0.6),
			Palette.StoneDark,
			M.Slate,
			I
		)
		for _, y in { FLOOR[1], CEILING_TOP - 0.3 } do
			Kit.box(
				ctx,
				structure,
				"Cornija",
				Vector3.new(CX, y, CZ + side * (HALF_D + T_EXT / 2 + 0.2)),
				Vector3.new(outerW + 0.8, 0.7, 0.4),
				Palette.Trim,
				M.Wood,
				nil,
				GHOST
			)
			Kit.box(
				ctx,
				structure,
				"Cornija",
				Vector3.new(CX + side * (HALF_W + T_EXT / 2 + 0.2), y, CZ),
				Vector3.new(0.4, 0.7, outerD),
				Palette.Trim,
				M.Wood,
				nil,
				GHOST
			)
		end
	end

	local roof = Kit.model("Mansão - Telhado")
	local halfDepthOuter = HALF_D + T_EXT / 2
	local overhang = 3
	local thick = 1.2
	local roofLength = outerW + 4
	local segments = 7
	for _, side in { 1, -1 } do
		local ridge = Vector3.new(0, CEILING_TOP + ROOF_RISE, CZ)
		local down = Vector3.new(0, -ROOF_RISE, side * halfDepthOuter).Unit
		local normal = Vector3.new(0, halfDepthOuter, side * ROOF_RISE).Unit
		local slopeLength = (halfDepthOuter + overhang) / math.abs(down.Z)
		local centerYZ = ridge + down * (slopeLength / 2) + normal * (thick / 2)
		for i = 1, segments do
			local x = CX - roofLength / 2 + (i - 0.5) * roofLength / segments
			Kit.box(
				ctx,
				roof,
				"Telhado",
				CFrame.fromMatrix(Vector3.new(x, centerYZ.Y, centerYZ.Z), Vector3.xAxis, normal),
				Vector3.new(roofLength / segments, thick, slopeLength),
				Palette.Roof,
				M.Slate,
				D
			)
		end
	end
	Kit.box(
		ctx,
		roof,
		"Cumeeira",
		Vector3.new(CX, CEILING_TOP + ROOF_RISE + 1.1, CZ),
		Vector3.new(roofLength, 0.8, 2.6),
		Palette.StoneDark,
		M.Slate
	)
	-- Oitões (triângulos de tijolo nas laterais): a rampa da cunha desce para o -Z local.
	for _, sx in { -1, 1 } do
		local x = CX + sx * HALF_W
		local y = CEILING_TOP + ROOF_RISE / 2
		Kit.wedge(
			ctx,
			roof,
			"Oitao",
			CFrame.new(x, y, CZ + halfDepthOuter / 2) * CFrame.Angles(0, math.pi, 0),
			Vector3.new(T_EXT, ROOF_RISE, halfDepthOuter),
			Palette.Brick,
			M.Brick
		)
		Kit.wedge(
			ctx,
			roof,
			"Oitao",
			CFrame.new(x, y, CZ - halfDepthOuter / 2),
			Vector3.new(T_EXT, ROOF_RISE, halfDepthOuter),
			Palette.Brick,
			M.Brick
		)
	end
	for _, sx in { -1, 1 } do
		local height = ROOF_RISE + 8
		Kit.box(
			ctx,
			roof,
			"Chamine",
			Vector3.new(CX + sx * 56, CEILING_TOP + height / 2, CZ - 10),
			Vector3.new(5, height, 4),
			Palette.BrickDark,
			M.Brick,
			D
		)
		Kit.box(
			ctx,
			roof,
			"Chamine",
			Vector3.new(CX + sx * 56, CEILING_TOP + height + 0.4, CZ - 10),
			Vector3.new(6, 0.8, 5),
			Palette.StoneDark,
			M.Slate
		)
	end
	Kit.attach(roof, root, Vector3.new(CX, CEILING_TOP + ROOF_RISE / 2, CZ))

	-- Pórtico de entrada com colunas e frontão.
	local porchZ0 = CZ + HALF_D + T_EXT / 2
	local porchDepth = 11
	local porch = Kit.model("Mansão - Pórtico")
	Kit.box(
		ctx,
		porch,
		"Piso",
		Vector3.new(CX, FLOOR[0] - 0.3, porchZ0 + porchDepth / 2),
		Vector3.new(24, 1, porchDepth),
		Palette.Marble,
		M.Marble,
		I
	)
	local porchTop = FLOOR[0] + 14
	for _, x in { -10, -4, 4, 10 } do
		Kit.cylinder(
			ctx,
			porch,
			"Coluna",
			Vector3.new(CX + x, (FLOOR[0] + porchTop) / 2, porchZ0 + porchDepth - 1.5),
			porchTop - FLOOR[0],
			1.8,
			Palette.Trim,
			M.Marble
		)
	end
	Kit.box(
		ctx,
		porch,
		"Cobertura",
		Vector3.new(CX, porchTop + 0.5, porchZ0 + porchDepth / 2),
		Vector3.new(25, 1, porchDepth + 1),
		Palette.Trim,
		M.Wood,
		D
	)
	for _, sx in { -1, 1 } do
		Kit.wedge(
			ctx,
			porch,
			"Frontao",
			CFrame.new(CX + sx * 6.25, porchTop + 3.5, porchZ0 + porchDepth / 2)
				* CFrame.Angles(0, -sx * math.rad(90), 0),
			Vector3.new(porchDepth + 1, 5, 12.5),
			Palette.Trim,
			M.Wood
		)
	end
	-- Portas de entrada abertas para dentro (decorativas).
	for _, sx in { -1, 1 } do
		Kit.box(
			ctx,
			porch,
			"PortaDeEntrada",
			Vector3.new(CX + sx * 3.75, FLOOR[0] + 5.45, CZ + HALF_D - T_EXT / 2 - 2),
			Vector3.new(0.4, 10.8, 3.9),
			Palette.WoodRed,
			M.Wood
		)
	end
	Kit.attach(porch, root, Vector3.new(CX, FLOOR[0] + 7, porchZ0 + porchDepth / 2))

	-- 8) Cômodos: descritores, regiões e móveis.
	local roomsBuilt = {}
	local startInfo = nil
	for story = 0, 1 do
		local done = {}
		for _, row in ROOM_ROWS do
			for c = 1, COLS do
				local key = cellKey(story, row, c)
				if key and not isVoid(key) and not done[key] then
					done[key] = true
					local c0, c1 = c, c
					while cellKey(story, row, c1 + 1) == key do
						c1 += 1
					end
					local z0, z1 = bandZ(row)
					local x0, x1 = colX0(c0), colX1(c1)
					local ix0 = x0 + thicknessAtBoundary(c0 - 1) / 2
					local ix1 = x1 - thicknessAtBoundary(c1) / 2
					local iz0 = z0 + thicknessAtZ(z0 - CZ) / 2
					local iz1 = z1 - thicknessAtZ(z1 - CZ) / 2
					local double = DOUBLE_HEIGHT[key] == true
					local floorY = FLOOR[story]
					local height = double and (CEILING_TOP - SLAB - floorY) or WALL_IN_HEIGHT
					-- Frente local (-Z) virada para a porta principal: faixa F olha para o corredor (−Z do mundo),
					-- faixas M e B olham para +Z do mundo.
					local yaw = (row == "F") and 0 or math.pi
					local centerX, centerZ = (ix0 + ix1) / 2, (iz0 + iz1) / 2
					local cf = CFrame.new(centerX, floorY, centerZ) * CFrame.Angles(0, yaw, 0)
					local info = Rooms.Info[key]
					local openings = {}
					local stories = double and { 0, 1 } or { story }
					for _, s in stories do
						for _, o in openingsByStory[s] do
							local p = o.position
							if p.X >= x0 - 1 and p.X <= x1 + 1 and p.Z >= z0 - 1 and p.Z <= z1 + 1 then
								table.insert(openings, o)
							end
						end
					end
					local room = Rooms.new(ctx, {
						key = key,
						name = info.name,
						kind = info.kind,
						story = story,
						floorY = floorY,
						cf = cf,
						w = ix1 - ix0,
						d = iz1 - iz0,
						h = height,
						openings = openings,
					})
					-- Áreas reservadas: as escadas e o espaço livre até a parede na frente do primeiro degrau.
					if key == "Hall" then
						room:reserveWorld(CX - 13.5, CX - 5.5, CZ + 26, CZ + HALF_D)
					elseif key == "EscadaFundos" then
						room:reserveWorld(CX - 13.5, CX - 5.5, CZ - HALF_D, CZ - 26)
					elseif key == "Biblioteca" then
						for _, x in { libX0 + 7, (libX0 + libX1) / 2, libX1 - 7 } do
							room:reserveWorld(x - 1.2, x + 1.2, mezzanineZ1 - 2.1, mezzanineZ1 + 0.3)
						end
					end
					local regionBottom = (story == 0) and (FLOOR[0] - 1.5) or (FLOOR[1] - 0.5)
					local regionTop = (double or story == 1) and CEILING_TOP or (FLOOR[1] - 0.5)
					Kit.region(
						ctx,
						info.name,
						CFrame.new((x0 + x1) / 2, (regionBottom + regionTop) / 2, (z0 + z1) / 2),
						Vector3.new(x1 - x0, regionTop - regionBottom, z1 - z0),
						story
					)
					if key == "Jogos" then
						startInfo = StartRoom.Build(ctx, room, startDoorSlots, sealParts)
					else
						Rooms.Furnish(room)
					end
					Kit.attach(room.model, root, Vector3.new(centerX, floorY + height / 2, centerZ))
					table.insert(roomsBuilt, room)
				end
			end
		end
	end

	-- Corredores (como "cômodos" compridos) e a região da escadaria principal.
	local corridorNames = {
		[0] = { C1 = "Corredor Principal", C2 = "Corredor dos Fundos" },
		[1] = { C1 = "Corredor Superior", C2 = "Corredor Superior dos Fundos" },
	}
	for story = 0, 1 do
		for _, band in { "C1", "C2" } do
			local z0, z1 = bandZ(band)
			local floorY = FLOOR[story]
			local name = corridorNames[story][band]
			local openings = {}
			for _, o in openingsByStory[story] do
				local p = o.position
				if p.Z >= z0 - 1 and p.Z <= z1 + 1 then
					table.insert(openings, o)
				end
			end
			local corridor = Rooms.new(ctx, {
				key = "Corredor",
				name = name,
				kind = "Corridor",
				story = story,
				floorY = floorY,
				cf = CFrame.new(CX, floorY, (z0 + z1) / 2),
				w = HALF_W * 2 - T_EXT,
				d = (z1 - z0) - T_IN,
				h = WALL_IN_HEIGHT,
				openings = openings,
			})
			if story == 1 and band == "C1" then
				-- Chegada da escadaria principal e beirada do vão do hall.
				corridor:reserveWorld(CX - 14, CX + 14, z1 - 4, z1)
			elseif story == 1 and band == "C2" then
				corridor:reserveWorld(CX - 14, CX - 5, z0, z0 + 4)
			end
			local regionBottom = (story == 0) and (FLOOR[0] - 1.5) or (FLOOR[1] - 0.5)
			local regionTop = (story == 0) and (FLOOR[1] - 0.5) or CEILING_TOP
			Kit.region(
				ctx,
				name,
				CFrame.new(CX, (regionBottom + regionTop) / 2, (z0 + z1) / 2),
				Vector3.new(HALF_W * 2, regionTop - regionBottom, z1 - z0),
				story
			)
			Rooms.Furnish(corridor)
			Kit.attach(corridor.model, root, Vector3.new(CX, floorY + 7, (z0 + z1) / 2))
		end
	end
	Kit.region(
		ctx,
		"Escadaria Principal",
		CFrame.new(CX - 9.75, (FLOOR[0] - 1.5 + CEILING_TOP) / 2, CZ + 39),
		Vector3.new(8.5, CEILING_TOP - FLOOR[0] + 1.5, 26),
		0
	)
	Kit.region(
		ctx,
		"Mansão",
		CFrame.new(CX, (FLOOR[0] - 2 + CEILING_TOP + ROOF_RISE + 8) / 2, CZ + 6),
		Vector3.new(HALF_W * 2 + 8, CEILING_TOP + ROOF_RISE + 10 - FLOOR[0], HALF_D * 2 + 24),
		0
	)

	-- 9) Selva invadindo a mansão: cipós nas fachadas e arbustos junto às paredes.
	local jungle = Kit.chunk("Mansão - Trepadeiras")
	local facades = {
		{
			normal = Vector3.new(0, 0, 1),
			fixed = CZ + HALF_D + T_EXT / 2 + 0.2,
			from = CX - HALF_W,
			to = CX + HALF_W,
			alongX = true,
		},
		{
			normal = Vector3.new(0, 0, -1),
			fixed = CZ - HALF_D - T_EXT / 2 - 0.2,
			from = CX - HALF_W,
			to = CX + HALF_W,
			alongX = true,
		},
		{
			normal = Vector3.new(1, 0, 0),
			fixed = CX + HALF_W + T_EXT / 2 + 0.2,
			from = CZ - HALF_D,
			to = CZ + HALF_D,
			alongX = false,
		},
		{
			normal = Vector3.new(-1, 0, 0),
			fixed = CX - HALF_W - T_EXT / 2 - 0.2,
			from = CZ - HALF_D,
			to = CZ + HALF_D,
			alongX = false,
		},
	}
	for _, facade in facades do
		local vines = facade.alongX and 9 or 5
		for _ = 1, vines do
			local s = rng:NextNumber(facade.from + 2, facade.to - 2)
			local topY = (rng:NextNumber() < 0.5) and (CEILING_TOP - 0.5) or (FLOOR[1] - 0.2)
			local length = rng:NextNumber(5, math.min(18, topY - FLOOR[0] - 1))
			local top = facade.alongX and Vector3.new(s, topY, facade.fixed) or Vector3.new(facade.fixed, topY, s)
			Plants.Vine(ctx, jungle, top, length, rng, facade.normal)
		end
		local bushes = facade.alongX and 6 or 3
		for _ = 1, bushes do
			local s = rng:NextNumber(facade.from + 4, facade.to - 4)
			-- Evita o pórtico e as portas externas.
			if not (facade.normal.Z > 0 and math.abs(s - CX) < 16) then
				local base = facade.alongX and Vector3.new(s, GameConfig.GROUND_Y, facade.fixed + facade.normal.Z * 2.5)
					or Vector3.new(facade.fixed + facade.normal.X * 2.5, GameConfig.GROUND_Y, s)
				local nearDoor = false
				for _, o in openingsByStory[0] do
					if
						o.kind == "door"
						and (Vector3.new(o.position.X, 0, o.position.Z) - Vector3.new(base.X, 0, base.Z)).Magnitude
							< 9
					then
						nearDoor = true
					end
				end
				if not nearDoor then
					Plants.Bush(ctx, jungle, base, rng:NextNumber(4, 7), rng)
				end
			end
		end
	end
	Kit.attach(jungle, root, Vector3.new(CX, FLOOR[1], CZ))

	Kit.attach(structure, root, Vector3.new(CX, FLOOR[1], CZ))

	-- Área ocupada pela mansão (a vegetação aleatória não nasce aqui).
	Kit.block(ctx, CX - HALF_W - 6, CX + HALF_W + 6, CZ - HALF_D - 6, CZ + HALF_D + porchDepth + 4)

	return {
		start = startInfo,
		frontDoor = Vector3.new(CX, GameConfig.GROUND_Y, porchZ0 + porchDepth),
		backDoor = Vector3.new(CX + OPENINGS.backDoor.offset, GameConfig.GROUND_Y, CZ - HALF_D - T_EXT / 2),
		sideDoor = Vector3.new(CX + HALF_W + T_EXT / 2, GameConfig.GROUND_Y, CZ + (BANDS.C1.z0 + BANDS.C1.z1) / 2),
		bounds = { minX = CX - HALF_W, maxX = CX + HALF_W, minZ = CZ - HALF_D, maxZ = CZ + HALF_D },
		rooms = roomsBuilt,
	}
end

return Mansion
