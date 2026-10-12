--!nonstrict
-- Utilitários dos NPCs (servidor):
--   * parâmetros de raycast/overlap compartilhados (só o cenário sólido; reconstruídos 1x por segundo);
--   * tiro em linha que para no cenário e acerta o primeiro jogador no caminho;
--   * sons com limite de repetição, avisos com cooldown, tremor de câmera e traço de tiro (Fx_Play);
--   * lentidão de jogadores (usa os modificadores empilháveis do PhysUtil quando existe, para não brigar
--     com os eventos físicos; senão, uma pilha própria com a mesma regra) e destaque visual (Highlight);
--   * objetos soltos (LooseProp): procurar, reservar, soltar e lançar (usa o DestructionService se houver).

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local Tags = require(ReplicatedStorage.Shared.Tags)

local CombatUtil = require(script.Parent.Parent.CombatUtil)
local GroundUtil = require(script.Parent.Parent.EventHelpers.GroundUtil)

local Effects = {}

local PARAMS_REFRESH = 1 -- segundos entre reconstruções da lista de exclusão
local SOUND_MIN_GAP = 0.25 -- o mesmo som não toca mais de uma vez nesse intervalo (muitos NPCs juntos)
local BODY_SAMPLES = { Vector3.new(0, -1.6, 0), Vector3.zero, Vector3.new(0, 1.5, 0) }
local BODY_RADIUS = 1.6 -- "espessura" do personagem para o tiro
local PROP_MAX_PARTS = 8 -- objeto soldado com mais partes que isto não é arremessável
local LEAF_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

-- Parâmetros de consulta -----------------------------------------------------------------------

local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Exclude
worldParams.IgnoreWater = true
worldParams.RespectCanCollide = true

local propParams = OverlapParams.new()
propParams.FilterType = Enum.RaycastFilterType.Exclude
propParams.MaxParts = 80

local lastRefresh = -math.huge

local function addFolder(list: { Instance }, parent: Instance?, name: string)
	local folder = parent and parent:FindFirstChild(name)
	if folder then
		table.insert(list, folder)
	end
end

local function refreshParams()
	local now = os.clock()
	if now - lastRefresh < PARAMS_REFRESH then
		return
	end
	lastRefresh = now
	local list: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	for _, name in { "NPCs", "Debris", "ActiveEvents", "Board" } do
		addFolder(list, workspace, name)
	end
	addFolder(list, workspace:FindFirstChild("Map"), "Regions")
	worldParams.FilterDescendantsInstances = list
	propParams.FilterDescendantsInstances = list
end

-- Raycast que só enxerga o cenário sólido: ignora personagens, NPCs, pedaços, eventos e o tabuleiro.
function Effects.WorldParams(): RaycastParams
	refreshParams()
	return worldParams
end

-- Força a reconstrução na próxima consulta (ex.: personagem novo).
function Effects.InvalidateParams()
	lastRefresh = -math.huge
end

-- Tiro em linha reta: para no cenário sólido e acerta o primeiro jogador vivo no caminho.
-- Retorna (jogador atingido?, ponto final do traço, resultado do cenário se parou numa parede).
function Effects.CastShot(origin: Vector3, direction: Vector3, range: number): (Player?, Vector3, RaycastResult?)
	local unit = if direction.Magnitude > 1e-3 then direction.Unit else Vector3.new(0, 0, -1)
	local world = workspace:Raycast(origin, unit * range, Effects.WorldParams())
	local length = if world then (world.Position - origin).Magnitude else range
	local bestPlayer, bestAlong = nil, math.huge
	for _, player in CombatUtil.GetAlivePlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			for _, offset in BODY_SAMPLES do
				local point = root.Position + offset
				local along = (point - origin):Dot(unit)
				if along > 0 and along <= length + BODY_RADIUS and along < bestAlong then
					if (point - (origin + unit * along)).Magnitude <= BODY_RADIUS then
						bestPlayer, bestAlong = player, along
					end
				end
			end
		end
	end
	if bestPlayer then
		return bestPlayer, origin + unit * bestAlong, nil
	end
	return nil, origin + unit * length, world
end

-- Chão sob `position` (ignora personagens, NPCs, pedaços e eventos).
function Effects.Ground(position: Vector3, maxDrop: number?, startAbove: number?): Vector3?
	local ground = GroundUtil.FindGround(position, maxDrop or 30, startAbove or 4)
	return ground
