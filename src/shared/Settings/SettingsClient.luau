--!nonstrict
-- Configurações do jogador no cliente (lobby e partida).
--   SettingsClient.Init()      idempotente; busca no servidor (Settings_Get, até 8 s; senão usa o padrão),
--                              aplica áudio e gráficos e inicia o GraphicsApplier
--   SettingsClient.Get()       cópia das configurações atuais
--   SettingsClient.Set(s)      valida, aplica na hora e salva no servidor com debounce de 1,5 s
--   SettingsClient.Changed     Signal (settings) disparado a cada mudança
--   SettingsClient.IsLoaded()  true depois que o Init terminou (com os dados do servidor ou o padrão)

local RunService = game:GetService("RunService")

local Net = require(script.Parent.Parent.Net)
local Signal = require(script.Parent.Parent.Util.Signal)
local SettingsSchema = require(script.Parent.SettingsSchema)
local AudioApplier = require(script.Parent.AudioApplier)
local GraphicsApplier = require(script.Parent.GraphicsApplier)

local SettingsClient = {}

SettingsClient.Changed = Signal.new()

local FETCH_TIMEOUT = 8
local SAVE_DEBOUNCE = 1.5

local current = SettingsSchema.Defaults()
local loaded = false
local initState = "idle" -- "idle" | "loading" | "done"
local initWaiters: { thread } = {}
local changedLocally = false -- o jogador mudou algo antes da resposta do servidor chegar
local saveToken = 0
local savePending = false

local function applyAll()
	local okAudio, audioErr = pcall(AudioApplier.Apply, current.audio)
	if not okAudio then
		warn("[SettingsClient] Erro ao aplicar o áudio: " .. tostring(audioErr))
	end
	local okGraphics, graphicsErr = pcall(GraphicsApplier.Apply, current.graphics)
	if not okGraphics then
		warn("[SettingsClient] Erro ao aplicar os gráficos: " .. tostring(graphicsErr))
	end
end

local function sendNow()
	savePending = false
	local snapshot = SettingsSchema.Clone(current)
	local ok, err = pcall(function()
		Net.event(Net.Names.Settings_Save):FireServer(snapshot)
	end)
	if not ok then
		warn("[SettingsClient] Não foi possível enviar as configurações: " .. tostring(err))
	end
end

local function scheduleSave()
	saveToken += 1
	local token = saveToken
	savePending = true
	task.delay(SAVE_DEBOUNCE, function()
		if token == saveToken and savePending then
			sendNow()
		end
	end)
end

-- Busca no servidor sem travar: a chamada roda numa thread separada e esperamos no máximo FETCH_TIMEOUT.
-- Se a resposta chegar depois do prazo (e o jogador não tiver mexido em nada), ela ainda é aplicada.
local function fetchFromServer(): any
	local result = nil
	local finished = false
	local timedOut = false

	task.spawn(function()
		local ok, value = pcall(function()
			return Net.func(Net.Names.Settings_Get):InvokeServer()
		end)
		if not ok then
			warn("[SettingsClient] Erro ao buscar as configurações: " .. tostring(value))
			value = nil
		end
		result = value
		finished = true
		if timedOut and value ~= nil and not changedLocally then
			current = SettingsSchema.Sanitize(value)
			applyAll()
			SettingsClient.Changed:Fire(SettingsSchema.Clone(current))
		end
	end)

	local started = os.clock()
	while not finished and os.clock() - started < FETCH_TIMEOUT do
		task.wait(0.1)
	end
	if not finished then
		timedOut = true
		warn("[SettingsClient] O servidor não respondeu a tempo; usando as configurações padrão por enquanto.")
		return nil
	end
	return result
end

function SettingsClient.Init()
	if not RunService:IsClient() then
		warn("[SettingsClient] Use somente no cliente.")
		return
	end
	if initState == "done" then
		return
	end
	if initState == "loading" then
		-- Outro script já está carregando: espera terminar (Init sempre retorna com tudo aplicado).
		table.insert(initWaiters, coroutine.running())
		coroutine.yield()
		return
	end
	initState = "loading"

	local okInit, initErr = pcall(GraphicsApplier.Init)
	if not okInit then
		warn("[SettingsClient] Erro ao iniciar o GraphicsApplier: " .. tostring(initErr))
	end

	local fromServer = fetchFromServer()
	if fromServer ~= nil and not changedLocally then
		current = SettingsSchema.Sanitize(fromServer)
	end
	applyAll()

	loaded = true
	initState = "done"
	SettingsClient.Changed:Fire(SettingsSchema.Clone(current))

	local waiters = initWaiters
	initWaiters = {}
	for _, thread in waiters do
		task.spawn(thread)
	end
end

function SettingsClient.Get()
	return SettingsSchema.Clone(current)
end

function SettingsClient.Set(settings)
	local clean = SettingsSchema.Sanitize(settings)
	current = clean
	changedLocally = true
	applyAll()
	SettingsClient.Changed:Fire(SettingsSchema.Clone(current))
	scheduleSave()
end

-- Envia agora uma gravação que ainda estava esperando o debounce (ex.: ao fechar a tela de configurações).
function SettingsClient.Flush()
	if savePending then
		saveToken += 1
		-- Em thread própria: Net.event pode esperar o remote existir, e quem chama não deve travar.
		task.spawn(sendNow)
	end
end

function SettingsClient.IsLoaded(): boolean
	return loaded
end

return SettingsClient
