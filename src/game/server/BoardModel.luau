--!nonstrict
-- Geometria do tabuleiro amaldiçoado (tudo por código, sem assets):
--   * caixa de madeira escura entalhada, aberta (≈ 5 x 0,6 x 3,5 studs);
--   * trilha de casas em espiral retangular, com a casa de partida e a última casa destacadas;
--   * "vidro" central com texto verde brilhante, onde aparecem os enigmas;
--   * a PEÇA única do grupo (uma estatueta de jade);
--   * os dados (cubos com pips nas 6 faces; faces opostas somam 7) e a leitura da face de cima.
-- Todas as parts recebem a tag Indestructible. Quem posiciona e anima é o BoardService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local PartBuilder = require(ReplicatedStorage.Shared.Util.PartBuilder)
local Tags = require(ReplicatedStorage.Shared.Tags)

local BoardModel = {}

export type Board = {
	model: Model,
	base: BasePart,
	-- parts que ficam ancoradas no chão e são soldadas à base quando alguém carrega (inclui base e pieceRoot)
	parts: { BasePart },
	-- parts visuais da peça: sempre desancoradas e soldadas ao pieceRoot
	pieceParts: { BasePart },
	pieceRoot: BasePart,
	glass: BasePart,
	glassLight: PointLight,
	riddleLabel: TextLabel,
	finalLight: PointLight,
	spaceCount: number,
	spaceOffsets: { [number]: Vector3 }, -- índice 0 (partida) até spaceCount, em coordenadas locais da base
	original: { [BasePart]: { collide: boolean, query: boolean } },
}

-- Medidas ------------------------------------------------------------------------------

local BASE_SIZE = Vector3.new(5, 0.3, 3.5)
local RIM_HEIGHT = 0.3
local RIM_THICKNESS = 0.16
local TOP_Y = BASE_SIZE.Y / 2 -- topo da base (coordenadas locais da base)
local SPACE_SIZE = 0.36
local SPACE_HEIGHT = 0.03
local PIECE_Y = TOP_Y + SPACE_HEIGHT + 0.03 -- centro do disco da peça
local DIE_SIZE = 0.8

BoardModel.BASE_SIZE = BASE_SIZE
BoardModel.TOTAL_HEIGHT = BASE_SIZE.Y + RIM_HEIGHT
BoardModel.DIE_SIZE = DIE_SIZE

-- Cores -------------------------------------------------------------------------------

local WOOD_DARK = Color3.fromRGB(52, 32, 18)
local WOOD = Color3.fromRGB(84, 52, 28)
local GOLD = Color3.fromRGB(196, 156, 64)
local JADE = Color3.fromRGB(36, 122, 86)
local GLASS_COLOR = Color3.fromRGB(18, 64, 36)
local RIDDLE_COLOR = Color3.fromRGB(120, 255, 140)
local SPACE_COLORS = {
	Color3.fromRGB(150, 116, 70),
	Color3.fromRGB(92, 118, 62),
}
local MARKER_COLOR = Color3.fromRGB(176, 120, 52)
local START_COLOR = Color3.fromRGB(226, 214, 180)
local DIE_COLOR = Color3.fromRGB(236, 228, 206)
local PIP_COLOR = Color3.fromRGB(46, 28, 16)

-- Espiral retangular por onde a trilha passa (X/Z locais da base). Começa num canto, dá uma volta
-- completa pela borda, entra num anel interno e termina ao lado do vidro central.
local PATH = {
	Vector2.new(-2.08, -1.36),
	Vector2.new(2.08, -1.36),
	Vector2.new(2.08, 1.36),
	Vector2.new(-2.08, 1.36),
	Vector2.new(-2.08, -0.9),
	Vector2.new(1.62, -0.9),
	Vector2.new(1.62, 0.9),
	Vector2.new(-1.62, 0.9),
	Vector2.new(-1.62, 0),
}

