--!nonstrict
-- Eventos do tabuleiro (servidor):
--   * carrega todo ModuleScript filho direto de Game/Events que tenha Id e Start;
--   * sorteia no Init o plano "casa -> evento" (pesos, MinSpace, sem repetir o mesmo evento em sequência);
--   * inicia eventos que duram até o fim da partida: cada evento roda em focos (pasta
--     workspace.ActiveEvents/<id do foco>, EventContext do contrato) que terminam, chamam o cleanup e
--     recomeçam em outro ponto do mapa; avisa os clientes (Event_Started / Event_Ended / Notify);
--   * eventos físicos trocam a textura dos blocos em volta de cada foco (EventHelpers/SurfaceSkin).
-- Um evento com erro nunca derruba o serviço: tudo que vem dos módulos de evento roda em pcall.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)

local BoardService = require(script.Parent.BoardService)
local CombatUtil = require(script.Parent.CombatUtil)
local GroundUtil = require(script.Parent.EventHelpers.GroundUtil)
local SurfaceSkin = require(script.Parent.EventHelpers.SurfaceSkin)

local EventService = {}

local FALLBACK_RIDDLE = "Um tambor distante começa a soar;\na selva acordou e vem te visitar."
local CLEANUP_TIMEOUT = 30 -- a pasta do evento é destruída mesmo que o cleanup trave
local MAX_START_FAILURES = 3

local initialized = false
local mapInfo = nil
local remotes: { [string]: RemoteEvent } = {}
local activeFolder: Folder = nil
local services: { [string]: any } = {}
local definitions: { [string]: any } = {}
local order: { string } = {} -- ids em ordem alfabética (sorteio determinístico dado o Random)
local plan: { [number]: string } = {}
local lastPlannedId: string? = nil
local active: { any } = {} -- eventos em ordem de início; cada um tem seus focos (runs)
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
	-- Focos ao mesmo tempo: físicos se espalham (vários focos); NPC e os que não se espalham têm um só.
	local spreads = result.Kind == "physical" and definition.Spread ~= false
	result.Spread = spreads
	result.Sites =
		math.floor(positiveNumber(definition.Sites, if spreads then GameConfig.PHYSICAL_EVENT_SITES else 1, 1, 8))
	-- Pausa (s) entre um foco terminar e o próximo começar.
	local delayRange = definition.RestartDelay
	if type(delayRange) == "table" and type(delayRange[1]) == "number" and type(delayRange[2]) == "number" then
		result.RestartDelay = { math.max(delayRange[1], 0), math.max(delayRange[2], delayRange[1], 0) }
	elseif result.Kind == "npc" then
		result.RestartDelay = { 25, 45 }
	else
		result.RestartDelay = { 3, 8 }
	end
	if
		definition.Skin ~= nil and (type(definition.Skin) ~= "table" or typeof(definition.Skin.Material) ~= "EnumItem")
	then
		warn(("[EventService] Skin inválido no evento '%s' (ignorado)."):format(definition.Id))
		result.Skin = nil
	end
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

-- Ciclo de vida -------------------------------------------------------------------------------
-- Um evento (o que aparece no HUD) dura até o fim da partida. Ele acontece em "focos": cada foco roda o
-- Start do módulo, termina sozinho (Duration ou ctx.finish, ex.: todos os bichos mortos) e, depois de uma
-- pausa, recomeça em outro lugar. Eventos físicos têm vários focos espalhados pelo mapa; eventos de NPC
-- mandam novas ondas perto dos jogadores; o pelicano volta sempre para o tabuleiro.

local function countRuns(): number
	local count = 0
	for _, event in active do
		count += #event.runs
	end
	return count
end

local function removeRun(event, run)
	local index = table.find(event.runs, run)
	if index then
		table.remove(event.runs, index)
	end
end

local scheduleNext: (event: any, slot: number) -> ()

