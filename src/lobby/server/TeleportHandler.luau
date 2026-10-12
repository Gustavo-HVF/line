--!nonstrict
-- Teleporte do lobby para a PARTIDA, sempre num servidor reservado (só o grupo entra nele).
-- O place é único: o servidor reservado é do MESMO place (game.PlaceId) e, por ser reservado,
-- roda como partida (ver Shared/PlaceMode).
--
--   TeleportHandler.Init()
--   TeleportHandler.TeleportToGame(players, data): (boolean, string?)
--
-- No Studio (ou num place ainda não publicado, PlaceId = 0) o teleporte não é tentado: cada jogador
-- recebe Menu_TeleportStatus("studio", mensagem) explicando como testar a partida.
-- Os jogadores recebem Menu_TeleportStatus("teleporting", ...) enquanto o servidor reserva e teleporta,
-- e Menu_TeleportStatus("failed", ...) com uma mensagem amigável se algo der errado.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

export type TeleportData = {
	mode: string, -- "solo" | "multiplayer"
	partyId: string,
	hostUserId: number,
	expectedUserIds: { number },
	partyName: string,
}

local TeleportHandler = {}

-- Disparado quando o teleporte de um jogador falha de vez: (player: Player, message: string).
TeleportHandler.Failed = Signal.new()

local RESERVE_ATTEMPTS = 3
local TELEPORT_ATTEMPTS = 3
local INIT_FAILED_RETRIES = 2 -- novas tentativas depois de TeleportInitFailed (Failure/Flooded)
local PENDING_TIMEOUT = 45 -- segundos em que um jogador fica marcado como "teleportando"
local MAX_PARTY_NAME_BYTES = 120

TeleportHandler.STUDIO_MESSAGE = "Teleporte não funciona no Studio nem em place não publicado. "
	.. 'Para testar a partida no Studio, troque STUDIO_MODE para "game" em Shared/Config/Places e aperte Play.'

local MESSAGES = {
	reserving = "Reservando um servidor para a partida…",
	teleporting = "Entrando na selva…",
	reserveFailed = "Não foi possível reservar um servidor para a partida. Tente de novo em instantes.",
	teleportFailed = "O teleporte falhou. Verifique sua conexão e tente de novo.",
	alreadyPending = "Você já está sendo levado para uma partida. Aguarde um instante.",
	noPlayers = "Nenhum jogador disponível para teleportar.",
}

local RESULT_MESSAGES = {
	[Enum.TeleportResult.Flooded] = "Muitos pedidos de teleporte ao mesmo tempo. Espere alguns segundos e tente de novo.",
	[Enum.TeleportResult.GameFull] = "O servidor da partida está cheio.",
	[Enum.TeleportResult.GameEnded] = "A partida não está mais disponível. Tente de novo.",
	[Enum.TeleportResult.GameNotFound] = "O servidor da partida não foi encontrado. Tente de novo.",
	[Enum.TeleportResult.Unauthorized] = "Sem permissão para entrar no servidor da partida.",
	[Enum.TeleportResult.Failure] = MESSAGES.teleportFailed,
}

local initialized = false
local statusRemote: RemoteEvent? = nil
local pendingUntil: { [Player]: number } = {}
local initRetries: { [Player]: number } = {}

local function getStatusRemote(): RemoteEvent
	if not statusRemote then
		statusRemote = Net.event(Net.Names.Menu_TeleportStatus)
	end
	return statusRemote :: RemoteEvent
end

local function isInGame(player: any): boolean
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function sendStatus(player: Player, status: string, message: string)
	if isInGame(player) then
		getStatusRemote():FireClient(player, status, message)
	end
end

local function sendStatusAll(list: { Player }, status: string, message: string)
	for _, player in list do
		sendStatus(player, status, message)
	end
end

-- Remove inválidos, repetidos e quem já saiu do servidor.
local function validPlayers(list: any): { Player }
	local result = {}
	if type(list) ~= "table" then
		return result
	end
	for _, player in list do
		if isInGame(player) and not table.find(result, player) then
			table.insert(result, player)
		end
	end
	return result
end

local function release(list: { Player })
	for _, player in list do
		pendingUntil[player] = nil
		initRetries[player] = nil
	end
end

-- Place da partida = este mesmo place.
local function matchPlaceId(): number
	return game.PlaceId
end

-- Teleporte desativado: Studio ou place ainda não publicado.
function TeleportHandler.IsStudioBlocked(): boolean
	return matchPlaceId() <= 0 or RunService:IsStudio()
end

function TeleportHandler.IsPending(player: Player): boolean
	return (pendingUntil[player] or 0) > os.clock()
end

-- Garante um TeleportData bem formado (a partida valida de novo ao ler).
local function buildTeleportData(data: any, list: { Player }): TeleportData
	local source = type(data) == "table" and data or {}
	local expected = {}
	if type(source.expectedUserIds) == "table" then
		for _, userId in source.expectedUserIds do
			if
				type(userId) == "number"
				and userId == userId
				and userId % 1 == 0
				and not table.find(expected, userId)
			then
				table.insert(expected, userId)
			end
		end
	end
	for _, player in list do
		if not table.find(expected, player.UserId) then
			table.insert(expected, player.UserId)
		end
	end
	local partyName = type(source.partyName) == "string" and source.partyName or ""
	if #partyName > MAX_PARTY_NAME_BYTES then
		partyName = string.sub(partyName, 1, MAX_PARTY_NAME_BYTES)
	end
	return {
		mode = source.mode == "multiplayer" and "multiplayer" or "solo",
		partyId = type(source.partyId) == "string" and source.partyId or "",
		hostUserId = type(source.hostUserId) == "number" and source.hostUserId or list[1].UserId,
		expectedUserIds = expected,
		partyName = partyName,
	}
