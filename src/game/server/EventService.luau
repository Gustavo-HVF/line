--!nonstrict
-- Eventos do tabuleiro (servidor):
--   * carrega todo ModuleScript filho direto de Game/Events que tenha Id e Start;
--   * sorteia no Init o plano "casa -> evento" (pesos, MinSpace, sem repetir o mesmo evento em sequência);
--   * inicia instâncias (pasta workspace.ActiveEvents/<instanceId>, EventContext do contrato),
--     agenda o fim, chama o cleanup e avisa os clientes (Event_Started / Event_Ended / Notify).
-- Um evento com erro nunca derruba o serviço: tudo que vem dos módulos de evento roda em pcall.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)

local BoardService = require(script.Parent.BoardService)
local CombatUtil = require(script.Parent.CombatUtil)
local GroundUtil = require(script.Parent.EventHelpers.GroundUtil)

local EventService = {}

local FALLBACK_RIDDLE = "Um tambor distante começa a soar;\na selva acordou e vem te visitar."
local CLEANUP_TIMEOUT = 30 -- a pasta do evento é destruída mesmo que o cleanup trave

local initialized = false
local mapInfo = nil
local remotes: { [string]: RemoteEvent } = {}
local activeFolder: Folder = nil
local services: { [string]: any } = {}
local definitions: { [string]: any } = {}
local order: { string } = {} -- ids em ordem alfabética (sorteio determinístico dado o Random)
local plan: { [number]: string } = {}
local lastPlannedId: string? = nil
local active: { any } = {} -- registros em ordem de início (o primeiro é o mais antigo)
local counter = 0
local random = Random.new()

-- Utilitários ---------------------------------------------------------------------------

-- require seguro de um módulo de outro dono: um módulo ausente ou quebrado vira nil (com aviso).
local function tryRequire(...: string): any
	local current: Instance? = script.Parent
	local path = {}
	for _, name in { ... } do
		table.insert(path, name)
		current = current and current:FindFirstChild(name)
	end
	local label = table.concat(path, ".")
	if not current or not current:IsA("ModuleScript") then
		warn(("[EventService] Módulo '%s' não encontrado; os eventos terão esse serviço como nil."):format(label))
		return nil
	end
	local ok, result = pcall(require, current)
	if not ok then
		warn(("[EventService] Erro ao carregar '%s': %s"):format(label, tostring(result)))
		return nil
	end
	return result
end

local function positiveNumber(value: any, default: number, min: number, max: number): number
	if type(value) ~= "number" or value ~= value then
		return default
	end
	return math.clamp(value, min, max)
end

-- Copia a definição preenchendo valores padrão e descartando campos inválidos.
local function normalize(definition: any, moduleName: string)
	local result = table.clone(definition)
	result.DisplayName = (type(definition.DisplayName) == "string" and definition.DisplayName ~= "")
			and definition.DisplayName
		or definition.Id
	result.Kind = (definition.Kind == "npc" or definition.Kind == "physical") and definition.Kind or "physical"
	result.Weight = positiveNumber(definition.Weight, 1, 0.01, 1000)
	result.MinSpace = math.floor(positiveNumber(definition.MinSpace, 1, 1, GameConfig.BOARD_SPACES))
	result.Duration = positiveNumber(definition.Duration, 60, 5, 900)
	result.Radius = positiveNumber(definition.Radius, GameConfig.EVENT_DEFAULT_RADIUS, 4, 1000)
	local riddles = {}
	if type(definition.Riddles) == "table" then
		for _, riddle in definition.Riddles do
			if type(riddle) == "string" and riddle ~= "" then
				table.insert(riddles, riddle)
			end
		end
	end
	if #riddles == 0 then
		warn(
			("[EventService] O evento '%s' não tem enigmas válidos; usando um enigma genérico."):format(
				definition.Id
			)
		)
	end
	result.Riddles = riddles
	if definition.Id ~= moduleName then
		warn(("[EventService] O Id '%s' é diferente do nome do arquivo '%s'."):format(definition.Id, moduleName))
	end
	return result
