--!nonstrict
-- Evento físico "Pelicano Ladrão": um pelicano gigante (modelo de blocos, ancorado, voando por CFrame)
-- mergulha até o tabuleiro, trava o tabuleiro (quem carregava larga), agarra e voa com ele até uma região
-- distante (de preferência o labirinto, a estufa ou um cômodo longe) e o solta no chão. Todos são avisados
-- de onde ele caiu. Se o evento acabar no meio do voo, o tabuleiro volta para o chão num lugar válido.
--
-- Durante o voo as parts do tabuleiro ficam soldadas na base (só a base é movida e replica), e no fim tudo
-- volta exatamente como estava antes de o BoardService assumir de novo (PlaceAt + SetLocked(false)).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local Tags = require(ReplicatedStorage.Shared.Tags)

local PhysCreatures = require(script.Parent.Parent.EventHelpers.PhysCreatures)
local PhysUtil = require(script.Parent.Parent.EventHelpers.PhysUtil)

local SPAWN_DISTANCE = 170
local SPAWN_HEIGHT = 60
local APPROACH_SPEED = 48
local CARRY_SPEED = 40
local LEAVE_SPEED = 45
local LOCK_DISTANCE = 10 -- trava o tabuleiro (quem carrega larga) um pouco antes de agarrar
local GRAB_DISTANCE = 2.5
local APPROACH_TIMEOUT = 25
local CRUISE_HEIGHT = 45
local HOVER_HEIGHT = 3.4 -- altura do corpo do pelicano acima do chão ao agarrar/soltar
local HANG = CFrame.new(0, -3.4, -1.2) -- onde o tabuleiro fica pendurado (relativo ao corpo)
local MIN_DESTINATION_DISTANCE = 120
local ISLAND_MARGIN = 30
local LEAVE_TIME = 3
local NEAR_DESTINATION = 40
local CLEARANCE = Vector3.new(5, 5.6, 5) -- espaço livre exigido acima do ponto de queda
local FALLBACK_REGION = "algum canto da ilha"

-- Só um pelicano carrega o tabuleiro por vez (um segundo evento simultâneo só sobrevoa e vai embora).
local holder: string? = nil

local function shuffle(list: { any }, rng: Random)
	for index = #list, 2, -1 do
		local other = rng:NextInteger(1, index)
		list[index], list[other] = list[other], list[index]
	end
end

local function isPreferredRegion(name: string): boolean
	return name:sub(1, 10) == "Labirinto " or name == "Clareira do Labirinto" or name == "Estufa"
end

