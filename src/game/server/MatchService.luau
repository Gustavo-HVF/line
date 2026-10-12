--!nonstrict
-- Fluxo da partida (servidor):
--   Loading -> WaitingPlayers -> Intro (primeira jogada liberada) -> Countdown (10 s) -> portas abrem
--   -> Playing -> Victory | Defeat -> volta ao lobby.
--
-- Participantes: quem está no servidor até a primeira jogada (o "início" da partida). Quem entra depois
-- vira espectador. Quem já estava no servidor, mas ainda carregando, nasce assim que ficar pronto.
-- "Pronto" = atributo ClientReady no Player (marcado quando o cliente manda Game_ClientReady).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)

local CharacterService = require(ServerScriptService.ServerShared.CharacterService)
local GlobalStats = require(ServerScriptService.ServerShared.GlobalStats)

local BoardService = require(script.Parent.BoardService)
local EventService = require(script.Parent.EventService)
local MatchStats = require(script.Parent.MatchStats)

local MatchService = {}

type Participant = {
	userId: number,
	name: string,
	eliminated: boolean,
	spawned: boolean,
	left: boolean,
}

local STUDIO_GRACE = 3 -- sem TeleportData: espera isto depois do primeiro pronto
local CORPSE_TIME = 6 -- segundos até o corpo do eliminado sumir
local TELEPORT_ATTEMPTS = 3
local TELEPORT_PLAYER_RETRIES = 2
local MAX_EXPECTED = 16
local MAX_RESULTS = 8 -- linhas na tela de resultados
local SPAWN_ATTEMPTS = 3 -- tentativas de criar o personagem
local LOADING_LIMIT = 120 -- participante que não termina de carregar em 2 min sai da conta de vivos
local DEFAULT_REASON = "Não resistiu aos perigos da selva"

local initialized = false
local mapInfo = nil
local remotes: { [string]: RemoteEvent } = {}
local MapBuilder = nil
local NPCService = nil

local state = {
	phase = "Loading",
	countdown = nil :: number?,
	message = "Preparando a ilha…" :: string?,
}
local participants: { [number]: Participant } = {}
local participantCount = 0
local expectedUserIds: { number }? = nil
local partyName: string? = nil
local teleportDataRead = false
local introStarted = false
local matchStarted = false -- depois da primeira jogada
local finished = false
local handledReady: { [Player]: boolean } = {}
local spawning: { [Player]: boolean } = {}
local spawnAttempts: { [Player]: number } = {}
local spawnIndex = 0
local teleportRetries: { [Player]: number } = {}

-- Utilitários ---------------------------------------------------------------------------

local function tryRequire(...: string): any
	local current: Instance? = script.Parent
	local path = {}
	for _, name in { ... } do
		table.insert(path, name)
		current = current and current:FindFirstChild(name)
	end
	local label = table.concat(path, ".")
	if not current or not current:IsA("ModuleScript") then
		warn(("[MatchService] Módulo '%s' não encontrado."):format(label))
		return nil
	end
	local ok, result = pcall(require, current)
	if not ok then
		warn(("[MatchService] Erro ao carregar '%s': %s"):format(label, tostring(result)))
		return nil
	end
	return result
end

-- Corta um texto UTF-8 em `maxChars` caracteres sem quebrar acentos.
local function truncate(text: string, maxChars: number): string
	local length = utf8.len(text)
	if not length then
		return ""
	end
	if length <= maxChars then
		return text
	end
	local cut = utf8.offset(text, maxChars + 1)
	return cut and text:sub(1, cut - 1) or text
end

local function aliveCount(): number
	local count = 0
	for _, record in participants do
		if not record.eliminated then
			count += 1
		end
	end
	return count
end

local function buildPayload()
	return {
		phase = state.phase,
		countdown = state.countdown,
		space = BoardService.GetSpace(),
		totalSpaces = GameConfig.BOARD_SPACES,
		alive = aliveCount(),
		total = participantCount,
		message = state.message,
	}
end

local function broadcastState()
	remotes.state:FireAllClients(buildPayload())
end

local function sendStateTo(player: Player)
	if player.Parent then
		remotes.state:FireClient(player, buildPayload())
	end
end

local function setPhase(phase: string, message: string?)
	state.phase = phase
	state.message = message
	state.countdown = nil
	broadcastState()
end

