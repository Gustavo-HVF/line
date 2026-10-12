--!nonstrict
-- Evento de NPC "Macacos Saqueadores": um bando de macacos (6 + 2 por jogador vivo extra) chega em 2 ou 3
-- ondas perto de onde o tabuleiro foi jogado. Eles mordem, arremessam objetos soltos nos jogadores (IA do
-- Macaco) e, de tempos em tempos, um deles faz bagunça: derruba um objeto solto ou quebra um móvel por
-- perto. Termina quando o bando inteiro for derrotado (ou ao fim da duração).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage.Shared.Tags)

local NpcEventUtil = require(script.Parent.Parent.EventHelpers.NpcEventUtil)
local Effects = require(script.Parent.Parent.NPC.Effects)

local BASE_COUNT = 6
local PER_EXTRA_PLAYER = 2
local WAVE_INTERVAL = 26
local MISCHIEF_MIN, MISCHIEF_MAX = 4, 7
local MISCHIEF_RADIUS = 12
local PROP_MAX_SIZE = 7
local BREAK_CHANCE = 0.35 -- chance de quebrar um móvel em vez de derrubar um objeto
local BREAK_MAX_SIZE = 12 -- só móveis (paredes inteiras ficam de fora)
local BREAK_IMPULSE = 30

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.MaxParts = 60

-- Um macaco derruba um objeto solto por perto (o objeto voa para cima e para o lado).
local function knockProp(position: Vector3, rng: Random): boolean
	local prop = Effects.FindLooseProp(position, MISCHIEF_RADIUS, PROP_MAX_SIZE, nil)
	if not prop then
		return false
	end
	local angle = rng:NextNumber(0, math.pi * 2)
	local speed = rng:NextNumber(12, 22)
	Effects.LaunchProp(prop, Vector3.new(math.cos(angle) * speed, rng:NextNumber(14, 24), math.sin(angle) * speed))
	return true
end

-- Um macaco quebra um móvel (Destructible pequeno) por perto.
local function breakFurniture(destruction, position: Vector3, rng: Random): boolean
	if not destruction or type(destruction.Fracture) ~= "function" then
		return false
	end
	local exclude = {}
	for _, name in { "NPCs", "Debris", "ActiveEvents", "Board" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(exclude, folder)
		end
	end
	overlapParams.FilterDescendantsInstances = exclude
	local candidates = {}
	for _, part in workspace:GetPartBoundsInRadius(position, MISCHIEF_RADIUS * 0.7, overlapParams) do
		if CollectionService:HasTag(part, Tags.Destructible) then
			local size = part.Size
			if math.max(size.X, size.Y, size.Z) <= BREAK_MAX_SIZE then
				local okCheck, destructible = pcall(destruction.IsDestructible, part)
				if okCheck and destructible then
					table.insert(candidates, part)
				end
			end
		end
	end
	if #candidates == 0 then
		return false
	end
	local part = candidates[rng:NextInteger(1, #candidates)]
	local ok, err = pcall(destruction.Fracture, part, part.Position, BREAK_IMPULSE)
	if not ok then
		warn("[Monkeys] Erro ao quebrar um móvel: " .. tostring(err))
		return false
	end
	return true
end

return {
	Id = "Monkeys",
	DisplayName = "Macacos Saqueadores",
	Kind = "npc",
	Riddles = {
		"Pulam do lustre e gritam sem parar;\ntudo o que estiver solto eles vão arremessar.",
		"Pequenos ladrões de rabo comprido;\nnenhum vaso da casa fica escondido.",
		"Ouça os guinchos que vêm do telhado;\no bando faminto está muito agitado.",
	},
	Weight = 1.2,
	MinSpace = 1,
	Duration = 90,
	Radius = 55,

	Start = function(ctx)
		local session = NpcEventUtil.new(ctx, "Monkeys")
		local rng: Random = ctx.random
		local players = NpcEventUtil.AlivePlayerCount(ctx)
		local total = BASE_COUNT + PER_EXTRA_PLAYER * (players - 1)
		local waves = NpcEventUtil.SplitWaves(total, if total >= 10 then 3 else 2)

		Effects.Sound("Monkey", ctx.position, { Volume = 1, RollOffMaxDistance = 220 })
		session:RunWaves("Monkey", waves, {
			interval = WAVE_INTERVAL,
			waveMessage = "Mais macacos estão chegando!",
		})

		-- Bagunça: de tempos em tempos, um macaco vivo derruba ou quebra alguma coisa perto dele.
		local destruction = ctx.services and ctx.services.Destruction
		session:Spawn(function()
			while session:Wait(rng:NextNumber(MISCHIEF_MIN, MISCHIEF_MAX)) do
				local models = session:GetModels()
				if #models > 0 then
					local model = models[rng:NextInteger(1, #models)]
					if model.Parent then
						local position = model:GetPivot().Position
						local done = false
						if rng:NextNumber() < BREAK_CHANCE then
							done = breakFurniture(destruction, position, rng)
						end
						if not done then
							done = knockProp(position, rng)
						end
						if done then
							Effects.Sound("Monkey", position, { Volume = 0.8, RollOffMaxDistance = 120 })
						end
					end
				end
			end
		end)

		return function()
			session:Cleanup()
		end
	end,
}
