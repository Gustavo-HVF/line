--!nonstrict
-- Labirinto de cerca viva gerado por busca em profundidade aleatória (um labirinto novo a cada servidor).
-- Paredes vizinhas na mesma linha são unidas para economizar parts (no máximo 4 células por parede,
-- para a destruição continuar com pedaços de bom tamanho). Cada canto pertence a uma única parede,
-- então não existem faces sobrepostas piscando.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local Furniture = require(script.Parent.Furniture)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local Plants = require(script.Parent.Plants)

local Maze = {}

local M = Enum.Material

local N = 21 -- células por lado
local CELL = 12
local HEDGE_HEIGHT = 14
local HEDGE_THICKNESS = 2.5
local SECTOR = 7 -- 3 x 3 setores de 7 x 7 células
local MAX_RUN = 4
local CLEARING_MIN, CLEARING_MAX = 8, 12 -- clareira central de 5 x 5 células
local EXTRA_OPENINGS = 0.07 -- paredes internas removidas para criar caminhos alternativos (rotas de fuga)

-- Nomes dos setores: linha 0 = norte (menor Z), coluna 0 = oeste (menor X).
local SECTOR_NAMES = {
	[0] = { [0] = "Noroeste", [1] = "Norte", [2] = "Nordeste" },
	[1] = { [0] = "Oeste", [1] = "Centro", [2] = "Leste" },
	[2] = { [0] = "Sudoeste", [1] = "Sul", [2] = "Sudeste" },
}

