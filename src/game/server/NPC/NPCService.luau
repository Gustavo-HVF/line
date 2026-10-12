--!nonstrict
-- Serviço de inimigos (servidor do jogo). API do contrato:
--   NPCService.Init()
--   NPCService.Spawn(kind, cframe, opts?) -> Model?   (nil se GameConfig.MAX_NPCS foi atingido)
--   NPCService.DespawnGroup(groupId) / NPCService.CountAlive(groupId?) / NPCService.DespawnAll()
-- Extra (fora do contrato, para os eventos de NPC): NPCService.GetGroup(groupId) -> { Model } vivos.
--
-- Como funciona:
--   * cada NPC é um Model em workspace.NPCs com a tag Enemy, atributos NpcKind/GroupId, barra de vida
--     (BillboardGui) e, conforme o tipo, Humanoid (terrestres) ou atributos Health/MaxHealth (voador e
--     planta). O modelo é montado por Rigs; o comportamento fica nos módulos *AI;
--   * UM único agendador no Heartbeat: cada NPC tem a hora do próximo "pensamento" e o loop atende os
--     que venceram em rodízio, com orçamento de tempo e de quantidade por frame (celular e servidor
--     leves). O mesmo loop avança os projéteis, a animação das pernas e os fades;
--   * morte: a IA para, o corpo desmonta (juntas quebradas, partes caem com colisão) e some com fade
--     em ~4 s. Remoção (DespawnGroup/DespawnAll): a IA para na hora e o modelo some com fade.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Tags = require(ReplicatedStorage.Shared.Tags)

local Brain = require(script.Parent.Brain)
local Effects = require(script.Parent.Effects)
local HealthBar = require(script.Parent.HealthBar)
local Kinds = require(script.Parent.Kinds)
local Projectiles = require(script.Parent.Projectiles)
local Rigs = require(script.Parent.Rigs)

local AIModules = {
	Monkey = require(script.Parent.MonkeyAI),
	Lion = require(script.Parent.LionAI),
	Hunter = require(script.Parent.HunterAI),
	Spider = require(script.Parent.SpiderAI),
	Mosquito = require(script.Parent.MosquitoAI),
	Plant = require(script.Parent.PlantAI),
}

local NPCService = {}

-- Ajustes ------------------------------------------------------------------------------------------

local FOLDER_NAME = "NPCs"
local EFFECTS_FOLDER_NAME = "Efeitos"
local NPC_GROUP = "Npc" -- grupo de colisão das raízes: NPC não esbarra em NPC (portas não entopem)
local DEBRIS_GROUP = "Debris" -- grupo do DestructionService (pedaço não colide com pedaço)
local THINK_BUDGET = 0.003 -- segundos de IA por frame, no máximo
local MAX_THINKS_PER_FRAME = 30
local MIN_THINK_DELAY = 0.03
local ERROR_THINK_DELAY = 1
local FADE_STEP = 0.1
local CORPSE_TIME = 3 -- o corpo fica parado este tempo e depois some em NPC_DESPAWN_FADE (≈ 4 s no total)
local CORPSE_MIN_PART = 0.45 -- partes menores que isto (olhos, dentes) somem na hora da morte
local CORPSE_MAX_PARTS = 24
local DROWN_DEPTH = 3 -- abaixo do nível do mar = afogou
local OUT_OF_BOUNDS_MARGIN = 30 -- além da borda da ilha (+ margem de eliminação) = morre
local ERROR_REPORT_GAP = 10

-- Estado -------------------------------------------------------------------------------------------

local initialized = false
local npcFolder: Folder? = nil
local npcGroupReady = false
local debrisGroupKnown = false
local active: { any } = {} -- registros; os que deixaram de estar vivos saem na próxima compactação
local fading: { any } = {} -- { model, parts = { [BasePart]: transparência inicial }, fadeAt, endAt, groupId }
local cursor = 0
local dirty = false
local lastFadeStep = 0
local serial = 0
local lastErrorReport: { [string]: number } = {}

