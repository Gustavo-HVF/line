--!nonstrict
-- Entrada do servidor do LOBBY. Ordem do contrato:
--   SoundUtil.EnsureGroups → iluminação → LobbyWorld.Build → DemoRoom.Build → SettingsStore.Init →
--   PartyService.Init → TeleportHandler.Init
-- Cada etapa roda protegida: um erro numa delas não impede as outras de iniciar.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)

local LobbyWorld = require(script.Parent.LobbyWorld)
local PartyService = require(script.Parent.PartyService)
local TeleportHandler = require(script.Parent.TeleportHandler)

local EFFECT_PREFIX = "Lobby" -- efeitos de pós-processamento criados aqui

local function step(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(("[LobbyMain] Falha em %s: %s"):format(label, tostring(err)))
	end
end

-- Require de um módulo de outro dono, sem derrubar o lobby se ele faltar ou tiver erro.
local function requireModule(parent: Instance?, name: string): any
	local moduleScript = parent and parent:FindFirstChild(name)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		error(("módulo %s não encontrado"):format(name), 0)
	end
	return require(moduleScript)
end

-- Entardecer misterioso: sol baixo, céu alaranjado com névoa arroxeada e bastante contraste.
local function setupLighting()
	Lighting.ClockTime = 17.75
	Lighting.GeographicLatitude = 20
	Lighting.Brightness = 1.8
	Lighting.Ambient = Color3.fromRGB(34, 28, 40)
	Lighting.OutdoorAmbient = Color3.fromRGB(96, 74, 86)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 170, 110)
	Lighting.ColorShift_Bottom = Color3.fromRGB(40, 22, 52)
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.ExposureCompensation = 0.1
	-- Sombras: só o servidor mexe nelas, e só aqui na inicialização (depois o GraphicsApplier do cliente assume).
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3

	for _, child in Lighting:GetChildren() do
		if string.sub(child.Name, 1, #EFFECT_PREFIX) == EFFECT_PREFIX then
			child:Destroy()
		end
	end
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") then
			child:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "LobbyAtmosphere"
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(196, 140, 120)
	atmosphere.Decay = Color3.fromRGB(78, 54, 84)
	atmosphere.Glare = 0.4
	atmosphere.Haze = 1.6
	atmosphere.Parent = Lighting

	if not Lighting:FindFirstChildOfClass("Sky") then
		local sky = Instance.new("Sky")
		sky.Name = "LobbySky"
		sky.StarCount = 3000
		sky.SunAngularSize = 14
		sky.MoonAngularSize = 9
		sky.Parent = Lighting
	end

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "LobbyBloom"
	bloom.Intensity = 0.5
	bloom.Size = 28
	bloom.Threshold = 1.4
	bloom.Parent = Lighting

	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "LobbyColor"
	color.Brightness = 0.02
	color.Contrast = 0.12
	color.Saturation = 0.05
	color.TintColor = Color3.fromRGB(255, 238, 224)
	color.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Name = "LobbySunRays"
	rays.Intensity = 0.06
	rays.Spread = 0.6
	rays.Parent = Lighting
end

step("SoundUtil.EnsureGroups", SoundUtil.EnsureGroups)
step("iluminação", setupLighting)
step("LobbyWorld.Build", function()
	LobbyWorld.Build()
end)
step("DemoRoom.Build", function()
	requireModule(script.Parent, "DemoRoom").Build()
end)
step("SettingsStore.Init", function()
	requireModule(ServerScriptService:FindFirstChild("ServerShared"), "SettingsStore").Init()
end)
step("PartyService.Init", PartyService.Init)
step("TeleportHandler.Init", TeleportHandler.Init)
