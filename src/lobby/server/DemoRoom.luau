--!nonstrict
-- Sala de demonstração das configurações gráficas (servidor do lobby).
-- Fica em GameConfig.DEMO_ROOM_ORIGIN (centro do piso, no nível de cima do piso) e foi pensada para MOSTRAR
-- cada opção quando o jogador mexe na aba Gráficos:
--   * Redução de texturas: piso de WoodPlanks, paredes de Brick, colunas de Marble, sofá e poltrona de Fabric,
--     tapete de Carpet, vaso com Grass, mesa de Granite, livros de Leather e um quadro "pintado" cujos
--     detalhes (atributo TextureDetail) somem e deixam só as cores chapadas.
--   * Sombras: lustre, luminárias e arandela com luzes Shadows = true, um holofote de "sol" entrando pela grade
--     da janela, colunas e móveis grandes fazendo sombras longas.
--   * Distância de renderização: a janela enorme olha para uma pista longa na direção +Z com marcos
--     (Models CullChunk) a 100, 200, 400, 800 e 1500 studs da câmera; eles somem conforme o limite escolhido.
-- Cria workspace.LobbyMarkers.DemoCamera (CFrame da câmera da demonstração) e guarda o mesmo CFrame no
-- atributo "DemoCameraCFrame" da pasta, para o cliente achar mesmo com streaming ligado.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local PartBuilder = require(ReplicatedStorage.Shared.Util.PartBuilder)
local Tags = require(ReplicatedStorage.Shared.Tags)

local DemoRoom = {}

local M = Enum.Material
local ORIGIN = GameConfig.DEMO_ROOM_ORIGIN

-- Medidas (studs, relativas a ORIGIN) -------------------------------------------------------
local HALF_X = 28 -- interior: X de -28 a 28
local HALF_Z = 22 -- interior: Z de -22 a 22 (a janela fica na parede +Z)
local HEIGHT = 20
local WALL = 1.5
local WINDOW_X0, WINDOW_X1 = -17, 13
local WINDOW_Y0, WINDOW_Y1 = 2, 18.5
local GROUND_TOP = -0.3 -- topo do gramado externo
local TRACK_TOP = -0.1
local TRACK_HALF_WIDTH = 10
local TRACK_END_Z = 1664
local TRACK_SEGMENT = 410 -- comprimento de cada pedaço da pista (máx. 2048 por part)

-- Câmera: no fundo da sala, um pouco alta, girada para a direita (-X) para que a sala e a pista
-- apareçam nos 62% da tela à esquerda do painel de configurações.
local CAMERA_LOCAL = Vector3.new(0, 11, -20)
local CAMERA_YAW = math.rad(12)
local CAMERA_PITCH = math.rad(-11)

-- Marcos da pista: distância até a câmera, deslocamento lateral, escala e cor.
-- A escala cresce com a distância para todos parecerem do mesmo tamanho pela janela.
local MARKERS = {
	{ distance = 100, x = 12, scale = 1, color = Color3.fromRGB(214, 64, 52) },
	{ distance = 200, x = -16, scale = 1.4, color = Color3.fromRGB(236, 140, 40) },
	{ distance = 400, x = 24, scale = 2.4, color = Color3.fromRGB(236, 206, 60) },
	{ distance = 800, x = -36, scale = 4, color = Color3.fromRGB(60, 170, 220) },
	{ distance = 1500, x = 20, scale = 7, color = Color3.fromRGB(176, 84, 210) },
}

-- Cores
local C = {
	floor = Color3.fromRGB(150, 104, 62),
	brick = Color3.fromRGB(150, 74, 54),
	plaster = Color3.fromRGB(232, 222, 200),
	beam = Color3.fromRGB(74, 48, 30),
	marble = Color3.fromRGB(236, 232, 224),
	windowWood = Color3.fromRGB(62, 42, 26),
	glass = Color3.fromRGB(180, 214, 230),
	curtain = Color3.fromRGB(128, 30, 40),
	gold = Color3.fromRGB(196, 156, 64),
	candle = Color3.fromRGB(246, 238, 214),
	flame = Color3.fromRGB(255, 170, 70),
	sofa = Color3.fromRGB(46, 96, 62),
	sofaCushion = Color3.fromRGB(58, 114, 74),
	pillow = Color3.fromRGB(214, 170, 72),
	armchair = Color3.fromRGB(196, 150, 52),
	darkWood = Color3.fromRGB(70, 44, 26),
	granite = Color3.fromRGB(78, 78, 84),
	rug = Color3.fromRGB(140, 36, 40),
	rugBorder = Color3.fromRGB(206, 164, 76),
	shelf = Color3.fromRGB(88, 56, 34),
	lampMetal = Color3.fromRGB(40, 40, 44),
	lampShade = Color3.fromRGB(232, 218, 180),
	pot = Color3.fromRGB(176, 92, 56),
	soil = Color3.fromRGB(76, 52, 34),
	leaves = Color3.fromRGB(62, 128, 52),
	grassField = Color3.fromRGB(76, 124, 56),
	track = Color3.fromRGB(150, 120, 80),
	trackAlt = Color3.fromRGB(138, 110, 72),
	stripe = Color3.fromRGB(240, 236, 226),
	plinth = Color3.fromRGB(120, 120, 126),
	warmLight = Color3.fromRGB(255, 206, 150),
	sunLight = Color3.fromRGB(255, 238, 204),
}

