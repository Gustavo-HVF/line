--!nonstrict
-- Destruição do cenário (servidor).
--   * Fracture: quebra uma part com a tag Destructible. Blocos (Part com Shape Block) são cortados no espaço
--     LOCAL da part: abre-se um "buraco" em volta do ponto de impacto (raio proporcional ao impulso), dividido
--     em grade de ≈ FRACTURE_CHUNK_SIZE; os pedaços do buraco soltam e voam, e o resto da part vira até 6
--     blocos que continuam ancorados e Destructible (parede parcialmente quebrada, que pode quebrar de novo).
--     Eixos finos (≤ 2 studs) nunca são divididos e o total de pedaços respeita MAX_CHUNKS_PER_FRACTURE.
--     Outras formas (WedgePart, cilindros, malhas...) apenas desancoram e viram pedaço inteiras.
--   * RegisterDebris: pedaços com física vão para workspace.Debris (grupo de colisão "Debris", que não
--     colide consigo mesmo), somem com fade depois de DEBRIS_LIFETIME e respeitam MAX_DEBRIS.
--   * Explode: explosão visual, quebra as parts mais próximas, solta/empurra objetos, dano e tremor.
-- Extras usados pelos eventos físicos (fora do contrato): GetLooseRoot, ReleaseProp, Push, IsProtected.
-- Pedaços e objetos soltos ficam com a física no servidor (não pesa nos celulares dos jogadores).

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local Tags = require(ReplicatedStorage.Shared.Tags)

local CombatUtil = require(script.Parent.CombatUtil)
local PhysUtil = require(script.Parent.EventHelpers.PhysUtil)

local DestructionService = {}

-- Ajustes --------------------------------------------------------------------------------

local DEBRIS_GROUP = "Debris"
local TICK = 0.25 -- intervalo da fila de pedaços (tempo de vida e fade em degraus)
local THIN_AXIS = 2 -- eixo com até isto de espessura não é dividido
local MIN_REMAINDER = 0.6 -- sobra mais fina que isto é incorporada ao buraco (sem lascas)
local MIN_RELEASE_RADIUS = 2
local MAX_RELEASE_RADIUS = 12
local DEFAULT_IMPULSE = 50
local MAX_IMPULSE = 250
local MAX_PIECE_SPEED = 160
local MAX_SPIN = 14
local EXPLODE_MAX_FRACTURES = 8
local EXPLODE_MAX_PUSH = 60
local EXPLODE_MAX_RADIUS = 120
local MAX_EXTRA_PARTS = 16 -- partes soldadas que acompanham um pedaço registrado
local CRUMBLE_INTERVAL = 0.25 -- intervalo mínimo entre sons de desmoronamento
local FALL_LIMIT_Y = GameConfig.WATER_LEVEL_Y - 40 -- pedaço que caiu no mar some na hora
local EXPLOSION_FLASH = Color3.fromRGB(255, 196, 120)

-- Estado ----------------------------------------------------------------------------------

local initialized = false
local loopStarted = false
local debrisFolder: Folder? = nil
local groupReady = false
local groupFailed = false
local entries: { any } = {} -- em ordem de chegada (o primeiro é o mais antigo)
local entryByPart: { [BasePart]: any } = {}
local serverOwned: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local lastCrumble = 0
local random = Random.new()

-- Preparação ------------------------------------------------------------------------------

local function ensureFolder(): Folder
	local folder = debrisFolder
	if folder and folder.Parent == workspace then
		return folder
	end
	local existing = workspace:FindFirstChild("Debris")
	if existing and existing:IsA("Folder") then
		debrisFolder = existing
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "Debris"
	created.Parent = workspace
	debrisFolder = created
	return created
end

local function ensureGroup()
	if groupReady or groupFailed then
		return
	end
	local ok, err = pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(DEBRIS_GROUP) then
			PhysicsService:RegisterCollisionGroup(DEBRIS_GROUP)
		end
		-- Pedaço não colide com pedaço: muito menos contatos para a física resolver.
		PhysicsService:CollisionGroupSetCollidable(DEBRIS_GROUP, DEBRIS_GROUP, false)
	end)
	if ok then
		groupReady = true
	else
		groupFailed = true
		warn("[DestructionService] Não foi possível criar o grupo de colisão 'Debris': " .. tostring(err))
	end
