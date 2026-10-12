--!nonstrict
-- Configurações dos jogadores no servidor (usado pelo lobby e pela partida).
--   SettingsStore.Init()        cria Settings_Get / Settings_Save e começa a carregar/gravar
--   SettingsStore.Get(player)   configurações do jogador (carrega se preciso; pode ceder)
--
-- DataStore "PlayerSettings_v1", chave "u_<userId>", até 3 tentativas por operação.
-- Gravação: no máximo 1 a cada 6 s por jogador; mudanças que chegam antes disso ficam agendadas e a
-- gravação adiada usa sempre o valor mais recente. Ao sair (PlayerRemoving) e ao fechar o servidor
-- (BindToClose, com limite de tempo) grava o que estiver pendente.
-- Sem acesso ao DataStore (Studio sem "Enable Studio Access to API Services" ou place não publicado):
-- usa o padrão, guarda só durante a sessão e avisa uma vez no Output.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local SettingsSchema = require(ReplicatedStorage.Shared.Settings.SettingsSchema)

local SettingsStore = {}

local STORE_NAME = "PlayerSettings_v1"
local KEY_PREFIX = "u_"
local MAX_ATTEMPTS = 3
local SAVE_INTERVAL = 6 -- s entre gravações do mesmo jogador
local MAX_WRITE_FAILURES = 3 -- falhas seguidas antes de desistir até a próxima mudança
local BUDGET_WAIT = 5 -- s esperando orçamento de requisições do DataStore
local CLOSE_TIMEOUT = 25 -- s (o Roblox dá no máximo 30 s ao BindToClose)
local RATE_WINDOW = 1 -- s
local RATE_MAX = 8 -- mensagens Settings_Save por janela; o excesso é ignorado

type Entry = {
	player: Player,
	userId: number,
	settings: any,
	state: string, -- "loading" | "ready"
	waiters: { thread },
	changedByPlayer: boolean,
	dirty: boolean,
	writing: boolean,
	writeScheduled: boolean,
	lastWrite: number,
	failures: number,
	removed: boolean,
	finalizing: boolean,
	rateStart: number,
	rateCount: number,
}

local entries: { [Player]: Entry } = {}
local pendingFinal: { [number]: Entry } = {} -- userId → entrada de quem saiu e ainda está gravando
local store: DataStore? = nil
local storeAvailable = true
local warnedUnavailable = false
local initialized = false
local closing = false
local activeWrites = 0
local activeFinals = 0

-- DataStore ------------------------------------------------------------------------------------

local function markUnavailable(reason: string)
	storeAvailable = false
	if warnedUnavailable then
		return
	end
	warnedUnavailable = true
	warn(
		("[SettingsStore] DataStore indisponível (%s). As configurações valem só nesta sessão e começam no padrão. "):format(
			reason
		)
			.. "No Studio: publique o place e ative Game Settings › Security › Enable Studio Access to API Services."
	)
end

-- Erros que não adianta repetir (sem permissão / Studio sem API / place não publicado).
local function isAccessError(message: string): boolean
	local lower = string.lower(message)
	for _, pattern in { "studio", "publish", "403", "not allowed", "forbidden", "api access" } do
		if string.find(lower, pattern, 1, true) then
			return true
		end
	end
	return false
end

local function getStore(): DataStore?
	if not storeAvailable then
		return nil
	end
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok and result then
		store = result
		return store
	end
	markUnavailable(tostring(result))
	return nil
end

-- Executa `callback` com até MAX_ATTEMPTS tentativas (espera 1 s, depois 2 s).
local function withRetries(label: string, callback: () -> any): (boolean, any)
	local lastError = "?"
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		lastError = tostring(result)
		if isAccessError(lastError) then
			markUnavailable(lastError)
			return false, lastError
		end
		if attempt < MAX_ATTEMPTS then
			task.wait(attempt)
		end
	end
	warn(("[SettingsStore] Falha ao %s depois de %d tentativas: %s"):format(label, MAX_ATTEMPTS, lastError))
	return false, lastError
end

