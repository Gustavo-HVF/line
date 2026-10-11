--!nonstrict
-- Plantas procedurais (todas feitas de parts): árvores, coqueiros, arbustos, samambaias,
-- folhas grandes, cipós e flores. Usadas pela ilha, pelos jardins, pela estufa e pela mansão.
-- `base` é sempre o ponto no chão onde a planta nasce.

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)

local Plants = {}

local M = Enum.Material
local GHOST = { Ghost = true }
local GHOST_NO_SHADOW = { Ghost = true, NoShadow = true }

-- Árvore de folhas largas: tronco quadrado e copa de blocos girados (estilo low-poly).
function Plants.Tree(ctx, parent: Instance, base: Vector3, scale: number, rng: Random)
	local height = 12 * scale
	local trunkWidth = 2.2 * scale
	Kit.box(
		ctx,
		parent,
		"Tronco",
		CFrame.new(base + Vector3.new(0, height / 2 - 0.5, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
		Vector3.new(trunkWidth, height + 1, trunkWidth),
		Palette.vary(Palette.Trunk, rng),
		M.Wood,
		Kit.D
	)
	local count = rng:NextInteger(2, 3)
	for i = 1, count do
		local size = (8 + rng:NextNumber(0, 5)) * scale
		local lift = (i == 1) and 0 or rng:NextNumber(1.5, 3.5) * scale
		local offset = Vector3.new(rng:NextNumber(-2, 2) * scale, height + lift, rng:NextNumber(-2, 2) * scale)
		Kit.box(
			ctx,
			parent,
			"Copa",
			CFrame.new(base + offset)
				* CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, math.pi), rng:NextNumber(-0.35, 0.35)),
			Vector3.new(size, size * 0.7, size),
			Palette.pick(Palette.Leaves, rng),
			M.LeafyGrass,
			Kit.D
		)
	end
end

-- Coqueiro com tronco curvo (4 segmentos), folhas caídas e cocos soltos.
function Plants.Palm(ctx, parent: Instance, base: Vector3, height: number, rng: Random, withCoconuts: boolean?)
	local direction = rng:NextNumber(0, math.pi * 2)
	local lean = rng:NextNumber(0.06, 0.2)
	local segments = 4
	local segmentLength = height / segments
	local width = math.clamp(height * 0.075, 0.9, 1.8)
	local joint = base - Vector3.new(0, 0.5, 0)
	local tilt = 0
	local up = Vector3.yAxis
	for i = 1, segments do
		tilt += lean * (i == 1 and 0.4 or 1)
		up = Vector3.new(math.sin(tilt) * math.cos(direction), math.cos(tilt), math.sin(tilt) * math.sin(direction))
		local center = joint + up * (segmentLength / 2)
		Kit.box(
			ctx,
			parent,
			"Tronco",
			CFrame.new(center) * CFrame.Angles(0, -direction, 0) * CFrame.Angles(0, 0, -tilt),
			Vector3.new(width * (1 - i * 0.06), segmentLength + 0.4, width * (1 - i * 0.06)),
			Palette.vary(Palette.PalmTrunk, rng),
			M.Wood,
			Kit.D
		)
		joint += up * segmentLength
	end
	local top = joint
	local fronds = rng:NextInteger(5, 7)
	local frondLength = math.clamp(height * 0.42, 4, 10)
	for i = 1, fronds do
		local angle = (i / fronds) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local droop = rng:NextNumber(0.25, 0.55)
		Kit.box(
			ctx,
			parent,
			"Folha",
			CFrame.new(top)
				* CFrame.Angles(0, angle, 0)
				* CFrame.Angles(-droop, 0, 0)
				* CFrame.new(0, 0, -frondLength / 2),
			Vector3.new(frondLength * 0.22, 0.25, frondLength),
			Palette.pick(Palette.PalmLeaf, rng),
			M.Grass,
			nil,
			GHOST
		)
	end
	if withCoconuts ~= false then
		for i = 1, rng:NextInteger(1, 3) do
			local angle = i * 2.1 + direction
			Kit.ball(
				ctx,
				parent,
				"Coco",
				top + Vector3.new(math.cos(angle) * 0.9, -0.7, math.sin(angle) * 0.9),
				1,
				Palette.Coconut,
				M.Wood,
				Kit.L
			)
		end
	end
