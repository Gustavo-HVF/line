--!nonstrict
-- Retextura o mapa em volta de um foco de evento físico (ex.: blocos viram areia em volta da Areia Movediça).
--
--   SurfaceSkin.Apply(skin, center, radius, random?, eventId?)   -- não cede
--     skin = { Material: Enum.Material, Colors: { Color3 } }   (campo Skin da definição do evento)
--
-- Regras:
--   * só mexe no que está em workspace.Map (ignora água, vidro, neon, partes invisíveis e as regiões);
--   * um bloco retexturizado ganha a tag EventSkinned e NUNCA muda de novo (o primeiro evento "ganha");
--   * blocos enormes (chão da ilha, pisos grandes) não mudam inteiros: ganham placas finas por cima numa
--     grade fixa; cada célula da grade recebe no máximo uma placa (a do primeiro evento).
-- A troca é permanente (não volta no fim do evento): o mapa vai mudando conforme a partida avança.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage.Shared.Tags)

local SurfaceSkin = {}

local MAX_PART_SIZE = 40 -- acima disto (maior dimensão) a part recebe placas em vez de mudar inteira
local MAX_PARTS_PER_APPLY = 160
local CELL = 8 -- lado das placas (studs)
local TILE_THICKNESS = 0.12
local MAX_TILES_PER_APPLY = 70
local RAY_START_ABOVE = 7
local RAY_LENGTH = 30

local SKIP_MATERIALS = {
	[Enum.Material.Glass] = true,
	[Enum.Material.Neon] = true,
	[Enum.Material.ForceField] = true,
	[Enum.Material.Water] = true,
}
local SKIP_TAGS = {
	Tags.Water,
	Tags.EventSkinned,
	Tags.Weapon,
	Tags.WeaponSpawn,
	Tags.PlayerSpawn,
	Tags.BoardSpawn,
}

local usedCells: { [string]: boolean } = {}
local tileFolder: Folder? = nil

local function mapFolder(): Instance?
	return workspace:FindFirstChild("Map")
end

local function getTileFolder(map: Instance): Folder
	if tileFolder and tileFolder.Parent then
		return tileFolder
	end
	local folder = map:FindFirstChild("PlacasDeEvento")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "PlacasDeEvento"
		folder.Parent = map
	end
	tileFolder = folder :: Folder
	return tileFolder :: Folder
end

local function maxSize(part: BasePart): number
	local size = part.Size
	return math.max(size.X, size.Y, size.Z)
end

local function canSkin(part: BasePart, regions: Instance?): boolean
	if part.Transparency >= 0.7 or SKIP_MATERIALS[part.Material] then
		return false
	end
	if regions and part:IsDescendantOf(regions) then
		return false
	end
	for _, tag in SKIP_TAGS do
		if CollectionService:HasTag(part, tag) then
			return false
		end
	end
	return true
end

local function pickColor(skin, rng: Random): Color3
	local colors = skin.Colors
	local base = if type(colors) == "table" and #colors > 0
		then colors[rng:NextInteger(1, #colors)]
		else Color3.fromRGB(150, 130, 100)
	local h, s, v = base:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + rng:NextNumber(-0.04, 0.04), 0, 1))
end

local function mark(part: BasePart, eventId: string?)
	CollectionService:AddTag(part, Tags.EventSkinned)
	if eventId then
		part:SetAttribute("EventSkin", eventId)
	end
end

local function skinParts(skin, center: Vector3, radius: number, rng: Random, map: Instance, eventId: string?)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { map }
	params.MaxParts = MAX_PARTS_PER_APPLY * 2
	local regions = map:FindFirstChild("Regions")
	local changed = 0
	for _, part in workspace:GetPartBoundsInRadius(center, radius, params) do
		if changed >= MAX_PARTS_PER_APPLY then
			break
		end
		if part:IsA("BasePart") and maxSize(part) <= MAX_PART_SIZE and canSkin(part, regions) then
			part.Material = skin.Material
			part.Color = pickColor(skin, rng)
			mark(part, eventId)
			changed += 1
		end
	end
end

local function cellKey(position: Vector3): string
	return ("%d,%d,%d"):format(math.floor(position.X / CELL), math.floor(position.Y / 2), math.floor(position.Z / CELL))
end

local function skinTiles(skin, center: Vector3, radius: number, rng: Random, map: Instance, eventId: string?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { map }
	params.IgnoreWater = true
	local regions = map:FindFirstChild("Regions")
	local folder = getTileFolder(map)
	local placed = 0
	local cells = math.ceil(radius / CELL)
	local baseX = math.floor(center.X / CELL)
	local baseZ = math.floor(center.Z / CELL)
	for dx = -cells, cells do
		for dz = -cells, cells do
			if placed >= MAX_TILES_PER_APPLY then
				return
			end
			local x = (baseX + dx + 0.5) * CELL
			local z = (baseZ + dz + 0.5) * CELL
			local flat = Vector3.new(x - center.X, 0, z - center.Z).Magnitude
			-- borda irregular: as células da beirada entram com menos chance
			if flat <= radius and (flat < radius * 0.7 or rng:NextNumber() < 0.55) then
				local origin = Vector3.new(x, center.Y + RAY_START_ABOVE, z)
				local hit = workspace:Raycast(origin, Vector3.new(0, -RAY_LENGTH, 0), params)
				local part = hit and hit.Instance
				if
					hit
					and part
					and part:IsA("BasePart")
					and part.Parent ~= folder
					and hit.Normal.Y > 0.7
					and maxSize(part) > MAX_PART_SIZE
					and canSkin(part, regions)
				then
					local key = cellKey(hit.Position)
					if not usedCells[key] then
						usedCells[key] = true
						local tile = Instance.new("Part")
						tile.Name = "Placa"
						tile.Anchored = true
						tile.CanCollide = false
						tile.CanTouch = false
						tile.CastShadow = false
						tile.Size = Vector3.new(CELL, TILE_THICKNESS, CELL)
						tile.CFrame = CFrame.new(x, hit.Position.Y + TILE_THICKNESS / 2 + 0.02, z)
						tile.Material = skin.Material
						tile.Color = pickColor(skin, rng)
						tile.TopSurface = Enum.SurfaceType.Smooth
						tile.BottomSurface = Enum.SurfaceType.Smooth
						tile.CanQuery = false
						mark(tile, eventId)
						tile.Parent = folder
						placed += 1
					end
				end
			end
		end
	end
end

function SurfaceSkin.Apply(skin, center: Vector3, radius: number, random: Random?, eventId: string?)
	if type(skin) ~= "table" or typeof(skin.Material) ~= "EnumItem" or typeof(center) ~= "Vector3" then
		return
	end
	local map = mapFolder()
	if not map or not (radius > 0) then
		return
	end
	local rng = random or Random.new()
	local ok, err = pcall(skinParts, skin, center, radius, rng, map, eventId)
	if not ok then
		warn("[SurfaceSkin] Erro ao retexturizar blocos: " .. tostring(err))
	end
	ok, err = pcall(skinTiles, skin, center, radius, rng, map, eventId)
	if not ok then
		warn("[SurfaceSkin] Erro ao criar placas: " .. tostring(err))
	end
end

return SurfaceSkin
