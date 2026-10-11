--!nonstrict
-- Jardins e selva da ilha: caminhos de pedra ligando a porta da mansão, a entrada do labirinto e a
-- estufa; fonte na frente da mansão; avenida até a praia; coreto; postes com luz; e a vegetação
-- (árvores, arbustos, samambaias) que fica mais densa perto da borda, como uma selva invadindo.
-- A vegetação é agrupada em Models CullChunk por setor de 150 x 150.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local Furniture = require(script.Parent.Furniture)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local Plants = require(script.Parent.Plants)

local Garden = {}

local M = Enum.Material
local GHOST = { Ghost = true }

local PATH_WIDTH = 8
local SECTOR_SIZE = 150
local FOUNTAIN_RING = 20

-- layout: { mansion = info da Mansion, maze = info do Maze, greenhouse = info da Greenhouse, island = info da Island }
function Garden.Build(ctx, layout)
	local groundY = GameConfig.GROUND_Y
	local islandCenter = GameConfig.ISLAND_CENTER
	local rng = ctx.random
	local mansion = layout.mansion
	local maze = layout.maze
	local greenhouse = layout.greenhouse
	local plateauRadius = (layout.island and layout.island.grassRadius) or (GameConfig.ISLAND_RADIUS - 70)

	-- Models por setor (criados sob demanda).
	local sectors = {}
	local function sectorAt(x: number, z: number): Model
		local gx = math.floor((x - islandCenter.X) / SECTOR_SIZE + 0.5)
		local gz = math.floor((z - islandCenter.Z) / SECTOR_SIZE + 0.5)
		local id = gx .. "," .. gz
		local sector = sectors[id]
		if not sector then
			sector = {
				model = Kit.chunk(("Jardim %d,%d"):format(gx, gz)),
				center = Vector3.new(islandCenter.X + gx * SECTOR_SIZE, groundY + 6, islandCenter.Z + gz * SECTOR_SIZE),
			}
			sectors[id] = sector
		end
		return sector.model
	end

	-- 1) Caminhos de pedra (alturas alternadas para as emendas não piscarem).
	local paths = Kit.model("Jardim - Caminhos")
	local pathCount = 0
	local function path(a: Vector3, b: Vector3, width: number?)
		local w = width or PATH_WIDTH
		local flatA = Vector3.new(a.X, 0, a.Z)
		local flatB = Vector3.new(b.X, 0, b.Z)
		local length = (flatB - flatA).Magnitude
		if length < 0.5 then
			return
		end
		pathCount += 1
		local topY = groundY + 0.1 + 0.05 * (pathCount % 3)
		local mid = (flatA + flatB) / 2
		local position = Vector3.new(mid.X, topY - 0.2, mid.Z)
		Kit.box(
			ctx,
			paths,
			"Caminho",
			CFrame.lookAt(position, Vector3.new(flatB.X, position.Y, flatB.Z)),
			Vector3.new(w, 0.4, length + w * 0.6),
			(pathCount % 2 == 0) and Palette.Path or Palette.PathDark,
			M.Cobblestone,
			Kit.I,
			{ NoShadow = true }
		)
		Kit.addPath(ctx, a, b, w)
	end
	local function point(x: number, z: number): Vector3
		return Vector3.new(x, groundY, z)
	end

	local front = mansion.frontDoor
	local fountain = point(front.X, front.Z + 52)
	-- Porta da frente -> fonte.
	path(front, point(fountain.X, fountain.Z - FOUNTAIN_RING))
	-- Anel em volta da fonte (octógono).
	for k = 0, 7 do
		local a1 = k * math.pi / 4
		local a2 = (k + 1) * math.pi / 4
		path(
			point(fountain.X + math.cos(a1) * FOUNTAIN_RING, fountain.Z + math.sin(a1) * FOUNTAIN_RING),
			point(fountain.X + math.cos(a2) * FOUNTAIN_RING, fountain.Z + math.sin(a2) * FOUNTAIN_RING),
			6
		)
	end
	-- Avenida até a praia.
	local avenueEnd = point(fountain.X, islandCenter.Z + plateauRadius - 6)
	path(point(fountain.X, fountain.Z + FOUNTAIN_RING), avenueEnd, 10)
	-- Fonte -> estufa (porta principal).
	local ghDoor = greenhouse.mainDoor
	local eastTurn = point(ghDoor.X - 40, fountain.Z)
	path(point(fountain.X + FOUNTAIN_RING, fountain.Z), eastTurn)
	path(eastTurn, ghDoor)
	-- Porta lateral da mansão -> estufa.
	path(mansion.sideDoor, ghDoor)
	-- Porta dos fundos -> entrada do labirinto.
	path(mansion.backDoor, maze.entrance)
	-- Anel externo: oeste (da fonte até o caminho do labirinto) e leste (do caminho lateral até o labirinto).
	local backZ = (mansion.bounds.minZ + maze.bounds.maxZ) / 2
	local westX = mansion.bounds.minX - 40
	local eastX = mansion.bounds.maxX + 50
	path(point(fountain.X - FOUNTAIN_RING, fountain.Z), point(westX, fountain.Z))
	path(point(westX, fountain.Z), point(westX, backZ))
	path(point(westX, backZ), point(maze.entrance.X, backZ))
	local sideZ = mansion.sideDoor.Z
		+ (ghDoor.Z - mansion.sideDoor.Z) * ((eastX - mansion.sideDoor.X) / (ghDoor.X - mansion.sideDoor.X))
	path(point(eastX, sideZ), point(eastX, backZ))
	path(point(eastX, backZ), point(maze.entrance.X, backZ))
	-- Saída do labirinto -> praia.
	local exitDirection = (maze.exit.Z < maze.entrance.Z) and -1 or 1
	path(maze.exit, point(maze.exit.X, islandCenter.Z + exitDirection * (plateauRadius - 8)))
	-- Coreto no jardim oeste.
	local gazebo = point(westX - 70, fountain.Z + 10)
	path(point(westX, fountain.Z), point(gazebo.X + 9, gazebo.Z))
	Kit.attach(paths, ctx.map, Vector3.new(front.X, groundY, front.Z + 100))

	-- 2) Fonte.
	local fountainModel = Kit.chunk("Jardim - Fonte")
	local basinRadius = 12
	for k = 0, 7 do
		local angle = k * math.pi / 4
		local length = 2 * basinRadius * math.tan(math.pi / 8) + 1.5
		local height = (k % 2 == 0) and 2.4 or 2.5
		Kit.box(
			ctx,
			fountainModel,
			"BordaDaFonte",
			CFrame.new(
				fountain.X + math.cos(angle) * basinRadius,
				groundY + height / 2,
				fountain.Z + math.sin(angle) * basinRadius
			) * CFrame.Angles(0, -angle + math.pi / 2, 0),
			Vector3.new(length, height, 1.5),
			Palette.Marble,
			M.Marble,
			Kit.D
		)
	end
	Kit.cylinder(
		ctx,
		fountainModel,
		"FundoDaFonte",
		fountain + Vector3.new(0, 0.2, 0),
		0.6,
		basinRadius * 2,
		Palette.StoneDark,
		M.Slate,
		Kit.I
	)
	Kit.cylinder(
		ctx,
		fountainModel,
		"Agua",
		fountain + Vector3.new(0, 1.7, 0),
		0.2,
		basinRadius * 2 - 1.5,
		Palette.Water,
		M.SmoothPlastic,
		nil,
		{ Ghost = true, Transparency = 0.3, Reflectance = 0.1 }
	)
	Kit.cylinder(ctx, fountainModel, "Coluna", fountain + Vector3.new(0, 4, 0), 8, 2.4, Palette.Marble, M.Marble, Kit.I)
	Kit.cylinder(ctx, fountainModel, "Taca", fountain + Vector3.new(0, 8.3, 0), 1, 9, Palette.Marble, M.Marble, Kit.I)
	Kit.cylinder(
		ctx,
		fountainModel,
		"AguaDaTaca",
		fountain + Vector3.new(0, 8.85, 0),
		0.15,
		8,
		Palette.Water,
		M.SmoothPlastic,
		nil,
		{ Ghost = true, Transparency = 0.3 }
	)
	Kit.ball(ctx, fountainModel, "Topo", fountain + Vector3.new(0, 10.2, 0), 2.2, Palette.Marble, M.Marble)
	-- Canteiros de flores nas diagonais da fonte.
	for k = 0, 3 do
		local angle = k * math.pi / 2 + math.pi / 4
		local spot = fountain + Vector3.new(math.cos(angle) * 32, 0, math.sin(angle) * 32)
		Kit.box(
			ctx,
			fountainModel,
			"Canteiro",
			CFrame.new(spot + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, angle, 0),
			Vector3.new(10, 0.6, 6),
			Palette.Soil,
			M.Ground,
			Kit.I,
			{ NoShadow = true }
		)
		Plants.Flowers(ctx, fountainModel, spot + Vector3.new(0, 0.3, 0), 3, 6, rng)
		Kit.addPath(ctx, spot, spot, 12)
	end
	Kit.attach(fountainModel, ctx.map, fountain + Vector3.new(0, 4, 0))
	Kit.block(ctx, fountain.X - 26, fountain.X + 26, fountain.Z - 26, fountain.Z + 26)

	-- 3) Coreto (gazebo) octogonal.
	local gazeboModel = Kit.chunk("Jardim - Coreto")
	Kit.cylinder(ctx, gazeboModel, "Piso", gazebo + Vector3.new(0, 0.5, 0), 1, 18, Palette.Stone, M.Granite, Kit.I)
	for k = 0, 5 do
		local angle = k * math.pi / 3
		Kit.cylinder(
			ctx,
			gazeboModel,
			"Coluna",
			gazebo + Vector3.new(math.cos(angle) * 8, 6, math.sin(angle) * 8),
			10,
			0.9,
			Palette.Trim,
			M.Wood
		)
	end
	Kit.cylinder(ctx, gazeboModel, "Telhado", gazebo + Vector3.new(0, 11.5, 0), 1, 20, Palette.Roof, M.Slate)
	Kit.cylinder(ctx, gazeboModel, "Telhado", gazebo + Vector3.new(0, 12.75, 0), 1.5, 13, Palette.Roof, M.Slate)
	Kit.cylinder(ctx, gazeboModel, "Telhado", gazebo + Vector3.new(0, 14.25, 0), 1.5, 6, Palette.Roof, M.Slate)
	local gazeboLamp = Kit.ball(
		ctx,
		gazeboModel,
		"Lanterna",
		gazebo + Vector3.new(0, 9.8, 0),
		1.2,
		Palette.LightWarm,
		M.Neon,
		nil,
		GHOST
	)
	Kit.light(gazeboLamp, Palette.LightWarm, 20, 0.9)
	Furniture.Bench(ctx, gazeboModel, CFrame.new(gazebo + Vector3.new(0, 1, -4.5)), 6, Palette.WoodLight)
	Kit.attach(gazeboModel, ctx.map, gazebo + Vector3.new(0, 7, 0))
	Kit.block(ctx, gazebo.X - 12, gazebo.X + 12, gazebo.Z - 12, gazebo.Z + 12)
	Kit.region(ctx, "Coreto", CFrame.new(gazebo + Vector3.new(0, 8, 0)), Vector3.new(24, 20, 24), 0)

	-- 4) Postes de luz ao longo dos caminhos (só alguns acendem, para pesar menos).
	local lampSpots = {
		{ point(front.X - 7, front.Z + 14), true },
		{ point(front.X + 7, front.Z + 14), true },
		{ point(fountain.X - 11, fountain.Z + FOUNTAIN_RING + 30), true },
		{ point(fountain.X + 11, fountain.Z + FOUNTAIN_RING + 30), false },
		{ point(fountain.X - 11, fountain.Z + FOUNTAIN_RING + 130), false },
		{ point(fountain.X + 11, fountain.Z + FOUNTAIN_RING + 230), false },
		{ point(maze.entrance.X - 9, maze.entrance.Z + 8), true },
		{ point(maze.entrance.X + 9, maze.entrance.Z + 8), false },
		{ point(ghDoor.X - 8, ghDoor.Z - 8), true },
		{ point(westX - 7, fountain.Z - 60), false },
		{ point(eastX + 7, backZ + 40), false },
		{ point(mansion.backDoor.X + 7, mansion.backDoor.Z - 30), false },
	}
	for _, entry in lampSpots do
		local base, lit = entry[1], entry[2]
		local chunk = sectorAt(base.X, base.Z)
		Kit.cylinder(ctx, chunk, "Poste", base + Vector3.new(0, 5, 0), 10, 0.5, Palette.Iron, M.Metal)
		local lantern = Kit.box(
			ctx,
			chunk,
			"Lanterna",
			base + Vector3.new(0, 10.6, 0),
			Vector3.new(1.2, 1.4, 1.2),
			Palette.LightWarm,
			M.Neon,
			nil,
			GHOST
		)
		Kit.box(
			ctx,
			chunk,
			"Chapeu",
			base + Vector3.new(0, 11.5, 0),
			Vector3.new(1.8, 0.4, 1.8),
			Palette.Iron,
			M.Metal,
			nil,
			GHOST
		)
		if lit then
			Kit.light(lantern, Palette.LightWarm, 26, 1.1)
		end
	end

	-- 5) Avenida: árvores alinhadas e cercas vivas baixas.
	local avenueStart = fountain.Z + FOUNTAIN_RING + 20
	local z = avenueStart
	while z < avenueEnd.Z - 20 do
		for _, side in { -1, 1 } do
			local base = point(fountain.X + side * 15, z)
			Plants.Tree(ctx, sectorAt(base.X, base.Z), base, rng:NextNumber(0.9, 1.15), rng)
		end
		z += 45
	end
	for _, side in { -1, 1 } do
		local segment = 60
		local startZ = avenueStart - 10
		while startZ + segment < avenueEnd.Z - 10 do
			local base = point(fountain.X + side * 8.2, startZ + segment / 2)
			Kit.box(
				ctx,
				sectorAt(base.X, base.Z),
				"CercaBaixa",
				base + Vector3.new(0, 1.2, 0),
				Vector3.new(1.6, 2.4, segment - 8),
				Palette.pick(Palette.Hedge, rng),
				M.LeafyGrass,
				Kit.D
			)
			startZ += segment
		end
	end

	-- 6) Vegetação: mais densa conforme se afasta da mansão (a selva invadindo).
	local grid = math.ceil(plateauRadius / SECTOR_SIZE)
	for gx = -grid, grid do
		for gz = -grid, grid do
			local sectorCenter =
				Vector3.new(islandCenter.X + gx * SECTOR_SIZE, groundY, islandCenter.Z + gz * SECTOR_SIZE)
			local distance = (Vector3.new(sectorCenter.X - islandCenter.X, 0, sectorCenter.Z - islandCenter.Z)).Magnitude
			if distance < plateauRadius + SECTOR_SIZE * 0.3 then
				local trees, bushes, ferns, bigLeaves
				if distance < 200 then
					trees, bushes, ferns, bigLeaves = 1, 2, 0, 0
				elseif distance < 380 then
					trees, bushes, ferns, bigLeaves = 2, 2, 1, 0
				else
					trees, bushes, ferns, bigLeaves = 3, 2, 1, 1
				end
				local function randomPoint(margin: number): Vector3?
					for _ = 1, 12 do
						local x = sectorCenter.X + rng:NextNumber(-SECTOR_SIZE / 2, SECTOR_SIZE / 2)
						local zz = sectorCenter.Z + rng:NextNumber(-SECTOR_SIZE / 2, SECTOR_SIZE / 2)
						local fromCenter = Vector3.new(x - islandCenter.X, 0, zz - islandCenter.Z).Magnitude
						if fromCenter < plateauRadius - 10 and not Kit.isBlocked(ctx, x, zz, margin) then
							return point(x, zz)
						end
					end
					return nil
				end
				local chunk = sectorAt(sectorCenter.X, sectorCenter.Z)
				for _ = 1, trees do
					local p = randomPoint(7)
					if p then
						if distance >= 380 and rng:NextNumber() < 0.25 then
							Plants.Palm(ctx, chunk, p, rng:NextNumber(16, 24), rng)
						else
							Plants.Tree(ctx, chunk, p, rng:NextNumber(0.9, 1.5), rng)
						end
						Kit.block(ctx, p.X - 5, p.X + 5, p.Z - 5, p.Z + 5)
					end
				end
				for _ = 1, bushes do
					local p = randomPoint(3)
					if p then
						Plants.Bush(ctx, chunk, p, rng:NextNumber(4, 8), rng)
					end
				end
				for _ = 1, ferns do
					local p = randomPoint(2)
					if p then
						Plants.Fern(ctx, chunk, p, rng:NextNumber(2.5, 4), rng)
					end
				end
				for _ = 1, bigLeaves do
					local p = randomPoint(2)
					if p then
						Plants.BigLeaves(ctx, chunk, p, rng:NextNumber(4, 6), rng)
					end
				end
			end
		end
	end

	-- 7) Armas espalhadas pelo jardim.
	local weaponSpots = {
		{ point(fountain.X + FOUNTAIN_RING, fountain.Z), "Fonte" },
		{ point(fountain.X - FOUNTAIN_RING, fountain.Z), "Fonte" },
		{ point(maze.entrance.X, maze.entrance.Z + 6), "Jardim dos Fundos" },
		{ point(ghDoor.X - 6, ghDoor.Z), "Jardim Leste" },
		{ point(gazebo.X, gazebo.Z + 3), "Coreto" },
		{ point(fountain.X, (fountain.Z + avenueEnd.Z) / 2), "Avenida" },
		{ point(avenueEnd.X, avenueEnd.Z - 4), "Avenida" },
		{ point(westX, (fountain.Z + backZ) / 2), "Jardim Oeste" },
		{ point(eastX, (sideZ + backZ) / 2), "Jardim Leste" },
	}
	for _, entry in weaponSpots do
		Kit.weaponSpawn(ctx, entry[1] + Vector3.new(0, 1.6, 0), entry[2])
	end

	for _, sector in sectors do
		Kit.attach(sector.model, ctx.map, sector.center)
	end

	-- 8) Regiões externas.
	local bounds = mansion.bounds
	local function region(name: string, minX: number, maxX: number, minZ: number, maxZ: number)
		if maxX - minX < 1 or maxZ - minZ < 1 then
			return
		end
		Kit.region(
			ctx,
			name,
			CFrame.new((minX + maxX) / 2, groundY + 30, (minZ + maxZ) / 2),
			Vector3.new(maxX - minX, 80, maxZ - minZ),
			0
		)
	end
	region("Fonte", fountain.X - 26, fountain.X + 26, fountain.Z - 26, fountain.Z + 26)
	region("Jardim da Frente", bounds.minX - 12, bounds.maxX + 12, bounds.maxZ + 2, fountain.Z + 60)
	region("Avenida", fountain.X - 24, fountain.X + 24, fountain.Z + 60, avenueEnd.Z + 6)
	region("Jardim dos Fundos", bounds.minX - 12, bounds.maxX + 12, maze.bounds.maxZ + 2, bounds.minZ - 2)
	region("Jardim Leste", bounds.maxX + 2, greenhouse.bounds.minX - 2, maze.bounds.maxZ + 2, fountain.Z + 60)
	region("Jardim Oeste", westX - 110, bounds.minX - 2, maze.bounds.maxZ + 2, fountain.Z + 60)
end

return Garden
