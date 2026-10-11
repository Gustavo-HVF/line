--!nonstrict
-- Formato das configurações do jogador, valores padrão e validação.
-- Usado pelo cliente (UI) e pelo servidor (DataStore) para garantir dados válidos.

local GameConfig = require(script.Parent.Parent.Config.GameConfig)

export type AudioSettings = {
	master: number, -- 0..1
	music: number, -- 0..1
	effects: number, -- 0..1
	ambience: number, -- 0..1
}

export type GraphicsSettings = {
	shadows: string, -- "off" | "low" | "high"
	reducedTextures: boolean,
	renderDistance: number, -- índice em GameConfig.RENDER_DISTANCES (1..4)
	preload: boolean, -- pré-carregar o jogo na tela de carregamento
}

export type Settings = {
	version: number,
	audio: AudioSettings,
	graphics: GraphicsSettings,
}

local SettingsSchema = {}

SettingsSchema.VERSION = 1
SettingsSchema.SHADOW_OPTIONS = { "off", "low", "high" }
SettingsSchema.SHADOW_LABELS = { off = "Desligadas", low = "Baixas", high = "Altas" }

function SettingsSchema.Defaults(): Settings
	return {
		version = SettingsSchema.VERSION,
		audio = {
			master = 0.8,
			music = 0.6,
			effects = 0.8,
			ambience = 0.7,
		},
		graphics = {
			shadows = "high",
			reducedTextures = false,
			renderDistance = 3,
			preload = true,
		},
	}
end

local function clampNumber(value: any, min: number, max: number, default: number): number
	if type(value) ~= "number" or value ~= value then
		return default
	end
	return math.clamp(value, min, max)
end

-- Recebe qualquer valor (vindo do cliente ou do DataStore) e devolve configurações válidas.
function SettingsSchema.Sanitize(input: any): Settings
	local defaults = SettingsSchema.Defaults()
	if type(input) ~= "table" then
		return defaults
	end
	local audio = type(input.audio) == "table" and input.audio or {}
	local graphics = type(input.graphics) == "table" and input.graphics or {}

	local result = SettingsSchema.Defaults()
	for key, default in defaults.audio do
		result.audio[key] = clampNumber(audio[key], 0, 1, default)
	end

	if table.find(SettingsSchema.SHADOW_OPTIONS, graphics.shadows) then
		result.graphics.shadows = graphics.shadows
	end
	if type(graphics.reducedTextures) == "boolean" then
		result.graphics.reducedTextures = graphics.reducedTextures
	end
	result.graphics.renderDistance = math.floor(
		clampNumber(graphics.renderDistance, 1, #GameConfig.RENDER_DISTANCES, defaults.graphics.renderDistance)
	)
	if type(graphics.preload) == "boolean" then
		result.graphics.preload = graphics.preload
	end
	return result
end

-- Cópia profunda simples (as configurações só têm tabelas, números, strings e booleanos).
function SettingsSchema.Clone(settings: Settings): Settings
	local function copy(value)
		if type(value) ~= "table" then
			return value
		end
		local out = {}
		for k, v in value do
			out[k] = copy(v)
		end
		return out
	end
	return copy(settings)
end

function SettingsSchema.RenderDistanceStuds(settings: Settings): number
	return GameConfig.RENDER_DISTANCES[settings.graphics.renderDistance] or GameConfig.RENDER_DISTANCES[3]
end

return SettingsSchema
