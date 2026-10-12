--!nonstrict
-- Efeitos locais das armas (nada aqui replica):
--   * traço do tiro, clarão do cano, faísca do impacto e o marcador do alvo da dinamite;
--   * animações por Tool.Grip (golpe estilo espada clássica, coice das armas, arremesso) e a animação de
--     braço padrão ("toolanim" Slash, lida pelo script Animate do personagem e replicada pelo Roblox);
--   * reação às armas dos OUTROS jogadores: o servidor sobe os atributos FireSeq/SwingSeq/ThrowSeq e
--     Reloading, e aqui tocamos som, clarão e animação de Grip na arma deles.
-- Limites de quantidade e nenhum loop rodando quando não há animação ativa.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local Tags = require(ReplicatedStorage.Shared.Tags)

local WeaponFx = {}

local LocalPlayer = Players.LocalPlayer

local FOLDER_NAME = "EfeitosArmas"
local MAX_TRACERS = 30
local MAX_IMPACTS = 12
local TRACER_LIFETIME = 0.12
local IMPACT_LIFETIME = 0.18
local FLASH_LIFETIME = 0.06
local FLASH_COLOR = Color3.fromRGB(255, 214, 120)
local MARKER_COLOR = Color3.fromRGB(255, 140, 50)
local REMOTE_FX_DISTANCE = 260 -- armas de outros jogadores mais longe que isto: sem efeito local

-- Animações de Grip: chaves { tempo, ângulo (graus, em torno do eixo X da mão), deslocamento em Z }.
-- O Grip final é Grip original * CFrame.new(0, 0, z) * CFrame.Angles(ângulo, 0, 0).
-- Ângulo positivo leva o topo da arma para a frente (lâmina "para fora"); negativo, para trás/cano para cima.
type GripKey = { number }
type GripAnim = { duration: number, keys: { GripKey } }

local GRIP_ANIMS: { [string]: GripAnim } = {
	swing = {
		duration = 0.42,
		keys = { { 0, 0, 0 }, { 0.06, -45, 0 }, { 0.16, 80, 0.1 }, { 0.3, 60, 0 }, { 0.42, 0, 0 } },
	},
	throw = {
		duration = 0.38,
		keys = { { 0, 0, 0 }, { 0.09, -60, -0.5 }, { 0.2, 70, 0.6 }, { 0.38, 0, 0 } },
	},
	-- Coice: o ângulo e o recuo são multiplicados pela força (graus do atributo Recoil / 10).
	recoil = {
		duration = 0.22,
		keys = { { 0, 0, 0 }, { 0.04, -10, -0.25 }, { 0.22, 0, 0 } },
	},
}