end

-- Arbusto arredondado meio enterrado.
function Plants.Bush(ctx, parent: Instance, base: Vector3, size: number, rng: Random, color: Color3?)
	Kit.ball(
		ctx,
		parent,
		"Arbusto",
		base + Vector3.new(0, size * 0.28, 0),
		size,
		color or Palette.pick(Palette.Leaves, rng),
		M.LeafyGrass,
		nil,
		size < 4 and GHOST or nil
	)
end

-- Folhas finas saindo do chão em leque (samambaia). Sem colisão.
function Plants.Fern(ctx, parent: Instance, base: Vector3, size: number, rng: Random, leaves: number?)
	local count = leaves or 5
	local start = rng:NextNumber(0, math.pi * 2)
	for i = 1, count do
		local angle = start + (i / count) * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local length = size * rng:NextNumber(0.8, 1.15)
		Kit.box(
			ctx,
			parent,
			"Samambaia",
			CFrame.new(base + Vector3.new(0, 0.1, 0))
				* CFrame.Angles(0, angle, 0)
				* CFrame.Angles(rng:NextNumber(0.45, 0.8), 0, 0)
				* CFrame.new(0, 0, -length / 2),
			Vector3.new(length * 0.28, 0.15, length),
			Palette.pick(Palette.Leaves, rng),
			M.Grass,
			nil,
			GHOST_NO_SHADOW
		)
	end
end

-- Folhas grandes (tipo taioba): poucas folhas largas e bem inclinadas.
function Plants.BigLeaves(ctx, parent: Instance, base: Vector3, size: number, rng: Random)
	local start = rng:NextNumber(0, math.pi * 2)
	for i = 1, 3 do
		local angle = start + i * 2.1
		local length = size * rng:NextNumber(0.85, 1.1)
		Kit.box(
			ctx,
			parent,
			"FolhaGrande",
			CFrame.new(base + Vector3.new(0, size * 0.25, 0))
				* CFrame.Angles(0, angle, 0)
				* CFrame.Angles(rng:NextNumber(0.6, 0.95), 0, 0)
				* CFrame.new(0, 0, -length / 2),
			Vector3.new(length * 0.55, 0.2, length),
			Palette.pick(Palette.PalmLeaf, rng),
			M.Grass,
			nil,
			GHOST
		)
	end
end

-- Cipó pendurado a partir de `top`, encostado numa superfície virada para `facing` (direção horizontal).
function Plants.Vine(ctx, parent: Instance, top: Vector3, length: number, rng: Random, facing: Vector3?)
	local yaw = 0
	if facing and facing.Magnitude > 0.01 then
		yaw = math.atan2(-facing.X, -facing.Z)
	end
	Kit.box(
		ctx,
		parent,
		"Cipo",
		CFrame.new(top - Vector3.new(0, length / 2, 0)) * CFrame.Angles(0, yaw, rng:NextNumber(-0.06, 0.06)),
		Vector3.new(rng:NextNumber(0.9, 1.6), length, 0.3),
		Palette.vary(Palette.Vine, rng, 0.15),
		M.Grass,
		nil,
		GHOST_NO_SHADOW
	)
end

-- Pequeno canteiro de flores (bolinhas coloridas sem colisão).
function Plants.Flowers(ctx, parent: Instance, center: Vector3, radius: number, count: number, rng: Random)
	local color = Palette.pick(Palette.Flowers, rng)
	for _ = 1, count do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(0, radius)
		Kit.ball(
			ctx,
			parent,
			"Flor",
			center + Vector3.new(math.cos(angle) * distance, 0.6, math.sin(angle) * distance),
			rng:NextNumber(0.7, 1.2),
			color,
			M.SmoothPlastic,
			nil,
			GHOST_NO_SHADOW
		)
	end
end

return Plants