-- Faces do dado e seus valores (faces opostas somam 7).
local DIE_FACES = {
	{ face = Enum.NormalId.Front, value = 1 },
	{ face = Enum.NormalId.Back, value = 6 },
	{ face = Enum.NormalId.Top, value = 2 },
	{ face = Enum.NormalId.Bottom, value = 5 },
	{ face = Enum.NormalId.Right, value = 3 },
	{ face = Enum.NormalId.Left, value = 4 },
}

-- Posição dos pips (fração da face).
local PIP_LAYOUT = {
	[1] = { { 0.5, 0.5 } },
	[2] = { { 0.26, 0.26 }, { 0.74, 0.74 } },
	[3] = { { 0.26, 0.26 }, { 0.5, 0.5 }, { 0.74, 0.74 } },
	[4] = { { 0.26, 0.26 }, { 0.74, 0.26 }, { 0.26, 0.74 }, { 0.74, 0.74 } },
	[5] = { { 0.26, 0.26 }, { 0.74, 0.26 }, { 0.5, 0.5 }, { 0.26, 0.74 }, { 0.74, 0.74 } },
	[6] = { { 0.26, 0.22 }, { 0.26, 0.5 }, { 0.26, 0.78 }, { 0.74, 0.22 }, { 0.74, 0.5 }, { 0.74, 0.78 } },
}

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cilindros do Roblox têm o eixo em X; isto os deixa em pé