-- Utilitários ---------------------------------------------------------------------------------------

local function report(key: string, message: string)
	local now = os.clock()
	local last = lastErrorReport[key]
	if last and now - last < ERROR_REPORT_GAP then
		return
	end
	lastErrorReport[key] = now
	warn("[NPCService] " .. message)
end

local function validNumber(value: any, default: number, min: number, max: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return default
	end
	return math.clamp(value, min, max)
end

-- Só a rotação no plano (o NPC nasce em pé, olhando para onde o CFrame aponta).
local function flatBase(cframe: CFrame): CFrame
	local position = cframe.Position
	local look = cframe.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(position, position + flat.Unit)
end

local function ensureFolder(): Folder
	local folder = npcFolder
	if not folder or folder.Parent ~= workspace then
		local existing = workspace:FindFirstChild(FOLDER_NAME)
		if existing and existing:IsA("Folder") then
			folder = existing
		else
			local created = Instance.new("Folder")
			created.Name = FOLDER_NAME
			created.Parent = workspace
			folder = created
		end
		npcFolder = folder
	end
	local effects = (folder :: Folder):FindFirstChild(EFFECTS_FOLDER_NAME)
	if not effects then
		effects = Instance.new("Folder")
		effects.Name = EFFECTS_FOLDER_NAME
		effects.Parent = folder
	end
	Effects.SetFolder(effects)
	return folder :: Folder
end

local function ensureCollisionGroups()
	if not npcGroupReady then
		local ok, err = pcall(function()
			if not PhysicsService:IsCollisionGroupRegistered(NPC_GROUP) then
				PhysicsService:RegisterCollisionGroup(NPC_GROUP)
			end
			PhysicsService:CollisionGroupSetCollidable(NPC_GROUP, NPC_GROUP, false)
		end)
		if ok then
			npcGroupReady = true
		else
			report("group", "Não foi possível criar o grupo de colisão dos NPCs: " .. tostring(err))
		end
	end
	if not debrisGroupKnown then
		local ok, registered = pcall(PhysicsService.IsCollisionGroupRegistered, PhysicsService, DEBRIS_GROUP)
		debrisGroupKnown = ok and registered == true
	end
end

local function isAlive(npc): boolean
	return npc.state == "alive"
end

-- Fades ---------------------------------------------------------------------------------------------

local function startFade(model: Model, delay: number, groupId: string?)
	local parts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts[descendant] = descendant.Transparency
		end
	end
	local now = os.clock()
	local fadeTime = math.max(GameConfig.NPC_DESPAWN_FADE, 0.05)
	table.insert(fading, {
		model = model,
		parts = parts,
		fadeAt = now + delay,
		endAt = now + delay + fadeTime,
		groupId = groupId,
	})
end

local function stepFades(now: number)
	for index = #fading, 1, -1 do
		local entry = fading[index]
		local model: Model = entry.model
		if not model.Parent or now >= entry.endAt then
			table.remove(fading, index)
			if model.Parent then
				model:Destroy()
			end
		elseif now >= entry.fadeAt then
			local alpha = math.clamp((now - entry.fadeAt) / math.max(entry.endAt - entry.fadeAt, 0.05), 0, 1)
			for part, base in entry.parts do
				if part.Parent then
					part.Transparency = base + (1 - base) * alpha
				end
			end
		end
	end
end

-- Parada da IA (morte ou remoção) ---------------------------------------------------------------------

local function stopBrain(npc)
	npc.alive = false
	dirty = true
	for _, connection in npc.connections do
		connection:Disconnect()
	end
	table.clear(npc.connections)
	local ai = npc.ai
	if ai and type(ai.Cleanup) == "function" then
		local ok, err = pcall(ai.Cleanup, npc)
		if not ok then
			report("cleanup:" .. npc.kind, ("Erro ao limpar a IA de %s: %s"):format(npc.kind, tostring(err)))
		end
	end
	Projectiles.ClearOwner(npc)
	if npc.bar then
		npc.bar:Destroy()
		npc.bar = nil
	end
	-- O caminho (Path) do Pathfinding não serve mais; um cálculo em andamento só termina e é ignorado.
	local path: Path? = npc.path
	npc.path = nil
	npc.waypoints = nil
	if path then
		pcall(path.Destroy, path)
	end
end

-- Desmonta o corpo: juntas quebradas, partes soltas com colisão, um empurrãozinho para fora.
local function dismantle(npc, center: Vector3)
	local model: Model = npc.model
	local rng: Random = npc.rng
	for _, descendant in model:GetDescendants() do
		if
			descendant:IsA("JointInstance")
			or descendant:IsA("WeldConstraint")
			or descendant:IsA("Beam")
			or descendant:IsA("Sound")
		then
			descendant:Destroy()
		end
	end
	local kept = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Parent then
			local size = descendant.Size
			local largest = math.max(size.X, size.Y, size.Z)
			if descendant.Transparency >= 0.99 or largest < CORPSE_MIN_PART or kept >= CORPSE_MAX_PARTS then
				descendant:Destroy()
			else
				kept += 1
				descendant.Anchored = false
				descendant.Massless = false
				descendant.CanCollide = true
				descendant.CanTouch = false
				if debrisGroupKnown then
					descendant.CollisionGroup = DEBRIS_GROUP
				end
				local away = descendant.Position - center
				local flat = Vector3.new(away.X, 0, away.Z)
				if flat.Magnitude < 0.05 then
					local angle = rng:NextNumber(0, math.pi * 2)
					flat = Vector3.new(math.cos(angle), 0, math.sin(angle))
				end
				descendant.AssemblyLinearVelocity = flat.Unit * rng:NextNumber(4, 11)
					+ Vector3.new(0, rng:NextNumber(5, 12), 0)
				descendant.AssemblyAngularVelocity =
					Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6), rng:NextNumber(-6, 6))
			end
		end
	end
