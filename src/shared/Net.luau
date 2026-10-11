--!nonstrict
-- Acesso centralizado aos RemoteEvents / RemoteFunctions.
-- No servidor, o remote é criado se ainda não existir; no cliente, espera ele aparecer.
-- Sempre use os nomes de Net.Names para evitar erros de digitação.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local FOLDER_NAME = "Remotes"

local Net = {}

Net.Names = {
	-- Configurações (lobby e jogo)
	Settings_Get = "Settings_Get", -- RemoteFunction: () -> Settings
	Settings_Save = "Settings_Save", -- C->S: (settings)

	-- Menu / Lobby
	Menu_RequestSolo = "Menu_RequestSolo", -- C->S: ()
	Menu_TeleportStatus = "Menu_TeleportStatus", -- S->C: (status: "teleporting"|"failed"|"studio", message: string)
	Hub_Enter = "Hub_Enter", -- C->S: () leva o personagem para o hub multiplayer
	Hub_Leave = "Hub_Leave", -- C->S: () volta para o menu
	Party_Create = "Party_Create", -- C->S: ({name: string, privacy: "public"|"friends", maxPlayers: number})
	Party_Join = "Party_Join", -- C->S: (partyId: string)
	Party_Leave = "Party_Leave", -- C->S: ()
	Party_Start = "Party_Start", -- C->S: () somente o dono
	Party_Update = "Party_Update", -- S->C: (PartyListPayload)
	Party_GetList = "Party_GetList", -- RemoteFunction: () -> PartyListPayload

	-- Jogo
	Game_ClientReady = "Game_ClientReady", -- C->S: () carregamento/pré-carregamento terminou
	Game_State = "Game_State", -- S->C: (GameStatePayload)
	Board_Status = "Board_Status", -- S->C: (BoardStatusPayload)
	Board_RollRequest = "Board_RollRequest", -- C->S: ()
	Board_DropRequest = "Board_DropRequest", -- C->S: () o carregador solta o tabuleiro
	Board_Riddle = "Board_Riddle", -- S->C: (RiddlePayload)
	Event_Started = "Event_Started", -- S->C: (EventInfoPayload)
	Event_Ended = "Event_Ended", -- S->C: (eventInstanceId: string)
	Player_Eliminated = "Player_Eliminated", -- S->C: (userId: number, reason: string)
	Fx_Play = "Fx_Play", -- S->C (RemoteEvent): (kind: string, params: table) — ver docs/ARQUITETURA.md
	Weapon_Fire = "Weapon_Fire", -- C->S: (tool: Tool, origin: Vector3, direction: Vector3)
	Weapon_Melee = "Weapon_Melee", -- C->S: (tool: Tool)
	Weapon_Throw = "Weapon_Throw", -- C->S: (tool: Tool, target: Vector3)
	Weapon_Reload = "Weapon_Reload", -- C->S: (tool: Tool)
	Notify = "Notify", -- S->C: (text: string, kind: "info"|"warning"|"danger"|"success"?)
}

local function getFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if folder then
		return folder
	end
	if IS_SERVER then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

local function get(name: string, className: string): Instance
	assert(type(name) == "string" and name ~= "", "Net: nome de remote inválido")
	local folder = getFolder()
	local remote = folder:FindFirstChild(name)
	if remote then
		return remote
	end
	if IS_SERVER then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	remote = folder:WaitForChild(name, 10)
	if not remote then
		warn(("[Net] Aguardando o remote '%s' ser criado pelo servidor..."):format(name))
		remote = folder:WaitForChild(name)
	end
	return remote
end

function Net.event(name: string): RemoteEvent
	return get(name, "RemoteEvent") :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	return get(name, "RemoteFunction") :: RemoteFunction
end

function Net.unreliable(name: string): UnreliableRemoteEvent
	return get(name, "UnreliableRemoteEvent") :: UnreliableRemoteEvent
end

return Net