local BOOK_COLORS = {
	Color3.fromRGB(128, 34, 38),
	Color3.fromRGB(36, 70, 120),
	Color3.fromRGB(40, 96, 56),
	Color3.fromRGB(150, 110, 40),
	Color3.fromRGB(90, 50, 110),
	Color3.fromRGB(60, 40, 30),
	Color3.fromRGB(170, 150, 120),
}

-- Helpers -------------------------------------------------------------------------------------

local function at(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

local function cf(x: number, y: number, z: number): CFrame
	return CFrame.new(at(x, y, z))
end

-- Part ancorada da sala. Decoração não colide nem participa de consultas espaciais (mais leve).
local function block(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	extra: { [string]: any }?
): BasePart
	local props = {
		Name = name,
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material,
		CanTouch = false,
		CanQuery = false,
		CanCollide = false,
		Parent = parent,
	}
	if extra then
		for key, value in extra do
			props[key] = value
		end
	end
	return PartBuilder.part(props)
end

local function ball(parent: Instance, name: string, diameter: number, position: Vector3, color: Color3, material)
	return block(parent, name, Vector3.one * diameter, CFrame.new(position), color, material, {
		Shape = Enum.PartType.Ball,
	})
end

-- Cilindro em pé (o eixo do cilindro no Roblox é o X da part; giramos para apontar para cima).
local function uprightCylinder(
	parent: Instance,
	name: string,
	height: number,
	diameter: number,
	center: Vector3,
	color: Color3,
	material
)
	return block(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		material,
		{ Shape = Enum.PartType.Cylinder }
	)
end

-- Luz dentro de uma part invisível (a luz não fica presa dentro de uma part opaca).
local function lightAt(parent: Instance, name: string, cframe: CFrame, className: string, props: { [string]: any })
	local holder = block(parent, name, Vector3.one * 0.2, cframe, Color3.new(1, 1, 1), M.SmoothPlastic, {
		Transparency = 1,
		CastShadow = false,
	})
	local light = Instance.new(className)
	for key, value in props do
		light[key] = value
	end
	light.Parent = holder
	return light
end

local function newFrame(parent: Instance, props: { [string]: any }): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	for key, value in props do
		frame[key] = value
	end
	frame.Parent = parent
	return frame
end

local function roundCorners(parent: Instance, radius: UDim?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(1, 0)
	corner.Parent = parent
end

local function squareAspect(parent: Instance)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = parent
end

-- Estrutura -------------------------------------------------------------------------------------

local function buildShell(room: Model)
	local outerX = HALF_X + WALL
	local outerZ = HALF_Z + WALL
	local solid = { CanCollide = true }

	block(room, "Piso", Vector3.new(outerX * 2, 1, outerZ * 2), cf(0, -0.5, 0), C.floor, M.WoodPlanks, solid)
	block(room, "Teto", Vector3.new(outerX * 2, 1, outerZ * 2), cf(0, HEIGHT + 0.5, 0), C.plaster, M.Plaster, solid)

	-- Paredes de tijolo
	block(
		room,
		"Parede do fundo",
		Vector3.new(outerX * 2, HEIGHT, WALL),
		cf(0, HEIGHT / 2, -HALF_Z - WALL / 2),
		C.brick,
		M.Brick,
		solid
	)
	block(
		room,
		"Parede esquerda",
		Vector3.new(WALL, HEIGHT, HALF_Z * 2),
		cf(HALF_X + WALL / 2, HEIGHT / 2, 0),
		C.brick,
		M.Brick,
		solid
	)
	block(
		room,
		"Parede direita",
		Vector3.new(WALL, HEIGHT, HALF_Z * 2),
		cf(-HALF_X - WALL / 2, HEIGHT / 2, 0),
		C.brick,
		M.Brick,
		solid
	)

	-- Parede da janela (+Z): dois trechos cheios, peitoril e verga.
	local wallZ = HALF_Z + WALL / 2
	local leftStart = WINDOW_X1
	local leftEnd = outerX
	local rightStart = -outerX
	local rightEnd = WINDOW_X0
	block(
		room,
		"Parede da janela (esquerda)",
		Vector3.new(leftEnd - leftStart, HEIGHT, WALL),
		cf((leftStart + leftEnd) / 2, HEIGHT / 2, wallZ),
		C.brick,
		M.Brick,
		solid
	)
	block(
		room,
		"Parede da janela (direita)",
		Vector3.new(rightEnd - rightStart, HEIGHT, WALL),
		cf((rightStart + rightEnd) / 2, HEIGHT / 2, wallZ),
		C.brick,
		M.Brick,
		solid
	)
	local windowWidth = WINDOW_X1 - WINDOW_X0
	local windowCenterX = (WINDOW_X0 + WINDOW_X1) / 2
	block(
		room,
		"Peitoril",
		Vector3.new(windowWidth, WINDOW_Y0, WALL),
		cf(windowCenterX, WINDOW_Y0 / 2, wallZ),
		C.brick,
		M.Brick,
		solid
	)
	block(
		room,
		"Verga",
		Vector3.new(windowWidth, HEIGHT - WINDOW_Y1, WALL),
		cf(windowCenterX, (WINDOW_Y1 + HEIGHT) / 2, wallZ),
		C.brick,
		M.Brick,
		solid
	)

	-- Lambri de madeira nas paredes laterais
	for _, side in { 1, -1 } do
		block(
			room,
			"Lambri",
			Vector3.new(0.3, 4, HALF_Z * 2),
			cf(side * (HALF_X - 0.15), 2, 0),
			C.darkWood,
			M.WoodPlanks
		)
	end

	-- Vigas no teto (fazem sombra do lustre no teto)
	for _, z in { -8, 6, 18 } do
		block(room, "Viga", Vector3.new(HALF_X * 2, 1.2, 1.2), cf(0, HEIGHT - 0.6, z), C.beam, M.WoodPlanks)
	end
end

-- Janela enorme com grade de madeira (a luz do "sol" entra por ela e desenha a grade no chão).
local function buildWindow(room: Model)
	local wallZ = HALF_Z + WALL / 2
	local width = WINDOW_X1 - WINDOW_X0
	local height = WINDOW_Y1 - WINDOW_Y0
	local centerX = (WINDOW_X0 + WINDOW_X1) / 2
	local centerY = (WINDOW_Y0 + WINDOW_Y1) / 2

	block(room, "Vidro", Vector3.new(width, height, 0.2), cf(centerX, centerY, wallZ + 0.4), C.glass, M.Glass, {
		Transparency = 0.75,
		CastShadow = false,
		CanCollide = true,
	})

	-- Montantes verticais
	local columns = 6
	for index = 0, columns do
		local x = WINDOW_X0 + width * index / columns
		block(room, "Montante", Vector3.new(0.6, height, 0.7), cf(x, centerY, wallZ), C.windowWood, M.Wood)
	end
	-- Travessas horizontais
	for index = 0, 3 do
		local y = WINDOW_Y0 + height * index / 3
		block(room, "Travessa", Vector3.new(width + 0.6, 0.6, 0.7), cf(centerX, y, wallZ), C.windowWood, M.Wood)
	end

	-- Parapeito de mármore por dentro
	block(
		room,
		"Parapeito",
		Vector3.new(width + 1, 0.4, 1.6),
		cf(centerX, WINDOW_Y0 + 0.2, HALF_Z - 0.6),
		C.marble,
		M.Marble
	)

	-- Cortinas de tecido nas laterais
	for _, x in { WINDOW_X0 - 1.1, WINDOW_X1 + 1.1 } do
		block(
			room,
			"Cortina",
			Vector3.new(2.2, HEIGHT - 2.5, 0.6),
			cf(x, (HEIGHT - 1.5) / 2 + 1, HALF_Z - 0.6),
			C.curtain,
			M.Fabric
		)
	end
	block(
		room,
		"Bandô",
		Vector3.new(width + 5, 1.2, 0.8),
		cf(centerX, HEIGHT - 1.2, HALF_Z - 0.6),
		C.windowWood,
		M.Wood
	)

	-- "Sol": holofote do lado de fora apontando para o chão da sala através da grade.
	local sunPosition = at(centerX, 24, 36)
	local sunTarget = at(centerX, 0, 8)
	lightAt(room, "Luz do sol", CFrame.lookAt(sunPosition, sunTarget), "SpotLight", {
		Brightness = 6,
		Range = 60,
		Angle = 70,
		Color = C.sunLight,
		Shadows = true,
		Face = Enum.NormalId.Front,
	})
end

local function buildColumn(room: Model, x: number, z: number)
	local column = PartBuilder.model("Coluna", room)
	block(column, "Base", Vector3.new(3.4, 1, 3.4), cf(x, 0.5, z), C.marble, M.Marble)
	uprightCylinder(column, "Fuste", HEIGHT - 2, 2.4, at(x, HEIGHT / 2, z), C.marble, M.Marble)
	block(column, "Capitel", Vector3.new(3.4, 1, 3.4), cf(x, HEIGHT - 0.5, z), C.marble, M.Marble)
end

local function buildChandelier(room: Model, x: number, z: number)
	local chandelier = PartBuilder.model("Lustre", room)
	local hubY = 15
	local hub = at(x, hubY, z)
	local radius = 3.2

	block(
		chandelier,
		"Corrente",
		Vector3.new(0.25, HEIGHT - 1.2 - hubY, 0.25),
		cf(x, (hubY + HEIGHT - 1.2) / 2, z),
		C.gold,
		M.Metal
	)
	ball(chandelier, "Centro", 1.4, hub, C.gold, M.Metal)

	local segment = 2 * radius * math.sin(math.pi / 8)
	for index = 0, 7 do
		local angle = index * math.pi / 4
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local tip = hub + direction * radius
		block(
			chandelier,
			"Braço",
			Vector3.new(0.25, 0.25, radius),
			CFrame.lookAt(hub + direction * (radius / 2), tip),
			C.gold,
			M.Metal
		)
		block(
			chandelier,
			"Pires",
			Vector3.new(0.7, 0.2, 0.7),
			CFrame.new(tip + Vector3.new(0, 0.1, 0)),
			C.gold,
			M.Metal
		)
		block(
			chandelier,
			"Vela",
			Vector3.new(0.35, 1, 0.35),
			CFrame.new(tip + Vector3.new(0, 0.7, 0)),
			C.candle,
			M.SmoothPlastic
		)
		ball(chandelier, "Chama", 0.35, tip + Vector3.new(0, 1.35, 0), C.flame, M.Neon)

		local nextAngle = angle + math.pi / 4
		local midAngle = angle + math.pi / 8
		local mid = hub + Vector3.new(math.cos(midAngle), 0, math.sin(midAngle)) * (radius * math.cos(math.pi / 8))
		local nextTip = hub + Vector3.new(math.cos(nextAngle), 0, math.sin(nextAngle)) * radius
		block(chandelier, "Aro", Vector3.new(0.2, 0.2, segment), CFrame.lookAt(mid, nextTip), C.gold, M.Metal)
	end

	lightAt(chandelier, "Luz do lustre", cf(x, hubY - 1.1, z), "PointLight", {
		Brightness = 2.4,
		Range = 32,
		Color = C.warmLight,
		Shadows = true,
	})
end

local function buildRugAndTable(room: Model)
	block(room, "Borda do tapete", Vector3.new(19, 0.16, 14), cf(1, 0.08, 6), C.rugBorder, M.Carpet)
	block(room, "Tapete", Vector3.new(18, 0.2, 13), cf(1, 0.1, 6), C.rug, M.Carpet)

	local tableModel = PartBuilder.model("Mesa de centro", room)
	block(tableModel, "Tampo", Vector3.new(7, 0.6, 4), cf(1, 2.2, 6), C.granite, M.Granite, { CanCollide = true })
	for _, corner in { { -3, -1.6 }, { 3, -1.6 }, { -3, 1.6 }, { 3, 1.6 } } do
		block(
			tableModel,
			"Pé",
			Vector3.new(0.6, 1.9, 0.6),
			cf(1 + corner[1], 0.2 + 0.95, 6 + corner[2]),
			C.granite,
			M.Granite
		)
	end

	-- Pilha de livros e uma caixa de jogo com dois dados
	local bookTop = 2.5
	for index, color in { BOOK_COLORS[1], BOOK_COLORS[2], BOOK_COLORS[4] } do
		local height = 0.3
		block(
			tableModel,
			"Livro",
			Vector3.new(1.6, height, 2.2),
			cf(-1.2, bookTop + height / 2, 6.2) * CFrame.Angles(0, math.rad(index * 9), 0),
			color,
			M.Leather
		)
		bookTop += height
	end
	block(tableModel, "Caixa do jogo", Vector3.new(2.6, 0.4, 2.6), cf(2.4, 2.7, 5.6), C.shelf, M.WoodPlanks)
	block(
		tableModel,
		"Dado",
		Vector3.new(0.5, 0.5, 0.5),
		cf(2.0, 3.15, 5.2) * CFrame.Angles(0, math.rad(20), 0),
		C.candle,
		M.SmoothPlastic
	)
	block(
		tableModel,
		"Dado",
		Vector3.new(0.5, 0.5, 0.5),
		cf(2.9, 3.15, 6.0) * CFrame.Angles(0, math.rad(-35), 0),
		C.candle,
		M.SmoothPlastic
	)
end

-- Sofá de tecido encostado no lado +X, virado para o centro (-X).
local function buildSofa(room: Model)
	local sofa = PartBuilder.model("Sofá", room)
	local x0, x1 = 12, 17
	local z0, z1 = 0, 12
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local depth, length = x1 - x0, z1 - z0

	for _, corner in { { x0 + 0.4, z0 + 0.4 }, { x1 - 0.4, z0 + 0.4 }, { x0 + 0.4, z1 - 0.4 }, { x1 - 0.4, z1 - 0.4 } } do
		block(sofa, "Pé", Vector3.new(0.5, 0.5, 0.5), cf(corner[1], 0.25, corner[2]), C.darkWood, M.Wood)
	end
	block(sofa, "Estrutura", Vector3.new(depth, 1.2, length), cf(cx, 1.1, cz), C.sofa, M.Fabric, { CanCollide = true })
	block(sofa, "Encosto", Vector3.new(1.2, 3.2, length), cf(x1 - 0.6, 3.3, cz), C.sofa, M.Fabric)
	for _, z in { z0 + 0.5, z1 - 0.5 } do
		block(sofa, "Braço", Vector3.new(depth, 2.4, 1), cf(cx, 1.7, z), C.sofa, M.Fabric)
	end
	for _, z in { 2.7, 6, 9.3 } do
		block(sofa, "Almofada", Vector3.new(3.6, 0.7, 3.2), cf(cx - 0.5, 2.05, z), C.sofaCushion, M.Fabric)
	end
	for _, z in { 2.4, 9.6 } do
		block(
			sofa,
			"Almofada decorativa",
			Vector3.new(0.8, 1.8, 1.8),
			cf(x1 - 1.6, 3.2, z) * CFrame.Angles(0, 0, math.rad(-12)),
			C.pillow,
			M.Fabric
		)
	end
end

-- Poltrona de tecido do lado -X, virada para a mesa (+X).
local function buildArmchair(room: Model)
	local chair = PartBuilder.model("Poltrona", room)
	local x, z = -8, 5
	block(chair, "Estrutura", Vector3.new(4, 1.2, 4.4), cf(x, 1.1, z), C.armchair, M.Fabric, { CanCollide = true })
	block(chair, "Encosto", Vector3.new(1, 3.4, 4.4), cf(x - 1.5, 3.4, z), C.armchair, M.Fabric)
	for _, side in { -1, 1 } do
		block(chair, "Braço", Vector3.new(4, 2.2, 0.8), cf(x, 1.6, z + side * 2.2), C.armchair, M.Fabric)
	end
	block(chair, "Almofada", Vector3.new(3, 0.6, 3.6), cf(x + 0.3, 2, z), C.pillow, M.Fabric)
	for _, offset in { { -1.6, -1.8 }, { 1.6, -1.8 }, { -1.6, 1.8 }, { 1.6, 1.8 } } do
		block(chair, "Pé", Vector3.new(0.4, 0.5, 0.4), cf(x + offset[1], 0.25, z + offset[2]), C.darkWood, M.Wood)
	end
end

local function buildFloorLamp(room: Model, x: number, z: number)
	local lamp = PartBuilder.model("Luminária", room)
	uprightCylinder(lamp, "Base", 0.3, 2, at(x, 0.15, z), C.lampMetal, M.Metal)
	block(lamp, "Haste", Vector3.new(0.3, 8.6, 0.3), cf(x, 4.6, z), C.lampMetal, M.Metal)
	block(lamp, "Cúpula", Vector3.new(2.6, 1.8, 2.6), cf(x, 9.6, z), C.lampShade, M.Fabric)
	lightAt(lamp, "Lâmpada", cf(x, 8.5, z), "SpotLight", {
		Brightness = 2,
		Range = 18,
		Angle = 110,
		Color = C.warmLight,
		Shadows = true,
		Face = Enum.NormalId.Bottom,
	})
end

local function buildVase(room: Model, x: number, z: number)
	local vase = PartBuilder.model("Vaso", room)
	uprightCylinder(vase, "Vaso", 2.6, 2.6, at(x, 1.3, z), C.pot, M.Sandstone)
	uprightCylinder(vase, "Terra", 0.2, 2.3, at(x, 2.55, z), C.soil, M.Ground)
	ball(vase, "Folhagem", 3.4, at(x, 3.9, z), C.leaves, M.Grass)
	ball(vase, "Folhagem", 2.2, at(x + 1, 4.9, z - 0.6), C.leaves, M.Grass)
	ball(vase, "Folhagem", 2, at(x - 0.9, 5.1, z + 0.5), C.leaves, M.Grass)
end

local function buildBookshelf(room: Model)
	local shelf = PartBuilder.model("Estante", room)
	local x0, x1 = 22, 27.8
	local z0, z1 = 19, 22
	local height = 15
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local width, depth = x1 - x0, z1 - z0

	block(shelf, "Fundo", Vector3.new(width, height, 0.3), cf(cx, height / 2, z1 - 0.15), C.shelf, M.WoodPlanks)
	for _, x in { x0 + 0.25, x1 - 0.25 } do
		block(shelf, "Lateral", Vector3.new(0.5, height, depth), cf(x, height / 2, cz), C.shelf, M.WoodPlanks)
	end
	block(shelf, "Topo", Vector3.new(width, 0.5, depth), cf(cx, height - 0.25, cz), C.shelf, M.WoodPlanks)

	local random = Random.new(1995)
	local shelfYs = { 0.2, 3.7, 7.2, 10.7 }
	for _, y in shelfYs do
		block(shelf, "Prateleira", Vector3.new(width - 1, 0.4, depth - 0.3), cf(cx, y, cz), C.shelf, M.WoodPlanks)
		local base = y + 0.2
		local x = x0 + 0.65
		local limit = x1 - 0.65
		while x < limit - 0.3 do
			local bookWidth = random:NextNumber(0.35, 0.6)
			if x + bookWidth > limit then
				break
			end
			local bookHeight = random:NextNumber(2, 2.8)
			local color = BOOK_COLORS[random:NextInteger(1, #BOOK_COLORS)]
			local material = random:NextNumber() < 0.6 and M.Leather or M.Fabric
			block(
				shelf,
				"Livro",
				Vector3.new(bookWidth, bookHeight, 2.2),
				cf(x + bookWidth / 2, base + bookHeight / 2, cz - 0.1),
				color,
				material
			)
			x += bookWidth + 0.05
			-- De vez em quando um vão (deixa a prateleira menos "perfeita")
			if random:NextNumber() < 0.12 then
				x += 0.5
			end
		end
	end
	-- Globo em cima da estante
	ball(shelf, "Globo", 1.6, at(cx, height + 0.8, cz), Color3.fromRGB(70, 120, 160), M.SmoothPlastic)
end

-- Quadro: moldura dourada + tela com SurfaceGui. A camada "Detalhes" (TextureDetail) some com a redução
-- de texturas e sobra só a base de duas cores chapadas.
local function buildPainting(room: Model)
	local painting = PartBuilder.model("Quadro", room)
	local cx, cy = 18.5, 9
	local width, height = 5, 3.8
	local z = HALF_Z - 0.25
	local border = 0.45

	local canvas = block(painting, "Tela", Vector3.new(width, height, 0.1), cf(cx, cy, z), C.plaster, M.SmoothPlastic)
	block(
		painting,
		"Moldura",
		Vector3.new(width + border * 2, border, 0.4),
		cf(cx, cy + height / 2 + border / 2, z - 0.1),
		C.gold,
		M.Wood
	)
	block(
		painting,
		"Moldura",
		Vector3.new(width + border * 2, border, 0.4),
		cf(cx, cy - height / 2 - border / 2, z - 0.1),
		C.gold,
		M.Wood
	)
	for _, side in { -1, 1 } do
		block(
			painting,
			"Moldura",
			Vector3.new(border, height, 0.4),
			cf(cx + side * (width / 2 + border / 2), cy, z - 0.1),
			C.gold,
			M.Wood
		)
	end

	-- Arandela de quadro (luz com sombra: a moldura projeta sombra na parede)
	local lightY = cy + height / 2 + border + 0.6
	block(painting, "Arandela", Vector3.new(3, 0.3, 0.6), cf(cx, lightY, z - 0.5), C.gold, M.Metal)
	lightAt(painting, "Luz do quadro", cf(cx, lightY - 0.3, z - 1.2), "PointLight", {
		Brightness = 1.4,
		Range = 9,
		Color = C.warmLight,
		Shadows = true,
	})

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Pintura"
	gui.Face = Enum.NormalId.Front -- a tela não é girada: Front aponta para -Z, para dentro da sala
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 1
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = canvas

	-- Base chapada (o que sobra com texturas reduzidas)
	newFrame(gui, {
		Name = "BaseCeu",
		Size = UDim2.fromScale(1, 0.58),
		BackgroundColor3 = Color3.fromRGB(128, 176, 204),
		ZIndex = 1,
	})
	newFrame(gui, {
		Name = "BaseChao",
		Position = UDim2.fromScale(0, 0.58),
		Size = UDim2.fromScale(1, 0.42),
		BackgroundColor3 = Color3.fromRGB(62, 112, 58),
		ZIndex = 1,
	})

	local detail = newFrame(gui, {
		Name = "Detalhes",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	detail:SetAttribute("TextureDetail", true)

	-- Céu de fim de tarde
	local sky = newFrame(detail, {
		Name = "Ceu",
		Size = UDim2.fromScale(1, 0.62),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 1,
	})
	local skyGradient = Instance.new("UIGradient")
	skyGradient.Rotation = 90
	skyGradient.Color = ColorSequence.new(Color3.fromRGB(86, 136, 196), Color3.fromRGB(250, 186, 116))
	skyGradient.Parent = sky

	local sun = newFrame(detail, {
		Name = "Sol",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.7, 0.3),
		Size = UDim2.fromScale(0.16, 0.16),
		BackgroundColor3 = Color3.fromRGB(255, 226, 130),
		ZIndex = 2,
	})
	squareAspect(sun)
	roundCorners(sun)

	-- Montanhas (quadrados girados; a metade de baixo fica atrás da mata)
	for _, mountain in
		{
			{ 0.14, 0.62, 0.5, Color3.fromRGB(70, 96, 122) },
			{ 0.46, 0.64, 0.62, Color3.fromRGB(84, 110, 134) },
			{ 0.86, 0.62, 0.46, Color3.fromRGB(64, 90, 116) },
		}
	do
		local peak = newFrame(detail, {
			Name = "Montanha",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(mountain[1], mountain[2]),
			Size = UDim2.fromScale(mountain[3], mountain[3]),
			Rotation = 45,
			BackgroundColor3 = mountain[4],
			ZIndex = 3,
		})
		squareAspect(peak)
	end

	-- Mata
	local ground = newFrame(detail, {
		Name = "Mata",
		Position = UDim2.fromScale(0, 0.6),
		Size = UDim2.fromScale(1, 0.4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 4,
	})
	local groundGradient = Instance.new("UIGradient")
	groundGradient.Rotation = 90
	groundGradient.Color = ColorSequence.new(Color3.fromRGB(58, 120, 54), Color3.fromRGB(30, 70, 34))
	groundGradient.Parent = ground

	-- Rio
	newFrame(detail, {
		Name = "Rio",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.42, 0.86),
		Size = UDim2.fromScale(0.62, 0.08),
		Rotation = -10,
		BackgroundColor3 = Color3.fromRGB(92, 152, 192),
		ZIndex = 5,
	})
	newFrame(detail, {
		Name = "Rio",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.66, 0.7),
		Size = UDim2.fromScale(0.34, 0.045),
		Rotation = 7,
		BackgroundColor3 = Color3.fromRGB(110, 166, 200),
		ZIndex = 5,
	})

	-- Palmeiras
	local function palm(x: number, baseY: number, trunkHeight: number)
		newFrame(detail, {
			Name = "Tronco",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(x, baseY),
			Size = UDim2.fromScale(0.02, trunkHeight),
			BackgroundColor3 = Color3.fromRGB(96, 66, 40),
			ZIndex = 6,
		})
		for _, leafAngle in { -150, -110, -70, -30, 10 } do
			local radians = math.rad(leafAngle)
			local leaf = newFrame(detail, {
				Name = "Folha",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(
					x + math.cos(radians) * 0.05,
					baseY - trunkHeight + math.sin(radians) * 0.05
				),
				Size = UDim2.fromScale(0.13, 0.04),
				Rotation = leafAngle,
				BackgroundColor3 = Color3.fromRGB(44, 124, 52),
				ZIndex = 7,
			})
			roundCorners(leaf)
		end
	end
	palm(0.12, 0.95, 0.5)
	palm(0.22, 0.9, 0.38)
	palm(0.88, 0.96, 0.46)

	-- Tambores em primeiro plano
	local function drum(x: number, scale: number)
		newFrame(detail, {
			Name = "Tambor",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(x, 0.97),
			Size = UDim2.fromScale(0.11 * scale, 0.16 * scale),
			BackgroundColor3 = Color3.fromRGB(140, 72, 40),
			ZIndex = 8,
		})
		for _, offset in { 0.04, 0.11 } do
			newFrame(detail, {
				Name = "Faixa",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(x, 0.97 - offset * scale),
				Size = UDim2.fromScale(0.11 * scale, 0.012),
				BackgroundColor3 = Color3.fromRGB(214, 170, 72),
				ZIndex = 9,
			})
		end
		local top = newFrame(detail, {
			Name = "Pele",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, 0.97 - 0.16 * scale),
			Size = UDim2.fromScale(0.115 * scale, 0.05 * scale),
			BackgroundColor3 = Color3.fromRGB(232, 210, 170),
			ZIndex = 9,
		})
		roundCorners(top)
	end
	drum(0.56, 1)
	drum(0.68, 0.75)

	-- Pinceladas (a "textura" da tela)
	local random = Random.new(42)
	for _ = 1, 26 do
		local y = random:NextNumber(0.03, 0.95)
		local base = y < 0.6 and Color3.fromRGB(240, 200, 150) or Color3.fromRGB(90, 150, 70)
		local stroke = newFrame(detail, {
			Name = "Pincelada",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(random:NextNumber(0.03, 0.97), y),
			Size = UDim2.fromScale(random:NextNumber(0.04, 0.12), random:NextNumber(0.01, 0.025)),
			Rotation = random:NextNumber(-25, 25),
			BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), random:NextNumber(0, 0.3)),
			BackgroundTransparency = random:NextNumber(0.45, 0.7),
			ZIndex = 10,
		})
		roundCorners(stroke)
	end
end

local function buildRoom(root: Model): Model
	local room = PartBuilder.model("Sala", root) :: Model
	PartBuilder.tag(room, Tags.CullChunk)

	buildShell(room)
	buildWindow(room)
	buildColumn(room, -12, 9)
	buildColumn(room, -18.3, 19.5)
	buildColumn(room, 14.3, 19.5)
	buildChandelier(room, 1, 6)
	buildRugAndTable(room)
	buildSofa(room)
	buildArmchair(room)
	buildFloorLamp(room, 19, 6.5)
	buildFloorLamp(room, -10.5, 13)
	buildVase(room, -15, 15)
	buildBookshelf(room)
	buildPainting(room)

	-- Luz de preenchimento sem sombra (evita cantos totalmente escuros)
	lightAt(room, "Luz ambiente", cf(0, HEIGHT - 2.5, -6), "PointLight", {
		Brightness = 0.5,
		Range = 40,
		Color = C.warmLight,
		Shadows = false,
	})

	room.WorldPivot = cf(0, 0, 0)
	return room
end

-- Pista externa ---------------------------------------------------------------------------------

local function buildTrack(root: Model)
	local track = PartBuilder.model("Pista", root) :: Model
	local startZ = HALF_Z + WALL
	local length = TRACK_END_Z - startZ

	-- Gramado largo (2000 x 1640: dentro do limite de 2048 por eixo) para o horizonte não ter "borda".
	block(
		track,
		"Gramado",
		Vector3.new(2000, 2, length),
		cf(0, GROUND_TOP - 1, startZ + length / 2),
		C.grassField,
		M.Grass,
		{ CanCollide = true }
	)

	-- Pista de terra em pedaços iguais de no máximo TRACK_SEGMENT studs
	local count = math.ceil(length / TRACK_SEGMENT)
	local segmentLength = length / count
	for index = 1, count do
		local z = startZ + segmentLength * (index - 0.5)
		block(
			track,
			"Pista " .. index,
			Vector3.new(TRACK_HALF_WIDTH * 2, 1, segmentLength),
			cf(0, TRACK_TOP - 0.5, z),
			index % 2 == 0 and C.trackAlt or C.track,
			M.Ground,
			{ CanCollide = true }
		)
	end

	-- Faixas brancas atravessando a pista na distância de cada marco
	for _, info in MARKERS do
		block(
			track,
			("Faixa %d studs"):format(info.distance),
			Vector3.new(TRACK_HALF_WIDTH * 2, 0.12, 1.6 * info.scale),
			cf(0, TRACK_TOP + 0.06, CAMERA_LOCAL.Z + info.distance),
			C.stripe,
			M.SmoothPlastic
		)
	end
	return track
end

local function buildMarker(root: Model, info)
	local s = info.scale
	local x = info.x
	local z = CAMERA_LOCAL.Z + info.distance
	local outward = x >= 0 and 1 or -1 -- a árvore fica do lado de fora; a placa, do lado da pista

	local model = PartBuilder.model(("Marco %d studs"):format(info.distance), root) :: Model
	PartBuilder.tag(model, Tags.CullChunk)

	local base = GROUND_TOP
	local bright = info.color:Lerp(Color3.new(1, 1, 1), 0.35)

	block(model, "Base", Vector3.new(6 * s, s, 6 * s), cf(x, base + s / 2, z), C.plinth, M.Concrete)
	block(
		model,
		"Pilar",
		Vector3.new(2.6 * s, 14 * s, 2.6 * s),
		cf(x, base + s + 7 * s, z),
		info.color,
		M.SmoothPlastic
	)
	block(model, "Faixa", Vector3.new(2.9 * s, s, 2.9 * s), cf(x, base + s + 10.5 * s, z), bright, M.Neon)
	ball(model, "Topo", 4 * s, at(x, base + s + 14 * s + 1.6 * s, z), bright, M.Neon)

	local treeX = x + outward * 5 * s
	block(model, "Tronco", Vector3.new(0.9 * s, 7 * s, 0.9 * s), cf(treeX, base + 3.5 * s, z), C.darkWood, M.Wood)
	ball(model, "Copa", 6 * s, at(treeX, base + 9 * s, z), info.color:Lerp(C.leaves, 0.55), M.Grass)

	local signX = x - outward * 4.6 * s
	block(
		model,
		"Poste da placa",
		Vector3.new(0.5 * s, 3.2 * s, 0.5 * s),
		cf(signX, base + 1.6 * s, z),
		C.darkWood,
		M.Wood
	)
	local board = block(
		model,
		"Placa",
		Vector3.new(4.6 * s, 2.2 * s, 0.35 * s),
		cf(signX, base + 3.2 * s, z - 0.4 * s),
		info.color,
		M.WoodPlanks
	)

	-- Texto com tamanho fixo em pixels: dá para ler mesmo a 1500 studs.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Distancia"
	billboard.Size = UDim2.fromOffset(150, 42)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 5000
	billboard.AlwaysOnTop = false
	billboard.Parent = board
	local back = newFrame(billboard, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 16, 12),
		BackgroundTransparency = 0.25,
	})
	roundCorners(back, UDim.new(0, 8))
	local stroke = Instance.new("UIStroke")
	stroke.Color = info.color
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = back
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.BuilderSansBold
	label.TextSize = 24
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = ("%d studs"):format(info.distance)
	label.Parent = back

	model.WorldPivot = cf(x, base, z)