end

local function handleDeath(npc)
	if not isAlive(npc) then
		return
	end
	npc.state = "dead"
	local model: Model = npc.model
	local root: BasePart = npc.root
	local center = if root.Parent then root.Position else model:GetPivot().Position
	stopBrain(npc)

	-- Vida zerada em qualquer caso (afogado, fora da ilha): IsEnemyAlive passa a ser falso.
	local humanoid: Humanoid? = npc.humanoid
	if humanoid and humanoid.Parent and humanoid.Health > 0 then
		humanoid.Health = 0
	end
	if not humanoid then
		model:SetAttribute("Health", 0)
	end
	model:SetAttribute("Dead", true)

	if not model.Parent then
		return
	end
	ensureCollisionGroups() -- o grupo "Debris" pode ter sido criado depois do Init
	local ok, err = pcall(dismantle, npc, center)
	if not ok then
		report("dismantle", "Erro ao desmontar o corpo: " .. tostring(err))
	end
	startFade(model, CORPSE_TIME, npc.groupId)
end

local function despawn(npc)
	if not isAlive(npc) then
		return
	end
	npc.state = "despawning"
	local model: Model = npc.model
	stopBrain(npc)
	-- Some de vez: ninguém mais mira nele nem o conta como inimigo.
	CollectionService:RemoveTag(model, Tags.Enemy)
	local root: BasePart = npc.root
	if root.Parent then
		local humanoid: Humanoid? = npc.humanoid
		if humanoid and humanoid.Parent then
			pcall(humanoid.MoveTo, humanoid, root.Position)
		end
		root.Anchored = true
	end
	if model.Parent then
		startFade(model, 0, npc.groupId)
	end
end

-- Modelo removido por fora (ex.: Destroy de outro sistema): só esquece o registro.
local function forget(npc)
	if not isAlive(npc) then
		return
	end
	npc.state = "gone"
	stopBrain(npc)
end

-- Vida -----------------------------------------------------------------------------------------------