local function readyPlayers(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("ClientReady") then
			table.insert(list, player)
		end
	end
	return list
end

-- TeleportData (enviado pelo lobby) do primeiro jogador: quem é esperado nesta partida.
local function readTeleportData(player: Player)
	if teleportDataRead then
		return
	end
	teleportDataRead = true
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or type(joinData) ~= "table" then
		return
	end
	local data = joinData.TeleportData
	if type(data) ~= "table" then
		return
	end
	if type(data.partyName) == "string" and data.partyName ~= "" then
		partyName = truncate(data.partyName, GameConfig.PARTY_NAME_MAX)
	end
	local list = {}
	if type(data.expectedUserIds) == "table" then
		local seen = 0
		for _, value in data.expectedUserIds do
			seen += 1
			if seen > MAX_EXPECTED then
				break
			end
			if type(value) == "number" and value == value and value > 0 and value % 1 == 0 then
				if not table.find(list, value) then
					table.insert(list, value)
				end
			end
		end
	end
	if #list == 0 and data.mode == "solo" then
		list = { player.UserId }
	end
	if #list > 0 then
		if not table.find(list, player.UserId) then
			table.insert(list, player.UserId)
		end
		expectedUserIds = list
	end
end

-- Participantes ---------------------------------------------------------------------------

local function addParticipant(player: Player): Participant
	local record = participants[player.UserId]
	if record then
		return record
	end
	record = {
		userId = player.UserId,
		name = player.DisplayName,
		eliminated = false,
		spawned = false,
		left = false,
	}
	participants[player.UserId] = record
	participantCount += 1
	return record
end

local checkDefeat: () -> ()

local function eliminate(player: Player, reason: string)
	if player:GetAttribute("Eliminated") then
		return
	end
	player:SetAttribute("Eliminated", true)
	local record = participants[player.UserId]
	if record then
		record.eliminated = true
	end
	remotes.eliminated:FireAllClients(player.UserId, reason)
	remotes.notify:FireAllClients(("%s foi eliminado (%s)."):format(player.DisplayName, reason), "danger")
	broadcastState()
	checkDefeat()
end

-- Quem entrou depois do início: assiste aos outros.
local function makeSpectator(player: Player, reason: string)
	if player:GetAttribute("Eliminated") then
		return
	end
	player:SetAttribute("Eliminated", true)
	player:SetAttribute("LastDamageSource", reason)
	remotes.eliminated:FireClient(player, player.UserId, reason)
	remotes.notify:FireClient(player, "A partida já começou: você vai assistir como espectador.", "info")
end

local function onCharacterDied(player: Player, character: Model)
	if not player:GetAttribute("Eliminated") then
		local source = player:GetAttribute("LastDamageSource")
		local reason = (type(source) == "string" and source ~= "") and source or DEFAULT_REASON
		eliminate(player, reason)
	end
	-- Sem respawn: o corpo some depois de alguns segundos para não pesar.
	task.delay(CORPSE_TIME, function()
		if player.Parent and player.Character == character then
			player.Character = nil
		end
		if character.Parent then
			character:Destroy()
		end
	end)
end

local function nextSpawnCFrame(): CFrame
	local spawns = mapInfo.playerSpawns
	spawnIndex += 1
	if type(spawns) == "table" and #spawns > 0 then
		return spawns[(spawnIndex - 1) % #spawns + 1]
	end
	return mapInfo.startRoom.cframe
end

local spawnCharacter: (Player) -> ()
function spawnCharacter(player: Player)
	local record = participants[player.UserId]
	if not record or record.eliminated or record.spawned or spawning[player] or not player.Parent then
		return
	end
	spawning[player] = true
	-- Personagem R6 com a aparência do jogador (ServerShared/CharacterService). Os spawns do mapa já estão
	-- na altura do HumanoidRootPart; só uma folga pequena.
	local ok, result = pcall(CharacterService.Spawn, player, nextSpawnCFrame() + Vector3.new(0, 0.5, 0))
	spawning[player] = nil
	local character = if ok then result else nil
	if not character or not player.Parent then
		local attempts = (spawnAttempts[player] or 0) + 1
		spawnAttempts[player] = attempts
		warn(
			("[MatchService] Falha ao criar o personagem de %s (tentativa %d): %s"):format(
				player.Name,
				attempts,
				tostring(result)
			)
		)
		if player.Parent and attempts < SPAWN_ATTEMPTS then
			task.delay(2, spawnCharacter, player)
		end
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn(("[MatchService] Personagem de %s sem Humanoid."):format(player.Name))
		return
	end
	record.spawned = true
	humanoid.MaxHealth = GameConfig.PLAYER_MAX_HEALTH
	humanoid.Health = GameConfig.PLAYER_MAX_HEALTH
	player:SetAttribute("LastDamageSource", nil)
	humanoid.Died:Once(function()
		onCharacterDied(player, character)
	end)
	broadcastState()
end

local function onPlayerReady(player: Player)
	if not player.Parent then
		return
	end
	sendStateTo(player)
	if finished then
		return
	end
	local record = participants[player.UserId]
	if not matchStarted then
		-- Antes da primeira jogada qualquer um entra (inclusive quem saiu e voltou).
		if record and record.left then
			record.eliminated = false
			record.left = false
			record.spawned = false
		end
		record = record or addParticipant(player)
	end
	if record and not record.eliminated then
		task.spawn(spawnCharacter, player)
	else
		makeSpectator(player, "Entrou depois do início")
	end
	broadcastState()
end

local function onPlayerAdded(player: Player)
	readTeleportData(player)
	local function check()
		if player:GetAttribute("ClientReady") and not handledReady[player] then
			handledReady[player] = true
			onPlayerReady(player)
		end
	end
	player:GetAttributeChangedSignal("ClientReady"):Connect(check)
	check()
end

local function onPlayerRemoving(player: Player)
	handledReady[player] = nil
	spawning[player] = nil
	spawnAttempts[player] = nil
	teleportRetries[player] = nil
	local record = participants[player.UserId]
	if record and not record.eliminated then
		record.eliminated = true
		record.left = true
		if not finished then
			remotes.eliminated:FireAllClients(player.UserId, "Saiu da partida")
			remotes.notify:FireAllClients(("%s saiu da partida."):format(player.DisplayName), "warning")
		end
	end
	task.defer(function()
		broadcastState()
		checkDefeat()
	end)
end

-- Fim da partida -------------------------------------------------------------------------

-- O lobby é este mesmo place: um teleporte SEM servidor reservado leva para um servidor público,
-- e servidor público sempre roda como lobby (ver Shared/PlaceMode).
local function lobbyPlaceId(): number
	return game.PlaceId
end

local function teleportPlayers(list: { Player }): (boolean, string?)
	local ok, err = pcall(function()
		return TeleportService:TeleportAsync(lobbyPlaceId(), list)
	end)
	if ok then
		return true, nil
	end
	return false, tostring(err)
end

local function returnToLobby()
	for remaining = math.max(math.floor(GameConfig.RETURN_TO_LOBBY_DELAY), 0), 1, -1 do
		state.countdown = remaining
		broadcastState()
		task.wait(1)
	end
	state.countdown = nil

	if lobbyPlaceId() <= 0 or RunService:IsStudio() then
		state.message = "Fim da partida! (sem teleporte no Studio)"
		broadcastState()
		remotes.notify:FireAllClients(
			"Fim da partida! No Studio (ou num place não publicado) não há teleporte de volta ao lobby. "
				.. "Pare o teste para jogar de novo.",
			"info"
		)
		return
	end

	state.message = "Voltando ao lobby…"
	broadcastState()
	for attempt = 1, TELEPORT_ATTEMPTS do
		local list = Players:GetPlayers()
		if #list == 0 then
			return
		end
		local ok, err = teleportPlayers(list)
		if ok then
			return
		end
		warn(("[MatchService] Teleporte para o lobby falhou (tentativa %d): %s"):format(attempt, tostring(err)))
		task.wait(2 * attempt)
	end
	remotes.notify:FireAllClients(
		"Não foi possível voltar ao lobby automaticamente. Saia e entre de novo no jogo.",
		"danger"
	)
end

local function onTeleportFailed(player: Player, result: Enum.TeleportResult, message: string)
	if not finished or not player.Parent then
		return
	end
	local count = (teleportRetries[player] or 0) + 1
	teleportRetries[player] = count
	warn(("[MatchService] Teleporte de %s falhou (%s): %s"):format(player.Name, tostring(result), tostring(message)))
	if count > TELEPORT_PLAYER_RETRIES then
		remotes.notify:FireClient(player, "Não foi possível voltar ao lobby. Saia e entre de novo no jogo.", "danger")
		return
	end
	task.delay(2 * count, function()
		if player.Parent then
			teleportPlayers({ player })
		end
	end)
end

local function endMatch(victory: boolean)
	if finished then
		return
	end
	finished = true
	pcall(BoardService.SetRollingEnabled, false)
	local ok, err = pcall(EventService.StopAll)
	if not ok then
		warn("[MatchService] Erro ao encerrar os eventos: " .. tostring(err))
	end
	-- Trava DEPOIS do StopAll: o cleanup de um evento (ex.: pelicano) chama SetLocked(false).
	pcall(BoardService.SetLocked, true)
	if NPCService and type(NPCService.DespawnAll) == "function" then
		ok, err = pcall(NPCService.DespawnAll)
		if not ok then
			warn("[MatchService] Erro ao remover os NPCs: " .. tostring(err))
		end
	end
	-- Resultados: cutscene com o melhor da partida (todos os clientes) e placar global (DataStore).
	local okResults, results = pcall(MatchStats.Results)
	if not okResults then
		warn("[MatchService] Erro ao calcular os resultados: " .. tostring(results))
		results = {}
	end
	local shown = {}
	local recorded = {}
	for _, entry in results do
		local record = participants[entry.userId]
		if record then
			if #shown < MAX_RESULTS then
				table.insert(shown, entry)
			end
			table.insert(recorded, entry)
		end
	end
	remotes.cutscene:FireAllClients({
		victory = victory,
		boardPosition = BoardService.GetBoardPosition(),
		results = shown,
		bestUserId = shown[1] and shown[1].userId or nil,
		killPoints = MatchStats.KILL_POINTS,
		rollPoints = MatchStats.ROLL_POINTS,
	})
	task.spawn(GlobalStats.RecordMatch, recorded, victory)

	if victory then
		setPhase("Victory", "O tabuleiro foi vencido!")
		SoundUtil.Play("Victory", { Group = "Music", Volume = 0.8 })
		remotes.notify:FireAllClients(("%s: o tabuleiro foi vencido!"):format(GameConfig.GAME_TITLE), "success")
	else
		setPhase("Defeat", "Todos foram eliminados. A selva venceu desta vez…")
		SoundUtil.Play("Defeat", { Group = "Music", Volume = 0.8 })
	end
	task.spawn(returnToLobby)
end

function checkDefeat()
	if finished or not introStarted or participantCount == 0 then
		return
	end
	if aliveCount() > 0 then
		return
	end
	endMatch(false)
end

-- Jogadas ---------------------------------------------------------------------------------

local function openStartDoors()
	if MapBuilder and type(MapBuilder.OpenStartDoors) == "function" then
		local ok, err = pcall(MapBuilder.OpenStartDoors)
		if not ok then
			warn("[MatchService] Erro ao abrir as portas da sala inicial: " .. tostring(err))
		end
	end
	local startRoom = mapInfo.startRoom
	SoundUtil.Play("DoorOpen", {
		Position = startRoom and startRoom.cframe.Position or BoardService.GetBoardPosition(),
		RollOffMaxDistance = 250,
	})
	remotes.notify:FireAllClients("As portas se abriram! Que comece o jogo.", "warning")
end

local function startEvent(eventId: string, position: Vector3)
	if eventId == "" then
		remotes.notify:FireAllClients("O tabuleiro estremece… mas nada acontece (nenhum evento carregado).", "info")
		return
	end
	local ok, err = pcall(EventService.Start, eventId, position)
	if not ok then
		warn(("[MatchService] Erro ao iniciar o evento '%s': %s"):format(eventId, tostring(err)))
	end
end

local function onRolled(result)
	if finished or type(result) ~= "table" then
		return
	end
	broadcastState()
	if result.isFinal then
		endMatch(true)
		return
	end

	local isFirst = result.isFirst == true
	if isFirst and not matchStarted then
		-- Início da partida: quem está no servidor agora participa (mesmo se ainda estiver carregando).
		matchStarted = true
		for _, player in Players:GetPlayers() do
			if not participants[player.UserId] and not player:GetAttribute("Eliminated") then
				addParticipant(player)
				if player:GetAttribute("ClientReady") then
					task.spawn(spawnCharacter, player)
				end
			end
		end
		-- Quem ainda não nasceu tem um tempo limite (senão um cliente travado impediria a derrota).
		task.delay(LOADING_LIMIT, function()
			for userId, record in participants do
				if not record.spawned and not record.eliminated and not finished then
					record.eliminated = true
					local player = Players:GetPlayerByUserId(userId)
					if player then
						player:SetAttribute("LastDamageSource", "Demorou demais para carregar")
						player:SetAttribute("Eliminated", true)
					end
				end
			end
			broadcastState()
			checkDefeat()
		end)
	end

	local eventId = EventService.EventForSpace(result.space)
	local riddle = EventService.GetRiddle(eventId)
	local countdown = isFirst and GameConfig.START_COUNTDOWN or GameConfig.EVENT_WARNING_TIME
	remotes.riddle:FireAllClients({
		text = riddle,
		space = result.space,
		dice = result.dice,
		countdown = countdown,
		isFirst = isFirst,
	})
	BoardService.ShowRiddle(riddle)
	local boardModel = BoardService.GetBoardModel()
	SoundUtil.Play("Drums", {
		Parent = boardModel and boardModel.PrimaryPart or nil,
		RollOffMaxDistance = 150,
		Volume = 0.8,
	})

	if isFirst then
		state.phase = "Countdown"
		state.message = "As portas vão se abrir…"
		for remaining = countdown, 1, -1 do
			state.countdown = remaining
			broadcastState()
			task.wait(1)
			if finished then
				return
			end
		end
		state.countdown = nil
		openStartDoors()
		startEvent(eventId, result.position)
		setPhase("Playing", nil)
	else
		task.wait(countdown)
		if finished then
			return
		end
		startEvent(eventId, result.position)
	end

	if finished then
		return
	end
	BoardService.StartCooldown(GameConfig.ROLL_COOLDOWN)
	BoardService.SetRollingEnabled(true)
	broadcastState()
end

-- Espera os jogadores esperados ficarem prontos (ou o tempo limite).
local function waitForPlayers()
	local started = os.clock()
	local firstReadyAt: number? = nil
	local lastMessage: string? = nil
	while not finished do
		local ready = readyPlayers()
		if #ready > 0 and not firstReadyAt then
			firstReadyAt = os.clock()
		end
		local expected = expectedUserIds
		local message
		if expected then
			local arrived = 0
			for _, userId in expected do
				local player = Players:GetPlayerByUserId(userId)
				if player and player:GetAttribute("ClientReady") then
					arrived += 1
				end
			end
			local elapsed = os.clock() - started
			if #ready > 0 and (arrived >= #expected or elapsed >= GameConfig.WAIT_FOR_PLAYERS_TIMEOUT) then
				break
			end
			local remaining = math.ceil(GameConfig.WAIT_FOR_PLAYERS_TIMEOUT - elapsed)
			if remaining > 0 then
				message = ("Aguardando jogadores (%d/%d)… começa em até %ds"):format(arrived, #expected, remaining)
			else
				message = ("Aguardando jogadores (%d/%d)…"):format(arrived, #expected)
			end
		else
			if firstReadyAt and os.clock() - firstReadyAt >= STUDIO_GRACE then
				break
			end
			message = ("Aguardando jogadores (%d pronto(s))…"):format(#ready)
		end
		if partyName then
			message = ("%s — %s"):format(partyName, message)
		end
		if message ~= lastMessage then
			lastMessage = message
			state.message = message
			broadcastState()
		end
		task.wait(0.25)
	end
end

local function startIntro()
	introStarted = true
	setPhase("Intro", "Pegue o tabuleiro (E) ou chegue perto dele e jogue o dado (T) para começar!")
	BoardService.SetLocked(false)
	BoardService.SetRollingEnabled(true)
	checkDefeat()
end

-- API pública ----------------------------------------------------------------------------

function MatchService.Init(info)
	if initialized then
		return
	end
	initialized = true
	mapInfo = info

	remotes.state = Net.event(Net.Names.Game_State)
	remotes.ready = Net.event(Net.Names.Game_ClientReady)
	remotes.riddle = Net.event(Net.Names.Board_Riddle)
	remotes.eliminated = Net.event(Net.Names.Player_Eliminated)
	remotes.notify = Net.event(Net.Names.Notify)
	remotes.cutscene = Net.event(Net.Names.Game_EndCutscene)

	MatchStats.Init()
	MapBuilder = tryRequire("Map", "MapBuilder")
	NPCService = tryRequire("NPC", "NPCService")

	BoardService.SetLocked(true)
	BoardService.SetRollingEnabled(false)
	BoardService.Rolled:Connect(onRolled)

	remotes.ready.OnServerEvent:Connect(function(player)
		if player:GetAttribute("ClientReady") then
			sendStateTo(player) -- pedido repetido: só reenvia o estado
		else
			player:SetAttribute("ClientReady", true)
		end
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	TeleportService.TeleportInitFailed:Connect(onTeleportFailed)

	setPhase("Loading", "Preparando a ilha…")
	task.spawn(function()
		setPhase("WaitingPlayers", "Aguardando jogadores…")
		waitForPlayers()
		if not finished then
			startIntro()
		end
	end)
end

return MatchService