local function stopRun(run, natural: boolean?)
	if run.stopped then
		return
	end
	if run.starting then
		-- Start ainda está rodando: termina assim que ele devolver o cleanup.
		run.active = false
		run.pendingStop = true
		run.pendingNatural = natural
		return
	end
	run.stopped = true
	run.active = false
	if run.timer and coroutine.running() ~= run.timer then
		pcall(task.cancel, run.timer)
	end
	local event = run.event
	removeRun(event, run)

	-- O cleanup pode ceder (ex.: fade de NPCs): roda em outra thread e só então destrói a pasta.
	local folder = run.folder
	local cleanup = run.cleanup
	-- Rede de segurança: os NPCs do foco usam groupId = id do foco. Se o Start falhou (sem cleanup)
	-- ou o cleanup quebrou/travou, eles não sumiriam nunca.
	local function despawnGroup()
		local npc = services.NPC
		if npc and type(npc.DespawnGroup) == "function" then
			pcall(npc.DespawnGroup, run.instanceId)
		end
	end
	task.spawn(function()
		if cleanup then
			local ok, err = pcall(cleanup)
			if not ok then
				warn(("[EventService] Erro no cleanup de '%s': %s"):format(run.instanceId, tostring(err)))
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

	if natural and not event.stopped then
		scheduleNext(event, run.slot)
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

-- Ponto no chão em algum lugar da ilha: dentro de uma região nomeada (cômodos, labirinto, estufa...) ou
-- em qualquer parte do platô.
local function randomMapPoint(rng: Random): Vector3
	local regions = mapInfo and mapInfo.regions
	if type(regions) == "table" and #regions > 0 and rng:NextNumber() < 0.7 then
		for _ = 1, 4 do
			local region = regions[rng:NextInteger(1, #regions)]
			if type(region) == "table" and typeof(region.cframe) == "CFrame" and typeof(region.size) == "Vector3" then
				local size = region.size
				local top = region.cframe
					* Vector3.new(
						rng:NextNumber(-0.4, 0.4) * size.X,
						size.Y / 2 - 0.5,
						rng:NextNumber(-0.4, 0.4) * size.Z
					)
				local ground = GroundUtil.FindGround(top, size.Y + 10, 0)
				if ground then
					return ground
				end
			end
		end
	end
	local center = mapInfo and mapInfo.islandCenter or GameConfig.ISLAND_CENTER
	local radius = (mapInfo and mapInfo.islandRadius or GameConfig.ISLAND_RADIUS) * 0.82
	local groundY = mapInfo and mapInfo.groundY or GameConfig.GROUND_Y
	local waterY = mapInfo and mapInfo.waterLevelY or GameConfig.WATER_LEVEL_Y
	for _ = 1, 10 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = math.sqrt(rng:NextNumber()) * radius
		local probe =
			Vector3.new(center.X + math.cos(angle) * distance, groundY + 80, center.Z + math.sin(angle) * distance)
		local ground = GroundUtil.FindGround(probe, 140, 0)
		if ground and ground.Y > waterY + 1 then
			return ground
		end
	end
	return BoardService.GetBoardPosition()
end

-- Perto de um jogador vivo qualquer (ou do tabuleiro, se ninguém estiver vivo).
local function nearRandomPlayer(rng: Random, minDistance: number, maxDistance: number): Vector3
	local alive = CombatUtil.GetAlivePlayers()
	if #alive > 0 then
		local player = alive[rng:NextInteger(1, #alive)]
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return GroundUtil.RandomPointNear(root.Position, minDistance, maxDistance, rng)
		end
	end
	return BoardService.GetBoardPosition()
end

local function nextPosition(event, rng: Random): Vector3
	local definition = event.definition
	if definition.Spread == false then
		return BoardService.GetBoardPosition()
	end
	if definition.Kind == "npc" then
		return nearRandomPlayer(rng, 20, 60)
	end
	if rng:NextNumber() < 0.45 then
		return nearRandomPlayer(rng, 25, 110)
	end
	return randomMapPoint(rng)
end

local function startRun(event, slot: number, position: Vector3)
	if event.stopped then
		return
	end
	local definition = event.definition
	counter += 1
	local instanceId = ("%s_%d"):format(definition.Id, counter)
	local folder = Instance.new("Folder")
	folder.Name = instanceId
	folder.Parent = activeFolder

	local run = {
		event = event,
		slot = slot,
		instanceId = instanceId,
		folder = folder,
		active = true,
		stopped = false,
		starting = true,
		pendingStop = false,
		pendingNatural = false,
		cleanup = nil,
		timer = nil,
	}
	table.insert(event.runs, run)

	local rng = Random.new()
	local context = {
		instanceId = instanceId,
		eventId = definition.Id,
		position = position,
		radius = definition.Radius,
		duration = definition.Duration,
		mapInfo = mapInfo,
		folder = folder,
		random = rng,
		isActive = function(): boolean
			return run.active
		end,
		finish = function()
			if run.stopped or run.pendingStop then
				return
			end
			run.active = false
			if run.starting then
				run.pendingStop = true
				run.pendingNatural = true
			else
				task.defer(stopRun, run, true)
			end
		end,
		services = services,
	}

	-- Blocos em volta do foco mudam de textura conforme o evento (permanente).
	if definition.Skin then
		task.spawn(
			SurfaceSkin.Apply,
			definition.Skin,
			position,
			math.min(definition.Radius * 0.75, 34),
			rng,
			definition.Id
		)
	end

	local ok, result = pcall(definition.Start, context)
	run.starting = false
	if not ok then
		warn(("[EventService] Erro ao iniciar '%s': %s"):format(definition.Id, tostring(result)))
		event.failures += 1
		run.pendingStop = true
		-- Um módulo que quebra sempre não fica tentando para sempre (3 falhas seguidas = para este foco).
		run.pendingNatural = event.failures < MAX_START_FAILURES
	else
		event.failures = 0
		if type(result) == "function" then
			run.cleanup = result
		end
	end

	if run.pendingStop then
		stopRun(run, run.pendingNatural)
	elseif definition.Kind ~= "npc" then
		-- Focos físicos terminam no tempo deles e recomeçam em outro lugar. Os de NPC terminam quando a
		-- onda inteira morre (ctx.finish).
		run.timer = task.delay(definition.Duration, stopRun, run, true)
	end
end

function scheduleNext(event, slot: number)
	local definition = event.definition
	local delayRange = definition.RestartDelay
	task.spawn(function()
		task.wait(random:NextNumber(delayRange[1], delayRange[2]))
		-- Limite global de focos (desempenho): espera vaga.
		while not event.stopped and countRuns() >= GameConfig.MAX_EVENT_SITES do
			task.wait(5)
		end
		if event.stopped then
			return
		end
		local ok, err = pcall(function()
			startRun(event, slot, nextPosition(event, Random.new()))
		end)
		if not ok then
			warn(("[EventService] Erro ao reiniciar '%s': %s"):format(definition.Id, tostring(err)))
			if not event.stopped then
				scheduleNext(event, slot)
			end
		end
	end)
end

local function watchReady(player: Player)
	local function sendActive()
		if not player.Parent or not player:GetAttribute("ClientReady") then
			return
		end
		-- Quem chega no meio recebe os eventos em andamento.
		for _, event in active do
			remotes.started:FireClient(player, table.clone(event.info))
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

-- Inicia o evento em `position` (o primeiro foco) e devolve o id do evento ("" se ele não existe).
-- O evento continua até EventService.StopAll (fim da partida).
function EventService.Start(eventId: string, position: Vector3): string
	local definition = definitions[eventId]
	if not initialized or not definition then
		warn(("[EventService] Evento desconhecido: %s"):format(tostring(eventId)))
		return ""
	end
	if typeof(position) ~= "Vector3" then
		position = BoardService.GetBoardPosition()
	end

	counter += 1
	local instanceId = ("%s_evento_%d"):format(definition.Id, counter)
	local regionName = regionNameAt(position)
	local event = {
		instanceId = instanceId,
		eventId = definition.Id,
		definition = definition,
		stopped = false,
		failures = 0,
		runs = {},
		info = {
			id = instanceId,
			eventId = definition.Id,
			name = definition.DisplayName,
			position = position,
			radius = definition.Radius,
			duration = -1, -- até o fim da partida
			regionName = regionName,
		},
	}
	table.insert(active, event)

	remotes.started:FireAllClients(event.info)
	local where = if definition.Kind == "physical" and definition.Spread ~= false
		then "espalhando-se pelo mapa"
		else regionName or "perto do tabuleiro"
	remotes.notify:FireAllClients(
		("Evento: %s — %s (até o fim da partida)"):format(definition.DisplayName, where),
		"warning"
	)

	-- Primeiro foco onde o dado foi jogado; os outros (eventos físicos) já em pontos espalhados.
	startRun(event, 1, position)
	for slot = 2, definition.Sites do
		task.delay(random:NextNumber(1.5, 6), function()
			if not event.stopped and countRuns() < GameConfig.MAX_EVENT_SITES then
				local ok, err = pcall(startRun, event, slot, nextPosition(event, Random.new()))
				if not ok then
					warn(("[EventService] Erro ao abrir um foco de '%s': %s"):format(definition.Id, tostring(err)))
				end
			elseif not event.stopped then
				scheduleNext(event, slot)
			end
		end)
	end
	return instanceId
end

-- Encerra todos os eventos (vitória / derrota).
function EventService.StopAll()
	for _, event in table.clone(active) do
		event.stopped = true
		for _, run in table.clone(event.runs) do
			stopRun(run, false)
			-- Segurança: se o foco ainda estava iniciando, sai da lista à força.
			removeRun(event, run)
		end
		remotes.ended:FireAllClients(event.instanceId)
	end
	table.clear(active)
end

-- Lista dos eventos ativos (payloads EventInfoPayload; duration = -1 = até o fim da partida).
function EventService.GetActive()
	local list = {}
	for _, event in active do
		table.insert(list, table.clone(event.info))
	end
	return list
end

return EventService
