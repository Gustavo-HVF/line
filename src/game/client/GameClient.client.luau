--!nonstrict
-- Entrada do cliente da PARTIDA:
--   1. configurações (busca no servidor em paralelo com a tela de carregamento);
--   2. tela de carregamento (bloqueante; pré-carrega o jogo se o jogador quiser);
--   3. interface e efeitos (HUD, enigma, efeitos, espectador, controles do tabuleiro);
--   4. avisa o servidor que está pronto (Game_ClientReady).
-- Os módulos começam ANTES do aviso de pronto para não perder o estado que o servidor manda em resposta.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(ReplicatedStorage.Shared.Net)
local UIKit = require(ReplicatedStorage.Shared.UI.UIKit)

local LoadingScreen = require(script.Parent.LoadingScreen)
local HUD = require(script.Parent.HUD)
local RiddleUI = require(script.Parent.RiddleUI)
local FxClient = require(script.Parent.FxClient)
local Spectate = require(script.Parent.Spectate)
local BoardClient = require(script.Parent.BoardClient)

local TOAST_KINDS = { info = true, warning = true, danger = true, success = true }

-- 1. Configurações -------------------------------------------------------------------------
local settingsDone = false
task.spawn(function()
	local settingsFolder = Shared:WaitForChild("Settings", 10)
	local moduleScript = settingsFolder and settingsFolder:WaitForChild("SettingsClient", 10)
	if moduleScript and moduleScript:IsA("ModuleScript") then
		local ok, SettingsClient = pcall(require, moduleScript)
		if ok and type(SettingsClient) == "table" and type(SettingsClient.Init) == "function" then
			local initOk, err = pcall(SettingsClient.Init)
			if not initOk then
				warn("[GameClient] Erro ao iniciar as configurações: " .. tostring(err))
			end
		else
			warn("[GameClient] SettingsClient não pôde ser carregado: " .. tostring(SettingsClient))
		end
	else
		warn("[GameClient] SettingsClient não encontrado; usando as configurações padrão.")
	end
	settingsDone = true
end)

-- Sem botão de "Resetar personagem": morrer elimina o jogador.
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end)
		if ok then
			break
		end
		task.wait(1)
	end
end)

-- 2. Tela de carregamento ----------------------------------------------------------------
local loadingOk, loadingErr = pcall(LoadingScreen.Run, function()
	return settingsDone
end)
if not loadingOk then
	warn("[GameClient] Erro na tela de carregamento: " .. tostring(loadingErr))
	LoadingScreen.ForceClose()
end

-- 3. Interface e efeitos -----------------------------------------------------------------
local function start(label: string, module)
	local ok, err = pcall(module.Init)
	if not ok then
		warn(("[GameClient] Erro ao iniciar %s: %s"):format(label, tostring(err)))
	end
end
start("FxClient", FxClient)
start("HUD", HUD)
start("RiddleUI", RiddleUI)
start("Spectate", Spectate)
start("BoardClient", BoardClient)

Net.event(Net.Names.Notify).OnClientEvent:Connect(function(text, kind)
	if type(text) ~= "string" or text == "" then
		return
	end
	UIKit.Toast(text, TOAST_KINDS[kind] and kind or "info")
end)

-- 4. Pronto! -------------------------------------------------------------------------------
Net.event(Net.Names.Game_ClientReady):FireServer()
