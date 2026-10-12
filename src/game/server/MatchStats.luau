--!nonstrict
-- Estatísticas da partida (servidor): bichos abatidos (golpe final) e jogadas no tabuleiro de cada jogador.
--
--   MatchStats.Init()
--   MatchStats.Results(): { MatchResult }  -- ordenado do melhor para o pior
--   MatchStats.KILL_POINTS / MatchStats.ROLL_POINTS
--
--   type MatchResult = { userId: number, name: string, kills: number, rolls: number, score: number }
-- Pontos = abates × KILL_POINTS + jogadas × ROLL_POINTS. Empate: mais abates, depois mais jogadas.

local Players = game:GetService("Players")

local BoardService = require(script.Parent.BoardService)
local CombatUtil = require(script.Parent.CombatUtil)

local MatchStats = {}

MatchStats.KILL_POINTS = 10
MatchStats.ROLL_POINTS = 15

local initialized = false
local stats: { [number]: { userId: number, name: string, kills: number, rolls: number } } = {}

local function entryFor(userId: number, name: string?)
	local entry = stats[userId]
	if not entry then
		entry = { userId = userId, name = name or ("Jogador " .. userId), kills = 0, rolls = 0 }
		stats[userId] = entry
	elseif name then
		entry.name = name
	end
	return entry
end

local function onPlayer(player: Player)
	entryFor(player.UserId, player.DisplayName)
end

function MatchStats.Init()
	if initialized then
		return
	end
	initialized = true
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	CombatUtil.EnemyKilled:Connect(function(attacker: Player)
		if typeof(attacker) == "Instance" and attacker:IsA("Player") then
			local entry = entryFor(attacker.UserId, attacker.DisplayName)
			entry.kills += 1
		end
	end)
	BoardService.Rolled:Connect(function(result)
		if type(result) == "table" and type(result.rollerUserId) == "number" then
			local player = Players:GetPlayerByUserId(result.rollerUserId)
			local entry = entryFor(result.rollerUserId, player and player.DisplayName or nil)
			entry.rolls += 1
		end
	end)
end

function MatchStats.Results()
	local list = {}
	for _, entry in stats do
		table.insert(list, {
			userId = entry.userId,
			name = entry.name,
			kills = entry.kills,
			rolls = entry.rolls,
			score = entry.kills * MatchStats.KILL_POINTS + entry.rolls * MatchStats.ROLL_POINTS,
		})
	end
	table.sort(list, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		if a.rolls ~= b.rolls then
			return a.rolls > b.rolls
		end
		return a.userId < b.userId
	end)
	return list
end

return MatchStats
