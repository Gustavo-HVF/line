--!nonstrict
-- Cenários do lobby, todos gerados por código:
--   * Sótão do menu (GameConfig.MENU_AREA_ORIGIN): estúdio antigo e escuro, mesa com a réplica do tabuleiro,
--     dois tambores, velas, estantes, baú e cipós da selva entrando por uma janela quebrada.
--   * Cubículo fechado ATRÁS da câmera do menu com o SpawnLocation (os personagens não aparecem no menu).
--   * Hub multiplayer (GameConfig.HUB_ORIGIN): salão de um templo na selva com colunas, tochas,
--     estátua do tabuleiro no centro, cipós e uma cachoeira decorativa.
-- Também cria workspace.LobbyMarkers com MenuCamera, MenuSpawn, HubSpawn e HubCamera.
-- Nada é construído perto de GameConfig.DEMO_ROOM_ORIGIN (a sala de demonstração fica lá).
--
-- Luzes que o cliente anima (LobbyAmbience): atributo "Flicker" (tremulação de vela/tocha) ou "Pulse"
-- (brilho mágico lento), ambos com a amplitude (0..1), e "BaseBrightness" com o brilho original.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local PartBuilder = require(ReplicatedStorage.Shared.Util.PartBuilder)

local LobbyWorld = {}

local WORLD_FOLDER = "LobbyWorld"
local MARKERS_FOLDER = "LobbyMarkers"

local Material = Enum.Material
local CYLINDER = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- deixa o eixo do cilindro (X) na vertical
local TAU = math.pi * 2

local C = {
	-- sótão
	FloorWood = Color3.fromRGB(78, 54, 36),
	WallWood = Color3.fromRGB(62, 44, 31),
	Beam = Color3.fromRGB(44, 30, 20),
	TableWood = Color3.fromRGB(94, 61, 36),
	DarkWood = Color3.fromRGB(54, 34, 20),
	Brass = Color3.fromRGB(176, 136, 62),
	Iron = Color3.fromRGB(58, 56, 54),
	Wax = Color3.fromRGB(236, 226, 200),
	Wick = Color3.fromRGB(30, 24, 20),
	Flame = Color3.fromRGB(255, 176, 72),
	CandleLight = Color3.fromRGB(255, 166, 92),
	WindowLight = Color3.fromRGB(255, 170, 126),
	Glass = Color3.fromRGB(170, 210, 200),
	RugRed = Color3.fromRGB(108, 30, 28),
	RugGold = Color3.fromRGB(150, 104, 40),
	Sheet = Color3.fromRGB(196, 188, 170),
	Crate = Color3.fromRGB(110, 78, 46),
	-- selva
	Vine = Color3.fromRGB(62, 86, 36),
	Trunk = Color3.fromRGB(52, 38, 28),
	Canopy = Color3.fromRGB(38, 62, 34),
	JungleGround = Color3.fromRGB(36, 54, 32),
	-- templo
	StoneFloor = Color3.fromRGB(98, 100, 90),
	StonePath = Color3.fromRGB(78, 80, 70),
	StonePlaza = Color3.fromRGB(116, 110, 92),
	StoneWall = Color3.fromRGB(88, 96, 78),
	StoneDark = Color3.fromRGB(70, 74, 64),
	StoneColumn = Color3.fromRGB(146, 142, 122),
	Moss = Color3.fromRGB(66, 96, 48),
	TorchWood = Color3.fromRGB(70, 46, 28),
	TorchLight = Color3.fromRGB(255, 150, 70),
	Water = Color3.fromRGB(110, 180, 205),
	PoolWater = Color3.fromRGB(60, 130, 140),
	PoolBed = Color3.fromRGB(30, 56, 60),
	Rune = Color3.fromRGB(60, 230, 120),
}

local LEAF_COLORS = {
	Color3.fromRGB(58, 112, 40),
	Color3.fromRGB(44, 92, 34),
	Color3.fromRGB(78, 128, 46),
}

local BOOK_COLORS = {
	Color3.fromRGB(110, 34, 30),
	Color3.fromRGB(40, 70, 44),
	Color3.fromRGB(42, 52, 86),
	Color3.fromRGB(120, 86, 40),
	Color3.fromRGB(78, 50, 32),
	Color3.fromRGB(150, 128, 92),
}

-- Estilos do tabuleiro decorativo (madeira no sótão, pedra na estátua do hub).
local WOOD_BOARD = {
	name = "ReplicaTabuleiro",
	body = Color3.fromRGB(64, 40, 22),
	bodyMaterial = Material.Wood,
	panel = Color3.fromRGB(118, 80, 46),
	panelMaterial = Material.Wood,
	trim = Color3.fromRGB(176, 136, 62),
	trimMaterial = Material.Metal,
	tiles = { Color3.fromRGB(46, 84, 44), Color3.fromRGB(214, 196, 150), Color3.fromRGB(166, 108, 44) },
	glow = Color3.fromRGB(60, 230, 120),
	glass = Color3.fromRGB(90, 200, 130),
	piece = Color3.fromRGB(226, 214, 186),
	lightRange = 9,
	lightBrightness = 1.5,
	collide = false,
}

local STONE_BOARD = {
	name = "TabuleiroDePedra",
	body = Color3.fromRGB(108, 108, 94),
	bodyMaterial = Material.Slate,
	panel = Color3.fromRGB(136, 132, 112),
	panelMaterial = Material.Limestone,
	trim = Color3.fromRGB(150, 118, 58),
	trimMaterial = Material.CorrodedMetal,
	tiles = { Color3.fromRGB(70, 102, 56), Color3.fromRGB(176, 168, 140), Color3.fromRGB(140, 100, 52) },
	glow = Color3.fromRGB(60, 230, 120),
	glass = Color3.fromRGB(90, 200, 130),
	piece = Color3.fromRGB(176, 170, 150),
	lightRange = 24,
	lightBrightness = 2.2,
	collide = true,
}

local WOOD_DRUM = {
	body = Color3.fromRGB(128, 74, 40),
	material = Material.Wood,
	hide = Color3.fromRGB(226, 206, 168),
	hideMaterial = Material.Fabric,
	rim = Color3.fromRGB(60, 36, 20),
	cord = Color3.fromRGB(214, 192, 150),
	cords = 7,
	collide = false,
}

local STONE_DRUM = {
	body = Color3.fromRGB(120, 118, 102),
	material = Material.Slate,
	hide = Color3.fromRGB(150, 144, 120),
	hideMaterial = Material.Limestone,
	rim = Color3.fromRGB(78, 80, 68),
	cord = Color3.fromRGB(0, 0, 0),
	cords = 0,
	collide = true,
}

local yieldStep: () -> () = function() end

-- Construção básica ------------------------------------------------------------------------------------

local function merge(base: { [string]: any }, extra: { [string]: any }?): { [string]: any }
	if extra then
		for key, value in extra do
			base[key] = value
		end
	end
	return base
end

-- Part sólida (colide). Use `extra` para Shape, Transparency, CastShadow, CanCollide etc.
local function makePart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	extra: { [string]: any }?
): BasePart
	local props = merge({
		Name = name,
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material,
		CanTouch = false,
	}, extra)
	props.Parent = parent
	local part = PartBuilder.part(props)
	if not part.CanCollide then
		part.CanQuery = false
	end
	yieldStep()
	return part
end

-- Part decorativa (não colide nem entra em raycasts).
local function deco(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	extra: { [string]: any }?
): BasePart
	return makePart(parent, name, size, cframe, color, material, merge({ CanCollide = false }, extra))
end

-- Cilindro em pé com o centro em `center`.
local function cylinder(
	parent: Instance,
	name: string,
	center: Vector3,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material,
	extra: { [string]: any }?
): BasePart
	return makePart(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(center) * UPRIGHT,
		color,
		material,
		merge({ Shape = CYLINDER }, extra)
	)
end

