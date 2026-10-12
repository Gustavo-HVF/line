--!nonstrict
-- Ponto de entrada do servidor da PARTIDA.
-- Ordem: personagens manuais, sons, iluminação, configurações, remotes, mapa e serviços.
-- Cada serviço inicia em pcall: um módulo quebrado não derruba os outros. Se o MapBuilder falhar,
-- o erro aparece bem visível no Output e um mapa reserva simples é criado para o jogo continuar testável.
-- O place é único: este script só roda no servidor reservado criado pelo lobby (ver Shared/PlaceMode).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

if require(ReplicatedStorage.Shared.PlaceMode).Get() ~= "game" then
	return -- servidor público: quem roda aqui é o LobbyMain
end

-- Personagens são criados pelo MatchService (sem respawn automático). Desligado antes de qualquer
-- espera, para ninguém nascer sozinho enquanto o mapa é construído.
Players.CharacterAutoLoads = false

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local PartBuilder = require(ReplicatedStorage.Shared.Util.PartBuilder)
local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local Tags = require(ReplicatedStorage.Shared.Tags)

local GameFolder = script.Parent

-- require seguro: devolve (módulo, nil) ou (nil, mensagem de erro).
local function tryRequire(parent: Instance, ...: string): (any, string?)
	local current: Instance? = parent
	local path = {}
	for _, name in { ... } do
		table.insert(path, name)
		current = current and current:FindFirstChild(name)
	end
	local label = table.concat(path, ".")
	if not current or not current:IsA("ModuleScript") then
		return nil, ("módulo '%s' não encontrado"):format(label)
	end
	local ok, result = pcall(require, current)
	if not ok then
		return nil, ("erro ao carregar '%s': %s"):format(label, tostring(result))
	end
	return result, nil
end

-- 1. Sons ---------------------------------------------------------------------------------
SoundUtil.EnsureGroups()

-- 2. Iluminação: selva no fim da tarde. Depois daqui, sombras são assunto do cliente (GraphicsApplier).
do
	Lighting.ClockTime = 17
	Lighting.GeographicLatitude = 15
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(46, 52, 40)
	Lighting.OutdoorAmbient = Color3.fromRGB(118, 124, 98)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 212, 158)
	Lighting.ColorShift_Bottom = Color3.fromRGB(40, 60, 30)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.35
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.2

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(176, 200, 150)
	atmosphere.Decay = Color3.fromRGB(88, 116, 74)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting

	local grade = Lighting:FindFirstChild("CorDaSelva") or Instance.new("ColorCorrectionEffect")
	grade.Name = "CorDaSelva"
	grade.TintColor = Color3.fromRGB(255, 248, 232)
	grade.Saturation = 0.08
	grade.Contrast = 0.06
	grade.Parent = Lighting
end

-- 3. Configurações dos jogadores (Settings_Get / Settings_Save).
do
	local SettingsStore, err = tryRequire(ServerScriptService, "ServerShared", "SettingsStore")
	if SettingsStore and type(SettingsStore.Init) == "function" then
		local ok, initErr = pcall(SettingsStore.Init)
		if not ok then
			warn("[GameMain] Erro ao iniciar o SettingsStore: " .. tostring(initErr))
		end
	else
		warn("[GameMain] SettingsStore indisponível: " .. tostring(err))
	end
end

-- Personagens R6: o MatchService cria cada um; o Init só liga o estado de movimento (escalada) replicado.
do
	local CharacterService, err = tryRequire(ServerScriptService, "ServerShared", "CharacterService")
	if CharacterService and type(CharacterService.Init) == "function" then
		local ok, initErr = pcall(CharacterService.Init)
		if not ok then
			warn("[GameMain] Erro ao iniciar o CharacterService: " .. tostring(initErr))
		end
	else
		warn("[GameMain] CharacterService indisponível: " .. tostring(err))
	end
end

-- 4. Remotes usados pelo fluxo da partida (existem antes de qualquer cliente pedir).
for _, name in
	{
		Net.Names.Game_ClientReady,
		Net.Names.Game_State,
		Net.Names.Board_Status,
		Net.Names.Board_RollRequest,
		Net.Names.Board_DropRequest,
		Net.Names.Board_Riddle,
		Net.Names.Event_Started,
		Net.Names.Event_Ended,
		Net.Names.Player_Eliminated,
		Net.Names.Fx_Play,
		Net.Names.Notify,
		Net.Names.Game_EndCutscene,
	}