end

-- API -------------------------------------------------------------------------------------------

function DemoRoom.Build(): Model
	local old = workspace:FindFirstChild("SalaDemonstracao")
	if old then
		old:Destroy()
	end

	local root = PartBuilder.model("SalaDemonstracao") :: Model
	-- Com streaming ligado, a sala e a pista precisam existir no cliente mesmo longe do personagem.
	root.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	buildRoom(root)
	buildTrack(root)
	for _, info in MARKERS do
		buildMarker(root, info)
	end
	root.WorldPivot = cf(0, 0, 0)
	root.Parent = workspace

	-- Marcador da câmera
	local markers = workspace:FindFirstChild("LobbyMarkers")
	if not markers then
		markers = Instance.new("Folder")
		markers.Name = "LobbyMarkers"
		markers.Parent = workspace
	end
	local previous = markers:FindFirstChild("DemoCamera")
	if previous then
		previous:Destroy()
	end

	local eye = at(CAMERA_LOCAL.X, CAMERA_LOCAL.Y, CAMERA_LOCAL.Z)
	local direction = Vector3.new(
		-math.sin(CAMERA_YAW) * math.cos(CAMERA_PITCH),
		math.sin(CAMERA_PITCH),
		math.cos(CAMERA_YAW) * math.cos(CAMERA_PITCH)
	)
	local cameraCFrame = CFrame.lookAt(eye, eye + direction)
	PartBuilder.part({
		Name = "DemoCamera",
		Size = Vector3.one,
		CFrame = cameraCFrame,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = markers,
	})
	markers:SetAttribute("DemoCameraCFrame", cameraCFrame)

	-- Boneco do jogador na sala (cópia local do personagem, ver MenuPuppet): no tapete, virado de lado
	-- para a câmera. O CFrame marca o chão sob os pés.
	local previousCharacter = markers:FindFirstChild("DemoCharacter")
	if previousCharacter then
		previousCharacter:Destroy()
	end
	local characterCFrame = CFrame.lookAt(at(-5, 0, -4), at(4, 0, -16))
	PartBuilder.part({
		Name = "DemoCharacter",
		Size = Vector3.one,
		CFrame = characterCFrame,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = markers,
	})
	markers:SetAttribute("DemoCharacterCFrame", characterCFrame)

	return root
end

return DemoRoom
