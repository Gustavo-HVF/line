--!nonstrict
-- Evento físico "Terremoto": a câmera treme forte num raio grande, partes Destructible próximas racham e
-- quebram aos poucos, objetos soltos tombam, pedaços do teto e lustres despencam (machucam quem estiver
-- embaixo) e fendas brilhando como brasa se abrem no chão (empurram e queimam quem pisa nelas).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)

local PhysUtil = require(script.Parent.Parent.EventHelpers.PhysUtil)

local SHAKE_INTERVAL = 1
local SHAKE_INTENSITY = 1.5
local BREAK_INTERVAL = 0.6
local BREAK_IMPULSE = 35
local MAX_FRACTURES = 45
local REFRESH_INTERVAL = 6
local MAX_QUERY_PARTS = 500
local PROPS_PER_TICK = 2
local CEILING_INTERVAL = 1.3
local CEILING_MAX_HEIGHT = 40
local MAX_FALLING = 6
local FALLING_LIFETIME = 10
local FALL_DAMAGE = 15
local FISSURE_INTERVAL = 2.5
local MAX_FISSURES = 8
local MAX_FISSURE_LIGHTS = 4
local FISSURE_DAMAGE = 10
local FISSURE_PUSH = 50
local FISSURE_COOLDOWN = 1
local HAZARD_INTERVAL = 0.12
local STUMBLE_INTERVAL = 2.5
local STUMBLE_STRENGTH = 12
local SOURCE_CEILING = "Desabamento"
local SOURCE_FISSURE = "Fenda do terremoto"

local CRACK_COLOR = Color3.fromRGB(34, 24, 20)
local LAVA_COLOR = Color3.fromRGB(255, 96, 30)
local GOLD = Color3.fromRGB(196, 156, 64)
local WARM_LIGHT = Color3.fromRGB(255, 214, 150)
local PLASTER = Color3.fromRGB(214, 204, 186)
local DUST = Color3.fromRGB(196, 184, 164)

