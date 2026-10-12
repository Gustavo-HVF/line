--!nonstrict
-- Hub multiplayer do lobby: entrar/sair do hub, salas (criar, entrar, sair, iniciar) e o pedido de partida solo.
--
-- Cada jogador recebe em Party_Update SOMENTE as salas que pode ver: as públicas e as "só amigos" cujo dono é
-- amigo dele (a sala dele aparece sempre). Party_GetList devolve o mesmo formato (PartyListPayload).
-- Todos os remotes têm limite de 1 pedido a cada 0,5 s por jogador (por remote).

local HttpService = game:GetService("HttpService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)

local TeleportHandler = require(script.Parent.TeleportHandler)

local PartyService = {}

export type PartySummary = {
	id: string,
	name: string,
	hostUserId: number,
	hostName: string,
	privacy: string,
	maxPlayers: number,
	members: { { userId: number, name: string } },
}

export type PartyListPayload = { parties: { PartySummary }, myPartyId: string? }

type Party = {
	id: string,
	name: string,
	host: Player,
	privacy: string,
	maxPlayers: number,
	members: { Player },
	createdAt: number,
	startingUntil: number, -- os.clock() até quando a sala está "iniciando" (travada)
}

local RATE_LIMIT = 0.5
local FRIEND_CACHE_TTL = 120
local FRIEND_FAIL_TTL = 15
local START_LOCK_TIME = 30
local RAW_NAME_MAX_BYTES = 200
local MAX_PARTY_ID_LENGTH = 64
local SPAWN_SPREAD = 6
local ROOT_HEIGHT = 3.5 -- altura do HumanoidRootPart acima do marcador (um pouco acima do chão)
local MENU_RECOVER_DISTANCE = 60
local COLLISION_GROUP = "LobbyPlayers"

local initialized = false
local remotes: { [string]: any } = {}

local parties: { [string]: Party } = {}
local partyOf: { [Player]: string } = {}
local inHub: { [Player]: boolean } = {}
local busy: { [Player]: boolean } = {} -- criando/entrando (operações que cedem)
local lastCall: { [Player]: { [string]: number } } = {}
local payloadVersion: { [Player]: number } = {}
local lastPayload: { [Player]: PartyListPayload } = {}
local characterConnections: { [Player]: { RBXScriptConnection } } = {}

local friendCache: { [string]: { value: boolean, expires: number } } = {}
local friendPending: { [string]: { thread } } = {}

local random = Random.new()
local collisionGroupReady = false
local broadcastQueued = false

-- Utilidades ---------------------------------------------------------------------------------------

local function isInGame(player: Player): boolean
	return player.Parent == Players
end

local function allow(player: Player, key: string): boolean
	local now = os.clock()
	local calls = lastCall[player]
	if not calls then
		calls = {}
		lastCall[player] = calls
	end
	local last = calls[key]
	if last and now - last < RATE_LIMIT then
		return false
	end
	calls[key] = now
	return true
end

local function notify(player: Player, text: string, kind: string?)
	if isInGame(player) then
		remotes.Notify:FireClient(player, text, kind or "info")
	end
end

local function isStarting(party: Party): boolean
	return party.startingUntil > os.clock()
end

-- Corta uma string em no máximo `maxChars` caracteres UTF-8 (nil se o texto não for UTF-8 válido).
-- Um caractere cortado ao meio no fim (a caixa de texto do cliente limita por bytes) é descartado.
local function truncateUtf8(text: string, maxChars: number): string?
	local length, invalidAt = utf8.len(text)
	if not length and invalidAt then
		text = string.sub(text, 1, invalidAt - 1)
		length = utf8.len(text)
	end
	if not length then
		return nil
	end
	if length <= maxChars then
		return text
	end
	local cut = utf8.offset(text, maxChars + 1)
	return cut and string.sub(text, 1, cut - 1) or text
end

local function cleanName(raw: string): string
	local text = string.gsub(raw, "%c", " ")
	text = string.gsub(text, "%s+", " ")
	text = string.match(text, "^%s*(.-)%s*$") or ""
	return truncateUtf8(text, GameConfig.PARTY_NAME_MAX) or ""
end

local function defaultPartyName(player: Player): string
	local name = ("Sala de %s"):format(player.DisplayName)
	return truncateUtf8(name, GameConfig.PARTY_NAME_MAX) or "Sala"
end

-- Filtra o nome com o filtro de texto do Roblox (obrigatório para texto visível a outros jogadores).
local function filterPartyName(player: Player, name: string): string
	if name == "" then
		return defaultPartyName(player)
	end
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(name, player.UserId, Enum.TextFilterContext.PublicChat)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(filtered) ~= "string" then
		warn("[PartyService] Falha ao filtrar o nome da sala: " .. tostring(filtered))
		return defaultPartyName(player)
	end
	local cleaned = cleanName(filtered)
	if cleaned == "" then
		return defaultPartyName(player)
	end
	return cleaned
end

-- Amizade (com cache por par e sem consultas repetidas em paralelo) ---------------------------------

local function pairKey(a: number, b: number): string
	if a < b then
		return ("%d:%d"):format(a, b)
	end
	return ("%d:%d"):format(b, a)
end

local function queryFriendship(player: Player, otherUserId: number): (boolean, boolean)
	local ok, result = pcall(function()
		return player:IsFriendsWithAsync(otherUserId)
	end)
	if ok then
		return true, result == true
	end
	-- Versões antigas da engine só têm IsFriendsWith.
	if type(result) == "string" and string.find(result, "not a valid member", 1, true) then
		local legacyOk, legacyResult = pcall(function()
			return (player :: any):IsFriendsWith(otherUserId)
		end)
		if legacyOk then
			return true, legacyResult == true
		end
	end
	warn("[PartyService] Não foi possível consultar amizade: " .. tostring(result))
	return false, false
end

local function areFriends(a: Player, b: Player): boolean
	if a == b then
		return true
	end
	local key = pairKey(a.UserId, b.UserId)
	local entry = friendCache[key]
	if entry and entry.expires > os.clock() then
		return entry.value
	end
	local waiting = friendPending[key]
	if waiting then
		table.insert(waiting, coroutine.running())
		return coroutine.yield()
	end
	waiting = {}
	friendPending[key] = waiting
	local ok, value = queryFriendship(a, b.UserId)
	friendCache[key] = { value = value, expires = os.clock() + (ok and FRIEND_CACHE_TTL or FRIEND_FAIL_TTL) }
	friendPending[key] = nil
	for _, thread in waiting do
		task.spawn(thread, value)
	end
	return value
end

local function forgetFriendships(userId: number)
	local prefix = tostring(userId) .. ":"
	local suffix = ":" .. tostring(userId)
	for key in friendCache do
		if string.sub(key, 1, #prefix) == prefix or string.sub(key, -#suffix) == suffix then
			friendCache[key] = nil
		end
	end
end

-- Lista de salas ------------------------------------------------------------------------------------

local function summarize(party: Party): PartySummary
	local members = {}
	for _, member in party.members do
		table.insert(members, { userId = member.UserId, name = member.DisplayName })
	end
	return {
		id = party.id,
		name = party.name,
		hostUserId = party.host.UserId,
		hostName = party.host.DisplayName,
		privacy = party.privacy,
		maxPlayers = party.maxPlayers,
		members = members,
	}
end

local function canSee(viewer: Player, party: Party): boolean
	if partyOf[viewer] == party.id then
		return true
	end
	if isStarting(party) then
		return false
	end
	if party.privacy == "public" then
		return true
	end
	return areFriends(viewer, party.host)
end

-- Cede quando precisa consultar amizades.
local function buildPayload(viewer: Player): PartyListPayload
	local snapshot = {}
	for _, party in parties do
		table.insert(snapshot, party)
	end
	local visible = {}
	for _, party in snapshot do
		if parties[party.id] == party and canSee(viewer, party) then
			table.insert(visible, party)
		end
	end
	local myPartyId = partyOf[viewer]
	local list = {}
	for _, party in visible do
		-- a sala pode ter sumido enquanto as amizades eram consultadas
		if parties[party.id] == party and #party.members > 0 then
			table.insert(list, party)
		end
	end
	table.sort(list, function(a, b)
		if (a.id == myPartyId) ~= (b.id == myPartyId) then
			return a.id == myPartyId
		end
		local aFull = #a.members >= a.maxPlayers
		local bFull = #b.members >= b.maxPlayers
		if aFull ~= bFull then
			return not aFull
		end
		if #a.members ~= #b.members then
			return #a.members > #b.members
		end
		return a.createdAt < b.createdAt
	end)
	local summaries = {}
	for _, party in list do
		table.insert(summaries, summarize(party))
	end
	return { parties = summaries, myPartyId = myPartyId }
end

local function sendUpdate(player: Player)
	local version = (payloadVersion[player] or 0) + 1
	payloadVersion[player] = version
	task.spawn(function()
		local ok, payload = pcall(buildPayload, player)
		if not ok then
			warn("[PartyService] Erro ao montar a lista de salas: " .. tostring(payload))
			return
		end
		-- descarta resultados velhos (outra atualização começou depois) e jogadores que saíram
		if payloadVersion[player] ~= version or not isInGame(player) then
			return
		end
		lastPayload[player] = payload
		remotes.Party_Update:FireClient(player, payload)
	end)
end

-- Agrupa várias mudanças no mesmo frame em um único envio.
local function scheduleBroadcast()
	if broadcastQueued then
		return
	end
	broadcastQueued = true
	task.defer(function()
		broadcastQueued = false
		for player in inHub do
			if isInGame(player) then
				sendUpdate(player)
			end
		end
	end)
end

-- Personagem e marcadores ---------------------------------------------------------------------------

local function getMarker(name: string): BasePart?
	local markers = workspace:FindFirstChild("LobbyMarkers")
	local marker = markers and markers:FindFirstChild(name)
	if marker and marker:IsA("BasePart") then
		return marker
	end
	return nil
end

local function spawnCFrame(markerName: string, fallback: Vector3): CFrame
	local marker = getMarker(markerName)
	local base = marker and marker.CFrame or CFrame.new(fallback)
	local offset = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)) * SPAWN_SPREAD
	return CFrame.new(base.Position + offset + Vector3.new(0, ROOT_HEIGHT, 0)) * base.Rotation
