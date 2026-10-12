--!nonstrict
-- Evento físico "Areia Movediça": manchas de areia (discos finos de Sand, sem colisão, um pouco acima do
-- chão) aparecem na área. Dentro delas o jogador fica lento, quase não pula e vai afundando (HipHeight
-- diminui aos poucos em personagens R15); depois de 5 s dentro, perde vida a cada segundo. Tudo volta
-- ao normal ao sair (ou no fim do evento). Objetos que caem numa mancha afundam e somem.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local Tags = require(ReplicatedStorage.Shared.Tags)

local PhysUtil = require(script.Parent.Parent.EventHelpers.PhysUtil)

local PATCH_MIN, PATCH_MAX = 4, 7
local DIAMETER_MIN, DIAMETER_MAX = 10, 18
local PATCH_THICKNESS = 0.3
local PATCH_LIFT = 0.18 -- altura do disco acima do chão
local CHECK_INTERVAL = 0.2
local SINK_RATE = 0.3 -- studs de HipHeight por segundo
local MAX_SINK = 2.2
local SLOW_SPEED = 5
local JUMP_MULTIPLIER = 0.3
local DAMAGE_DELAY = 5
local DAMAGE_PER_SECOND = 8
local NOTIFY_COOLDOWN = 10
local PROP_SCAN_INTERVAL = 0.5
local MAX_SINKING = 10
local PROP_SINK_TIME = 2.5
local PROP_SINK_STEP = 0.1
local DRY_TIME = 2.5
local SOURCE = "Areia Movediça"

local SAND = Color3.fromRGB(184, 150, 98)
local WET_SAND = Color3.fromRGB(132, 102, 64)
local BUBBLE = Color3.fromRGB(120, 92, 58)