end

-- Módulos de outros donos (require seguro, uma vez) ----------------------------------------------

local cachedModules: { [string]: any } = {}

local function safeRequire(...: string): any
	local key = table.concat({ ... }, ".")
	local cached = cachedModules[key]
	if cached ~= nil then
		return cached or nil
	end
	local current: Instance? = script.Parent.Parent
	for _, name in { ... } do
		current = current and current:FindFirstChild(name)
	end
	local module = nil
	if current and current:IsA("ModuleScript") then
		local ok, result = pcall(require, current)
		if ok and type(result) == "table" then
			module = result
		else
			warn(("[NPC] Não foi possível carregar '%s': %s"):format(key, tostring(result)))
		end
	end
	cachedModules[key] = module or false
	return module
end

function Effects.GetDestruction(): any
	return safeRequire("DestructionService")
end

local function getPhysUtil(): any
	local module = safeRequire("EventHelpers", "PhysUtil")
	if module and type(module.SetTimedModifier) == "function" then
		return module
	end
	return nil
end

-- Pasta de efeitos dos NPCs (workspace.NPCs.Efeitos), definida pelo NPCService.
local effectsFolder: Instance? = nil

function Effects.SetFolder(folder: Instance)
	effectsFolder = folder
end

function Effects.Folder(): Instance
	if effectsFolder and effectsFolder.Parent then
		return effectsFolder
	end
	return workspace
end

-- Sons, avisos, tremor e traço --------------------------------------------------------------------

local lastSound: { [string]: number } = {}

-- Toca um som de Config/Sounds numa posição (ids vazios não fazem nada). Limita repetições seguidas.
function Effects.Sound(name: string, position: Vector3?, options: { [string]: any }?): Sound?
	local now = os.clock()
	local last = lastSound[name]
	if last and now - last < SOUND_MIN_GAP then
		return nil
	end
	lastSound[name] = now
	local opts = table.clone(options or {})
	if position and not opts.Parent then
		opts.Position = position
	end
	return SoundUtil.Play(name, opts)
end

local notifyRemote: RemoteEvent? = nil
local fxRemote: RemoteEvent? = nil
local notifyTimes: { [Player]: { [string]: number } } = setmetatable({}, { __mode = "k" }) :: any

local function getNotify(): RemoteEvent
	if not notifyRemote then
		notifyRemote = Net.event(Net.Names.Notify)
	end
	return notifyRemote :: RemoteEvent
end

local function getFx(): RemoteEvent
	if not fxRemote then
		fxRemote = Net.event(Net.Names.Fx_Play)
	end
	return fxRemote :: RemoteEvent
end

-- Aviso para um jogador; com `cooldownKey`, no máximo um aviso desse tipo a cada `cooldown` segundos.
function Effects.Notify(player: Player, text: string, kind: string?, cooldownKey: string?, cooldown: number?)
	if not player.Parent then
		return
	end
	if cooldownKey then
		local times = notifyTimes[player]
		if not times then
			times = {}
			notifyTimes[player] = times
		end
		local now = os.clock()
		local last = times[cooldownKey]
		if last and now - last < (cooldown or 6) then
			return
		end
		times[cooldownKey] = now
	end
	getNotify():FireClient(player, text, kind or "info")
end

function Effects.NotifyAll(text: string, kind: string?)
	getNotify():FireAllClients(text, kind or "info")
end

-- Treme a câmera de quem está vivo até `reach` studs da origem (o cliente enfraquece com a distância).
function Effects.Shake(origin: Vector3, reach: number, intensity: number, duration: number)
	local params = {
		intensity = math.clamp(intensity, 0.2, 2),
		duration = math.max(duration, 0.1),
		origin = origin,
		radius = reach,
	}
	for _, player in CombatUtil.GetAlivePlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - origin).Magnitude <= reach then
			getFx():FireClient(player, "shake", params)
		end
	end
end

-- Traço de tiro para todos os clientes.
function Effects.Tracer(from: Vector3, to: Vector3, color: Color3?, width: number?)
	getFx():FireAllClients("tracer", { from = from, to = to, color = color, width = width })
end