end

local function moveCharacter(player: Player, target: CFrame)
	local character = player.Character
	if not character or not character.Parent then
		return
	end
	if workspace.StreamingEnabled then
		-- carrega a área de destino no cliente antes de mover (senão o personagem pode cair)
		pcall(function()
			player:RequestStreamAroundAsync(target.Position, 3)
		end)
		if player.Character ~= character or not character.Parent then
			return
		end
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Sit then
		humanoid.Sit = false
	end
	character:PivotTo(target)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

local function moveToHub(player: Player)
	moveCharacter(player, spawnCFrame("HubSpawn", GameConfig.HUB_ORIGIN + Vector3.new(0, 0.5, 34)))
end

local function moveToMenu(player: Player)
	moveCharacter(player, spawnCFrame("MenuSpawn", GameConfig.MENU_AREA_ORIGIN + Vector3.new(0, 0, 30)))
end

local function setupCollisionGroup()
	local ok, err = pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(COLLISION_GROUP) then
			PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
		end
		PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)
	end)
	collisionGroupReady = ok
	if not ok then
		warn("[PartyService] Não foi possível criar o grupo de colisão do lobby: " .. tostring(err))
	end
end

local function applyCollisionGroup(instance: Instance)
	if collisionGroupReady and instance:IsA("BasePart") then
		instance.CollisionGroup = COLLISION_GROUP
	end
