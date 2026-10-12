--!nonstrict
-- Entrada do cliente da PARTIDA:
--   1. configurações (busca no servidor em paralelo com a tela de carregamento);
--   2. tela de carregamento (bloqueante; pré-carrega o jogo se o jogador quiser);
--   3. interface e efeitos (HUD, enigma, efeitos, espectador, controles do tabuleiro, cutscene final);
--   4. personagem: animação R6 de todos, primeira pessoa, corrida e escalada (desligados para quem foi
--      eliminado e durante a cutscene final);
--   5. avisa o servidor que está pronto (Game_ClientReady).
-- Os módulos começam ANTES do aviso de pronto para não perder o estado que o servidor manda em resposta.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
-- Place único: no lobby este cliente não roda (quem roda é o MainMenu).
if require(Shared:WaitForChild("PlaceMode")).Get() ~= "game" then
	return
end

local Net = require(ReplicatedStorage.Shared.Net)
local UIKit = require(ReplicatedStorage.Shared.UI.UIKit)

local LoadingScreen = require(script.Parent.LoadingScreen)
local HUD = require(script.Parent.HUD)
local RiddleUI = require(script.Parent.RiddleUI)
local FxClient = require(script.Parent.FxClient)
local Spectate = require(script.Parent.Spectate)
local BoardClient = require(script.Parent.BoardClient)
local EndCutscene = require(script.Parent.EndCutscene)

local CharacterFolder = Shared:WaitForChild("Character")
local FirstPerson = require(CharacterFolder:WaitForChild("FirstPerson"))
local Movement = require(CharacterFolder:WaitForChild("Movement"))
local R6Animator = require(CharacterFolder:WaitForChild("R6Animator"))

local LocalPlayer = Players.LocalPlayer

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

-- Os outros jogadores já aparecem animados durante o carregamento.
R6Animator.Init()

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
start("EndCutscene", EndCutscene)

Net.event(Net.Names.Notify).OnClientEvent:Connect(function(text, kind)
	if type(text) ~= "string" or text == "" then
		return
	end
	UIKit.Toast(text, TOAST_KINDS[kind] and kind or "info")
end)

-- 4. Personagem ---------------------------------------------------------------------------
local function refreshCharacterMode()
	local eliminated = LocalPlayer:GetAttribute("Eliminated") == true
	if eliminated or EndCutscene.IsPlaying() then
		FirstPerson.Disable()
		Movement.Disable()
	else
		FirstPerson.Enable()
		Movement.Enable({ climb = true })
	end
end
LocalPlayer:GetAttributeChangedSignal("Eliminated"):Connect(refreshCharacterMode)
EndCutscene.Started:Connect(refreshCharacterMode)
local ok, err = pcall(refreshCharacterMode)
if not ok then
	warn("[GameClient] Erro ao ligar a primeira pessoa: " .. tostring(err))
end

-- 5. Pronto! -------------------------------------------------------------------------------
Net.event(Net.Names.Game_ClientReady):FireServer()
