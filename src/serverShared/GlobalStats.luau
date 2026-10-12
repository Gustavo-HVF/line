--!nonstrict
-- Placar global entre partidas (DataStore). A partida grava; o lobby lê e mostra os melhores.
--
--   GlobalStats.RecordMatch(entries, victory)   -- cede; chame com task.spawn
--       entries: { { userId: number, kills: number, rolls: number, score: number } }
--   GlobalStats.GetTop(count): ({ LeaderboardEntry }?, string?)   -- cede
--       LeaderboardEntry = { rank, userId, name, points, kills, rolls, wins, matches }
--
-- Pontos do placar = pontos da partida (abates e jogadas) + VICTORY_BONUS para quem venceu.
-- OrderedDataStore guarda só os pontos (para ordenar); um DataStore comum guarda os detalhes.
-- Sem acesso ao DataStore (Studio sem API), as funções avisam uma vez e devolvem vazio.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local UserService = game:GetService("UserService")

local GlobalStats = {}

GlobalStats.VICTORY_BONUS = 50

local ORDERED_NAME = "PlacarGlobal_Pontos_v1"
local DETAILS_NAME = "PlacarGlobal_Detalhes_v1"
local ATTEMPTS = 3

local ordered: OrderedDataStore? = nil
local details: GlobalDataStore? = nil
local unavailable = false
local warned = false
local nameCache: { [number]: string } = {}

local function warnOnce(message: string)
	if not warned then
		warned = true
		warn("[GlobalStats] " .. message)
	end
end

local function stores(): boolean
	if unavailable then
		return false
	end
	if ordered and details then
		return true
	end
	local ok, err = pcall(function()
		ordered = DataStoreService:GetOrderedDataStore(ORDERED_NAME)
		details = DataStoreService:GetDataStore(DETAILS_NAME)
	end)
	if not ok then
		unavailable = true
		warnOnce("DataStore indisponível; o placar global não vai funcionar aqui: " .. tostring(err))
		return false
	end
	return true
end

local function keyFor(userId: number): string
	return "u_" .. tostring(userId)
end

local function retry(label: string, fn: () -> any): (boolean, any)
	local lastError = nil
	for attempt = 1, ATTEMPTS do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < ATTEMPTS then
			task.wait(2 ^ attempt)
		end
	end
	warn(("[GlobalStats] %s falhou: %s"):format(label, tostring(lastError)))
	return false, lastError
end

local function whole(value: any): number
	if type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.max(math.floor(value), 0)
end

function GlobalStats.RecordMatch(entries: { any }, victory: boolean)
	if type(entries) ~= "table" or not stores() then
		return
	end
	for _, entry in entries do
		local userId = type(entry) == "table" and entry.userId
		if type(userId) == "number" and userId > 0 then
			local kills, rolls = whole(entry.kills), whole(entry.rolls)
			local points = whole(entry.score) + (if victory then GlobalStats.VICTORY_BONUS else 0)
			local key = keyFor(userId)
			if points > 0 then
				retry("IncrementAsync " .. key, function()
					return (ordered :: OrderedDataStore):IncrementAsync(key, points)
				end)
			end
			retry("UpdateAsync " .. key, function()
				return (details :: GlobalDataStore):UpdateAsync(key, function(old)
					local data = type(old) == "table" and old or {}
					return {
						points = whole(data.points) + points,
						kills = whole(data.kills) + kills,
						rolls = whole(data.rolls) + rolls,
						wins = whole(data.wins) + (if victory then 1 else 0),
						matches = whole(data.matches) + 1,
					}
				end)
			end)
		end
	end
end

local function resolveNames(userIds: { number })
	local missing = {}
	for _, userId in userIds do
		if not nameCache[userId] then
			table.insert(missing, userId)
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and type(infos) == "table" then
		for _, info in infos do
			if type(info) == "table" and type(info.Id) == "number" then
				nameCache[info.Id] = info.DisplayName or info.Username
			end
		end
	end
	for _, userId in missing do
		if not nameCache[userId] then
			local nameOk, name = pcall(function()
				return Players:GetNameFromUserIdAsync(userId)
			end)
			nameCache[userId] = if nameOk and type(name) == "string" then name else ("Jogador " .. userId)
		end
	end
end

function GlobalStats.GetTop(count: number): ({ any }?, string?)
	if not stores() then
		return nil, "indisponível"
	end
	local ok, pages = retry("GetSortedAsync", function()
		return (ordered :: OrderedDataStore):GetSortedAsync(false, math.clamp(count, 1, 100))
	end)
	if not ok or not pages then
		return nil, tostring(pages)
	end
	local page = pages:GetCurrentPage()
	local list = {}
	local ids = {}
	for index, item in page do
		local userId = tonumber(string.match(tostring(item.key), "^u_(%d+)$"))
		if userId then
			table.insert(ids, userId)
			table.insert(list, { rank = index, userId = userId, points = whole(item.value) })
		end
	end
	resolveNames(ids)
	for _, entry in list do
		entry.name = nameCache[entry.userId] or ("Jogador " .. entry.userId)
		local detailOk, data = pcall(function()
			return (details :: GlobalDataStore):GetAsync(keyFor(entry.userId))
		end)
		if detailOk and type(data) == "table" then
			entry.kills = whole(data.kills)
			entry.rolls = whole(data.rolls)
			entry.wins = whole(data.wins)
			entry.matches = whole(data.matches)
		end
	end
	return list, nil
end

return GlobalStats
