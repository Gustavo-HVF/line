--!nonstrict
-- Controles do tabuleiro para quem o carrega: T joga o dado, G solta (com botões na tela no celular).
-- As ações só existem quando fazem sentido (de acordo com o Board_Status). Perto do tabuleiro no chão,
-- quem cuida é o ProximityPrompt do servidor ("Jogar o dado", tecla T, ou toque no prompt).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local BoardClient = {}

local LocalPlayer = Players.LocalPlayer

local ROLL_ACTION = "SelvaJogarDado"
local DROP_ACTION = "SelvaSoltarTabuleiro"
local SEND_DEBOUNCE = 0.5

local initialized = false
local status = nil
local bound: { [string]: boolean } = {}
local lastSend = 0
local remotes: { [string]: RemoteEvent } = {}

local function send(remote: RemoteEvent)
	local now = os.clock()
	if now - lastSend < SEND_DEBOUNCE then
		return
	end
	lastSend = now
	remote:FireServer()
end

local function onRoll(_actionName: string, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		send(remotes.roll)
	end
	return Enum.ContextActionResult.Sink
end

local function onDrop(_actionName: string, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		send(remotes.drop)
	end
	return Enum.ContextActionResult.Sink
end

local function setBound(
	name: string,
	shouldBind: boolean,
	handler: (string, Enum.UserInputState) -> Enum.ContextActionResult,
	title: string,
	keyboard: Enum.KeyCode,
	gamepad: Enum.KeyCode
)
	if (bound[name] == true) == shouldBind then
		return
	end
	bound[name] = shouldBind
	if shouldBind then
		ContextActionService:BindAction(name, handler, true, keyboard, gamepad)
		ContextActionService:SetTitle(name, title)
	else
		ContextActionService:UnbindAction(name)
	end
end

local function refresh()
	local eliminated = LocalPlayer:GetAttribute("Eliminated") == true
	local carrying = not eliminated and status ~= nil and status.carrierUserId == LocalPlayer.UserId
	local canRoll = carrying and status.canRoll and not status.rolling and not status.locked
	setBound(ROLL_ACTION, canRoll, onRoll, "Jogar dado", Enum.KeyCode.T, Enum.KeyCode.ButtonY)
	setBound(DROP_ACTION, carrying and not status.rolling, onDrop, "Soltar", Enum.KeyCode.G, Enum.KeyCode.ButtonB)
end

local function onStatus(payload)
	if type(payload) ~= "table" then
		return
	end
	status = {
		carrierUserId = type(payload.carrierUserId) == "number" and payload.carrierUserId or nil,
		canRoll = payload.canRoll == true,
		locked = payload.locked == true,
		rolling = payload.rolling == true,
	}
	refresh()
end

function BoardClient.Init()
	if initialized then
		return
	end
	initialized = true
	remotes.roll = Net.event(Net.Names.Board_RollRequest)
	remotes.drop = Net.event(Net.Names.Board_DropRequest)

	Net.event(Net.Names.Board_Status).OnClientEvent:Connect(onStatus)
	LocalPlayer:GetAttributeChangedSignal("Eliminated"):Connect(refresh)
	LocalPlayer.CharacterRemoving:Connect(function()
		status = nil
		refresh()
	end)
	refresh()
end

return BoardClient
