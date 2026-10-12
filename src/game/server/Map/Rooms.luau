--!nonstrict
-- Cômodos da mansão: nomes, pisos e a mobília temática de cada um.
--
-- Cada cômodo é um objeto Room com um referencial local: origem no centro do piso, -Z apontando para a
-- porta principal ("front"), +Z para a parede oposta ("back"), -X = "left" e +X = "right".
-- O Room conhece as portas e janelas das suas paredes e guarda as áreas ocupadas, então os móveis
-- nunca bloqueiam uma porta e não se sobrepõem.

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local Furniture = require(script.Parent.Furniture)
local Plants = require(script.Parent.Plants)

local Rooms = {}

local M = Enum.Material

-- Dados dos cômodos ------------------------------------------------------------------------

Rooms.Info = {
	-- Térreo
	JardimInverno = {
		name = "Jardim de Inverno",
		kind = "WinterGarden",
		floorMaterial = M.CeramicTiles,
		floorColor = Palette.TilesBlue,
		weapons = 1,
	},
	Musica = {
		name = "Sala de Música",
		kind = "Music",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWoodLight,
		weapons = 1,
	},
	Estar = {
		name = "Sala de Estar",
		kind = "Living",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWood,
		weapons = 2,
	},
	Hall = {
		name = "Hall de Entrada",
		kind = "Hall",
		floorMaterial = M.Marble,
		floorColor = Palette.Marble,
		weapons = 2,
	},
	Biblioteca = {
		name = "Biblioteca",
		kind = "Library",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWood,
		weapons = 2,
	},
	Escritorio = {
		name = "Escritório",
		kind = "Study",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWood,
		weapons = 1,
	},
	Adega = { name = "Adega", kind = "Cellar", floorMaterial = M.Slate, floorColor = Palette.StoneDark, weapons = 1 },
	Trofeus = {
		name = "Sala de Troféus de Caça",
		kind = "Trophy",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWood,
		weapons = 2,
	},
	Bilhar = {
		name = "Sala de Bilhar",
		kind = "Billiards",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWoodLight,
		weapons = 1,
	},
	Jogos = {
		name = "Sala de Jogos",
		kind = "GameRoom",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.WoodRed,
		weapons = 0,
	},
	Jantar = {
		name = "Sala de Jantar",
		kind = "Dining",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWood,
		weapons = 2,
	},
	Despensa = { name = "Despensa", kind = "Pantry", floorMaterial = M.Slate, floorColor = Palette.Stone, weapons = 1 },
	Baile = {
		name = "Salão de Baile",
		kind = "Ballroom",
		floorMaterial = M.Marble,
		floorColor = Palette.Marble,
		weapons = 2,
	},
	EscadaFundos = {
		name = "Escadaria dos Fundos",
		kind = "BackStairs",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWood,
		weapons = 1,
	},
	Cozinha = {
		name = "Cozinha",
		kind = "Kitchen",
		floorMaterial = M.CeramicTiles,
		floorColor = Palette.Tiles,
		weapons = 2,
	},
	Lavanderia = {
		name = "Lavanderia",
		kind = "Laundry",
		floorMaterial = M.CeramicTiles,
		floorColor = Palette.TilesBlue,
		weapons = 1,
	},
	-- 2º andar (o material vale para a laje: o lado de baixo é o teto do térreo)
	Observatorio = {
		name = "Observatório",
		kind = "Observatory",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWood,
		weapons = 1,
	},
	Pintura = {
		name = "Estúdio de Pintura",
		kind = "Painting",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWoodLight,
		weapons = 1,
	},
	Costura = {
		name = "Sala de Costura",
		kind = "Sewing",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWood,
		weapons = 1,
	},
	Mapas = {
		name = "Sala de Mapas",
		kind = "Maps",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWood,
		weapons = 1,
	},
	Banheiro1 = {
		name = "Banheiro 1",
		kind = "Bathroom",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWoodLight,
		weapons = 1,
	},
	Banheiro2 = {
		name = "Banheiro 2",
		kind = "Bathroom",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWoodLight,
		weapons = 1,
	},
	Banheiro3 = {
		name = "Banheiro 3",
		kind = "Bathroom",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWoodLight,
		weapons = 1,
	},
	Hospedes1 = {
		name = "Quarto de Hóspedes 1",
		kind = "GuestRoom",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWood,
		weapons = 1,
	},
	Hospedes2 = {
		name = "Quarto de Hóspedes 2",
		kind = "GuestRoom",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWood,
		weapons = 1,
	},
	Hospedes3 = {
		name = "Quarto de Hóspedes 3",
		kind = "GuestRoom",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWood,
		weapons = 1,
	},
	Hospedes4 = {
		name = "Quarto de Hóspedes 4",
		kind = "GuestRoom",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWood,
		weapons = 1,
	},
	Galeria = {
		name = "Galeria de Arte",
		kind = "Gallery",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWoodLight,
		weapons = 2,
	},
	Criancas = {
		name = "Quarto das Crianças",
		kind = "Kids",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWoodLight,
		weapons = 1,
	},
	QuartoPrincipal = {
		name = "Quarto Principal",
		kind = "MasterBedroom",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWood,
		weapons = 2,
	},
	Sotao = {
		name = "Sótão",
		kind = "Attic",
		floorMaterial = M.WoodPlanks,
		floorColor = Palette.FloorWoodLight,
		weapons = 2,
	},
}

-- Objeto Room ---------------------------------------------------------------------------------

local Room = {}
Room.__index = Room

local DOOR_ZONE_DEPTH = 5.5

-- def: { key, name, kind, story, floorY, cf, w, d, h, openings }
function Rooms.new(ctx, def)
	local self = setmetatable({}, Room)
	self.ctx = ctx
	self.rng = ctx.random
	self.key = def.key
	self.name = def.name
	self.kind = def.kind
	self.story = def.story
	self.floorY = def.floorY
	self.cf = def.cf
	self.w = def.w
	self.d = def.d
	self.h = def.h
	self.model = Kit.chunk(def.name)
	self.occupied = {}
	self.doorZones = {}
	self.openings = {}
	for _, opening in def.openings or {} do
		self:_addOpening(opening)
	end
	return self
end

-- Converte uma abertura do mundo para o referencial do cômodo.
function Room:_addOpening(o)
	local p = self.cf:PointToObjectSpace(o.position)
	local halfW, halfD = self.w / 2, self.d / 2
	local wall, along
	-- A parede é paralela ao X do mundo; como o cômodo só gira 0° ou 180°, continua paralela ao X local.
	if o.axis == "X" then
		if math.abs(math.abs(p.Z) - halfD) > 1.6 or math.abs(p.X) > halfW + 1 then
			return
		end
		wall = (p.Z < 0) and "front" or "back"
		along = p.X
	else
		if math.abs(math.abs(p.X) - halfW) > 1.6 or math.abs(p.Z) > halfD + 1 then
			return
		end
		wall = (p.X < 0) and "left" or "right"
		along = p.Z
	end
	local bottom = o.bottomY - self.floorY
	local entry = {
		wall = wall,
		along = along,
		width = o.width,
		kind = o.kind,
		bottom = bottom,
		top = o.topY - self.floorY,
	}
	table.insert(self.openings, entry)
	if o.kind == "door" and math.abs(bottom) < 1 then
		local hw = o.width / 2 + 1
		local zone
		if wall == "front" then
			zone = { cx = along, cz = -halfD + DOOR_ZONE_DEPTH / 2, hx = hw, hz = DOOR_ZONE_DEPTH / 2 }
		elseif wall == "back" then
			zone = { cx = along, cz = halfD - DOOR_ZONE_DEPTH / 2, hx = hw, hz = DOOR_ZONE_DEPTH / 2 }
		elseif wall == "left" then
			zone = { cx = -halfW + DOOR_ZONE_DEPTH / 2, cz = along, hx = DOOR_ZONE_DEPTH / 2, hz = hw }
		else
			zone = { cx = halfW - DOOR_ZONE_DEPTH / 2, cz = along, hx = DOOR_ZONE_DEPTH / 2, hz = hw }
		end
		table.insert(self.doorZones, zone)
	end
end