local function onHealthChanged(npc, health: number, maxHealth: number)
	if not isAlive(npc) then
		return
	end
	if npc.bar then
		npc.bar:Set(health, maxHealth)
	end
	if health < (npc.lastHealth or maxHealth) then
		-- Quem bateu vira o alvo preferido por alguns segundos.
		local userId = npc.model:GetAttribute("LastAttackerUserId")
		if type(userId) == "number" then
			local attacker = Players:GetPlayerByUserId(userId)
			if attacker then
				Brain.Provoke(npc, attacker, os.clock())
			end
		end
	end
	npc.lastHealth = health
	if health <= 0 then
		handleDeath(npc)
	end
end

local function currentHealth(npc): (number, number)
	local humanoid: Humanoid? = npc.humanoid
	if humanoid then
		return humanoid.Health, humanoid.MaxHealth
	end
	local model: Model = npc.model
	return tonumber(model:GetAttribute("Health")) or 0, tonumber(model:GetAttribute("MaxHealth")) or npc.maxHealth
end

-- Agendador -----------------------------------------------------------------------------------------

local function compact()
	dirty = false
	local kept = {}
	for _, npc in active do
		if isAlive(npc) then
			table.insert(kept, npc)
		end
	end
	active = kept
	if cursor > #active then
		cursor = 0
	end
end

local function think(npc, now: number)
	local model: Model = npc.model
	local root: BasePart = npc.root
	if not model.Parent then
		forget(npc)
		return
	end
	if not root.Parent then
		handleDeath(npc)
		return
	end
	local health = currentHealth(npc)
	if health <= 0 then
		handleDeath(npc)
		return
	end
	-- Caiu no mar ou saiu da ilha (ex.: bote na beirada, tornado): morre.
	local position = root.Position
	local center = GameConfig.ISLAND_CENTER
	local dx, dz = position.X - center.X, position.Z - center.Z
	local limit = GameConfig.ISLAND_RADIUS + GameConfig.ELIMINATION_MARGIN + OUT_OF_BOUNDS_MARGIN
	if position.Y < GameConfig.WATER_LEVEL_Y - DROWN_DEPTH or dx * dx + dz * dz > limit * limit then
		handleDeath(npc)
		return
	end

	local dt = now - npc.lastThink
	npc.lastThink = now
	local ok, result = pcall(npc.ai.Think, npc, now, dt)
	local delay = npc.def.thinkInterval
	if not ok then
		report("think:" .. npc.kind, ("Erro na IA de %s: %s"):format(npc.kind, tostring(result)))
		delay = ERROR_THINK_DELAY
	elseif type(result) == "number" and result == result then
		delay = result
	end
	npc.nextThink = now + math.max(delay, MIN_THINK_DELAY)
end

local function onHeartbeat()
	local now = os.clock()
	if dirty then
		compact()
	end

	local okProjectiles, projectileError = pcall(Projectiles.Step, now)
	if not okProjectiles then
		report("projectiles", "Erro nos projéteis: " .. tostring(projectileError))
	end

	local count = #active
	if count > 0 then
		-- Rodízio: começa de onde parou no frame anterior; para quando o orçamento acaba.
		local started = os.clock()
		local thinks = 0
		for _ = 1, count do
			cursor = cursor % count + 1
			local npc = active[cursor]
			if npc and isAlive(npc) and now >= npc.nextThink then
				think(npc, now)
				thinks += 1
				if thinks >= MAX_THINKS_PER_FRAME or os.clock() - started >= THINK_BUDGET then
					break
				end
			end
		end
		-- Pernas (cada NPC limita a própria frequência e só anima perto de jogadores).
		for _, npc in active do
			if isAlive(npc) and npc.rig.gait then
				local ok, err = pcall(Brain.Animate, npc, now)
				if not ok then
					report("animate", "Erro na animação: " .. tostring(err))
				end
			end
		end
	end

	if #fading > 0 and now - lastFadeStep >= FADE_STEP then
		lastFadeStep = now
		local ok, err = pcall(stepFades, now)
		if not ok then
			report("fade", "Erro no fade dos NPCs: " .. tostring(err))
		end
	end
