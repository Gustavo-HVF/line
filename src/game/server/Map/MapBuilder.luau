--!nonstrict
-- Constrói o mapa da partida em workspace.Map (somente Parts, nada de Terrain):
--   ilha com praia e oceano, mansão de 2 andares (30 cômodos), labirinto de cerca viva, estufa e jardins.
-- No fim marca workspace:SetAttribute("MapReady", true).
--
-- API (docs/ARQUITETURA.md):
--   MapBuilder.Build(): MapInfo
--   MapBuilder.OpenStartDoors()
--   MapBuilder.GetRegionAt(position: Vector3): Region?

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local Garden = require(script.Parent.Garden)
local Greenhouse = require(script.Parent.Greenhouse)
local Island = require(script.Parent.Island)
local Kit = require(script.Parent.Kit)
local Mansion = require(script.Parent.Mansion)
local Maze = require(script.Parent.Maze)
local StartRoom = require(script.Parent.StartRoom)

local MapBuilder = {}

export type Region = { name: string, cframe: CFrame, size: Vector3, floor: number }

export type MapInfo = {
	islandCenter: Vector3,
	islandRadius: number,
	groundY: number,
	waterLevelY: number,
	startRoom: { cframe: CFrame, size: Vector3 },
	boardSpawn: CFrame, -- em cima da mesa na sala inicial (Y = superfície do tampo)
	playerSpawns: { CFrame }, -- dentro da sala inicial (8), na altura do HumanoidRootPart, olhando para a mesa
	weaponSpawns: { BasePart }, -- Parts com tag WeaponSpawn
	regions: { Region },
	mapFolder: Folder, -- workspace.Map
}

local MIN_WEAPON_SPAWNS = 60

local mapInfo: MapInfo? = nil
local building = false
local startState = nil
-- Regiões com volume pré-calculado (para escolher a menor quando várias contêm o ponto).
local regionIndex: { { region: Region, volume: number, half: Vector3 } } = {}

local function indexRegions(regions: { Region })
	table.clear(regionIndex)
	for _, region in regions do
		table.insert(regionIndex, {
			region = region,
			volume = region.size.X * region.size.Y * region.size.Z,
			half = region.size / 2,
		})
	end
end

-- Lê as regiões das Parts de workspace.Map.Regions (se o Build ainda não rodou neste servidor).
local function ensureRegions()
	if #regionIndex > 0 then
		return
	end
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Regions")
	if not folder then
		return
	end
	local regions = {}
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") then
			local name = part:GetAttribute("RegionName")
			table.insert(regions, {
				name = (type(name) == "string") and name or part.Name,
				cframe = part.CFrame,
				size = part.Size,
				floor = tonumber(part:GetAttribute("Floor")) or 0,
			})
		end
	end
	indexRegions(regions)
end

-- Executa uma etapa da construção; um erro numa etapa não derruba as outras.
local function step(name: string, fn: () -> any): any
	local ok, result = xpcall(fn, debug.traceback)
	if not ok then
		warn(("[MapBuilder] Falha ao construir %s: %s"):format(name, tostring(result)))
		return nil
	end
	return result
end

-- Dados de emergência da sala inicial (só usados se a mansão falhar ao ser construída).
local function fallbackStart()
	local center = GameConfig.MANSION_CENTER + Vector3.new(0, 0.2, 0)
	local spawns = {}
	for i = 1, 8 do
		local angle = math.rad(22.5 + (i - 1) * 45)
		local position = center + Vector3.new(math.cos(angle) * 9, 3, math.sin(angle) * 9)
		table.insert(spawns, CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)))
	end
	return {
		startRoom = { cframe = CFrame.new(center + Vector3.new(0, 7.5, 0)), size = Vector3.new(27, 15, 27) },
		boardSpawn = CFrame.new(center + Vector3.new(0, 3.5, 0)),
		playerSpawns = spawns,
		doors = {},
		sealParts = {},
		opened = true,
	}
end

