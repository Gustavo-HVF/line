--!nonstrict
-- A ilha: platô de grama, praia em rampa suave até a borda (ISLAND_RADIUS), fundo do mar e oceano.
-- Tudo é feito de Parts (o Terrain fica livre para os eventos). Nada bloqueia a passagem para fora da
-- borda: a eliminação é feita pelo BoundaryService. Pedras grandes e falésias ficam só além da borda.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Tags = require(ReplicatedStorage.Shared.Tags)

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local Plants = require(script.Parent.Plants)

local Island = {}

local M = Enum.Material

local BEACH_WIDTH = 70 -- largura da praia (a grama vai até ISLAND_RADIUS - BEACH_WIDTH)
local BEACH_SEGMENTS = 48
local OCEAN_SIZE = 4000
local OCEAN_TILE = 2000 -- partes têm no máximo 2048 studs por eixo
local SEABED_RADIUS = 1000

-- Direções da bússola: -Z = Norte, +X = Leste.
local SECTOR_NAMES = { "Leste", "Sudeste", "Sul", "Sudoeste", "Oeste", "Noroeste", "Norte", "Nordeste" }

-- Altura do topo da praia em função da distância ao centro (usada para assentar pedras e coqueiros).
local function beachSurface(profile, distance: number): number
	return profile.innerTop - (distance - profile.inner) * profile.slope
end

