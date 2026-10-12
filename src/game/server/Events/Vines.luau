--!nonstrict
-- Evento físico "Cipós Carnívoros": cipós (cadeias de cilindros verdes) crescem a partir do ponto do evento
-- pelo chão e sobem pelas paredes. Encostar num cipó prende o jogador (WalkSpeed 2 por 1,5 s) e machuca.
-- Plantas carnívoras (NPC "Plant") brotam entre os cipós; quando todas morrem, os cipós murcham e o
-- evento acaba antes do tempo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)

local PhysUtil = require(script.Parent.Parent.EventHelpers.PhysUtil)

local START_TENDRILS = 6
local MAX_TENDRILS = 11
local SEGMENT_LENGTH = 3
local MAX_SEGMENTS = 110 -- orçamento total de segmentos (celular)
local MAX_SEGMENTS_PER_TENDRIL = 18
local BRANCH_EVERY = 6
local GROW_INTERVAL = 0.35
local MAX_CLIMB = 10
local LEAF_EVERY = 3
local START_THICKNESS = 1.1
local MIN_THICKNESS = 0.45
local SNARE_SPEED = 2
local SNARE_TIME = 1.5
local SNARE_DAMAGE = 5
local SNARE_COOLDOWN = 1.5
local SNARE_NOTIFY_COOLDOWN = 8
local TOUCH_INTERVAL = 0.15
local TOUCH_REACH = 1.3 -- folga entre o cipó e o corpo do jogador
local PLANT_MIN, PLANT_MAX = 3, 6
local PLANT_INTERVAL = 1.6
local NO_PLANT_TIMEOUT = 40 -- sem plantas (limite de NPCs): os cipós murcham depois disto
local WITHER_STEPS = 5
local SOURCE = "Cipós Carnívoros"

local VINE_COLORS = { Color3.fromRGB(46, 108, 40), Color3.fromRGB(58, 124, 46), Color3.fromRGB(38, 92, 36) }
local LEAF_COLOR = Color3.fromRGB(86, 156, 60)
local WITHERED = Color3.fromRGB(112, 86, 52)

