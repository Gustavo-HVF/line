--!nonstrict
-- Evento de NPC "Enxame de Mosquitos": 8 a 12 mosquitos gigantes (mais com mais jogadores) chegam em 2
-- ondas. Eles circulam em volta dos jogadores e dão rasantes; a picada machuca e dá febre (IA do
-- Mosquito). Termina quando o enxame inteiro morre (ou ao fim da duração).

local NpcEventUtil = require(script.Parent.Parent.EventHelpers.NpcEventUtil)
local Effects = require(script.Parent.Parent.NPC.Effects)

local MIN_COUNT, MAX_COUNT = 8, 12
local WAVE_INTERVAL = 25

return {
	Id = "Mosquitos",
	DisplayName = "Enxame de Mosquitos",
	Kind = "npc",
	Riddles = {
		"Um zumbido agudo cresce no ar;\npicadas gigantes vêm te encontrar.",
		"Pequenos vampiros de asas ligeiras;\nsua sede de sangue não tem fronteiras.",
		"Abane os braços e não fique parado;\no enxame faminto chega de todo lado.",
	},
	Weight = 1,
	MinSpace = 1,
	Duration = 75,
	Radius = 50,

	Start = function(ctx)
		local session = NpcEventUtil.new(ctx, "Mosquitos")
		local rng: Random = ctx.random
		local players = NpcEventUtil.AlivePlayerCount(ctx)
		local total = math.clamp(MIN_COUNT + (players - 1) + rng:NextInteger(0, 1), MIN_COUNT, MAX_COUNT)

		Effects.Sound("Mosquito", ctx.position, { Volume = 1, RollOffMaxDistance = 160 })
		session:RunWaves("Mosquito", NpcEventUtil.SplitWaves(total, 2), {
			interval = WAVE_INTERVAL,
			waveMessage = "O zumbido aumenta: mais mosquitos!",
		})

		return function()
			session:Cleanup()
		end
	end,
}