return {
	Id = "Quicksand",
	DisplayName = "Areia Movediça",
	Kind = "physical",
	Riddles = {
		"O chão parece firme, mas é só ilusão;\nquem pisa na areia afunda sem perdão.",
		"Debaixo dos pés, o chão vira mingau;\nficar parado ali termina muito mal.",
		"Grão por grão, o chão começa a sugar;\nquem fica parado não vai mais voltar.",
	},
	Weight = 1,
	MinSpace = 2,
	Duration = 60,
	Radius = 40,

	Start = function(ctx)
		local trove = PhysUtil.newTrove()
		local services = PhysUtil.Services(ctx)
		local Destruction = services.Destruction
		local Combat = services.Combat
		local Ground = services.Ground
		local rng = ctx.random
		local center = ctx.position
		local radius = ctx.radius
		local modifierKey = "Quicksand:" .. ctx.instanceId
		local cleaned = false

		-- Manchas -------------------------------------------------------------------------------
		local patches = {} -- { position: Vector3 (topo do chão), radius: number, parts: { BasePart } }

		local function overlapsExisting(point: Vector3, patchRadius: number): boolean
			for _, patch in patches do
				if PhysUtil.FlatDistance(point, patch.position) < (patch.radius + patchRadius) * 0.6 then
					return true
				end
			end
			return false
		end

		local function createPatch(point: Vector3, diameter: number)
			local upright = CFrame.new(point + Vector3.new(0, PATCH_LIFT, 0)) * CFrame.Angles(0, 0, math.rad(90))
			local outer = PhysUtil.GhostPart({
				Name = "AreiaMovedica",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(PATCH_THICKNESS, 1, 1),
				CFrame = upright,
				Color = SAND,
				Material = Enum.Material.Sand,
				Parent = ctx.folder,
			})
			local inner = PhysUtil.GhostPart({
				Name = "Redemoinho",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(PATCH_THICKNESS + 0.04, 0.6, 0.6),
				CFrame = upright,
				Color = WET_SAND,
				Material = Enum.Material.Mud,
				Parent = ctx.folder,
			})
			trove:Add(outer)
			trove:Add(inner)
			PhysUtil.Emitter(inner, {
				Texture = PhysUtil.Textures.Smoke,
				Color = BUBBLE,
				Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.3),
					NumberSequenceKeypoint.new(1, 0.9),
				}),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.3),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Lifetime = NumberRange.new(0.8, 1.4),
				Rate = 2,
				Speed = NumberRange.new(0.5, 1.5),
				EmissionDirection = Enum.NormalId.Right, -- o eixo X do cilindro aponta para cima
				SpreadAngle = Vector2.new(10, 10),
			})
			-- A mancha "abre" em 1,5 s.
			local info = TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(outer, info, { Size = Vector3.new(PATCH_THICKNESS, diameter, diameter) }):Play()
			TweenService
				:Create(inner, info, { Size = Vector3.new(PATCH_THICKNESS + 0.04, diameter * 0.55, diameter * 0.55) })
				:Play()
			table.insert(patches, { position = point, radius = diameter / 2, parts = { outer, inner } })
			SoundUtil.Play("Crumble", { Position = point, RollOffMaxDistance = 100, Volume = 0.5 })
		end

		do
			local count = rng:NextInteger(PATCH_MIN, PATCH_MAX)
			local groundY = PhysUtil.EventGroundY(center)
			-- A primeira mancha fica bem perto do tabuleiro; as outras se espalham pela área.
			local first = Ground.RandomPointNear(center, 4, 8, rng, 6)
			if math.abs(first.Y - groundY) > 4 then
				first = Vector3.new(center.X, groundY, center.Z)
			end
			createPatch(first, rng:NextNumber(DIAMETER_MIN, DIAMETER_MAX))
			for _ = 2, count do
				local diameter = rng:NextNumber(DIAMETER_MIN, DIAMETER_MAX)
				for _ = 1, 6 do
					local point = Ground.RandomPointNear(center, 8, radius * 0.85, rng, 6)
					if not overlapsExisting(point, diameter / 2) and math.abs(point.Y - groundY) < 12 then
						createPatch(point, diameter)
						break
					end
				end
			end
		end

		local function patchAt(position: Vector3, verticalBand: number): any
			for _, patch in patches do
				local height = position.Y - patch.position.Y
				if
					height > -1
					and height <= verticalBand
					and PhysUtil.FlatDistance(position, patch.position) <= patch.radius - 0.3
				then
					return patch
				end
			end
			return nil
		end

		-- Jogadores ------------------------------------------------------------------------------------
		local inside: { [Player]: any } = {}
		local canWarn = PhysUtil.newCooldown(NOTIFY_COOLDOWN)

		local function release(player: Player)
			local state = inside[player]
			if state then
				inside[player] = nil
				PhysUtil.ClearModifier(state.humanoid, modifierKey)
			end
		end

		trove:Spawn(function()
			while ctx.isActive() do
				task.wait(CHECK_INTERVAL)
				local seen = {}
				for _, target in PhysUtil.PlayersInRadius(center, radius + 25, true) do
					local player = target.player
					if patchAt(target.root.Position, 6) then
						seen[player] = true
						local state = inside[player]
						if state and state.humanoid ~= target.humanoid then
							release(player)
							state = nil
						end
						if not state then
							state = { humanoid = target.humanoid, time = 0, sink = 0, nextDamage = DAMAGE_DELAY }
							inside[player] = state
							if canWarn(player) then
								PhysUtil.Notify(player, "Areia movediça! Saia antes de afundar.", "warning")
							end
						end
						state.time += CHECK_INTERVAL
						state.sink = math.min(state.sink + SINK_RATE * CHECK_INTERVAL, MAX_SINK)
						PhysUtil.SetModifier(target.humanoid, modifierKey, {
							walkSpeed = SLOW_SPEED,
							jumpMultiplier = JUMP_MULTIPLIER,
							hipHeightOffset = state.sink,
						})
						if state.time >= state.nextDamage then
							state.nextDamage += 1
							Combat.DamagePlayer(player, DAMAGE_PER_SECOND, SOURCE)
						end
					end
				end
				-- Quem saiu da areia (ou morreu, ou saiu do jogo) volta ao normal.
				for player in table.clone(inside) do
					if not seen[player] then
						release(player)
					end
				end
			end
		end)

		-- Objetos que caem nas manchas afundam e somem ----------------------------------------------
		local sinking: { [BasePart]: { BasePart } } = {} -- raiz -> partes que afundam juntas
		local sinkingCount = 0

		local function sinkProp(root: BasePart)
			local members: { BasePart } = { root }
			sinking[root] = members
			sinkingCount += 1
			if not root.Anchored then
				local ok, connected = pcall(root.GetConnectedParts, root, true)
				if ok then
					for _, other in connected do
						if other ~= root and #members < 16 then
							table.insert(members, other)
						end
					end
				end
			end
			root.Anchored = true -- o conjunto soldado desce junto com a raiz
			for _, member in members do
				member.CanCollide = false
				member.CanQuery = false
			end
			local depth = math.max(root.Size.Y, 1) + 3
			local steps = math.max(math.floor(PROP_SINK_TIME / PROP_SINK_STEP), 1)
			local tilt =
				CFrame.Angles(rng:NextNumber(-0.04, 0.04), rng:NextNumber(-0.08, 0.08), rng:NextNumber(-0.04, 0.04))
			trove:Spawn(function()
				for _ = 1, steps do
					task.wait(PROP_SINK_STEP)
					if not root.Parent then
						break
					end
					root.CFrame = (root.CFrame - Vector3.new(0, depth / steps, 0)) * tilt
				end
				for _, member in members do
					if member.Parent then
						member:Destroy()
					end
				end
				sinking[root] = nil
				sinkingCount -= 1
			end)
		end

		trove:Spawn(function()
			while ctx.isActive() do
				task.wait(PROP_SCAN_INTERVAL)
				if Destruction and sinkingCount < MAX_SINKING then
					local params = PhysUtil.OverlapParams(true, 40)
					for _, patch in patches do
						local diameter = patch.radius * 2
						local found = workspace:GetPartBoundsInBox(
							CFrame.new(patch.position + Vector3.new(0, 3, 0)),
							Vector3.new(diameter, 6, diameter),
							params
						)
						for _, part in found do
							if sinkingCount >= MAX_SINKING then
								break
							end
							local root = Destruction.GetLooseRoot(part)
							if not root and not part.Anchored and CollectionService:HasTag(part, Tags.Debris) then
								root = part.AssemblyRootPart or part
							end
							if
								root
								and not sinking[root]
								and root.Parent
								and not Destruction.IsProtected(root)
								and patchAt(root.Position, 6)
							then
								sinkProp(root)
							end
						end
					end
				end
			end
		end)

		-- No finzinho, a areia seca e some.
		trove:Add(task.delay(math.max(ctx.duration - DRY_TIME - 0.2, 1), function()
			if not ctx.isActive() then
				return
			end
			local info = TweenInfo.new(DRY_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			for _, patch in patches do
				for _, part in patch.parts do
					if part.Parent then
						TweenService:Create(part, info, { Transparency = 1, Color = SAND }):Play()
					end
				end
			end
		end))

		return function()
			if cleaned then
				return
			end
			cleaned = true
			trove:Clean()
			for player in table.clone(inside) do
				release(player)
			end
			PhysUtil.ClearModifiersWithKey(modifierKey)
			-- Objetos que estavam afundando foram "engolidos".
			for _, members in sinking do
				for _, member in members do
					if member.Parent then
						member:Destroy()
					end
				end
			end
			table.clear(sinking)
		end
	end,
}