return {
	Id = "Vines",
	DisplayName = "Cipós Carnívoros",
	Kind = "physical",
	Riddles = {
		"Verdes serpentes sobem pela parede;\nflores com dentes estão com muita sede.",
		"Não toque nos cipós que brotam do chão;\na flor faminta quer morder a sua mão.",
		"Raízes famintas rastejam devagar;\nse um cipó te pegar, não vai te soltar.",
	},
	Weight = 1,
	MinSpace = 3,
	Duration = 90,
	Radius = 45,

	Start = function(ctx)
		local trove = PhysUtil.newTrove()
		local services = PhysUtil.Services(ctx)
		local NPC = services.NPC
		local Combat = services.Combat
		local Ground = services.Ground
		local rng = ctx.random
		local center = ctx.position
		local radius = ctx.radius
		local modifierKey = "Vines:" .. ctx.instanceId
		local groundY = PhysUtil.EventGroundY(center)
		local origin = Vector3.new(center.X, groundY + 0.45, center.Z)
		local rayParams = PhysUtil.RaycastParams()

		local segments = {} -- { a: Vector3, b: Vector3, radius: number, part: BasePart }
		local leaves: { BasePart } = {}
		local tendrils = {}
		local withering = false
		local cleaned = false

		-- Construção ------------------------------------------------------------------------------
		local function addSegment(tendril, a: Vector3, b: Vector3)
			local cframe, length = PhysUtil.CylinderBetween(a, b)
			if length < 0.2 then
				return
			end
			local progress = tendril.segments / (MAX_SEGMENTS_PER_TENDRIL * 1.3)
			local thickness = math.max(tendril.thickness * (1 - progress), MIN_THICKNESS)
			local part = PhysUtil.GhostPart({
				Name = "Cipo",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(length + thickness * 0.6, thickness, thickness),
				CFrame = cframe,
				Color = VINE_COLORS[rng:NextInteger(1, #VINE_COLORS)],
				Material = Enum.Material.Grass,
				Parent = ctx.folder,
			})
			table.insert(segments, { a = a, b = b, radius = thickness / 2, part = part })
			tendril.segments += 1
			if tendril.segments % LEAF_EVERY == 0 then
				local middle = (a + b) / 2
				local leaf = PhysUtil.GhostPart({
					Name = "Folha",
					Size = Vector3.new(1, 0.12, 0.7),
					CFrame = CFrame.new(middle + Vector3.new(0, thickness * 0.4, 0))
						* CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, math.pi * 2), 0)
						* CFrame.new(thickness * 0.5 + 0.4, 0, 0),
					Color = LEAF_COLOR,
					Material = Enum.Material.Grass,
					Parent = ctx.folder,
				})
				table.insert(leaves, leaf)
			end
		end

		local function newTendril(position: Vector3, direction: Vector3, thickness: number)
			if #tendrils >= MAX_TENDRILS then
				return
			end
			table.insert(tendrils, {
				pos = position,
				dir = PhysUtil.FlatUnit(direction),
				mode = "ground",
				normal = Vector3.zero,
				climbed = 0,
				segments = 0,
				thickness = thickness,
				alive = true,
			})
		end

		local function growGround(tendril)
			tendril.dir = (CFrame.Angles(0, rng:NextNumber(-0.45, 0.45), 0) * tendril.dir).Unit
			local nextFlat = tendril.pos + tendril.dir * SEGMENT_LENGTH
			if PhysUtil.FlatDistance(nextFlat, center) > radius then
				tendril.alive = false
				return
			end
			-- Parede à frente: o cipó encosta nela e começa a subir.
			local wall = workspace:Raycast(tendril.pos, tendril.dir * SEGMENT_LENGTH, rayParams)
			if wall and math.abs(wall.Normal.Y) < 0.5 then
				local contact = wall.Position + wall.Normal * 0.5
				addSegment(tendril, tendril.pos, contact)
				tendril.pos = contact
				tendril.mode = "wall"
				tendril.normal = PhysUtil.FlatUnit(wall.Normal)
				tendril.climbed = 0
				return
			end
			-- Segue o chão (degraus baixos); sem chão (beirada), o cipó para.
			local ground = workspace:Raycast(nextFlat + Vector3.new(0, 3, 0), Vector3.new(0, -7, 0), rayParams)
			if not ground then
				tendril.alive = false
				return
			end
			local point = ground.Position + Vector3.new(0, 0.45, 0)
			addSegment(tendril, tendril.pos, point)
			tendril.pos = point
		end

		local function growWall(tendril)
			local along = tendril.normal:Cross(Vector3.yAxis)
			local delta = Vector3.new(0, SEGMENT_LENGTH * 0.85, 0) + along * rng:NextNumber(-0.9, 0.9)
			local nextPoint = tendril.pos + delta
			-- Teto (ou outra coisa) no caminho: para de subir.
			if workspace:Raycast(tendril.pos, delta, rayParams) then
				tendril.alive = false
				return
			end
			-- A parede acabou (topo de uma cerca ou de uma parede baixa): para.
			if not workspace:Raycast(nextPoint, -tendril.normal * 1.6, rayParams) then
				tendril.alive = false
				return
			end
			addSegment(tendril, tendril.pos, nextPoint)
			tendril.pos = nextPoint
			tendril.climbed += delta.Y
			if tendril.climbed >= MAX_CLIMB then
				tendril.alive = false
			end
		end

		-- Crescimento ao longo do tempo.
		for index = 1, START_TENDRILS do
			local angle = (index / START_TENDRILS) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			newTendril(origin, Vector3.new(math.cos(angle), 0, math.sin(angle)), START_THICKNESS)
		end
		trove:Spawn(function()
			while ctx.isActive() and not withering and #segments < MAX_SEGMENTS do
				local growing = 0
				for _, tendril in table.clone(tendrils) do
					if tendril.alive and #segments < MAX_SEGMENTS then
						growing += 1
						if tendril.mode == "ground" then
							growGround(tendril)
						else
							growWall(tendril)
						end
						if tendril.segments >= MAX_SEGMENTS_PER_TENDRIL then
							tendril.alive = false
						end
						-- Galhos: de vez em quando nasce um cipó novo para o lado.
						if
							tendril.alive
							and tendril.mode == "ground"
							and tendril.segments > 0
							and tendril.segments % BRANCH_EVERY == 0
						then
							local side = rng:NextNumber() < 0.5 and -1 or 1
							local branchDir = CFrame.Angles(0, side * rng:NextNumber(0.6, 1.1), 0) * tendril.dir
							newTendril(tendril.pos, branchDir, math.max(tendril.thickness * 0.8, MIN_THICKNESS + 0.2))
						end
					end
				end
				if growing == 0 then
					break
				end
				task.wait(GROW_INTERVAL)
			end
		end)

		-- Plantas carnívoras -----------------------------------------------------------------------
		local plantsSpawned = 0
		local plantPhaseDone = false
		local function plantPoint(): Vector3
			-- De preferência na ponta de um cipó que está no chão; senão, um ponto livre perto do centro.
			local candidates = {}
			for _, tendril in tendrils do
				if tendril.mode == "ground" and tendril.segments >= 2 then
					table.insert(candidates, tendril.pos)
				end
			end
			if #candidates > 0 and rng:NextNumber() < 0.7 then
				local point = candidates[rng:NextInteger(1, #candidates)]
				local ground = Ground.FindGround(point, 8, 2)
				if ground then
					return ground
				end
			end
			return Ground.RandomPointNear(center, 6, radius * 0.6, rng, 8)
		end

		trove:Spawn(function()
			local total = rng:NextInteger(PLANT_MIN, PLANT_MAX)
			if NPC and type(NPC.Spawn) == "function" then
				for _ = 1, total do
					task.wait(PLANT_INTERVAL)
					if not ctx.isActive() or withering then
						break
					end
					local point = plantPoint()
					local cframe = CFrame.new(point) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
					local ok, model = pcall(NPC.Spawn, "Plant", cframe, { groupId = ctx.instanceId })
					if ok and model then
						plantsSpawned += 1
						SoundUtil.Play("Crumble", { Position = point, RollOffMaxDistance = 100, Volume = 0.4 })
					elseif not ok then
						warn("[Vines] Erro ao criar planta carnívora: " .. tostring(model))
					end
				end
			else
				warn("[Vines] NPCService indisponível: os cipós vão aparecer sem plantas carnívoras.")
			end
			plantPhaseDone = true
		end)

		-- Murchar e terminar.
		local function wither(message: string?)
			if withering or not ctx.isActive() then
				return
			end
			withering = true
			PhysUtil.ClearModifiersWithKey(modifierKey)
			if message then
				for _, target in PhysUtil.PlayersInRadius(center, radius * 3) do
					PhysUtil.Notify(target.player, message, "success")
				end
			end
			local originals = {}
			for _, segment in segments do
				originals[segment.part] = segment.part.Color
			end
			for _, leaf in leaves do
				originals[leaf] = leaf.Color
			end
			for step = 1, WITHER_STEPS do
				task.wait(0.4)
				if cleaned then
					return
				end
				local alpha = step / WITHER_STEPS
				for part, color in originals do
					if part.Parent then
						part.Color = color:Lerp(WITHERED, alpha)
						part.Transparency = alpha * 0.6
					end
				end
			end
			if ctx.isActive() then
				ctx.finish()
			end
		end

		trove:Spawn(function()
			local started = os.clock()
			while ctx.isActive() and not withering do
				task.wait(1)
				if plantPhaseDone then
					if plantsSpawned > 0 then
						local ok, alive = pcall(NPC.CountAlive, ctx.instanceId)
						if ok and type(alive) == "number" and alive <= 0 then
							wither("As plantas carnívoras morreram: os cipós estão murchando!")
						end
					elseif os.clock() - started >= NO_PLANT_TIMEOUT then
						wither(nil)
					end
				end
			end
		end)

		-- Toque nos cipós ----------------------------------------------------------------------------
		local canHurt = PhysUtil.newCooldown(SNARE_COOLDOWN)
		local canWarn = PhysUtil.newCooldown(SNARE_NOTIFY_COOLDOWN)
		-- Renovar a prisão a cada checagem criaria uma thread nova por vez: só renova perto de acabar.
		local snaredUntil: { [Humanoid]: number } = setmetatable({}, { __mode = "k" }) :: any
		local function touchesVine(point: Vector3): boolean
			for _, segment in segments do
				if PhysUtil.DistanceToSegment(point, segment.a, segment.b) <= segment.radius + TOUCH_REACH then
					return true
				end
			end
			return false
		end

		trove:Spawn(function()
			while ctx.isActive() and not withering do
				task.wait(TOUCH_INTERVAL)
				if #segments > 0 and not withering then
					for _, target in PhysUtil.PlayersInRadius(center, radius + 15, true) do
						local rootPosition = target.root.Position
						if touchesVine(rootPosition - Vector3.new(0, 2.2, 0)) or touchesVine(rootPosition) then
							local now = os.clock()
							if (snaredUntil[target.humanoid] or 0) - now < SNARE_TIME * 0.5 then
								snaredUntil[target.humanoid] = now + SNARE_TIME
								PhysUtil.SetTimedModifier(
									target.humanoid,
									modifierKey,
									{ walkSpeed = SNARE_SPEED, jumpMultiplier = 0.2 },
									SNARE_TIME
								)
							end
							if canHurt(target.player) then
								Combat.DamagePlayer(target.player, SNARE_DAMAGE, SOURCE)
							end
							if canWarn(target.player) then
								PhysUtil.Notify(target.player, "Um cipó prendeu você! Afaste-se devagar.", "warning")
							end
						end
					end
				end
			end
		end)

		return function()
			if cleaned then
				return
			end
			cleaned = true
			trove:Clean()
			PhysUtil.ClearModifiersWithKey(modifierKey)
			if NPC and type(NPC.DespawnGroup) == "function" then
				local ok, err = pcall(NPC.DespawnGroup, ctx.instanceId)
				if not ok then
					warn("[Vines] Erro ao remover as plantas: " .. tostring(err))
				end
			end
		end
	end,
}
