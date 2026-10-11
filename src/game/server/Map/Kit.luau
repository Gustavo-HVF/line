--!nonstrict
-- Ferramentas compartilhadas pelos construtores do mapa:
--   * criação de parts com contagem (orçamento) e pausas automáticas (PartBuilder.yielder);
--   * regiões nomeadas (workspace.Map.Regions) e pontos de arma (tag WeaponSpawn);
--   * chunks (Models com tag CullChunk) montados fora do workspace e anexados de uma vez;
--   * áreas bloqueadas e caminhos, para a vegetação aleatória não nascer em cima de nada.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartBuilder = require(ReplicatedStorage.Shared.Util.PartBuilder)
local Tags = require(ReplicatedStorage.Shared.Tags)

local Kit = {}

Kit.PART_BUDGET = 7000

-- Listas de tags reutilizadas (não altere estas tabelas).
Kit.D = { Tags.Destructible }
Kit.I = { Tags.Indestructible }
Kit.L = { Tags.LooseProp }

export type Region = { name: string, cframe: CFrame, size: Vector3, floor: number }

export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }

export type PathSegment = { ax: number, az: number, bx: number, bz: number, width: number }

export type Ctx = {
	map: Folder,
	regionsFolder: Folder,
	spawnsFolder: Folder,
	markersFolder: Folder,
	random: Random,
	regions: { Region },
	weaponSpawns: { BasePart },
	blocked: { Rect },
	paths: { PathSegment },
	partCount: number,
	budgetWarned: boolean,
	yield: () -> (),
}

-- Chaves especiais aceitas em `extra` (não são propriedades do Roblox):
--   Ghost = true    -> sem colisão, sem consulta espacial e sem toque (decoração pura)
--   NoShadow = true -> CastShadow = false
local SPECIAL_EXTRA = { Ghost = true, NoShadow = true }

function Kit.new(map: Folder, regionsFolder: Folder, spawnsFolder: Folder, markersFolder: Folder): Ctx
	return {
		map = map,
		regionsFolder = regionsFolder,
		spawnsFolder = spawnsFolder,
		markersFolder = markersFolder,
		random = Random.new(),
		regions = {},
		weaponSpawns = {},
		blocked = {},
		paths = {},
		partCount = 0,
		budgetWarned = false,
		yield = PartBuilder.yielder(180),
	}
end

local function applyGhost(part: BasePart)
	-- A ordem importa: CanQuery só pode ficar falso com CanCollide falso.
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

-- Cria uma part (qualquer classe) contando o orçamento e cedendo de tempos em tempos.
function Kit.part(ctx: Ctx, props: { [string]: any }, extra: { [string]: any }?): BasePart
	ctx.partCount += 1
	if ctx.partCount > Kit.PART_BUDGET and not ctx.budgetWarned then
		ctx.budgetWarned = true
		warn(("[MapBuilder] O mapa passou do orçamento de %d parts."):format(Kit.PART_BUDGET))
	end
	if extra then
		for key, value in extra do
			if not SPECIAL_EXTRA[key] then
				props[key] = value
			end
		end
	end
	local parent = props.Parent
	props.Parent = nil
	local part = PartBuilder.part(props)
	if extra then
		if extra.Ghost then
			applyGhost(part)
		end
		if extra.NoShadow then
			part.CastShadow = false
		end
	end
	if parent then
		part.Parent = parent
	end
	ctx.yield()
	return part
end

local function toCFrame(value: any): CFrame
	if typeof(value) == "Vector3" then
		return CFrame.new(value)
	end
	return value
end

-- Bloco (Shape Block). `cf` pode ser CFrame ou Vector3.
function Kit.box(
	ctx: Ctx,
	parent: Instance,
	name: string,
	cf: any,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	tags: { string }?,
	extra: { [string]: any }?
): BasePart
	return Kit.part(ctx, {
		Name = name,
		CFrame = toCFrame(cf),
		Size = size,
		Color = color,
		Material = material,
		Tags = tags,
		Parent = parent,
	}, extra)
end

-- Cunha (WedgePart). A rampa desce em direção ao -Z local (frente) e a face alta fica no +Z local.
function Kit.wedge(
	ctx: Ctx,
	parent: Instance,
	name: string,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	tags: { string }?,
	extra: { [string]: any }?
): BasePart
	return Kit.part(ctx, {
		ClassName = "WedgePart",
		Name = name,
		CFrame = cf,
		Size = size,
		Color = color,
		Material = material,
		Tags = tags,
		Parent = parent,
	}, extra)
end

-- Cilindro com eixo no X local de `cf` (é assim que o Roblox orienta cilindros).
function Kit.cylinderAlong(
	ctx: Ctx,
	parent: Instance,
	name: string,
	cf: CFrame,
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material,
	tags: { string }?,
	extra: { [string]: any }?
): BasePart
	return Kit.part(ctx, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		CFrame = cf,
		Size = Vector3.new(length, diameter, diameter),
		Color = color,
		Material = material,
		Tags = tags,
		Parent = parent,
	}, extra)
end

local VERTICAL = CFrame.Angles(0, 0, math.rad(90))