end

local function disconnectCharacter(player: Player)
	local list = characterConnections[player]
	if list then
		for _, connection in list do
			connection:Disconnect()
		end
	end
	characterConnections[player] = nil
end

local function onCharacterAdded(player: Player, character: Model)
	disconnectCharacter(player)
	-- jogadores do lobby atravessam uns aos outros (ninguém empurra ninguém no hub)
	for _, descendant in character:GetDescendants() do
		applyCollisionGroup(descendant)
	end
	characterConnections[player] = { character.DescendantAdded:Connect(applyCollisionGroup) }

	task.spawn(function()
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not root or player.Character ~= character then
			return
		end
		task.wait(0.15) -- deixa o posicionamento padrão do spawn acontecer antes
		if player.Character ~= character or not character.Parent then
			return
		end
		if inHub[player] then
			moveToHub(player)
		else
			-- o personagem pode ter nascido antes do cenário existir; leva para o cubículo do menu
			local menuSpawn = getMarker("MenuSpawn")
			if
				menuSpawn
				and root:IsA("BasePart")
				and (root.Position - menuSpawn.Position).Magnitude > MENU_RECOVER_DISTANCE
			then
				moveToMenu(player)
			end
		end
	end)
end

-- Salas -----------------------------------------------------------------------------------------------

