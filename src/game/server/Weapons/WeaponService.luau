--!nonstrict
-- Serviço das armas (servidor do jogo).
--   WeaponService.Init(mapInfo)        cria os remotes Weapon_*, liga os handlers e espalha as armas
--   WeaponService.GiveWeapon(player, kind): Tool?
--
-- O cliente só PEDE (Weapon_Fire / Weapon_Melee / Weapon_Throw / Weapon_Reload). Aqui tudo é validado:
-- tipo de cada argumento, Tool marcada com a tag Weapon e criada por este servidor para ESTE jogador,
-- arma na mão (tool.Parent == player.Character), jogador vivo, cadência, munição/cargas, recarga em
-- andamento, origem do tiro perto da cabeça, direção finita e unitária, alvo do arremesso dentro do
-- alcance e um limite de pedidos por segundo. Jogador eliminado perde as armas.
--
-- Submódulos: Definitions (números), ToolFactory (modelos), Inventory (posse e coleta), Combat (ações),
-- Spawner (armas no chão).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Tags = require(ReplicatedStorage.Shared.Tags)

local CombatUtil = require(script.Parent.Parent.CombatUtil)
local Combat = require(script.Parent.Combat)
local Definitions = require(script.Parent.Definitions)
local Inventory = require(script.Parent.Inventory)
local Spawner = require(script.Parent.Spawner)
local ToolFactory = require(script.Parent.ToolFactory)

local WeaponService = {}

local MAX_COORDINATE = 1e6
local ERROR_LOG_INTERVAL = 5 -- no máximo um aviso de erro por jogador a cada 5 s

local initialized = false
local buckets: { [Player]: { tokens: number, last: number } } = {}
local lastErrorLog: { [Player]: number } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}

-- Carrega um módulo irmão de outro dono sem derrubar as armas se ele falhar.
local function safeRequire(parent: Instance, name: string): any
	local module = parent:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		warn(("[WeaponService] Módulo '%s' não encontrado: armas sem esse recurso."):format(name))
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok then
		warn(("[WeaponService] Erro ao carregar '%s': %s"):format(name, tostring(result)))
		return nil
	end
	return result
end

-- Validação -----------------------------------------------------------------------------------

local function isFiniteVector(value: any): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local x, y, z = value.X, value.Y, value.Z
	-- x == x é falso para NaN; o limite também barra ±inf.
	return x == x
		and y == y
		and z == z
		and math.abs(x) < MAX_COORDINATE
		and math.abs(y) < MAX_COORDINATE
		and math.abs(z) < MAX_COORDINATE
end

-- Balde de fichas: cada pedido gasta uma; elas voltam com o tempo.
local function takeToken(player: Player): boolean
	local now = os.clock()
	local bucket = buckets[player]
	if not bucket then
		bucket = { tokens = Definitions.REQUEST_BUDGET, last = now }
		buckets[player] = bucket
	end
	bucket.tokens =
		math.min(Definitions.REQUEST_BUDGET, bucket.tokens + (now - bucket.last) * Definitions.REQUEST_REFILL)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

-- Confere a arma de um pedido. Retorna (estado, definição, personagem) ou nil se algo não bater.
local function resolveTool(player: Player, tool: any, category: string): (any, Definitions.WeaponDef?, Model?)
	if not takeToken(player) then
		return nil, nil, nil
	end
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") or not CollectionService:HasTag(tool, Tags.Weapon) then
		return nil, nil, nil
	end
	local state = ToolFactory.GetState(tool)
	if not state or state.ownerUserId ~= player.UserId then
		return nil, nil, nil
	end
	local character = player.Character
	if not character or tool.Parent ~= character or not CombatUtil.IsPlayerAlive(player) then
		return nil, nil, nil
	end
	local def = Definitions.Get(state.kind)
	if not def or def.category ~= category then
		return nil, nil, nil
	end
	return state, def, character
end

local function cooldownReady(state: any, def: Definitions.WeaponDef): boolean
	return os.clock() - state.lastUse >= def.cooldown * Definitions.COOLDOWN_TOLERANCE
end

-- Handlers ---------------------------------------------------------------------------------------

local function onFire(player: Player, tool: any, origin: any, direction: any)
	local state, def, character = resolveTool(player, tool, "gun")
	if not state or not def or not character then
		return
	end
	if not isFiniteVector(origin) or not isFiniteVector(direction) then
		return
	end
	local magnitude = direction.Magnitude
	if magnitude < 1e-3 then
		return
	end
	local unit = direction / magnitude
	if state.reloading or not cooldownReady(state, def) then
		return
	end
	local head = Combat.GetHeadPosition(character)
	if not head or (origin - head).Magnitude > Definitions.ORIGIN_MAX_DISTANCE then
		return
	end
	if (tonumber(tool:GetAttribute("Ammo")) or 0) <= 0 then
		-- O cliente achou que tinha bala (dessincronizado): recarrega em vez de atirar.
		Combat.StartReload(player, tool, state, def)
		return
	end
	Combat.Fire(player, tool, state, def, origin, unit)
