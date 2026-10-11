--!nonstrict
-- Sala de Jogos (sala inicial): fechada por duas portas de madeira até a contagem terminar.
-- Tem a mesa onde o tabuleiro nasce (BoardSpawn), os spawns dos jogadores (PlayerSpawn), armas,
-- lareira, estantes e tambores. As paredes e o teto em volta ficam Indestructible até as portas abrirem,
-- para ninguém escapar antes da hora com dinamite.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local Tags = require(ReplicatedStorage.Shared.Tags)

local Furniture = require(script.Parent.Furniture)
local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)

local StartRoom = {}

local M = Enum.Material
local GHOST_NO_SHADOW = { Ghost = true, NoShadow = true }

local TABLE_HEIGHT = 3.5
local OPEN_ANGLE = math.rad(172) -- a folha termina quase encostada na parede do corredor
local OPEN_TIME = 1.8
local SPAWN_RADIUS = 9.2
local SPAWN_COUNT = 8

export type DoorRecord = {
	model: Model,
	leaf: BasePart,
	hinge: CFrame,
	offset: CFrame,
	openAngle: number,
}

-- Cria uma porta de madeira com dobradiça. `slot`: centro do vão no piso (mundo), largura, altura e
-- o lado do corredor (outward = +1 se o corredor fica no +Z do mundo, -1 se fica no -Z).
local function buildDoor(ctx, parent: Instance, slot, index: number, wallThickness: number): DoorRecord
	local model = Kit.model("PortaDaSalaDeJogos" .. index)
	local leafWidth = slot.width - 0.2
	local leafHeight = slot.height - 0.1
	local leafThickness = 0.4
	local outward = slot.outward
	local floorY = slot.center.Y
	-- Dobradiça no batente esquerdo (menor X), na face da parede voltada para o corredor.
	local hingePosition = Vector3.new(
		slot.center.X - slot.width / 2 + 0.05,
		floorY + 0.05 + leafHeight / 2,
		slot.center.Z + outward * (wallThickness / 2)
	)
	local hinge = CFrame.new(hingePosition)
	local offset = CFrame.new(leafWidth / 2, 0, -outward * (leafThickness / 2))
	local leaf = Kit.box(
		ctx,
		model,
		"Folha",
		hinge * offset,
		Vector3.new(leafWidth, leafHeight, leafThickness),
		Palette.WoodRed,
		M.Wood,
		Kit.I
	)
	-- Detalhes soldados na folha (acompanham a rotação): almofadas dos dois lados e maçanetas.
	local details = {}
	for _, face in { -1, 1 } do
		for _, y in { -2.2, 2 } do
			table.insert(
				details,
				Kit.box(
					ctx,
					model,
					"Almofada",
					leaf.CFrame * CFrame.new(0, y, face * (leafThickness / 2 + 0.04)),
					Vector3.new(leafWidth * 0.7, 3.2, 0.08),
					Palette.WoodDark,
					M.Wood,
					nil,
					GHOST_NO_SHADOW
				)
			)
		end
		table.insert(
			details,
			Kit.ball(
				ctx,
				model,
				"Macaneta",
				(leaf.CFrame * CFrame.new(leafWidth / 2 - 0.6, -0.4, face * 0.35)).Position,
				0.45,
				Palette.Brass,
				M.Metal,
				nil,
				GHOST_NO_SHADOW
			)
		)
	end
	for _, detail in details do
		detail.Massless = true
	end
	Kit.weldTo(leaf, details)
	CollectionService:AddTag(model, Tags.StartRoomDoor)
	model:SetAttribute("Open", false)
	model:SetAttribute("HingeCFrame", hinge)
	model:SetAttribute("LeafOffset", offset)
	model:SetAttribute("OpenAngle", -outward * OPEN_ANGLE)
	Kit.attach(model, parent, leaf.Position)
	-- Batentes fixos (moldura) dos dois lados da parede.
	for _, side in { -1, 1 } do
		local z = slot.center.Z + side * (wallThickness / 2 + 0.1)
		for _, x in { slot.center.X - slot.width / 2 - 0.3, slot.center.X + slot.width / 2 + 0.3 } do
			Kit.box(
				ctx,
				parent,
				"Batente",
				Vector3.new(x, floorY + slot.height / 2, z),
				Vector3.new(0.6, slot.height, 0.25),
				Palette.Trim,
				M.Wood,
				nil,
				GHOST_NO_SHADOW
			)
		end
		Kit.box(
			ctx,
			parent,
			"Batente",
			Vector3.new(slot.center.X, floorY + slot.height + 0.35, z),
			Vector3.new(slot.width + 1.2, 0.7, 0.25),
			Palette.Trim,
			M.Wood,
			nil,
			GHOST_NO_SHADOW
		)
	end
	return { model = model, leaf = leaf, hinge = hinge, offset = offset, openAngle = -outward * OPEN_ANGLE }
