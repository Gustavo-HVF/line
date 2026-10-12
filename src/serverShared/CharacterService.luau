--!nonstrict
-- Personagens R6 criados por código (lobby e partida), independentes do tipo de avatar da experiência.
-- A aparência do jogador (roupas, cores, acessórios) vem da HumanoidDescription dele, montada num rig R6.
-- O script "Animate" padrão é removido: a animação é procedural (Shared/Character/R6Animator, no cliente).
--
--   CharacterService.Init(options?)
--     options.autoSpawn: boolean?        -- cria o personagem ao entrar e de novo depois de morrer (lobby)
--     options.respawnDelay: number?      -- segundos até renascer (padrão 3)
--     options.spawnCFrame: ((Player) -> CFrame?)?  -- onde nascer (CFrame da HumanoidRootPart)
--   CharacterService.Spawn(player, cframe?): Model?   -- cede (busca a aparência); nil se falhar
--
-- Também recebe Char_MoveState ("none" | "climb") e grava no atributo "MoveState" do personagem, para os
-- outros clientes saberem que ele está escalando.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local CharacterService = {}

local DEFAULT_RESPAWN_DELAY = 3
local MOVE_STATES = { none = true, climb = true }
local DESCRIPTION_ATTEMPTS = 2

local initialized = false
local options: { [string]: any } = {}
local descriptions: { [number]: HumanoidDescription } = {}
local spawning: { [Player]: boolean } = {}

local function getDescription(userId: number): HumanoidDescription
	local cached = descriptions[userId]
	if cached then
		return cached:Clone()
	end
	if userId > 0 then
		for attempt = 1, DESCRIPTION_ATTEMPTS do
			local ok, result = pcall(function()
				return Players:GetHumanoidDescriptionFromUserId(userId)
			end)
			if ok and result then
				descriptions[userId] = result
				return result:Clone()
			end
			warn(
				("[CharacterService] Aparência de %d indisponível (tentativa %d): %s"):format(
					userId,
					attempt,
					tostring(result)
				)
			)
			task.wait(0.5)
		end
	end
	return Instance.new("HumanoidDescription")
end

local function buildModel(description: HumanoidDescription): Model?
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R6)
	end)
	if ok and model then
		return model
	end
	warn("[CharacterService] Falha ao montar o personagem: " .. tostring(model))
	-- Aparência com algum item inválido: tenta com a aparência padrão.
	ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	end)
	if ok and model then
		return model
	end
	warn("[CharacterService] Falha ao montar o personagem padrão: " .. tostring(model))
	return nil
end

-- Cria (ou recria) o personagem R6 do jogador. Cede.
function CharacterService.Spawn(player: Player, cframe: CFrame?): Model?
	if not player.Parent or spawning[player] then
		return nil
	end
	spawning[player] = true
	local description = getDescription(player.UserId)
	local model = player.Parent and buildModel(description) or nil
	spawning[player] = nil
	if not model or not player.Parent then
		if model then
			model:Destroy()
		end
		return nil
	end

	model.Name = player.Name
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = player.DisplayName
	end

	local target = cframe
	if not target and options.spawnCFrame then
		local ok, result = pcall(options.spawnCFrame, player)
		if ok and typeof(result) == "CFrame" then
			target = result
		end
	end
	if target then
		model:PivotTo(target)
	end

	local old = player.Character
	player.Character = model
	model.Parent = workspace
	if old and old ~= model then
		old:Destroy()
	end
	return model
end

local function watchDeath(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.Died:Once(function()
		task.wait(options.respawnDelay or DEFAULT_RESPAWN_DELAY)
		if player.Parent and player.Character == character then
			CharacterService.Spawn(player)
		end
	end)
end

local function onMoveState(player: Player, state: any)
	local character = player.Character
	if not character or type(state) ~= "string" or not MOVE_STATES[state] then
		return
	end
	local value = if state == "none" then nil else state
	if character:GetAttribute("MoveState") ~= value then
		character:SetAttribute("MoveState", value)
	end
end

function CharacterService.Init(initOptions: { [string]: any }?)
	if initialized then
		return
	end
	initialized = true
	options = initOptions or {}

	Net.event(Net.Names.Char_MoveState).OnServerEvent:Connect(onMoveState)

	Players.PlayerRemoving:Connect(function(player)
		spawning[player] = nil
		descriptions[player.UserId] = nil
	end)

	if options.autoSpawn then
		local function onPlayer(player: Player)
			player.CharacterAdded:Connect(function(character)
				task.spawn(watchDeath, player, character)
			end)
			if not player.Character then
				task.spawn(CharacterService.Spawn, player)
			end
		end
		Players.PlayerAdded:Connect(onPlayer)
		for _, player in Players:GetPlayers() do
			task.spawn(onPlayer, player)
		end
	end
end

return CharacterService