-- CFrame no mundo a partir de coordenadas locais (x, z), giro em graus e altura acima do piso.
function Room:at(x: number, z: number, yawDegrees: number?, y: number?): CFrame
	return self.cf * CFrame.new(x, y or 0, z) * CFrame.Angles(0, math.rad(yawDegrees or 0), 0)
end

local function overlaps(ax, az, ahx, ahz, b): boolean
	return math.abs(ax - b.cx) < ahx + b.hx and math.abs(az - b.cz) < ahz + b.hz
end

function Room:isFree(cx: number, cz: number, hx: number, hz: number): boolean
	if math.abs(cx) + hx > self.w / 2 + 0.01 or math.abs(cz) + hz > self.d / 2 + 0.01 then
		return false
	end
	for _, rect in self.occupied do
		if overlaps(cx, cz, hx, hz, rect) then
			return false
		end
	end
	for _, zone in self.doorZones do
		if overlaps(cx, cz, hx, hz, zone) then
			return false
		end
	end
	return true
end

function Room:occupy(cx: number, cz: number, hx: number, hz: number)
	table.insert(self.occupied, { cx = cx, cz = cz, hx = hx, hz = hz })
end

-- Reserva uma área dada em coordenadas do mundo (ex.: escadas).
function Room:reserveWorld(x0: number, x1: number, z0: number, z1: number)
	local a = self.cf:PointToObjectSpace(Vector3.new(x0, self.floorY, z0))
	local b = self.cf:PointToObjectSpace(Vector3.new(x1, self.floorY, z1))
	self:occupy((a.X + b.X) / 2, (a.Z + b.Z) / 2, math.abs(a.X - b.X) / 2, math.abs(a.Z - b.Z) / 2)
end

local function halfExtents(yaw: number, sx: number, sz: number): (number, number)
	local quarter = math.abs(yaw) % 180
	if quarter == 90 then
		return sz / 2, sx / 2
	end
	return sx / 2, sz / 2
end

-- Coloca um objeto de pegada sx (largura) x sz (profundidade) em (x, z) com giro yaw.
function Room:place(x: number, z: number, yaw: number, sx: number, sz: number, builder: (CFrame) -> ()): boolean
	local hx, hz = halfExtents(yaw, sx, sz)
	if not self:isFree(x, z, hx, hz) then
		return false
	end
	self:occupy(x, z, hx, hz)
	builder(self:at(x, z, yaw))
	return true
end

-- Posição de um objeto encostado numa parede (costas do objeto na parede).
function Room:wallPose(wall: string, along: number, sx: number, sz: number, gap: number?): (number, number, number)
	local g = gap or 0.1
	if wall == "back" then
		return along, self.d / 2 - sz / 2 - g, 0
	elseif wall == "front" then
		return along, -self.d / 2 + sz / 2 + g, 180
	elseif wall == "left" then
		return -self.w / 2 + sz / 2 + g, along, -90
	end
	return self.w / 2 - sz / 2 - g, along, 90
end

function Room:wallLength(wall: string): number
	if wall == "front" or wall == "back" then
		return self.w
	end
	return self.d
end

-- Encosta um objeto na parede. `height` evita cobrir janelas (objetos mais altos que o peitoril).
function Room:against(
	wall: string,
	along: number,
	sx: number,
	sz: number,
	builder: (CFrame) -> (),
	height: number?
): boolean
	if math.abs(along) + sx / 2 > self:wallLength(wall) / 2 + 0.01 then
		return false
	end
	if height then
		for _, o in self.openings do
			if o.wall == wall and o.kind == "window" and o.bottom < height and o.top > 0 then
				if math.abs(o.along - along) < (o.width / 2 + sx / 2 + 0.2) then
					return false
				end
			end
		end
	end
	local x, z, yaw = self:wallPose(wall, along, sx, sz)
	return self:place(x, z, yaw, sx, sz, builder)
end

-- Tenta várias combinações (parede, posição) em ordem até uma dar certo.
function Room:tryAgainst(
	walls: { string },
	alongs: { number },
	sx: number,
	sz: number,
	builder: (CFrame) -> (),
	height: number?
): boolean
	for _, wall in walls do
		for _, along in alongs do
			if self:against(wall, along, sx, sz, builder, height) then
				return true
			end
		end
	end
	return false
end

-- Objeto preso na parede (quadros, troféus). `y` = altura do centro acima do piso.
function Room:wallItem(wall: string, along: number, y: number, w: number, h: number, builder: (CFrame) -> ()): boolean
	if math.abs(along) + w / 2 > self:wallLength(wall) / 2 - 0.3 then
		return false
	end
	for _, o in self.openings do
		if o.wall == wall and math.abs(o.along - along) < o.width / 2 + w / 2 + 0.4 then
			if y - h / 2 < o.top + 0.4 and y + h / 2 > o.bottom - 0.4 then
				return false
			end
		end
	end
	local cf
	if wall == "back" then
		cf = self:at(along, self.d / 2, 0, y)
	elseif wall == "front" then
		cf = self:at(along, -self.d / 2, 180, y)
	elseif wall == "left" then
		cf = self:at(-self.w / 2, along, -90, y)
	else
		cf = self:at(self.w / 2, along, 90, y)
	end
	builder(cf)
	return true
end

-- Ponto livre aleatório no piso (ou nil).
function Room:spot(hx: number, hz: number, margin: number?): (number?, number?)
	local m = margin or 1
	local rangeX = self.w / 2 - hx - m
	local rangeZ = self.d / 2 - hz - m
	if rangeX <= 0 or rangeZ <= 0 then
		return nil, nil
	end
	for _ = 1, 40 do
		local x = self.rng:NextNumber(-rangeX, rangeX)
		local z = self.rng:NextNumber(-rangeZ, rangeZ)
		if self:isFree(x, z, hx, hz) then
			return x, z
		end
	end
	return nil, nil
end

-- Lustre no teto (local x, z).
function Room:chandelier(x: number, z: number, range: number, shadows: boolean?, diameter: number?, drop: number?)
	return Furniture.Chandelier(
		self.ctx,
		self.model,
		self:at(x, z, 0, self.h).Position,
		drop or 3,
		diameter or 3,
		range,
		shadows,
		nil
	)
end