-- Distribui count+1 pontos (0..count) igualmente espaçados ao longo da espiral.
local function samplePath(count: number): { [number]: Vector3 }
	local segments = {}
	local total = 0
	for i = 1, #PATH - 1 do
		local a, b = PATH[i], PATH[i + 1]
		local length = (b - a).Magnitude
		table.insert(segments, { a = a, b = b, length = length })
		total += length
	end

	local points = {}
	for index = 0, count do
		local target = total * index / count
		local accumulated = 0
		local point = PATH[#PATH]
		for _, segment in segments do
			if target <= accumulated + segment.length then
				local alpha = segment.length > 0 and (target - accumulated) / segment.length or 0
				point = segment.a:Lerp(segment.b, alpha)
				break
			end
			accumulated += segment.length
		end
		points[index] = Vector3.new(point.X, TOP_Y, point.Y)
	end
	return points
end

local function makeSurfaceText(part: BasePart, face: Enum.NormalId, props: { [string]: any }): (SurfaceGui, TextLabel)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Texto"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = props.PixelsPerStud or 100
	gui.LightInfluence = props.LightInfluence or 1
	gui.Brightness = props.Brightness or 1
	gui.MaxDistance = props.MaxDistance or 80
	gui.ClipsDescendants = true
	gui.ResetOnSpawn = false

	local label = Instance.new("TextLabel")
	label.Name = "Rotulo"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Fondamento
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = props.TextColor3 or RIDDLE_COLOR
	label.TextStrokeColor3 = props.TextStrokeColor3 or Color3.fromRGB(0, 40, 12)
	label.TextStrokeTransparency = props.TextStrokeTransparency or 0.5
	label.Text = props.Text or ""
	label.Parent = gui

	local padding = Instance.new("UIPadding")
	local px = UDim.new(0, props.Padding or 6)
	padding.PaddingLeft = px
	padding.PaddingRight = px
	padding.PaddingTop = px
	padding.PaddingBottom = px
	padding.Parent = label

	if props.MaxTextSize then
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = props.MaxTextSize
		constraint.Parent = label
	end

	gui.Parent = part
	return gui, label
end

-- Constrói o tabuleiro com a base na origem (fundo em Y = 0) dentro de `parent`.
-- O pivot do Model fica no centro do FUNDO da base: PivotTo(cframe no chão) apoia o tabuleiro no chão.
function BoardModel.Build(parent: Instance, spaceCount: number?): Board
	local count = math.max(math.floor(spaceCount or GameConfig.BOARD_SPACES), 2)

	local model = Instance.new("Model")
	model.Name = "Tabuleiro"

	local parts: { BasePart } = {}
	local pieceParts: { BasePart } = {}
	local original = {}

	-- Cria uma part do tabuleiro. collide = true só para base e bordas.
	local function add(props: { [string]: any }, collide: boolean?, isPieceChild: boolean?): BasePart
		props.Parent = props.Parent or model
		props.Tags = { Tags.Indestructible }
		props.CanTouch = false
		props.Massless = true
		props.Locked = true
		if props.CastShadow == nil then
			props.CastShadow = false
		end
		local part = PartBuilder.part(props)
		-- CanQuery só pode ser falso com CanCollide falso: ajusta nesta ordem.
		if collide then
			part.CanCollide = true
			part.CanQuery = true
		else
			part.CanCollide = false
			part.CanQuery = false
		end
		original[part] = { collide = part.CanCollide, query = part.CanQuery }
		if isPieceChild then
			table.insert(pieceParts, part)
		else
			table.insert(parts, part)
		end
		return part
	end

	local baseCFrame = CFrame.new(0, BASE_SIZE.Y / 2, 0)
	local function at(x: number, y: number, z: number): CFrame
		return baseCFrame * CFrame.new(x, y, z)
	end

	-- Base e bordas da caixa aberta ------------------------------------------------------
	local base = add({
		Name = "Base",
		Size = BASE_SIZE,
		CFrame = baseCFrame,
		Color = WOOD_DARK,
		Material = Enum.Material.Wood,
		CastShadow = true,
	}, true)
	base.PivotOffset = CFrame.new(0, -BASE_SIZE.Y / 2, 0)

	local rimY = TOP_Y + RIM_HEIGHT / 2
	local halfX, halfZ = BASE_SIZE.X / 2, BASE_SIZE.Z / 2
	for _, sign in { -1, 1 } do
		add({
			Name = "BordaLonga",
			Size = Vector3.new(BASE_SIZE.X, RIM_HEIGHT, RIM_THICKNESS),
			CFrame = at(0, rimY, sign * (halfZ - RIM_THICKNESS / 2)),
			Color = WOOD,
			Material = Enum.Material.Wood,
			CastShadow = true,
		}, true)
		add({
			Name = "BordaCurta",
			Size = Vector3.new(RIM_THICKNESS, RIM_HEIGHT, BASE_SIZE.Z - RIM_THICKNESS * 2),
			CFrame = at(sign * (halfX - RIM_THICKNESS / 2), rimY, 0),
			Color = WOOD,
			Material = Enum.Material.Wood,
			CastShadow = true,
		}, true)
		-- Entalhe dourado no topo das bordas longas
		add({
			Name = "Entalhe",
			Size = Vector3.new(3.4, 0.03, 0.06),
			CFrame = at(0, TOP_Y + RIM_HEIGHT + 0.015, sign * (halfZ - RIM_THICKNESS / 2)),
			Color = GOLD,
			Material = Enum.Material.Metal,
		})
		-- Dobradiças na borda de trás (a caixa abre como um livro)
		add({
			Name = "Dobradica",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 0.12, 0.12),
			CFrame = at(sign * 1.2, TOP_Y + 0.05, -(halfZ + 0.05)),
			Color = GOLD,
			Material = Enum.Material.Metal,
		})
	end

	-- Cantoneiras douradas
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			add({
				Name = "Cantoneira",
				Size = Vector3.new(0.24, 0.1, 0.24),
				CFrame = at(sx * (halfX - 0.1), TOP_Y + RIM_HEIGHT + 0.05, sz * (halfZ - 0.1)),
				Color = GOLD,
				Material = Enum.Material.Metal,
			})
		end
	end

	-- Placa com o nome do jogo na frente da caixa
	local plate = add({
		Name = "Placa",
		Size = Vector3.new(1.8, 0.36, 0.03),
		CFrame = at(0, 0.15, halfZ + 0.015),
		Color = GOLD,
		Material = Enum.Material.Metal,
	})
	makeSurfaceText(plate, Enum.NormalId.Back, {
		Text = GameConfig.GAME_TITLE,
		TextColor3 = WOOD_DARK,
		TextStrokeTransparency = 1,
		PixelsPerStud = 80,
		MaxDistance = 40,
		Padding = 2,
	})

	-- Vidro central do enigma -------------------------------------------------------------
	add({
		Name = "MolduraVidro",
		Size = Vector3.new(2.46, 0.025, 1.16),
		CFrame = at(0.15, TOP_Y + 0.0125, 0),
		Color = GOLD,
		Material = Enum.Material.Metal,
	})
	local glass = add({
		Name = "Vidro",
		Size = Vector3.new(2.3, 0.04, 1.0),
		CFrame = at(0.15, TOP_Y + 0.025 + 0.02, 0),
		Color = GLASS_COLOR,
		Material = Enum.Material.Glass,
		Transparency = 0.15,
		Reflectance = 0.1,
	})
	local _, riddleLabel = makeSurfaceText(glass, Enum.NormalId.Top, {
		Text = GameConfig.GAME_TITLE,
		LightInfluence = 0,
		Brightness = 2,
		PixelsPerStud = 110,
		MaxDistance = 70,
		MaxTextSize = 40,
	})
	local glassLight = Instance.new("PointLight")
	glassLight.Name = "Brilho"
	glassLight.Color = Color3.fromRGB(90, 255, 120)
	glassLight.Range = 5
	glassLight.Brightness = 0.6
	glassLight.Shadows = false
	glassLight.Parent = glass

	-- Trilha de casas -------------------------------------------------------------------------
	local offsets = samplePath(count)
	local finalLight: PointLight? = nil
	for index = 0, count do
		local offset = offsets[index]
		local size, color, material = SPACE_SIZE, SPACE_COLORS[index % 2 + 1], Enum.Material.SmoothPlastic
		local name = "Casa" .. index
		if index == 0 then
			size, color, name = 0.42, START_COLOR, "CasaPartida"
		elseif index == count then
			size, color, material, name = 0.46, JADE, Enum.Material.Neon, "CasaFinal"
		elseif index % 5 == 0 then
			color = MARKER_COLOR
		end
		local space = add({
			Name = name,
			Size = Vector3.new(size, SPACE_HEIGHT, size),
			CFrame = at(offset.X, TOP_Y + SPACE_HEIGHT / 2, offset.Z),
			Color = color,
			Material = material,
		})
		if index == count then
			local light = Instance.new("PointLight")
			light.Name = "BrilhoFinal"
			light.Color = JADE
			light.Range = 3
			light.Brightness = 0.8
			light.Shadows = false
			light.Parent = space
			finalLight = light
		end
	end

	-- A PEÇA única do grupo ------------------------------------------------------------------
	-- Ponto de extensão para skins futuras: no futuro, BoardModel.Build poderá receber um "skinId" e trocar
	-- apenas as parts visuais abaixo (disco, corpo, faixa, cabeça), mantendo o pieceRoot invisível como
	-- âncora de animação. NÃO implementado agora (fora do escopo desta versão).
	local pieceCFrame = at(offsets[0].X, PIECE_Y, offsets[0].Z)
	local pieceModel = Instance.new("Model")
	pieceModel.Name = "Peca"
	pieceModel.Parent = model
	local pieceRoot = add({
		Name = "PecaRaiz",
		Size = Vector3.new(0.3, 0.06, 0.3),
		CFrame = pieceCFrame,
		Transparency = 1,
		Parent = pieceModel,
	})
	pieceModel.PrimaryPart = pieceRoot

	local function piecePart(props: { [string]: any }, offsetY: number, cylinder: boolean)
		props.Parent = pieceModel
		props.Anchored = false
		props.CFrame = pieceCFrame * CFrame.new(0, offsetY, 0) * (cylinder and UPRIGHT or CFrame.identity)
		local part = add(props, false, true)
		PartBuilder.weld(part, pieceRoot)
		return part
	end
	piecePart({
		Name = "Disco",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.06, 0.34, 0.34),
		Color = GOLD,
		Material = Enum.Material.Metal,
	}, 0, true)
	piecePart({
		Name = "Corpo",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.32, 0.2, 0.2),
		Color = JADE,
		Material = Enum.Material.Marble,
	}, 0.19, true)
	piecePart({
		Name = "Faixa",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.04, 0.24, 0.24),
		Color = GOLD,
		Material = Enum.Material.Metal,
	}, 0.35, true)
	piecePart({
		Name = "Cabeca",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.22, 0.22, 0.22),
		Color = JADE,
		Material = Enum.Material.Marble,
	}, 0.48, false)

	model.PrimaryPart = base
	model.Parent = parent

	return {
		model = model,
		base = base,
		parts = parts,
		pieceParts = pieceParts,
		pieceRoot = pieceRoot,
		glass = glass,
		glassLight = glassLight,
		riddleLabel = riddleLabel,
		finalLight = finalLight :: PointLight,
		spaceCount = count,
		spaceOffsets = offsets,
		original = original,
	}
