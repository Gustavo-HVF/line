--!nonstrict
-- Câmera cinematográfica do menu principal.
-- Fica no marcador workspace.LobbyMarkers.MenuCamera (criado pelo LobbyWorld) com uma leve "respiração",
-- uma aproximação lenta quando o menu aparece e um pouco de paralaxe seguindo o mouse (PC).
--
--   MenuCamera.Start(withIntro?)   -- câmera Scriptable no enquadramento do menu (animada)
--   MenuCamera.Pause()             -- para a animação e deixa a câmera parada no enquadramento
--   MenuCamera.Stop()              -- devolve a câmera ao personagem (Custom)
--   MenuCamera.PlayIntro()         -- reinicia a aproximação
--   MenuCamera.WaitForMarker(timeout): boolean

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local MenuCamera = {}

local BIND_NAME = "LobbyMenuCamera"
local MENU_FOV = 55
local DEFAULT_FOV = 70
local INTRO_TIME = 4.5
local INTRO_DISTANCE = 3.5

local running = false
local baseCFrame: CFrame? = nil
local watching = false
local introActive = false
local introStart = 0
local parallax = Vector2.zero

-- Mesmo enquadramento do LobbyWorld; só é usado até o marcador chegar do servidor.
local function fallbackCFrame(): CFrame
	local position = GameConfig.MENU_AREA_ORIGIN + Vector3.new(-4, 8.5, 9)
	return CFrame.lookAt(position, position + Vector3.new(0, -0.306, -1))
end

local function watchMarker()
	if watching then
		return
	end
	watching = true
	task.spawn(function()
		local markers = workspace:WaitForChild("LobbyMarkers", 60)
		local marker = markers and markers:WaitForChild("MenuCamera", 60)
		if marker and marker:IsA("BasePart") then
			baseCFrame = marker.CFrame
		else
			warn("[MenuCamera] Marcador MenuCamera não encontrado; usando o enquadramento padrão.")
		end
	end)
end

function MenuCamera.GetCFrame(): CFrame
	return baseCFrame or fallbackCFrame()
end

-- Espera o marcador (até `timeout` segundos). Retorna true se ele chegou.
function MenuCamera.WaitForMarker(timeout: number): boolean
	watchMarker()
	local deadline = os.clock() + timeout
	while not baseCFrame and os.clock() < deadline do
		task.wait(0.1)
	end
	return baseCFrame ~= nil
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	local now = os.clock()

	-- aproximação inicial (dolly-in suave)
	local push = 0
	if introActive then
		local alpha = math.clamp((now - introStart) / INTRO_TIME, 0, 1)
		push = (1 - alpha) ^ 3 * INTRO_DISTANCE -- começa afastada e desacelera ao chegar
		if alpha >= 1 then
			introActive = false
		end
	end

	-- paralaxe: a câmera olha um pouquinho na direção do mouse
	local target = Vector2.zero
	if UserInputService.MouseEnabled then
		local viewport = camera.ViewportSize
		if viewport.X > 0 and viewport.Y > 0 then
			local mouse = UserInputService:GetMouseLocation()
			target = Vector2.new(
				math.clamp(mouse.X / viewport.X - 0.5, -0.5, 0.5),
				math.clamp(mouse.Y / viewport.Y - 0.5, -0.5, 0.5)
			)
		end
	end
	parallax = parallax:Lerp(target, math.min(1, dt * 2.5))

	local breathe = CFrame.new(
		math.sin(now * 0.31) * 0.16,
		math.sin(now * 0.47) * 0.09,
		push + math.sin(now * 0.23) * 0.1
	) * CFrame.Angles(
		math.sin(now * 0.37) * 0.005 - parallax.Y * 0.025,
		math.sin(now * 0.29) * 0.008 - parallax.X * 0.045,
		math.sin(now * 0.21) * 0.003
	)
	camera.CFrame = MenuCamera.GetCFrame() * breathe
	camera.FieldOfView = MENU_FOV
end

function MenuCamera.PlayIntro()
	introActive = true
	introStart = os.clock()
end

function MenuCamera.Start(withIntro: boolean?)
	watchMarker()
	if withIntro then
		MenuCamera.PlayIntro()
	end
	if running then
		return
	end
	running = true
	parallax = Vector2.zero
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = MenuCamera.GetCFrame()
		camera.FieldOfView = MENU_FOV
	end
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, update)
end

local function unbind()
	if running then
		running = false
		RunService:UnbindFromRenderStep(BIND_NAME)
	end
end

-- Para a animação mantendo a câmera parada no enquadramento do menu (ex.: antes de abrir as configurações,
-- que guardam e depois restauram a câmera).
function MenuCamera.Pause()
	unbind()
	introActive = false
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = MenuCamera.GetCFrame()
		camera.FieldOfView = MENU_FOV
	end
end

-- Devolve a câmera ao personagem.
function MenuCamera.Stop()
	unbind()
	introActive = false
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera.FieldOfView = DEFAULT_FOV
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	camera.CameraType = Enum.CameraType.Custom
end

function MenuCamera.IsRunning(): boolean
	return running
end

return MenuCamera