-- Nuvem de folhas/poeira rápida (nascimento de NPC). Uma partícula curta, sem loop.
function Effects.Burst(position: Vector3, color: Color3)
	local attachment = Instance.new("Attachment")
	attachment.Name = "NpcBurst"
	attachment.Parent = workspace.Terrain
	attachment.WorldPosition = position
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = LEAF_TEXTURE
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 2.6) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(4, 9)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 45
	emitter.LightInfluence = 0.6
	emitter.Parent = attachment
	task.delay(0.25, function()
		if emitter.Parent then
			emitter.Enabled = false
		end
	end)
	Debris:AddItem(attachment, 2)
end

-- Lentidão / prisão de jogadores ----------------------------------------------------------------
-- Pilha própria (só usada se o PhysUtil não existir): o menor teto de velocidade vence e os valores
-- originais voltam quando o último efeito acaba.

local localStacks: { [Humanoid]: any } = {}

local function applyStack(humanoid: Humanoid, entry)
	local speed = entry.baseSpeed
	local jump = 1
	for _, modifier in entry.modifiers do
		speed = math.min(speed, modifier.walkSpeed)
		jump = math.min(jump, modifier.jump)
	end
	humanoid.WalkSpeed = speed
	humanoid.JumpPower = entry.baseJumpPower * jump
	humanoid.JumpHeight = entry.baseJumpHeight * jump
end

local function releaseStack(humanoid: Humanoid, entry, restore: boolean)
	if localStacks[humanoid] ~= entry then
		return
	end
	localStacks[humanoid] = nil
	if entry.diedConnection then
		entry.diedConnection:Disconnect()
	end
	if restore and humanoid.Parent and humanoid.Health > 0 then
		humanoid.WalkSpeed = entry.baseSpeed
		humanoid.JumpPower = entry.baseJumpPower
		humanoid.JumpHeight = entry.baseJumpHeight
	end
end

local function setLocalModifier(humanoid: Humanoid, key: string, walkSpeed: number, jump: number, seconds: number)
	local entry = localStacks[humanoid]
	if not entry then
		entry = {
			baseSpeed = humanoid.WalkSpeed,
			baseJumpPower = humanoid.JumpPower,
			baseJumpHeight = humanoid.JumpHeight,
			modifiers = {},
			tokens = {},
			diedConnection = nil,
		}
		localStacks[humanoid] = entry
		entry.diedConnection = humanoid.Died:Connect(function()
			releaseStack(humanoid, entry, false)
		end)
	end
	local token = {}
	entry.modifiers[key] = { walkSpeed = walkSpeed, jump = jump }
	entry.tokens[key] = token
	applyStack(humanoid, entry)
	task.delay(seconds, function()
		if localStacks[humanoid] ~= entry or entry.tokens[key] ~= token then
			return
		end
		entry.modifiers[key] = nil
		entry.tokens[key] = nil
		if next(entry.modifiers) == nil then
			releaseStack(humanoid, entry, true)
		elseif humanoid.Parent and humanoid.Health > 0 then
			applyStack(humanoid, entry)
		end
	end)
end

-- Deixa o jogador lento por `seconds` (chamar de novo com a mesma chave renova o tempo, sem empilhar).
function Effects.Slow(player: Player, key: string, walkSpeed: number, seconds: number, jumpMultiplier: number?)
	local humanoid = CombatUtil.GetHumanoid(player.Character)
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local physUtil = getPhysUtil()
	if physUtil then
		local ok, err = pcall(
			physUtil.SetTimedModifier,
			humanoid,
			key,
			{ walkSpeed = walkSpeed, jumpMultiplier = jumpMultiplier },
			seconds
		)
		if ok then
			return
		end
		warn("[NPC] Erro ao aplicar lentidão pelo PhysUtil: " .. tostring(err))
	end
	setLocalModifier(humanoid, key, walkSpeed, math.clamp(jumpMultiplier or 1, 0, 1), seconds)
end