end

-- Constrói a sala inicial dentro do Room (ver Rooms.new). Retorna os dados da sala para o MapBuilder.
function StartRoom.Build(ctx, room, doorSlots, sealParts: { BasePart })
	local model, rng = room.model, room.rng

	-- Armas nos quatro cantos (reservadas antes de qualquer móvel).
	for _, corner in { { -10.5, -10.5 }, { 10.5, -10.5 }, { -10.5, 10.5 }, { 10.5, 10.5 } } do
		room:occupy(corner[1], corner[2], 1.5, 1.5)
		Kit.weaponSpawn(ctx, room:at(corner[1], corner[2], 0, 1.5).Position, room.name)
	end

	-- Spawns dos jogadores em volta da mesa, olhando para o tabuleiro.
	local center = room:at(0, 0).Position
	local playerSpawns = {}
	for i = 1, SPAWN_COUNT do
		local angle = math.rad(22.5 + (i - 1) * (360 / SPAWN_COUNT))
		local x, z = math.cos(angle) * SPAWN_RADIUS, math.sin(angle) * SPAWN_RADIUS
		room:occupy(x, z, 1.2, 1.2)
		local position = room:at(x, z, 0, 3).Position
		local cframe = CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z))
		Kit.marker(ctx, "PlayerSpawn" .. i, cframe, Vector3.new(2, 1, 2), Tags.PlayerSpawn)
		table.insert(playerSpawns, cframe)
	end

	-- Mesa do tabuleiro e cadeiras.
	room:rug(0, 0, 20, 17, Palette.Fabrics[1], Palette.Gold)
	room:occupy(0, 0, 6.6, 5.2)
	local tableCF = room:at(0, 0)
	Furniture.Table(ctx, model, tableCF, 10, 7, TABLE_HEIGHT, Palette.WoodDark)
	for _, x in { -2.5, 2.5 } do
		Furniture.Chair(ctx, model, tableCF * CFrame.new(x, 0, 4.6), Palette.WoodDark, Palette.Fabrics[1])
		Furniture.Chair(
			ctx,
			model,
			tableCF * CFrame.new(x, 0, -4.6) * CFrame.Angles(0, math.pi, 0),
			Palette.WoodDark,
			Palette.Fabrics[1]
		)
	end
	Furniture.Chair(
		ctx,
		model,
		tableCF * CFrame.new(6.1, 0, 0) * CFrame.Angles(0, math.rad(90), 0),
		Palette.WoodDark,
		Palette.Fabrics[1]
	)
	Furniture.Chair(
		ctx,
		model,
		tableCF * CFrame.new(-6.1, 0, 0) * CFrame.Angles(0, math.rad(-90), 0),
		Palette.WoodDark,
		Palette.Fabrics[1]
	)
	local boardSpawn = CFrame.new(tableCF.Position + Vector3.new(0, TABLE_HEIGHT, 0))
	Kit.marker(ctx, "BoardSpawn", boardSpawn, Vector3.new(1, 0.2, 1), Tags.BoardSpawn)

	-- Lareira acesa numa parede lateral e estantes na outra.
	room:against("left", 0, 7.5, 2.4, function(cf)
		Furniture.Fireplace(ctx, model, cf, 7, room.h, true, true)
	end)
	for _, along in { -5, 5 } do
		room:against("right", along, 6, 1.6, function(cf)
			Furniture.Bookshelf(ctx, model, cf, 6, 10, 1.6, rng)
		end)
	end
	-- Tambores antigos entre as estantes (o "chamado" do tabuleiro).
	room:against("right", 0, 3.2, 3.2, function(cf)
		Furniture.Drum(ctx, model, cf, 2.6, 3)
		Furniture.Drum(ctx, model, cf * CFrame.new(-1.2, 0, -2.3), 1.6, 2, Palette.Wood)
	end)
	room:against("left", -6.8, 3.4, 2.2, function(cf)
		Furniture.Chest(ctx, model, cf, Palette.WoodRed)
	end)

	-- Lustre (a luz principal da sala, com sombra) e decoração nas paredes.
	room:chandelier(0, 0, 32, true, 4, 4)
	for _, wall in { "front", "back" } do
		for _, along in { -8, 8 } do
			room:wallItem(wall, along, 8, 4.5, 3.5, function(cf)
				Furniture.Painting(ctx, model, cf, 4.5, 3.5, rng)
			end)
		end
	end
	for _, along in { -7.5, 7.5 } do
		room:wallItem("left", along, 9, 2, 2.8, function(cf)
			Furniture.Mask(ctx, model, cf, rng)
		end)
	end
	-- Cipós descendo pelos cantos: a selva já está chegando.
	for _, corner in { { -13, -13 }, { 13, -13 }, { -13, 13 }, { 13, 13 } } do
		local length = rng:NextNumber(5, 9)
		local top = room:at(corner[1], corner[2], 0, room.h - 0.1).Position
		Kit.box(
			ctx,
			model,
			"Cipo",
			CFrame.new(top - Vector3.new(0, length / 2, 0)) * CFrame.Angles(0, math.rad(45), 0),
			Vector3.new(1.2, length, 0.3),
			Palette.Vine,
			M.Grass,
			nil,
			GHOST_NO_SHADOW
		)
	end

	-- Portas (Models com tag StartRoomDoor) nos vãos deixados pela Mansion. Ficam fora do Model do
	-- cômodo para nunca serem escondidas pela distância de renderização.
	local doorsModel = Kit.model("Sala de Jogos - Portas")
	local doors = {}
	for index, slot in doorSlots do
		table.insert(doors, buildDoor(ctx, doorsModel, slot, index, 1))
	end
	Kit.attach(doorsModel, ctx.map, room:at(0, 0, 0, 5).Position)
	for _, part in sealParts do
		part:SetAttribute("StartRoomSeal", true)
	end

	local roomCenter = room:at(0, 0, 0, room.h / 2).Position
	return {
		startRoom = { cframe = CFrame.new(roomCenter), size = Vector3.new(room.w, room.h, room.d) },
		boardSpawn = boardSpawn,
		playerSpawns = playerSpawns,
		doors = doors,
		sealParts = sealParts,
		opened = false,
	}