end

local startLoop: () -> ()

local function ensureSetup()
	ensureFolder()
	ensureGroup()
	startLoop()
end

-- Proteções -------------------------------------------------------------------------------

local function folderContains(name: string, instance: Instance): boolean
	local folder = workspace:FindFirstChild(name)
	return folder ~= nil and instance:IsDescendantOf(folder)
end

-- Personagens, inimigos e o tabuleiro: nunca quebrados, empurrados nem registrados como pedaço.
local function isLivingOrBoard(instance: Instance): boolean
	if folderContains("Board", instance) or folderContains("NPCs", instance) then
		return true
	end
	return CombatUtil.FindPlayerFromPart(instance) ~= nil or CombatUtil.FindEnemyFromPart(instance) ~= nil
end

-- true se a instância não deve ser tocada pela destruição (Indestructible, vivos, tabuleiro, armas).
function DestructionService.IsProtected(instance: Instance): boolean
	if typeof(instance) ~= "Instance" then
		return true
	end
	if CollectionService:HasTag(instance, Tags.Indestructible) or CollectionService:HasTag(instance, Tags.Weapon) then
		return true
	end
	if instance:FindFirstAncestorOfClass("Tool") then
		return true
	end
	return isLivingOrBoard(instance)
end

function DestructionService.IsDestructible(part: BasePart): boolean
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return false
	end
	if not part:IsDescendantOf(workspace) then
		return false
	end
	if not CollectionService:HasTag(part, Tags.Destructible) or CollectionService:HasTag(part, Tags.Debris) then
		return false
	end
	return not DestructionService.IsProtected(part)
end

-- Física ----------------------------------------------------------------------------------

-- O servidor passa a simular a peça (só funciona em parts soltas; falha calada em ancoradas/soldadas).
local function takeOwnership(part: BasePart)
	if serverOwned[part] then
		return
	end
	local ok = pcall(part.SetNetworkOwner, part, nil)
	if ok then
		serverOwned[part] = true
	end
end

local function clampVector(vector: Vector3, maxMagnitude: number): Vector3
	local magnitude = vector.Magnitude
	if magnitude ~= magnitude then
		return Vector3.zero
	end
	if magnitude > maxMagnitude then
		return vector.Unit * maxMagnitude
	end
	return vector
end

local function randomSpin(scale: number): Vector3
	local s = math.min(scale, MAX_SPIN)
	return Vector3.new(random:NextNumber(-s, s), random:NextNumber(-s, s), random:NextNumber(-s, s))
end

-- Aplica velocidade numa part solta (ou no conjunto soldado dela).
function DestructionService.Push(part: BasePart, velocity: Vector3, angular: Vector3?)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or typeof(velocity) ~= "Vector3" then
		return
	end
	if part.Anchored or not part:IsDescendantOf(workspace) or isLivingOrBoard(part) then
		return
	end
	takeOwnership(part)
	part.AssemblyLinearVelocity = clampVector(velocity, MAX_PIECE_SPEED * 1.5)
	if typeof(angular) == "Vector3" then
		part.AssemblyAngularVelocity = clampVector(angular, MAX_SPIN * 2)
	end
end

-- Part raiz de um objeto LooseProp (a própria part, a raiz do conjunto soldado ou uma vizinha marcada).
function DestructionService.GetLooseRoot(part: BasePart): BasePart?
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return nil
	end
	if CollectionService:HasTag(part, Tags.LooseProp) then
		return part
	end
	local root = part.AssemblyRootPart
	if root and root ~= part and CollectionService:HasTag(root, Tags.LooseProp) then
		return root
	end
	if not part.Anchored then
		-- Depois de solto, a raiz do conjunto pode ser outra part: procura a marcada entre as soldadas.
		local ok, connected = pcall(part.GetConnectedParts, part, true)
		if ok then
			for index, other in connected do
				if index > MAX_EXTRA_PARTS then
					break
				end
				if CollectionService:HasTag(other, Tags.LooseProp) then
					return other
				end
			end
		end
	end
	return nil
end

