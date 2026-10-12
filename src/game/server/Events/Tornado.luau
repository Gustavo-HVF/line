--!nonstrict
-- Evento físico "Tornado": um funil de vento (cilindros translúcidos girando, com pedaços orbitando e
-- poeira) desce do céu, anda devagar pela área por ~40 s e sobe de volta. Puxa e levanta objetos soltos e
-- pedaços (velocidade tangencial + para cima), quebra (com chance) partes Destructible que toca e
-- arremessa jogadores para o alto com dano.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local Tags = require(ReplicatedStorage.Shared.Tags)

local PhysUtil = require(script.Parent.Parent.EventHelpers.PhysUtil)

local FUNNEL_HEIGHT = 60
local SEGMENTS = 7
local BASE_DIAMETER = 5
local TOP_DIAMETER = 38
local ORBIT_BITS = 8
local SPIN_SPEED = 2.6 -- rad/s
local WANDER_SPEED = 9
local TOUCHDOWN_TIME = 3
local ACTIVE_TIME = 38
local LIFTOFF_TIME = 3
local EDGE_MARGIN = 45
local EFFECT_INTERVAL = 0.1
local PULL_RADIUS = 24
local PULL_CENTER_HEIGHT = 12
local SWIRL_SPEED = 38
local INWARD_SPEED = 14
local LIFT_SPEED = 34
local FLING_SPEED = 60
local MAX_LIFTED_PER_TICK = 35
local LIFTED_LIFETIME = 25
local BREAK_INTERVAL = 0.4
local BREAK_RADIUS = 9
local BREAK_HEIGHT = 30
local BREAK_CHANCE = 0.35
local MAX_BREAKS_PER_TICK = 3
local BREAK_IMPULSE = 70
local PLAYER_RADIUS = 10
local PLAYER_DAMAGE = 10
local PLAYER_COOLDOWN = 1.2
local PLAYER_FLING = 80
local SUCTION_RADIUS = 32
local SUCTION_INTERVAL = 0.8
local SUCTION_STRENGTH = 10
local SHAKE_INTERVAL = 1
local SOURCE = "Tornado"

local FUNNEL_COLORS = { Color3.fromRGB(128, 126, 120), Color3.fromRGB(104, 102, 98), Color3.fromRGB(146, 142, 134) }
local DUST_COLOR = Color3.fromRGB(142, 122, 96)
local BIT_COLORS = { Color3.fromRGB(96, 70, 42), Color3.fromRGB(70, 110, 52), Color3.fromRGB(120, 100, 76) }

