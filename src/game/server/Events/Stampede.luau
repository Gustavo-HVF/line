--!nonstrict
-- Evento físico "Debandada": ondas de rinocerontes e elefantes atravessam o ponto do evento em linha reta,
-- cada onda vinda de uma direção aleatória. Os animais são modelos de blocos ancorados, movidos por CFrame
-- a ~40 studs/s seguindo o chão; quebram o que é Destructible à frente, arremessam objetos soltos e
-- atropelam jogadores (dano + empurrão) e inimigos.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local Tags = require(ReplicatedStorage.Shared.Tags)

local PhysCreatures = require(script.Parent.Parent.EventHelpers.PhysCreatures)
local PhysUtil = require(script.Parent.Parent.EventHelpers.PhysUtil)

local SPEED = 40 -- studs/s
local WAVES = 4
local WAVE_GAP = 1.5 -- pausa entre o fim de uma onda e o começo da próxima
local HALF_PATH = 130 -- distância percorrida antes e depois do centro
local EDGE_MARGIN = 15 -- os animais não passam da borda da ilha
local MIN_ANIMALS, MAX_ANIMALS = 3, 5
local LANE_SPACING = 7.5
local MAX_STAGGER = 14 -- atraso máximo (em studs) entre animais da mesma onda
local SCAN_INTERVAL = 0.1
local MAX_FRACTURES_PER_SCAN = 4
local SMASH_IMPULSE = 95
local PROP_SPEED = 45
local HIT_DAMAGE = 30
local HIT_COOLDOWN = 1.2
local KNOCKBACK = 85
local STEP_UP = 3 -- degrau máximo que os animais sobem sem quebrar
local CLIMB_SPEED = 30
local FALL_SPEED = 35
local SHAKE_INTERVAL = 0.5
local SOURCE = "Debandada"

local DUST_COLOR = Color3.fromRGB(156, 128, 92)

local function addDust(creature)
	local attachment = Instance.new("Attachment")
	attachment.Name = "Poeira"
	attachment.Position = Vector3.new(0, -creature.footOffset + 0.6, creature.backReach * 0.4)
	attachment.Parent = creature.root
	PhysUtil.Emitter(attachment, {
		Texture = PhysUtil.Textures.Smoke,
		Color = DUST_COLOR,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 2),
			NumberSequenceKeypoint.new(1, 6),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(1, 1.6),
		Rate = 10,
		Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, 2, 0),
		RotSpeed = NumberRange.new(-40, 40),
		Rotation = NumberRange.new(0, 360),
		LightInfluence = 1,
	})
end

