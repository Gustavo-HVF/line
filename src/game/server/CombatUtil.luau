--!nonstrict
-- Funções de combate compartilhadas no servidor do jogo (armas, NPCs e eventos usam isto).
-- Regras:
--   * Jogadores só levam dano de inimigos/eventos (sem fogo amigo).
--   * Inimigos podem ter Humanoid OU atributos "Health"/"MaxHealth" no Model (ex.: mosquitos voadores).
--   * Jogador eliminado tem o atributo "Eliminated" = true no objeto Player.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Tags = require(ReplicatedStorage.Shared.Tags)

local CombatUtil = {}

-- Jogadores -----------------------------------------------------------------------

function CombatUtil.GetHumanoid(model: Instance?): Humanoid?
	if not model then
		return nil
	end
	return model:FindFirstChildOfClass("Humanoid")
end

function CombatUtil.IsPlayerAlive(player: Player): boolean
	if player:GetAttribute("Eliminated") then
		return false
	end
	local character = player.Character
	local humanoid = CombatUtil.GetHumanoid(character)
	return humanoid ~= nil and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart") ~= nil
end

function CombatUtil.GetAlivePlayers(): { Player }
	local alive = {}
	for _, player in Players:GetPlayers() do
		if CombatUtil.IsPlayerAlive(player) then
			table.insert(alive, player)
		end
	end
	return alive
end

-- Jogador vivo mais próximo de uma posição (ou nil). maxDistance opcional.
function CombatUtil.GetNearestAlivePlayer(position: Vector3, maxDistance: number?): (Player?, number)
	local best, bestDistance = nil, maxDistance or math.huge
	for _, player in CombatUtil.GetAlivePlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = player, distance
			end
		end
	end
	return best, bestDistance
end

-- Causa dano a um jogador. `source` é um texto curto usado na mensagem de eliminação (ex.: "Leão").
function CombatUtil.DamagePlayer(player: Player, amount: number, source: string?)
	-- NaN passaria pelo "<= 0" e deixaria a vida em NaN (nunca morre, nunca é eliminado: a derrota trava).
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or not CombatUtil.IsPlayerAlive(player) then
		return
	end
	local humanoid = CombatUtil.GetHumanoid(player.Character)
	if not humanoid then
		return
	end
	if source then
		player:SetAttribute("LastDamageSource", source)
	end
	humanoid:TakeDamage(amount)
end

-- Encontra o jogador dono de uma part (parte do personagem).
function CombatUtil.FindPlayerFromPart(part: Instance?): Player?
	local current = part
	while current and current ~= workspace do
		if current:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(current)
			if player then
				return player
			end
		end
		current = current.Parent
	end
	return nil
end

-- Inimigos ------------------------------------------------------------------------

function CombatUtil.IsEnemy(model: Instance?): boolean
	return model ~= nil and CollectionService:HasTag(model, Tags.Enemy)
end

-- Sobe na hierarquia até achar o Model marcado com a tag Enemy.
function CombatUtil.FindEnemyFromPart(part: Instance?): Model?
	local current = part
	while current and current ~= workspace do
		if CollectionService:HasTag(current, Tags.Enemy) then
			return current :: Model
		end
		current = current.Parent
	end
	return nil
end

function CombatUtil.GetEnemyHealth(model: Model): (number, number)
	local humanoid = CombatUtil.GetHumanoid(model)
	if humanoid then
		return humanoid.Health, humanoid.MaxHealth
	end
	local health = tonumber(model:GetAttribute("Health")) or 0
	local maxHealth = tonumber(model:GetAttribute("MaxHealth")) or 0
	return health, maxHealth
end

function CombatUtil.IsEnemyAlive(model: Model): boolean
	if not model.Parent then
		return false
	end
	return (CombatUtil.GetEnemyHealth(model)) > 0
end

-- Causa dano a um inimigo. Retorna true se o golpe matou o inimigo.
function CombatUtil.DamageEnemy(model: Model, amount: number, attacker: Player?): boolean
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or not CombatUtil.IsEnemyAlive(model) then
		return false
	end
	if attacker then
		model:SetAttribute("LastAttackerUserId", attacker.UserId)
	end
	local humanoid = CombatUtil.GetHumanoid(model)
	if humanoid then
		humanoid:TakeDamage(amount)
		return humanoid.Health <= 0
	end
	local health = math.max((tonumber(model:GetAttribute("Health")) or 0) - amount, 0)
	model:SetAttribute("Health", health)
	return health <= 0
end

-- Dano em área ----------------------------------------------------------------------

-- Dano a jogadores dentro de um raio (com queda linear até a borda). Retorna os jogadores atingidos.
function CombatUtil.DamagePlayersInRadius(
	position: Vector3,
	radius: number,
	maxDamage: number,
	source: string?
): { Player }
	local hit = {}
	if not (radius > 0) then
		return hit -- raio 0 (ou NaN) daria falloff NaN
	end
	for _, player in CombatUtil.GetAlivePlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local distance = (root.Position - position).Magnitude
			if distance <= radius then
				local falloff = 1 - (distance / radius) * 0.6
				CombatUtil.DamagePlayer(player, maxDamage * falloff, source)
				table.insert(hit, player)
			end
		end
	end
	return hit
end

-- Dano a inimigos dentro de um raio. Retorna a quantidade atingida.
function CombatUtil.DamageEnemiesInRadius(
	position: Vector3,
	radius: number,
	maxDamage: number,
	attacker: Player?
): number
	local count = 0
	if not (radius > 0) then
		return count
	end
	for _, enemy in CollectionService:GetTagged(Tags.Enemy) do
		if enemy:IsA("Model") and enemy:IsDescendantOf(workspace) and CombatUtil.IsEnemyAlive(enemy) then
			local pivot = enemy:GetPivot().Position
			local distance = (pivot - position).Magnitude
			if distance <= radius then
				local falloff = 1 - (distance / radius) * 0.6
				CombatUtil.DamageEnemy(enemy, maxDamage * falloff, attacker)
				count += 1
			end
		end
	end
	return count
end

-- Empurra o personagem de um jogador (knockback).
-- O personagem é simulado pelo cliente dono dele, então o empurrão é aplicado lá (FxClient, tipo "knockback").
function CombatUtil.Knockback(player: Player, direction: Vector3, strength: number)
	if direction.Magnitude < 1e-3 or not CombatUtil.IsPlayerAlive(player) then
		return
	end
	local push = direction.Unit * strength + Vector3.new(0, strength * 0.4, 0)
	Net.event(Net.Names.Fx_Play):FireClient(player, "knockback", { velocity = push })
end

return CombatUtil
