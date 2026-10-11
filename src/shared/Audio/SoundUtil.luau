--!nonstrict
-- Utilitário para tocar sons usando os ids de Config/Sounds.
-- Funciona no servidor (som replica para todos) e no cliente (som só local).

local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Sounds = require(script.Parent.Parent.Config.Sounds)

local SoundUtil = {}

-- Cria os SoundGroups no SoundService. Chame uma vez no servidor de cada place.
function SoundUtil.EnsureGroups()
	for _, groupName in Sounds.Groups do
		if not SoundService:FindFirstChild(groupName) then
			if RunService:IsClient() then
				SoundService:WaitForChild(groupName, 5)
			else
				local group = Instance.new("SoundGroup")
				group.Name = groupName
				group.Volume = 1
				group.Parent = SoundService
			end
		end
	end
end

function SoundUtil.GetGroup(groupKey: string): SoundGroup?
	local groupName = Sounds.Groups[groupKey] or groupKey
	return SoundService:FindFirstChild(groupName) :: SoundGroup?
end

export type PlayOptions = {
	Parent: Instance?, -- onde o som fica (part = som 3D)
	Position: Vector3?, -- cria um attachment temporário nessa posição (som 3D)
	Volume: number?,
	PlaybackSpeed: number?,
	Group: string?, -- "Music" | "Effects" | "Ambience" (padrão Effects)
	Looped: boolean?,
	RollOffMaxDistance: number?,
}

-- Toca um som pelo nome em Sounds.Ids. Retorna o Sound (ou nil se o id estiver vazio).
-- Sons não-looped são destruídos sozinhos ao terminar.
function SoundUtil.Play(name: string, options: PlayOptions?): Sound?
	local opts = options or {}
	local id = Sounds.Ids[name]
	if id == nil or id == "" then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = opts.Volume or 0.6
	sound.PlaybackSpeed = opts.PlaybackSpeed or 1
	sound.Looped = opts.Looped == true
	sound.RollOffMaxDistance = opts.RollOffMaxDistance or 250
	sound.SoundGroup = SoundUtil.GetGroup(opts.Group or "Effects")

	local holder: Instance = opts.Parent or SoundService
	if opts.Position then
		local attachment = Instance.new("Attachment")
		attachment.Name = "SoundAt_" .. name
		attachment.WorldPosition = opts.Position
		attachment.Parent = workspace.Terrain
		holder = attachment
		if not sound.Looped then
			Debris:AddItem(attachment, 30)
		end
	end
	sound.Parent = holder
	sound:Play()

	if not sound.Looped then
		sound.Ended:Once(function()
			if sound.Parent and sound.Parent:IsA("Attachment") and sound.Parent.Name:sub(1, 8) == "SoundAt_" then
				sound.Parent:Destroy()
			else
				sound:Destroy()
			end
		end)
		Debris:AddItem(sound, 30)
	end
	return sound
end

return SoundUtil