end

-- CFrame do pieceRoot quando a peça está na casa `space` (0 = partida), relativo à posição atual da base.
function BoardModel.GetPieceCFrame(board: Board, space: number): CFrame
	local index = math.clamp(math.floor(space), 0, board.spaceCount)
	local offset = board.spaceOffsets[index]
	return board.base.CFrame * CFrame.new(offset.X, PIECE_Y, offset.Z)
end

-- Texto do vidro central (nil volta ao nome do jogo).
function BoardModel.SetRiddle(board: Board, text: string?)
	board.riddleLabel.Text = text or GameConfig.GAME_TITLE
end

-- Cria um dado (desancorado) em `cframe` dentro de `parent`.
function BoardModel.CreateDie(parent: Instance, cframe: CFrame): BasePart
	local die = PartBuilder.part({
		Name = "Dado",
		Size = Vector3.new(DIE_SIZE, DIE_SIZE, DIE_SIZE),
		CFrame = cframe,
		Color = DIE_COLOR,
		Material = Enum.Material.SmoothPlastic,
		CanTouch = false,
		CastShadow = true,
		CustomPhysicalProperties = PhysicalProperties.new(1.2, 0.55, 0.25, 1, 1),
		Tags = { Tags.Indestructible },
	})

	for _, entry in DIE_FACES do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Face" .. entry.value
		gui.Face = entry.face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(100, 100)
		gui.LightInfluence = 1
		gui.MaxDistance = 120
		gui.ResetOnSpawn = false
		for _, pip in PIP_LAYOUT[entry.value] do
			local dot = Instance.new("Frame")
			dot.Name = "Pip"
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromScale(pip[1], pip[2])
			dot.Size = UDim2.fromScale(0.2, 0.2)
			dot.BackgroundColor3 = PIP_COLOR
			dot.BorderSizePixel = 0
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = dot
			dot.Parent = gui
		end
		gui.Parent = die
	end

	die.Anchored = false
	die.Parent = parent
	return die
end

-- Lê o valor da face de cima: a face cuja normal (no mundo) aponta mais para +Y.
function BoardModel.ReadDie(die: BasePart): number
	local best, bestDot = 1, -math.huge
	for _, entry in DIE_FACES do
		local normal = die.CFrame:VectorToWorldSpace(Vector3.FromNormalId(entry.face))
		if normal.Y > bestDot then
			best, bestDot = entry.value, normal.Y
		end
	end
	return best
end

return BoardModel
