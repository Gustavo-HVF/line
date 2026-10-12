--!nonstrict
-- Evento de NPC "Leão Faminto": um leão (dois, com 4 jogadores ou mais) surge perto de onde o tabuleiro foi
-- jogado. Ele ruge, persegue, dá garradas fortes e salta em bote de média distância (IA do Leão). A vida
-- cresce um pouco com o número de jogadores. Termina quando os leões morrem (ou ao fim da duração).

local NpcEventUtil = require(script.Parent.Parent.EventHelpers.NpcEventUtil)
local Effects = require(script.Parent.Parent.NPC.Effects)

local BASE_HEALTH = 220
local HEALTH_PER_EXTRA_PLAYER = 0.1 -- +10% de vida por jogador vivo além do primeiro
local SECOND_LION_PLAYERS = 4
local SECOND_LION_DELAY = 8

return {
	Id = "Lion",
	DisplayName = "Leão Faminto",
	Kind = "npc",
	Riddles = {
		"Juba dourada e garras afiadas;\nfuja depressa das suas passadas.",
		"Um rugido ecoa e faz tremer o chão;\nfaminto e veloz, o rei vem em sua direção.",
		"Não corra em linha reta pela savana;\no grande felino salta e não se engana.",
	},
	Weight = 0.9,
	MinSpace = 12,
	Duration = 80,
	Radius = 60,

	Start = function(ctx)
		local session = NpcEventUtil.new(ctx, "Lion")
		local players = NpcEventUtil.AlivePlayerCount(ctx)
		local health = math.floor(BASE_HEALTH * (1 + HEALTH_PER_EXTRA_PLAYER * (players - 1)))
		local waves = if players >= SECOND_LION_PLAYERS then { 1, 1 } else { 1 }

		-- O rugido chega antes do leão.
		Effects.Sound("Roar", ctx.position, { Volume = 1, RollOffMaxDistance = 400 })
		Effects.Shake(ctx.position, ctx.radius * 1.5, 0.5, 0.8)

		session:RunWaves("Lion", waves, {
			startDelay = 1,
			interval = SECOND_LION_DELAY,
			health = health,
			waveMessage = "Outro leão faminto apareceu!",
		})

		return function()
			session:Cleanup()
		end
	end,
}
