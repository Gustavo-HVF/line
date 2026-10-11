--!nonstrict
-- Estufa grande (110 x 70, telhado de duas águas com cumeeira a 30 studs): estrutura de metal verde,
-- painéis de vidro destrutíveis, canteiros elevados com plantas tropicais, cipós pendurados e um
-- tanque de água. Portas nas duas pontas (a do oeste fica voltada para a mansão).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local Furniture = require(script.Parent.Furniture)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local Plants = require(script.Parent.Plants)

local Greenhouse = {}

local M = Enum.Material
local GHOST = { Ghost = true }

local LENGTH = 110 -- ao longo do X
local WIDTH = 70 -- ao longo do Z
local WALL_HEIGHT = 18
local RIDGE = 12
local BAY = 11
local KNEE = 2.5 -- murinho de tijolo na base
local DOOR_WIDTH = 8
local DOOR_HEIGHT = 11

function Greenhouse.Build(ctx)
	local center = GameConfig.GREENHOUSE_CENTER
	local groundY = GameConfig.GROUND_Y
	local rng = ctx.random
	local model = Kit.chunk("Estufa")
	local frameColor = Palette.GreenhouseFrame
	local glassExtra = { Transparency = 0.5, Reflectance = 0.08 }

	local cx, cz = center.X, center.Z
	local x0, x1 = cx - LENGTH / 2, cx + LENGTH / 2
	local z0, z1 = cz - WIDTH / 2, cz + WIDTH / 2
	local floorY = groundY + 0.2
	local top = floorY + WALL_HEIGHT

	local function glass(name: string, cf: CFrame, size: Vector3)
		Kit.box(ctx, model, name, cf, size, Palette.GreenhouseGlass, M.Glass, Kit.D, glassExtra)
	end
	local function frame(name: string, cf: any, size: Vector3, tags)
		Kit.box(ctx, model, name, cf, size, frameColor, M.Metal, tags)
	end

	-- Piso de pedra.
	Kit.box(
		ctx,
		model,
		"Piso",
		Vector3.new(cx, floorY - 0.5, cz),
		Vector3.new(LENGTH, 1, WIDTH),
		Palette.Stone,
		M.Slate,
		Kit.I
	)

	-- Laterais compridas (z0 e z1): murinho, pilares a cada vão, vidro e travessas.
	for _, z in { z0, z1 } do
		Kit.box(
			ctx,
			model,
			"Murinho",
			Vector3.new(cx, floorY + KNEE / 2, z),
			Vector3.new(LENGTH, KNEE, 1),
			Palette.Brick,
			M.Brick,
			Kit.D
		)
		for k = 0, LENGTH / BAY do
			frame(
				"Pilar",
				Vector3.new(x0 + k * BAY, floorY + WALL_HEIGHT / 2, z),
				Vector3.new(0.8, WALL_HEIGHT, 0.8),
				Kit.D
			)
		end
		for k = 0, LENGTH / BAY - 1 do
			glass(
				"Vidro",
				CFrame.new(x0 + (k + 0.5) * BAY, floorY + KNEE + (WALL_HEIGHT - KNEE) / 2, z),
				Vector3.new(BAY - 0.8, WALL_HEIGHT - KNEE, 0.3)
			)
		end
		frame("Travessa", Vector3.new(cx, floorY + 10, z), Vector3.new(LENGTH, 0.4, 0.5))
		frame("Calha", Vector3.new(cx, top, z), Vector3.new(LENGTH + 0.8, 0.8, 0.8))
	end

	-- Pontas (x0 e x1) com porta no meio.
	local endPosts = { -35, -25, -15, -DOOR_WIDTH / 2, DOOR_WIDTH / 2, 15, 25, 35 }
	for _, x in { x0, x1 } do
		for index = 1, #endPosts do
			local zRel = endPosts[index]
			if index > 1 and index < #endPosts then
				frame(
					"Pilar",
					Vector3.new(x, floorY + WALL_HEIGHT / 2, cz + zRel),
					Vector3.new(0.8, WALL_HEIGHT, 0.8),
					Kit.D
				)
			end
			if index < #endPosts then
				local a, b = zRel, endPosts[index + 1]
				local isDoor = a == -DOOR_WIDTH / 2
				if isDoor then
					glass(
						"Bandeira",
						CFrame.new(x, floorY + DOOR_HEIGHT + (WALL_HEIGHT - DOOR_HEIGHT) / 2, cz),
						Vector3.new(0.3, WALL_HEIGHT - DOOR_HEIGHT, DOOR_WIDTH - 0.8)
					)
					frame("Verga", Vector3.new(x, floorY + DOOR_HEIGHT, cz), Vector3.new(0.6, 0.6, DOOR_WIDTH))
				else
					-- Nas quinas o murinho comprido já ocupa o canto.
					local ka = (index == 1) and (a + 0.5) or a
					local kb = (index == #endPosts - 1) and (b - 0.5) or b
					Kit.box(
						ctx,
						model,
						"Murinho",
						Vector3.new(x, floorY + KNEE / 2, cz + (ka + kb) / 2),
						Vector3.new(1, KNEE, kb - ka),
						Palette.Brick,
						M.Brick,
						Kit.D
					)
					glass(
						"Vidro",
						CFrame.new(x, floorY + KNEE + (WALL_HEIGHT - KNEE) / 2, cz + (a + b) / 2),
						Vector3.new(0.3, WALL_HEIGHT - KNEE, b - a - 0.8)
					)
				end
			end
		end
		frame("Calha", Vector3.new(x, top, cz), Vector3.new(0.8, 0.8, WIDTH))
		-- Oitão de vidro (dois triângulos) e um montante central.
		Kit.wedge(
			ctx,
			model,
			"Oitao",
			CFrame.new(x, top + RIDGE / 2, cz + WIDTH / 4) * CFrame.Angles(0, math.pi, 0),
			Vector3.new(0.3, RIDGE, WIDTH / 2),
			Palette.GreenhouseGlass,
			M.Glass,
			nil,
			glassExtra
		)
		Kit.wedge(
			ctx,
			model,
			"Oitao",
			CFrame.new(x, top + RIDGE / 2, cz - WIDTH / 4),
			Vector3.new(0.3, RIDGE, WIDTH / 2),
			Palette.GreenhouseGlass,
			M.Glass,
			nil,
			glassExtra
		)
		frame("Montante", Vector3.new(x, top + RIDGE / 2, cz), Vector3.new(0.6, RIDGE, 0.6))
	end

	-- Telhado: caibros e painéis de vidro inclinados nas duas águas, e a cumeeira.
	frame("Cumeeira", Vector3.new(cx, top + RIDGE, cz), Vector3.new(LENGTH + 0.8, 0.8, 0.8))
	for _, side in { 1, -1 } do
		local ridge = Vector3.new(0, top + RIDGE, cz)
		local down = Vector3.new(0, -RIDGE, side * WIDTH / 2).Unit
		local normal = Vector3.new(0, WIDTH / 2, side * RIDGE).Unit
		local slope = math.sqrt((WIDTH / 2) ^ 2 + RIDGE ^ 2)
		local middle = ridge + down * (slope / 2)
		for k = 0, LENGTH / BAY do
			local x = x0 + k * BAY
			frame(
				"Caibro",
				CFrame.fromMatrix(Vector3.new(x, middle.Y, middle.Z) - normal * 0.3, Vector3.xAxis, normal),
				Vector3.new(0.6, 0.6, slope)
			)
		end
		for k = 0, LENGTH / BAY - 1 do
			local x = x0 + (k + 0.5) * BAY
			glass(
				"Telhado",
				CFrame.fromMatrix(Vector3.new(x, middle.Y, middle.Z) + normal * 0.15, Vector3.xAxis, normal),
				Vector3.new(BAY - 0.6, 0.3, slope)
			)
		end
	end

	-- Corredores: central (ao longo do X) e transversal (ao longo do Z) ficam livres.
	-- Canteiros elevados nos quatro quadrantes; o quadrante nordeste vira um tanque de água.
	local quadrants = {
		{ minX = x0 + 3, maxX = cx - 4, minZ = z0 + 3, maxZ = cz - 5 },
		{ minX = cx + 4, maxX = x1 - 3, minZ = z0 + 3, maxZ = cz - 5 },
		{ minX = x0 + 3, maxX = cx - 4, minZ = cz + 5, maxZ = z1 - 3 },
		{ minX = cx + 4, maxX = x1 - 3, minZ = cz + 5, maxZ = z1 - 3 },
	}
	local tankIndex = rng:NextInteger(1, 4)
	for index, q in quadrants do
		local qx, qz = (q.minX + q.maxX) / 2, (q.minZ + q.maxZ) / 2
		local w, d = q.maxX - q.minX, q.maxZ - q.minZ
		if index == tankIndex then
			-- Tanque de água com borda de pedra e vitórias-régias.
			local rim = 1.4
			Kit.box(
				ctx,
				model,
				"FundoDoTanque",
				Vector3.new(qx, floorY + 0.15, qz),
				Vector3.new(w, 0.3, d),
				Palette.Soil,
				M.Mud,
				Kit.I
			)
			for _, side in { -1, 1 } do
				Kit.box(
					ctx,
					model,
					"BordaDoTanque",
					Vector3.new(qx, floorY + 1, qz + side * (d / 2 - rim / 2)),
					Vector3.new(w, 2, rim),
					Palette.Stone,
					M.Granite,
					Kit.D
				)
				Kit.box(
					ctx,
					model,
					"BordaDoTanque",
					Vector3.new(qx + side * (w / 2 - rim / 2), floorY + 1, qz),
					Vector3.new(rim, 2, d - rim * 2),
					Palette.Stone,
					M.Granite,
					Kit.D
				)
			end
			Kit.box(
				ctx,
				model,
				"Agua",
				Vector3.new(qx, floorY + 1.5, qz),
				Vector3.new(w - rim * 2, 0.2, d - rim * 2),
				Palette.Water,
				M.SmoothPlastic,
				nil,
				{ Ghost = true, Transparency = 0.3, Reflectance = 0.1 }
			)
			for _ = 1, 5 do
				Kit.cylinder(
					ctx,
					model,
					"VitoriaRegia",
					Vector3.new(
						qx + rng:NextNumber(-w / 2 + 4, w / 2 - 4),
						floorY + 1.65,
						qz + rng:NextNumber(-d / 2 + 4, d / 2 - 4)
					),
					0.1,
					rng:NextNumber(2.5, 4.5),
					Palette.Leaves[3],
					M.Grass,
					nil,
					{ Ghost = true, NoShadow = true }
				)
			end
		else
			Kit.box(
				ctx,
				model,
				"Canteiro",
				Vector3.new(qx, floorY + 0.6, qz),
				Vector3.new(w, 1.2, d),
				Palette.Brick,
				M.Brick,
				Kit.I
			)
			Kit.box(
				ctx,
				model,
				"Terra",
				Vector3.new(qx, floorY + 1.45, qz),
				Vector3.new(w - 0.8, 0.5, d - 0.8),
				Palette.Soil,
				M.Mud,
				Kit.I
			)
			local soilY = floorY + 1.7
			local function soilPoint(margin: number): Vector3
				return Vector3.new(
					qx + rng:NextNumber(-w / 2 + margin, w / 2 - margin),
					soilY,
					qz + rng:NextNumber(-d / 2 + margin, d / 2 - margin)
				)
			end
			Plants.Palm(
				ctx,
				model,
				Vector3.new(qx + rng:NextNumber(-8, 8), soilY, qz),
				rng:NextNumber(15, 20),
				rng,
				false
			)
			for _ = 1, 3 do
				Plants.BigLeaves(ctx, model, soilPoint(4), rng:NextNumber(4, 6), rng)
			end
			for _ = 1, 3 do
				Plants.Fern(ctx, model, soilPoint(3), rng:NextNumber(2.5, 3.5), rng, 4)
			end
			Plants.Bush(ctx, model, soilPoint(4), rng:NextNumber(3, 4.5), rng)
			Plants.Flowers(ctx, model, soilPoint(5), 2.5, 4, rng)
		end
	end

	-- Cipós pendurados nos caibros.
	for _ = 1, 12 do
		local x = x0 + rng:NextInteger(1, LENGTH / BAY - 1) * BAY
		local zRel = rng:NextNumber(-WIDTH / 2 + 6, WIDTH / 2 - 6)
		local roofY = top + RIDGE * (1 - math.abs(zRel) / (WIDTH / 2)) - 0.8
		Plants.Vine(ctx, model, Vector3.new(x, roofY, cz + zRel), rng:NextNumber(6, 12), rng, Vector3.xAxis)
	end

	-- Vasos soltos e bancos no corredor central.
	for _ = 1, 6 do
		local x = rng:NextNumber(x0 + 6, x1 - 6)
		if math.abs(x - cx) > 5 and math.abs(math.abs(x - cx) - 30) > 4 then
			local z = cz + (rng:NextNumber() < 0.5 and -1 or 1) * 3.2
			Furniture.PottedPlant(ctx, model, CFrame.new(x, floorY, z), rng:NextNumber(1.6, 2.4), rng)
		end
	end
	for _, side in { -1, 1 } do
		Furniture.Bench(ctx, model, CFrame.new(cx + side * 30, floorY, cz - 3), 5, Palette.WoodLight)
	end
	-- Bancada de jardinagem perto da porta leste.
	local benchCF = CFrame.new(x1 - 1.75, floorY, cz + 9) * CFrame.Angles(0, math.rad(90), 0)
	Furniture.Table(ctx, model, benchCF, 6, 2.4, 3, Palette.WoodLight)
	for i = -1, 1 do
		Furniture.PottedPlant(ctx, model, benchCF * CFrame.new(i * 1.8, 3, 0), 1.2, rng)
	end

	-- Luz suave sob a cumeeira.
	local lamp = Kit.box(
		ctx,
		model,
		"Lampada",
		Vector3.new(cx, top + RIDGE - 2, cz),
		Vector3.new(1, 1, 1),
		Palette.LightWarm,
		M.Neon,
		nil,
		GHOST
	)
	Kit.light(lamp, Palette.LightWarm, 50, 0.8)

	-- Armas nos corredores.
	for _, offset in
		{
			Vector3.new(-20, 0, 0),
			Vector3.new(20, 0, 0),
			Vector3.new(-45, 0, 0),
			Vector3.new(45, 0, 0),
			Vector3.new(0, 0, -20),
			Vector3.new(0, 0, 20),
		}
	do
		Kit.weaponSpawn(ctx, Vector3.new(cx + offset.X, floorY + 1.5, cz + offset.Z), "Estufa")
	end

	Kit.attach(model, ctx.map, Vector3.new(cx, floorY + WALL_HEIGHT / 2, cz))
	Kit.region(
		ctx,
		"Estufa",
		CFrame.new(cx, floorY + (WALL_HEIGHT + RIDGE + 2) / 2 - 1, cz),
		Vector3.new(LENGTH + 1, WALL_HEIGHT + RIDGE + 2, WIDTH + 1),
		0
	)
	Kit.block(ctx, x0 - 6, x1 + 6, z0 - 6, z1 + 6)

	local mansionIsWest = GameConfig.MANSION_CENTER.X <= cx
	local west = Vector3.new(x0 - 1, groundY, cz)
	local east = Vector3.new(x1 + 1, groundY, cz)
	return {
		mainDoor = mansionIsWest and west or east,
		backDoor = mansionIsWest and east or west,
		bounds = { minX = x0, maxX = x1, minZ = z0, maxZ = z1 },
	}
end

return Greenhouse