return {
	Id = "Tornado",
	DisplayName = "Tornado",
	Kind = "physical",
	Riddles = {
		"Um funil de vento desce do céu cinzento;\nsegure-se firme ou voe com o vento.",
		"Um vento que gira e não sabe parar;\no que não está preso, ele vai levar.",
		"Rodopia, rodopia a fúria do ar;\ncadeiras e gente vão sair a voar.",
	},
	Weight = 0.8,
	MinSpace = 10,
	Duration = 48,
	Radius = 70,

	Start = function(ctx)
		local trove = PhysUtil.newTrove()
		local services = PhysUtil.Services(ctx)
		local Destruction = services.Destruction
		local Combat = services.Combat
		local rng = ctx.random
		local center = ctx.position
		local radius = ctx.radius

		local islandGround = (ctx.mapInfo and ctx.mapInfo.groundY) or PhysUtil.EventGroundY(center)
		local baseY = PhysUtil.EventGroundY(center)
		if baseY > islandGround + 6 then
			baseY = islandGround -- evento no andar de cima: o tornado anda pelo térreo
		end

		-- Funil ------------------------------------------------------------------------------------
		local model = Instance.new("Model")
		model.Name = "Tornado"
		local startFlat = center + PhysUtil.RandomFlatUnit(rng) * rng:NextNumber(12, 20)
		local pose = CFrame.new(startFlat.X, baseY + FUNNEL_HEIGHT, startFlat.Z)
		local root = PhysUtil.GhostPart({
			Name = "Raiz",
			Size = Vector3.one,
			CFrame = pose,
			Transparency = 1,
			Parent = model,
		})
		local parts: { BasePart } = { root }
		local visible: { BasePart } = {}
		local segmentHeight = FUNNEL_HEIGHT / SEGMENTS
		local middleSegment: BasePart = root
		for index = 1, SEGMENTS do
			local t = (index - 0.5) / SEGMENTS
			local diameter = BASE_DIAMETER + (TOP_DIAMETER - BASE_DIAMETER) * t ^ 1.6
			local wobble = math.sin(index * 1.3) * 1.2
			local segment = PhysUtil.GhostPart({
				Name = "Funil",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(segmentHeight + 0.6, diameter, diameter),
				CFrame = pose
					* CFrame.new(wobble, (index - 0.5) * segmentHeight, 0)
					* CFrame.Angles(0, 0, math.rad(90)),
				Color = FUNNEL_COLORS[(index % #FUNNEL_COLORS) + 1],
				Material = Enum.Material.SmoothPlastic,
				Transparency = 0.45 + index * 0.035,
				Parent = model,
			})
			table.insert(parts, segment)
			table.insert(visible, segment)
			if index == math.ceil(SEGMENTS / 2) then
				middleSegment = segment
			end
		end
		-- Pedaços orbitando: deixam o giro visível (cilindros girando em volta do eixo parecem parados).
		for index = 1, ORBIT_BITS do
			local height = rng:NextNumber(4, FUNNEL_HEIGHT * 0.8)
			local t = height / FUNNEL_HEIGHT
			local orbit = (BASE_DIAMETER + (TOP_DIAMETER - BASE_DIAMETER) * t ^ 1.6) / 2 + 1.5
			local angle = (index / ORBIT_BITS) * math.pi * 2
			local bit = PhysUtil.GhostPart({
				Name = "Destroco",
				Size = Vector3.new(rng:NextNumber(0.6, 1.6), rng:NextNumber(0.3, 0.8), rng:NextNumber(1, 2.4)),
				CFrame = pose
					* CFrame.new(math.cos(angle) * orbit, height, math.sin(angle) * orbit)
					* CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), rng:NextNumber(0, 3)),
				Color = BIT_COLORS[rng:NextInteger(1, #BIT_COLORS)],
				Material = Enum.Material.Wood,
				Parent = model,
			})
			table.insert(parts, bit)
			table.insert(visible, bit)
		end
		-- Anel de poeira no chão.
		local ring = PhysUtil.GhostPart({
			Name = "Poeira",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 16, 16),
			CFrame = pose * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = DUST_COLOR,
			Transparency = 0.7,
			Parent = model,
		})
		table.insert(parts, ring)
		table.insert(visible, ring)
		PhysUtil.Emitter(ring, {
			Texture = PhysUtil.Textures.Smoke,
			Color = DUST_COLOR,
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 4),
				NumberSequenceKeypoint.new(1, 10),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(1.5, 2.5),
			Rate = 28,
			Speed = NumberRange.new(8, 14),
			EmissionDirection = Enum.NormalId.Right, -- o eixo X do cilindro aponta para cima
			SpreadAngle = Vector2.new(75, 75),
			Acceleration = Vector3.new(0, 6, 0),
			RotSpeed = NumberRange.new(-120, 120),
			Rotation = NumberRange.new(0, 360),
		})
		PhysUtil.Emitter(middleSegment, {
			Texture = PhysUtil.Textures.Smoke,
			Color = FUNNEL_COLORS[2],
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 6),
				NumberSequenceKeypoint.new(1, 12),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.6),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(1.2, 1.8),
			Rate = 10,
			Speed = NumberRange.new(2, 4),
			RotSpeed = NumberRange.new(-200, 200),
			Rotation = NumberRange.new(0, 360),
		})
		PhysUtil.WeldAll(root, parts)
		model.PrimaryPart = root
		model.Parent = ctx.folder
		trove:Add(model)
		SoundUtil.Play("Wind", { Parent = root, Looped = true, Volume = 1, RollOffMaxDistance = 300 })

		-- Movimento ------------------------------------------------------------------------------
		local position = Vector3.new(startFlat.X, baseY, startFlat.Z)
		local height = FUNNEL_HEIGHT -- altura da base acima do chão (desce no começo, sobe no fim)
		local spin = 0
		local phase = "touchdown"
		local phaseStarted = os.clock()
		local waypoint = position

		local function newWaypoint()
			for _ = 1, 10 do
				local candidate = center + PhysUtil.RandomFlatUnit(rng) * rng:NextNumber(0, radius * 0.8)
				if PhysUtil.IsInsideIsland(ctx.mapInfo, candidate, EDGE_MARGIN) then
					waypoint = Vector3.new(candidate.X, baseY, candidate.Z)
					return
				end
			end
			waypoint = Vector3.new(center.X, baseY, center.Z)
		end
		newWaypoint()

		local function grounded(): boolean
			return phase == "active"
		end

		trove:Connect(RunService.Heartbeat, function(dt)
			local step = math.min(dt, 0.1)
			local now = os.clock()
			local elapsed = now - phaseStarted
			if phase == "touchdown" then
				height = FUNNEL_HEIGHT * (1 - math.clamp(elapsed / TOUCHDOWN_TIME, 0, 1))
				if elapsed >= TOUCHDOWN_TIME then
					phase, phaseStarted, height = "active", now, 0
				end
			elseif phase == "active" then
				if elapsed >= ACTIVE_TIME then
					phase, phaseStarted = "liftoff", now
				end
			elseif phase == "liftoff" then
				height = FUNNEL_HEIGHT * math.clamp(elapsed / LIFTOFF_TIME, 0, 1)
			end

			local toWaypoint = waypoint - position
			local flat = Vector3.new(toWaypoint.X, 0, toWaypoint.Z)
			if flat.Magnitude < 4 then
				newWaypoint()
			else
				position += flat.Unit * math.min(WANDER_SPEED * step, flat.Magnitude)
			end
			spin = (spin + SPIN_SPEED * step) % (math.pi * 2)
			local lean = flat.Magnitude > 0.1 and flat.Unit * 0.07 or Vector3.zero
			if root.Parent then
				root.CFrame = CFrame.new(position + Vector3.new(0, height, 0))
					* CFrame.Angles(lean.Z, 0, -lean.X)
					* CFrame.Angles(0, spin, 0)
			end
		end)

		-- Fim: o funil sobe, some e o evento termina.
		trove:Spawn(function()
			while ctx.isActive() and phase ~= "liftoff" do
				task.wait(0.25)
			end
			if not ctx.isActive() then
				return
			end
			local originals = {}
			for _, part in visible do
				originals[part] = part.Transparency
			end
			for stepIndex = 1, 6 do
				task.wait(LIFTOFF_TIME / 6)
				local alpha = stepIndex / 6
				for part, base in originals do
					if part.Parent then
						part.Transparency = base + (1 - base) * alpha
					end
				end
			end
			for _, emitter in model:GetDescendants() do
				if emitter:IsA("ParticleEmitter") then
					emitter.Enabled = false
				end
			end
			task.wait(0.5)
			if ctx.isActive() then
				ctx.finish()
			end
		end)

		-- Efeitos ----------------------------------------------------------------------------------
		local canHit = PhysUtil.newCooldown(PLAYER_COOLDOWN)
		trove:Spawn(function()
			local lastBreak, lastSuction, lastShake = 0, 0, 0
			while ctx.isActive() do
				task.wait(EFFECT_INTERVAL)
				if grounded() then
					local base = Vector3.new(position.X, baseY, position.Z)
					local now = os.clock()

					-- Objetos soltos e pedaços: giram em volta do funil, sobem e são cuspidos lá em cima.
					if Destruction then
						local found = workspace:GetPartBoundsInRadius(
							base + Vector3.new(0, PULL_CENTER_HEIGHT, 0),
							PULL_RADIUS,
							PhysUtil.OverlapParams(true, 150)
						)
						local handled = {}
						local count = 0
						for _, part in found do
							if count >= MAX_LIFTED_PER_TICK then
								break
							end
							local target = Destruction.GetLooseRoot(part)
							if not target and not part.Anchored and CollectionService:HasTag(part, Tags.Debris) then
								target = part.AssemblyRootPart or part
							end
							if target and not handled[target] and target.Parent then
								handled[target] = true
								count += 1
								if CollectionService:HasTag(target, Tags.LooseProp) then
									-- O tornado "leva" o objeto: ele vira pedaço e some depois de um tempo.
									target = Destruction.ReleaseProp(target)
									if target then
										Destruction.RegisterDebris(target, LIFTED_LIFETIME)
									end
								end
								if target and not target.Anchored then
									local offset = target.Position - base
									local flat = Vector3.new(offset.X, 0, offset.Z)
									local distance = flat.Magnitude
									local outward = distance > 0.1 and flat.Unit or Vector3.xAxis
									local velocity
									if offset.Y > FUNNEL_HEIGHT * 0.7 then
										velocity = outward * FLING_SPEED + Vector3.new(0, 8, 0)
									else
										local closeness = 1 - math.clamp(distance / PULL_RADIUS, 0, 1)
										local tangent = Vector3.yAxis:Cross(outward)
										local inward = distance > 6 and -outward * INWARD_SPEED or outward * 3
										velocity = tangent * SWIRL_SPEED * (0.5 + closeness * 0.5)
											+ inward
											+ Vector3.new(0, LIFT_SPEED * (0.35 + closeness * 0.65), 0)
									end
									Destruction.Push(target, velocity)
								end
							end
						end
					end

					-- Partes Destructible tocadas pelo funil quebram (com chance).
					if Destruction and now - lastBreak >= BREAK_INTERVAL then
						lastBreak = now
						local touched = workspace:GetPartBoundsInBox(
							CFrame.new(base + Vector3.new(0, BREAK_HEIGHT / 2, 0)),
							Vector3.new(BREAK_RADIUS * 2, BREAK_HEIGHT, BREAK_RADIUS * 2),
							PhysUtil.OverlapParams(false, 60)
						)
						local breaks = 0
						for _, part in touched do
							if breaks >= MAX_BREAKS_PER_TICK then
								break
							end
							if rng:NextNumber() < BREAK_CHANCE and Destruction.IsDestructible(part) then
								breaks += 1
								local axisPoint = Vector3.new(base.X, part.Position.Y, base.Z)
								Destruction.Fracture(part, PhysUtil.ClosestPointOnPart(part, axisPoint), BREAK_IMPULSE)
							end
						end
					end

					-- Jogadores: perto do eixo voam para o alto; um pouco mais longe são puxados.
					local suction = now - lastSuction >= SUCTION_INTERVAL
					if suction then
						lastSuction = now
					end
					for _, target in PhysUtil.PlayersInRadius(base, SUCTION_RADIUS, true) do
						local offset = target.root.Position - base
						if offset.Y > -4 and offset.Y < FUNNEL_HEIGHT then
							local outward = PhysUtil.FlatUnit(offset, Vector3.xAxis)
							if target.distance <= PLAYER_RADIUS then
								if canHit(target.player) then
									Combat.DamagePlayer(target.player, PLAYER_DAMAGE, SOURCE)
									local tangent = Vector3.yAxis:Cross(outward)
									Combat.Knockback(
										target.player,
										tangent * 0.6 + Vector3.new(0, 1.6, 0),
										PLAYER_FLING
									)
								end
							elseif suction then
								Combat.Knockback(target.player, -outward, SUCTION_STRENGTH)
							end
						end
					end

					if now - lastShake >= SHAKE_INTERVAL then
						lastShake = now
						PhysUtil.Shake(base, 70, 0.6, SHAKE_INTERVAL + 0.2)
					end
				end
			end
		end)

		return function()
			trove:Clean()
		end
	end,
}