end

-- API ------------------------------------------------------------------------------------------------

function NPCService.Init()
	if initialized then
		return
	end
	initialized = true
	ensureFolder()
	ensureCollisionGroups()
	-- Remotes usados pelos NPCs (existem antes de qualquer cliente pedir).
	Net.event(Net.Names.Fx_Play)
	Net.event(Net.Names.Notify)

	-- Personagem novo: a lista de exclusão dos raios precisa incluí-lo logo.
	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(function()
			Effects.InvalidateParams()
		end)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function()
		Effects.InvalidateParams()
	end)

	RunService.Heartbeat:Connect(onHeartbeat)
end

-- Cria um inimigo do tipo `kind` em `cframe` (ponto no chão; a frente do NPC é o LookVector).
-- opts: { groupId: string?, health: number?, damage: number? }. Retorna o Model ou nil.
function NPCService.Spawn(kind: string, cframe: CFrame, opts: { [string]: any }?): Model?
	if type(kind) ~= "string" then
		report("kind", "Spawn chamado sem um tipo de NPC válido.")
		return nil
	end
	local def = Kinds.Get(kind)
	local ai = AIModules[kind]
	if not def or not ai then
		report("kind:" .. kind, ("Tipo de NPC desconhecido: '%s'."):format(kind))
		return nil
	end
	if typeof(cframe) ~= "CFrame" then
		report("cframe", "Spawn precisa de um CFrame.")
		return nil
	end
	local spawnPosition = cframe.Position
	local spawnSum = spawnPosition.X + spawnPosition.Y + spawnPosition.Z
	if spawnSum ~= spawnSum or math.abs(spawnSum) == math.huge then
		report("cframe", "Spawn recebeu uma posição inválida (NaN ou infinita).")
		return nil
	end
	if not initialized then
		NPCService.Init()
	end
	if NPCService.CountAlive() >= GameConfig.MAX_NPCS then
		return nil
	end

	local options = if type(opts) == "table" then opts else {}
	local groupId = if type(options.groupId) == "string" and options.groupId ~= "" then options.groupId else nil
	local maxHealth = validNumber(options.health, def.health, 1, 100000)
	local damage = validNumber(options.damage, def.damage, 0, 10000)
	local base = flatBase(cframe)

	local built, rigOrError = pcall(Rigs.Build, kind, def.displayName, base)
	if not built or not rigOrError then
		report("rig:" .. kind, ("Erro ao montar o modelo de %s: %s"):format(kind, tostring(rigOrError)))
		return nil
	end
	local rig = rigOrError
	local model: Model = rig.model
	local root: BasePart = rig.root
	local humanoid: Humanoid? = rig.humanoid

	serial += 1
	model:SetAttribute("NpcKind", kind)
	model:SetAttribute("NpcId", serial)
	if groupId then
		model:SetAttribute("GroupId", groupId)
	end
	if humanoid then
		humanoid.MaxHealth = maxHealth
		humanoid.Health = maxHealth
		humanoid.WalkSpeed = def.walkSpeed
		humanoid.JumpPower = def.jumpPower
	else
		model:SetAttribute("MaxHealth", maxHealth)
		model:SetAttribute("Health", maxHealth)
	end
	if npcGroupReady and humanoid then
		root.CollisionGroup = NPC_GROUP
	end

	local bar = HealthBar.new(rig.barAdornee, def.displayName, rig.barOffset, def.barMaxDistance, def.boss)
	CollectionService:AddTag(model, Tags.Enemy)
	model.Parent = ensureFolder()
	if humanoid then
		-- A física do NPC fica no servidor (nada de cliente puxando o inimigo).
		local ok, err = pcall(root.SetNetworkOwner, root, nil)
		if not ok then
			report("owner", "Não foi possível definir o dono de rede do NPC: " .. tostring(err))
		end
		-- Estados que um inimigo nunca usa (depois de entrar no workspace, onde o servidor simula o Humanoid):
		-- menos trabalho para o Humanoid e nada de sentar em bancos.
		for _, state in
			{
				Enum.HumanoidStateType.Climbing,
				Enum.HumanoidStateType.Seated,
				Enum.HumanoidStateType.FallingDown,
				Enum.HumanoidStateType.Ragdoll,
				Enum.HumanoidStateType.PlatformStanding,
			}
		do
			humanoid:SetStateEnabled(state, false)
		end
	end

	local now = os.clock()
	local rng = Random.new()
	local npc = {
		id = serial,
		kind = kind,
		def = def,
		ai = ai,
		model = model,
		rig = rig,
		root = root,
		humanoid = humanoid,
		groupId = groupId,
		state = "alive",
		alive = true,
		damage = damage,
		maxHealth = maxHealth,
		lastHealth = maxHealth,
		memory = {},
		rng = rng,
		home = base.Position,
		feetOffset = rig.feetOffset,
		-- Espalha os primeiros pensamentos (um grupo inteiro não pensa no mesmo frame).
		nextThink = now + rng:NextNumber(0.05, 0.25),
		lastThink = now,
		bar = bar,
		connections = {},
	}

	if humanoid then
		table.insert(
			npc.connections,
			humanoid.HealthChanged:Connect(function(health)
				onHealthChanged(npc, health, humanoid.MaxHealth)
			end)
		)
		table.insert(
			npc.connections,
			humanoid.Died:Connect(function()
				handleDeath(npc)
			end)
		)
	else
		table.insert(
			npc.connections,
			model:GetAttributeChangedSignal("Health"):Connect(function()
				local health, max = currentHealth(npc)
				onHealthChanged(npc, health, max)
			end)
		)
	end
	table.insert(
		npc.connections,
		model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(workspace) then
				forget(npc)
			end
		end)
	)

	table.insert(active, npc)

	local ok, err = pcall(ai.Setup, npc, now)
	if not ok then
		report("setup:" .. kind, ("Erro ao preparar a IA de %s: %s"):format(kind, tostring(err)))
	end
	return model