local function waitForBudget(requestType: Enum.DataStoreRequestType)
	local started = os.clock()
	while os.clock() - started < BUDGET_WAIT do
		local ok, budget = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(requestType)
		end)
		if not ok or budget > 0 or closing then
			return
		end
		task.wait(0.5)
	end
end

local function sameSettings(a, b): boolean
	if a.version ~= b.version then
		return false
	end
	for key, value in a.audio do
		if b.audio[key] ~= value then
			return false
		end
	end
	for key, value in a.graphics do
		if b.graphics[key] ~= value then
			return false
		end
	end
	return true
end

-- Gravação ---------------------------------------------------------------------------------------

local scheduleWrite -- declarada abaixo (recursão com writeEntry)

local function writeEntry(entry: Entry): boolean
	if entry.writing or not entry.dirty then
		return false
	end
	local dataStore = getStore()
	if not dataStore then
		-- Sem DataStore não há onde gravar: o valor fica só no cache desta sessão.
		entry.dirty = false
		return false
	end

	entry.writing = true
	entry.dirty = false
	entry.lastWrite = os.clock()
	activeWrites += 1
	local snapshot = SettingsSchema.Clone(entry.settings)
	local key = KEY_PREFIX .. tostring(entry.userId)
	local userIds = { entry.userId }

	waitForBudget(Enum.DataStoreRequestType.SetIncrementAsync)
	local ok = withRetries(("gravar as configurações de %d"):format(entry.userId), function()
		dataStore:SetAsync(key, snapshot, userIds)
	end)

	activeWrites -= 1
	entry.writing = false
	entry.lastWrite = os.clock()
	if ok then
		entry.failures = 0
	elseif storeAvailable then
		entry.failures += 1
		if entry.failures < MAX_WRITE_FAILURES then
			entry.dirty = true -- tenta de novo mais tarde
		end
	end
	return ok
end

-- Agenda uma gravação respeitando o intervalo mínimo; o valor gravado é o mais recente na hora.
scheduleWrite = function(entry: Entry)
	if entry.writeScheduled or entry.removed or closing then
		return
	end
	entry.writeScheduled = true
	local delayTime = math.max(0, entry.lastWrite + SAVE_INTERVAL - os.clock())
	task.delay(delayTime, function()
		entry.writeScheduled = false
		if entry.removed or closing or entry.writing then
			-- Saída/fechamento fazem a gravação final; uma gravação em andamento reagenda ao terminar.
			return
		end
		writeEntry(entry)
		if entry.dirty and not entry.removed and not closing then
			scheduleWrite(entry)
		end
	end)
end

-- Gravação final (jogador saiu ou servidor fechando).
local function finalSave(entry: Entry)
	while entry.writing do
		task.wait(0.2)
	end
	if not entry.dirty then
		return
	end
	-- Respeita o intervalo por chave, a não ser que o servidor esteja fechando.
	local readyAt = entry.lastWrite + SAVE_INTERVAL
	while os.clock() < readyAt and not closing do
		task.wait(0.25)
	end
	writeEntry(entry)
end

local function startFinalSave(entry: Entry)
	if entry.finalizing then
		return
	end
	entry.finalizing = true
	activeFinals += 1
	pendingFinal[entry.userId] = entry
	task.spawn(function()
		local ok, err = pcall(finalSave, entry)
		if not ok then
			warn("[SettingsStore] Erro na gravação final: " .. tostring(err))
		end
		activeFinals -= 1
		if pendingFinal[entry.userId] == entry then
			pendingFinal[entry.userId] = nil
		end
	end)
end

-- Carregamento -----------------------------------------------------------------------------------

local function wakeWaiters(entry: Entry)
	local waiters = entry.waiters
	entry.waiters = {}
	for _, thread in waiters do
		task.spawn(thread)
	end
end