-- Cilindro decorativo ligando dois pontos (cipós, cordas, suportes).
local function segment(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	thickness: number,
	color: Color3,
	material: Enum.Material,
	extra: { [string]: any }?
): BasePart?
	local delta = b - a
	local length = delta.Magnitude
	if length < 0.01 then
		return nil
	end
	local direction = delta / length
	local up = math.abs(direction.Y) > 0.98 and Vector3.xAxis or Vector3.yAxis
	-- lookAt aponta -Z para b; girar 90° em Y leva o eixo X do cilindro para essa direção
	local cframe = CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.pi / 2, 0)
	return makePart(
		parent,
		name,
		Vector3.new(length + thickness * 0.6, thickness, thickness),
		cframe,
		color,
		material,
		merge({ Shape = CYLINDER, CanCollide = false }, extra)
	)
end

local function ball(
	parent: Instance,
	name: string,
	center: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material,
	extra: { [string]: any }?
): BasePart
	return makePart(
		parent,
		name,
		Vector3.one * diameter,
		CFrame.new(center),
		color,
		material,
		merge({ Shape = BALL, CanCollide = false }, extra)
	)
end

local function addPointLight(
	part: BasePart,
	color: Color3,
	brightness: number,
	range: number,
	shadows: boolean,
	flicker: number?,
	pulse: number?
): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = shadows
	light:SetAttribute("BaseBrightness", brightness)
	if flicker then
		light:SetAttribute("Flicker", flicker)
	end
	if pulse then
		light:SetAttribute("Pulse", pulse)
	end
	light.Parent = part
	return light
end