-- Destaque (Highlight) no personagem por alguns segundos; a mesma chave reaproveita o destaque.
local marks: { [Player]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any

function Effects.Mark(player: Player, key: string, color: Color3, seconds: number)
	local character = player.Character
	if not character then
		return
	end
	local byKey = marks[player]
	if not byKey then
		byKey = {}
		marks[player] = byKey
	end
	local entry = byKey[key]
	local highlight: Highlight? = entry and entry.highlight
	if not highlight or highlight.Parent ~= character then
		if highlight then
			highlight:Destroy()
		end
		local created = Instance.new("Highlight")
		created.Name = "NpcMarca_" .. key
		created.DepthMode = Enum.HighlightDepthMode.Occluded
		created.Adornee = character
		created.Parent = character
		highlight = created
	end
	local active = highlight :: Highlight
	active.FillColor = color
	active.FillTransparency = 0.6
	active.OutlineColor = color
	active.OutlineTransparency = 0.15
	local token = {}
	byKey[key] = { highlight = active, token = token }
	task.delay(seconds, function()
		local current = marks[player] and marks[player][key]
		if current and current.token == token then
			marks[player][key] = nil
			if active.Parent then
				active:Destroy()
			end
		end
	end)
end

-- Objetos soltos (LooseProp) ---------------------------------------------------------------------

local claims: { [BasePart]: any } = setmetatable({}, { __mode = "k" }) :: any

-- Reserva um objeto para um NPC (dois macacos não pegam o mesmo vaso). Retorna false se já reservado.
function Effects.ClaimProp(part: BasePart, owner: any): boolean
	local current = claims[part]
	if current ~= nil and current ~= owner then
		return false
	end
	claims[part] = owner
	return true
end

function Effects.ReleaseClaim(part: BasePart)
	claims[part] = nil
end

function Effects.ClearClaims()
	table.clear(claims)
end

local function countConnected(part: BasePart): number
	local ok, connected = pcall(part.GetConnectedParts, part, true)
	if ok and type(connected) == "table" then
		return #connected
	end
	return 1
end

-- O objeto ainda é um LooseProp pegável (no mundo, não reservado por outro, não protegido)?
function Effects.IsPropAvailable(part: BasePart, owner: any): boolean
	if not part.Parent or not part:IsDescendantOf(workspace) then
		return false
	end
	local current = claims[part]
	if current ~= nil and current ~= owner then
		return false
	end
	return CollectionService:HasTag(part, Tags.LooseProp)
		and not CollectionService:HasTag(part, Tags.Indestructible)
		and not CollectionService:HasTag(part, Tags.Debris)
end

-- Procura o LooseProp pequeno mais próximo (raiz do objeto) dentro do raio. Ignora os reservados.
function Effects.FindLooseProp(position: Vector3, radius: number, maxSize: number, owner: any): BasePart?
	refreshParams()
	local parts = workspace:GetPartBoundsInRadius(position, radius, propParams)
	local best, bestDistance = nil, math.huge
	for _, part in parts do
		if Effects.IsPropAvailable(part, owner) then
			local offset = part.Position - position
			local distance = offset.Magnitude
			if
				distance < bestDistance
				and math.abs(offset.Y) < 6
				and part.Size.Magnitude <= maxSize
				and countConnected(part) <= PROP_MAX_PARTS
			then
				best, bestDistance = part, distance
			end
		end
	end
	return best
end

-- Solta o objeto (desancora, física no servidor) e aplica velocidade; ele vira pedaço e some depois.
-- Retorna a part raiz lançada (ou nil).
function Effects.LaunchProp(part: BasePart, velocity: Vector3): BasePart?
	if not part.Parent then
		return nil
	end
	claims[part] = nil
	local destruction = Effects.GetDestruction()
	local root: BasePart? = nil
	if destruction and type(destruction.ReleaseProp) == "function" then
		local ok, released = pcall(destruction.ReleaseProp, part, velocity)
		if ok and typeof(released) == "Instance" and released:IsA("BasePart") then
			root = released :: BasePart
		end
	end
	if not root then
		part.Anchored = false
		pcall(part.SetNetworkOwner, part, nil)
		part.AssemblyLinearVelocity = velocity
		part.AssemblyAngularVelocity = Vector3.new(math.random() * 6 - 3, math.random() * 6 - 3, math.random() * 6 - 3)
		root = part
	end
	if destruction and type(destruction.RegisterDebris) == "function" then
		local ok, err = pcall(destruction.RegisterDebris, root)
		if not ok then
			warn("[NPC] Erro ao registrar objeto arremessado: " .. tostring(err))
		end
	end
	return root
end

return Effects
