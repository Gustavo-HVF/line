--!nonstrict
-- Evento de NPC "O Caçador": um caçador de chapéu e bigode persegue o grupo durante toda a duração
-- (150 s) ou até morrer. Ele mantém distância, recua de quem chega perto e atira com o rifle depois de
-- mirar com um laser vermelho (dá para sair da mira). A vida cresce com o número de jogadores.

local NpcEventUtil = require(script.Parent.Parent.EventHelpers.NpcEventUtil)
local Effects = require(script.Parent.Parent.NPC.Effects)

local BASE_HEALTH = 250
local HEALTH_PER_EXTRA_PLAYER = 0.12

return {
	Id = "Hunter",
	DisplayName = "O Caçador",
	Kind = "npc",
	Riddles = {
		"Um ponto vermelho procura o seu peito;\ncorra para o lado antes do disparo perfeito.",
		"Ele caça leões, mas hoje a presa é você;\nesconda-se bem onde o rifle não vê.",
		"Chapéu de couro e bigode cerrado;\nquem fica parado já está caçado.",
	},
	Weight = 0.7,
	MinSpace = 18,
	Duration = 150,
	Radius = 80,

	Start = function(ctx)
		local session = NpcEventUtil.new(ctx, "Hunter")
		local players = NpcEventUtil.AlivePlayerCount(ctx)
		local health = math.floor(BASE_HEALTH * (1 + HEALTH_PER_EXTRA_PLAYER * (players - 1)))

		session:RunWaves("Hunter", { 1 }, {
			startDelay = 1.5,
			health = health,
			onSpawned = function(models)
				local model = models[1]
				if model then
					Effects.Sound("Reload", model:GetPivot().Position, { Volume = 1, RollOffMaxDistance = 200 })
				end
				NpcEventUtil.NotifyAll(
					"O Caçador chegou! Quando o laser vermelho mirar em você, saia do lugar ou se esconda.",
					"danger"
				)
			end,
		})

		return function()
			session:Cleanup()
		end
	end,
}