-- Desancora um objeto LooseProp (o conjunto soldado vai junto) e, se pedido, aplica velocidade.
-- Retorna a part raiz solta, ou nil se a part não for um objeto solto válido.
function DestructionService.ReleaseProp(part: BasePart, velocity: Vector3?): BasePart?
	local root = DestructionService.GetLooseRoot(part)
	if not root or not root:IsDescendantOf(workspace) or DestructionService.IsProtected(root) then
		return nil
	end
	if root.Anchored then
		root.Anchored = false
	end
	if typeof(velocity) == "Vector3" then
		DestructionService.Push(root, velocity, randomSpin(velocity.Magnitude * 0.1))
	else
		takeOwnership(root)
	end
	return root
end

-- Fila de pedaços ---------------------------------------------------------------------------

local function destroyEntry(entry)
	for _, part in entry.parts do
		entryByPart[part] = nil
		serverOwned[part] = nil
		if part.Parent then
			part:Destroy()
		end
	end
end

local function removeEntryAt(index: number)
	local entry = table.remove(entries, index)
	if entry then
		destroyEntry(entry)
	end
end

local function startFade(entry, now: number)
	entry.fadeStart = now
	entry.base = {}
	for _, part in entry.parts do
		if part.Parent then
			entry.base[part] = part.Transparency
			-- Parado e sem colisão durante o fade: ninguém tropeça num pedaço "fantasma".
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
		end
	end
end

local function stepEntries()
	local now = os.clock()
	local fadeTime = math.max(GameConfig.DEBRIS_FADE_TIME, 0.05)
	for index = #entries, 1, -1 do
		local entry = entries[index]
		local part = entry.part
		if not part.Parent or not part:IsDescendantOf(workspace) then
			removeEntryAt(index)
		elseif entry.fadeStart then
			local alpha = (now - entry.fadeStart) / fadeTime
			if alpha >= 1 then
				removeEntryAt(index)
			else
				for fading, base in entry.base do
					if fading.Parent then
						fading.Transparency = base + (1 - base) * alpha
					end
				end
			end
		elseif part.Position.Y < FALL_LIMIT_Y then
			removeEntryAt(index)
		elseif now >= entry.expireAt then
			startFade(entry, now)
		end
	end
end

function startLoop()
	if loopStarted then
		return
	end
	loopStarted = true
	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(stepEntries)
			if not ok then
				warn("[DestructionService] Erro na fila de pedaços: " .. tostring(err))
			end
		end
	end)
end

local function prepareDebrisPart(part: BasePart, folder: Folder)
	part.Parent = folder
	if groupReady then
		part.CollisionGroup = DEBRIS_GROUP
	end
	CollectionService:RemoveTag(part, Tags.Destructible)
	CollectionService:RemoveTag(part, Tags.LooseProp)
	CollectionService:AddTag(part, Tags.Debris)
end

function DestructionService.RegisterDebris(part: BasePart, lifetime: number?)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part.Parent then
		return
	end
	if isLivingOrBoard(part) then
		return
	end
	ensureSetup()
	local now = os.clock()
	local life = GameConfig.DEBRIS_LIFETIME
	if type(lifetime) == "number" and lifetime == lifetime then
		life = math.clamp(lifetime, 0.5, 600)
	end

	local existing = entryByPart[part]
	if existing then
		if not existing.fadeStart then
			existing.expireAt = now + life
		end
		return
	end

	-- Partes soldadas e soltas (ex.: pernas de uma cadeira) acompanham a part e somem junto.
	local parts = { part }
	if not part.Anchored then
		local ok, connected = pcall(part.GetConnectedParts, part, true)
		if ok then
			for _, other in connected do
				if #parts > MAX_EXTRA_PARTS then
					break
				end
				if other ~= part and not other.Anchored and not entryByPart[other] and not isLivingOrBoard(other) then
					table.insert(parts, other)
				end
			end
		end
	end

	local folder = ensureFolder()
	for _, member in parts do
		prepareDebrisPart(member, folder)
	end
	local entry = { part = part, parts = parts, expireAt = now + life, fadeStart = nil, base = nil }
	table.insert(entries, entry)
	for _, member in parts do
		entryByPart[member] = entry
	end

	-- Limite global: os mais antigos somem na hora.
	local maxDebris = math.max(math.floor(GameConfig.MAX_DEBRIS), 1)
	while #entries > maxDebris do
		removeEntryAt(1)
	end