-- Quadros em paredes aleatórias.
function Room:paintings(count: number, y: number?)
	local walls = { "back", "left", "right", "front" }
	local placed = 0
	for _ = 1, count * 6 do
		if placed >= count then
			break
		end
		local wall = walls[self.rng:NextInteger(1, #walls)]
		local length = self:wallLength(wall)
		local w = self.rng:NextNumber(3, 5.5)
		local h = self.rng:NextNumber(3, 4.5)
		local along = self.rng:NextNumber(-length / 2 + w, length / 2 - w)
		if
			self:wallItem(wall, along, y or 8, w, h, function(cf)
				Furniture.Painting(self.ctx, self.model, cf, w, h, self.rng)
			end)
		then
			placed += 1
		end
	end
end

-- Pontos de arma em lugares livres do piso.
function Room:weapons(count: number)
	for _ = 1, count do
		local x, z = self:spot(1.5, 1.5, 1.5)
		if x then
			self:occupy(x, z, 1.5, 1.5)
			Kit.weaponSpawn(self.ctx, self:at(x, z, 0, 1.5).Position, self.name)
		end
	end
end

-- Tapete centralizado (não ocupa espaço).
function Room:rug(x: number, z: number, w: number, d: number, color: Color3, border: Color3?)
	Furniture.Rug(self.ctx, self.model, self:at(x, z), w, d, color, border)
end

-- Conjunto de mesa com cadeiras ao redor (pegada inclui as cadeiras).
local function diningSet(
	room,
	x: number,
	z: number,
	yaw: number,
	tableW: number,
	tableD: number,
	chairsPerSide: number,
	wood: Color3,
	seat: Color3,
	withEnds: boolean?
)
	local footprintW = tableW + (withEnds and 4.4 or 0.4)
	local footprintD = tableD + 4.6
	return room:place(x, z, yaw, footprintW, footprintD, function(cf)
		Furniture.Table(room.ctx, room.model, cf, tableW, tableD, 3.2, wood)
		for i = 1, chairsPerSide do
			local cx = -tableW / 2 + (i - 0.5) * (tableW / chairsPerSide)
			Furniture.Chair(room.ctx, room.model, cf * CFrame.new(cx, 0, tableD / 2 + 1.1), wood, seat)
			Furniture.Chair(
				room.ctx,
				room.model,
				cf * CFrame.new(cx, 0, -tableD / 2 - 1.1) * CFrame.Angles(0, math.pi, 0),
				wood,
				seat
			)
		end
		if withEnds then
			Furniture.Chair(
				room.ctx,
				room.model,
				cf * CFrame.new(tableW / 2 + 1.1, 0, 0) * CFrame.Angles(0, math.rad(90), 0),
				wood,
				seat
			)
			Furniture.Chair(
				room.ctx,
				room.model,
				cf * CFrame.new(-tableW / 2 - 1.1, 0, 0) * CFrame.Angles(0, math.rad(-90), 0),
				wood,
				seat
			)
		end
	end)
end

-- Cama encostada numa parede livre, com criados-mudos dos lados.
local function bedSet(room, bedW: number, bedL: number, frame: Color3, sheet: Color3, lit: boolean)
	local candidates = {}
	local side = room.w / 2 - bedW / 2 - 0.6
	for _, wall in { "back", "left", "right", "front" } do
		table.insert(candidates, { wall, 0 })
		table.insert(candidates, { wall, side })
		table.insert(candidates, { wall, -side })
	end
	for _, candidate in candidates do
		local wall, along = candidate[1], candidate[2]
		if
			room:against(wall, along, bedW, bedL, function(cf)
				Furniture.Bed(room.ctx, room.model, cf, bedW, bedL, frame, sheet)
			end)
		then
			for index, offset in { bedW / 2 + 1.2, -(bedW / 2 + 1.2) } do
				room:against(wall, along + offset, 2, 1.8, function(cf)
					Furniture.Nightstand(room.ctx, room.model, cf, frame, true, lit and index == 1)
				end)
			end
			return true
		end
	end
	return false
end

-- Mobília por tipo ----------------------------------------------------------------------------

local FURNISH = {}

FURNISH.Hall = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	room:rug(4, 0, 14, 18, Palette.Fabrics[1], Palette.Gold)
	room:chandelier(4, 0, 42, true, 5, 9)
	room:against("back", 9.5, 2.2, 2.2, function(cf)
		Furniture.Statue(ctx, model, cf)
	end)
	room:against("back", 6.2, 1.6, 1.6, function(cf)
		Furniture.PottedPlant(ctx, model, cf, 2.4, rng)
	end)
	room:against("right", 8.5, 2, 1.4, function(cf)
		Furniture.Clock(ctx, model, cf)
	end)
	room:against("right", -8.5, 5, 1.8, function(cf)
		Furniture.Table(ctx, model, cf, 5, 1.6, 3, Palette.WoodDark)
		Furniture.Vase(ctx, model, cf * CFrame.new(0, 3, 0), 1.6, Palette.TilesBlue, rng)
	end)
	room:wallItem("left", 2, 21, 9, 7, function(cf)
		Furniture.Painting(ctx, model, cf, 9, 7, rng)
	end)
	room:wallItem("right", 0, 21, 8, 6, function(cf)
		Furniture.Painting(ctx, model, cf, 8, 6, rng)
	end)
	room:wallItem("right", 0, 13, 2.2, 3, function(cf)
		Furniture.Mask(ctx, model, cf, rng)
	end)
end

FURNISH.Library = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	local function shelf(height)
		return function(cf)
			Furniture.Bookshelf(ctx, model, cf, 8, height, 1.6, rng)
		end
	end
	-- Estantes no térreo (embaixo do mezanino a altura é limitada).
	for _, along in { -8.5, 8.5 } do
		room:against("left", along, 8, 1.6, shelf(11), 11)
		room:against("right", along, 8, 1.6, shelf(11), 11)
	end
	room:against("back", 0, 12, 1.6, function(cf)
		Furniture.Bookshelf(ctx, model, cf, 12, 12, 1.6, rng)
	end, 12)
	room:against("front", 0, 12, 1.6, function(cf)
		Furniture.Bookshelf(ctx, model, cf, 12, 11, 1.6, rng)
	end, 11)
	for _, along in { -23.5, 23.5 } do
		room:against("back", along, 6, 1.6, function(cf)
			Furniture.Bookshelf(ctx, model, cf, 6, 12, 1.6, rng)
		end, 12)
		room:against("front", along, 6, 1.6, function(cf)
			Furniture.Bookshelf(ctx, model, cf, 6, 11, 1.6, rng)
		end, 11)
	end
	room:rug(0, 3, 30, 12, Palette.Fabrics[2], Palette.Gold)
	for _, x in { -9, 9 } do
		diningSet(room, x, 3.5, 0, 8, 3.6, 2, Palette.WoodDark, Palette.Fabrics[1])
	end
	room:place(0, 9, 0, 3, 3, function(cf)
		Furniture.Globe(ctx, model, cf, 2.6)
	end)
	for _, x in { -16, 16 } do
		room:place(x, 7, 0, 1.6, 1.6, function(cf)
			Furniture.FloorLamp(ctx, model, cf, false)
		end)
	end
	room:chandelier(0, 3, 46, true, 5, 10)
	-- Livros soltos em cima das mesas de leitura.
	Furniture.Book(ctx, model, room:at(-9.5, 3.5, 20, 3.2), rng)
	Furniture.Book(ctx, model, room:at(8.6, 3.2, -35, 3.2), rng)
	-- Mezanino (2º andar): estantes encostadas na parede do corredor e um ponto de arma.
	local mezzanineFront = -room.d / 2
	for _, along in { -23.5, -4.5, 4.5, 13.5, 22.5 } do
		Furniture.Bookshelf(ctx, model, room:at(along, mezzanineFront + 0.85, 180, 16), 8, 10, 1.6, rng)
	end
	Kit.weaponSpawn(ctx, room:at(0, mezzanineFront + 4.5, 0, 17.5).Position, room.name)
	room:paintings(2, 22)
end

FURNISH.Study = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	room:rug(0, 2, 12, 10, Palette.Fabrics[5], Palette.Gold)
	room:place(0, 4, 180, 5.4, 6, function(cf)
		Furniture.Desk(ctx, model, cf, Palette.WoodRed, rng)
		Furniture.Chair(
			ctx,
			model,
			cf * CFrame.new(0, 0, -2.4) * CFrame.Angles(0, math.pi, 0),
			Palette.WoodRed,
			Palette.Leather
		)
		Furniture.Candle(ctx, model, cf * CFrame.new(-2, 3.1, 0.6))
		Furniture.Globe(ctx, model, cf * CFrame.new(2.5, 0, 4.2), 1.6)
	end)
	room:tryAgainst({ "left", "right", "back" }, { -8.5, 8.5 }, 8, 1.6, function(cf)
		Furniture.Bookshelf(ctx, model, cf, 8, 11, 1.6, rng)
	end, 11)
	room:tryAgainst({ "right", "left", "back" }, { 8.5, -8.5 }, 8, 1.6, function(cf)
		Furniture.Bookshelf(ctx, model, cf, 8, 11, 1.6, rng)
	end, 11)
	room:tryAgainst({ "front", "back" }, { -9, 9 }, 3, 2.4, function(cf)
		Kit.box(
			ctx,
			model,
			"Cofre",
			cf * CFrame.new(0, 1.5, 0),
			Vector3.new(3, 3, 2.4),
			Palette.Iron,
			M.DiamondPlate,
			Kit.D
		)
	end)
	room:tryAgainst({ "front", "left" }, { 9, -9, 6 }, 3, 3, function(cf)
		Furniture.Armchair(ctx, model, cf, Palette.Leather)
	end)
	room:tryAgainst({ "back", "front" }, { -10, 10 }, 1.6, 1.6, function(cf)
		Furniture.FloorLamp(ctx, model, cf, true)
	end)
	room:paintings(2)
end

FURNISH.Living = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	local fabric = Palette.pick(Palette.Fabrics, rng)
	local placedFire = room:tryAgainst({ "back", "left", "right" }, { 8.5, -8.5 }, 7.5, 2.4, function(cf)
		Furniture.Fireplace(ctx, model, cf, 7, room.h, true, true)
	end)
	room:rug(0, 2, 14, 11, Palette.Fabrics[1], Palette.Gold)
	room:place(0, 1.5, 180, 9, 3.4, function(cf)
		Furniture.Sofa(ctx, model, cf, 9, fabric)
	end)
	room:place(0, 5.5, 0, 4, 2.4, function(cf)
		Furniture.Table(ctx, model, cf, 4, 2.2, 1.6, Palette.WoodDark)
		Furniture.Vase(ctx, model, cf * CFrame.new(1, 1.6, 0), 1.2, Palette.Terracotta, rng)
	end)
	for _, x in { -7, 7 } do
		room:place(x, 6, x < 0 and 90 or -90, 3, 3, function(cf)
			Furniture.Armchair(ctx, model, cf, fabric)
		end)
	end
	room:tryAgainst({ "left", "right", "front" }, { -9, 9 }, 8, 1.6, function(cf)
		Furniture.Bookshelf(ctx, model, cf, 8, 10, 1.6, rng)
	end, 10)
	room:tryAgainst({ "front", "back" }, { -10.5, 10.5 }, 1.6, 1.6, function(cf)
		Furniture.FloorLamp(ctx, model, cf, not placedFire)
	end)
	room:tryAgainst({ "front", "right" }, { 10.5, -10.5 }, 1.6, 1.6, function(cf)
		Furniture.PottedPlant(ctx, model, cf, 2.2, rng)
	end)
	room:paintings(3)
end

FURNISH.Music = function(room)
	local ctx, model = room.ctx, room.model
	room:rug(-2, 2, 12, 12, Palette.Fabrics[2], Palette.Gold)
	room:place(-3, 3, 30, 7, 9, function(cf)
		Furniture.GrandPiano(ctx, model, cf)
	end)
	for i, x in { 5, 8 } do
		room:place(x, -2 + i * 2, 200, 1.5, 1.5, function(cf)
			Furniture.MusicStand(ctx, model, cf)
		end)
		room:place(x + 0.5, i * 2 + 0.5, 20, 2.2, 2.2, function(cf)
			Furniture.Chair(ctx, model, cf, Palette.WoodDark, Palette.Fabrics[1])
		end)
	end
	-- Tambores da selva: o tema do jogo.
	for i, along in { -9, -6.5, 8 } do
		room:tryAgainst({ "back", "left", "right" }, { along }, 2.4, 2.4, function(cf)
			Furniture.Drum(ctx, model, cf, 1.6 + i * 0.3, 2 + i * 0.4)
		end)
	end
	room:tryAgainst({ "left", "right", "front" }, { 9, -9 }, 2, 2, function(cf)
		Furniture.Table(ctx, model, cf, 2, 2, 2.6, Palette.WoodDark)
		Furniture.Gramophone(ctx, model, cf * CFrame.new(0, 2.6, 0))
	end)
	room:tryAgainst({ "front", "back" }, { -10, 10 }, 1.6, 1.6, function(cf)
		Furniture.FloorLamp(ctx, model, cf, true)
	end)
	room:paintings(2)
end

FURNISH.WinterGarden = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	-- Muitas plantas em vasos e duas palmeiras pequenas.
	for _, spot in { { -9, 9 }, { 9, 9 }, { -9, -2 } } do
		room:place(spot[1], spot[2], 0, 3, 3, function(cf)
			Kit.cylinder(
				ctx,
				model,
				"Vaso",
				(cf * CFrame.new(0, 1, 0)).Position,
				2,
				2.6,
				Palette.Terracotta,
				M.Slate,
				Kit.L
			)
			Plants.Palm(ctx, model, (cf * CFrame.new(0, 2, 0)).Position, rng:NextNumber(6, 8), rng, false)
		end)
	end
	for _ = 1, 7 do
		local x, z = room:spot(1, 1, 0.5)
		if x then
			room:place(x, z, 0, 2, 2, function(cf)
				Furniture.PottedPlant(ctx, model, cf, rng:NextNumber(1.6, 2.6), rng)
			end)
		end
	end
	room:place(2, 3, 0, 7, 7, function(cf)
		Furniture.SideTable(ctx, model, cf * CFrame.new(0, 0, 0), 3, 2.8, Palette.White)
		Furniture.Vase(ctx, model, cf * CFrame.new(0, 2.8, 0), 1, Palette.TilesBlue, rng)
		Furniture.Chair(ctx, model, cf * CFrame.new(0, 0, 2.4), Palette.WoodLight, Palette.Fabrics[3])
		Furniture.Chair(
			ctx,
			model,
			cf * CFrame.new(0, 0, -2.4) * CFrame.Angles(0, math.pi, 0),
			Palette.WoodLight,
			Palette.Fabrics[3]
		)
	end)
	room:place(-3, -7, 0, 2, 2, function(cf)
		Plants.Fern(ctx, model, cf.Position, 2.5, rng)
	end)
	local light = Kit.box(
		ctx,
		model,
		"Lampiao",
		room:at(0, 0, 0, room.h - 2).Position,
		Vector3.new(1, 1.4, 1),
		Palette.LightWarm,
		M.Neon,
		nil,
		{ Ghost = true }
	)
	Kit.light(light, Palette.LightWarm, 22, 0.8)
end

FURNISH.Cellar = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	-- Barris deitados em suportes, encostados nas paredes.
	for _, wall in { "left", "right" } do
		for _, along in { -8, 0, 8 } do
			room:against(wall, along, 4, 3.4, function(cf)
				Kit.box(
					ctx,
					model,
					"Suporte",
					cf * CFrame.new(0, 0.5, 0),
					Vector3.new(4, 1, 3),
					Palette.WoodDark,
					M.Wood,
					Kit.D
				)
				Furniture.Barrel(ctx, model, cf * CFrame.new(0, 1, 0) * CFrame.Angles(0, math.rad(90), 0), 3.6, 3, true)
			end)
		end
	end
	room:tryAgainst({ "back", "front" }, { -8, 8 }, 8, 1.6, function(cf)
		Furniture.Bookshelf(ctx, model, cf, 8, 9, 1.6, rng, "bottles", Palette.WoodDark)
	end, 9)
	room:tryAgainst({ "back", "front" }, { 8, -8 }, 8, 1.6, function(cf)
		Furniture.Bookshelf(ctx, model, cf, 8, 9, 1.6, rng, "bottles", Palette.WoodDark)
	end, 9)
	room:place(0, 0, 0, 5, 5, function(cf)
		Furniture.Barrel(ctx, model, cf, 3.2, 3.4, false)
		Furniture.Bottle(ctx, model, cf * CFrame.new(0.4, 3.2, 0.2))
		Furniture.Bottle(ctx, model, cf * CFrame.new(-0.6, 3.2, -0.3), Color3.fromRGB(90, 20, 30))
	end)
	for _ = 1, 3 do
		local x, z = room:spot(1.4, 1.4, 0.5)
		if x then
			room:place(x, z, rng:NextNumber(0, 90), 2.6, 2.6, function(cf)
				Furniture.Crate(ctx, model, cf, Vector3.new(2.4, 2, 2.4))
			end)
		end
	end
	room:chandelier(0, 0, 18, false, 1.6, 2)
end

FURNISH.Trophy = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	room:place(0, 1, 0, 4.5, 7, function(cf)
		Furniture.SkinRug(ctx, model, cf)
	end)
	local heads = 0
	for _, wall in { "left", "right", "back", "front" } do
		for _, along in { -7, 7 } do
			if
				heads < 5
				and room:wallItem(wall, along, 10, 2.4, 3, function(cf)
					Furniture.TrophyHead(ctx, model, cf, rng)
				end)
			then
				heads += 1
			end
		end
	end
	room:wallItem("back", 0, 10, 4, 6, function(cf)
		Furniture.WallWeapons(ctx, model, cf)
	end)
	room:wallItem("front", 0, 12, 4, 6, function(cf)
		Furniture.WallWeapons(ctx, model, cf)
	end)
	for _, spot in { { -8, 8, 135 }, { 8, 8, -135 } } do
		room:place(spot[1], spot[2], spot[3], 3.2, 3.2, function(cf)
			Furniture.Armchair(ctx, model, cf, Palette.Leather)
		end)
	end
	room:place(0, 9, 0, 2, 2, function(cf)
		Furniture.SideTable(ctx, model, cf, 2, 2.6, Palette.WoodDark)
	end)
	room:tryAgainst({ "left", "right" }, { 8, -8 }, 3, 3, function(cf)
		Furniture.DisplayCase(ctx, model, cf, rng)
	end, 7)
	room:chandelier(0, 0, 24, false, 2.6, 3)
end

FURNISH.Billiards = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	room:place(0, 0, 90, 10, 7, function(cf)
		Furniture.BilliardTable(ctx, model, cf, rng)
	end)
	-- Luminária retangular sobre a mesa.
	local lamp = Kit.box(
		ctx,
		model,
		"Luminaria",
		room:at(0, 0, 0, room.h - 4).Position,
		Vector3.new(2, 0.8, 6),
		Palette.Felt,
		M.Metal,
		nil,
		{ Ghost = true }
	)
	Kit.light(lamp, Palette.LightWarm, 24, 1.1)
	Kit.cylinder(
		ctx,
		model,
		"Corrente",
		room:at(0, 0, 0, room.h - 1.8).Position,
		3.6,
		0.2,
		Palette.Iron,
		M.Metal,
		nil,
		{ Ghost = true }
	)
	room:tryAgainst({ "back", "front", "left" }, { 8, -8 }, 8, 2.4, function(cf)
		Furniture.Counter(ctx, model, cf, 8, Palette.WoodRed, Palette.MarbleDark)
		for i = -2, 2 do
			Furniture.Bottle(
				ctx,
				model,
				cf * CFrame.new(i * 1.3, 3.3, 0.3),
				Palette.pick(
					{ Color3.fromRGB(40, 80, 40), Color3.fromRGB(90, 20, 30), Color3.fromRGB(150, 110, 40) },
					rng
				)
			)
		end
	end, 3.5)
	for _ = 1, 2 do
		local x, z = room:spot(1, 1, 1)
		if x then
			room:place(x, z, 0, 1.8, 1.8, function(cf)
				Furniture.Stool(ctx, model, cf, Palette.WoodRed, 2.6)
			end)
		end
	end
	-- Suporte de tacos na parede (LooseProp).
	room:wallItem("left", 0, 8, 1.6, 6, function(cf)
		local rack = Kit.box(
			ctx,
			model,
			"SuporteDeTacos",
			cf * CFrame.new(0, -2.6, -0.15),
			Vector3.new(1.6, 0.4, 0.3),
			Palette.WoodDark,
			M.Wood,
			Kit.L,
			{ NoShadow = true }
		)
		local cues = {}
		for i = -1, 1 do
			table.insert(
				cues,
				Kit.box(
					ctx,
					model,
					"Taco",
					cf * CFrame.new(i * 0.4, 0, -0.3),
					Vector3.new(0.2, 6, 0.2),
					Palette.WoodLight,
					M.Wood,
					nil,
					{ Ghost = true }
				)
			)
		end
		Kit.weldTo(rack, cues)
	end)
	room:tryAgainst({ "right", "left" }, { -8, 8 }, 3, 3, function(cf)
		Furniture.Armchair(ctx, model, cf, Palette.Fabrics[3])
	end)
	room:paintings(2)
end

FURNISH.Dining = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	room:rug(0, 0, 30, 12, Palette.Fabrics[1], Palette.Gold)
	diningSet(room, 0, 0, 0, 22, 4.5, 5, Palette.WoodRed, Palette.Fabrics[1], true)
	for _, x in { -6, 0, 6 } do
		Furniture.Candle(ctx, model, room:at(x, 0, 0, 3.2))
	end
	for i = -1, 1 do
		Kit.cylinder(
			ctx,
			model,
			"Prato",
			room:at(i * 7 + 2, 1.2, 0, 3.25).Position,
			0.1,
			1.4,
			Palette.White,
			M.SmoothPlastic,
			Kit.L
		)
	end
	room:chandelier(-9, 0, 30, false, 3, 3)
	room:chandelier(9, 0, 0, false, 3, 3)
	for _, along in { -20, 20, -6, 6 } do
		room:tryAgainst({ "back", "front" }, { along }, 7, 2.4, function(cf)
			Furniture.Counter(ctx, model, cf, 7, Palette.WoodRed, Palette.WoodDark)
			Furniture.Vase(ctx, model, cf * CFrame.new(0, 3.3, 0), 1.4, Palette.Marble, rng)
		end, 3.5)
	end
	room:tryAgainst({ "left", "right" }, { 8, -8 }, 2, 1.4, function(cf)
		Furniture.Clock(ctx, model, cf)
	end)
	room:paintings(4)
end

FURNISH.Pantry = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	for _, wall in { "left", "right", "back", "front" } do
		for _, along in { -8, 8 } do
			room:against(wall, along, 7, 1.6, function(cf)
				Furniture.Bookshelf(
					ctx,
					model,
					cf,
					7,
					9,
					1.6,
					rng,
					rng:NextNumber() < 0.5 and "jars" or "boxes",
					Palette.WoodLight
				)
			end, 9)
		end
	end
	for _ = 1, 4 do
		local x, z = room:spot(1, 1, 0.5)
		if x then
			room:place(x, z, 0, 2, 2, function(cf)
				Furniture.Sack(ctx, model, cf, rng)
			end)
		end
	end
	for _ = 1, 2 do
		local x, z = room:spot(1.5, 1.5, 0.5)
		if x then
			room:place(x, z, 0, 3, 3, function(cf)
				Furniture.Barrel(ctx, model, cf, 3, 2.6, false)
			end)
		end
	end
	room:chandelier(0, 0, 18, false, 1.4, 2)
end

FURNISH.Ballroom = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	room:rug(0, 0, 40, 12, Palette.Fabrics[5], Palette.Gold)
	room:chandelier(-20, 0, 48, true, 6, 4)
	room:chandelier(20, 0, 0, false, 6, 4)
	-- Espelhos e cadeiras ao longo das paredes.
	for _, along in { -36, -20, -4, 12, 28 } do
		room:wallItem("back", along, 7, 4, 7, function(cf)
			Kit.box(
				ctx,
				model,
				"Espelho",
				cf * CFrame.new(0, 0, -0.15),
				Vector3.new(4, 7, 0.2),
				Palette.Glass,
				M.Glass,
				Kit.D,
				{ Reflectance = 0.6 }
			)
		end)
	end
	for _, wall in { "back", "front" } do
		for along = -36, 36, 12 do
			room:against(wall, along, 2.2, 2.2, function(cf)
				Furniture.Chair(ctx, model, cf, Palette.Gold, Palette.Fabrics[5])
			end)
		end
	end
	room:tryAgainst({ "left", "right" }, { 6, -6 }, 7, 9, function(cf)
		Furniture.GrandPiano(ctx, model, cf * CFrame.Angles(0, math.pi, 0))
	end)
	room:tryAgainst({ "right", "left" }, { -6, 6 }, 2.2, 2.2, function(cf)
		Furniture.Statue(ctx, model, cf)
	end)
	room:tryAgainst({ "right", "left" }, { 6, -6 }, 2, 2, function(cf)
		Furniture.Table(ctx, model, cf, 2, 2, 2.6, Palette.WoodDark)
		Furniture.Gramophone(ctx, model, cf * CFrame.new(0, 2.6, 0))
	end)
	for _, along in { -11, 11 } do
		room:tryAgainst({ "left", "right" }, { along }, 1.8, 1.8, function(cf)
			Furniture.PottedPlant(ctx, model, cf, 2.6, rng)
		end)
	end
end

FURNISH.BackStairs = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	-- A escada ocupa a faixa reservada pela Mansion; o resto vira um vestíbulo de serviço.
	room:tryAgainst({ "right", "left" }, { -6, 6, 0 }, 1.6, 1.6, function(cf)
		local base = Kit.cylinder(
			ctx,
			model,
			"Cabideiro",
			(cf * CFrame.new(0, 0.15, 0)).Position,
			0.3,
			1.4,
			Palette.WoodDark,
			M.Wood,
			Kit.L
		)
		local pole =
			Kit.cylinder(ctx, model, "Haste", (cf * CFrame.new(0, 3.2, 0)).Position, 6, 0.3, Palette.WoodDark, M.Wood)
		local coat = Kit.box(
			ctx,
			model,
			"Casaco",
			cf * CFrame.new(0, 4.6, -0.3),
			Vector3.new(1.4, 2.6, 0.5),
			Palette.Fabrics[4],
			M.Fabric
		)
		Kit.weldTo(base, { pole, coat })
	end)
	room:tryAgainst({ "right", "left", "back" }, { 6, -6, 0 }, 5, 1.8, function(cf)
		Furniture.Bench(ctx, model, cf, 5, Palette.Wood)
	end)
	room:tryAgainst({ "back", "front" }, { 9, -9 }, 3.4, 2.2, function(cf)
		Furniture.Chest(ctx, model, cf)
	end)
	for _ = 1, 2 do
		local x, z = room:spot(1, 1, 0.5)
		if x then
			room:place(x, z, 0, 2.4, 2.4, function(cf)
				Furniture.Crate(ctx, model, cf, Vector3.new(2, 1.6, 2))
			end)
		end
	end
	-- Patamar do 2º andar (faixa leste da célula, acima do vestíbulo).
	local landing = room:at(-4.5, 0, 0, 16)
	Furniture.PottedPlant(ctx, model, landing * CFrame.new(-6, 0, 10), 2.4, rng)
	Kit.weaponSpawn(ctx, (landing * CFrame.new(-2, 1.5, -2)).Position, room.name)
	room:chandelier(2, 0, 30, false, 2, 4)
end

FURNISH.Kitchen = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	local placedStove = false
	for _, along in { -22, -14, -6, 6, 14, 22 } do
		if not placedStove and math.abs(along) == 6 then
			placedStove = room:against("back", along, 4.2, 2.6, function(cf)
				Furniture.Stove(ctx, model, cf, room.h)
			end)
			if placedStove then
				continue
			end
		end
		room:against("back", along, 7, 2.4, function(cf)
			Furniture.Counter(ctx, model, cf, 7)
			Furniture.Vase(ctx, model, cf * CFrame.new(rng:NextNumber(-2, 2), 3.3, 0), 1, Palette.Steel)
		end, 3.4)
	end
	room:tryAgainst({ "left", "right" }, { 8, -8 }, 3, 2.6, function(cf)
		Furniture.Icebox(ctx, model, cf)
	end)
	room:tryAgainst({ "front" }, { -20, 20, -6, 6 }, 4, 2.4, function(cf)
		Furniture.Counter(ctx, model, cf, 4, Palette.White, Palette.Marble)
		Kit.box(
			ctx,
			model,
			"Cuba",
			cf * CFrame.new(0, 3.32, 0),
			Vector3.new(2.4, 0.06, 1.4),
			Palette.Steel,
			M.Metal,
			nil,
			{ Ghost = true }
		)
	end, 3.4)
	room:place(0, 2, 0, 12, 5, function(cf)
		Furniture.Table(ctx, model, cf, 12, 4, 3.2, Palette.WoodLight, M.WoodPlanks)
		Kit.cylinder(
			ctx,
			model,
			"Panela",
			(cf * CFrame.new(-3, 3.8, 0)).Position,
			1.2,
			1.6,
			Palette.Steel,
			M.Metal,
			Kit.L
		)
		Kit.box(
			ctx,
			model,
			"TabuaDeCarne",
			cf * CFrame.new(2, 3.3, 0.5),
			Vector3.new(2.4, 0.2, 1.6),
			Palette.WoodLight,
			M.Wood,
			Kit.L
		)
		Kit.ball(
			ctx,
			model,
			"Repolho",
			(cf * CFrame.new(4, 3.9, -0.6)).Position,
			1.2,
			Palette.Leaves[3],
			M.Grass,
			Kit.L
		)
	end)
	for _ = 1, 3 do
		local x, z = room:spot(1, 1, 0.5)
		if x then
			room:place(x, z, 0, 2, 2, function(cf)
				Furniture.Sack(ctx, model, cf, rng)
			end)
		end
	end
	room:chandelier(-12, 2, 30, false, 2, 3)
end

FURNISH.Laundry = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	room:tryAgainst({ "back", "left", "right" }, { -7, 7 }, 3.2, 3.2, function(cf)
		Furniture.Washtub(ctx, model, cf)
	end)
	room:tryAgainst({ "back", "left", "right" }, { 7, -7 }, 3.2, 3.2, function(cf)
		Furniture.Washtub(ctx, model, cf)
	end)
	room:place(0, 3, 0, 12, 2, function(cf)
		Furniture.ClothesLine(ctx, model, cf, 11, rng)
	end)
	room:tryAgainst({ "left", "right", "front" }, { 8, -8 }, 7, 1.6, function(cf)
		Furniture.Bookshelf(ctx, model, cf, 7, 8, 1.6, rng, "boxes", Palette.WoodLight)
	end, 8)
	room:tryAgainst({ "right", "left" }, { -8, 8 }, 5, 1.6, function(cf)
		Furniture.Table(ctx, model, cf, 5, 1.4, 3, Palette.WoodLight)
		Kit.box(
			ctx,
			model,
			"FerroDePassar",
			cf * CFrame.new(1, 3.3, 0),
			Vector3.new(1, 0.6, 0.6),
			Palette.Iron,
			M.Metal,
			Kit.L
		)
	end)
	for _ = 1, 2 do
		local x, z = room:spot(1, 1, 0.5)
		if x then
			room:place(x, z, 0, 2, 2, function(cf)
				Kit.cylinder(
					ctx,
					model,
					"Cesto",
					(cf * CFrame.new(0, 0.9, 0)).Position,
					1.8,
					2,
					Palette.WoodLight,
					M.Fabric,
					Kit.L
				)
			end)
		end
	end
	room:chandelier(0, 0, 20, false, 1.4, 2)
end

FURNISH.Observatory = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	room:rug(0, 0, 13, 13, Palette.Fabrics[2], Palette.Gold)
	-- Telescópio apontado para a janela da fachada (parede "back").
	room:place(0, room.d / 2 - 5, 180, 3, 3, function(cf)
		Furniture.Telescope(ctx, model, cf)
	end)
	room:place(-6, 0, 0, 4, 4, function(cf)
		Furniture.Table(ctx, model, cf, 3.5, 3.5, 3, Palette.WoodDark)
		Furniture.Orrery(ctx, model, cf * CFrame.new(-0.6, 3, 0))
	end)
	room:tryAgainst({ "left", "right", "front" }, { -8.5, 8.5 }, 5.4, 2.6, function(cf)
		Furniture.Desk(ctx, model, cf, Palette.WoodDark, rng)
	end)
	room:tryAgainst({ "front", "right" }, { 9, -9 }, 3, 3, function(cf)
		Furniture.Armchair(ctx, model, cf, Palette.Fabrics[2])
	end)
	room:place(7, -3, 0, 3, 3, function(cf)
		Furniture.Globe(ctx, model, cf, 2)
	end)
	-- Cartas celestes (quadros azul-escuros).
	for _, wall in { "left", "right", "front" } do
		room:wallItem(wall, -7, 8, 4, 4, function(cf)
			local chart = Kit.box(
				ctx,
				model,
				"CartaCeleste",
				cf * CFrame.new(0, 0, -0.1),
				Vector3.new(4, 4, 0.2),
				Palette.Canvas[6],
				M.Fabric,
				Kit.L,
				{ NoShadow = true }
			)
			local star = Kit.ball(
				ctx,
				model,
				"Estrela",
				(cf * CFrame.new(0.8, 0.6, -0.25)).Position,
				0.4,
				Palette.Gold,
				M.Neon,
				nil,
				{ Ghost = true }
			)
			Kit.weldTo(chart, { star })
		end)
	end
	room:chandelier(0, 0, 22, false, 2, 3)
end

FURNISH.Painting = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	room:rug(0, 0, 12, 10, Palette.White)
	for _, spot in { { -5, 2, 20 }, { 1, 5, -10 }, { 6, -1, -40 } } do
		room:place(spot[1], spot[2], spot[3], 3.6, 3, function(cf)
			Furniture.Easel(ctx, model, cf, rng)
		end)
	end
	room:place(-1, -4, 0, 2, 2, function(cf)
		Furniture.Stool(ctx, model, cf, Palette.WoodLight)
	end)
	room:tryAgainst({ "left", "right", "back" }, { 8, -8 }, 6, 2.4, function(cf)
		Furniture.Table(ctx, model, cf, 6, 2.2, 3, Palette.WoodLight)
		for i = -2, 2 do
			Kit.cylinder(
				ctx,
				model,
				"PoteDeTinta",
				(cf * CFrame.new(i * 1.1, 3.4, 0)).Position,
				0.8,
				0.7,
				Palette.Toys[(i + 3) % 4 + 1],
				M.SmoothPlastic,
				Kit.L
			)
		end
	end)
	-- Telas encostadas na parede.
	room:tryAgainst({ "front", "back", "left" }, { -9, 9 }, 4, 1.4, function(cf)
		for i = 0, 2 do
			Kit.box(
				ctx,
				model,
				"TelaEncostada",
				cf * CFrame.new(0, 1.8, 0.2 - i * 0.35) * CFrame.Angles(math.rad(8), 0, 0),
				Vector3.new(3.6 - i * 0.4, 3.4 - i * 0.3, 0.2),
				Palette.pick(Palette.Canvas, rng),
				M.Fabric,
				Kit.L
			)
		end
	end)
	room:paintings(4)
	room:chandelier(0, 0, 22, false, 2, 3)
end

FURNISH.Sewing = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	room:rug(0, 0, 12, 12, Palette.Fabrics[5], Palette.Gold)
	for _, along in { -7, 7 } do
		room:tryAgainst({ "back", "left", "right" }, { along, -along }, 5, 2.6, function(cf)
			Furniture.Table(ctx, model, cf, 5, 2.4, 3, Palette.WoodLight)
			Furniture.SewingMachine(ctx, model, cf * CFrame.new(0, 3, 0))
			Furniture.Chair(
				ctx,
				model,
				cf * CFrame.new(0, 0, -2.2) * CFrame.Angles(0, math.pi, 0),
				Palette.WoodLight,
				Palette.Fabrics[6]
			)
		end)
	end
	for _, spot in { { -5, 2 }, { 5, 2 } } do
		room:place(spot[1], spot[2], 0, 2.2, 2.2, function(cf)
			Furniture.Mannequin(ctx, model, cf, Palette.pick(Palette.Fabrics, rng))
		end)
	end
	room:tryAgainst({ "left", "right", "front" }, { 8.5, -8.5 }, 8, 1.6, function(cf)
		Furniture.Bookshelf(ctx, model, cf, 8, 9, 1.6, rng, "fabric", Palette.WoodLight)
	end, 9)
	for _ = 1, 3 do
		local x, z = room:spot(1, 1, 0.5)
		if x then
			room:place(x, z, 0, 2.2, 2.2, function(cf)
				Kit.cylinderAlong(
					ctx,
					model,
					"RoloDeTecido",
					cf * CFrame.new(0, 0.6, 0),
					2,
					1.2,
					Palette.pick(Palette.Fabrics, rng),
					M.Fabric,
					Kit.L
				)
			end)
		end
	end
	room:chandelier(0, 0, 22, false, 2, 3)
end

FURNISH.Maps = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	room:place(0, 1, 0, 9, 6, function(cf)
		Furniture.Table(ctx, model, cf, 8, 5, 3.2, Palette.WoodDark)
		Kit.box(
			ctx,
			model,
			"Mapa",
			cf * CFrame.new(0, 3.24, 0),
			Vector3.new(6.5, 0.06, 4),
			Palette.Parchment,
			M.Fabric,
			Kit.L
		)
		Furniture.Candle(ctx, model, cf * CFrame.new(3.2, 3.2, 1.8))
	end)
	room:place(-7, 7, 0, 3, 3, function(cf)
		Furniture.Globe(ctx, model, cf, 2.4)
	end)
	room:tryAgainst({ "left", "right", "back" }, { -8.5, 8.5 }, 8, 1.6, function(cf)
		Furniture.Bookshelf(ctx, model, cf, 8, 10, 1.6, rng, "scrolls", Palette.WoodDark)
	end, 10)
	for _, along in { -9, 9 } do
		room:tryAgainst({ "front", "back" }, { along }, 3.4, 2.2, function(cf)
			Furniture.Chest(ctx, model, cf, Palette.WoodRed)
		end)
	end
	-- Mapas antigos nas paredes.
	for _, wall in { "left", "right", "back", "front" } do
		room:wallItem(wall, 7, 8, 5, 4, function(cf)
			local oldMap = Kit.box(
				ctx,
				model,
				"MapaAntigo",
				cf * CFrame.new(0, 0, -0.1),
				Vector3.new(5, 4, 0.15),
				Palette.Parchment,
				M.Fabric,
				Kit.L,
				{ NoShadow = true }
			)
			local island = Kit.box(
				ctx,
				model,
				"Ilha",
				cf * CFrame.new(-0.5, 0.2, -0.2),
				Vector3.new(2, 1.4, 0.05),
				Palette.Leaves[1],
				M.Fabric,
				nil,
				{ Ghost = true }
			)
			Kit.weldTo(oldMap, { island })
		end)
	end
	room:chandelier(0, 1, 22, false, 2, 3)
end

FURNISH.Bathroom = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	-- Piso de ladrilhos por cima da laje.
	Kit.box(
		ctx,
		model,
		"Ladrilhos",
		room:at(0, 0, 0, 0.05),
		Vector3.new(room.w, 0.1, room.d),
		Palette.Tiles,
		M.CeramicTiles,
		nil,
		{ Ghost = true, NoShadow = true }
	)
	room:tryAgainst({ "back", "left", "right", "front" }, { 0, 7, -7 }, 6.2, 3.2, function(cf)
		Furniture.Bathtub(ctx, model, cf)
	end)
	room:tryAgainst({ "left", "right", "back", "front" }, { 8, -8, 0 }, 1.8, 2.4, function(cf)
		Furniture.Toilet(ctx, model, cf)
	end)
	room:tryAgainst({ "right", "left", "back", "front" }, { 8, -8, 0 }, 2.4, 1.8, function(cf)
		Furniture.Sink(ctx, model, cf, 6)
	end)
	room:tryAgainst({ "front", "back", "left" }, { -10, 10 }, 1.6, 1.6, function(cf)
		Furniture.PottedPlant(ctx, model, cf, 2, rng)
	end)
	room:rug(0, 0, 5, 3.5, Palette.pick(Palette.Fabrics, rng))
	room:chandelier(0, 0, 20, false, 1.4, 2)
end

FURNISH.GuestRoom = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	local frame = Palette.pick({ Palette.Wood, Palette.WoodDark, Palette.WoodRed }, rng)
	local sheet = Palette.pick(Palette.Fabrics, rng)
	room:rug(0, 0, 12, 10, Palette.pick(Palette.Fabrics, rng), Palette.Gold)
	bedSet(room, 6, 8.5, frame, sheet, true)
	room:tryAgainst({ "left", "right", "front", "back" }, { 8, -8 }, 5, 2.4, function(cf)
		Furniture.Wardrobe(ctx, model, cf, 5, 8, frame)
	end)
	room:tryAgainst({ "right", "left", "front", "back" }, { -8, 8 }, 4.4, 2, function(cf)
		Furniture.Dresser(ctx, model, cf, 4.4, frame)
	end, 7)
	room:tryAgainst({ "front", "left", "right" }, { 9.5, -9.5 }, 3, 3, function(cf)
		Furniture.Armchair(ctx, model, cf, sheet)
	end)
	room:paintings(2)
end

FURNISH.Gallery = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	room:rug(0, 0, 6, 20, Palette.Fabrics[1], Palette.Gold)
	for _, wall in { "left", "right", "back", "front" } do
		for _, along in { -8, 8 } do
			room:wallItem(wall, along, 7.5, 5, 4.5, function(cf)
				Furniture.Painting(ctx, model, cf, 5, 4.5, rng)
			end)
		end
	end
	for _, spot in { { -6, -5 }, { 6, -5 }, { 0, 6 } } do
		room:place(spot[1], spot[2], 0, 3.4, 3.4, function(cf)
			Furniture.DisplayCase(ctx, model, cf, rng)
		end)
	end
	for _, spot in { { -7, 4 }, { 7, 4 } } do
		room:place(spot[1], spot[2], 0, 2.4, 2.4, function(cf)
			Furniture.Statue(ctx, model, cf, Palette.pick({ Palette.Marble, Palette.Stone }, rng))
		end)
	end
	room:place(0, -1, 90, 5, 2, function(cf)
		Furniture.Bench(ctx, model, cf, 5, Palette.WoodDark)
	end)
	room:chandelier(0, 0, 26, false, 2.4, 3)
end

FURNISH.Kids = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	room:rug(0, 0, 12, 12, Palette.Toys[2], Palette.Toys[3])
	local made = 0
	for _, candidate in
		{ { "back", -7 }, { "back", 7 }, { "left", -7 }, { "left", 7 }, { "right", -7 }, { "right", 7 } }
	do
		if made >= 2 then
			break
		end
		if
			room:against(candidate[1], candidate[2], 4, 6.5, function(cf)
				Furniture.Bed(ctx, model, cf, 4, 6.5, Palette.WoodLight, Palette.Toys[made + 1])
			end)
		then
			made += 1
		end
	end
	room:place(4, -3, 30, 4.2, 4.2, function(cf)
		Furniture.RockingHorse(ctx, model, cf, Palette.Toys[1])
	end)
	room:place(-4, 2, 0, 5, 5, function(cf)
		Furniture.Table(ctx, model, cf, 3, 3, 2.2, Palette.Toys[4])
		Furniture.Stool(ctx, model, cf * CFrame.new(0, 0, 2.2), Palette.Toys[3], 1.6)
		Furniture.Stool(ctx, model, cf * CFrame.new(0, 0, -2.2), Palette.Toys[2], 1.6)
	end)
	room:tryAgainst({ "front", "back", "left" }, { -9, 9 }, 3.4, 2.2, function(cf)
		Furniture.Chest(ctx, model, cf, Palette.Toys[2])
	end)
	for i = 1, 4 do
		local x, z = room:spot(0.6, 0.6, 1)
		if x then
			room:place(x, z, rng:NextNumber(0, 90), 1, 1, function(cf)
				Furniture.Crate(ctx, model, cf, Vector3.new(0.9, 0.9, 0.9), Palette.Toys[i])
			end)
		end
	end
	room:place(2, 4, 0, 2, 2, function(cf)
		Furniture.Drum(ctx, model, cf, 1.4, 1.4, Palette.Toys[1])
	end)
	room:tryAgainst({ "left", "right", "front" }, { 8.5, -8.5 }, 6, 1.6, function(cf)
		Furniture.Bookshelf(ctx, model, cf, 6, 6, 1.6, rng, "books", Palette.WoodLight)
	end, 6)
	room:paintings(2, 7)
	room:chandelier(0, 0, 22, false, 2, 3)
end

FURNISH.MasterBedroom = function(room)
	local ctx, model = room.ctx, room.model
	local frame = Palette.WoodRed
	room:rug(-10, 0, 16, 14, Palette.Fabrics[1], Palette.Gold)
	-- Cama grande na metade "esquerda" do quarto.
	local placedBed = false
	for _, along in { -14, -8, 8, 14 } do
		if not placedBed then
			placedBed = room:against("back", along, 8, 9.5, function(cf)
				Furniture.Bed(ctx, model, cf, 8, 9.5, frame, Palette.Fabrics[1])
			end)
			if placedBed then
				for index, offset in { 5.4, -5.4 } do
					room:against("back", along + offset, 2, 1.8, function(cf)
						Furniture.Nightstand(ctx, model, cf, frame, true, index == 1)
					end)
				end
			end
		end
	end
	if not placedBed then
		bedSet(room, 8, 9.5, frame, Palette.Fabrics[1], true)
	end
	room:tryAgainst({ "front", "back" }, { 16, 20, -20 }, 7.5, 2.4, function(cf)
		Furniture.Fireplace(ctx, model, cf, 7, room.h, true, false)
	end)
	for _, along in { -20, -5 } do
		room:tryAgainst({ "front", "left" }, { along, -along }, 5, 2.4, function(cf)
			Furniture.Wardrobe(ctx, model, cf, 5, 9, frame)
		end)
	end
	room:tryAgainst({ "right", "front" }, { 0, 8 }, 4.4, 2, function(cf)
		Furniture.Dresser(ctx, model, cf, 4.4, frame)
	end, 7)
	for _, x in { 14, 20 } do
		room:place(x, 3, x == 14 and 120 or -120, 3, 3, function(cf)
			Furniture.Armchair(ctx, model, cf, Palette.Fabrics[1])
		end)
	end
	room:place(17, 5, 0, 2, 2, function(cf)
		Furniture.SideTable(ctx, model, cf, 1.8, 2.4, Palette.WoodDark)
	end)
	room:paintings(3)
	room:chandelier(-10, 0, 32, false, 3, 3)
end

FURNISH.Attic = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	-- Depósito bagunçado: caixotes empilhados, móveis cobertos, baús e um manequim velho.
	for _ = 1, 9 do
		local sx = rng:NextNumber(2, 3.4)
		local x, z = room:spot(sx / 2 + 0.3, sx / 2 + 0.3, 0.5)
		if x then
			room:place(x, z, 0, sx + 0.6, sx + 0.6, function(cf)
				local height = rng:NextNumber(1.6, 2.6)
				Furniture.Crate(
					ctx,
					model,
					cf * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0),
					Vector3.new(sx, height, sx)
				)
				if rng:NextNumber() < 0.5 then
					Furniture.Crate(
						ctx,
						model,
						cf * CFrame.new(0, height, 0) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0),
						Vector3.new(sx * 0.7, height * 0.8, sx * 0.7)
					)
				end
			end)
		end
	end
	for _ = 1, 4 do
		local w, d, h = rng:NextNumber(3, 6), rng:NextNumber(2.5, 4), rng:NextNumber(2.5, 5)
		local x, z = room:spot(w / 2 + 0.3, d / 2 + 0.3, 0.5)
		if x then
			room:place(x, z, 0, w + 0.6, d + 0.6, function(cf)
				Furniture.Covered(ctx, model, cf, Vector3.new(w, h, d), rng)
			end)
		end
	end
	for _, along in { -18, 18 } do
		room:tryAgainst({ "back", "front" }, { along }, 3.4, 2.2, function(cf)
			Furniture.Chest(ctx, model, cf)
		end)
	end
	local x, z = room:spot(1.2, 1.2, 1)
	if x then
		room:place(x, z, rng:NextNumber(0, 180), 2.4, 2.4, function(cf)
			Furniture.Mannequin(ctx, model, cf, Palette.Fabrics[6])
		end)
	end
	x, z = room:spot(2.2, 2.2, 1)
	if x then
		room:place(x, z, rng:NextNumber(0, 180), 4.2, 4.2, function(cf)
			Furniture.RockingHorse(ctx, model, cf, Palette.WoodLight)
		end)
	end
	room:chandelier(-12, 0, 24, false, 1.4, 2)
