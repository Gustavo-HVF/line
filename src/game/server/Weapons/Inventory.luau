--!nonstrict
-- Armas que cada jogador carrega (Backpack + personagem) e as regras de coleta:
--   * no máximo Definitions.MAX_WEAPONS_PER_PLAYER armas;
--   * pegar um tipo que já tem recarrega a munição (armas de fogo) ou soma cargas (dinamite);
--   * senão, cria a Tool na Backpack.
-- Também cancela a recarga quando a arma sai da mão e remove as armas de quem foi eliminado.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage.Shared.Tags)

local Definitions = require(script.Parent.Definitions)
local ToolFactory = require(script.Parent.ToolFactory)

local Inventory = {}

-- Resultado de uma tentativa de dar arma (usado nas mensagens ao jogador).
export type GiveResult = "created" | "refilled" | "full" | "limit" | "invalid"

-- Consulta ------------------------------------------------------------------------------------

local function isOwnedWeapon(instance: Instance, player: Player): boolean
	if not instance:IsA("Tool") or not CollectionService:HasTag(instance, Tags.Weapon) then
		return false
	end
	local state = ToolFactory.GetState(instance)
	return state ~= nil and state.ownerUserId == player.UserId
end

-- Todas as armas do jogador (as da Backpack e a que está na mão).
function Inventory.GetWeapons(player: Player): { Tool }
	local list = {}
	local containers = { player:FindFirstChildOfClass("Backpack"), player.Character }
	for _, container in containers do
		if container then
			for _, child in container:GetChildren() do
				if isOwnedWeapon(child, player) then
					table.insert(list, child :: Tool)
				end
			end
		end
	end
	return list
end

function Inventory.FindByKind(player: Player, kind: string): Tool?
	for _, tool in Inventory.GetWeapons(player) do
		if tool:GetAttribute("WeaponKind") == kind then
			return tool
		end
	end
	return nil
end

-- Recarga -------------------------------------------------------------------------------------

-- Interrompe uma recarga em andamento (a munição não muda).
function Inventory.CancelReload(tool: Tool)
	local state = ToolFactory.GetState(tool)
	if not state or not state.reloading then
		return
	end
	state.reloading = false
	state.reloadToken += 1
	tool:SetAttribute("Reloading", false)
end

-- Enche a munição / soma cargas de uma arma que o jogador já tem. Retorna false se nada mudaria.
function Inventory.Refill(tool: Tool, def: Definitions.WeaponDef): boolean
	if def.category == "gun" then
		local ammo = tonumber(tool:GetAttribute("Ammo")) or 0
		local maxAmmo = def.maxAmmo or 0
		if ammo >= maxAmmo and not tool:GetAttribute("Reloading") then
			return false
		end
		Inventory.CancelReload(tool)
		tool:SetAttribute("Ammo", maxAmmo)
		return true
	elseif def.category == "throw" then
		local charges = tonumber(tool:GetAttribute("Charges")) or 0
		local maxCharges = def.maxCharges or def.charges or 1
		if charges >= maxCharges then
			return false
		end
		tool:SetAttribute("Charges", math.min(charges + (def.charges or 1), maxCharges))
		return true
	end
	-- Corpo a corpo não tem munição: um segundo facão não muda nada.
	return false
end

-- Criação ---------------------------------------------------------------------------------------

local function watchTool(tool: Tool, player: Player)
	local state = ToolFactory.GetState(tool)
	if not state then
		return
	end
	-- Guardou a arma (ou ela saiu do personagem) no meio da recarga: a recarga é cancelada.
	table.insert(
		state.connections,
		tool:GetPropertyChangedSignal("Parent"):Connect(function()
			if state.reloading and (player.Character == nil or tool.Parent ~= player.Character) then
				Inventory.CancelReload(tool)
			end
		end)
	)
end

-- Dá uma arma ao jogador seguindo as regras. Retorna a Tool afetada (nova ou recarregada) e o resultado.
function Inventory.Give(player: Player, kind: string): (Tool?, GiveResult)
	local def = Definitions.Get(kind)
	if not def or not player.Parent then
		return nil, "invalid"
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return nil, "invalid"
	end

	local existing = Inventory.FindByKind(player, kind)
	if existing then
		if Inventory.Refill(existing, def) then
			return existing, "refilled"
		end
		return existing, "full"
	end

	if #Inventory.GetWeapons(player) >= Definitions.MAX_WEAPONS_PER_PLAYER then
		return nil, "limit"
	end

	local tool = ToolFactory.CreateTool(kind, player)
	if not tool then
		return nil, "invalid"
	end
	watchTool(tool, player)
	tool.Parent = backpack
	return tool, "created"
end

-- Remove todas as armas do jogador (eliminado ou fim de jogo).
function Inventory.RemoveAll(player: Player)
	for _, tool in Inventory.GetWeapons(player) do
		tool:Destroy()
	end
	-- Ferramentas marcadas como arma sem registro (não deveriam existir) também saem.
	local containers = { player:FindFirstChildOfClass("Backpack"), player.Character }
	for _, container in containers do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and CollectionService:HasTag(child, Tags.Weapon) then
					child:Destroy()
				end
			end
		end
	end
end

return Inventory