end

-- ReserveServer com algumas tentativas e espera crescente (1 s, 2 s...).
local function reserveServer(): (string?, string?)
	local lastError = nil
	for attempt = 1, RESERVE_ATTEMPTS do
		local ok, accessCode = pcall(function()
			return TeleportService:ReserveServer(matchPlaceId())
		end)
		if ok and type(accessCode) == "string" and accessCode ~= "" then
			return accessCode, nil
		end
		lastError = tostring(accessCode)
		warn(
			("[TeleportHandler] ReserveServer falhou (tentativa %d/%d): %s"):format(
				attempt,
				RESERVE_ATTEMPTS,
				lastError
			)
		)
		if attempt < RESERVE_ATTEMPTS then
			task.wait(2 ^ (attempt - 1))
		end
	end
	return nil, lastError
end

local function teleportWithRetries(list: { Player }, options: TeleportOptions): (boolean, string?)
	local lastError = nil
	for attempt = 1, TELEPORT_ATTEMPTS do
		local current = validPlayers(list)
		if #current == 0 then
			return false, MESSAGES.noPlayers
		end
		local ok, err = pcall(function()
			return TeleportService:TeleportAsync(matchPlaceId(), current, options)
		end)
		if ok then
			return true, nil
		end
		lastError = tostring(err)
		warn(
			("[TeleportHandler] TeleportAsync falhou (tentativa %d/%d): %s"):format(
				attempt,
				TELEPORT_ATTEMPTS,
				lastError
			)
		)
		if attempt < TELEPORT_ATTEMPTS then
			task.wait(2 ^ (attempt - 1))
		end
	end
	return false, lastError
end

-- Teleporta os jogadores juntos para um servidor reservado deste place (que vira a partida).
-- Cede (yield). Retorna (true) quando o pedido de teleporte foi aceito pelo Roblox, ou (false, motivo).
function TeleportHandler.TeleportToGame(players: { Player }, data: TeleportData): (boolean, string?)
	local list = validPlayers(players)
	if #list == 0 then
		return false, MESSAGES.noPlayers
	end

	if TeleportHandler.IsStudioBlocked() then
		sendStatusAll(list, "studio", TeleportHandler.STUDIO_MESSAGE)
		return false, TeleportHandler.STUDIO_MESSAGE
	end

	-- Evita teleporte duplicado: quem já está sendo teleportado fica de fora deste pedido.
	local now = os.clock()
	local ready = {}
	for _, player in list do
		if (pendingUntil[player] or 0) <= now then
			table.insert(ready, player)
		end
	end
	if #ready == 0 then
		return false, MESSAGES.alreadyPending
	end
	for _, player in ready do
		pendingUntil[player] = now + PENDING_TIMEOUT
		initRetries[player] = 0
	end

	local teleportData = buildTeleportData(data, ready)
	sendStatusAll(ready, "teleporting", MESSAGES.reserving)

	local accessCode, reserveError = reserveServer()
	if not accessCode then
		warn("[TeleportHandler] Desistindo de reservar servidor: " .. tostring(reserveError))
		release(ready)
		sendStatusAll(ready, "failed", MESSAGES.reserveFailed)
		return false, MESSAGES.reserveFailed
	end

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	options:SetTeleportData(teleportData)

	sendStatusAll(ready, "teleporting", MESSAGES.teleporting)
	local ok, teleportError = teleportWithRetries(ready, options)
	if not ok then
		warn("[TeleportHandler] Desistindo do teleporte: " .. tostring(teleportError))
		release(ready)
		sendStatusAll(ready, "failed", MESSAGES.teleportFailed)
		return false, MESSAGES.teleportFailed
	end
	return true, nil
end

local function failPlayer(player: Player, message: string)
	pendingUntil[player] = nil
	initRetries[player] = nil
	sendStatus(player, "failed", message)
	TeleportHandler.Failed:Fire(player, message)
end

local function onTeleportInitFailed(
	player: Player,
	result: Enum.TeleportResult,
	errorMessage: string,
	placeId: number,
	options: TeleportOptions?
)
	if result == Enum.TeleportResult.IsTeleporting then
		return -- o jogador já está a caminho
	end
	warn(
		("[TeleportHandler] Teleporte de %s falhou (%s): %s"):format(
			player.Name,
			tostring(result),
			tostring(errorMessage)
		)
	)

	local retries = initRetries[player] or 0
	local retryable = result == Enum.TeleportResult.Failure or result == Enum.TeleportResult.Flooded
	if retryable and options and placeId == matchPlaceId() and retries < INIT_FAILED_RETRIES then
		initRetries[player] = retries + 1
		pendingUntil[player] = os.clock() + PENDING_TIMEOUT
		sendStatus(player, "teleporting", "O teleporte demorou. Tentando de novo…")
		task.spawn(function()
			task.wait(2 * (retries + 1))
			if not isInGame(player) then
				return
			end
			local ok, err = pcall(function()
				return TeleportService:TeleportAsync(placeId, { player }, options)
			end)
			if not ok then
				warn("[TeleportHandler] Nova tentativa falhou: " .. tostring(err))
				failPlayer(player, MESSAGES.teleportFailed)
			end
		end)
		return
	end

	failPlayer(player, RESULT_MESSAGES[result] or MESSAGES.teleportFailed)
end

function TeleportHandler.Init()
	if initialized then
		return
	end
	initialized = true
	getStatusRemote()
	TeleportService.TeleportInitFailed:Connect(onTeleportInitFailed)
	Players.PlayerRemoving:Connect(function(player)
		pendingUntil[player] = nil
		initRetries[player] = nil
	end)
end

return TeleportHandler