return {
	Id = "Earthquake",
	DisplayName = "Terremoto",
	Kind = "physical",
	Riddles = {
		"A terra ruge, racha e range sem parar;\nlustres despencam: não fique a admirar.",
		"Quando o chão dança sem ninguém tocar,\no teto despenca e o fogo vem te queimar.",
		"Brasas acordam nas rachaduras do chão;\nnem a mansão inteira escapa da agitação.",
	},
	Weight = 0.7,
	MinSpace = 14,
	Duration = 30,
	Radius = 80,
	Sites = 2, -- focos ao mesmo tempo, espalhados pelo mapa
	-- blocos em volta de cada foco viram pedra rachada (permanente; um bloco só muda uma vez)
	Skin = {
		Material = Enum.Material.Basalt,
		Colors = { Color3.fromRGB(72, 68, 66), Color3.fromRGB(60, 56, 54), Color3.fromRGB(86, 80, 76) },
	},

	Start = function(ctx)
		local trove = PhysUtil.newTrove()
		local services = PhysUtil.Services(ctx)
		local Destruction = services.Destruction
		local Combat = services.Combat
		local Ground = services.Ground
		local rng = ctx.random
		local center = ctx.position
		local radius = ctx.radius
		local groundY = PhysUtil.EventGroundY(center)

		-- Som contínuo no centro.
		local soundPart = PhysUtil.GhostPart({
			Name = "SomDoTerremoto",
			Size = Vector3.one,
			CFrame = CFrame.new(center.X, groundY + 4, center.Z),
			Transparency = 1,
			Parent = ctx.folder,
		})
		trove:Add(soundPart)
		SoundUtil.Play("Earthquake", { Parent = soundPart, Looped = true, Volume = 1, RollOffMaxDistance = radius * 4 })

		-- Candidatos (atualizados de tempos em tempos) -----------------------------------------
		local candidates: { BasePart } = {}
		local props: { BasePart } = {}
		local function refresh()
			table.clear(candidates)
			table.clear(props)
			if not Destruction then
				return
			end
			local seen = {}
			local found =
				workspace:GetPartBoundsInRadius(center, radius, PhysUtil.OverlapParams(false, MAX_QUERY_PARTS))
			for _, part in found do
				if Destruction.IsDestructible(part) then
					table.insert(candidates, part)
				else
					local root = Destruction.GetLooseRoot(part)
					if root and root.Anchored and not seen[root] then
						seen[root] = true
						table.insert(props, root)
					end
				end
			end
		end

		local function takeRandom(list: { BasePart }): BasePart?
			while #list > 0 do
				local index = rng:NextInteger(1, #list)
				local part = list[index]
				list[index] = list[#list]
				list[#list] = nil
				if part.Parent then
					return part
				end
			end
			return nil
		end

		-- Fendas -------------------------------------------------------------------------------
		local fissures = {}
		local function spawnFissure()
			local point = Ground.RandomPointNear(center, 6, radius * 0.85, rng, 6)
			if math.abs(point.Y - groundY) > 12 then
				return
			end
			local width = rng:NextNumber(1.4, 2.2)
			local length = rng:NextNumber(10, 18)
			local cframe = CFrame.new(point + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
			local crack = PhysUtil.GhostPart({
				Name = "Fenda",
				Size = Vector3.new(width, 0.24, 0.5),
				CFrame = cframe,
				Color = CRACK_COLOR,
				Material = Enum.Material.Slate,
				Parent = ctx.folder,
			})
			local glow = PhysUtil.GhostPart({
				Name = "Brasa",
				Size = Vector3.new(width * 0.45, 0.26, 0.4),
				CFrame = cframe,
				Color = LAVA_COLOR,
				Material = Enum.Material.Neon,
				Parent = ctx.folder,
			})
			trove:Add(crack)
			trove:Add(glow)
			if #fissures < MAX_FISSURE_LIGHTS then
				local light = Instance.new("PointLight")
				light.Color = LAVA_COLOR
				light.Range = 10
				light.Brightness = 2
				light.Shadows = false
				light.Parent = glow
			end
			PhysUtil.Emitter(glow, {
				Texture = PhysUtil.Textures.Sparkle,
				Color = LAVA_COLOR,
				Size = 0.35,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.1),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Lifetime = NumberRange.new(0.8, 1.4),
				Rate = 5,
				Speed = NumberRange.new(3, 7),
				EmissionDirection = Enum.NormalId.Top,
				SpreadAngle = Vector2.new(20, 20),
				LightEmission = 1,
			})
			local info = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(crack, info, { Size = Vector3.new(width, 0.24, length) }):Play()
			TweenService:Create(glow, info, { Size = Vector3.new(width * 0.45, 0.26, length - 0.8) }):Play()
			SoundUtil.Play("Crumble", { Position = point, RollOffMaxDistance = 150, Volume = 0.7 })
			table.insert(fissures, { cframe = cframe, halfWidth = width / 2, halfLength = length / 2 })
		end

		-- Pedaços do teto e lustres ---------------------------------------------------------------
		local falling = {}
		local function puff(position: Vector3)
			local holder = PhysUtil.GhostPart({
				Name = "Poeira",
				Size = Vector3.one,
				CFrame = CFrame.new(position),
				Transparency = 1,
				Parent = ctx.folder,
			})
			local emitter = PhysUtil.Emitter(holder, {
				Texture = PhysUtil.Textures.Smoke,
				Color = DUST,
				Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1.5),
					NumberSequenceKeypoint.new(1, 4),
				}),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.4),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Lifetime = NumberRange.new(0.8, 1.3),
				Rate = 0,
				Speed = NumberRange.new(2, 5),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, -4, 0),
			})
			emitter:Emit(10)
			task.delay(2, function()
				if holder.Parent then
					holder:Destroy()
				end
			end)
		end

		local function spawnFalling(ceiling: Vector3, ceilingPart: BasePart?)
			if #falling >= MAX_FALLING then
				return
			end
			local parts: { BasePart } = {}
			local root: BasePart
			if rng:NextNumber() < 0.25 then
				-- Lustre: aro dourado com o globo de luz soldado.
				root = PhysUtil.GhostPart({
					Name = "LustreCaindo",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.5, 3.4, 3.4),
					CFrame = CFrame.new(ceiling - Vector3.new(0, 1.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
					Color = GOLD,
					Material = Enum.Material.Metal,
				})
				local globe = PhysUtil.GhostPart({
					Name = "Globo",
					Shape = Enum.PartType.Ball,
					Size = Vector3.new(1.2, 1.2, 1.2),
					CFrame = CFrame.new(ceiling - Vector3.new(0, 2.2, 0)),
					Color = WARM_LIGHT,
					Material = Enum.Material.Neon,
				})
				table.insert(parts, globe)
			else
				local size = Vector3.new(rng:NextNumber(1.6, 3.2), rng:NextNumber(0.8, 1.4), rng:NextNumber(1.6, 3.2))
				local color, material = PLASTER, Enum.Material.Plaster
				if ceilingPart and ceilingPart:IsA("BasePart") then
					color, material = ceilingPart.Color, ceilingPart.Material
				end
				root = PhysUtil.GhostPart({
					Name = "PedacoDoTeto",
					Size = size,
					CFrame = CFrame.new(ceiling - Vector3.new(0, size.Y / 2 + 0.15, 0))
						* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
					Color = color,
					Material = material,
				})
			end
			table.insert(parts, 1, root)
			PhysUtil.WeldAll(root, parts)
			for _, part in parts do
				part.CanCollide = true
				part.CanQuery = true
				part.CanTouch = true
				part.Parent = ctx.folder
			end
			root.Anchored = false
			if Destruction then
				Destruction.Push(
					root,
					Vector3.new(0, -8, 0),
					Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
				)
				Destruction.RegisterDebris(root, FALLING_LIFETIME)
			end
			table.insert(falling, { part = root, spawned = os.clock(), hit = {} })
			puff(ceiling - Vector3.new(0, 0.5, 0))
			SoundUtil.Play("Crumble", { Position = ceiling, RollOffMaxDistance = 120, Volume = 0.6 })
		end

		-- Laços ------------------------------------------------------------------------------------

		-- Tremor, quebra de partes e objetos tombando.
		trove:Spawn(function()
			refresh()
			local fractures = 0
			local lastRefresh = os.clock()
			local lastShake = 0
			local lastStumble = os.clock()
			local started = os.clock()
			while ctx.isActive() do
				local now = os.clock()
				if now - lastShake >= SHAKE_INTERVAL then
					lastShake = now
					PhysUtil.Shake(center, radius * 2.5, SHAKE_INTENSITY, SHAKE_INTERVAL + 0.3)
				end
				if now - lastRefresh >= REFRESH_INTERVAL then
					lastRefresh = now
					refresh()
				end
				if Destruction then
					-- No meio do terremoto (o pico) quebram duas partes por vez.
					local elapsed = now - started
					local perTick = (elapsed > ctx.duration * 0.3 and elapsed < ctx.duration * 0.75) and 2 or 1
					for _ = 1, perTick do
						if fractures < MAX_FRACTURES then
							local part = takeRandom(candidates)
							if part and Destruction.IsDestructible(part) then
								fractures += 1
								Destruction.Fracture(part, PhysUtil.RandomPointInPart(part, rng), BREAK_IMPULSE)
							end
						end
					end
					for _ = 1, PROPS_PER_TICK do
						local prop = takeRandom(props)
						if prop then
							Destruction.ReleaseProp(
								prop,
								Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(4, 9), rng:NextNumber(-6, 6))
							)
						end
					end
				end
				if now - lastStumble >= STUMBLE_INTERVAL then
					lastStumble = now
					for _, target in PhysUtil.PlayersInRadius(center, radius, true) do
						Combat.Knockback(target.player, PhysUtil.RandomFlatUnit(rng), STUMBLE_STRENGTH)
					end
				end
				task.wait(BREAK_INTERVAL)
			end
		end)

		-- Teto caindo (perto de jogadores ou em pontos aleatórios da área).
		trove:Spawn(function()
			while ctx.isActive() do
				task.wait(CEILING_INTERVAL)
				local players = PhysUtil.PlayersInRadius(center, radius, true)
				local target: Vector3
				if #players > 0 and rng:NextNumber() < 0.65 then
					local chosen = players[rng:NextInteger(1, #players)]
					target = chosen.root.Position + Vector3.new(rng:NextNumber(-3, 3), 1.5, rng:NextNumber(-3, 3))
				else
					target = Ground.RandomPointNear(center, 0, radius * 0.7, rng, 4) + Vector3.new(0, 3, 0)
				end
				local ceiling, ceilingPart = PhysUtil.CeilingAbove(target, CEILING_MAX_HEIGHT)
				if ceiling and ceiling.Y - target.Y > 3 then
					spawnFalling(ceiling, ceilingPart)
				end
			end
		end)

		-- Fendas novas de tempos em tempos.
		trove:Spawn(function()
			while ctx.isActive() and #fissures < MAX_FISSURES do
				task.wait(FISSURE_INTERVAL)
				if ctx.isActive() then
					spawnFissure()
				end
			end
		end)

		-- Perigos: pedaços caindo em cima de alguém e jogadores pisando nas fendas.
		local canBurn = PhysUtil.newCooldown(FISSURE_COOLDOWN)
		trove:Spawn(function()
			while ctx.isActive() do
				task.wait(HAZARD_INTERVAL)
				local players = PhysUtil.PlayersInRadius(center, radius + 30, true)
				local now = os.clock()
				for index = #falling, 1, -1 do
					local item = falling[index]
					local part = item.part
					if not part.Parent or now - item.spawned > 2.5 then
						table.remove(falling, index)
					elseif part.AssemblyLinearVelocity.Y < -4 then
						local reach = math.max(part.Size.X, part.Size.Z) / 2 + 2
						for _, target in players do
							local offset = part.Position - target.root.Position
							if
								not item.hit[target.player]
								and Vector3.new(offset.X, 0, offset.Z).Magnitude <= reach
								and offset.Y > -1
								and offset.Y < 4.5
							then
								item.hit[target.player] = true
								Combat.DamagePlayer(target.player, FALL_DAMAGE, SOURCE_CEILING)
							end
						end
					end
				end
				for _, fissure in fissures do
					for _, target in players do
						local localPoint = fissure.cframe:PointToObjectSpace(target.root.Position)
						if
							math.abs(localPoint.X) <= fissure.halfWidth + 0.8
							and math.abs(localPoint.Z) <= fissure.halfLength + 0.3
							and localPoint.Y > -1
							and localPoint.Y < 4.5
							and canBurn(target.player)
						then
							Combat.DamagePlayer(target.player, FISSURE_DAMAGE, SOURCE_FISSURE)
							local side = localPoint.X >= 0 and 1 or -1
							Combat.Knockback(target.player, fissure.cframe.RightVector * side, FISSURE_PUSH)
						end
					end
				end
			end
		end)

		return function()
			trove:Clean()
			table.clear(fissures)
			table.clear(falling)
		end
	end,
}
