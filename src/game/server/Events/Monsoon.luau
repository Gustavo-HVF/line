--!nonstrict
-- Evento físico "Monção": chuva forte (ParticleEmitter numa part invisível no alto), céu escurecido e água
-- de Terrain subindo em camadas numa caixa centrada no evento (até ~8 studs em ~30 s), parando um pouco e
-- depois baixando. Quem fica com a cabeça embaixo d'água por mais de 4 s se afoga aos poucos.
-- Objetos soltos (LooseProp) são desancorados quando a água chega neles e boiam sozinhos.
-- O mapa não usa Terrain: a limpeza apaga (Air) somente a caixa que este evento encheu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)

local PhysUtil = require(script.Parent.Parent.EventHelpers.PhysUtil)

local Terrain = workspace.Terrain

local MAX_DEPTH = 8
local UPSTAIRS_EXTRA = 2.5 -- evento no 2º andar: a água sobe até um pouco acima desse piso
local MAX_UPSTAIRS_DEPTH = 20
local RISE_TIME = 30
local HOLD_TIME = 16
local DRAIN_TIME = 18
local WATER_STEP = 1 -- segundos entre as camadas
local VOXEL = 4
local CHECK_INTERVAL = 0.5
local DROWN_GRACE = 4
local DROWN_DPS = 10
local RAIN_HEIGHT = 70
local MAX_PROPS = 60
local THUNDER_MIN, THUNDER_MAX = 9, 16
local SOURCE = "Afogamento"

local RAIN_COLOR = Color3.fromRGB(200, 214, 230)
local THUNDER_COLOR = Color3.fromRGB(235, 240, 255)

-- Aparência da água do Terrain (global): guardada pelo primeiro evento e restaurada pelo último.
local waterStyleUsers = 0
local savedWaterStyle = nil

local function pushWaterStyle()
	if waterStyleUsers == 0 then
		savedWaterStyle = {
			WaterColor = Terrain.WaterColor,
			WaterTransparency = Terrain.WaterTransparency,
			WaterWaveSize = Terrain.WaterWaveSize,
			WaterWaveSpeed = Terrain.WaterWaveSpeed,
			WaterReflectance = Terrain.WaterReflectance,
		}
		Terrain.WaterColor = Color3.fromRGB(78, 96, 72) -- enchente barrenta
		Terrain.WaterTransparency = 0.55
		Terrain.WaterWaveSize = 0.12
		Terrain.WaterWaveSpeed = 14
		Terrain.WaterReflectance = 0.4
	end
	waterStyleUsers += 1
end

local function popWaterStyle()
	waterStyleUsers = math.max(waterStyleUsers - 1, 0)
	if waterStyleUsers == 0 and savedWaterStyle then
		for name, value in savedWaterStyle do
			Terrain[name] = value
		end
		savedWaterStyle = nil
	end
end

