--!nonstrict
-- Armas espalhadas pelo mapa (servidor).
--   * No Init coloca GameConfig.WEAPON_SPAWN_COUNT armas em pontos WeaponSpawn: primeiro TODOS os pontos
--     dentro da sala inicial (Facão e Revólver alternados, garantidos), depois o resto espalhado por área
--     (rodízio entre cômodos/setores), com pelo menos uma de cada tipo.
--   * Cada arma no chão é um modelo de exibição ancorado (não é Tool) com luz fraca e um ProximityPrompt
--     "Pegar <nome>". A coleta segue as regras do Inventory (limite, recarga, soma de cargas).
--   * Ao ser coletada, o ponto fica livre e, depois de WEAPON_RESPAWN_TIME, uma nova arma aparece num
--     ponto livre aleatório.
-- Os modelos ficam em workspace.Map.ArmasNoChao (o cliente os anima de perto: ver Weapons/PickupFx).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Tags = require(ReplicatedStorage.Shared.Tags)

local CombatUtil = require(script.Parent.Parent.CombatUtil)
local GroundUtil = require(script.Parent.Parent.EventHelpers.GroundUtil)
local Definitions = require(script.Parent.Definitions)
local Inventory = require(script.Parent.Inventory)
local ToolFactory = require(script.Parent.ToolFactory)

local Spawner = {}

Spawner.FOLDER_NAME = "ArmasNoChao"

local GLOW_COLOR = Color3.fromRGB(255, 214, 140)
local START_ROOM_MARGIN = 1 -- folga da caixa da sala inicial (pontos rente às paredes)

type Entry = {
	kind: string,
	spot: any,
	model: Model,
	taken: boolean,
}

type Spot = {
	position: Vector3,
	part: BasePart?, -- nil nos pontos extras criados aqui
	area: string,
	inStartRoom: boolean,
	entry: Entry?,
}

local initialized = false
local spots: { Spot } = {}
local folder: Instance? = nil
local activeCount = 0
local targetCount = 0
local random = Random.new()
local lastPickup: { [Player]: number } = {}
local notifyRemote: RemoteEvent? = nil

-- Utilitários ---------------------------------------------------------------------------------

local function notify(player: Player, text: string, kind: string)
	if notifyRemote and player.Parent then
		notifyRemote:FireClient(player, text, kind)
	end
end

local function shuffle(list: { any })
	for index = #list, 2, -1 do
		local other = random:NextInteger(1, index)
		list[index], list[other] = list[other], list[index]
	end
end

local function isInsideBox(position: Vector3, cframe: CFrame, size: Vector3, margin: number): boolean
	local localPosition = cframe:PointToObjectSpace(position)
	return math.abs(localPosition.X) <= size.X / 2 + margin
		and math.abs(localPosition.Y) <= size.Y / 2 + margin
		and math.abs(localPosition.Z) <= size.Z / 2 + margin
end

local function spotUsable(spot: Spot): boolean
	if spot.entry then
		return false
	end
	local part = spot.part
	return part == nil or part.Parent ~= nil
end

-- "do Revólver" / "da Espingarda"
local function ofWeapon(def: Definitions.WeaponDef): string
	return (def.article == "a" and "da " or "do ") .. def.displayName
end

-- Exibição ------------------------------------------------------------------------------------

local onTriggered: (Entry, Player) -> ()

local function place(spot: Spot, kind: string): boolean
	if not spotUsable(spot) or not folder then
		return false
	end
	local def = Definitions.Get(kind)
	if not def then
		return false
	end
	local target = CFrame.new(spot.position) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
	local model, root = ToolFactory.BuildDisplay(kind, target)
	if not model or not root then
		return false
	end

	-- Brilho leve para a arma chamar a atenção (sem sombra: barato no celular).
	local light = Instance.new("PointLight")
	light.Name = "Brilho"
	light.Color = GLOW_COLOR
	light.Brightness = 0.9
	light.Range = 7
	light.Shadows = false
	light.Parent = root

	local attachment = Instance.new("Attachment")
	attachment.Name = "Coleta"
	attachment.Position = root.CFrame:PointToObjectSpace(spot.position + Vector3.new(0, 0.5, 0))
	attachment.Parent = root

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PegarArma"
	prompt.ActionText = "Pegar " .. def.displayName
	prompt.ObjectText = def.description
	prompt.HoldDuration = Definitions.PICKUP_HOLD
	prompt.MaxActivationDistance = Definitions.PICKUP_PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = attachment

	model:SetAttribute("WeaponKind", kind)
	model.Parent = folder

	local entry: Entry = { kind = kind, spot = spot, model = model, taken = false }
	spot.entry = entry
	activeCount += 1
	-- A conexão morre junto com o prompt quando o modelo é destruído.
	prompt.Triggered:Connect(function(player)
		onTriggered(entry, player)
	end)
	return true
