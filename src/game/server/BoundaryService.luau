--!nonstrict
-- Borda da ilha (servidor): quem passa do raio da ilha (mais a margem) ou afunda abaixo do nível do mar
-- é eliminado. A morte é tratada pelo MatchService (Humanoid.Died -> eliminado com o motivo abaixo).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local CombatUtil = require(script.Parent.CombatUtil)

local BoundaryService = {}

local CHECK_INTERVAL = 0.25
local REASON = "Saiu da ilha"
local BELOW_WATER = 4 -- studs abaixo do nível do mar

local initialized = false

function BoundaryService.Init(mapInfo)
	if initialized then
		return
	end
	initialized = true

	local center: Vector3 = mapInfo.islandCenter or GameConfig.ISLAND_CENTER
	local limit: number = (mapInfo.islandRadius or GameConfig.ISLAND_RADIUS) + GameConfig.ELIMINATION_MARGIN
	local minY: number = (mapInfo.waterLevelY or GameConfig.WATER_LEVEL_Y) - BELOW_WATER

	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			for _, player in Players:GetPlayers() do
				if CombatUtil.IsPlayerAlive(player) then
					local character = player.Character
					local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					local position = root.Position
					local horizontal = Vector3.new(position.X - center.X, 0, position.Z - center.Z).Magnitude
					if humanoid and (horizontal > limit or position.Y < minY) then
						player:SetAttribute("LastDamageSource", REASON)
						humanoid.Health = 0
					end
				end
			end
		end
	end)
end

return BoundaryService