local function numberSequence(points: { { number } }): NumberSequence
	local keypoints = {}
	for _, point in points do
		table.insert(keypoints, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(keypoints)
end

-- Peças reutilizáveis -----------------------------------------------------------------------------------

local function leaf(parent: Instance, position: Vector3, rng: Random, scale: number, shadows: boolean)
	local cframe = CFrame.new(position)
		* CFrame.Angles(rng:NextNumber(-1.1, 1.1), rng:NextNumber(0, TAU), rng:NextNumber(-1.1, 1.1))
		* CFrame.new(0.3 * scale, 0, 0)
	deco(
		parent,
		"Folha",
		Vector3.new(0.9, 0.06, 0.5) * scale,
		cframe,
		LEAF_COLORS[rng:NextInteger(1, #LEAF_COLORS)],
		Material.LeafyGrass,
		{ CastShadow = shadows }
	)
end

-- Cipó passando pelos pontos, com folhas ao longo de cada trecho.
local function vine(
	parent: Instance,
	points: { Vector3 },
	thickness: number,
	rng: Random,
	leavesPerSegment: number,
	leafScale: number,
	shadows: boolean
)
	local model = PartBuilder.model("Cipo", parent)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		segment(model, "Ramo", a, b, thickness, C.Vine, Material.Grass, { CastShadow = shadows })
		for j = 1, leavesPerSegment do
			leaf(model, a:Lerp(b, (j - 0.5) / leavesPerSegment), rng, leafScale, shadows)
		end
	end
end

-- Cipó pendurado a partir de `top`, balançando um pouco.
local function hangingVine(parent: Instance, top: Vector3, length: number, rng: Random)
	local segments = math.max(3, math.floor(length / 2.4))
	local step = length / segments
	local phase = rng:NextNumber(0, TAU)
	local points = { top }
	for k = 1, segments do
		table.insert(
			points,
			top + Vector3.new(math.sin(phase + k * 0.9) * 0.5, -k * step, math.cos(phase + k * 0.7) * 0.35)
		)
	end
	vine(parent, points, 0.24, rng, 1, 1.4, false)
end

local function candle(parent: Instance, base: Vector3, height: number): BasePart
	cylinder(
		parent,
		"Vela",
		base + Vector3.new(0, height / 2, 0),
		height,
		0.3,
		C.Wax,
		Material.SmoothPlastic,
		{ CanCollide = false, CastShadow = false }
	)
	deco(
		parent,
		"Pavio",
		Vector3.new(0.03, 0.1, 0.03),
		CFrame.new(base + Vector3.new(0, height + 0.05, 0)),
		C.Wick,
		Material.SmoothPlastic,
		{ CastShadow = false }
	)
	local flame = deco(
		parent,
		"Chama",
		Vector3.new(0.14, 0.32, 0.14),
		CFrame.new(base + Vector3.new(0, height + 0.22, 0)),
		C.Flame,
		Material.Neon,
		{ CastShadow = false }
	)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = flame
	return flame
end

-- Grupo de velas num pires; a mais alta leva a luz.
local function candleCluster(
	parent: Instance,
	base: Vector3,
	heights: { number },
	range: number,
	brightness: number,
	shadows: boolean
)
	local model = PartBuilder.model("Velas", parent)
	cylinder(
		model,
		"Pires",
		base + Vector3.new(0, 0.04, 0),
		0.08,
		1.3,
		C.Brass,
		Material.Metal,
		{ CanCollide = false, CastShadow = false }
	)
	local offsets = { Vector3.new(0, 0, 0), Vector3.new(0.42, 0, 0.22), Vector3.new(-0.36, 0, 0.3) }
	local lightFlame = nil
	for index, height in heights do
		local flame = candle(model, base + (offsets[index] or Vector3.zero) + Vector3.new(0, 0.08, 0), height)
		lightFlame = lightFlame or flame
	end
	if lightFlame then
		addPointLight(lightFlame, C.CandleLight, brightness, range, shadows, 0.3)
	end
end

-- Réplica do tabuleiro amaldiçoado. `base` é o centro da face de baixo; `s` é a escala.
-- Retorna a part do brilho verde central.
local function boardReplica(parent: Instance, base: CFrame, s: number, style): BasePart
	local model = PartBuilder.model(style.name, parent)
	local function lp(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x * s, y * s, z * s)
	end
	local W, D, H = 4.6, 3.4, 0.55
	local noCollide = { CanCollide = false }
	local flat = { CanCollide = false, CastShadow = false }

	makePart(
		model,
		"Caixa",
		Vector3.new(W, H, D) * s,
		lp(0, H / 2, 0),
		style.body,
		style.bodyMaterial,
		{ CanCollide = style.collide }
	)
	for _, side in { -1, 1 } do
		deco(
			model,
			"Metade",
			Vector3.new(2.15, 0.08, 3.1) * s,
			lp(side * 1.13, H + 0.04, 0),
			style.panel,
			style.panelMaterial,
			flat
		)
		deco(
			model,
			"Friso",
			Vector3.new(W + 0.06, 0.14, 0.14) * s,
			lp(0, H - 0.03, side * D / 2),
			style.trim,
			style.trimMaterial,
			noCollide
		)
		deco(
			model,
			"Friso",
			Vector3.new(0.14, 0.14, D + 0.06) * s,
			lp(side * W / 2, H - 0.03, 0),
			style.trim,
			style.trimMaterial,
			noCollide
		)
	end
	deco(
		model,
		"Dobradica",
		Vector3.new(0.14, 0.12, 3.25) * s,
		lp(0, H + 0.05, 0),
		style.trim,
		style.trimMaterial,
		flat
	)
	-- cantoneiras entalhadas
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			deco(
				model,
				"Cantoneira",
				Vector3.new(0.5, H + 0.16, 0.5) * s,
				lp(sx * (W / 2 - 0.12), (H + 0.16) / 2, sz * (D / 2 - 0.12)),
				style.trim,
				style.trimMaterial,
				noCollide
			)
		end
	end
	-- casas do caminho em volta do vidro central
	local tileCount = 18
	local pieceTile = nil
	for i = 1, tileCount do
		local angle = (i / tileCount) * TAU
		local x, z = math.cos(angle) * 1.78, math.sin(angle) * 1.22
		local tileCFrame = lp(x, H + 0.11, z) * CFrame.Angles(0, -angle, 0)
		deco(
			model,
			"Casa",
			Vector3.new(0.34, 0.05, 0.34) * s,
			tileCFrame,
			style.tiles[(i % #style.tiles) + 1],
			Material.SmoothPlastic,
			flat
		)
		if i == 4 then
			pieceTile = lp(x, H + 0.135, z)
		end
	end
	-- vidro verde central com brilho
	makePart(
		model,
		"Aro",
		Vector3.new(0.16, 1.8, 1.8) * s,
		lp(0, H + 0.1, 0) * UPRIGHT,
		style.trim,
		style.trimMaterial,
		{ Shape = CYLINDER, CanCollide = false }
	)
	local glow = makePart(
		model,
		"Brilho",
		Vector3.new(0.08, 1.5, 1.5) * s,
		lp(0, H + 0.15, 0) * UPRIGHT,
		style.glow,
		Material.Neon,
		{ Shape = CYLINDER, CanCollide = false, CastShadow = false }
	)
	makePart(
		model,
		"Vidro",
		Vector3.new(0.1, 1.5, 1.5) * s,
		lp(0, H + 0.22, 0) * UPRIGHT,
		style.glass,
		Material.Glass,
		{ Shape = CYLINDER, CanCollide = false, CastShadow = false, Transparency = 0.35, Reflectance = 0.15 }
	)
	addPointLight(glow, style.glow, style.lightBrightness, style.lightRange, false, nil, 0.35)

	-- a peça única do grupo, parada numa casa
	if pieceTile then
		local pieceModel = PartBuilder.model("Peca", model)
		makePart(
			pieceModel,
			"Base",
			Vector3.new(0.06, 0.26, 0.26) * s,
			pieceTile * CFrame.new(0, 0.03 * s, 0) * UPRIGHT,
			style.piece,
			Material.SmoothPlastic,
			{ Shape = CYLINDER, CanCollide = false }
		)
		makePart(
			pieceModel,
			"Corpo",
			Vector3.new(0.3, 0.13, 0.13) * s,
			pieceTile * CFrame.new(0, 0.21 * s, 0) * UPRIGHT,
			style.piece,
			Material.SmoothPlastic,
			{ Shape = CYLINDER, CanCollide = false }
		)
		makePart(
			pieceModel,
			"Cabeca",
			Vector3.one * 0.2 * s,
			pieceTile * CFrame.new(0, 0.42 * s, 0),
			style.piece,
			Material.SmoothPlastic,
			{ Shape = BALL, CanCollide = false }
		)
	end
	return glow
end

-- Tambor com couro e amarração em zigue-zague. `base` é o centro da base.
local function drum(parent: Instance, base: Vector3, height: number, diameter: number, style)
	local model = PartBuilder.model("Tambor", parent)
	cylinder(
		model,
		"Corpo",
		base + Vector3.new(0, height / 2, 0),
		height,
		diameter,
		style.body,
		style.material,
		{ CanCollide = style.collide }
	)
	cylinder(
		model,
		"Couro",
		base + Vector3.new(0, height + 0.04, 0),
		0.08,
		diameter + 0.06,
		style.hide,
		style.hideMaterial,
		{ CanCollide = false }
	)
	for _, y in { height - 0.12, 0.13 } do
		cylinder(
			model,
			"Aro",
			base + Vector3.new(0, y, 0),
			0.24,
			diameter + 0.16,
			style.rim,
			Material.Wood,
			{ CanCollide = false }
		)
	end
	local count = style.cords
	if count > 0 then
		local radius = diameter / 2 + 0.05
		local function rim(angle: number, y: number): Vector3
			return base + Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
		end
		for i = 0, count - 1 do
			local a1 = (i / count) * TAU
			local a2 = ((i + 0.5) / count) * TAU
			local a3 = ((i + 1) / count) * TAU
			local low = rim(a2, 0.3)
			segment(
				model,
				"Corda",
				rim(a1, height - 0.25),
				low,
				0.05,
				style.cord,
				Material.Fabric,
				{ CastShadow = false }
			)
			segment(
				model,
				"Corda",
				low,
				rim(a3, height - 0.25),
				0.05,
				style.cord,
				Material.Fabric,
				{ CastShadow = false }
			)
		end
	end
end

-- Baú antigo com tampa arredondada e cintas de metal. `base` = centro da base.
local function chest(parent: Instance, base: CFrame)
	local model = PartBuilder.model("Bau", parent)
	local function lp(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end
	makePart(model, "Corpo", Vector3.new(3.4, 1.6, 2), lp(0, 0.8, 0), C.DarkWood, Material.WoodPlanks)
	makePart(
		model,
		"Tampa",
		Vector3.new(3.4, 2, 2),
		lp(0, 1.6, 0),
		Color3.fromRGB(70, 44, 24),
		Material.WoodPlanks,
		{ Shape = CYLINDER }
	)
	for _, x in { -1.15, 1.15 } do
		deco(
			model,
			"Cinta",
			Vector3.new(0.2, 2.1, 2.1),
			lp(x, 1.6, 0),
			C.Iron,
			Material.CorrodedMetal,
			{ Shape = CYLINDER }
		)
		deco(model, "Cinta", Vector3.new(0.2, 1.62, 2.08), lp(x, 0.8, 0), C.Iron, Material.CorrodedMetal)
	end
	deco(model, "Fechadura", Vector3.new(0.45, 0.55, 0.14), lp(0, 1.45, 1.04), C.Brass, Material.Metal)
end

-- Estante com livros. `base` = centro da base, com a frente virada para +Z local.
local function bookshelf(
	parent: Instance,
	base: CFrame,
	width: number,
	height: number,
	depth: number,
	levels: number,
	rng: Random
)
	local model = PartBuilder.model("Estante", parent)
	local function lp(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end
	for _, side in { -1, 1 } do
		makePart(
			model,
			"Lateral",
			Vector3.new(0.4, height, depth),
			lp(side * (width / 2 - 0.2), height / 2, 0),
			C.DarkWood,
			Material.Wood
		)
	end
	makePart(
		model,
		"Fundo",
		Vector3.new(width, height, 0.2),
		lp(0, height / 2, -depth / 2 + 0.1),
		C.Beam,
		Material.Wood
	)
	makePart(
		model,
		"Topo",
		Vector3.new(width + 0.3, 0.3, depth + 0.2),
		lp(0, height + 0.15, 0),
		C.DarkWood,
		Material.Wood
	)
	local gap = (height - 0.3) / levels
	for level = 0, levels - 1 do
		local y = 0.15 + level * gap
		deco(model, "Prateleira", Vector3.new(width - 0.8, 0.25, depth - 0.2), lp(0, y, 0.1), C.DarkWood, Material.Wood)
		-- livros em blocos de larguras variadas, com alguns vãos e alguns inclinados
		local x = -width / 2 + 0.45
		local limit = width / 2 - 0.45
		while x < limit - 0.3 do
			local bookWidth = math.min(rng:NextNumber(0.35, 0.85), limit - x)
			if rng:NextNumber() < 0.15 then
				x += rng:NextNumber(0.3, 0.7)
			else
				local bookHeight = rng:NextNumber(gap * 0.55, gap * 0.82)
				local tilt = rng:NextNumber() < 0.12 and rng:NextNumber(-0.22, 0.22) or 0
				deco(
					model,
					"Livros",
					Vector3.new(bookWidth, bookHeight, depth * 0.68),
					lp(x + bookWidth / 2, y + 0.125 + bookHeight / 2, 0.05) * CFrame.Angles(0, 0, tilt),
					BOOK_COLORS[rng:NextInteger(1, #BOOK_COLORS)],
					Material.Fabric,
					{ CastShadow = false }
				)
				x += bookWidth + 0.04
			end
		end
	end
end

local function torch(parent: Instance, wallPoint: Vector3, inward: Vector3)
	local model = PartBuilder.model("Tocha", parent)
	local tip = wallPoint + inward * 1.3 + Vector3.new(0, 0.7, 0)
	segment(
		model,
		"Suporte",
		wallPoint + Vector3.new(0, -0.3, 0),
		tip,
		0.3,
		C.Iron,
		Material.CorrodedMetal,
		{ CastShadow = false }
	)
	cylinder(
		model,
		"Haste",
		tip + Vector3.new(0, 0.4, 0),
		1.2,
		0.45,
		C.TorchWood,
		Material.Wood,
		{ CanCollide = false, CastShadow = false }
	)
	cylinder(
		model,
		"Bacia",
		tip + Vector3.new(0, 1.1, 0),
		0.45,
		1.1,
		C.Iron,
		Material.CorrodedMetal,
		{ CanCollide = false, CastShadow = false }
	)
	local flame = deco(
		model,
		"Fogo",
		Vector3.new(0.5, 0.5, 0.5),
		CFrame.new(tip + Vector3.new(0, 1.6, 0)),
		C.Flame,
		Material.Neon,
		{ Transparency = 1, CastShadow = false }
	)
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 7
	fire.Color = Color3.fromRGB(255, 140, 50)
	fire.SecondaryColor = Color3.fromRGB(255, 70, 20)
	fire.Parent = flame
	addPointLight(flame, C.TorchLight, 2.2, 18, false, 0.25)
end

-- Marcadores ---------------------------------------------------------------------------------------------

local function getMarkersFolder(): Instance
	local folder = workspace:FindFirstChild(MARKERS_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = MARKERS_FOLDER
		folder.Parent = workspace
	end
	return folder
end

local function setMarker(folder: Instance, name: string, cframe: CFrame, extra: { [string]: any }?): BasePart
	local old = folder:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local props = merge({
		Name = name,
		Size = Vector3.new(1, 1, 1),
		CFrame = cframe,
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		CastShadow = false,
	}, extra)
	props.Parent = folder
	local part = PartBuilder.part(props)
	part.CanQuery = false
	return part
end

-- Cubículo do spawn (sem ceder: precisa existir antes do primeiro personagem nascer) -----------------------

local function buildSpawnCubicle(root: Instance, markers: Instance)
	local O = GameConfig.MENU_AREA_ORIGIN
	local function m(x: number, y: number, z: number): Vector3
		return O + Vector3.new(x, y, z)
	end
	local model = PartBuilder.model("CubiculoSpawn", root)
	local color = Color3.fromRGB(40, 32, 26)
	-- interior x -8..8, z 22..38 (atrás da parede da frente do sótão, fora do quadro da câmera)
	makePart(model, "Piso", Vector3.new(18, 1, 18), CFrame.new(m(0, -0.5, 30)), color, Material.WoodPlanks)
	makePart(model, "Teto", Vector3.new(18, 1, 18), CFrame.new(m(0, 12.5, 30)), color, Material.WoodPlanks)
	makePart(model, "Parede", Vector3.new(18, 12, 1), CFrame.new(m(0, 6, 21.5)), color, Material.WoodPlanks)
	makePart(model, "Parede", Vector3.new(18, 12, 1), CFrame.new(m(0, 6, 38.5)), color, Material.WoodPlanks)
	makePart(model, "Parede", Vector3.new(1, 12, 18), CFrame.new(m(-8.5, 6, 30)), color, Material.WoodPlanks)
	makePart(model, "Parede", Vector3.new(1, 12, 18), CFrame.new(m(8.5, 6, 30)), color, Material.WoodPlanks)
	local lamp = deco(
		model,
		"Lampada",
		Vector3.new(0.6, 0.6, 0.6),
		CFrame.new(m(0, 11.6, 30)),
		C.Flame,
		Material.Neon,
		{ CastShadow = false }
	)
	addPointLight(lamp, C.CandleLight, 0.6, 18, false)

	setMarker(markers, "MenuSpawn", CFrame.new(m(0, -0.45, 30)), {
		ClassName = "SpawnLocation",
		Size = Vector3.new(10, 1, 10),
		Neutral = true,
		Duration = 0,
		AllowTeamChangeOnTouch = false,
		Enabled = true,
	})
end

-- Sótão do menu ----------------------------------------------------------------------------------------

local function buildMenuScene(root: Instance, markers: Instance)
	local O = GameConfig.MENU_AREA_ORIGIN
	local function m(x: number, y: number, z: number): Vector3
		return O + Vector3.new(x, y, z)
	end
	local rng = Random.new(1995)
	local scene = PartBuilder.model("MenuScene")
	local noCollide = { CanCollide = false }

	-- Câmera do menu: enquadra a mesa pela direita da tela (o menu fica à esquerda), levemente de cima.
	local cameraPosition = m(-4, 8.5, 9)
	setMarker(markers, "MenuCamera", CFrame.lookAt(cameraPosition, cameraPosition + Vector3.new(0, -0.306, -1)))

	-- Casca: interior x -20..20, z -18..18, piso em y 0, paredes laterais até 10 e cumeeira em 18,4.
	local shell = PartBuilder.model("Sotao", scene)
	makePart(shell, "Piso", Vector3.new(42, 1, 38), CFrame.new(m(0, -0.5, 0)), C.FloorWood, Material.WoodPlanks)
	makePart(shell, "Parede", Vector3.new(1, 10.5, 38), CFrame.new(m(-20.5, 5.25, 0)), C.WallWood, Material.WoodPlanks)
	makePart(shell, "Parede", Vector3.new(1, 10.5, 38), CFrame.new(m(20.5, 5.25, 0)), C.WallWood, Material.WoodPlanks)
	makePart(shell, "Parede", Vector3.new(42, 19, 1), CFrame.new(m(0, 9.5, 18.5)), C.WallWood, Material.WoodPlanks)
	-- parede do fundo com a abertura da janela (x -1,5..7,5; y 3,5..10,5)
	makePart(
		shell,
		"Parede",
		Vector3.new(19.5, 19, 1),
		CFrame.new(m(-11.25, 9.5, -18.5)),
		C.WallWood,
		Material.WoodPlanks
	)
	makePart(
		shell,
		"Parede",
		Vector3.new(13.5, 19, 1),
		CFrame.new(m(14.25, 9.5, -18.5)),
		C.WallWood,
		Material.WoodPlanks
	)
	makePart(shell, "Parede", Vector3.new(9, 3.5, 1), CFrame.new(m(3, 1.75, -18.5)), C.WallWood, Material.WoodPlanks)
	makePart(shell, "Parede", Vector3.new(9, 8.5, 1), CFrame.new(m(3, 14.75, -18.5)), C.WallWood, Material.WoodPlanks)

	-- telhado de duas águas, caibros, cumeeira e vigas
	local rise, run = 8.4, 21
	local angle = math.atan2(rise, run)
	local roofLength = math.sqrt(rise * rise + run * run)
	for _, side in { -1, 1 } do
		local normal = Vector3.new(side * math.sin(angle), math.cos(angle), 0)
		local rotation = CFrame.Angles(0, 0, -side * angle)
		local mid = m(side * run / 2, 10 + rise / 2, 0)
		makePart(
			shell,
			"Telhado",
			Vector3.new(roofLength + 1.2, 1, 40),
			CFrame.new(mid + normal * 0.5) * rotation,
			C.WallWood,
			Material.WoodPlanks
		)
		for _, z in { -15, -9, -3, 3, 9, 15 } do
			deco(
				shell,
				"Caibro",
				Vector3.new(roofLength, 0.8, 0.8),
				CFrame.new(mid - normal * 0.4 + Vector3.new(0, 0, z)) * rotation,
				C.Beam,
				Material.Wood
			)
		end
	end
	deco(shell, "Cumeeira", Vector3.new(1.2, 1.2, 38), CFrame.new(m(0, 17.9, 0)), C.Beam, Material.Wood)
	for _, z in { -10, 6 } do
		deco(shell, "Viga", Vector3.new(41, 0.9, 0.9), CFrame.new(m(0, 10.4, z)), C.Beam, Material.Wood)
	end

	-- janela quebrada
	local window = PartBuilder.model("JanelaQuebrada", scene)
	deco(window, "Peitoril", Vector3.new(10, 0.4, 1.6), CFrame.new(m(3, 3.3, -18.3)), C.DarkWood, Material.Wood)
	deco(window, "Verga", Vector3.new(10, 0.5, 1.3), CFrame.new(m(3, 10.75, -18.5)), C.DarkWood, Material.Wood)
	deco(window, "Batente", Vector3.new(0.5, 7.5, 1.3), CFrame.new(m(-1.75, 7, -18.5)), C.DarkWood, Material.Wood)
	deco(window, "Batente", Vector3.new(0.5, 7.5, 1.3), CFrame.new(m(7.75, 7, -18.5)), C.DarkWood, Material.Wood)
	deco(
		window,
		"Travessa",
		Vector3.new(0.3, 2.9, 0.3),
		CFrame.new(m(3, 4.95, -18.5)) * CFrame.Angles(0, 0, 0.15),
		C.DarkWood,
		Material.Wood
	)
	deco(
		window,
		"Travessa",
		Vector3.new(0.3, 2.2, 0.3),
		CFrame.new(m(3.25, 9.45, -18.5)) * CFrame.Angles(0, 0, -0.3),
		C.DarkWood,
		Material.Wood
	)
	deco(
		window,
		"Travessa",
		Vector3.new(2.6, 0.3, 0.3),
		CFrame.new(m(6.3, 7.1, -18.5)) * CFrame.Angles(0, 0, 0.2),
		C.DarkWood,
		Material.Wood
	)
	-- cacos de vidro presos nos cantos e caídos no chão
	local shardProps = { Transparency = 0.45, Reflectance = 0.2, CastShadow = false, CanCollide = false }
	for _, spot in
		{
			{ m(-1.2, 10.0, -18.5), 0.4 },
			{ m(7.2, 9.9, -18.5), -0.6 },
			{ m(-1.1, 4.1, -18.5), 2.6 },
			{ m(7.1, 4.3, -18.5), 3.6 },
		}
	do
		PartBuilder.wedge(merge({
			Name = "Caco",
			Size = Vector3.new(0.05, 1.3, 0.9),
			CFrame = CFrame.new(spot[1]) * CFrame.Angles(0, math.pi / 2, spot[2]),
			Color = C.Glass,
			Material = Material.Glass,
			CanTouch = false,
			Parent = window,
		}, shardProps))
	end
	for _ = 1, 6 do
		PartBuilder.wedge(merge({
			Name = "Caco",
			Size = Vector3.new(0.05, rng:NextNumber(0.4, 0.9), rng:NextNumber(0.3, 0.7)),
			CFrame = CFrame.new(m(rng:NextNumber(0.5, 6.5), 0.03, rng:NextNumber(-17.2, -12.5)))
				* CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
				* CFrame.Angles(0, 0, math.pi / 2),
			Color = C.Glass,
			Material = Material.Glass,
			CanTouch = false,
			Parent = window,
		}, shardProps))
	end

	-- luz do entardecer entrando pela janela
	local windowLight = deco(
		window,
		"LuzJanela",
		Vector3.new(0.5, 0.5, 0.5),
		CFrame.lookAt(m(3, 7.6, -17.4), m(1, 0, -8)),
		C.WindowLight,
		Material.SmoothPlastic,
		{ Transparency = 1, CastShadow = false }
	)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Angle = 70
	spot.Range = 26
	spot.Brightness = 2.4
	spot.Color = C.WindowLight
	spot.Shadows = true
	spot.Parent = windowLight
	-- feixe de luz "volumétrico" bem sutil, com poeira
	local shaftFrom, shaftTo = m(3, 7, -18), m(1.4, 0, -9.5)
	deco(
		window,
		"FeixeDeLuz",
		Vector3.new(7.5, 6, (shaftTo - shaftFrom).Magnitude),
		CFrame.lookAt((shaftFrom + shaftTo) / 2, shaftTo),
		Color3.fromRGB(255, 200, 160),
		Material.Neon,
		{ Transparency = 0.955, CastShadow = false }
	)
	local dustVolume = deco(
		scene,
		"Poeira",
		Vector3.new(22, 8, 16),
		CFrame.new(m(2, 4, -9)),
		Color3.new(1, 1, 1),
		Material.SmoothPlastic,
		{ Transparency = 1, CastShadow = false }
	)
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "Poeira"
	dust.Shape = Enum.ParticleEmitterShape.Box
	dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	dust.Rate = 6
	dust.Lifetime = NumberRange.new(9, 14)
	dust.Speed = NumberRange.new(0.05, 0.2)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Acceleration = Vector3.new(0, -0.01, 0)
	dust.RotSpeed = NumberRange.new(-20, 20)
	dust.Size = numberSequence({ { 0, 0.07 }, { 0.5, 0.11 }, { 1, 0.06 } })
	dust.Transparency = numberSequence({ { 0, 1 }, { 0.15, 0.35 }, { 0.85, 0.45 }, { 1, 1 } })
	dust.LightEmission = 0.6
	dust.LightInfluence = 0.4
	dust.Color = ColorSequence.new(Color3.fromRGB(255, 228, 190))
	dust.Parent = dustVolume

	-- tapete
	deco(scene, "Tapete", Vector3.new(17, 0.08, 12), CFrame.new(m(0, 0.04, -4.5)), C.RugGold, Material.Fabric)
	deco(scene, "Tapete", Vector3.new(16, 0.1, 11), CFrame.new(m(0, 0.06, -4.5)), C.RugRed, Material.Fabric)

	-- mesa com a réplica do tabuleiro, tambores, dados e velas
	local tableModel = PartBuilder.model("Mesa", scene)
	makePart(tableModel, "Tampo", Vector3.new(10, 0.6, 6), CFrame.new(m(0, 3.1, -4)), C.TableWood, Material.Wood)
	for _, x in { -4.3, 4.3 } do
		for _, z in { -6.4, -1.6 } do
			makePart(
				tableModel,
				"Perna",
				Vector3.new(0.7, 2.8, 0.7),
				CFrame.new(m(x, 1.4, z)),
				C.DarkWood,
				Material.Wood
			)
		end
	end
	for _, z in { -6.7, -1.3 } do
		deco(tableModel, "Saia", Vector3.new(8.6, 0.5, 0.3), CFrame.new(m(0, 2.55, z)), C.DarkWood, Material.Wood)
	end
	boardReplica(scene, CFrame.new(m(0, 3.4, -4.2)) * CFrame.Angles(0, math.rad(-8), 0), 1, WOOD_BOARD)
	drum(scene, m(-3.8, 3.4, -3.4), 2.0, 1.7, WOOD_DRUM)
	drum(scene, m(3.9, 3.4, -3.6), 1.6, 1.5, WOOD_DRUM)

	-- dados (mostrando 5 e 3)
	local dice = {
		{ m(1.6, 3.59, -1.9), 0.5, { { 0, 0 }, { -1, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 } } },
		{ m(2.3, 3.59, -2.4), -0.35, { { 0, 0 }, { -1, -1 }, { 1, 1 } } },
	}
	for _, info in dice do
		local dieCFrame = CFrame.new(info[1]) * CFrame.Angles(0, info[2], 0)
		deco(tableModel, "Dado", Vector3.one * 0.38, dieCFrame, Color3.fromRGB(240, 232, 214), Material.SmoothPlastic)
		for _, pip in info[3] do
			deco(
				tableModel,
				"Ponto",
				Vector3.new(0.02, 0.07, 0.07),
				dieCFrame * CFrame.new(pip[1] * 0.1, 0.19, pip[2] * 0.1) * UPRIGHT,
				Color3.fromRGB(30, 24, 20),
				Material.SmoothPlastic,
				{ Shape = CYLINDER, CastShadow = false }
			)
		end
	end

	candleCluster(scene, m(-3.4, 3.4, -6.2), { 1.4, 1.0, 0.7 }, 11, 1.4, true)
	candleCluster(scene, m(2.9, 3.4, -6.4), { 1.1, 0.75 }, 10, 1.2, false)

	-- candelabro de chão
	local stand = PartBuilder.model("Candelabro", scene)
	cylinder(stand, "Base", m(10.5, 0.15, -12.5), 0.3, 1.6, C.Iron, Material.CorrodedMetal, noCollide)
	cylinder(stand, "Haste", m(10.5, 2.4, -12.5), 4.2, 0.25, C.Iron, Material.CorrodedMetal, noCollide)
	deco(stand, "Braco", Vector3.new(2.4, 0.15, 0.15), CFrame.new(m(10.5, 4.5, -12.5)), C.Iron, Material.CorrodedMetal)
	local standFlame = nil
	for _, dx in { -1.1, 0, 1.1 } do
		cylinder(stand, "Copo", m(10.5 + dx, 4.65, -12.5), 0.2, 0.42, C.Brass, Material.Metal, noCollide)
		local flame = candle(stand, m(10.5 + dx, 4.75, -12.5), dx == 0 and 1.0 or 0.75)
		if dx == 0 then
			standFlame = flame
		end
	end
	if standFlame then
		addPointLight(standFlame, C.CandleLight, 1.5, 14, true, 0.3)
	end

	-- baú embaixo da janela, com uma vela em cima
	chest(scene, CFrame.new(m(5.2, 0, -14.6)) * CFrame.Angles(0, math.rad(8), 0))
	cylinder(scene, "Pires", m(6.1, 2.62, -14.5), 0.08, 0.7, C.Brass, Material.Metal, noCollide)
	local chestFlame = candle(scene, m(6.1, 2.66, -14.5), 0.6)
	addPointLight(chestFlame, C.CandleLight, 1.0, 9, false, 0.35)

	-- estantes no fundo, dos dois lados da janela
	bookshelf(scene, CFrame.new(m(13.5, 0, -17.1)), 7, 8, 1.6, 4, rng)
	bookshelf(scene, CFrame.new(m(-7.5, 0, -17.1)), 6, 7.5, 1.6, 4, rng)

	-- caixotes e um móvel coberto por um lençol (canto esquerdo)
	local clutter = PartBuilder.model("Tralhas", scene)
	makePart(clutter, "Caixote", Vector3.one * 2.6, CFrame.new(m(-13, 1.3, -14)), C.Crate, Material.WoodPlanks)
	makePart(
		clutter,
		"Caixote",
		Vector3.one * 1.8,
		CFrame.new(m(-13.2, 3.5, -14.1)) * CFrame.Angles(0, 0.4, 0),
		C.Crate,
		Material.WoodPlanks
	)
	makePart(
		clutter,
		"Caixote",
		Vector3.one * 2,
		CFrame.new(m(-10.0, 1, -14.4)) * CFrame.Angles(0, -0.3, 0),
		C.Crate,
		Material.WoodPlanks
	)
	makePart(clutter, "Lencol", Vector3.new(4, 3.2, 2.6), CFrame.new(m(-15, 1.6, -6)), C.Sheet, Material.Fabric)
	deco(
		clutter,
		"Lencol",
		Vector3.new(3.4, 1, 2.2),
		CFrame.new(m(-15.1, 3.6, -6.3)) * CFrame.Angles(0.08, 0, 0.1),
		C.Sheet,
		Material.Fabric
	)

	-- cipós da selva entrando pela janela
	local vines = PartBuilder.model("Cipos", scene)
	vine(vines, {
		m(0.5, 11.5, -21),
		m(0.8, 10.9, -18.6),
		m(1.2, 9.6, -17.6),
		m(0.9, 7.4, -17.4),
		m(0.5, 5.2, -17.3),
		m(0.2, 3.0, -17.2),
		m(0.0, 0.9, -16.8),
		m(-0.3, 0.15, -15.4),
		m(-0.9, 0.15, -12.6),
		m(-1.6, 0.15, -9.6),
	}, 0.22, rng, 1, 1, true)
	vine(vines, {
		m(6.0, 11.4, -21),
		m(6.4, 10.9, -18.6),
		m(7.6, 10.6, -17.8),
		m(9.2, 11.4, -17.8),
		m(10.6, 12.6, -17.8),
		m(12.6, 12.9, -17.7),
		m(14.6, 12.2, -17.7),
	}, 0.2, rng, 2, 0.9, true)
	vine(vines, {
		m(3.0, 3.0, -21),
		m(3.2, 3.8, -18.4),
		m(3.6, 3.4, -17.0),
		m(4.2, 2.8, -15.8),
		m(4.8, 2.75, -14.6),
		m(5.6, 2.2, -13.4),
		m(6.0, 0.8, -13.0),
		m(5.8, 0.15, -11.6),
		m(5.0, 0.15, -8.8),
		m(4.5, 0.15, -7.0),
		m(4.35, 1.4, -6.85),
		m(4.4, 2.6, -6.85),
		m(4.0, 3.45, -6.6),
	}, 0.2, rng, 1, 0.9, true)
	vine(vines, {
		m(-1.2, 10.6, -18.2),
		m(-3.4, 11.8, -17.9),
		m(-5.6, 11.2, -17.85),
		m(-7.8, 12.4, -17.85),
		m(-9.6, 11.6, -17.85),
	}, 0.18, rng, 2, 0.9, true)
	vine(vines, { m(-5.6, 11.2, -17.85), m(-5.4, 9.3, -17.7), m(-5.7, 8.2, -17.6) }, 0.14, rng, 1, 0.8, true)
	vine(
		vines,
		{ m(4.2, 10.4, -18.3), m(4.5, 8.6, -18.1), m(4.2, 7.0, -18.0), m(4.6, 5.9, -17.9) },
		0.16,
		rng,
		1,
		0.9,
		true
	)

	-- selva do lado de fora da janela (silhuetas sob o céu do entardecer)
	local outside = PartBuilder.model("SelvaLaFora", scene)
	makePart(outside, "Chao", Vector3.new(80, 1, 70), CFrame.new(m(5, -2.5, -55)), C.JungleGround, Material.Grass)
	for _ = 1, 9 do
		local x, z = rng:NextNumber(-25, 35), rng:NextNumber(-80, -28)
		local trunkHeight = rng:NextNumber(14, 22)
		cylinder(
			outside,
			"Tronco",
			m(x, -2 + trunkHeight / 2, z),
			trunkHeight,
			rng:NextNumber(1.4, 2.4),
			C.Trunk,
			Material.Wood,
			noCollide
		)
		for _ = 1, 2 do
			ball(
				outside,
				"Copa",
				m(x + rng:NextNumber(-3, 3), -2 + trunkHeight + rng:NextNumber(-2, 2), z + rng:NextNumber(-3, 3)),
				rng:NextNumber(9, 15),
				C.Canopy,
				Material.LeafyGrass
			)
		end
	end
	for _, info in { { -30, -125 }, { 40, -135 } } do
		ball(outside, "Morro", m(info[1], -22, info[2]), 64, Color3.fromRGB(30, 44, 30), Material.Grass)
	end

	scene.Parent = root
end

-- Hub: salão do templo --------------------------------------------------------------------------------

local function buildHub(root: Instance, markers: Instance)
	local O = GameConfig.HUB_ORIGIN
	local function h(x: number, y: number, z: number): Vector3
		return O + Vector3.new(x, y, z)
	end
	local rng = Random.new(1969)
	local HALF = 46 -- meia largura interna
	local WALL_H = 30
	local hub = PartBuilder.model("Hub")
	local temple = PartBuilder.model("Templo", hub)
	local flat = { CanCollide = false, CastShadow = false }

	-- jogadores aparecem diante da porta, olhando para a estátua
	setMarker(markers, "HubSpawn", CFrame.lookAt(h(0, 0.5, 34), h(0, 0.5, 0)))
	setMarker(markers, "HubCamera", CFrame.lookAt(h(34, 24, 40), h(0, 4, 0)))

	-- piso, caminhos e praça central
	makePart(temple, "Piso", Vector3.new(98, 2, 98), CFrame.new(h(0, -1, 0)), C.StoneFloor, Material.Slate)
	deco(temple, "Caminho", Vector3.new(8, 0.1, 78), CFrame.new(h(0, 0.05, 5)), C.StonePath, Material.Cobblestone, flat)
	deco(temple, "Caminho", Vector3.new(90, 0.1, 8), CFrame.new(h(0, 0.06, 0)), C.StonePath, Material.Cobblestone, flat)
	cylinder(temple, "Praca", h(0, 0.08, 0), 0.12, 34, C.StonePlaza, Material.Pebble, flat)
	for _ = 1, 8 do
		local x, z = rng:NextNumber(-42, 42), rng:NextNumber(-42, 42)
		if math.abs(x) > 18 or math.abs(z) > 18 then
			deco(
				temple,
				"Musgo",
				Vector3.new(rng:NextNumber(3, 8), 0.06, rng:NextNumber(2, 6)),
				CFrame.new(h(x, 0.03, z)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0),
				C.Moss,
				Material.Grass,
				flat
			)
		end
	end

	-- paredes, rodapé, cornija e pilastras
	local wallDefs = {
		{ Vector3.new(104, WALL_H, 3), h(0, WALL_H / 2, -(HALF + 1.5)) },
		{ Vector3.new(104, WALL_H, 3), h(0, WALL_H / 2, HALF + 1.5) },
		{ Vector3.new(3, WALL_H, 98), h(-(HALF + 1.5), WALL_H / 2, 0) },
		{ Vector3.new(3, WALL_H, 98), h(HALF + 1.5, WALL_H / 2, 0) },
	}
	for _, def in wallDefs do
		makePart(temple, "Parede", def[1], CFrame.new(def[2]), C.StoneWall, Material.Cobblestone)
	end
	for _, sign in { -1, 1 } do
		makePart(
			temple,
			"Cornija",
			Vector3.new(104, 1.6, 5),
			CFrame.new(h(0, WALL_H + 0.8, sign * (HALF + 1.5))),
			C.StoneDark,
			Material.Granite
		)
		makePart(
			temple,
			"Cornija",
			Vector3.new(5, 1.6, 104),
			CFrame.new(h(sign * (HALF + 1.5), WALL_H + 0.8, 0)),
			C.StoneDark,
			Material.Granite
		)
		makePart(
			temple,
			"Rodape",
			Vector3.new(92, 1.4, 1),
			CFrame.new(h(0, 0.7, sign * (HALF - 0.5))),
			C.StoneDark,
			Material.Granite
		)
		makePart(
			temple,
			"Rodape",
			Vector3.new(1, 1.4, 92),
			CFrame.new(h(sign * (HALF - 0.5), 0.7, 0)),
			C.StoneDark,
			Material.Granite
		)
		for _, offset in { -36, -18, 18, 36 } do
			makePart(
				temple,
				"Pilastra",
				Vector3.new(3, WALL_H, 1.2),
				CFrame.new(h(offset, WALL_H / 2, sign * (HALF - 0.6))),
				C.StoneDark,
				Material.Slate
			)
			makePart(
				temple,
				"Pilastra",
				Vector3.new(1.2, WALL_H, 3),
				CFrame.new(h(sign * (HALF - 0.6), WALL_H / 2, offset)),
				C.StoneDark,
				Material.Slate
			)
		end
	end

	-- porta de pedra selada (parede sul), com o emblema verde do tabuleiro
	local door = PartBuilder.model("PortaDoTemplo", hub)
	for _, x in { -9, 9 } do
		makePart(
			door,
			"Batente",
			Vector3.new(3, 20, 2.4),
			CFrame.new(h(x, 10, HALF - 0.8)),
			C.StoneDark,
			Material.Granite
		)
	end
	makePart(
		door,
		"Verga",
		Vector3.new(21, 3.2, 2.8),
		CFrame.new(h(0, 21.6, HALF - 0.8)),
		C.StoneDark,
		Material.Granite
	)
	makePart(door, "Porta", Vector3.new(15, 20, 0.8), CFrame.new(h(0, 10, HALF - 0.3)), C.StoneWall, Material.Slate)
	local facingNorth = CFrame.Angles(0, math.pi / 2, 0) -- eixo do cilindro ao longo de Z
	deco(
		door,
		"Emblema",
		Vector3.new(0.3, 6.4, 6.4),
		CFrame.new(h(0, 11, HALF - 0.75)) * facingNorth,
		STONE_BOARD.trim,
		STONE_BOARD.trimMaterial,
		{ Shape = CYLINDER }
	)
	deco(
		door,
		"Emblema",
		Vector3.new(0.3, 5, 5),
		CFrame.new(h(0, 11, HALF - 0.85)) * facingNorth,
		Color3.fromRGB(40, 170, 96),
		Material.Neon,
		{ Shape = CYLINDER, Transparency = 0.15, CastShadow = false }
	)

	-- cachoeira decorativa (parede norte) caindo numa piscina rasa
	local fall = PartBuilder.model("Cachoeira", hub)
	makePart(
		fall,
		"Bica",
		Vector3.new(16, 1.6, 3.4),
		CFrame.new(h(0, 26.2, -(HALF - 1.4))),
		C.StoneDark,
		Material.Granite
	)
	deco(
		fall,
		"Agua",
		Vector3.new(12, 25.6, 0.4),
		CFrame.new(h(0, 13.2, -(HALF - 0.8))),
		C.Water,
		Material.Glass,
		{ Transparency = 0.35, CastShadow = false }
	)
	deco(
		fall,
		"Espuma",
		Vector3.new(11, 25.6, 0.12),
		CFrame.new(h(0, 13.2, -(HALF - 1.1))),
		Color3.fromRGB(235, 245, 250),
		Material.SmoothPlastic,
		{ Transparency = 0.72, CastShadow = false }
	)
	for _, x in { -11.4, 11.4 } do
		makePart(fall, "Borda", Vector3.new(1.2, 1.2, 9.2), CFrame.new(h(x, 0.6, -40.6)), C.StoneDark, Material.Granite)
	end
	makePart(fall, "Borda", Vector3.new(24, 1.2, 1.2), CFrame.new(h(0, 0.6, -35.6)), C.StoneDark, Material.Granite)
	deco(fall, "Fundo", Vector3.new(21.6, 0.1, 9.6), CFrame.new(h(0, 0.06, -40.8)), C.PoolBed, Material.Slate, flat)
	deco(
		fall,
		"Piscina",
		Vector3.new(21.6, 0.3, 9.6),
		CFrame.new(h(0, 0.75, -40.8)),
		C.PoolWater,
		Material.Glass,
		{ Transparency = 0.3, CastShadow = false }
	)
	for _, spotInfo in { { -7.5, -43.5, 2.4 }, { 7.8, -43.8, 2.0 }, { -9.6, -38.6, 1.4 }, { 9.4, -39.2, 1.6 } } do
		makePart(
			fall,
			"Pedra",
			Vector3.new(spotInfo[3] * 1.3, spotInfo[3], spotInfo[3] * 1.1),
			CFrame.new(h(spotInfo[1], spotInfo[3] / 2, spotInfo[2])) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0.1),
			C.StoneDark,
			Material.Rock
		)
	end
	local streamSource = deco(
		fall,
		"FonteDaQueda",
		Vector3.new(12, 0.2, 0.4),
		CFrame.new(h(0, 25.4, -(HALF - 1.2))),
		C.Water,
		Material.SmoothPlastic,
		{ Transparency = 1, CastShadow = false }
	)
	local stream = Instance.new("ParticleEmitter")
	stream.Name = "Queda"
	stream.Texture = "rbxasset://textures/particles/smoke_main.dds"
	stream.Shape = Enum.ParticleEmitterShape.Box
	stream.EmissionDirection = Enum.NormalId.Bottom
	stream.Rate = 36
	stream.Lifetime = NumberRange.new(1.0, 1.2)
	stream.Speed = NumberRange.new(20, 24)
	stream.Acceleration = Vector3.new(0, -8, 0)
	stream.SpreadAngle = Vector2.new(2, 2)
	stream.Size = numberSequence({ { 0, 1.2 }, { 1, 2.4 } })
	stream.Transparency = numberSequence({ { 0, 0.6 }, { 0.8, 0.75 }, { 1, 1 } })
	stream.Color = ColorSequence.new(Color3.fromRGB(225, 240, 250))
	stream.LightEmission = 0.3
	stream.Parent = streamSource
	local mistSource = deco(
		fall,
		"Nevoa",
		Vector3.new(12, 1, 2),
		CFrame.new(h(0, 0.9, -(HALF - 2))),
		C.Water,
		Material.SmoothPlastic,
		{ Transparency = 1, CastShadow = false }
	)
	local mist = Instance.new("ParticleEmitter")
	mist.Name = "Nevoa"
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Shape = Enum.ParticleEmitterShape.Box
	mist.EmissionDirection = Enum.NormalId.Top
	mist.Rate = 12
	mist.Lifetime = NumberRange.new(2, 3)
	mist.Speed = NumberRange.new(1, 3)
	mist.SpreadAngle = Vector2.new(60, 60)
	mist.Size = numberSequence({ { 0, 3 }, { 1, 7 } })
	mist.Transparency = numberSequence({ { 0, 0.75 }, { 1, 1 } })
	mist.Color = ColorSequence.new(Color3.fromRGB(225, 240, 255))
	mist.LightEmission = 0.2
	mist.Parent = mistSource

	-- colunatas com arquitraves
	local colonnade = PartBuilder.model("Colunas", hub)
	for _, x in { -28, 28 } do
		for _, z in { -27, -9, 9, 27 } do
			makePart(
				colonnade,
				"BaseColuna",
				Vector3.new(5, 1.6, 5),
				CFrame.new(h(x, 0.8, z)),
				C.StoneDark,
				Material.Granite
			)
			cylinder(colonnade, "Coluna", h(x, 13.1, z), 23, 3.6, C.StoneColumn, Material.Limestone)
			makePart(
				colonnade,
				"Capitel",
				Vector3.new(5.4, 1.8, 5.4),
				CFrame.new(h(x, 25.5, z)),
				C.StoneDark,
				Material.Granite
			)
		end
		makePart(
			colonnade,
			"Arquitrave",
			Vector3.new(5, 2.2, 62),
			CFrame.new(h(x, 27.5, 0)),
			C.StoneWall,
			Material.Slate
		)
	end
	-- coluna caída
	makePart(
		colonnade,
		"ColunaCaida",
		Vector3.new(9, 3.6, 3.6),
		CFrame.new(h(37, 1.8, -20)) * CFrame.Angles(0, 0.6, 0),
		C.StoneColumn,
		Material.Limestone,
		{ Shape = CYLINDER }
	)

	-- tochas
	local torches = PartBuilder.model("Tochas", hub)
	for _, z in { -27, 0, 27 } do
		torch(torches, h(-HALF, 9, z), Vector3.new(1, 0, 0))
		torch(torches, h(HALF, 9, z), Vector3.new(-1, 0, 0))
	end
	for _, x in { -14, 14 } do
		torch(torches, h(x, 9, HALF), Vector3.new(0, 0, -1))
		torch(torches, h(x * 1.1, 9, -HALF), Vector3.new(0, 0, 1))
	end

	-- estátua do tabuleiro no centro
	local statue = PartBuilder.model("Estatua", hub)
	cylinder(statue, "Degrau", h(0, 0.5, 0), 1, 18, C.StoneDark, Material.Granite)
	makePart(statue, "Degrau", Vector3.new(10, 1, 10), CFrame.new(h(0, 1.5, 0)), C.StoneFloor, Material.Slate)
	makePart(statue, "Pedestal", Vector3.new(6.4, 1.2, 4.8), CFrame.new(h(0, 2.6, 0)), C.StoneDark, Material.Granite)
	boardReplica(statue, CFrame.new(h(0, 3.2, 0)), 2, STONE_BOARD)
	drum(statue, h(-7.2, 1, 0), 3, 2.4, STONE_DRUM)
	drum(statue, h(7.2, 1, 0), 2.6, 2.2, STONE_DRUM)
	for _, info in { { h(5.2, 1.8, 6.6), 0.5 }, { h(3.4, 1.8, 7.6), -0.3 } } do
		makePart(
			statue,
			"DadoGigante",
			Vector3.one * 1.6,
			CFrame.new(info[1]) * CFrame.Angles(0, info[2], 0),
			Color3.fromRGB(214, 206, 186),
			Material.Marble
		)
	end
	-- obeliscos com runas verdes em volta da praça
	for i = 0, 7 do
		local angle = (i / 8) * TAU + math.pi / 8
		local position = h(math.cos(angle) * 14.5, 0, math.sin(angle) * 14.5)
		local facing = CFrame.lookAt(position, h(0, 0, 0))
		makePart(
			statue,
			"Obelisco",
			Vector3.new(1.4, 4, 1.4),
			facing * CFrame.new(0, 2, 0),
			C.StoneDark,
			Material.Slate
		)
		deco(
			statue,
			"Runa",
			Vector3.new(0.7, 1.4, 0.1),
			facing * CFrame.new(0, 2.6, -0.72),
			C.Rune,
			Material.Neon,
			{ CastShadow = false }
		)
	end

	-- vegetação: cipós pendurados, arbustos e copas da selva por cima dos muros
	local plants = PartBuilder.model("Vegetacao", hub)
	for _, x in { -28, 28 } do
		for _, z in { -18, 0, 18 } do
			hangingVine(
				plants,
				h(x + rng:NextNumber(-1.8, 1.8), 26.4, z + rng:NextNumber(-4, 4)),
				rng:NextNumber(6, 12),
				rng
			)
		end
	end
	for _, info in
		{
			{ -(HALF - 0.4), -40 },
			{ -(HALF - 0.4), 12 },
			{ HALF - 0.4, -6 },
			{ HALF - 0.4, 33 },
		}
	do
		hangingVine(plants, h(info[1], WALL_H - 0.2, info[2]), rng:NextNumber(9, 16), rng)
	end
	for _, x in { -26, 24 } do
		hangingVine(plants, h(x, WALL_H - 0.2, HALF - 0.4), rng:NextNumber(9, 15), rng)
	end
	for _, x in { -7.4, 7.4 } do
		hangingVine(plants, h(x, 25.4, -(HALF - 2.9)), rng:NextNumber(5, 8), rng)
	end
	for _, corner in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
		for _ = 1, 3 do
			local size = rng:NextNumber(4, 6.5)
			ball(
				plants,
				"Arbusto",
				h(corner[1] * rng:NextNumber(38, 43), size * 0.3, corner[2] * rng:NextNumber(38, 43)),
				size,
				LEAF_COLORS[rng:NextInteger(1, #LEAF_COLORS)],
				Material.LeafyGrass
			)
		end
	end
	for _ = 1, 10 do
		-- fora dos muros (a borda da copa nunca atravessa a parede)
		local angle = rng:NextNumber(0, TAU)
		local diameter = rng:NextNumber(18, 28)
		local distance = 52 + diameter / 2 + rng:NextNumber(2, 10)
		ball(
			plants,
			"Copa",
			h(math.cos(angle) * distance, rng:NextNumber(30, 40), math.sin(angle) * distance),
			diameter,
			C.Canopy,
			Material.LeafyGrass,
			{ CastShadow = false }
		)
	end
	for _ = 1, 6 do
		local side = rng:NextInteger(0, 3)
		local along = rng:NextNumber(-38, 38)
		local x = side == 0 and -(HALF - 2) or side == 1 and (HALF - 2) or along
		local z = side == 2 and -(HALF - 2) or side == 3 and (HALF - 2) or along
		if math.abs(x) < 12 and z < 0 then
			continue -- não cobre a piscina
		end
		local size = rng:NextNumber(0.8, 1.8)
		deco(
			plants,
			"Entulho",
			Vector3.new(size * 1.3, size, size),
			CFrame.new(h(x, size / 2, z)) * CFrame.Angles(rng:NextNumber(0, 0.4), rng:NextNumber(0, TAU), 0),
			C.StoneDark,
			Material.Rock
		)
	end

	hub.Parent = root
end

-- API ------------------------------------------------------------------------------------------------------

-- Constrói (ou reconstrói) o lobby. Cede durante a construção; o cubículo do spawn e o MenuSpawn são criados
-- antes de qualquer pausa, para o primeiro personagem já nascer no lugar certo.
function LobbyWorld.Build(): Instance
	yieldStep = function() end
	local markers = getMarkersFolder()
	local old = workspace:FindFirstChild(WORLD_FOLDER)
	if old then
		old:Destroy()
	end
	local root = PartBuilder.model(WORLD_FOLDER, nil, "Folder")
	buildSpawnCubicle(root, markers)
	root.Parent = workspace

	yieldStep = PartBuilder.yielder(150)
	local ok, err = pcall(buildMenuScene, root, markers)
	if not ok then
		warn("[LobbyWorld] Erro ao construir o cenário do menu: " .. tostring(err))
	end
	ok, err = pcall(buildHub, root, markers)
	if not ok then
		warn("[LobbyWorld] Erro ao construir o hub: " .. tostring(err))
	end
	yieldStep = function() end
	return root
end

return LobbyWorld