local function removeFromParty(player: Player, silent: boolean?)
	local partyId = partyOf[player]
	if not partyId then
		return
	end
	partyOf[player] = nil
	local party = parties[partyId]
	if not party then
		scheduleBroadcast()
		return
	end
	local index = table.find(party.members, player)
	if index then
		table.remove(party.members, index)
	end

	if #party.members == 0 then
		parties[partyId] = nil
	else
		-- quem sai durante o teleporte não precisa gerar avisos
		local quiet = silent or isStarting(party)
		if party.host == player then
			party.host = party.members[1]
			if not quiet then
				notify(party.host, "Agora você é o dono da sala.", "info")
			end
		end
		if not quiet then
			for _, member in party.members do
				notify(member, ("%s saiu da sala."):format(player.DisplayName), "warning")
			end
		end
	end
	scheduleBroadcast()
end

local function onPartyCreate(player: Player, data: any)
	if not allow(player, "Party_Create") or busy[player] then
		return
	end
	if type(data) ~= "table" then
		return
	end
	if not inHub[player] then
		notify(player, "Entre no hub multiplayer para criar uma sala.", "warning")
		return
	end
	if partyOf[player] then
		notify(player, "Você já está em uma sala. Saia dela para criar outra.", "warning")
		return
	end

	local privacy = data.privacy
	if privacy ~= "public" and privacy ~= "friends" then
		notify(player, "Privacidade inválida.", "danger")
		return
	end
	local maxPlayers = data.maxPlayers
	if
		type(maxPlayers) ~= "number"
		or maxPlayers ~= maxPlayers
		or maxPlayers % 1 ~= 0
		or maxPlayers < 1
		or maxPlayers > GameConfig.MAX_PARTY_SIZE
	then
		notify(player, ("O máximo de jogadores deve ser de 1 a %d."):format(GameConfig.MAX_PARTY_SIZE), "danger")
		return
	end
	local rawName = data.name
	if rawName == nil then
		rawName = ""
	end
	if type(rawName) ~= "string" or #rawName > RAW_NAME_MAX_BYTES then
		notify(player, "Nome de sala inválido.", "danger")
		return
	end

	busy[player] = true
	local name = filterPartyName(player, cleanName(rawName))
	busy[player] = nil

	-- o filtro cede: confere tudo de novo
	if not isInGame(player) or not inHub[player] or partyOf[player] then
		return
	end

	local party: Party = {
		id = HttpService:GenerateGUID(false),
		name = name,
		host = player,
		privacy = privacy,
		maxPlayers = maxPlayers,
		members = { player },
		createdAt = os.clock(),
		startingUntil = 0,
	}
	parties[party.id] = party
	partyOf[player] = party.id
	notify(player, ('Sala "%s" criada!'):format(name), "success")
	scheduleBroadcast()
