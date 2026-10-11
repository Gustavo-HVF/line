--!nonstrict
-- Efeitos rápidos pedidos pelo servidor (Fx_Play):
--   shake     → treme a câmera (fraco longe da origem)
--   tracer    → traço de tiro local que some (o atirador ignora o próprio eco)
--   knockback → soma velocidade no HumanoidRootPart do jogador local
--   flash     → a tela pisca numa cor
-- Tudo é local e leve: limites de quantidade e nada de loops quando não há efeito ativo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local UIKit = require(ReplicatedStorage.Shared.UI.UIKit)

local FxClient = {}

local LocalPlayer = Players.LocalPlayer

local MAX_SHAKES = 8
local MAX_TRACERS = 40
local MAX_KNOCKBACK = 300
local TRACER_LIFETIME = 0.15
local DEFAULT_SHAKE_RADIUS = 150

local initialized = false
local shakes = {}
local appliedOffset: CFrame? = nil
local appliedResult: CFrame? = nil
local tracers: { BasePart } = {}
local fxFolder: Folder? = nil
local flashFrame: Frame? = nil
local flashToken = 0

local function clampNumber(value: any, min: number, max: number, default: number): number
	if type(value) ~= "number" or value ~= value then
		return default
	end
	return math.clamp(value, min, max)
end

local function getFocusPosition(): Vector3
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = workspace.CurrentCamera
	return camera and camera.Focus.Position or Vector3.zero
end

-- Tremor -----------------------------------------------------------------------------------

local function addShake(params)
	if #shakes >= MAX_SHAKES then
		table.remove(shakes, 1)
	end
	table.insert(shakes, {
		intensity = clampNumber(params.intensity, 0.2, 2, 0.6),
		duration = clampNumber(params.duration, 0.05, 10, 0.5),
		origin = typeof(params.origin) == "Vector3" and params.origin or nil,
		radius = clampNumber(params.radius, 1, 5000, DEFAULT_SHAKE_RADIUS),
		started = os.clock(),
	})
end

-- Antes da câmera atualizar: desfaz o tremor do frame anterior (evita "deriva" da câmera).
local function undoShake()
	if not appliedOffset then
		return
	end
	local camera = workspace.CurrentCamera
	if camera and appliedResult and camera.CFrame:FuzzyEq(appliedResult, 1e-4) then
		camera.CFrame = camera.CFrame * appliedOffset:Inverse()
	end
	appliedOffset, appliedResult = nil, nil
end

-- Depois da câmera atualizar: aplica o tremor deste frame.
local function applyShake()
	if #shakes == 0 then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	local focus = getFocusPosition()
	local strength = 0
	for index = #shakes, 1, -1 do
		local shake = shakes[index]
		local elapsed = now - shake.started
		if elapsed >= shake.duration then
			table.remove(shakes, index)
		else
			local fade = 1 - elapsed / shake.duration
			local factor = 1
			if shake.origin then
				factor = math.clamp(1 - (focus - shake.origin).Magnitude / shake.radius, 0, 1)
			end
			strength += shake.intensity * fade * factor
		end
	end
	if strength <= 0.001 then
		return
	end
	strength = math.min(strength, 2.5)
	local t = now * 22
	local offset = CFrame.new(math.noise(t, 1.3) * 0.5 * strength, math.noise(t, 7.1) * 0.5 * strength, 0)
		* CFrame.Angles(
			math.rad(math.noise(t, 3.7) * 1.6 * strength),
			math.rad(math.noise(t, 5.9) * 1.6 * strength),
			math.rad(math.noise(t, 9.4) * 1.0 * strength)
		)
	local result = camera.CFrame * offset
	camera.CFrame = result
	appliedOffset, appliedResult = offset, result
end

-- Traço de tiro -------------------------------------------------------------------------------

local function addTracer(params)
	if params.shooterUserId == LocalPlayer.UserId then
		return -- o atirador já desenhou o próprio traço
	end
	local from, to = params.from, params.to
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	local delta = to - from
	local length = delta.Magnitude
	if length < 0.1 or length > 2000 then
		return
	end
	local width = clampNumber(params.width, 0.03, 1, 0.12)
	local color = typeof(params.color) == "Color3" and params.color or Color3.fromRGB(255, 226, 140)

	if not fxFolder or not fxFolder.Parent then
		local folder = Instance.new("Folder")
		folder.Name = "EfeitosLocais"
		folder.Parent = workspace
		fxFolder = folder
	end
	if #tracers >= MAX_TRACERS then
		local oldest = table.remove(tracers, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	local part = Instance.new("Part")
	part.Name = "Tracer"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.15
	part.Size = Vector3.new(width, width, length)
	part.CFrame = CFrame.lookAt(from + delta / 2, to)
	part.Parent = fxFolder :: Folder
	table.insert(tracers, part)

	local tween = TweenService:Create(part, TweenInfo.new(TRACER_LIFETIME), { Transparency = 1 })
	tween.Completed:Once(function()
		local index = table.find(tracers, part)
		if index then
			table.remove(tracers, index)
		end
		part:Destroy()
	end)
	tween:Play()
end

-- Empurrão --------------------------------------------------------------------------------------

local function applyKnockback(params)
	local velocity = params.velocity
	if typeof(velocity) ~= "Vector3" or velocity.Magnitude ~= velocity.Magnitude then
		return
	end
	if velocity.Magnitude > MAX_KNOCKBACK then
		velocity = velocity.Unit * MAX_KNOCKBACK
	end
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return
	end
	if velocity.Y > 5 then
		-- Tira o personagem do chão para o atrito não "comer" o empurrão.
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	root.AssemblyLinearVelocity += velocity
end

-- Clarão --------------------------------------------------------------------------------------

local function flash(params)
	if not flashFrame or not flashFrame.Parent then
		local gui = UIKit.ScreenGui("FlashFx", 50)
		flashFrame = UIKit.Create("Frame", {
			Name = "Clarao",
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Parent = gui,
		}) :: Frame
	end
	local frame = flashFrame :: Frame
	flashToken += 1
	local myToken = flashToken
	local duration = clampNumber(params.duration, 0.05, 3, 0.35)
	frame.BackgroundColor3 = typeof(params.color) == "Color3" and params.color or Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 0.25
	frame.Visible = true
	local tween = TweenService:Create(frame, TweenInfo.new(duration), { BackgroundTransparency = 1 })
	tween.Completed:Once(function()
		if myToken == flashToken then
			frame.Visible = false
		end
	end)
	tween:Play()
end

-- API -------------------------------------------------------------------------------------------

local HANDLERS = {
	shake = addShake,
	tracer = addTracer,
	knockback = applyKnockback,
	flash = flash,
}

function FxClient.Init()
	if initialized then
		return
	end
	initialized = true

	RunService:BindToRenderStep("SelvaTremorDesfaz", Enum.RenderPriority.Camera.Value - 1, undoShake)
	RunService:BindToRenderStep("SelvaTremor", Enum.RenderPriority.Camera.Value + 1, applyShake)

	Net.event(Net.Names.Fx_Play).OnClientEvent:Connect(function(kind, params)
		local handler = type(kind) == "string" and HANDLERS[kind]
		if not handler then
			return
		end
		local ok, err = pcall(handler, type(params) == "table" and params or {})
		if not ok then
			warn(("[FxClient] Erro no efeito '%s': %s"):format(kind, tostring(err)))
		end
	end)
end

return FxClient