local function load(entry: Entry)
	local data = nil
	local ok, err = pcall(function()
		local dataStore = getStore()
		if not dataStore then
			return
		end
		waitForBudget(Enum.DataStoreRequestType.GetAsync)
		local key = KEY_PREFIX .. tostring(entry.userId)
		local success, result = withRetries(("carregar as configurações de %d"):format(entry.userId), function()
			return dataStore:GetAsync(key)
		end)
		if success then
			data = result
		end
	end)
	if not ok then
		warn("[SettingsStore] Erro ao carregar: " .. tostring(err))
	end

	-- Se o jogador já mudou algo enquanto carregava, a escolha dele vale mais que o valor salvo.
	if not entry.changedByPlayer then
		entry.settings = SettingsSchema.Sanitize(data)
	end
	entry.state = "ready"
	wakeWaiters(entry)

	if entry.dirty then
		if entry.removed then
			startFinalSave(entry)
		else
			scheduleWrite(entry)
		end
	end
end

local function newEntry(player: Player): Entry
	return {
		player = player,
		userId = player.UserId,
		settings = SettingsSchema.Defaults(),
		state = "loading",
		waiters = {},
		changedByPlayer = false,
		dirty = false,
		writing = false,
		writeScheduled = false,
		lastWrite = 0,
		failures = 0,
		removed = false,
		finalizing = false,
		rateStart = 0,
		rateCount = 0,
	}
end

local function ensureEntry(player: Player): Entry?
	local entry = entries[player]
	if entry then
		return entry
	end
	if player.Parent ~= Players then
		return nil
	end
	entry = newEntry(player)
	entries[player] = entry

	-- Voltou antes da gravação final terminar: usa o valor que ainda está sendo gravado.
	local previous = pendingFinal[player.UserId]
	if previous then
		entry.settings = SettingsSchema.Clone(previous.settings)
		entry.state = "ready"
		entry.lastWrite = os.clock()
		return entry
	end

	task.spawn(load, entry)
	return entry
end

-- Remotes ----------------------------------------------------------------------------------------

local function onSave(player: Player, payload: any)
	local entry = entries[player]
	if not entry or entry.removed then
		return
	end

	-- Limite de frequência (o cliente já espera 1,5 s entre envios; isto só barra abuso).
	local now = os.clock()
	if now - entry.rateStart > RATE_WINDOW then
		entry.rateStart = now
		entry.rateCount = 0
	end
	entry.rateCount += 1
	if entry.rateCount > RATE_MAX then
		return
	end

	if type(payload) ~= "table" then
		return
	end
	local ok, clean = pcall(SettingsSchema.Sanitize, payload)
	if not ok then
		return
	end

	entry.changedByPlayer = true
	if sameSettings(clean, entry.settings) then
		return
	end
	entry.settings = clean
	entry.dirty = true
	entry.failures = 0
	if entry.state == "ready" then
		scheduleWrite(entry)
	end
end

local function onPlayerRemoving(player: Player)
	local entry = entries[player]
	if not entry then
		return
	end
	entries[player] = nil
	entry.removed = true
	if entry.state == "ready" and entry.dirty then
		startFinalSave(entry)
	end
	-- Ainda carregando: o load termina, acorda quem espera e faz a gravação final se precisar.
end

local function onClose()
	closing = true
	for _, entry in entries do
		if entry.state == "ready" and entry.dirty then
			startFinalSave(entry)
		end
	end
	local started = os.clock()
	while (activeFinals > 0 or activeWrites > 0) and os.clock() - started < CLOSE_TIMEOUT do
		task.wait(0.25)
	end
end

-- API pública ------------------------------------------------------------------------------------

function SettingsStore.Init()
	if initialized then
		return
	end
	initialized = true

	local getRemote = Net.func(Net.Names.Settings_Get)
	local saveRemote = Net.event(Net.Names.Settings_Save)

	getRemote.OnServerInvoke = function(player)
		return SettingsStore.Get(player)
	end
	saveRemote.OnServerEvent:Connect(onSave)

	Players.PlayerAdded:Connect(ensureEntry)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(ensureEntry, player)
	end

	game:BindToClose(onClose)
end

-- Configurações do jogador (cópia). Cede enquanto o DataStore responde.
function SettingsStore.Get(player: Player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return SettingsSchema.Defaults()
	end
	local entry = ensureEntry(player)
	if not entry then
		return SettingsSchema.Defaults()
	end
	if entry.state ~= "ready" then
		table.insert(entry.waiters, coroutine.running())
		coroutine.yield()
	end
	return SettingsSchema.Clone(entry.settings)
end

return SettingsStore