end

local function joinChecks(player: Player, party: Party): boolean
	if isStarting(party) then
		notify(player, "Essa sala já está iniciando a partida.", "warning")
		return false
	end
	if #party.members >= party.maxPlayers then
		notify(player, "Essa sala está cheia.", "warning")
		return false
	end
	return true
end

local function onPartyJoin(player: Player, partyId: any)
	if not allow(player, "Party_Join") or busy[player] then
		return
	end
	if type(partyId) ~= "string" or #partyId == 0 or #partyId > MAX_PARTY_ID_LENGTH then
		return
	end
	if not inHub[player] then
		notify(player, "Entre no hub multiplayer para entrar em uma sala.", "warning")
		return
	end
	local party = parties[partyId]
	if not party then
		notify(player, "Essa sala não existe mais.", "warning")
		scheduleBroadcast()
		return
	end
	if partyOf[player] == partyId then
		return
	end
	if not joinChecks(player, party) then
		return
	end

	if party.privacy == "friends" then
		busy[player] = true
		local checkedHost = party.host
		local friends = areFriends(player, checkedHost)
		-- o dono pode ter mudado enquanto consultávamos: confere de novo uma vez
		if parties[partyId] == party and party.host ~= checkedHost and isInGame(player) then
			friends = areFriends(player, party.host)
		end
		busy[player] = nil
		if not isInGame(player) or not inHub[player] then
			return
		end
		if parties[partyId] ~= party then
			notify(player, "Essa sala não existe mais.", "warning")
			return
		end
		if not friends then
			notify(player, "Essa sala é só para amigos do dono.", "warning")
			return
		end
		if partyOf[player] == partyId or not joinChecks(player, party) then
			return
		end
	end

	-- trocar de sala: sai da anterior primeiro
	if partyOf[player] then
		removeFromParty(player)
	end
	for _, member in party.members do
		notify(member, ("%s entrou na sala."):format(player.DisplayName), "info")
	end
	table.insert(party.members, player)
	partyOf[player] = partyId
	notify(player, ('Você entrou na sala "%s".'):format(party.name), "success")
	scheduleBroadcast()
end

local function onPartyLeave(player: Player)
	if not allow(player, "Party_Leave") then
		return
	end
	if partyOf[player] then
		removeFromParty(player)
		sendUpdate(player)
	end
end

local function onPartyStart(player: Player)
	if not allow(player, "Party_Start") then
		return
	end
	local partyId = partyOf[player]
	local party = partyId and parties[partyId]
	if not party then
		notify(player, "Você não está em uma sala.", "warning")
		return
	end
	if party.host ~= player then
		notify(player, "Só o dono da sala pode iniciar a partida.", "warning")
		return
	end
	if isStarting(party) then
		return
	end

	local members = {}
	local userIds = {}
	for _, member in party.members do
		if isInGame(member) then
			table.insert(members, member)
			table.insert(userIds, member.UserId)
		end
	end
	if #members == 0 then
		return
	end

	party.startingUntil = os.clock() + START_LOCK_TIME
	scheduleBroadcast()

	local ok = TeleportHandler.TeleportToGame(members, {
		mode = "multiplayer",
		partyId = party.id,
		hostUserId = player.UserId,
		expectedUserIds = userIds,
		partyName = party.name,
	})
	if ok then
		return -- os membros saem do servidor; PlayerRemoving limpa a sala
	end

	party.startingUntil = 0
	if parties[party.id] == party and not TeleportHandler.IsStudioBlocked() then
		notify(party.host, "A partida não começou. A sala continua aberta: tente iniciar de novo.", "warning")
	end
	scheduleBroadcast()
end