do
	Net.event(name)
end

-- "Pronto" vira um atributo no Player: os serviços reagem a ele, independentemente da ordem de Init.
Net.event(Net.Names.Game_ClientReady).OnServerEvent:Connect(function(player)
	if not player:GetAttribute("ClientReady") then
		player:SetAttribute("ClientReady", true)
	end
end)

-- 5. Mapa ----------------------------------------------------------------------------------

-- Mapa reserva: plataforma, mesa com o tabuleiro e pontos de nascimento (só se o MapBuilder falhar).
local function buildFallbackMap(reason: string)
	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Map"
	local regions = Instance.new("Folder")
	regions.Name = "Regions"
	regions.Parent = folder

	local center = GameConfig.ISLAND_CENTER
	local groundY = GameConfig.GROUND_Y
	local size = 400

	PartBuilder.part({
		Name = "PlataformaReserva",
		Size = Vector3.new(size, 4, size),
		CFrame = CFrame.new(center.X, groundY - 2, center.Z),
		Color = Color3.fromRGB(74, 120, 56),
		Material = Enum.Material.Grass,
		Tags = { Tags.Indestructible },
		Parent = folder,
	})
	PartBuilder.part({
		Name = "OceanoReserva",
		Size = Vector3.new(2000, 1, 2000),
		CFrame = CFrame.new(center.X, GameConfig.WATER_LEVEL_Y - 0.5, center.Z),
		Color = Color3.fromRGB(40, 110, 140),
		Material = Enum.Material.Glass,
		Transparency = 0.3,
		CanCollide = false,
		CastShadow = false,
		Tags = { Tags.Water, Tags.Indestructible },
		Parent = folder,
	})
	local tableTop = PartBuilder.part({
		Name = "MesaReserva",
		Size = Vector3.new(7, 3, 5),
		CFrame = CFrame.new(center.X, groundY + 1.5, center.Z),
		Color = Color3.fromRGB(92, 60, 32),
		Material = Enum.Material.Wood,
		Tags = { Tags.Indestructible },
		Parent = folder,
	})
	local region = PartBuilder.part({
		Name = "RegiaoReserva",
		Size = Vector3.new(size, 40, size),
		CFrame = CFrame.new(center.X, groundY + 20, center.Z),
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		Attributes = { RegionName = "Clareira", Floor = 0 },
		Parent = regions,
	})
	region.CanQuery = false -- só depois de CanCollide = false

	local spawns = {}
	for index = 1, 6 do
		local angle = (index / 6) * math.pi * 2
		local position = Vector3.new(center.X + math.cos(angle) * 12, groundY, center.Z + math.sin(angle) * 12)
		table.insert(spawns, CFrame.lookAt(position, Vector3.new(center.X, groundY, center.Z)))
	end

	folder.Parent = workspace
	workspace:SetAttribute("MapError", reason)
	workspace:SetAttribute("MapReady", true)

	return {
		islandCenter = center,
		islandRadius = size / 2 - 10,
		groundY = groundY,
		waterLevelY = GameConfig.WATER_LEVEL_Y,
		startRoom = { cframe = CFrame.new(center.X, groundY + 6, center.Z), size = Vector3.new(60, 12, 60) },
		boardSpawn = CFrame.new(tableTop.Position + Vector3.new(0, tableTop.Size.Y / 2, 0)),
		playerSpawns = spawns,
		weaponSpawns = {},
		regions = {},
		mapFolder = folder,
	}
end