function Maze.Build(ctx)
	local center = GameConfig.MAZE_CENTER
	local groundY = GameConfig.GROUND_Y
	local rng = ctx.random
	local size = N * CELL
	local x0 = center.X - size / 2
	local z0 = center.Z - size / 2

	-- hWalls[j][i]: parede ao longo do X na linha z = z0 + j*CELL, entre as células (i, j-1) e (i, j).
	-- vWalls[i][j]: parede ao longo do Z na linha x = x0 + i*CELL, entre as células (i-1, j) e (i, j).
	local hWalls, vWalls = {}, {}
	for j = 0, N do
		hWalls[j] = {}
		for i = 0, N - 1 do
			hWalls[j][i] = true
		end
	end
	for i = 0, N do
		vWalls[i] = {}
		for j = 0, N - 1 do
			vWalls[i][j] = true
		end
	end

	-- Busca em profundidade iterativa a partir do centro.
	local visited = {}
	local function key(i: number, j: number): number
		return j * N + i
	end
	local startCell = math.floor(N / 2)
	local stack = { { startCell, startCell } }
	visited[key(startCell, startCell)] = true
	while #stack > 0 do
		local top = stack[#stack]
		local i, j = top[1], top[2]
		local options = {}
		if i > 0 and not visited[key(i - 1, j)] then
			table.insert(options, { i - 1, j, "W" })
		end
		if i < N - 1 and not visited[key(i + 1, j)] then
			table.insert(options, { i + 1, j, "E" })
		end
		if j > 0 and not visited[key(i, j - 1)] then
			table.insert(options, { i, j - 1, "N" })
		end
		if j < N - 1 and not visited[key(i, j + 1)] then
			table.insert(options, { i, j + 1, "S" })
		end
		if #options == 0 then
			table.remove(stack)
		else
			local choice = options[rng:NextInteger(1, #options)]
			local ni, nj, direction = choice[1], choice[2], choice[3]
			if direction == "W" then
				vWalls[i][j] = false
			elseif direction == "E" then
				vWalls[i + 1][j] = false
			elseif direction == "N" then
				hWalls[j][i] = false
			else
				hWalls[j + 1][i] = false
			end
			visited[key(ni, nj)] = true
			table.insert(stack, { ni, nj })
		end
	end

	-- Clareira central aberta.
	for j = CLEARING_MIN + 1, CLEARING_MAX do
		for i = CLEARING_MIN, CLEARING_MAX do
			hWalls[j][i] = false
		end
	end
	for i = CLEARING_MIN + 1, CLEARING_MAX do
		for j = CLEARING_MIN, CLEARING_MAX do
			vWalls[i][j] = false
		end
	end
	-- Alguns atalhos extras.
	for j = 1, N - 1 do
		for i = 0, N - 1 do
			if hWalls[j][i] and rng:NextNumber() < EXTRA_OPENINGS then
				hWalls[j][i] = false
			end
		end
	end
	for i = 1, N - 1 do
		for j = 0, N - 1 do
			if vWalls[i][j] and rng:NextNumber() < EXTRA_OPENINGS then
				vWalls[i][j] = false
			end
		end
	end

	-- Entrada voltada para a mansão e saída do lado oposto.
	local mansionIsSouth = GameConfig.MANSION_CENTER.Z >= center.Z
	local entranceLine = mansionIsSouth and N or 0
	local exitLine = mansionIsSouth and 0 or N
	local entranceI = startCell
	local exitI = rng:NextInteger(2, N - 3)
	hWalls[entranceLine][entranceI] = false
	hWalls[exitLine][exitI] = false

	-- Models por setor.
	local sectors = {}
	local function sectorModel(si: number, sj: number): Model
		local id = sj * 3 + si
		if not sectors[id] then
			sectors[id] = { model = Kit.chunk("Labirinto - " .. SECTOR_NAMES[sj][si]), si = si, sj = sj }
		end
		return sectors[id].model
	end
	local function clampSector(index: number): number
		return math.clamp(math.floor(index / SECTOR), 0, 2)
	end

	local claimed = {}
	local function cornerKey(ci: number, cj: number): number
		return cj * (N + 1) + ci
	end
	local function hCovered(ci: number, cj: number): boolean
		local row = hWalls[cj]
		return (ci > 0 and row[ci - 1] == true) or (ci < N and row[ci] == true)
	end
	local half = HEDGE_THICKNESS / 2
	local hedgeY = groundY - 0.5 + (HEDGE_HEIGHT + 0.5) / 2
	local function hedge(parent: Model, cf: CFrame, size: Vector3)
		Kit.box(ctx, parent, "CercaViva", cf, size, Palette.pick(Palette.Hedge, rng), M.LeafyGrass, Kit.D)
	end

	-- Paredes ao longo do X: cada trecho inclui os cantos das pontas.
	for j = 0, N do
		local z = z0 + j * CELL
		local i = 0
		while i < N do
			if hWalls[j][i] then
				local a = i
				local b = i + 1
				while b < N and hWalls[j][b] and (b - a) < MAX_RUN and b % SECTOR ~= 0 do
					b += 1
				end
				local startX = claimed[cornerKey(a, j)] and (x0 + a * CELL + half) or (x0 + a * CELL - half)
				local endX = x0 + b * CELL + half
				for ci = a, b do
					claimed[cornerKey(ci, j)] = true
				end
				hedge(
					sectorModel(clampSector(a), clampSector(math.min(j, N - 1))),
					CFrame.new((startX + endX) / 2, hedgeY, z),
					Vector3.new(endX - startX, HEDGE_HEIGHT + 0.5, HEDGE_THICKNESS)
				)
				i = b
			else
				i += 1
			end
		end
	end

	-- Paredes ao longo do Z: quebram nos cantos que já têm parede em X (sem sobreposição).
	for i = 0, N do
		local x = x0 + i * CELL
		local j = 0
		while j < N do
			if vWalls[i][j] then
				local a = j
				local b = j + 1
				while b < N and vWalls[i][b] and (b - a) < MAX_RUN and b % SECTOR ~= 0 and not hCovered(i, b) do
					b += 1
				end
				local startZ, endZ
				local startKey, endKey = cornerKey(i, a), cornerKey(i, b)
				if hCovered(i, a) or claimed[startKey] then
					startZ = z0 + a * CELL + half
				else
					startZ = z0 + a * CELL - half
					claimed[startKey] = true
				end
				if hCovered(i, b) or claimed[endKey] then
					endZ = z0 + b * CELL - half
				else
					endZ = z0 + b * CELL + half
					claimed[endKey] = true
				end
				for cj = a + 1, b - 1 do
					claimed[cornerKey(i, cj)] = true
				end
				if endZ - startZ > 0.1 then
					hedge(
						sectorModel(clampSector(math.min(i, N - 1)), clampSector(a)),
						CFrame.new(x, hedgeY, (startZ + endZ) / 2),
						Vector3.new(HEDGE_THICKNESS, HEDGE_HEIGHT + 0.5, endZ - startZ)
					)
				end
				j = b
			else
				j += 1
			end
		end
	end

	-- Clareira: fonte com um tambor de pedra gigante, bancos e tochas.
	local clearing = sectorModel(1, 1)
	local cx, cz = center.X, center.Z
	local basinRadius = 7
	for k = 0, 7 do
		local angle = k * math.pi / 4
		local length = 2 * basinRadius * math.tan(math.pi / 8) + 1.2
		local height = (k % 2 == 0) and 2.2 or 2.3
		Kit.box(
			ctx,
			clearing,
			"BordaDaFonte",
			CFrame.new(cx + math.cos(angle) * basinRadius, groundY + height / 2, cz + math.sin(angle) * basinRadius)
				* CFrame.Angles(0, -angle + math.pi / 2, 0),
			Vector3.new(length, height, 1.2),
			Palette.Stone,
			M.Granite,
			Kit.D
		)
	end
	Kit.cylinder(
		ctx,
		clearing,
		"FundoDaFonte",
		Vector3.new(cx, groundY + 0.1, cz),
		0.6,
		basinRadius * 2,
		Palette.StoneDark,
		M.Slate,
		Kit.I
	)
	Kit.cylinder(
		ctx,
		clearing,
		"Agua",
		Vector3.new(cx, groundY + 1.5, cz),
		0.2,
		basinRadius * 2 - 1,
		Palette.Water,
		M.SmoothPlastic,
		nil,
		{ Ghost = true, Transparency = 0.3 }
	)
	Kit.cylinder(ctx, clearing, "Pilar", Vector3.new(cx, groundY + 3, cz), 6, 2.6, Palette.Stone, M.Granite, Kit.I)
	Kit.cylinder(
		ctx,
		clearing,
		"TamborDePedra",
		Vector3.new(cx, groundY + 8, cz),
		4,
		5.5,
		Palette.Marble,
		M.Marble,
		Kit.I
	)
	Kit.cylinder(
		ctx,
		clearing,
		"PeleDePedra",
		Vector3.new(cx, groundY + 10.1, cz),
		0.3,
		5.1,
		Palette.Parchment,
		M.Marble,
		nil,
		{ NoShadow = true }
	)
	Kit.cylinder(
		ctx,
		clearing,
		"Cinta",
		Vector3.new(cx, groundY + 7, cz),
		0.8,
		5.8,
		Palette.Gold,
		M.Metal,
		nil,
		{ NoShadow = true }
	)
	for k = 0, 3 do
		local angle = k * math.pi / 2 + math.pi / 4
		local position = Vector3.new(cx + math.cos(angle) * 15, groundY, cz + math.sin(angle) * 15)
		Furniture.Bench(
			ctx,
			clearing,
			CFrame.lookAt(position, Vector3.new(cx, groundY, cz)) * CFrame.Angles(0, math.pi, 0),
			5,
			Palette.Stone,
			M.Granite
		)
	end
	for k, corner in { { -24, -24 }, { 24, -24 }, { -24, 24 }, { 24, 24 } } do
		local base = Vector3.new(cx + corner[1], groundY, cz + corner[2])
		Kit.cylinder(ctx, clearing, "Tocha", base + Vector3.new(0, 3.5, 0), 7, 0.5, Palette.WoodDark, M.Wood)
		local flame = Kit.ball(
			ctx,
			clearing,
			"Chama",
			base + Vector3.new(0, 7.4, 0),
			1,
			Palette.Flame,
			M.Neon,
			nil,
			{ Ghost = true, NoShadow = true }
		)
		if k % 2 == 1 then
			Kit.light(flame, Palette.Flame, 26, 1.2)
		end
	end
	for k = 0, 5 do
		local angle = k * math.pi / 3
		Plants.Fern(ctx, clearing, Vector3.new(cx + math.cos(angle) * 27, groundY, cz + math.sin(angle) * 27), 3, rng)
	end

	-- Armas: quatro na clareira e uma por setor em becos sem saída.
	for k = 0, 3 do
		local angle = k * math.pi / 2
		Kit.weaponSpawn(
			ctx,
			Vector3.new(cx + math.cos(angle) * 11, groundY + 1.5, cz + math.sin(angle) * 11),
			"Clareira do Labirinto"
		)
	end
	local deadEnds = {}
	for j = 0, N - 1 do
		for i = 0, N - 1 do
			local inClearing = i >= CLEARING_MIN and i <= CLEARING_MAX and j >= CLEARING_MIN and j <= CLEARING_MAX
			if not inClearing then
				local walls = (hWalls[j][i] and 1 or 0)
					+ (hWalls[j + 1][i] and 1 or 0)
					+ (vWalls[i][j] and 1 or 0)
					+ (vWalls[i + 1][j] and 1 or 0)
				if walls >= 3 then
					local sectorId = clampSector(j) * 3 + clampSector(i)
					deadEnds[sectorId] = deadEnds[sectorId] or {}
					table.insert(deadEnds[sectorId], { i, j })
				end
			end
		end
	end
	for sectorId = 0, 8 do
		local list = deadEnds[sectorId]
		if list and #list > 0 and sectorId ~= 4 then
			local cell = list[rng:NextInteger(1, #list)]
			local si, sj = sectorId % 3, math.floor(sectorId / 3)
			Kit.weaponSpawn(
				ctx,
				Vector3.new(x0 + (cell[1] + 0.5) * CELL, groundY + 1.5, z0 + (cell[2] + 0.5) * CELL),
				"Labirinto - " .. SECTOR_NAMES[sj][si]
			)
		end
	end

	-- Portais de pedra na entrada (com placa) e na saída.
	local function gate(line: number, cellI: number, label: string?)
		local gateModel = sectorModel(clampSector(cellI), clampSector(math.min(line, N - 1)))
		local z = z0 + line * CELL
		local outward = (line == N) and 1 or -1
		local gx = x0 + (cellI + 0.5) * CELL
		for _, side in { -1, 1 } do
			Kit.box(
				ctx,
				gateModel,
				"Portal",
				Vector3.new(gx + side * (CELL / 2 - 0.2), groundY + 8, z + outward * 2.2),
				Vector3.new(2.6, 16, 2.6),
				Palette.Stone,
				M.Granite,
				Kit.D
			)
			Kit.ball(
				ctx,
				gateModel,
				"Lanterna",
				Vector3.new(gx + side * (CELL / 2 - 0.2), groundY + 16.8, z + outward * 2.2),
				1.4,
				Palette.LightWarm,
				M.Neon,
				nil,
				{ Ghost = true, NoShadow = true }
			)
		end
		Kit.box(
			ctx,
			gateModel,
			"Arco",
			Vector3.new(gx, groundY + 15, z + outward * 2.2),
			Vector3.new(CELL + 2.2, 2, 2.6),
			Palette.Stone,
			M.Granite,
			Kit.D
		)
		if label then
			local sign = Kit.box(
				ctx,
				gateModel,
				"Placa",
				Vector3.new(gx, groundY + 13, z + outward * 3.6),
				Vector3.new(8, 1.8, 0.3),
				Palette.WoodDark,
				M.Wood,
				nil,
				{ Ghost = true }
			)
			local gui = Instance.new("SurfaceGui")
			gui.Name = "Texto"
			gui.Face = (outward > 0) and Enum.NormalId.Back or Enum.NormalId.Front
			gui.CanvasSize = Vector2.new(400, 90)
			gui.LightInfluence = 1
			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 1
			text.Font = Enum.Font.Fondamento
			text.TextScaled = true
			text.TextColor3 = Palette.Gold
			text.Text = label
			text.Parent = gui
			gui.Parent = sign
		end
	end
	gate(entranceLine, entranceI, "LABIRINTO")
	gate(exitLine, exitI, nil)

	for _, sector in sectors do
		local sx = x0 + (sector.si + 0.5) * SECTOR * CELL
		local sz = z0 + (sector.sj + 0.5) * SECTOR * CELL
		Kit.attach(sector.model, ctx.map, Vector3.new(sx, groundY + HEDGE_HEIGHT / 2, sz))
		local regionName = "Labirinto - " .. SECTOR_NAMES[sector.sj][sector.si]
		Kit.region(ctx, regionName, CFrame.new(sx, groundY + 10, sz), Vector3.new(SECTOR * CELL, 26, SECTOR * CELL), 0)
	end
	local clearingSize = (CLEARING_MAX - CLEARING_MIN + 1) * CELL
	Kit.region(
		ctx,
		"Clareira do Labirinto",
		CFrame.new(cx, groundY + 10, cz),
		Vector3.new(clearingSize, 26, clearingSize),
		0
	)

	Kit.block(ctx, x0 - 8, x0 + size + 8, z0 - 8, z0 + size + 8)

	local entranceZ = z0 + entranceLine * CELL + (mansionIsSouth and 6 or -6)
	local exitZ = z0 + exitLine * CELL + (mansionIsSouth and -6 or 6)
	return {
		entrance = Vector3.new(x0 + (entranceI + 0.5) * CELL, groundY, entranceZ),
		exit = Vector3.new(x0 + (exitI + 0.5) * CELL, groundY, exitZ),
		bounds = { minX = x0, maxX = x0 + size, minZ = z0, maxZ = z0 + size },
	}
end

return Maze