end

local function loadDefinitions()
	local folder = script.Parent:FindFirstChild("Events")
	if not folder then
		warn("[EventService] Pasta Game/Events não encontrada: nenhum evento vai acontecer.")
		return
	end
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			local ok, definition = pcall(require, child)
			if not ok then
				warn(("[EventService] Erro ao carregar o evento '%s': %s"):format(child.Name, tostring(definition)))
			elseif
				type(definition) ~= "table"
				or type(definition.Id) ~= "string"
				or definition.Id == ""
				or type(definition.Start) ~= "function"
			then
				warn(("[EventService] '%s' não é um evento válido (precisa de Id e Start)."):format(child.Name))
			elseif definitions[definition.Id] then
				warn(("[EventService] Id de evento repetido: '%s' (ignorado)."):format(definition.Id))
			else
				definitions[definition.Id] = normalize(definition, child.Name)
				table.insert(order, definition.Id)
			end
		end
	end
	table.sort(order)
	if #order == 0 then
		warn("[EventService] Nenhum evento carregado: as jogadas vão andar a peça, mas nada vai acontecer.")
	else
		print(("[EventService] %d evento(s) carregado(s): %s"):format(#order, table.concat(order, ", ")))
	end
end

-- Sorteio ---------------------------------------------------------------------------------

local function pickWeighted(list: { any }): string?
	local totalWeight = 0
	for _, definition in list do
		totalWeight += definition.Weight
	end
	if #list == 0 or totalWeight <= 0 then
		return nil
	end
	local roll = random:NextNumber(0, totalWeight)
	for _, definition in list do
		roll -= definition.Weight
		if roll <= 0 then
			return definition.Id
		end
	end
	return list[#list].Id
end

-- Escolhe um evento para a casa. Tenta, em ordem: respeitar MinSpace e evitar `exclude` e `avoid`;
-- depois só MinSpace e `exclude`; depois o(s) de menor MinSpace. Retorna nil se não houver eventos.
local function pickFor(spaceIndex: number, exclude: string?, avoid: { [string]: boolean }?): string?
	local strict, relaxed = {}, {}
	for _, id in order do
		local definition = definitions[id]
		if definition.MinSpace <= spaceIndex and id ~= exclude then
			table.insert(relaxed, definition)
			if not (avoid and avoid[id]) then
				table.insert(strict, definition)
			end
		end
	end
	local picked = pickWeighted(strict) or pickWeighted(relaxed)
	if picked then
		return picked
	end

	-- Nenhum elegível pela casa: usa os de menor MinSpace (preferindo não repetir).
	local lowest = math.huge
	for _, id in order do
		lowest = math.min(lowest, definitions[id].MinSpace)
	end
	local fallback, fallbackAny = {}, {}
	for _, id in order do
		local definition = definitions[id]
		if definition.MinSpace == lowest then
			table.insert(fallbackAny, definition)
			if id ~= exclude then
				table.insert(fallback, definition)
			end
		end
	end
	return pickWeighted(fallback) or pickWeighted(fallbackAny)
end

local function buildPlan()
	table.clear(plan)
	local previous: string? = nil
	for spaceIndex = 1, GameConfig.BOARD_SPACES do
		local id = pickFor(spaceIndex, previous, nil)
		if id then
			plan[spaceIndex] = id
			previous = id
		end
	end
end

-- Ciclo de vida das instâncias -----------------------------------------------------------

local function removeFromActive(record)
	local index = table.find(active, record)
	if index then
		table.remove(active, index)
	end
end

local function stopRecord(record, natural: boolean?)
	if record.stopped then
		return
	end
	if record.starting then
		-- Start ainda está rodando: termina assim que ele devolver o cleanup.
		record.active = false
		record.pendingStop = true
		return
	end
	record.stopped = true
	record.active = false
	if record.timer and coroutine.running() ~= record.timer then
		pcall(task.cancel, record.timer)
	end
	removeFromActive(record)

	-- O cleanup pode ceder (ex.: fade de NPCs): roda em outra thread e só então destrói a pasta.
	local folder = record.folder
	local cleanup = record.cleanup
	-- Rede de segurança: os NPCs do evento usam groupId = instanceId. Se o Start falhou (sem cleanup)
	-- ou o cleanup quebrou/travou, eles sumiriam nunca.
	local function despawnGroup()
		local npc = services.NPC
		if npc and type(npc.DespawnGroup) == "function" then
			pcall(npc.DespawnGroup, record.instanceId)
		end
	end
	task.spawn(function()
		if cleanup then
			local ok, err = pcall(cleanup)
			if not ok then
				warn(("[EventService] Erro no cleanup de '%s': %s"):format(record.instanceId, tostring(err)))
			end
		end
		despawnGroup()
		if folder and folder.Parent then
			folder:Destroy()
		end
	end)
	task.delay(CLEANUP_TIMEOUT, function()
		despawnGroup()
		if folder and folder.Parent then
			folder:Destroy()
		end
	end)

	remotes.ended:FireAllClients(record.instanceId)
	if natural then
		remotes.notify:FireAllClients(("%s acabou."):format(record.definition.DisplayName), "info")
	end
end

local function regionNameAt(position: Vector3): string?
	local map = services.Map
	if not map or type(map.GetRegionAt) ~= "function" then
		return nil
	end
	local ok, region = pcall(map.GetRegionAt, position)
	if ok and type(region) == "table" and type(region.name) == "string" then
		return region.name
	end
	return nil
end

local function watchReady(player: Player)
	local function sendActive()
		if not player.Parent or not player:GetAttribute("ClientReady") then
			return
		end
		-- Quem chega no meio recebe os eventos em andamento com a duração que ainda falta.
		for _, record in active do
			local info = table.clone(record.info)
			info.duration = math.max(record.definition.Duration - (os.clock() - record.startedAt), 0)
			remotes.started:FireClient(player, info)
		end
	end
	player:GetAttributeChangedSignal("ClientReady"):Connect(sendActive)
	sendActive()
end

-- API pública ----------------------------------------------------------------------------

function EventService.Init(info)
	if initialized then
		return
	end
	initialized = true
	mapInfo = info

	remotes.started = Net.event(Net.Names.Event_Started)
	remotes.ended = Net.event(Net.Names.Event_Ended)
	remotes.notify = Net.event(Net.Names.Notify)
	remotes.ready = Net.event(Net.Names.Game_ClientReady)

	local existing = workspace:FindFirstChild("ActiveEvents")
	if existing and existing:IsA("Folder") then
		activeFolder = existing
	else
		local folder = Instance.new("Folder")
		folder.Name = "ActiveEvents"
		folder.Parent = workspace
		activeFolder = folder
	end

	services = {
		Destruction = tryRequire("DestructionService"),
		NPC = tryRequire("NPC", "NPCService"),
		Board = BoardService,
		Combat = CombatUtil,
		Map = tryRequire("Map", "MapBuilder"),
		Ground = GroundUtil,
	}

	loadDefinitions()
	buildPlan()

	remotes.ready.OnServerEvent:Connect(function(player)
		if not player:GetAttribute("ClientReady") then
			player:SetAttribute("ClientReady", true)
		end
	end)
	Players.PlayerAdded:Connect(watchReady)
	for _, player in Players:GetPlayers() do
		watchReady(player)
	end
end

function EventService.GetDefinition(eventId: string)
	return definitions[eventId]
end

-- Evento planejado para a casa. Evita repetir o último evento sorteado e eventos ainda ativos
-- (quando há alternativa). Retorna "" se nenhum evento foi carregado.
function EventService.EventForSpace(spaceIndex: number): string
	if #order == 0 then
		return ""
	end
	local index = math.clamp(math.floor(tonumber(spaceIndex) or 1), 1, GameConfig.BOARD_SPACES)
	local id = plan[index] or pickFor(index, lastPlannedId, nil)
	local activeIds = {}
	for _, record in active do
		activeIds[record.eventId] = true
	end
	if id == lastPlannedId or activeIds[id] then
		local alternative = pickFor(index, lastPlannedId, activeIds)
		if alternative then
			id = alternative
			plan[index] = alternative
		end
	end
	lastPlannedId = id
	return id or ""
end

-- Um dos enigmas do evento (ao acaso).
function EventService.GetRiddle(eventId: string): string
	local definition = definitions[eventId]
	if not definition or #definition.Riddles == 0 then
		return FALLBACK_RIDDLE
	end
	return definition.Riddles[random:NextInteger(1, #definition.Riddles)]
end

-- Inicia o evento em `position` e devolve o id da instância ("" se o evento não existe).
function EventService.Start(eventId: string, position: Vector3): string
	local definition = definitions[eventId]
	if not initialized or not definition then
		warn(("[EventService] Evento desconhecido: %s"):format(tostring(eventId)))
		return ""
	end
	if typeof(position) ~= "Vector3" then
		position = BoardService.GetBoardPosition()
	end

	-- Limite de eventos simultâneos: o mais antigo termina.
	local maxActive = math.max(math.floor(GameConfig.MAX_ACTIVE_EVENTS), 1)
	while #active >= maxActive do
		stopRecord(active[1], false)
		-- Segurança: se o registro não saiu da lista (ainda iniciando), remove à força.
		if active[1] and active[1].pendingStop then
			table.remove(active, 1)
		end
	end

	counter += 1
	local instanceId = ("%s_%d"):format(definition.Id, counter)
	local folder = Instance.new("Folder")
	folder.Name = instanceId
	folder.Parent = activeFolder

	local regionName = regionNameAt(position)
	local record = {
		instanceId = instanceId,
		eventId = definition.Id,
		definition = definition,
		folder = folder,
		active = true,
		stopped = false,
		starting = true,
		pendingStop = false,
		startedAt = os.clock(),
		cleanup = nil,
		timer = nil,
		info = {
			id = instanceId,
			eventId = definition.Id,
			name = definition.DisplayName,
			position = position,
			radius = definition.Radius,
			duration = definition.Duration,
			regionName = regionName,
		},
	}
	table.insert(active, record)

	local context = {
		instanceId = instanceId,
		eventId = definition.Id,
		position = position,
		radius = definition.Radius,
		duration = definition.Duration,
		mapInfo = mapInfo,
		folder = folder,
		random = Random.new(),
		isActive = function(): boolean
			return record.active
		end,
		finish = function()
			if record.stopped or record.pendingStop then
				return
			end
			record.active = false
			if record.starting then
				record.pendingStop = true
			else
				task.defer(stopRecord, record, true)
			end
		end,
		services = services,
	}

	remotes.started:FireAllClients(record.info)
	remotes.notify:FireAllClients(
		("Evento: %s — %s"):format(definition.DisplayName, regionName or "perto do tabuleiro"),
		"warning"
	)

	local ok, result = pcall(definition.Start, context)
	record.starting = false
	if not ok then
		warn(("[EventService] Erro ao iniciar '%s': %s"):format(definition.Id, tostring(result)))
		record.pendingStop = true
	elseif type(result) == "function" then
		record.cleanup = result
	end

	if record.pendingStop then
		stopRecord(record, ok)
	else
		record.timer = task.delay(definition.Duration, stopRecord, record, true)
	end
	return instanceId
end

-- Encerra todos os eventos ativos (vitória / derrota).
function EventService.StopAll()
	for _, record in table.clone(active) do
		stopRecord(record, false)
	end
	table.clear(active)
end

-- Lista dos eventos ativos (payloads EventInfoPayload).
function EventService.GetActive()
	local list = {}
	for _, record in active do
		table.insert(list, table.clone(record.info))
	end
	return list
end

return EventService