-- Cilindro em pé, com centro em `center`.
function Kit.cylinder(
	ctx: Ctx,
	parent: Instance,
	name: string,
	center: Vector3,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material,
	tags: { string }?,
	extra: { [string]: any }?
): BasePart
	return Kit.cylinderAlong(
		ctx,
		parent,
		name,
		CFrame.new(center) * VERTICAL,
		height,
		diameter,
		color,
		material,
		tags,
		extra
	)
end

-- Esfera.
function Kit.ball(
	ctx: Ctx,
	parent: Instance,
	name: string,
	center: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material,
	tags: { string }?,
	extra: { [string]: any }?
): BasePart
	return Kit.part(ctx, {
		Name = name,
		Shape = Enum.PartType.Ball,
		CFrame = CFrame.new(center),
		Size = Vector3.new(diameter, diameter, diameter),
		Color = color,
		Material = material,
		Tags = tags,
		Parent = parent,
	}, extra)
end

-- Luz pontual (sem sombra por padrão: sombras de luzes pontuais pesam no celular).
function Kit.light(part: BasePart, color: Color3, range: number, brightness: number?, shadows: boolean?): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness or 1
	light.Shadows = shadows == true
	light.Parent = part
	return light
end

-- Model comum (sem tag), ainda fora do workspace.
function Kit.model(name: string, parent: Instance?): Model
	return PartBuilder.model(name, parent) :: Model
end

-- Model com tag CullChunk (o cliente pode escondê-lo pela distância). Monte-o e depois chame Kit.attach.
function Kit.chunk(name: string): Model
	local model = Kit.model(name)
	PartBuilder.tag(model, Tags.CullChunk)
	return model
end

-- Define o pivô (centro usado no cálculo de distância) e coloca o model no pai de uma vez só.
function Kit.attach(model: Model, parent: Instance, pivot: Vector3)
	model.WorldPivot = CFrame.new(pivot)
	model.Parent = parent
end

-- Prende `others` na part raiz com WeldConstraint. Só a raiz fica ancorada: quando um evento
-- desancorar a raiz (LooseProp), o objeto inteiro voa junto.
function Kit.weldTo(root: BasePart, others: { BasePart })
	for _, part in others do
		if part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
			part.Anchored = false
		end
	end
end

-- Região nomeada (Part invisível em workspace.Map.Regions).
function Kit.region(ctx: Ctx, name: string, cframe: CFrame, size: Vector3, floor: number)
	local part = PartBuilder.part({
		Name = name,
		CFrame = cframe,
		Size = size,
		Transparency = 1,
		CastShadow = false,
		Attributes = { RegionName = name, Floor = floor },
	})
	applyGhost(part)
	part.Parent = ctx.regionsFolder
	table.insert(ctx.regions, { name = name, cframe = cframe, size = size, floor = floor })
end

-- Ponto de arma: Part invisível 1x1x1, ~1,5 stud acima do piso.
function Kit.weaponSpawn(ctx: Ctx, position: Vector3, area: string): BasePart
	local part = PartBuilder.part({
		Name = "WeaponSpawn",
		CFrame = CFrame.new(position),
		Size = Vector3.one,
		Transparency = 1,
		CastShadow = false,
		Tags = { Tags.WeaponSpawn },
		Attributes = { Area = area },
	})
	applyGhost(part)
	part.Parent = ctx.spawnsFolder
	table.insert(ctx.weaponSpawns, part)
	return part
end

-- Marcador invisível (spawns de jogador, tabuleiro).
function Kit.marker(ctx: Ctx, name: string, cframe: CFrame, size: Vector3, tag: string): BasePart
	local part = PartBuilder.part({
		Name = name,
		CFrame = cframe,
		Size = size,
		Transparency = 1,
		CastShadow = false,
		Tags = { tag },
	})
	applyGhost(part)
	part.Parent = ctx.markersFolder
	return part
end

-- Áreas bloqueadas para a vegetação aleatória -------------------------------------

function Kit.block(ctx: Ctx, minX: number, maxX: number, minZ: number, maxZ: number)
	table.insert(ctx.blocked, { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ })
end

function Kit.addPath(ctx: Ctx, a: Vector3, b: Vector3, width: number)
	table.insert(ctx.paths, { ax = a.X, az = a.Z, bx = b.X, bz = b.Z, width = width })
end

local function distanceToSegment(px: number, pz: number, seg: PathSegment): number
	local dx, dz = seg.bx - seg.ax, seg.bz - seg.az
	local lengthSq = dx * dx + dz * dz
	local t = 0
	if lengthSq > 0 then
		t = math.clamp(((px - seg.ax) * dx + (pz - seg.az) * dz) / lengthSq, 0, 1)
	end
	local cx, cz = seg.ax + dx * t, seg.az + dz * t
	return math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2)
end

-- true se o ponto (x, z) estiver numa área bloqueada ou perto de um caminho (com margem).
function Kit.isBlocked(ctx: Ctx, x: number, z: number, margin: number?): boolean
	local m = margin or 0
	for _, rect in ctx.blocked do
		if x >= rect.minX - m and x <= rect.maxX + m and z >= rect.minZ - m and z <= rect.maxZ + m then
			return true
		end
	end
	for _, seg in ctx.paths do
		if distanceToSegment(x, z, seg) < seg.width / 2 + m then
			return true
		end
	end
	return false
end

return Kit
