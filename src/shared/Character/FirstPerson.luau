--!nonstrict
-- Câmera em primeira pessoa (somente cliente).
--   * CameraMode = LockFirstPerson;
--   * o próprio corpo continua visível (braços, tronco, pernas e ferramentas); só a cabeça, o rosto e os
--     acessórios somem, para não taparem a visão;
--   * a câmera fica um pouco à frente do rosto (Humanoid.CameraOffset) e balança com os passos
--     (mais forte correndo), com um "afundar" ao cair de altura.
--
--   FirstPerson.Enable()   -- hub do lobby e partida
--   FirstPerson.Disable()  -- menu, espectador e cutscenes (volta à câmera clássica)
--   FirstPerson.IsEnabled(): boolean
--   FirstPerson.SetClimbing(climbing)  -- encostado na parede: a câmera não avança (não atravessa a parede)
--
-- O balanço segue o padrão do FxClient: desfaz o deslocamento antes da câmera do Roblox atualizar e
-- reaplica depois, para não acumular rotação de um frame para o outro.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local FirstPerson = {}

local UNDO_STEP = "SelvaPrimeiraPessoaDesfaz"
local APPLY_STEP = "SelvaPrimeiraPessoa"
local BODY_STEP = "SelvaCorpoVisivel"
local FORWARD_OFFSET = 0.7 -- studs à frente do rosto
local RUN_SPEED = 20
local DEFAULT_MAX_ZOOM = 12

local LocalPlayer = Players.LocalPlayer

local enabled = false
local climbing = false
local applied = CFrame.identity
local bobPhase = 0
local wasAirborne = false
local fallSpeed = 0
local landDip = 0
local smoothedSpeed = 0

local hiddenParts: { [BasePart]: boolean } = {}
local visibleParts: { [BasePart]: boolean } = {}
local trackedCharacter: Model? = nil
local characterConnections: { RBXScriptConnection } = {}

-- Corpo visível -------------------------------------------------------------------------------------

local function shouldHide(part: BasePart, character: Model): boolean
	if part.Name == "Head" and part.Parent == character then
		return true
	end
	return part:FindFirstAncestorOfClass("Accessory") ~= nil or part:FindFirstAncestorOfClass("Accoutrement") ~= nil
end

local function classify(instance: Instance, character: Model)
	if instance:IsA("BasePart") then
		if shouldHide(instance, character) then
			hiddenParts[instance] = true
		elseif instance.Name ~= "HumanoidRootPart" then
			visibleParts[instance] = true
		end
	end
end

local function clearCharacter()
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	for part in hiddenParts do
		part.LocalTransparencyModifier = 0
	end
	table.clear(hiddenParts)
	table.clear(visibleParts)
	trackedCharacter = nil
end

local function trackCharacter(character: Model?)
	if character == trackedCharacter then
		return
	end
	clearCharacter()
	if not character then
		return
	end
	trackedCharacter = character
	for _, descendant in character:GetDescendants() do
		classify(descendant, character)
	end
	table.insert(
		characterConnections,
		character.DescendantAdded:Connect(function(descendant)
			classify(descendant, character)
		end)
	)
	table.insert(
		characterConnections,
		character.DescendantRemoving:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				hiddenParts[descendant] = nil
				visibleParts[descendant] = nil
			end
		end)
	)
end

local function updateBody()
	local character = LocalPlayer.Character
	trackCharacter(character)
	if not character then
		return
	end
	local camera = workspace.CurrentCamera
	local head = character:FindFirstChild("Head")
	-- Só esconde a cabeça quando a câmera está realmente nela (primeira pessoa de verdade).
	local inside = camera ~= nil
		and head ~= nil
		and head:IsA("BasePart")
		and (camera.CFrame.Position - head.Position).Magnitude < 2.5
	for part in hiddenParts do
		part.LocalTransparencyModifier = if inside then 1 else 0
	end
	for part in visibleParts do
		part.LocalTransparencyModifier = 0
	end
	-- O rosto (Decal na cabeça) some junto com a cabeça.
	if head then
		local face = head:FindFirstChildOfClass("Decal")
		if face then
			face.LocalTransparencyModifier = if inside then 1 else 0
		end
	end