end

-- Fratura -----------------------------------------------------------------------------------

local function playCrumble(position: Vector3)
	local now = os.clock()
	if now - lastCrumble < CRUMBLE_INTERVAL then
		return
	end
	lastCrumble = now
	SoundUtil.Play("Crumble", { Position = position, RollOffMaxDistance = 200, Volume = 0.7 })
end

-- Raio do buraco a partir do impulso (impulso 50 ≈ 4,5 studs).
local function releaseRadiusFor(impulse: number): number
	return math.clamp(1.5 + impulse * 0.06, MIN_RELEASE_RADIUS, MAX_RELEASE_RADIUS)
end

local function axisCount(length: number, chunk: number): number
	if length <= THIN_AXIS then
		return 1
	end
	return math.max(1, math.floor(length / chunk + 0.5))
end

local function newPiece(source: BasePart, cframe: CFrame, size: Vector3): Part
	local piece = Instance.new("Part")
	piece.Name = source.Name
	piece.Anchored = true
	piece.TopSurface = Enum.SurfaceType.Smooth
	piece.BottomSurface = Enum.SurfaceType.Smooth
	piece.Material = source.Material
	piece.MaterialVariant = source.MaterialVariant
	piece.Color = source.Color
	piece.Transparency = source.Transparency
	piece.Reflectance = source.Reflectance
	piece.CastShadow = source.CastShadow
	piece.Size = size
	piece.CFrame = cframe
	return piece
end

-- Pedaço que continua no lugar: mesma colisão, tags e atributos da original (pode quebrar de novo).
local function setupAnchoredPiece(piece: Part, source: BasePart, sourceTags: { string }, attributes)
	piece.CanCollide = source.CanCollide
	piece.CanTouch = source.CanTouch
	piece.CanQuery = source.CanQuery or source.CanCollide
	piece.CollisionGroup = source.CollisionGroup
	for _, tag in sourceTags do
		if tag ~= Tags.Debris then
			CollectionService:AddTag(piece, tag)
		end
	end
	CollectionService:AddTag(piece, Tags.Destructible)
	for name, value in attributes do
		piece:SetAttribute(name, value)
	end
end

-- Lança um pedaço solto: para longe da origem do impacto, um pouco para cima, girando.
local function launch(part: BasePart, origin: Vector3, speed: number)
	local direction = part.Position - origin
	if direction.Magnitude < 0.05 then
		direction = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(0, 1), random:NextNumber(-1, 1))
	end
	if direction.Magnitude < 0.05 then
		direction = Vector3.yAxis
	end
	local s = speed * random:NextNumber(0.6, 1)
	local velocity = direction.Unit * s + Vector3.new(0, speed * random:NextNumber(0.15, 0.3), 0)
	part.Anchored = false
	takeOwnership(part)
	part.AssemblyLinearVelocity = clampVector(velocity, MAX_PIECE_SPEED)
	part.AssemblyAngularVelocity = randomSpin(speed * 0.15 + 2)
end

-- Solta a part inteira (formas que não são bloco, ou bloco pequeno demais para dividir).
local function releaseWhole(part: BasePart, origin: Vector3, speed: number): { BasePart }
	CollectionService:RemoveTag(part, Tags.Destructible)
	local folder = ensureFolder()
	part.Parent = folder
	launch(part, origin, speed)
	DestructionService.RegisterDebris(part)
	playCrumble(part.Position)
	return { part }
end