return {
	Id = "Monsoon",
	DisplayName = "Monção",
	Kind = "physical",
	Riddles = {
		"Nuvens pesadas cobrem a sua cabeça;\nsuba bem alto antes que a água cresça.",
		"Gota após gota, o chão vira lagoa;\nquem não sabe nadar, a correnteza não perdoa.",
		"O céu vai chorar sem parar um segundo;\na água vai subir e engolir o seu mundo.",
	},
	Weight = 0.9,
	MinSpace = 6,
	Duration = 75,
	Radius = 55,
	Sites = 2, -- focos ao mesmo tempo, espalhados pelo mapa
	-- blocos em volta de cada foco viram lama (permanente; um bloco só muda uma vez)
	Skin = {
		Material = Enum.Material.Mud,
		Colors = { Color3.fromRGB(94, 74, 52), Color3.fromRGB(80, 63, 45), Color3.fromRGB(106, 84, 60) },
	},

	Start = function(ctx)
		local trove = PhysUtil.newTrove()
		local services = PhysUtil.Services(ctx)
		local Destruction = services.Destruction
		local Combat = services.Combat
		local rng = ctx.random
		local lightingKey = "Monsoon:" .. ctx.instanceId
		local cleaned = false

		local center = ctx.position
		local cx, cz = center.X, center.Z
		local half = ctx.radius
		local size = half * 2
		local islandGround = (ctx.mapInfo and ctx.mapInfo.groundY) or PhysUtil.EventGroundY(center)
		local localGround = PhysUtil.EventGroundY(center)
		local bottom, depth
		if localGround > islandGround + 6 then
			-- Evento no andar de cima: a enchente começa no térreo e sobe até esse andar.
			bottom = islandGround
			depth = math.clamp(localGround + UPSTAIRS_EXTRA - islandGround, MAX_DEPTH, MAX_UPSTAIRS_DEPTH)
		else
			bottom = localGround
			depth = MAX_DEPTH
		end
		local level = bottom -- nível atual da água
		local filledTop = bottom -- ponto mais alto já preenchido (para a limpeza)

		-- Água ---------------------------------------------------------------------------------
		local function fillTo(target: number)
			if target - bottom < 0.1 then
				return
			end
			Terrain:FillBlock(
				CFrame.new(cx, (bottom + target) / 2, cz),
				Vector3.new(size, target - bottom, size),
				Enum.Material.Water
			)
			filledTop = math.max(filledTop, target)
		end

		local function lowerTo(target: number)
			local top = filledTop + VOXEL
			if top - target > 0.05 then
				Terrain:FillBlock(
					CFrame.new(cx, (target + top) / 2, cz),
					Vector3.new(size, top - target, size),
					Enum.Material.Air
				)
			end
			fillTo(target) -- refaz a camada parcial de cima
		end

		local function clearWater()
			if filledTop <= bottom then
				return
			end
			-- Uma célula de voxel de folga em volta: a borda da caixa preenche voxels parciais.
			local low = bottom - VOXEL
			local high = filledTop + VOXEL
			Terrain:FillBlock(
				CFrame.new(cx, (low + high) / 2, cz),
				Vector3.new(size + VOXEL * 2, high - low, size + VOXEL * 2),
				Enum.Material.Air
			)
			filledTop = bottom
		end

		-- Chuva, som e céu -------------------------------------------------------------------------
		local rainPart = PhysUtil.GhostPart({
			Name = "Chuva",
			Size = Vector3.new(size, 1, size),
			CFrame = CFrame.new(cx, math.max(bottom, localGround) + RAIN_HEIGHT, cz),
			Transparency = 1,
			Parent = ctx.folder,
		})
		trove:Add(rainPart)
		PhysUtil.Emitter(rainPart, {
			Texture = PhysUtil.Textures.Smoke,
			Color = RAIN_COLOR,
			Size = 0.22,
			Squash = 2.6, -- gotas compridas e finas
			Transparency = 0.35,
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			EmissionDirection = Enum.NormalId.Bottom,
			Speed = NumberRange.new(95, 110),
			Lifetime = NumberRange.new(0.72, 0.82),
			SpreadAngle = Vector2.new(3, 3),
			Rate = 320,
			LightEmission = 0.25,
			LightInfluence = 0.6,
		})

		local soundPart = PhysUtil.GhostPart({
			Name = "SomDaChuva",
			Size = Vector3.one,
			CFrame = CFrame.new(cx, localGround + 4, cz),
			Transparency = 1,
			Parent = ctx.folder,
		})
		trove:Add(soundPart)
		SoundUtil.Play("Rain", {
			Parent = soundPart,
			Looped = true,
			Group = "Ambience",
			Volume = 0.8,
			RollOffMaxDistance = half * 4,
		})

		PhysUtil.PushLighting(lightingKey, function(base)
			local target = {}
			target.Brightness = (base.Brightness or 2) * 0.45
			local clock = base.ClockTime
			if clock and clock > 6 and clock < 17.6 then
				target.ClockTime = clock + 0.6
			end
			if base.AtmosphereDensity then
				target.AtmosphereDensity = math.min(base.AtmosphereDensity + 0.18, 0.65)
			end
			return target
		end, 4)
		pushWaterStyle()

		-- Objetos soltos na área: desancorados quando a água chega na base deles.
		local props: { BasePart } = {}
		if Destruction then
			local seen = {}
			local found = workspace:GetPartBoundsInBox(
				CFrame.new(cx, bottom + depth / 2 + 1, cz),
				Vector3.new(size, depth + 2, size),
				PhysUtil.OverlapParams(false, 400)
			)
			for _, part in found do
				local root = Destruction.GetLooseRoot(part)
				if root and root.Anchored and not seen[root] and #props < MAX_PROPS then
					seen[root] = true
					table.insert(props, root)
				end
			end
			table.sort(props, function(a, b)
				return a.Position.Y < b.Position.Y
			end)
		end
		local nextProp = 1
		local function releaseSubmergedProps()
			while nextProp <= #props do
				local root = props[nextProp]
				if root.Parent and root.Position.Y - root.Size.Y / 2 > level - 0.3 then
					break
				end
				nextProp += 1
				if root.Parent and root.Anchored then
					Destruction.ReleaseProp(
						root,
						Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(1, 3), rng:NextNumber(-2, 2))
					)
				end
			end
		end

		-- Linha do tempo da água: sobe, para, desce e termina o evento.
		trove:Spawn(function()
			local riseSteps = math.max(math.floor(RISE_TIME / WATER_STEP), 1)
			for step = 1, riseSteps do
				task.wait(WATER_STEP)
				if not ctx.isActive() then
					return
				end
				level = bottom + depth * (step / riseSteps)
				fillTo(level)
				releaseSubmergedProps()
			end
			task.wait(HOLD_TIME)
			local drainSteps = math.max(math.floor(DRAIN_TIME / WATER_STEP), 1)
			for step = drainSteps - 1, 0, -1 do
				task.wait(WATER_STEP)
				if not ctx.isActive() then
					return
				end
				level = bottom + depth * (step / drainSteps)
				lowerTo(level)
			end
			clearWater()
			level = bottom
			if ctx.isActive() then
				ctx.finish()
			end
		end)

		-- Afogamento: cabeça abaixo do nível atual, dentro da caixa, por mais de DROWN_GRACE segundos.
		local submerged: { [Player]: number } = {}
		local warned: { [Player]: boolean } = {}
		trove:Spawn(function()
			while ctx.isActive() do
				task.wait(CHECK_INTERVAL)
				local current = {}
				for _, target in PhysUtil.PlayersInRadius(center, half * 1.5, true) do
					local head = target.player.Character and target.player.Character:FindFirstChild("Head")
					if head and head:IsA("BasePart") then
						local p = head.Position
						if math.abs(p.X - cx) <= half and math.abs(p.Z - cz) <= half and p.Y < level - 0.3 then
							local time = (submerged[target.player] or 0) + CHECK_INTERVAL
							current[target.player] = time
							if time > DROWN_GRACE then
								if not warned[target.player] then
									warned[target.player] = true
									PhysUtil.Notify(
										target.player,
										"Você está se afogando! Suba para respirar.",
										"danger"
									)
								end
								Combat.DamagePlayer(target.player, DROWN_DPS * CHECK_INTERVAL, SOURCE)
							end
						end
					end
				end
				submerged = current
			end
		end)

		-- Trovões: clarão e um tremor leve de vez em quando.
		trove:Spawn(function()
			while ctx.isActive() do
				task.wait(rng:NextNumber(THUNDER_MIN, THUNDER_MAX))
				if not ctx.isActive() then
					return
				end
				for _, target in PhysUtil.PlayersInRadius(center, half * 2.5) do
					PhysUtil.Flash(target.player, THUNDER_COLOR, 0.25)
				end
				PhysUtil.Shake(center, half * 2.5, 0.35, 0.6)
			end
		end)

		return function()
			if cleaned then
				return
			end
			cleaned = true
			trove:Clean()
			local ok, err = pcall(clearWater)
			if not ok then
				warn("[Monsoon] Erro ao remover a água: " .. tostring(err))
			end
			PhysUtil.PopLighting(lightingKey, 3)
			popWaterStyle()
		end
	end,
}
