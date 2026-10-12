--!nonstrict
-- Utilitários compartilhados pelos eventos físicos (Debandada, Monção, Terremoto, Cipós, Areia Movediça,
-- Tornado, Pelicano):
--   * Trove: guarda conexões, instâncias, threads e funções para uma limpeza idempotente;
--   * consultas espaciais que ignoram personagens, NPCs, o tabuleiro e as pastas de eventos;
--   * tremor de câmera / avisos para os jogadores;
--   * modificadores de movimento empilháveis (vários eventos podem deixar o mesmo jogador lento ao
--     mesmo tempo sem que um "restaure" o valor errado do outro);
--   * pilha de iluminação com contagem de referência (eventos simultâneos escurecem/restauram certo).

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Tags = require(ReplicatedStorage.Shared.Tags)

local CombatUtil = require(script.Parent.Parent.CombatUtil)
local GroundUtil = require(script.Parent.GroundUtil)

local PhysUtil = {}

-- Texturas que já vêm com o cliente do Roblox (não precisam de upload).
PhysUtil.Textures = {
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
}

-- Trove (limpeza) ----------------------------------------------------------------------------

local Trove = {}
Trove.__index = Trove

export type Trove = {
	Add: (self: any, item: any) -> any,
	Connect: (self: any, signal: RBXScriptSignal, handler: (...any) -> ()) -> RBXScriptConnection,
	Spawn: (self: any, fn: (...any) -> (), ...any) -> thread,
	Clean: (self: any) -> (),
	IsCleaned: (self: any) -> boolean,
}

local function cleanItem(item: any)
	local kind = typeof(item)
	if kind == "Instance" then
		item:Destroy()
	elseif kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "thread" then
		-- Nunca cancela a própria thread que está limpando.
		if item ~= coroutine.running() and coroutine.status(item) ~= "dead" then
			task.cancel(item)
		end
	elseif kind == "function" then
		item()
	elseif kind == "table" then
		if type(item.Disconnect) == "function" then
			item:Disconnect()
		elseif type(item.Destroy) == "function" then
			item:Destroy()
		end
	end
end

function PhysUtil.newTrove(): Trove
	return setmetatable({ _items = {}, _cleaned = false }, Trove) :: any
end

-- Guarda um item para a limpeza. Depois da limpeza, o item é limpo na hora (threads atrasadas).
function Trove:Add(item: any): any
	if self._cleaned then
		local ok, err = pcall(cleanItem, item)
		if not ok then
			warn("[PhysUtil] Erro ao limpar item atrasado: " .. tostring(err))
		end
		return item
	end
	table.insert(self._items, item)
	return item
end

function Trove:Connect(signal: RBXScriptSignal, handler: (...any) -> ()): RBXScriptConnection
	return self:Add(signal:Connect(handler))
end

-- task.spawn rastreado (cancelado na limpeza).
function Trove:Spawn(fn: (...any) -> (), ...: any): thread
	return self:Add(task.spawn(fn, ...))
end

function Trove:Clean()
	if self._cleaned then
		return
	end
	self._cleaned = true
	local items = self._items
	self._items = {}
	for index = #items, 1, -1 do
		local ok, err = pcall(cleanItem, items[index])
		if not ok then
			warn("[PhysUtil] Erro na limpeza: " .. tostring(err))
		end
	end
end

function Trove:IsCleaned(): boolean
	return self._cleaned
end

-- Números e geometria -----------------------------------------------------------------------

function PhysUtil.Flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

function PhysUtil.FlatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Unitário horizontal (ou `fallback` se o vetor for quase vertical/nulo).
function PhysUtil.FlatUnit(vector: Vector3, fallback: Vector3?): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 1e-3 then
		return fallback or Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

function PhysUtil.RandomFlatUnit(rng: Random): Vector3
	local angle = rng:NextNumber(0, math.pi * 2)
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

-- Ponto da part (bloco) mais próximo de `point`.
function PhysUtil.ClosestPointOnPart(part: BasePart, point: Vector3): Vector3
	local half = part.Size / 2
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local clamped = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)
	return part.CFrame:PointToWorldSpace(clamped)
end