local function buildAll(): MapInfo
	local started = os.clock()
	workspace:SetAttribute("MapReady", false)

	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	local mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	mapFolder.Parent = workspace
	local regionsFolder = Instance.new("Folder")
	regionsFolder.Name = "Regions"
	regionsFolder.Parent = mapFolder
	local spawnsFolder = Instance.new("Folder")
	spawnsFolder.Name = "WeaponSpawns"
	spawnsFolder.Parent = mapFolder
	local markersFolder = Instance.new("Folder")
	markersFolder.Name = "Marcadores"
	markersFolder.Parent = mapFolder

	local ctx = Kit.new(mapFolder, regionsFolder, spawnsFolder, markersFolder)

	local islandInfo = step("a ilha", function()
		return Island.Build(ctx)
	end)
	local mansionInfo = step("a mansão", function()
		return Mansion.Build(ctx)
	end)
	local mazeInfo = step("o labirinto", function()
		return Maze.Build(ctx)
	end)
	local greenhouseInfo = step("a estufa", function()
		return Greenhouse.Build(ctx)
	end)
	if mansionInfo and mazeInfo and greenhouseInfo then
		step("os jardins", function()
			Garden.Build(ctx, {
				mansion = mansionInfo,
				maze = mazeInfo,
				greenhouse = greenhouseInfo,
				island = islandInfo,
			})
		end)
	end

	startState = (mansionInfo and mansionInfo.start) or fallbackStart()
	if #ctx.weaponSpawns < MIN_WEAPON_SPAWNS then
		warn(
			("[MapBuilder] Só %d pontos de arma foram criados (mínimo esperado: %d)."):format(
				#ctx.weaponSpawns,
				MIN_WEAPON_SPAWNS
			)
		)
	end

	indexRegions(ctx.regions)
	local info: MapInfo = {
		islandCenter = GameConfig.ISLAND_CENTER,
		islandRadius = GameConfig.ISLAND_RADIUS,
		groundY = GameConfig.GROUND_Y,
		waterLevelY = GameConfig.WATER_LEVEL_Y,
		startRoom = startState.startRoom,
		boardSpawn = startState.boardSpawn,
		playerSpawns = startState.playerSpawns,
		weaponSpawns = ctx.weaponSpawns,
		regions = ctx.regions,
		mapFolder = mapFolder,
	}
	mapInfo = info
	workspace:SetAttribute("MapReady", true)
	print(
		("[MapBuilder] Mapa pronto: %d parts, %d regiões, %d pontos de arma em %.2f s."):format(
			ctx.partCount,
			#ctx.regions,
			#ctx.weaponSpawns,
			os.clock() - started
		)
	)
	return info
end

function MapBuilder.Build(): MapInfo
	if mapInfo then
		return mapInfo
	end
	if building then
		-- Outra thread já está construindo: espera ela terminar.
		while building do
			task.wait(0.1)
		end
		if mapInfo then
			return mapInfo
		end
		error("[MapBuilder] A construção do mapa falhou em outra chamada.")
	end
	building = true
	local ok, result = xpcall(buildAll, debug.traceback)
	building = false
	if not ok then
		error(result, 0)
	end
	return result
end

-- Abre (tween) as portas da sala inicial e libera a destruição das paredes dela. Pode ser chamada mais
-- de uma vez (só a primeira tem efeito) e não cede.
function MapBuilder.OpenStartDoors()
	if not startState and not workspace:FindFirstChild("Map") then
		warn("[MapBuilder] OpenStartDoors chamado antes do mapa existir.")
		return
	end
	StartRoom.OpenDoors(startState)
end

-- Região nomeada que contém o ponto (a de menor volume, se houver mais de uma), ou nil.
function MapBuilder.GetRegionAt(position: Vector3): Region?
	if typeof(position) ~= "Vector3" then
		return nil
	end
	ensureRegions()
	local best, bestVolume = nil, math.huge
	for _, entry in regionIndex do
		local localPoint = entry.region.cframe:PointToObjectSpace(position)
		local half = entry.half
		if
			math.abs(localPoint.X) <= half.X
			and math.abs(localPoint.Y) <= half.Y
			and math.abs(localPoint.Z) <= half.Z
			and entry.volume < bestVolume
		then
			best, bestVolume = entry.region, entry.volume
		end
	end
	return best
end

return MapBuilder