function Island.Build(ctx)
	local center = GameConfig.ISLAND_CENTER
	local radius = GameConfig.ISLAND_RADIUS
	local groundY = GameConfig.GROUND_Y
	local waterY = GameConfig.WATER_LEVEL_Y
	local rng = ctx.random

	local ground = Kit.model("Ilha")

	-- Platô de grama: cilindro em pé (o eixo do cilindro é o X, então giramos 90° no Z).
	local grassRadius = radius - BEACH_WIDTH
	Kit.cylinder(
		ctx,
		ground,
		"Grama",
		Vector3.new(center.X, groundY - 15, center.Z),
		30,
		grassRadius * 2,
		Palette.Grass,
		M.Grass,
		Kit.I
	)

	-- Praia: anel de cunhas descendo do platô até um pouco abaixo do mar.
	-- A linha d'água fica 6 studs depois de ISLAND_RADIUS (logo antes da margem de eliminação).
	local profile = {}
	profile.inner = grassRadius - 2
	profile.innerTop = groundY - 0.02
	profile.bottom = waterY - 1.5
	local shoreline = radius + 6
	profile.slope = (profile.innerTop - waterY) / (shoreline - profile.inner)
	profile.outer = profile.inner + (profile.innerTop - profile.bottom) / profile.slope
	local wedgeLength = profile.outer - profile.inner
	local wedgeHeight = profile.innerTop - profile.bottom
	local wedgeWidth = 2 * profile.outer * math.sin(math.pi / BEACH_SEGMENTS) + 0.6
	for k = 0, BEACH_SEGMENTS - 1 do
		local angle = (k / BEACH_SEGMENTS) * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local middle = center + direction * ((profile.inner + profile.outer) / 2)
		local position = Vector3.new(middle.X, profile.bottom + wedgeHeight / 2, middle.Z)
		-- A frente (−Z) da cunha aponta para o mar: a rampa desce para fora.
		Kit.wedge(
			ctx,
			ground,
			"Praia",
			CFrame.lookAt(position, position + direction),
			Vector3.new(wedgeWidth, wedgeHeight, wedgeLength),
			(k % 2 == 0) and Palette.Sand or Palette.vary(Palette.Sand, rng, 0.03),
			M.Sand,
			Kit.I
		)
	end

	-- Fundo do mar raso em volta da ilha.
	Kit.cylinder(
		ctx,
		ground,
		"FundoDoMar",
		Vector3.new(center.X, profile.bottom - 5, center.Z),
		10,
		SEABED_RADIUS * 2,
		Palette.Seabed,
		M.Sand,
		Kit.I
	)
	Kit.attach(ground, ctx.map, Vector3.new(center.X, groundY, center.Z))

	-- Oceano: fundo escuro e lâminas de água translúcidas (sem colisão, sem consulta).
	local ocean = Kit.model("Oceano")
	local tiles = OCEAN_SIZE / OCEAN_TILE
	for ix = 0, tiles - 1 do
		for iz = 0, tiles - 1 do
			local x = center.X - OCEAN_SIZE / 2 + (ix + 0.5) * OCEAN_TILE
			local z = center.Z - OCEAN_SIZE / 2 + (iz + 0.5) * OCEAN_TILE
			Kit.box(
				ctx,
				ocean,
				"FundoDoOceano",
				Vector3.new(x, waterY - 42, z),
				Vector3.new(OCEAN_TILE, 4, OCEAN_TILE),
				Palette.DeepSea,
				M.Sand,
				Kit.I,
				{ NoShadow = true }
			)
			Kit.box(
				ctx,
				ocean,
				"Mar",
				Vector3.new(x, waterY - 0.5, z),
				Vector3.new(OCEAN_TILE, 1, OCEAN_TILE),
				Palette.Water,
				M.SmoothPlastic,
				{ Tags.Water },
				{ Ghost = true, NoShadow = true, Transparency = 0.25, Reflectance = 0.12 }
			)
		end
	end
	Kit.attach(ocean, ctx.map, Vector3.new(center.X, waterY, center.Z))

	-- Setores da praia: coqueiros, pedras e (no norte) falésias.
	local sectorSize = math.pi * 2 / #SECTOR_NAMES
	for index, name in SECTOR_NAMES do
		local sectorAngle = (index - 1) * sectorSize
		local chunk = Kit.chunk("Praia " .. name)
		local function randomAngle(): number
			return sectorAngle + rng:NextNumber(-sectorSize / 2 + 0.05, sectorSize / 2 - 0.05)
		end
		local function pointAt(angle: number, distance: number): Vector3
			return center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		end

		-- Coqueiros na areia.
		local placed = {}
		for _ = 1, 8 do
			if #placed >= 3 then
				break
			end
			local distance = rng:NextNumber(grassRadius + 8, radius - 12)
			local p = pointAt(randomAngle(), distance)
			local tooClose = false
			for _, other in placed do
				if (other - p).Magnitude < 30 then
					tooClose = true
				end
			end
			if not tooClose and not Kit.isBlocked(ctx, p.X, p.Z, 5) then
				table.insert(placed, p)
				local base = Vector3.new(p.X, beachSurface(profile, distance), p.Z)
				Plants.Palm(ctx, chunk, base, rng:NextNumber(14, 22), rng)
			end
		end

		-- Pedrinhas soltas na areia (pequenas: dá para passar por elas).
		for _ = 1, 2 do
			local distance = rng:NextNumber(grassRadius + 10, radius - 6)
			local p = pointAt(randomAngle(), distance)
			if not Kit.isBlocked(ctx, p.X, p.Z, 3) then
				local size = rng:NextNumber(2.5, 5)
				Kit.box(
					ctx,
					chunk,
					"Pedra",
					CFrame.new(p.X, beachSurface(profile, distance) + size * 0.2, p.Z)
						* CFrame.Angles(
							rng:NextNumber(0, math.pi),
							rng:NextNumber(0, math.pi),
							rng:NextNumber(0, math.pi)
						),
					Vector3.new(size, size * 0.8, size * 1.1),
					Palette.pick(Palette.Rocks, rng),
					M.Rock
				)
			end
		end

		-- Rochedos no mar (sempre depois da borda).
		local isCliff = name == "Norte" or name == "Noroeste" or name == "Nordeste"
		local stacks = isCliff and 4 or 2
		for _ = 1, stacks do
			local width = isCliff and rng:NextNumber(14, 26) or rng:NextNumber(8, 16)
			local height = isCliff and rng:NextNumber(26, 46) or rng:NextNumber(10, 26)
			local distance = radius + 14 + width / 2 + rng:NextNumber(0, isCliff and 30 or 90)
			local p = pointAt(randomAngle(), distance)
			local material = Palette.pick({ M.Rock, M.Slate, M.Basalt }, rng)
			local color = Palette.pick(Palette.Rocks, rng)
			Kit.box(
				ctx,
				chunk,
				"Rochedo",
				CFrame.new(p.X, profile.bottom + height / 2 - 2, p.Z)
					* CFrame.Angles(
						rng:NextNumber(-0.12, 0.12),
						rng:NextNumber(0, math.pi),
						rng:NextNumber(-0.12, 0.12)
					),
				Vector3.new(width, height, width * rng:NextNumber(0.7, 1.2)),
				color,
				material,
				Kit.I
			)
			if rng:NextNumber() < 0.6 then
				local small = width * 0.55
				Kit.box(
					ctx,
					chunk,
					"Rochedo",
					CFrame.new(
						p.X + rng:NextNumber(-width, width) * 0.5,
						profile.bottom + height * 0.35,
						p.Z + rng:NextNumber(-width, width) * 0.5
					)
						* CFrame.Angles(
							rng:NextNumber(-0.3, 0.3),
							rng:NextNumber(0, math.pi),
							rng:NextNumber(-0.3, 0.3)
						),
					Vector3.new(small, height * 0.6, small),
					color,
					material,
					Kit.I
				)
			end
		end
		Kit.attach(chunk, ctx.map, pointAt(sectorAngle, radius - 20) + Vector3.new(0, groundY, 0))

		-- Região da praia deste setor (caixa tangente ao anel).
		local direction = Vector3.new(math.cos(sectorAngle), 0, math.sin(sectorAngle))
		local regionMiddle = center + direction * (grassRadius - 10 + (radius + 16 - grassRadius + 10) / 2)
		local regionCenter = Vector3.new(regionMiddle.X, groundY + 20, regionMiddle.Z)
		local tangentLength = 2 * (radius + 16) * math.tan(sectorSize / 2) + 4
		Kit.region(
			ctx,
			"Praia " .. name,
			CFrame.lookAt(regionCenter, regionCenter + direction),
			Vector3.new(tangentLength, 70, radius + 16 - grassRadius + 10),
			0
		)
	end

	-- Região geral da ilha (vale quando nenhuma região menor contém o ponto).
	Kit.region(
		ctx,
		"Selva",
		CFrame.new(center.X, groundY + 70, center.Z),
		Vector3.new(radius * 2 + 40, 180, radius * 2 + 40),
		0
	)

	return {
		grassRadius = grassRadius,
		beach = profile,
	}
end

return Island