end

-- Inimigos vivos (de um grupo ou de todos).
function NPCService.CountAlive(groupId: string?): number
	local count = 0
	for _, npc in active do
		if isAlive(npc) and (groupId == nil or npc.groupId == groupId) then
			count += 1
		end
	end
	return count
end

-- Models vivos de um grupo (extra para os eventos de NPC).
function NPCService.GetGroup(groupId: string): { Model }
	local models = {}
	if type(groupId) ~= "string" then
		return models
	end
	for _, npc in active do
		if isAlive(npc) and npc.groupId == groupId then
			table.insert(models, npc.model)
		end
	end
	return models
end

-- Remove todos os inimigos do grupo (com fade) e apressa o sumiço dos corpos dele.
function NPCService.DespawnGroup(groupId: string)
	if type(groupId) ~= "string" then
		return
	end
	for _, npc in table.clone(active) do
		if npc.groupId == groupId then
			despawn(npc)
		end
	end
	local now = os.clock()
	for _, entry in fading do
		if entry.groupId == groupId and entry.fadeAt > now then
			local fadeTime = entry.endAt - entry.fadeAt
			entry.fadeAt = now
			entry.endAt = now + fadeTime
		end
	end
end

-- Remove todos os inimigos (fim da partida).
function NPCService.DespawnAll()
	for _, npc in table.clone(active) do
		despawn(npc)
	end
	local now = os.clock()
	for _, entry in fading do
		if entry.fadeAt > now then
			local fadeTime = entry.endAt - entry.fadeAt
			entry.fadeAt = now
			entry.endAt = now + fadeTime
		end
	end
	Projectiles.ClearAll()
	Effects.ClearClaims()
	for kind, ai in AIModules do
		if type(ai.ResetAll) == "function" then
			local ok, err = pcall(ai.ResetAll)
			if not ok then
				report("reset:" .. kind, ("Erro ao reiniciar a IA de %s: %s"):format(kind, tostring(err)))
			end
		end
	end
end

return NPCService