return {
	Id = "Pelican",
	DisplayName = "Pelicano Ladrão",
	Kind = "physical",
	Riddles = {
		"Asas enormes e um bico guloso;\nleva o que é seu esse ladrão ardiloso.",
		"Do céu vem um bico que tudo carrega;\nsegure o tabuleiro, que a ave não sossega.",
		"Um ladrão de penas mergulha do alto;\no jogo some num único salto.",
	},
	Weight = 0.8,
	MinSpace = 2,
	Duration = 60,
	Radius = 30,

	Start = function(ctx)
		local trove = PhysUtil.newTrove()
		local services = PhysUtil.Services(ctx)
		local Board = services.Board
		local Ground = services.Ground
		local Map = services.Map
		local rng = ctx.random
		local cleaned = false

		if not Board or type(Board.GetBoardPosition) ~= "function" then
			warn("[Pelican] BoardService indisponível: o pelicano não tem o que roubar.")
			task.defer(ctx.finish)
			return function() end
		end

		-- Estado do roubo.
		local locked = false -- este evento travou o tabuleiro
		local attached = nil -- { base, pivotToBase, anchored = {[BasePart]=bool}, welds = {Instance} }
		local grabCFrame: CFrame? = nil -- onde o tabuleiro estava quando foi agarrado
		local destination: Vector3? = nil

		-- Pelicano ---------------------------------------------------------------------------------
		local boardStart = Board.GetBoardPosition()
		local fromDirection = PhysUtil.RandomFlatUnit(rng)
		local position = boardStart + fromDirection * SPAWN_DISTANCE + Vector3.new(0, SPAWN_HEIGHT, 0)
		local look = PhysUtil.FlatUnit(boardStart - position)
		local pelican = PhysCreatures.Pelican(ctx.folder, CFrame.lookAt(position, position + look))
		trove:Add(pelican.model)
		local root = pelican.root
		SoundUtil.Play("Pelican", { Parent = root, Volume = 1, RollOffMaxDistance = 400 })

		local function moveBoard()
			if attached and attached.base.Parent then
				attached.base.CFrame = root.CFrame * HANG * attached.pivotToBase
			end
		end

		local function setPose(forward: Vector3?, flapping: boolean)
			if forward then
				local flat = Vector3.new(forward.X, 0, forward.Z)
				if flat.Magnitude > 0.5 then
					look = flat.Unit
				end
			end
			if not root.Parent then
				return
			end
			root.CFrame = CFrame.lookAt(position, position + look)
			local angle = if flapping then math.sin(os.clock() * 9) * 0.6 else 0.12
			PhysCreatures.SetWings(pelican, angle)
			moveBoard()
		end

		-- Avança na direção do alvo; true quando chegou.
		local function flyTowards(target: Vector3, speed: number, dt: number): boolean
			local delta = target - position
			local distance = delta.Magnitude
			local stepLength = speed * math.min(dt, 0.1)
			if distance <= stepLength then
				position = target
				return true
			end
			position += delta.Unit * stepLength
			return false
		end

		-- Tabuleiro: soldar na base durante o voo e devolver tudo como estava ------------------------
		local function attachBoard(): boolean
			local model = Board.GetBoardModel()
			if not model or not model.Parent then
				return false
			end
			local base = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
			if not base then
				return false
			end
			local state = {
				base = base,
				pivotToBase = model:GetPivot():ToObjectSpace(base.CFrame),
				anchored = {},
				welds = {},
			}
			-- Solda primeiro (tudo ainda ancorado) e só depois solta as partes: nada cai no meio.
			local toRelease = {}
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and part ~= base and part.Anchored then
					local weld = Instance.new("WeldConstraint")
					weld.Name = "SoldaDoPelicano"
					weld.Part0 = base
					weld.Part1 = part
					weld.Parent = base
					table.insert(state.welds, weld)
					table.insert(toRelease, part)
				end
			end
			for _, part in toRelease do
				state.anchored[part] = true
				part.Anchored = false
			end
			base.Anchored = true
			grabCFrame = model:GetPivot()
			attached = state
			return true
		end

		local function detachBoard()
			local state = attached
			if not state then
				return
			end
			attached = nil
			for part, wasAnchored in state.anchored do
				if part.Parent then
					part.Anchored = wasAnchored
				end
			end
			for _, weld in state.welds do
				weld:Destroy()
			end
		end

		local function unlock()
			if locked then
				locked = false
				pcall(Board.SetLocked, false)
			end
			if holder == ctx.instanceId then
				holder = nil
			end
		end

		-- Escolha do destino ---------------------------------------------------------------------------
		local clearanceParams = PhysUtil.OverlapParams(false, 8)
		clearanceParams.RespectCanCollide = true

		-- Chão válido: firme, fora d'água, dentro da ilha e com espaço livre em cima (nada de cerca ou móvel).
		local function validGround(probe: Vector3, maxDrop: number, floorY: number?): Vector3?
			local ground, hit = Ground.FindGround(probe, maxDrop, 0)
			if not ground or not hit then
				return nil
			end
			if CollectionService:HasTag(hit, Tags.Water) then
				return nil
			end
			if floorY and ground.Y > floorY + 5 then
				return nil
			end
			if not PhysUtil.IsInsideIsland(ctx.mapInfo, ground, ISLAND_MARGIN) then
				return nil
			end
			clearanceParams.FilterDescendantsInstances = PhysUtil.ExcludeList(false)
			local blocking = workspace:GetPartBoundsInBox(
				CFrame.new(ground + Vector3.new(0, CLEARANCE.Y / 2 + 0.3, 0)),
				CLEARANCE,
				clearanceParams
			)
			if #blocking > 0 then
				return nil
			end
			return ground
		end

		local function pointInRegion(region): Vector3?
			if typeof(region.cframe) ~= "CFrame" or typeof(region.size) ~= "Vector3" then
				return nil
			end
			local bottom = region.cframe.Position.Y - region.size.Y / 2
			local startHeight = math.min(6, region.size.Y * 0.5)
			for _ = 1, 8 do
				local localPoint = Vector3.new(
					rng:NextNumber(-0.35, 0.35) * region.size.X,
					0,
					rng:NextNumber(-0.35, 0.35) * region.size.Z
				)
				local flat = region.cframe:PointToWorldSpace(localPoint)
				local probe = Vector3.new(flat.X, bottom + startHeight, flat.Z)
				local ground = validGround(probe, startHeight + 6, bottom + 1.5)
				if ground then
					return ground
				end
			end
			return nil
		end

		local function chooseDestination(from: Vector3): (Vector3, string)
			local preferred, others = {}, {}
			local regions = (ctx.mapInfo and type(ctx.mapInfo.regions) == "table") and ctx.mapInfo.regions or {}
			for _, region in regions do
				if
					type(region) == "table"
					and type(region.name) == "string"
					and typeof(region.cframe) == "CFrame"
					and typeof(region.size) == "Vector3"
					and region.size.X < 250
					and region.size.Z < 250
					and PhysUtil.FlatDistance(region.cframe.Position, from) >= MIN_DESTINATION_DISTANCE
					and PhysUtil.IsInsideIsland(ctx.mapInfo, region.cframe.Position, ISLAND_MARGIN)
				then
					if isPreferredRegion(region.name) then
						table.insert(preferred, region)
					else
						table.insert(others, region)
					end
				end
			end
			shuffle(preferred, rng)
			shuffle(others, rng)
			local order = {}
			local first, second = preferred, others
			if rng:NextNumber() >= 0.7 then
				first, second = others, preferred
			end
			for _, region in first do
				table.insert(order, region)
			end
			for _, region in second do
				table.insert(order, region)
			end
			for index, region in order do
				if index > 12 then
					break
				end
				local point = pointInRegion(region)
				if point then
					return point, region.name
				end
			end

			-- Sem região boa: um ponto qualquer da ilha, longe do tabuleiro.
			local groundY = (ctx.mapInfo and ctx.mapInfo.groundY) or from.Y
			local islandCenter = (ctx.mapInfo and ctx.mapInfo.islandCenter) or Vector3.zero
			local islandRadius = (ctx.mapInfo and ctx.mapInfo.islandRadius) or 600
			for _ = 1, 20 do
				local angle = rng:NextNumber(0, math.pi * 2)
				local distance = rng:NextNumber(0, islandRadius - ISLAND_MARGIN * 2)
				local candidate = islandCenter + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
				if PhysUtil.FlatDistance(candidate, from) >= MIN_DESTINATION_DISTANCE then
					local ground = validGround(Vector3.new(candidate.X, groundY + 6, candidate.Z), 14, groundY + 1)
					if ground then
						local name = FALLBACK_REGION
						if Map and type(Map.GetRegionAt) == "function" then
							local ok, region = pcall(Map.GetRegionAt, ground + Vector3.new(0, 2, 0))
							if ok and type(region) == "table" and type(region.name) == "string" then
								name = region.name
							end
						end
						return ground, name
					end
				end
			end
			-- Último recurso: o pelicano desiste e devolve o tabuleiro onde estava.
			return from, "o mesmo lugar (o pelicano desistiu)"
		end

		-- Voo ------------------------------------------------------------------------------------------
		trove:Spawn(function()
			-- 1. Mergulho até o tabuleiro (segue o tabuleiro mesmo que alguém esteja correndo com ele).
			local deadline = os.clock() + APPROACH_TIMEOUT
			while ctx.isActive() do
				local dt = task.wait()
				local target = Board.GetBoardPosition() + Vector3.new(0, HOVER_HEIGHT, 0)
				local flatDistance = PhysUtil.FlatDistance(position, target)
				local aim = target + Vector3.new(0, math.clamp(flatDistance * 0.45, 0, 35), 0)
				flyTowards(aim, APPROACH_SPEED, dt)
				setPose(aim - position, true)
				local distance = (position - target).Magnitude
				local late = os.clock() > deadline
				if not locked and (distance <= LOCK_DISTANCE or late) then
					if holder ~= nil and holder ~= ctx.instanceId then
						break -- outro pelicano já está com o tabuleiro
					end
					holder = ctx.instanceId
					locked = true
					Board.SetLocked(true) -- quem carregava larga o tabuleiro no chão
				end
				if locked and (distance <= GRAB_DISTANCE or late) then
					break
				end
			end
			if not ctx.isActive() then
				return
			end

			if not locked or not attachBoard() then
				-- Não conseguiu pegar: sobrevoa e vai embora.
				unlock()
				local away = position + look * 120 + Vector3.new(0, 60, 0)
				local started = os.clock()
				while ctx.isActive() and os.clock() - started < LEAVE_TIME do
					local dt = task.wait()
					flyTowards(away, LEAVE_SPEED, dt)
					setPose(away - position, true)
				end
				if ctx.isActive() then
					ctx.finish()
				end
				return
			end

			-- 2. Agarrou: avisa todo mundo e escolhe para onde levar.
			moveBoard()
			SoundUtil.Play("Pelican", { Parent = root, Volume = 1, RollOffMaxDistance = 400 })
			PhysUtil.NotifyAll("O pelicano roubou o tabuleiro! Siga-o!", "warning")
			local from = (grabCFrame :: CFrame).Position
			local regionName
			destination, regionName = chooseDestination(from)
			local dest = destination :: Vector3

			-- 3. Sobe, cruza o céu e desce no destino.
			local cruiseY = math.max(position.Y, dest.Y + CRUISE_HEIGHT, from.Y + CRUISE_HEIGHT)
			local path = {
				Vector3.new(position.X, cruiseY, position.Z),
				Vector3.new(dest.X, cruiseY, dest.Z),
				dest + Vector3.new(0, HOVER_HEIGHT, 0),
			}
			for _, waypoint in path do
				while ctx.isActive() do
					local dt = task.wait()
					local arrived = flyTowards(waypoint, CARRY_SPEED, dt)
					setPose(Vector3.new(dest.X, 0, dest.Z) - Vector3.new(position.X, 0, position.Z), true)
					if arrived then
						break
					end
				end
				if not ctx.isActive() then
					return
				end
			end

			-- 4. Solta o tabuleiro no chão e libera.
			detachBoard()
			Board.PlaceAt(CFrame.lookAt(dest, dest + look))
			unlock()
			SoundUtil.Play("Pelican", { Parent = root, Volume = 1, RollOffMaxDistance = 400 })
			PhysUtil.NotifyAll(("O pelicano largou o tabuleiro em: %s!"):format(regionName), "info")

			-- 5. Vai embora e o evento termina.
			local away = position + look * 140 + Vector3.new(0, 70, 0)
			local started = os.clock()
			while ctx.isActive() and os.clock() - started < LEAVE_TIME do
				local dt = task.wait()
				flyTowards(away, LEAVE_SPEED, dt)
				setPose(away - position, true)
			end
			if ctx.isActive() then
				ctx.finish()
			end
		end)

		return function()
			if cleaned then
				return
			end
			cleaned = true
			trove:Clean()
			if attached then
				-- Acabou no meio do voo: perto do destino, solta lá; senão, devolve onde foi agarrado.
				local base = attached.base
				local current = base.Parent and base.Position or position
				detachBoard()
				local target: CFrame
				if destination and PhysUtil.FlatDistance(current, destination) <= NEAR_DESTINATION then
					target = CFrame.lookAt(destination, destination + look)
				elseif grabCFrame then
					target = grabCFrame
				else
					local ground = PhysUtil.GroundAt(current, 400, 2)
					target = CFrame.new(ground or current)
				end
				local ok, err = pcall(Board.PlaceAt, target)
				if not ok then
					warn("[Pelican] Erro ao devolver o tabuleiro: " .. tostring(err))
				end
			end
			unlock()
		end
	end,
}
