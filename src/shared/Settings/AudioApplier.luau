--!nonstrict
-- Aplica as configurações de áudio no cliente.
-- Cada SoundGroup de Config/Sounds.Groups recebe volume = geral × volume do grupo:
--   Music → music, Effects → effects, Ambience → ambience.
-- A mudança é local (só este jogador ouve diferente). Os grupos são criados pelo servidor
-- (SoundUtil.EnsureGroups); se ainda não existirem, o volume é aplicado assim que aparecerem.

local SoundService = game:GetService("SoundService")

local Sounds = require(script.Parent.Parent.Config.Sounds)
local SettingsSchema = require(script.Parent.SettingsSchema)

local AudioApplier = {}

-- Chave do grupo em Sounds.Groups → campo correspondente em AudioSettings.
local GROUP_FIELDS = {
	Music = "music",
	Effects = "effects",
	Ambience = "ambience",
}

-- Nome do SoundGroup no SoundService → chave do grupo.
local groupKeyByName = {}
for groupKey, groupName in Sounds.Groups do
	groupKeyByName[groupName] = groupKey
end

local latest = nil -- últimas configurações de áudio aplicadas (já validadas)
local watchConnection: RBXScriptConnection? = nil

local function volumeFor(groupKey: string, audio): number
	local field = GROUP_FIELDS[groupKey]
	local groupValue = field and audio[field] or 1
	return math.clamp(audio.master * groupValue, 0, 1)
end

local function applyToGroup(group: Instance)
	if not latest or not group:IsA("SoundGroup") then
		return
	end
	local groupKey = groupKeyByName[group.Name]
	if not groupKey then
		return
	end
	local volume = volumeFor(groupKey, latest)
	if math.abs(group.Volume - volume) > 1e-4 then
		group.Volume = volume
	end
end

-- Ajusta o volume dos SoundGroups. Não cede (pode ser chamado a cada movimento de um slider).
function AudioApplier.Apply(audio)
	latest = SettingsSchema.Sanitize({ audio = audio }).audio

	for _, groupName in Sounds.Groups do
		local group = SoundService:FindFirstChild(groupName)
		if group then
			applyToGroup(group)
		end
	end

	-- Grupos que ainda não chegaram do servidor (ou que forem recriados) recebem o volume ao aparecer.
	if not watchConnection then
		watchConnection = SoundService.ChildAdded:Connect(applyToGroup)
	end
end

-- Volume final de um grupo ("Music" | "Effects" | "Ambience") com as configurações atuais.
function AudioApplier.GetVolume(groupKey: string): number
	if not latest then
		return 1
	end
	return volumeFor(groupKey, latest)
end

return AudioApplier