end

local function respawnOne()
	if activeCount >= targetCount then
		return
	end
	local free = {}
	for _, spot in spots do
		if spotUsable(spot) then
			table.insert(free, spot)
		end
	end
	if #free > 0 then
		local spot = free[random:NextInteger(1, #free)]
		if place(spot, Definitions.RandomKind(random)) then
			return
		end
	end
	task.delay(Definitions.RESPAWN_RETRY, respawnOne)
end

local function take(entry: Entry)
	entry.taken = true
	if entry.spot.entry == entry then
		entry.spot.entry = nil
	end
	activeCount = math.max(activeCount - 1, 0)
	entry.model:Destroy()
	task.delay(GameConfig.WEAPON_RESPAWN_TIME, respawnOne)
end

-- Coleta ---------------------------------------------------------------------------------------

function onTriggered(entry: Entry, player: Player)
	if entry.taken or not entry.model.Parent then
		return
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not CombatUtil.IsPlayerAlive(player) then
		return
	end
	local now = os.clock()
	if now - (lastPickup[player] or 0) < Definitions.PICKUP_DEBOUNCE then
		return
	end
	lastPickup[player] = now

	-- O prompt é do cliente: a distância é conferida aqui.
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - entry.spot.position).Magnitude > Definitions.PICKUP_DISTANCE then
		return
	end

	local def = Definitions.Get(entry.kind)
	if not def then
		return
	end
	local tool, result = Inventory.Give(player, entry.kind)
	if result == "created" then
		notify(player, ("Você pegou %s!"):format(Definitions.WithArticle(def)), "success")
	elseif result == "refilled" and tool then
		if def.category == "throw" then
			local charges = tonumber(tool:GetAttribute("Charges")) or 0
			notify(player, ("Mais %s! Agora você tem %d cargas."):format(def.displayName, charges), "success")
		else
			notify(player, ("Munição %s recarregada!"):format(ofWeapon(def)), "success")
		end
	elseif result == "full" then
		-- Nada mudaria: a arma continua no chão para outra pessoa.
		if def.category == "melee" then
			notify(
				player,
				("Você já tem %s %s."):format(def.article == "a" and "uma" or "um", def.displayName),
				"info"
			)
		elseif def.category == "throw" then
			notify(
				player,
				("Você já carrega o máximo %s (%d cargas)."):format(ofWeapon(def), def.maxCharges or 0),
				"info"
			)
		else
			notify(
				player,
				("%s %s já está com a munição cheia."):format(
					def.article == "a" and "Sua" or "Seu",
					def.displayName
				),
				"info"
			)
		end
		return
	elseif result == "limit" then
		notify(
			player,
			("Você já carrega %d armas, o máximo. Use a dinamite para abrir espaço."):format(
				Definitions.MAX_WEAPONS_PER_PLAYER
			),
			"warning"
		)
		return
	else
		return
	end
	take(entry)
end

-- Distribuição inicial ------------------------------------------------------------------------------

-- Escolhe `count` pontos em rodízio por área (um cômodo de cada vez), para espalhar as armas.
local function pickSpread(candidates: { Spot }, count: number): { Spot }
	local groups: { [string]: { Spot } } = {}
	local order: { string } = {}
	for _, spot in candidates do
		local group = groups[spot.area]
		if not group then
			group = {}
			groups[spot.area] = group
			table.insert(order, spot.area)
		end
		table.insert(group, spot)
	end
	for _, group in groups do
		shuffle(group)
	end
	shuffle(order)

	local picked = {}
	local round = 1
	while #picked < count do
		local added = false
		for _, area in order do
			local spot = groups[area][round]
			if spot then
				table.insert(picked, spot)
				added = true
				if #picked >= count then
					break
				end
			end
		end
		if not added then
			break
		end
		round += 1
	end
	return picked
end

-- Lista de tipos com variedade: pelo menos 1 de cada (2 de cada se couber bastante), o resto sorteado.
local function buildKinds(count: number): { string }
	local kinds = {}
	local minimum = if count >= Definitions.MAX_WEAPONS_PER_PLAYER * #Definitions.ORDER then 2 else 1
	for _ = 1, minimum do
		for _, kind in Definitions.ORDER do
			if #kinds < count then
				table.insert(kinds, kind)
			end
		end
	end
	while #kinds < count do
		table.insert(kinds, Definitions.RandomKind(random))
	end
	shuffle(kinds)
	return kinds
end

-- Mapa sem pontos na sala inicial (ex.: mapa reserva): cria dois pontos no chão da sala.
local function createStartRoomSpots(startRoom): { Spot }
	local created = {}
	local cframe, size = startRoom.cframe, startRoom.size
	for _, offset in { Vector2.new(-0.3, 0.3), Vector2.new(0.3, -0.3) } do
		local probe = cframe * Vector3.new(size.X * offset.X, 0, size.Z * offset.Y)
		local ground = GroundUtil.FindGround(probe, size.Y + 6, 0)
		local floorY = if ground then ground.Y else probe.Y - size.Y / 2
		local spot: Spot = {
			position = Vector3.new(probe.X, floorY + 1.5, probe.Z),
			part = nil,
			area = "SalaInicial",
			inStartRoom = true,
			entry = nil,
		}
		table.insert(created, spot)
	end
	return created
end

local function collectSpots(mapInfo)
	local seen: { [BasePart]: boolean } = {}
	local function add(part: any)
		if typeof(part) ~= "Instance" or not part:IsA("BasePart") or seen[part] then
			return
		end
		seen[part] = true
		local area = part:GetAttribute("Area")
		table.insert(spots, {
			position = part.Position,
			part = part,
			area = if type(area) == "string" and area ~= "" then area else "?",
			inStartRoom = false,
			entry = nil,
		})
	end
	if type(mapInfo.weaponSpawns) == "table" then
		for _, part in mapInfo.weaponSpawns do
			add(part)
		end
	end
	if #spots == 0 then
		for _, part in CollectionService:GetTagged(Tags.WeaponSpawn) do
			add(part)
		end
	end

	local startRoom = mapInfo.startRoom
	local hasRoom = type(startRoom) == "table"
		and typeof(startRoom.cframe) == "CFrame"
		and typeof(startRoom.size) == "Vector3"
	local startCount = 0
	if hasRoom then
		for _, spot in spots do
			if isInsideBox(spot.position, startRoom.cframe, startRoom.size, START_ROOM_MARGIN) then
				spot.inStartRoom = true
				startCount += 1
			end
		end
		if startCount == 0 then
			for _, spot in createStartRoomSpots(startRoom) do
				table.insert(spots, spot)
			end
		end
	end
end

local function distribute()
	local startSpots, otherSpots = {}, {}
	for _, spot in spots do
		table.insert(if spot.inStartRoom then startSpots else otherSpots, spot)
	end

	-- 1. Sala inicial: garantida (mesmo que passe do total), Facão e Revólver alternados.
	local startKinds = Definitions.START_ROOM_KINDS
	for index, spot in startSpots do
		place(spot, startKinds[(index - 1) % #startKinds + 1])
	end

	-- 2. Resto do mapa.
	local remaining = math.max(targetCount - activeCount, 0)
	local picked = pickSpread(otherSpots, remaining)
	local kinds = buildKinds(#picked)
	for index, spot in picked do
		place(spot, kinds[index])
	end
	targetCount = math.max(targetCount, activeCount)
end

-- API ----------------------------------------------------------------------------------------------

function Spawner.Init(mapInfo)
	if initialized then
		return
	end
	initialized = true
	notifyRemote = Net.event(Net.Names.Notify)

	local parent = (typeof(mapInfo.mapFolder) == "Instance" and mapInfo.mapFolder)
		or workspace:FindFirstChild("Map")
		or workspace
	local existing = parent:FindFirstChild(Spawner.FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
	local created = Instance.new("Folder")
	created.Name = Spawner.FOLDER_NAME
	created.Parent = parent
	folder = created

	collectSpots(mapInfo)
	targetCount = math.min(GameConfig.WEAPON_SPAWN_COUNT, #spots)
	distribute()
	if #spots == 0 then
		warn("[Weapons] Nenhum ponto de arma no mapa: nenhuma arma foi espalhada.")
	end
end

function Spawner.ForgetPlayer(player: Player)
	lastPickup[player] = nil
end

-- Quantas armas estão no chão agora (para depuração).
function Spawner.CountActive(): number
	return activeCount
end

return Spawner