local folder: Folder? = nil
local tracers: { BasePart } = {}
local impacts: { BasePart } = {}
local baseGrips: { [Tool]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local activeAnims: { [Tool]: { anim: GripAnim, started: number, scale: number, base: CFrame } } = {}
local animLoop: RBXScriptConnection? = nil
local marker: BasePart? = nil
local markerDot: BasePart? = nil
local watched: { [Instance]: { RBXScriptConnection } } = {}
local initialized = false

-- Peças locais -----------------------------------------------------------------------------------------

local function getFolder(): Folder
	local current = folder
	if current and current.Parent then
		return current
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = workspace
	folder = created
	return created
end

local function fxPart(name: string, size: Vector3, cframe: CFrame, color: Color3, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	if shape then
		part.Shape = shape
	end
	part.Size = size
	part.CFrame = cframe
	return part
end

local function pushLimited(list: { BasePart }, part: BasePart, limit: number)
	if #list >= limit then
		local oldest = table.remove(list, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	table.insert(list, part)
end

local function fadeAndRemove(list: { BasePart }, part: BasePart, duration: number)
	local tween = TweenService:Create(part, TweenInfo.new(duration), { Transparency = 1 })
	tween.Completed:Once(function()
		local index = table.find(list, part)
		if index then
			table.remove(list, index)
		end
		part:Destroy()
	end)
	tween:Play()
end

-- Traço de tiro local (o mesmo visual do FxClient; o atirador desenha o próprio na hora).
function WeaponFx.Tracer(from: Vector3, to: Vector3, color: Color3?, width: number?)
	local delta = to - from
	local length = delta.Magnitude
	if length < 0.1 or length > 2000 then
		return
	end
	local size = math.clamp(width or 0.1, 0.03, 1)
	local part =
		fxPart("Tracer", Vector3.new(size, size, length), CFrame.lookAt(from + delta / 2, to), color or FLASH_COLOR)
	part.Transparency = 0.15
	part.Parent = getFolder()
	pushLimited(tracers, part, MAX_TRACERS)
	fadeAndRemove(tracers, part, TRACER_LIFETIME)
end

-- Faísca no ponto atingido.
function WeaponFx.Impact(position: Vector3, color: Color3?)
	local part = fxPart("Impacto", Vector3.new(0.35, 0.35, 0.35), CFrame.new(position), color or FLASH_COLOR)
	part.Transparency = 0.1
	part.Parent = getFolder()
	pushLimited(impacts, part, MAX_IMPACTS)
	fadeAndRemove(impacts, part, IMPACT_LIFETIME)
end

-- Clarão rápido na boca do cano (bola de neon + luz).
function WeaponFx.MuzzleFlash(position: Vector3)
	local part = fxPart("Clarao", Vector3.new(0.7, 0.7, 0.7), CFrame.new(position), FLASH_COLOR, Enum.PartType.Ball)
	part.Transparency = 0.2
	local light = Instance.new("PointLight")
	light.Color = FLASH_COLOR
	light.Brightness = 4
	light.Range = 12
	light.Shadows = false
	light.Parent = part
	part.Parent = getFolder()
	task.delay(FLASH_LIFETIME, function()
		part:Destroy()
	end)
end

-- Ponto de saída do tiro: o Attachment "Muzzle" do Handle (ou o próprio Handle).
function WeaponFx.GetMuzzle(tool: Tool): Vector3?
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return nil
	end
	local muzzle = handle:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	return handle.Position
end

-- Marcador do alvo da dinamite (disco do tamanho da explosão + ponto central). nil esconde.
function WeaponFx.SetMarker(position: Vector3?, radius: number?)
	if not position then
		if marker then
			marker.Parent = nil
		end
		if markerDot then
			markerDot.Parent = nil
		end
		return
	end
	local diameter = math.clamp((radius or 14) * 2, 2, 60)
	if not marker then
		local disc = fxPart("AlvoDinamite", Vector3.new(0.1, diameter, diameter), CFrame.new(), MARKER_COLOR)
		disc.Shape = Enum.PartType.Cylinder
		disc.Material = Enum.Material.SmoothPlastic
		disc.Transparency = 0.75
		marker = disc
		local dot = fxPart("AlvoCentro", Vector3.new(0.12, 1.2, 1.2), CFrame.new(), MARKER_COLOR)
		dot.Shape = Enum.PartType.Cylinder
		dot.Transparency = 0.2
		markerDot = dot
	end
	local disc = marker :: BasePart
	local dot = markerDot :: BasePart
	if disc.Size.Y ~= diameter then
		disc.Size = Vector3.new(0.1, diameter, diameter)
	end
	-- Cilindro deitado: o eixo (X) aponta para cima.
	local flat = CFrame.new(position + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
	disc.CFrame = flat
	dot.CFrame = flat * CFrame.new(0.02, 0, 0)
	local parent = getFolder()
	disc.Parent = parent
	dot.Parent = parent
end

-- Animações de Grip -------------------------------------------------------------------------------------

-- Ajusta o C1 das soldas "RightGrip" que prendem o Handle na mão (pode haver mais de uma no cliente
-- dono: a local, criada ao equipar, e a replicada pelo servidor).
local function setGripJoints(tool: Tool, grip: CFrame)
	local handle = tool:FindFirstChild("Handle")
	local character = tool.Parent
	if not handle or not character then
		return
	end
	for _, handName in { "RightHand", "Right Arm" } do
		local hand = character:FindFirstChild(handName)
		if hand then
			for _, child in hand:GetChildren() do
				if child.Name == "RightGrip" and child:IsA("JointInstance") and child.Part1 == handle then
					if child.C1 ~= grip then
						child.C1 = grip
					end
				end
			end
		end
	end
end

local function applyGrip(tool: Tool, grip: CFrame)
	-- A solda da mão normalmente acompanha o Tool.Grip; ajustar o C1 garante o mesmo resultado localmente.
	tool.Grip = grip
	setGripJoints(tool, grip)
end

local function smooth(alpha: number): number
	return alpha * alpha * (3 - 2 * alpha)
end

local function sampleGrip(anim: GripAnim, elapsed: number, scale: number): CFrame
	local keys = anim.keys
	for index = 1, #keys - 1 do
		local a, b = keys[index], keys[index + 1]
		if elapsed <= b[1] then
			local span = math.max(b[1] - a[1], 1e-3)
			local alpha = smooth(math.clamp((elapsed - a[1]) / span, 0, 1))
			local angle = (a[2] + (b[2] - a[2]) * alpha) * scale
			local z = (a[3] + (b[3] - a[3]) * alpha) * scale
			return CFrame.new(0, 0, z) * CFrame.Angles(math.rad(angle), 0, 0)
		end
	end
	return CFrame.new()
end

local function stepAnims()
	local now = os.clock()
	for tool, state in activeAnims do
		local elapsed = now - state.started
		if not tool.Parent then
			activeAnims[tool] = nil
		elseif elapsed >= state.anim.duration then
			applyGrip(tool, state.base)
			activeAnims[tool] = nil
		else
			applyGrip(tool, state.base * sampleGrip(state.anim, elapsed, state.scale))
		end
	end
	if next(activeAnims) == nil and animLoop then
		animLoop:Disconnect()
		animLoop = nil
	end
end

-- Toca uma animação de Grip ("swing" | "throw" | "recoil"). `scale` multiplica ângulos e recuo.
function WeaponFx.PlayGrip(tool: Tool, name: string, scale: number?)
	local anim = GRIP_ANIMS[name]
	if not anim or not tool.Parent then
		return
	end
	local current = activeAnims[tool]
	local base = if current then current.base else baseGrips[tool]
	if not base then
		base = tool.Grip
		baseGrips[tool] = base
	end
	activeAnims[tool] = { anim = anim, started = os.clock(), scale = scale or 1, base = base }
	if not animLoop then
		animLoop = RunService.Heartbeat:Connect(stepAnims)
	end
end

-- Volta o Grip ao original (ao guardar a arma no meio de uma animação).
function WeaponFx.ResetGrip(tool: Tool)
	local state = activeAnims[tool]
	activeAnims[tool] = nil
	local base = (state and state.base) or baseGrips[tool]
	if base then
		applyGrip(tool, base)
	end
end

-- Animação de braço padrão do Roblox (o script Animate do personagem lê o StringValue "toolanim").
function WeaponFx.PlayToolAnim(tool: Tool, animName: string)
	local value = Instance.new("StringValue")
	value.Name = "toolanim"
	value.Value = animName
	value.Parent = tool
	task.delay(1, function()
		value:Destroy()
	end)
end

-- Armas dos outros jogadores ------------------------------------------------------------------------------

-- Personagem (de outro jogador) que segura a arma, se estiver perto o bastante para valer o efeito.
local function remoteHolder(tool: Tool): Model?
	local character = tool.Parent
	if not character or not character:IsA("Model") or character == LocalPlayer.Character then
		return nil
	end
	if not character:FindFirstChildOfClass("Humanoid") then
		return nil
	end
	local handle = tool:FindFirstChild("Handle")
	local camera = workspace.CurrentCamera
	if not handle or not handle:IsA("BasePart") or not camera then
		return nil
	end
	if (handle.Position - camera.CFrame.Position).Magnitude > REMOTE_FX_DISTANCE then
		return nil
	end
	return character
end

local function playToolSound(tool: Tool, soundName: any, volume: number)
	local handle = tool:FindFirstChild("Handle")
	if type(soundName) == "string" and handle then
		SoundUtil.Play(soundName, { Parent = handle, Volume = volume, RollOffMaxDistance = 300 })
	end
end

local function onRemoteFire(tool: Tool)
	if not remoteHolder(tool) then
		return
	end
	playToolSound(tool, tool:GetAttribute("UseSound"), 0.8)
	local muzzle = WeaponFx.GetMuzzle(tool)
	if muzzle then
		WeaponFx.MuzzleFlash(muzzle)
	end
	WeaponFx.PlayGrip(tool, "recoil", (tonumber(tool:GetAttribute("Recoil")) or 10) / 10)
end

local function onRemoteSwing(tool: Tool, gripName: string)
	if not remoteHolder(tool) then
		return
	end
	playToolSound(tool, tool:GetAttribute("UseSound"), 0.6)
	WeaponFx.PlayGrip(tool, gripName)
end

local function onRemoteReload(tool: Tool)
	if tool:GetAttribute("Reloading") == true and remoteHolder(tool) then
		playToolSound(tool, "Reload", 0.6)
	end
end

local function unwatch(instance: Instance)
	local connections = watched[instance]
	watched[instance] = nil
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
	end
end

local function watch(instance: Instance)
	if watched[instance] or not instance:IsA("Tool") then
		return
	end
	local tool = instance :: Tool
	watched[tool] = {
		tool:GetAttributeChangedSignal("FireSeq"):Connect(function()
			onRemoteFire(tool)
		end),
		tool:GetAttributeChangedSignal("SwingSeq"):Connect(function()
			onRemoteSwing(tool, "swing")
		end),
		tool:GetAttributeChangedSignal("ThrowSeq"):Connect(function()
			onRemoteSwing(tool, "throw")
		end),
		tool:GetAttributeChangedSignal("Reloading"):Connect(function()
			onRemoteReload(tool)
		end),
	}
end

function WeaponFx.Init()
	if initialized then
		return
	end
	initialized = true
	CollectionService:GetInstanceAddedSignal(Tags.Weapon):Connect(watch)
	CollectionService:GetInstanceRemovedSignal(Tags.Weapon):Connect(unwatch)
	for _, instance in CollectionService:GetTagged(Tags.Weapon) do
		watch(instance)
	end
end

return WeaponFx