-- Garante todos os campos do MapInfo (com valores padrão onde faltar).
local function normalizeMapInfo(info)
	local result = table.clone(info)
	if typeof(result.islandCenter) ~= "Vector3" then
		result.islandCenter = GameConfig.ISLAND_CENTER
	end
	if type(result.islandRadius) ~= "number" then
		result.islandRadius = GameConfig.ISLAND_RADIUS
	end
	if type(result.groundY) ~= "number" then
		result.groundY = GameConfig.GROUND_Y
	end
	if type(result.waterLevelY) ~= "number" then
		result.waterLevelY = GameConfig.WATER_LEVEL_Y
	end
	if type(result.startRoom) ~= "table" or typeof(result.startRoom.cframe) ~= "CFrame" then
		result.startRoom = {
			cframe = CFrame.new(GameConfig.MANSION_CENTER + Vector3.new(0, 6, 0)),
			size = Vector3.new(40, 12, 40),
		}
	end
	if typeof(result.boardSpawn) ~= "CFrame" then
		result.boardSpawn = result.startRoom.cframe
	end
	local spawns = {}
	if type(result.playerSpawns) == "table" then
		for _, spawnCFrame in result.playerSpawns do
			if typeof(spawnCFrame) == "CFrame" then
				table.insert(spawns, spawnCFrame)
			end
		end
	end
	if #spawns == 0 then
		local roomCFrame = result.startRoom.cframe
		local radius = 6
		if typeof(result.startRoom.size) == "Vector3" then
			radius = math.clamp(math.min(result.startRoom.size.X, result.startRoom.size.Z) / 3, 4, 14)
		end
		for index = 1, 6 do
			local angle = (index / 6) * math.pi * 2
			table.insert(spawns, roomCFrame * CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
		end
		warn("[GameMain] MapInfo sem playerSpawns; usando pontos ao redor da sala inicial.")
	end
	result.playerSpawns = spawns
	if type(result.weaponSpawns) ~= "table" then
		result.weaponSpawns = {}
	end
	if type(result.regions) ~= "table" then
		result.regions = {}
	end
	if typeof(result.mapFolder) ~= "Instance" then
		result.mapFolder = workspace:FindFirstChild("Map")
	end
	return result
end

local mapInfo = nil
do
	local MapBuilder, loadError = tryRequire(GameFolder, "Map", "MapBuilder")
	local failure = loadError
	if MapBuilder and type(MapBuilder.Build) == "function" then
		local ok, result = pcall(MapBuilder.Build)
		if ok and type(result) == "table" then
			mapInfo = result
		else
			failure = ok and "MapBuilder.Build não devolveu um MapInfo" or tostring(result)
		end
	elseif MapBuilder then
		failure = "MapBuilder não tem a função Build"
	end

	if not mapInfo then
		local message = tostring(failure)
		warn(
			"\n==================== ERRO AO CONSTRUIR O MAPA ====================\n"
				.. "[GameMain] "
				.. message
				.. "\nUm mapa reserva simples será usado para o jogo continuar testável."
				.. "\nCorrija o erro em Game/Map/MapBuilder e rode de novo."
				.. "\n================================================================="
		)
		mapInfo = buildFallbackMap(message)
	end
end
mapInfo = normalizeMapInfo(mapInfo)
if not workspace:GetAttribute("MapReady") then
	workspace:SetAttribute("MapReady", true)
end

-- 6. Serviços (cada um em pcall) ----------------------------------------------------------

local function initService(label: string, path: { string }, ...: any)
	local module, err = tryRequire(GameFolder, table.unpack(path))
	if not module then
		warn(("[GameMain] %s não foi carregado: %s"):format(label, tostring(err)))
		return
	end
	if type(module.Init) ~= "function" then
		warn(("[GameMain] %s não tem a função Init."):format(label))
		return
	end
	local args = table.pack(...)
	local ok, initErr = pcall(function()
		module.Init(table.unpack(args, 1, args.n))
	end)
	if not ok then
		warn(("[GameMain] Erro ao iniciar %s: %s"):format(label, tostring(initErr)))
	end
end

initService("DestructionService", { "DestructionService" })
initService("NPCService", { "NPC", "NPCService" })
initService("WeaponService", { "Weapons", "WeaponService" }, mapInfo)
initService("BoardService", { "BoardService" }, mapInfo)
initService("EventService", { "EventService" }, mapInfo)
initService("BoundaryService", { "BoundaryService" }, mapInfo)
initService("MatchService", { "MatchService" }, mapInfo)

print(("[GameMain] %s: servidor da partida pronto."):format(GameConfig.GAME_TITLE))