-- Núcleo da fratura. `holeRadius`: meia-largura do buraco; `speed`: velocidade dos pedaços;
-- `origin`: de onde os pedaços são empurrados (ponto de impacto ou centro da explosão).
local function fracture(
	part: BasePart,
	impact: Vector3,
	holeRadius: number,
	speed: number,
	origin: Vector3
): { BasePart }
	if not part:IsA("Part") or (part :: Part).Shape ~= Enum.PartType.Block then
		return releaseWhole(part, origin, speed)
	end

	ensureSetup()
	local cframe = part.CFrame
	local size = part.Size
	local sizes = { size.X, size.Y, size.Z }
	local halves = { size.X / 2, size.Y / 2, size.Z / 2 }
	local localImpact = cframe:PointToObjectSpace(impact)
	local centerOf = { localImpact.X, localImpact.Y, localImpact.Z }

	-- 1. Intervalo do buraco em cada eixo (eixo fino: inteiro).
	local lo, hi = {}, {}
	for axis = 1, 3 do
		local half = halves[axis]
		local c = math.clamp(centerOf[axis], -half, half)
		if sizes[axis] <= THIN_AXIS then
			lo[axis], hi[axis] = -half, half
		else
			local a = math.max(-half, c - holeRadius)
			local b = math.min(half, c + holeRadius)
			if a + half < MIN_REMAINDER then
				a = -half
			end
			if half - b < MIN_REMAINDER then
				b = half
			end
			lo[axis], hi[axis] = a, b
		end
	end

	-- 2. Sobras (até 6 blocos), cortando primeiro o eixo mais comprido para as sobras ficarem inteiras.
	local order = { 1, 2, 3 }
	table.sort(order, function(a, b)
		return sizes[a] > sizes[b]
	end)
	local boxLo = { -halves[1], -halves[2], -halves[3] }
	local boxHi = { halves[1], halves[2], halves[3] }
	local remainders: { { cframe: CFrame, size: Vector3 } } = {}
	local function addRemainder(minV: { number }, maxV: { number })
		local sx, sy, sz = maxV[1] - minV[1], maxV[2] - minV[2], maxV[3] - minV[3]
		if sx > 0.05 and sy > 0.05 and sz > 0.05 then
			local center = Vector3.new((minV[1] + maxV[1]) / 2, (minV[2] + maxV[2]) / 2, (minV[3] + maxV[3]) / 2)
			table.insert(remainders, { cframe = cframe * CFrame.new(center), size = Vector3.new(sx, sy, sz) })
		end
	end
	for _, axis in order do
		local belowMax = table.clone(boxHi)
		belowMax[axis] = lo[axis]
		addRemainder(boxLo, belowMax)
		local aboveMin = table.clone(boxLo)
		aboveMin[axis] = hi[axis]
		addRemainder(aboveMin, boxHi)
		boxLo[axis] = lo[axis]
		boxHi[axis] = hi[axis]
	end

	-- 3. Grade do buraco: pedaços ≈ FRACTURE_CHUNK_SIZE, aumentando o tamanho até caber no limite.
	local holeSize = { hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3] }
	local maxChunks = math.max(math.floor(GameConfig.MAX_CHUNKS_PER_FRACTURE), 2)
	local budget = math.max(maxChunks - #remainders, 1)
	local chunk = math.max(GameConfig.FRACTURE_CHUNK_SIZE, 0.5)
	local counts = { 1, 1, 1 }
	for _ = 1, 60 do
		counts = { axisCount(holeSize[1], chunk), axisCount(holeSize[2], chunk), axisCount(holeSize[3], chunk) }
		if counts[1] * counts[2] * counts[3] <= budget then
			break
		end
		chunk *= 1.2
	end

	-- Bloco pequeno inteiro dentro do buraco: solta a própria part (sem criar cópias).
	if #remainders == 0 and counts[1] * counts[2] * counts[3] == 1 then
		return releaseWhole(part, origin, speed)
	end

	local sourceTags = CollectionService:GetTags(part)
	local attributes = part:GetAttributes()
	local parent = part.Parent
	local folder = ensureFolder()
	local pieces: { BasePart } = {}
	local loose: { BasePart } = {}

	for _, remainder in remainders do
		local piece = newPiece(part, remainder.cframe, remainder.size)
		setupAnchoredPiece(piece, part, sourceTags, attributes)
		piece.Parent = parent
		table.insert(pieces, piece)
	end

	local cell = Vector3.new(holeSize[1] / counts[1], holeSize[2] / counts[2], holeSize[3] / counts[3])
	local localHit = Vector3.new(
		math.clamp(centerOf[1], -halves[1], halves[1]),
		math.clamp(centerOf[2], -halves[2], halves[2]),
		math.clamp(centerOf[3], -halves[3], halves[3])
	)
	local keepDistance = holeRadius * 1.3
	local nearest, nearestDistance = nil, math.huge
	local holeCells = {}
	for ix = 1, counts[1] do
		for iy = 1, counts[2] do
			for iz = 1, counts[3] do
				local center =
					Vector3.new(lo[1] + (ix - 0.5) * cell.X, lo[2] + (iy - 0.5) * cell.Y, lo[3] + (iz - 0.5) * cell.Z)
				local distance = (center - localHit).Magnitude
				local entry = { center = center, distance = distance }
				table.insert(holeCells, entry)
				if distance < nearestDistance then
					nearest, nearestDistance = entry, distance
				end
			end
		end
	end
	-- Pedaços soltos ficam um tiquinho menores para não nascerem encostados (sem tremedeira).
	local looseSize =
		Vector3.new(math.max(cell.X - 0.04, 0.2), math.max(cell.Y - 0.04, 0.2), math.max(cell.Z - 0.04, 0.2))
	for _, entry in holeCells do
		local worldCFrame = cframe * CFrame.new(entry.center)
		if entry == nearest or entry.distance <= keepDistance then
			local piece = newPiece(part, worldCFrame, looseSize)
			piece.CanCollide = true
			piece.CanTouch = true
			piece.CanQuery = true
			piece.Parent = folder
			table.insert(pieces, piece)
			table.insert(loose, piece)
		else
			local piece = newPiece(part, worldCFrame, cell)
			setupAnchoredPiece(piece, part, sourceTags, attributes)
			piece.Parent = parent
			table.insert(pieces, piece)
		end
	end

	-- Partes soldadas na original (enfeites presos nela) caem junto como pedaços.
	local dependents: { BasePart } = {}
	local okJoints, connected = pcall(part.GetConnectedParts, part, false)
	if okJoints then
		for _, other in connected do
			if other ~= part and not other.Anchored and not DestructionService.IsProtected(other) then
				table.insert(dependents, other)
			end
		end
	end

	local impactWorld = cframe:PointToWorldSpace(localHit)
	part:Destroy()

	for _, piece in loose do
		launch(piece, origin, speed)
		DestructionService.RegisterDebris(piece)
	end
	for _, other in dependents do
		if other.Parent then
			launch(other, origin, speed * 0.5)
			DestructionService.RegisterDebris(other)
		end
	end
	playCrumble(impactWorld)
	return pieces
end

function DestructionService.Fracture(part: BasePart, impactPoint: Vector3, impulse: number?): { BasePart }
	if not DestructionService.IsDestructible(part) then
		return {}
	end
	local power = DEFAULT_IMPULSE
	if type(impulse) == "number" and impulse == impulse then
		power = math.clamp(impulse, 0, MAX_IMPULSE)
	end
	local impact = impactPoint
	if typeof(impact) ~= "Vector3" or impact ~= impact then
		impact = part.Position
	end
	-- Impacto longe demais da part (argumento estranho): usa o ponto da part mais próximo.
	impact = PhysUtil.ClosestPointOnPart(part, impact)
	local ok, result =
		pcall(fracture, part, impact, releaseRadiusFor(power), math.min(power * 0.5, MAX_PIECE_SPEED), impact)
	if not ok then
		warn("[DestructionService] Erro ao quebrar '" .. part:GetFullName() .. "': " .. tostring(result))
		return {}
	end
	return result
end

-- Explosão ----------------------------------------------------------------------------------

function DestructionService.Explode(
	position: Vector3,
	radius: number,
	force: number,
	opts: {
		damagePlayers: number?,
		damageEnemies: number?,
		attacker: Player?,
		source: string?,
		visual: boolean?,
	}?
)
	if typeof(position) ~= "Vector3" or position ~= position then
		return
	end
	local blastRadius = math.clamp(tonumber(radius) or 10, 1, EXPLODE_MAX_RADIUS)
	local power = math.clamp(tonumber(force) or 60, 0, MAX_IMPULSE)
	local options = type(opts) == "table" and opts or {}
	ensureSetup()

	local visual = options.visual ~= false
	if visual then
		local explosion = Instance.new("Explosion")
		explosion.BlastPressure = 0
		explosion.BlastRadius = blastRadius
		explosion.DestroyJointRadiusPercent = 0
		explosion.ExplosionType = Enum.ExplosionType.NoCraters
		explosion.Position = position
		explosion.Parent = workspace
		SoundUtil.Play("Explosion", { Position = position, RollOffMaxDistance = 350, Volume = 0.9 })
	end

	-- 1. Classifica o que está no raio (antes de quebrar, para não empurrar duas vezes os pedaços novos).
	local params = PhysUtil.OverlapParams(true, 400)
	local found = workspace:GetPartBoundsInRadius(position, blastRadius, params)
	local destructibles = {}
	local pushed: { [BasePart]: boolean } = {}
	local pushList: { BasePart } = {}
	for _, part in found do
		if DestructionService.IsDestructible(part) then
			local point = PhysUtil.ClosestPointOnPart(part, position)
			table.insert(destructibles, { part = part, point = point, distance = (point - position).Magnitude })
		else
			local root = DestructionService.GetLooseRoot(part)
			if not root and not part.Anchored and CollectionService:HasTag(part, Tags.Debris) then
				root = part.AssemblyRootPart or part
			end
			if root and not pushed[root] and #pushList < EXPLODE_MAX_PUSH then
				pushed[root] = true
				table.insert(pushList, root)
			end
		end
	end

	-- 2. Quebra as parts mais próximas.
	table.sort(destructibles, function(a, b)
		return a.distance < b.distance
	end)
	for index = 1, math.min(#destructibles, EXPLODE_MAX_FRACTURES) do
		local item = destructibles[index]
		if item.part.Parent then
			local falloff = math.clamp(1 - item.distance / blastRadius, 0.25, 1)
			local hole = math.clamp(blastRadius - item.distance, MIN_RELEASE_RADIUS, MAX_RELEASE_RADIUS * 1.5)
			local ok, err =
				pcall(fracture, item.part, item.point, hole, math.min(power * falloff, MAX_PIECE_SPEED), position)
			if not ok then
				warn("[DestructionService] Erro ao quebrar na explosão: " .. tostring(err))
			end
		end
	end

	-- 3. Solta e empurra objetos e pedaços.
	for _, root in pushList do
		if root.Parent then
			local offset = root.Position - position
			local distance = offset.Magnitude
			local falloff = math.clamp(1 - distance / blastRadius, 0.15, 1)
			local direction = distance > 0.05 and offset.Unit or Vector3.yAxis
			local velocity = direction * power * falloff + Vector3.new(0, power * 0.35 * falloff, 0)
			if CollectionService:HasTag(root, Tags.LooseProp) then
				DestructionService.ReleaseProp(root, velocity)
			else
				DestructionService.Push(root, velocity, randomSpin(power * 0.1))
			end
		end
	end

	-- 4. Dano e empurrão em jogadores (só quando a explosão fere jogadores: sem fogo amigo) e inimigos.
	local damagePlayers = tonumber(options.damagePlayers) or 0
	if damagePlayers > 0 then
		local source = type(options.source) == "string" and options.source or "Explosão"
		local hits = CombatUtil.DamagePlayersInRadius(position, blastRadius, damagePlayers, source)
		for _, player in hits do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local away = PhysUtil.FlatUnit(root.Position - position, Vector3.xAxis)
				CombatUtil.Knockback(player, away, math.clamp(power * 0.6, 20, 110))
			end
		end
	end
	local damageEnemies = tonumber(options.damageEnemies) or 0
	if damageEnemies > 0 then
		local attacker = options.attacker
		if typeof(attacker) ~= "Instance" or not attacker:IsA("Player") then
			attacker = nil
		end
		CombatUtil.DamageEnemiesInRadius(position, blastRadius, damageEnemies, attacker)
	end

	-- 5. Tremor para quem está perto e clarão para quem está quase dentro.
	PhysUtil.Shake(position, blastRadius * 4, math.clamp(power / 100, 0.3, 1.6), 0.6)
	if visual then
		for _, hit in PhysUtil.PlayersInRadius(position, blastRadius * 1.5) do
			PhysUtil.Flash(hit.player, EXPLOSION_FLASH, 0.3)
		end
	end
end

-- Inicialização -------------------------------------------------------------------------------

function DestructionService.Init()
	if initialized then
		return
	end
	initialized = true
	-- Remotes usados por este serviço (existem antes de qualquer cliente pedir).
	Net.event(Net.Names.Fx_Play)
	Net.event(Net.Names.Notify)
	ensureSetup()
end

return DestructionService