end

FURNISH.Corridor = function(room)
	local ctx, model, rng = room.ctx, room.model, room.rng
	room:rug(0, 0, room.w - 8, 4, Palette.Fabrics[1], Palette.Gold)
	room:chandelier(-49, 0, 34, false, 2, 2)
	room:chandelier(49, 0, 34, false, 2, 2)
	-- Entre as portas (as portas ficam no centro das células; as divisas ficam em ±14, ±42, ±70).
	for _, along in { -70, -42, -14, 14, 42, 70 } do
		for _, wall in { "front", "back" } do
			room:wallItem(wall, along, 8, 4.5, 3.5, function(cf)
				Furniture.Painting(ctx, model, cf, 4.5, 3.5, rng)
			end)
		end
	end
	for _, along in { -42, 42 } do
		room:against("back", along, 5, 1.8, function(cf)
			Furniture.Table(ctx, model, cf, 5, 1.6, 3, Palette.WoodDark)
			Furniture.Vase(
				ctx,
				model,
				cf * CFrame.new(0, 3, 0),
				1.5,
				Palette.pick({ Palette.TilesBlue, Palette.Terracotta, Palette.Marble }, rng),
				rng
			)
		end)
	end
	for _, along in { -70, 70 } do
		room:against("front", along, 2.2, 2.2, function(cf)
			Furniture.Statue(ctx, model, cf)
		end)
	end
	for _, along in { -95, 95 } do
		room:tryAgainst({ "front", "back" }, { along }, 1.8, 1.8, function(cf)
			Furniture.PottedPlant(ctx, model, cf, 2.4, rng)
		end)
	end
end

-- Mobilia o cômodo e espalha os pontos de arma.
function Rooms.Furnish(room)
	local builder = FURNISH[room.kind]
	if builder then
		builder(room)
	else
		warn(("[MapBuilder] Cômodo sem mobília definida: %s"):format(tostring(room.kind)))
	end
	local info = Rooms.Info[room.key]
	local count = info and info.weapons or 1
	room:weapons(count)
end

return Rooms