-- O teleporte de alguém falhou depois de aceito: destrava a sala para o dono tentar de novo.
local function onTeleportFailed(player: Player)
	local partyId = partyOf[player]
	local party = partyId and parties[partyId]
	if not party or not isStarting(party) then
		return
	end
	party.startingUntil = 0
	if party.host ~= player then
		notify(party.host, ("O teleporte de %s falhou. Tente iniciar de novo."):format(player.DisplayName), "warning")
	end
	scheduleBroadcast()
end

-- Hub e menu --------------------------------------------------------------------------------------------

local function onHubEnter(player: Player)
	if not allow(player, "Hub_Enter") then
		return
	end
	local wasInHub = inHub[player] == true
	inHub[player] = true
	sendUpdate(player)
	if not wasInHub then
		moveToHub(player)
	end
end

local function onHubLeave(player: Player)
	if not allow(player, "Hub_Leave") then
		return
	end
	if not inHub[player] then
		return
	end
	removeFromParty(player)
	inHub[player] = nil
	moveToMenu(player)
end

local function onRequestSolo(player: Player)
	if not allow(player, "Menu_RequestSolo") then
		return
	end
	if partyOf[player] then
		remotes.Menu_TeleportStatus:FireClient(player, "failed", "Saia da sala multiplayer antes de jogar solo.")
		return
	end
	if TeleportHandler.IsPending(player) then
		return
	end
	TeleportHandler.TeleportToGame({ player }, {
		mode = "solo",
		partyId = "solo_" .. HttpService:GenerateGUID(false),
		hostUserId = player.UserId,
		expectedUserIds = { player.UserId },
		partyName = "",
	})
end

local function onGetList(player: Player): PartyListPayload
	if not allow(player, "Party_GetList") then
		local cached = lastPayload[player]
		return { parties = cached and cached.parties or {}, myPartyId = partyOf[player] }
	end
	local ok, payload = pcall(buildPayload, player)
	if ok then
		if isInGame(player) then
			lastPayload[player] = payload
		end
		return payload
	end
	warn("[PartyService] Erro em Party_GetList: " .. tostring(payload))
	return { parties = {}, myPartyId = partyOf[player] }
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	removeFromParty(player)
	inHub[player] = nil
	busy[player] = nil
	lastCall[player] = nil
	payloadVersion[player] = nil
	lastPayload[player] = nil
	disconnectCharacter(player)
	forgetFriendships(player.UserId)
end

-- API ------------------------------------------------------------------------------------------------------

function PartyService.IsInHub(player: Player): boolean
	return inHub[player] == true
end

function PartyService.GetPartyId(player: Player): string?
	return partyOf[player]
end

function PartyService.Init()
	if initialized then
		return
	end
	initialized = true

	for _, name in
		{
			"Hub_Enter",
			"Hub_Leave",
			"Party_Create",
			"Party_Join",
			"Party_Leave",
			"Party_Start",
			"Party_Update",
			"Menu_RequestSolo",
			"Menu_TeleportStatus",
			"Notify",
		}
	do
		remotes[name] = Net.event(Net.Names[name])
	end
	remotes.Party_GetList = Net.func(Net.Names.Party_GetList)

	setupCollisionGroup()

	remotes.Hub_Enter.OnServerEvent:Connect(onHubEnter)
	remotes.Hub_Leave.OnServerEvent:Connect(onHubLeave)
	remotes.Party_Create.OnServerEvent:Connect(onPartyCreate)
	remotes.Party_Join.OnServerEvent:Connect(onPartyJoin)
	remotes.Party_Leave.OnServerEvent:Connect(onPartyLeave)
	remotes.Party_Start.OnServerEvent:Connect(onPartyStart)
	remotes.Menu_RequestSolo.OnServerEvent:Connect(onRequestSolo)
	remotes.Party_GetList.OnServerInvoke = onGetList

	TeleportHandler.Failed:Connect(onTeleportFailed)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PartyService