-- Distância de um ponto a um segmento AB.
function PhysUtil.DistanceToSegment(point: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	if lengthSq < 1e-6 then
		return (point - a).Magnitude
	end
	local t = math.clamp((point - a):Dot(ab) / lengthSq, 0, 1)
	return (point - (a + ab * t)).Magnitude
end

-- Distância (no plano XZ) de `position` até a borda da ilha andando na direção `direction`.
function PhysUtil.DistanceToIslandEdge(mapInfo: any, position: Vector3, direction: Vector3): number
	local center = mapInfo and mapInfo.islandCenter or Vector3.zero
	local radius = mapInfo and mapInfo.islandRadius or 600
	local p = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
	local d = PhysUtil.FlatUnit(direction)
	local b = p:Dot(d)
	local c = p:Dot(p) - radius * radius
	local discriminant = b * b - c
	if discriminant < 0 then
		return 0
	end
	return math.max(-b + math.sqrt(discriminant), 0)
end

-- Está dentro da ilha (com margem da borda)?
function PhysUtil.IsInsideIsland(mapInfo: any, position: Vector3, margin: number?): boolean
	local center = mapInfo and mapInfo.islandCenter or Vector3.zero
	local radius = mapInfo and mapInfo.islandRadius or 600
	return PhysUtil.FlatDistance(position, center) <= radius - (margin or 0)
end

-- Consultas espaciais -------------------------------------------------------------------------

local function addFolder(list: { Instance }, name: string)
	local folder = workspace:FindFirstChild(name)
	if folder then
		table.insert(list, folder)
	end
end

-- Lista de exclusão padrão: personagens, inimigos, tabuleiro, NPCs, eventos ativos e regiões.
function PhysUtil.ExcludeList(includeDebris: boolean?, extra: { Instance }?): { Instance }
	local list: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	for _, enemy in CollectionService:GetTagged(Tags.Enemy) do
		table.insert(list, enemy)
	end
	addFolder(list, "Board")
	addFolder(list, "NPCs")
	addFolder(list, "ActiveEvents")
	if not includeDebris then
		addFolder(list, "Debris")
	end
	local map = workspace:FindFirstChild("Map")
	local regions = map and map:FindFirstChild("Regions")
	if regions then
		table.insert(list, regions)
	end
	if extra then
		for _, instance in extra do
			table.insert(list, instance)
		end
	end
	return list
end

function PhysUtil.OverlapParams(includeDebris: boolean?, maxParts: number?, extra: { Instance }?): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = PhysUtil.ExcludeList(includeDebris, extra)
	params.MaxParts = maxParts or 200
	return params
end

-- Raycast que só enxerga o cenário sólido (sem pedaços, personagens, eventos nem tabuleiro).
function PhysUtil.RaycastParams(extra: { Instance }?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = PhysUtil.ExcludeList(false, extra)
	params.IgnoreWater = true
	params.RespectCanCollide = true
	return params
end

-- Chão sob `position` ignorando também o tabuleiro (GroundUtil já ignora personagens, NPCs e pedaços).
function PhysUtil.GroundAt(position: Vector3, maxDrop: number?, startAbove: number?): (Vector3?, BasePart?)
	local exclude = {}
	addFolder(exclude, "Board")
	return GroundUtil.FindGround(position, maxDrop or 40, startAbove or 3, exclude)
end

-- Altura do chão no ponto do evento (o tabuleiro fica no chão; se estiver nas costas de alguém,
-- procura o chão logo abaixo).
function PhysUtil.EventGroundY(position: Vector3): number
	local ground = PhysUtil.GroundAt(position, 30, 1)
	if ground then
		return ground.Y
	end
	return position.Y
end

-- Primeiro obstáculo sólido acima de `position` (teto), até `maxHeight` studs.
function PhysUtil.CeilingAbove(position: Vector3, maxHeight: number): (Vector3?, BasePart?)
	local result = workspace:Raycast(position, Vector3.new(0, maxHeight, 0), PhysUtil.RaycastParams())
	if result then
		return result.Position, result.Instance :: BasePart
	end
	return nil, nil
end

-- Ponto aleatório dentro do volume de uma part (bloco).
function PhysUtil.RandomPointInPart(part: BasePart, rng: Random): Vector3
	local half = part.Size / 2
	return part.CFrame:PointToWorldSpace(
		Vector3.new(rng:NextNumber(-half.X, half.X), rng:NextNumber(-half.Y, half.Y), rng:NextNumber(-half.Z, half.Z))
	)
end

-- Serviços ----------------------------------------------------------------------------------

local fallbackModules: { [string]: any } = {}

-- require seguro de um módulo do servidor do jogo (caminho relativo a ServerScriptService.Game).
local function loadFallback(...: string): any
	local key = table.concat({ ... }, ".")
	if fallbackModules[key] ~= nil then
		return fallbackModules[key] or nil
	end
	local current: Instance? = script.Parent.Parent
	for _, name in { ... } do
		current = current and current:FindFirstChild(name)
	end
	local module = nil
	if current and current:IsA("ModuleScript") then
		local ok, result = pcall(require, current)
		if ok then
			module = result
		end
	end
	fallbackModules[key] = module or false
	return module
end

-- Serviços do EventContext com reserva: se o EventService não entregou algum, tenta carregar aqui.
-- Módulos de outros donos podem continuar nil (NPC, Map); quem usa precisa conferir.
function PhysUtil.Services(ctx: any): { [string]: any }
	local given = (type(ctx) == "table" and type(ctx.services) == "table") and ctx.services or {}
	return {
		Destruction = given.Destruction or loadFallback("DestructionService"),
		NPC = given.NPC or loadFallback("NPC", "NPCService"),
		Board = given.Board or loadFallback("BoardService"),
		Combat = given.Combat or CombatUtil,
		Map = given.Map or loadFallback("Map", "MapBuilder"),
		Ground = given.Ground or GroundUtil,
	}
end

-- Jogadores ---------------------------------------------------------------------------------

export type PlayerHit = { player: Player, root: BasePart, humanoid: Humanoid, distance: number }

-- Jogadores vivos com HumanoidRootPart dentro do raio (3D, ou só no plano XZ se `flat`).
function PhysUtil.PlayersInRadius(position: Vector3, radius: number, flat: boolean?): { PlayerHit }
	local result = {}
	for _, player in CombatUtil.GetAlivePlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and root:IsA("BasePart") then
			local distance = if flat
				then PhysUtil.FlatDistance(root.Position, position)
				else (root.Position - position).Magnitude
			if distance <= radius then
				table.insert(result, { player = player, root = root, humanoid = humanoid, distance = distance })
			end
		end
	end
	return result
end

local fxRemote: RemoteEvent? = nil
local notifyRemote: RemoteEvent? = nil

local function getFx(): RemoteEvent
	if not fxRemote then
		fxRemote = Net.event(Net.Names.Fx_Play)
	end
	return fxRemote :: RemoteEvent
end

local function getNotify(): RemoteEvent
	if not notifyRemote then
		notifyRemote = Net.event(Net.Names.Notify)
	end
	return notifyRemote :: RemoteEvent
end

-- Treme a câmera de quem estiver até `reach` studs da origem (o cliente enfraquece com a distância).
function PhysUtil.Shake(origin: Vector3, reach: number, intensity: number, duration: number)
	local fx = getFx()
	local params = {
		intensity = math.clamp(intensity, 0.2, 2),
		duration = math.max(duration, 0.1),
		origin = origin,
		radius = reach,
	}
	for _, hit in PhysUtil.PlayersInRadius(origin, reach) do
		fx:FireClient(hit.player, "shake", params)
	end
end

function PhysUtil.Flash(player: Player, color: Color3?, duration: number?)
	getFx():FireClient(player, "flash", { color = color, duration = duration })
end

function PhysUtil.NotifyAll(text: string, kind: string?)
	getNotify():FireAllClients(text, kind or "info")
end

function PhysUtil.Notify(player: Player, text: string, kind: string?)
	getNotify():FireClient(player, text, kind or "info")
end

-- Cooldown simples por chave (jogador, part...). Retorna true se pode agir agora e marca o tempo.
function PhysUtil.newCooldown(seconds: number)
	local last: { [any]: number } = {}
	return function(key: any): boolean
		local now = os.clock()
		local previous = last[key]
		if previous and now - previous < seconds then
			return false
		end
		last[key] = now
		return true
	end
end

-- Modificadores de movimento ------------------------------------------------------------------
-- Cada efeito registra um modificador com uma chave própria; o valor aplicado é a combinação de todos
-- (menor velocidade, menor pulo, maior afundamento). Quando o último sai, os valores originais voltam.

export type Modifier = {
	walkSpeed: number?, -- teto de WalkSpeed
	jumpMultiplier: number?, -- multiplica JumpPower/JumpHeight (0..1)
	hipHeightOffset: number?, -- quanto o HipHeight desce (só R15; mínimo 0)
}

local modifierEntries: { [Humanoid]: any } = {}

local function releaseEntry(humanoid: Humanoid)
	local entry = modifierEntries[humanoid]
	if not entry then
		return
	end
	modifierEntries[humanoid] = nil
	for _, connection in entry.connections do
		connection:Disconnect()
	end
end

local function applyEntry(humanoid: Humanoid, entry)
	local base = entry.base
	local walkSpeed = base.walkSpeed
	local jumpMultiplier = 1
	local hipOffset = 0
	for _, modifier in entry.modifiers do
		if type(modifier.walkSpeed) == "number" then
			walkSpeed = math.min(walkSpeed, modifier.walkSpeed)
		end
		if type(modifier.jumpMultiplier) == "number" then
			jumpMultiplier = math.min(jumpMultiplier, math.clamp(modifier.jumpMultiplier, 0, 1))
		end
		if type(modifier.hipHeightOffset) == "number" then
			hipOffset = math.max(hipOffset, modifier.hipHeightOffset)
		end
	end
	humanoid.WalkSpeed = walkSpeed
	humanoid.JumpPower = base.jumpPower * jumpMultiplier
	humanoid.JumpHeight = base.jumpHeight * jumpMultiplier
	if base.isR15 then
		humanoid.HipHeight = math.max(base.hipHeight - hipOffset, 0)
	end
end

local function restoreEntry(humanoid: Humanoid, entry)
	local base = entry.base
	if humanoid.Parent and humanoid.Health > 0 then
		humanoid.WalkSpeed = base.walkSpeed
		humanoid.JumpPower = base.jumpPower
		humanoid.JumpHeight = base.jumpHeight
		if base.isR15 then
			humanoid.HipHeight = base.hipHeight
		end
	end
end

function PhysUtil.SetModifier(humanoid: Humanoid, key: string, modifier: Modifier)
	if typeof(humanoid) ~= "Instance" or not humanoid:IsA("Humanoid") or humanoid.Health <= 0 then
		return
	end
	local entry = modifierEntries[humanoid]
	if not entry then
		entry = {
			base = {
				walkSpeed = humanoid.WalkSpeed,
				jumpPower = humanoid.JumpPower,
				jumpHeight = humanoid.JumpHeight,
				hipHeight = humanoid.HipHeight,
				isR15 = humanoid.RigType == Enum.HumanoidRigType.R15,
			},
			modifiers = {},
			tokens = {},
			connections = {},
		}
		modifierEntries[humanoid] = entry
		-- Morreu ou saiu do jogo: não há o que restaurar.
		table.insert(
			entry.connections,
			humanoid.Died:Connect(function()
				releaseEntry(humanoid)
			end)
		)
		table.insert(
			entry.connections,
			humanoid.AncestryChanged:Connect(function()
				if not humanoid:IsDescendantOf(game) then
					releaseEntry(humanoid)
				end
			end)
		)
	end
	entry.modifiers[key] = modifier
	applyEntry(humanoid, entry)
end

function PhysUtil.ClearModifier(humanoid: Humanoid, key: string)
	local entry = modifierEntries[humanoid]
	if not entry or entry.modifiers[key] == nil then
		return
	end
	entry.modifiers[key] = nil
	entry.tokens[key] = nil
	if next(entry.modifiers) == nil then
		restoreEntry(humanoid, entry)
		releaseEntry(humanoid)
	else
		applyEntry(humanoid, entry)
	end
end

-- Modificador que sai sozinho depois de `seconds` (chamar de novo renova o tempo).
function PhysUtil.SetTimedModifier(humanoid: Humanoid, key: string, modifier: Modifier, seconds: number)
	PhysUtil.SetModifier(humanoid, key, modifier)
	local entry = modifierEntries[humanoid]
	if not entry then
		return
	end
	local token = {}
	entry.tokens[key] = token
	task.delay(seconds, function()
		local current = modifierEntries[humanoid]
		if current == entry and entry.tokens[key] == token then
			PhysUtil.ClearModifier(humanoid, key)
		end
	end)
end

-- Remove a chave de todos os humanoides (limpeza de um evento).
function PhysUtil.ClearModifiersWithKey(key: string)
	local humanoids = {}
	for humanoid, entry in modifierEntries do
		if entry.modifiers[key] ~= nil then
			table.insert(humanoids, humanoid)
		end
	end
	for _, humanoid in humanoids do
		PhysUtil.ClearModifier(humanoid, key)
	end
end

-- Iluminação com contagem de referência ---------------------------------------------------------
-- O primeiro evento que escurece guarda os valores originais; cada evento novo aplica o seu alvo;
-- ao sair, volta para o alvo do evento anterior que ainda está ativo ou para os valores originais.

export type LightingTarget = {
	Brightness: number?,
	ClockTime: number?,
	FogStart: number?,
	FogEnd: number?,
	AtmosphereDensity: number?,
}

local lightingStack: { { key: string, target: LightingTarget } } = {}
local lightingBase: LightingTarget? = nil

local function captureLighting(): LightingTarget
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	return {
		Brightness = Lighting.Brightness,
		ClockTime = Lighting.ClockTime,
		FogStart = Lighting.FogStart,
		FogEnd = Lighting.FogEnd,
		AtmosphereDensity = atmosphere and atmosphere.Density or nil,
	}
end

local function tweenLighting(target: LightingTarget, seconds: number)
	local info = TweenInfo.new(math.max(seconds, 0.05), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local props = {}
	for _, name in { "Brightness", "ClockTime", "FogStart", "FogEnd" } do
		if type(target[name]) == "number" then
			props[name] = target[name]
		end
	end
	if next(props) then
		TweenService:Create(Lighting, info, props):Play()
	end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere and type(target.AtmosphereDensity) == "number" then
		TweenService:Create(atmosphere, info, { Density = math.clamp(target.AtmosphereDensity, 0, 1) }):Play()
	end
end

-- `makeTarget(base)` recebe os valores originais e devolve o alvo deste evento.
function PhysUtil.PushLighting(key: string, makeTarget: (LightingTarget) -> LightingTarget, seconds: number?)
	if not lightingBase then
		lightingBase = captureLighting()
	end
	for index = #lightingStack, 1, -1 do
		if lightingStack[index].key == key then
			table.remove(lightingStack, index)
		end
	end
	local ok, target = pcall(makeTarget, table.clone(lightingBase :: LightingTarget))
	if not ok or type(target) ~= "table" then
		target = {}
	end
	table.insert(lightingStack, { key = key, target = target })
	local merged = table.clone(lightingBase :: LightingTarget)
	for name, value in target do
		merged[name] = value
	end
	tweenLighting(merged, seconds or 3)
end

function PhysUtil.PopLighting(key: string, seconds: number?)
	local removed = false
	for index = #lightingStack, 1, -1 do
		if lightingStack[index].key == key then
			table.remove(lightingStack, index)
			removed = true
		end
	end
	if not removed or not lightingBase then
		return
	end
	local base = lightingBase :: LightingTarget
	if #lightingStack == 0 then
		lightingBase = nil
		tweenLighting(base, seconds or 3)
	else
		local merged = table.clone(base)
		for name, value in lightingStack[#lightingStack].target do
			merged[name] = value
		end
		tweenLighting(merged, seconds or 3)
	end
end

-- Construção ------------------------------------------------------------------------------------

-- Part decorativa de evento: ancorada, sem colisão, sem toque e invisível para consultas espaciais.
function PhysUtil.GhostPart(props: { [string]: any }): BasePart
	local part = Instance.new(props.ClassName or "Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	for key, value in props do
		if key ~= "ClassName" and key ~= "Parent" then
			part[key] = value
		end
	end
	if props.Parent then
		part.Parent = props.Parent
	end
	return part
end

-- CFrame de um cilindro (eixo X do Roblox) indo de `a` até `b`.
function PhysUtil.CylinderBetween(a: Vector3, b: Vector3): (CFrame, number)
	local length = (b - a).Magnitude
	local middle = (a + b) / 2
	if length < 1e-3 then
		return CFrame.new(middle), 0
	end
	local up = math.abs((b - a).Unit.Y) > 0.98 and Vector3.xAxis or Vector3.yAxis
	return CFrame.lookAt(middle, b, up) * CFrame.Angles(0, math.pi / 2, 0), length
end

-- ParticleEmitter com propriedades (Color/Size/Transparency aceitam valores simples).
function PhysUtil.Emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	for key, value in props do
		if key == "Color" and typeof(value) == "Color3" then
			emitter.Color = ColorSequence.new(value)
		elseif (key == "Size" or key == "Transparency" or key == "Squash") and type(value) == "number" then
			emitter[key] = NumberSequence.new(value)
		else
			emitter[key] = value
		end
	end
	emitter.Parent = parent
	return emitter
end

-- Solda (WeldConstraint) as parts na raiz, deixando só a raiz ancorada.
function PhysUtil.WeldAll(root: BasePart, parts: { BasePart })
	for _, part in parts do
		if part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
			part.Anchored = false
			part.Massless = true
		end
	end
end

return PhysUtil
