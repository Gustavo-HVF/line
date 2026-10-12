--!nonstrict
-- Evento de NPC "Aranhas Gigantes": teias decorativas aparecem nas paredes (ou no chão) em volta do ponto
-- do evento e 5 a 8 aranhas saem de pontos ao redor, em 2 ondas. Elas mordem e cospem teia, que deixa o
-- jogador lento (IA da Aranha). Termina quando todas morrem (ou ao fim da duração).

local NpcEventUtil = require(script.Parent.Parent.EventHelpers.NpcEventUtil)
local Effects = require(script.Parent.Parent.NPC.Effects)

local MIN_COUNT, MAX_COUNT = 5, 8
local WAVE_INTERVAL = 30
local WEB_COUNT_MIN, WEB_COUNT_MAX = 3, 4
local WEB_SPOKES = 6
local WEB_RADIUS_MIN, WEB_RADIUS_MAX = 3.5, 5.5
local WEB_SEARCH_DIRECTIONS = 10
local WEB_WALL_REACH = 24
local WEB_HEIGHT = 5 -- altura do centro da teia nas paredes
local WEB_COLOR = Color3.fromRGB(236, 236, 230)
local STRAND_THICKNESS = 0.09

-- Um fio de teia (part fina, ancorada, sem colisão e fora das consultas espaciais).
local function strand(folder: Instance, a: Vector3, b: Vector3, thickness: number)
	local length = (b - a).Magnitude
	if length < 0.1 then
		return
	end
	local part = Instance.new("Part")
	part.Name = "FioDeTeia"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = WEB_COLOR
	part.Transparency = 0.2
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.new(thickness, thickness, length)
	part.CFrame = CFrame.lookAt((a + b) / 2, b)
	part.Parent = folder
end

-- Teia radial no plano XY local de `cframe` (o LookVector é a normal da teia): raios + um anel.
local function buildWeb(folder: Instance, cframe: CFrame, radius: number, rng: Random)
	local ring = {}
	for index = 1, WEB_SPOKES do
		local angle = (index / WEB_SPOKES) * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local direction = Vector3.new(math.cos(angle), math.sin(angle), 0)
		strand(folder, cframe.Position, cframe:PointToWorldSpace(direction * radius), STRAND_THICKNESS)
		ring[index] = cframe:PointToWorldSpace(direction * radius * rng:NextNumber(0.5, 0.65))
	end
	for index = 1, WEB_SPOKES do
		strand(folder, ring[index], ring[index % WEB_SPOKES + 1], STRAND_THICKNESS * 0.8)
	end
end

-- Procura paredes em volta do centro; sem parede, a teia fica deitada no chão.
local function decorate(ctx, rng: Random, ground)
	local center: Vector3 = ctx.position
	local floor = Effects.Ground(center, 30, 2) or center
	local eye = floor + Vector3.new(0, WEB_HEIGHT, 0)
	local params = Effects.WorldParams()
	local wanted = rng:NextInteger(WEB_COUNT_MIN, WEB_COUNT_MAX)
	local placed = 0
	local offset = rng:NextNumber(0, math.pi * 2)
	for index = 1, WEB_SEARCH_DIRECTIONS do
		if placed >= wanted then
			break
		end
		local angle = offset + (index / WEB_SEARCH_DIRECTIONS) * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local hit = workspace:Raycast(eye, direction * WEB_WALL_REACH, params)
		if hit and math.abs(hit.Normal.Y) < 0.3 then
			local position = hit.Position + hit.Normal * 0.12
			buildWeb(
				ctx.folder,
				CFrame.lookAt(position, position + hit.Normal),
				rng:NextNumber(WEB_RADIUS_MIN, WEB_RADIUS_MAX),
				rng
			)
			placed += 1
		end
	end
	-- Faltou parede: teias no chão em volta do centro.
	while placed < wanted do
		local point = ground.RandomPointNear(center, 6, math.max(ctx.radius * 0.4, 10), rng, 6)
		local flatWeb = CFrame.new(point + Vector3.new(0, 0.1, 0))
			* CFrame.Angles(math.pi / 2, rng:NextNumber(0, math.pi * 2), 0)
		buildWeb(ctx.folder, flatWeb, rng:NextNumber(WEB_RADIUS_MIN, WEB_RADIUS_MAX), rng)
		placed += 1
	end
end

return {
	Id = "Spiders",
	DisplayName = "Aranhas Gigantes",
	Kind = "npc",
	Riddles = {
		"Oito patas saem do canto escuro;\nsua teia te prende, nenhum passo é seguro.",
		"Fios brancos se espalham pelo salão;\nquem cair na teia vira refeição.",
		"Algo peludo corre pelas paredes;\nfuja das presas e das grudentas redes.",
	},
	Weight = 1,
	MinSpace = 4,
	Duration = 90,
	Radius = 50,

	Start = function(ctx)
		local session = NpcEventUtil.new(ctx, "Spiders")
		local rng: Random = ctx.random
		local players = NpcEventUtil.AlivePlayerCount(ctx)
		local total = math.clamp(MIN_COUNT + (players - 1) + rng:NextInteger(0, 1), MIN_COUNT, MAX_COUNT)

		local ok, err = pcall(decorate, ctx, rng, session.ground)
		if not ok then
			warn("[Spiders] Erro ao criar as teias: " .. tostring(err))
		end
		Effects.Sound("Spider", ctx.position, { Volume = 1, RollOffMaxDistance = 160 })

		session:RunWaves("Spider", NpcEventUtil.SplitWaves(total, 2), {
			interval = WAVE_INTERVAL,
			waveMessage = "Mais aranhas descem das teias!",
		})

		return function()
			session:Cleanup()
		end
	end,
}