end

-- Balanço da câmera ----------------------------------------------------------------------------------

local function undoBob()
	local camera = workspace.CurrentCamera
	if camera and applied ~= CFrame.identity then
		camera.CFrame = camera.CFrame * applied:Inverse()
	end
	applied = CFrame.identity
end

local function applyBob(dt: number)
	local camera = workspace.CurrentCamera
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if
		not camera
		or camera.CameraType ~= Enum.CameraType.Custom
		or not humanoid
		or humanoid.Health <= 0
		or not root
		or not root:IsA("BasePart")
	then
		return
	end
	dt = math.min(dt, 0.1)
	humanoid.CameraOffset = Vector3.new(0, 0, if climbing then 0 else -FORWARD_OFFSET)

	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local airborne = humanoid.FloorMaterial == Enum.Material.Air
	if airborne then
		fallSpeed = math.min(fallSpeed, velocity.Y)
	elseif wasAirborne then
		-- pousou: afunda proporcional à velocidade da queda
		landDip = math.max(landDip, math.clamp(-fallSpeed / 70, 0, 0.7))
		fallSpeed = 0
	end
	wasAirborne = airborne
	landDip = math.max(landDip - dt * 2.2, 0)

	local target = if airborne or climbing then 0 else speed
	smoothedSpeed += (target - smoothedSpeed) * math.min(dt * 10, 1)
	local running = smoothedSpeed > RUN_SPEED - 2
	bobPhase += dt * smoothedSpeed * (if running then 0.62 else 0.75)
	local intensity = math.clamp(smoothedSpeed / 16, 0, 1.5)
	local amplitude = if running then 0.16 else 0.1

	local now = os.clock()
	local breathe = math.sin(now * 1.6) * 0.025
	local bobY = math.abs(math.sin(bobPhase)) * amplitude * intensity
	local swayX = math.cos(bobPhase) * amplitude * 0.6 * intensity
	local roll = math.cos(bobPhase) * math.rad(if running then 1.1 else 0.6) * intensity
	if climbing then
		bobY = math.sin(now * 7) * 0.05 * math.clamp(math.abs(velocity.Y) / 8, 0, 1)
	end

	local offset = CFrame.new(swayX, bobY + breathe - landDip, 0) * CFrame.Angles(0, 0, roll)
	camera.CFrame = camera.CFrame * offset
	applied = offset
end

-- API ---------------------------------------------------------------------------------------------

function FirstPerson.Enable()
	if enabled then
		return
	end
	enabled = true
	LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
	LocalPlayer.CameraMinZoomDistance = 0.5
	applied = CFrame.identity
	RunService:BindToRenderStep(UNDO_STEP, Enum.RenderPriority.Camera.Value - 2, undoBob)
	RunService:BindToRenderStep(APPLY_STEP, Enum.RenderPriority.Camera.Value + 2, applyBob)
	RunService:BindToRenderStep(BODY_STEP, Enum.RenderPriority.Camera.Value + 3, updateBody)
end

function FirstPerson.Disable()
	if not enabled then
		return
	end
	enabled = false
	RunService:UnbindFromRenderStep(UNDO_STEP)
	RunService:UnbindFromRenderStep(APPLY_STEP)
	RunService:UnbindFromRenderStep(BODY_STEP)
	undoBob()
	clearCharacter()
	LocalPlayer.CameraMode = Enum.CameraMode.Classic
	LocalPlayer.CameraMaxZoomDistance = DEFAULT_MAX_ZOOM
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.CameraOffset = Vector3.zero
	end
end

function FirstPerson.IsEnabled(): boolean
	return enabled
end

function FirstPerson.SetClimbing(value: boolean)
	climbing = value == true
end

return FirstPerson
