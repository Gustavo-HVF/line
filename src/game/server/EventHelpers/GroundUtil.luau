--!nonstrict
-- Funções para achar o chão e pontos válidos perto de uma posição (spawn de NPCs, efeitos de eventos).
-- Ignora personagens, NPCs, pedaços de destruição e partes sem colisão.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Tags = require(game:GetService("ReplicatedStorage").Shared.Tags)

local GroundUtil = {}

local function buildExcludeList(extra: { Instance }?): { Instance }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	for _, enemy in CollectionService:GetTagged(Tags.Enemy) do
		table.insert(list, enemy)
	end
	local debrisFolder = workspace:FindFirstChild("Debris")
	if debrisFolder then
		table.insert(list, debrisFolder)
	end
	local eventsFolder = workspace:FindFirstChild("ActiveEvents")
	if eventsFolder then
		table.insert(list, eventsFolder)
	end
	if extra then
		for _, instance in extra do
			table.insert(list, instance)
		end
	end
	return list
end

-- Faz um raycast para baixo a partir de `position` (começando `startAbove` studs acima).
-- Retorna o ponto do chão e a part atingida, ou nil.
function GroundUtil.FindGround(
	position: Vector3,
	maxDrop: number?,
	startAbove: number?,
	exclude: { Instance }?
): (Vector3?, BasePart?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = buildExcludeList(exclude)
	params.IgnoreWater = false
	local origin = position + Vector3.new(0, startAbove or 3, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -(maxDrop or 60), 0), params)
	if result and result.Instance and result.Instance.CanCollide then
		return result.Position, result.Instance :: BasePart
	end
	return nil, nil
end

-- Verifica se há linha de visão livre entre dois pontos (sem paredes no meio).
function GroundUtil.HasLineOfSight(from: Vector3, to: Vector3, exclude: { Instance }?): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = buildExcludeList(exclude)
	local direction = to - from
	local result = workspace:Raycast(from, direction, params)
	return result == nil or (result.Position - to).Magnitude < 1
end

-- Procura um ponto no chão perto de `center`, a uma distância entre minRadius e maxRadius,
-- com linha de visão a partir do centro (para não nascer do outro lado de uma parede).
-- Se não achar, devolve o chão sob o centro (ou o próprio centro).
function GroundUtil.RandomPointNear(
	center: Vector3,
	minRadius: number,
	maxRadius: number,
	random: Random?,
	attempts: number?
): Vector3
	local rng = random or Random.new()
	for _ = 1, attempts or 12 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(minRadius, maxRadius)
		local candidate = center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local ground = GroundUtil.FindGround(candidate, 30, 6)
		if ground and math.abs(ground.Y - center.Y) < 12 then
			local eye = center + Vector3.new(0, 3, 0)
			if GroundUtil.HasLineOfSight(eye, ground + Vector3.new(0, 3, 0)) then
				return ground
			end
		end
	end
	return GroundUtil.FindGround(center, 40, 4) or center
end

return GroundUtil