end

local function onMelee(player: Player, tool: any)
	local state, def = resolveTool(player, tool, "melee")
	if not state or not def or not cooldownReady(state, def) then
		return
	end
	Combat.Melee(player, tool, state, def)
end

local function onThrow(player: Player, tool: any, target: any)
	local state, def, character = resolveTool(player, tool, "throw")
	if not state or not def or not character or not isFiniteVector(target) then
		return
	end
	if not cooldownReady(state, def) or (tonumber(tool:GetAttribute("Charges")) or 0) <= 0 then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	if (target - root.Position).Magnitude > def.range + Definitions.THROW_RANGE_TOLERANCE then
		return
	end
	Combat.Throw(player, tool, state, def, target)
end

local function onReload(player: Player, tool: any)
	local state, def = resolveTool(player, tool, "gun")
	if not state or not def then
		return
	end
	Combat.StartReload(player, tool, state, def)
end

-- Erros de um handler (argumentos estranhos) não podem derrubar a conexão nem lotar o Output.
local function guard(label: string, handler: (Player, ...any) -> ())
	return function(player: Player, ...)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			local now = os.clock()
			if now - (lastErrorLog[player] or -math.huge) >= ERROR_LOG_INTERVAL then
				lastErrorLog[player] = now
				warn(("[WeaponService] Erro em %s (%s): %s"):format(label, player.Name, tostring(err)))
			end
		end
	end
end

-- Jogadores -------------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	if playerConnections[player] then
		return
	end
	local connections = {}
	table.insert(
		connections,
		player:GetAttributeChangedSignal("Eliminated"):Connect(function()
			if player:GetAttribute("Eliminated") then
				Inventory.RemoveAll(player)
			end
		end)
	)
	playerConnections[player] = connections
	if player:GetAttribute("Eliminated") then
		Inventory.RemoveAll(player)
	end
end

local function onPlayerRemoving(player: Player)
	buckets[player] = nil
	lastErrorLog[player] = nil
	Spawner.ForgetPlayer(player)
	local connections = playerConnections[player]
	playerConnections[player] = nil
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
	end
end

-- API ----------------------------------------------------------------------------------------------

function WeaponService.Init(mapInfo)
	if initialized then
		return
	end
	initialized = true

	Combat.Init(safeRequire(script.Parent.Parent, "DestructionService"))

	-- Remotes usados pelas armas (existem antes de qualquer cliente pedir).
	Net.event(Net.Names.Fx_Play)
	Net.event(Net.Names.Notify)
	Net.event(Net.Names.Weapon_Fire).OnServerEvent:Connect(guard("Weapon_Fire", onFire))
	Net.event(Net.Names.Weapon_Melee).OnServerEvent:Connect(guard("Weapon_Melee", onMelee))
	Net.event(Net.Names.Weapon_Throw).OnServerEvent:Connect(guard("Weapon_Throw", onThrow))
	Net.event(Net.Names.Weapon_Reload).OnServerEvent:Connect(guard("Weapon_Reload", onReload))

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	local ok, err = pcall(Spawner.Init, type(mapInfo) == "table" and mapInfo or {})
	if not ok then
		warn("[WeaponService] Erro ao espalhar as armas: " .. tostring(err))
	end
end

-- Dá uma arma seguindo as regras de coleta (limite de armas; mesmo tipo = recarrega/soma cargas).
-- Retorna a Tool do jogador desse tipo, ou nil se não foi possível (limite, eliminado, tipo inválido).
function WeaponService.GiveWeapon(player: Player, kind: "Machete" | "Revolver" | "Shotgun" | "Dynamite"): Tool?
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not player.Parent then
		return nil
	end
	if player:GetAttribute("Eliminated") then
		return nil
	end
	local tool, result = Inventory.Give(player, kind)
	if result == "created" or result == "refilled" or result == "full" then
		return tool
	end
	return nil
end

-- Remove todas as armas de um jogador (extra; o serviço já faz isso quando ele é eliminado).
function WeaponService.RemoveWeapons(player: Player)
	if typeof(player) == "Instance" and player:IsA("Player") then
		Inventory.RemoveAll(player)
	end
end

return WeaponService