end

-- Lê as portas pelas tags (caso o estado do Build não esteja disponível).
local function doorsFromTags(): { DoorRecord }
	local doors = {}
	for _, model in CollectionService:GetTagged(Tags.StartRoomDoor) do
		local leaf = model:FindFirstChild("Folha")
		local hinge = model:GetAttribute("HingeCFrame")
		local offset = model:GetAttribute("LeafOffset")
		local angle = model:GetAttribute("OpenAngle")
		if leaf and typeof(hinge) == "CFrame" and typeof(offset) == "CFrame" and type(angle) == "number" then
			table.insert(doors, { model = model, leaf = leaf, hinge = hinge, offset = offset, openAngle = angle })
		end
	end
	return doors
end

local function openDoor(door: DoorRecord)
	if door.model:GetAttribute("Open") then
		return
	end
	door.model:SetAttribute("Open", true)
	local value = Instance.new("NumberValue")
	value.Name = "AnguloDaPorta"
	value.Value = 0
	value.Parent = door.model
	local connection = value.Changed:Connect(function(angle)
		if door.leaf.Parent then
			door.leaf.CFrame = door.hinge * CFrame.Angles(0, angle, 0) * door.offset
		end
	end)
	local tween = TweenService:Create(
		value,
		TweenInfo.new(OPEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = door.openAngle }
	)
	tween.Completed:Once(function()
		connection:Disconnect()
		if door.leaf.Parent then
			door.leaf.CFrame = door.hinge * CFrame.Angles(0, door.openAngle, 0) * door.offset
		end
		value:Destroy()
		tween:Destroy()
	end)
	tween:Play()
	SoundUtil.Play("DoorOpen", { Position = door.leaf.Position, Volume = 0.8 })
end

-- Abre as portas (tween na dobradiça) e libera a destruição das paredes da sala. Não cede (não usa wait).
function StartRoom.OpenDoors(state)
	local doors = state and state.doors or doorsFromTags()
	for _, door in doors do
		openDoor(door)
	end
	if state and state.opened then
		return
	end
	local seal = state and state.sealParts
	if not seal then
		-- Sem o estado do Build: procura as parts marcadas no mapa.
		seal = {}
		local map = workspace:FindFirstChild("Map")
		if map then
			for _, descendant in map:GetDescendants() do
				if descendant:IsA("BasePart") and descendant:GetAttribute("StartRoomSeal") then
					table.insert(seal, descendant)
				end
			end
		end
	end
	if state then
		state.opened = true
	end
	for _, part in seal do
		if part.Parent and part:GetAttribute("StartRoomSeal") then
			part:SetAttribute("StartRoomSeal", nil)
			CollectionService:RemoveTag(part, Tags.Indestructible)
			CollectionService:AddTag(part, Tags.Destructible)
		end
	end
end

return StartRoom
