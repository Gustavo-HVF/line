--!nonstrict
-- Decide se ESTE servidor é o lobby ou a partida (o jogo tem um único place, ver Config/Places).
--
--   PlaceMode.Get(): "lobby" | "game"
--     servidor: calcula na primeira chamada e publica em ReplicatedStorage:GetAttribute("PlaceMode");
--     cliente: espera o servidor publicar (cede).
--   PlaceMode.IsReservedServer(): boolean   -- só faz sentido no servidor
--
-- Regra: servidor reservado (PrivateServerId ~= "" e sem dono) = partida; qualquer outro = lobby.
-- Servidores VIP (com dono) também viram lobby. No Studio vale Places.STUDIO_MODE.
-- Os scripts de entrada (LobbyMain, GameMain, MainMenu, GameClient, WeaponClient) chamam Get() logo
-- no começo e saem na hora se o modo não for o deles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Places = require(script.Parent.Config.Places)

local ATTRIBUTE = "PlaceMode"
local CLIENT_WARN_AFTER = 15 -- segundos esperando o servidor até avisar no console

local PlaceMode = {}

local cached: string? = nil

local function isValid(value: any): boolean
	return value == "lobby" or value == "game"
end

function PlaceMode.IsReservedServer(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

local function computeServerMode(): string
	if RunService:IsStudio() then
		return if Places.STUDIO_MODE == "game" then "game" else "lobby"
	end
	return if PlaceMode.IsReservedServer() then "game" else "lobby"
end

function PlaceMode.Get(): string
	if cached then
		return cached
	end

	if RunService:IsServer() then
		local mode = computeServerMode()
		cached = mode
		ReplicatedStorage:SetAttribute(ATTRIBUTE, mode)
		print(
			("[PlaceMode] Este servidor é %s (PlaceId %d, reservado: %s)."):format(
				if mode == "game" then "a PARTIDA" else "o LOBBY",
				game.PlaceId,
				tostring(PlaceMode.IsReservedServer())
			)
		)
		return mode
	end

	local started = os.clock()
	local warned = false
	local value = ReplicatedStorage:GetAttribute(ATTRIBUTE)
	while not isValid(value) do
		if not warned and os.clock() - started > CLIENT_WARN_AFTER then
			warned = true
			warn("[PlaceMode] O servidor ainda não informou se é lobby ou partida; continuando a esperar…")
		end
		task.wait(0.1)
		value = ReplicatedStorage:GetAttribute(ATTRIBUTE)
	end
	cached = value
	return value
end

return PlaceMode