return {
	Id = "Stampede",
	DisplayName = "Debandada",
	Kind = "physical",
	Riddles = {
		"Uma nuvem de poeira anuncia a manada;\nnão há porta que resista à debandada.",
		"Ouça o chão tremer com patas de gigante;\nquem ficar no caminho não vê o próximo instante.",
		"Chifres e trombas em fúria vêm rolando;\nparedes e portas vão desmoronando.",
	},
	Weight = 0.8,
	MinSpace = 8,
	Duration = 45,
	Radius = 70,

	Start = function(ctx)
		local trove = PhysUtil.newTrove()
		local services = PhysUtil.Services(ctx)
		local Destruction = services.Destruction
		local Combat = services.Combat
		local rng = ctx.random
		local center = ctx.position
		local groundY = PhysUtil.EventGroundY(center)
		local canHit = PhysUtil.newCooldown(HIT_COOLDOWN)

		local function runWave(waveIndex: number)
			local angle = rng:NextNumber(0, math.pi * 2)
			local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local right = direction:Cross(Vector3.yAxis).Unit
			local flatCenter = Vector3.new(center.X, 0, center.Z)
			local back = math.max(
				math.min(HALF_PATH, PhysUtil.DistanceToIslandEdge(ctx.mapInfo, flatCenter, -direction) - EDGE_MARGIN),
				25
			)
			local front = math.max(
				math.min(HALF_PATH, PhysUtil.DistanceToIslandEdge(ctx.mapInfo, flatCenter, direction) - EDGE_MARGIN),
				25
			)
			local start = flatCenter - direction * back
			local pathLength = back + front

			local waveFolder = Instance.new("Folder")
			waveFolder.Name = "Onda" .. waveIndex
			waveFolder.Parent = ctx.folder
			trove:Add(waveFolder)

			-- Monta a manada em fileiras, com atrasos diferentes (ninguém chega junto).
			local animals = {}
			local count = rng:NextInteger(MIN_ANIMALS, MAX_ANIMALS)
			for index = 1, count do
				local isRhino = rng:NextNumber() < 0.55
				local lateral = (index - (count + 1) / 2) * LANE_SPACING + rng:NextNumber(-2, 2)
				local progress = -rng:NextNumber(0, MAX_STAGGER)
				local flat = start + direction * progress + right * lateral
				local footOffset = isRhino and 4.1 or 6.6
				local pose = CFrame.lookAt(
					Vector3.new(flat.X, groundY + footOffset, flat.Z),
					Vector3.new(flat.X, groundY + footOffset, flat.Z) + direction
				)
				local creature = if isRhino
					then PhysCreatures.Rhino(waveFolder, pose)
					else PhysCreatures.Elephant(waveFolder, pose)
				addDust(creature)
				table.insert(animals, {
					creature = creature,
					lateral = lateral,
					progress = progress,
					y = groundY + creature.footOffset,
					targetY = groundY + creature.footOffset,
					phase = rng:NextNumber(0, math.pi),
					gait = isRhino and 13 or 9,
					bob = isRhino and 0.45 or 0.6,
					done = false,
				})
			end
			SoundUtil.Play("Stampede", {
				Parent = animals[1].creature.root,
				Looped = true,
				Volume = 0.9,
				RollOffMaxDistance = 320,
			})

			-- Movimento (todo frame): só a raiz de cada animal muda de CFrame.
			local movement = trove:Connect(RunService.Heartbeat, function(dt)
				local step = math.min(dt, 0.1)
				local now = os.clock()
				for _, animal in animals do
					if not animal.done then
						animal.progress += SPEED * step
						if animal.progress > pathLength + MAX_STAGGER then
							animal.done = true
						end
						if animal.targetY > animal.y then
							animal.y = math.min(animal.targetY, animal.y + CLIMB_SPEED * step)
						else
							animal.y = math.max(animal.targetY, animal.y - FALL_SPEED * step)
						end
						local flat = start + direction * animal.progress + right * animal.lateral
						local bob = math.abs(math.sin(animal.phase + now * animal.gait)) * animal.bob
						local position = Vector3.new(flat.X, animal.y + bob, flat.Z)
						local root = animal.creature.root
						if root.Parent then
							root.CFrame = CFrame.lookAt(position, position + direction)
						end
					end
				end
			end)

			-- Varredura (10x por segundo): chão, destruição, objetos soltos e atropelamentos.
			local rayParams = PhysUtil.RaycastParams()
			local lastShake = 0
			while ctx.isActive() do
				task.wait(SCAN_INTERVAL)
				local overlap = PhysUtil.OverlapParams(true, 60)
				local fractures = 0
				local alive = 0
				local players = PhysUtil.PlayersInRadius(center, HALF_PATH * 2 + 20, true)
				local enemies = CollectionService:GetTagged(Tags.Enemy)
				local lead: Vector3? = nil
				for _, animal in animals do
					local creature = animal.creature
					local root = creature.root
					if not animal.done and root.Parent and animal.progress > -2 then
						alive += 1
						local rootCFrame = root.CFrame
						lead = lead or rootCFrame.Position

						-- Chão: sobe degraus baixos, desce (cai) quando o chão some.
						local feetY = animal.y - creature.footOffset
						local probe = Vector3.new(rootCFrame.X, feetY + STEP_UP + 1, rootCFrame.Z)
						local hit = workspace:Raycast(probe, Vector3.new(0, -40, 0), rayParams)
						if hit then
							animal.targetY = hit.Position.Y + creature.footOffset
						else
							animal.targetY = animal.y - 6
						end

						-- Caixa à frente do animal (do joelho até o topo, com folga para não pular paredes finas).
						local bottom = -creature.footOffset + 0.8
						local top = creature.topY
						local boxCFrame = rootCFrame * CFrame.new(0, (bottom + top) / 2, -creature.frontReach + 2)
						local boxSize = Vector3.new(creature.halfWidth * 2 + 1, top - bottom, 7)
						local touched = workspace:GetPartBoundsInBox(boxCFrame, boxSize, overlap)
						for _, part in touched do
							if Destruction and Destruction.IsDestructible(part) then
								if fractures < MAX_FRACTURES_PER_SCAN then
									fractures += 1
									Destruction.Fracture(
										part,
										PhysUtil.ClosestPointOnPart(part, rootCFrame.Position),
										SMASH_IMPULSE
									)
								end
							elseif Destruction then
								local fling = direction * PROP_SPEED
									+ right * rng:NextNumber(-12, 12)
									+ Vector3.new(0, rng:NextNumber(18, 30), 0)
								if not Destruction.ReleaseProp(part, fling) and not part.Anchored then
									if CollectionService:HasTag(part, Tags.Debris) then
										Destruction.Push(part, fling)
									end
								end
							end
						end

						-- Atropelamento de jogadores (caixa do corpo no espaço local do animal).
						for _, target in players do
							local localPoint = rootCFrame:PointToObjectSpace(target.root.Position)
							if
								math.abs(localPoint.X) <= creature.halfWidth + 1.5
								and localPoint.Z >= -creature.frontReach - 1.5
								and localPoint.Z <= creature.backReach + 1
								and localPoint.Y >= -creature.footOffset - 1
								and localPoint.Y <= creature.topY + 2
								and canHit(target.player)
							then
								Combat.DamagePlayer(target.player, HIT_DAMAGE, SOURCE)
								local side = localPoint.X >= 0 and 1 or -1
								Combat.Knockback(target.player, direction + right * side * 0.9, KNOCKBACK)
							end
						end

						-- Inimigos no caminho também são atropelados.
						for _, enemy in enemies do
							if enemy:IsA("Model") and enemy:IsDescendantOf(workspace) then
								local localPoint = rootCFrame:PointToObjectSpace(enemy:GetPivot().Position)
								if
									math.abs(localPoint.X) <= creature.halfWidth + 1.5
									and math.abs(localPoint.Z) <= creature.frontReach + 1
									and math.abs(localPoint.Y) <= creature.footOffset + 3
									and canHit(enemy)
								then
									Combat.DamageEnemy(enemy, HIT_DAMAGE, nil)
								end
							end
						end
					elseif not animal.done then
						alive += 1
					end
				end

				local now = os.clock()
				if lead and now - lastShake >= SHAKE_INTERVAL then
					lastShake = now
					PhysUtil.Shake(lead, 90, 0.9, 0.7)
				end
				if alive == 0 then
					break
				end
			end

			movement:Disconnect()
			if waveFolder.Parent then
				waveFolder:Destroy()
			end
		end

		trove:Spawn(function()
			for waveIndex = 1, WAVES do
				if not ctx.isActive() then
					return
				end
				if waveIndex > 1 then
					for _, target in PhysUtil.PlayersInRadius(center, ctx.radius * 3) do
						PhysUtil.Notify(target.player, "A manada está voltando! Saia do caminho!", "warning")
					end
				end
				local ok, err = pcall(runWave, waveIndex)
				if not ok then
					warn("[Stampede] Erro na onda " .. waveIndex .. ": " .. tostring(err))
				end
				task.wait(WAVE_GAP)
			end
			if ctx.isActive() then
				ctx.finish()
			end
		end)

		return function()
			trove:Clean()
		end
	end,
}
