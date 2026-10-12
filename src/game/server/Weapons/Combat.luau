--!nonstrict
-- Ações das armas no servidor. O WeaponService já validou o pedido (dono, arma na mão, jogador vivo,
-- argumentos e cadência); aqui ficam as regras de cada tipo:
--   * Fire: um raycast por projétil (com espalhamento), dano em inimigos, empurra objetos soltos, a
--     espingarda quebra parts Destructible de perto e todos veem o traço (Fx_Play "tracer");
--   * Melee: cone à frente do HumanoidRootPart, até maxTargets inimigos, com linha de visão;
--   * Throw: dinamite com física (trajetória balística até o alvo), pavio com faísca e explosão;
--   * StartReload: recarga com tempo (cancelada se a arma sair da mão; ver Inventory).
-- Sem fogo amigo: os tiros atravessam personagens e a explosão da dinamite não fere jogadores.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local Tags = require(ReplicatedStorage.Shared.Tags)

local CombatUtil = require(script.Parent.Parent.CombatUtil)
local Definitions = require(script.Parent.Definitions)

local Combat = {}

-- Ajustes --------------------------------------------------------------------------------------

local MAX_LIVE_DYNAMITE = 24 -- bananas acesas ao mesmo tempo (o resto do arremesso é recusado)
local DYNAMITE_NO_COLLIDE_TIME = 0.12 -- sem colisão logo após sair da mão (não bate no próprio corpo)
local DYNAMITE_COLOR = Color3.fromRGB(176, 38, 30)
local SPARK_COLOR = ColorSequence.new(Color3.fromRGB(255, 236, 140), Color3.fromRGB(255, 120, 40))
local FUSE_LIGHT = Color3.fromRGB(255, 170, 80)
local MELEE_PREFILTER = 14 -- folga sobre o alcance para o pivô de inimigos grandes (leão)

-- Estado ---------------------------------------------------------------------------------------

local random = Random.new()
local fxRemote: RemoteEvent? = nil
local Destruction = nil -- DestructionService (opcional: carregado com segurança pelo WeaponService)
local liveDynamite = 0

function Combat.Init(destructionService: any)
	Destruction = destructionService
	fxRemote = Net.event(Net.Names.Fx_Play)
end

-- Utilitários ----------------------------------------------------------------------------------

-- Posição da cabeça (ou um ponto acima do HumanoidRootPart, se não houver cabeça).
function Combat.GetHeadPosition(character: Model?): Vector3?
	if not character then
		return nil
	end
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position + Vector3.new(0, 1.5, 0)
	end
	return nil
end

local function bumpCounter(tool: Tool, attribute: string)
	tool:SetAttribute(attribute, (tonumber(tool:GetAttribute(attribute)) or 0) + 1)
end

-- Lista de exclusão dos tiros: personagens (sem fogo amigo), pedaços de destruição e o tabuleiro
-- (que pode estar nas costas de quem atira).
local function shotExcludeList(): { Instance }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	for _, name in { "Debris", "Board" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(list, folder)
		end
	end
	return list
end

local function newShotParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = shotExcludeList()
	params.IgnoreWater = true
	return params
end

-- Raiz do objeto solto (LooseProp) ao qual a part pertence, ou nil.
local function looseRootOf(part: BasePart): BasePart?
	if Destruction and type(Destruction.GetLooseRoot) == "function" then
		local ok, root = pcall(Destruction.GetLooseRoot, part)
		return ok and root or nil
	end
	if CollectionService:HasTag(part, Tags.LooseProp) then
		return part
	end
	return nil
end

-- O tiro atravessa parts invisíveis ou sem colisão (folhagem, água, volumes de evento),
-- mas nunca inimigos nem objetos soltos (que são alvos).
local function shouldPierce(part: BasePart): boolean
	if part:IsA("Terrain") then
		return false
	end
	if part.CanCollide and part.Transparency < 0.9 then
		return false
	end
	if CombatUtil.FindEnemyFromPart(part) then
		return false
	end
	return looseRootOf(part) == nil
end

-- Raycast que atravessa até MAX_RAY_PIERCE parts "vazadas". Retorna o resultado (ou nil) e o ponto final.
local function castRay(
	origin: Vector3,
	direction: Vector3,
	distance: number,
	params: RaycastParams
): (RaycastResult?, Vector3)
	local start = origin
	local remaining = distance
	for _ = 0, Definitions.MAX_RAY_PIERCE do
		local result = workspace:Raycast(start, direction * remaining, params)
		if not result then
			break
		end
		if not shouldPierce(result.Instance) then
			return result, result.Position
		end
		params:AddToFilter(result.Instance)
		remaining -= (result.Position - start).Magnitude
		start = result.Position
		if remaining <= 0.05 then
			return nil, start
		end
	end
	return nil, start + direction * remaining
end

-- Direção aleatória dentro de um cone (distribuição uniforme no disco).
local function spreadDirection(direction: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return direction
	end
	local up = if math.abs(direction.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	local right = direction:Cross(up).Unit
	local realUp = right:Cross(direction).Unit
	local angle = math.rad(degrees) * math.sqrt(random:NextNumber())
	local theta = random:NextNumber(0, math.pi * 2)
	local offset = (right * math.cos(theta) + realUp * math.sin(theta)) * math.tan(angle)
	return (direction + offset).Unit
end

-- Solta (desancora) e empurra um objeto solto. Cada objeto é empurrado uma vez por tiro.
local function pushProp(part: BasePart, velocity: Vector3, pushed: { [BasePart]: boolean }): boolean
	local root = looseRootOf(part)
	if not root or pushed[root] then
		return root ~= nil
	end
	pushed[root] = true
	if Destruction and type(Destruction.ReleaseProp) == "function" then
		local ok, err = pcall(Destruction.ReleaseProp, root, velocity)
		if not ok then
			warn("[Weapons] Erro ao soltar objeto: " .. tostring(err))
		end
	elseif root.Anchored or root.AssemblyRootPart == root then
		root.Anchored = false
		pcall(root.SetNetworkOwner, root, nil)
		root.AssemblyLinearVelocity = velocity
	end
	return true
end

local function fireTracer(from: Vector3, to: Vector3, def: Definitions.WeaponDef, shooter: Player)
	if not fxRemote then
		return
	end
	fxRemote:FireAllClients("tracer", {
		from = from,
		to = to,
		color = def.tracerColor,
		width = def.tracerWidth,
		shooterUserId = shooter.UserId,
	})
end

-- Recarga ----------------------------------------------------------------------------------------

function Combat.StartReload(player: Player, tool: Tool, state: any, def: Definitions.WeaponDef): boolean
	if def.category ~= "gun" or state.reloading or not tool.Parent then
		return false
	end
	local ammo = tonumber(tool:GetAttribute("Ammo")) or 0
	local maxAmmo = def.maxAmmo or 0
	if ammo >= maxAmmo then
		return false
	end
	state.reloading = true
	state.reloadToken += 1
	local token = state.reloadToken
	tool:SetAttribute("Reloading", true)
	task.delay(def.reloadTime or 1.5, function()
		if state.reloadToken ~= token or not state.reloading then
			return -- cancelada (arma guardada) ou substituída por uma coleta
		end
		state.reloading = false
		if not tool.Parent then
			return
		end
		tool:SetAttribute("Reloading", false)
		if tool.Parent == player.Character and CombatUtil.IsPlayerAlive(player) then
			tool:SetAttribute("Ammo", maxAmmo)
		end
	end)
	return true
end

-- Tiro -------------------------------------------------------------------------------------------

-- `origin` e `direction` já validados (origem perto da cabeça, direção unitária).
function Combat.Fire(
	player: Player,
	tool: Tool,
	state: any,
	def: Definitions.WeaponDef,
	origin: Vector3,
	direction: Vector3
): boolean
	local ammo = tonumber(tool:GetAttribute("Ammo")) or 0
	if ammo <= 0 or state.reloading then
		return false
	end
	state.lastUse = os.clock()
	ammo -= 1
	tool:SetAttribute("Ammo", ammo)
	bumpCounter(tool, "FireSeq")

	local params = newShotParams()

	-- Cano atravessando uma parede (jogador encostado nela): o tiro sai da cabeça e para na parede.
	local start = origin
	local head = Combat.GetHeadPosition(player.Character)
	if head then
		local toOrigin = origin - head
		local length = toOrigin.Magnitude
		if length > 0.05 then
			local blocked = castRay(head, toOrigin / length, length, params)
			if blocked then
				start = head
			end
		end
	end

	local pellets = math.max(math.floor(def.pellets or 1), 1)
	local damage = def.damage or 0
	local damageByEnemy: { [Model]: number } = {}
	local enemyOrder: { Model } = {}
	local pushed: { [BasePart]: boolean } = {}
	local fractureHits: { [BasePart]: { count: number, sum: Vector3 } } = {}

	for _ = 1, pellets do
		local pelletDirection = spreadDirection(direction, def.spread or 0)
		local result, endPoint = castRay(start, pelletDirection, def.range, params)
		if result then
			local part = result.Instance
			local enemy = CombatUtil.FindEnemyFromPart(part)
			if enemy then
				if not damageByEnemy[enemy] then
					table.insert(enemyOrder, enemy)
				end
				damageByEnemy[enemy] = (damageByEnemy[enemy] or 0) + damage
			elseif not pushProp(part, pelletDirection * (def.propPush or 0), pushed) then
				local canBreak = def.fractureRange ~= nil
					and Destruction ~= nil
					and (result.Position - start).Magnitude <= def.fractureRange
					and Destruction.IsDestructible(part)
				if canBreak then
					local entry = fractureHits[part]
					if not entry then
						entry = { count = 0, sum = Vector3.zero }
						fractureHits[part] = entry
					end
					entry.count += 1
					entry.sum += result.Position
				end
			end
		end
		fireTracer(start, endPoint, def, player)
	end

	-- Dano somado por inimigo (um golpe só para vários projéteis no mesmo alvo).
	for _, enemy in enemyOrder do
		CombatUtil.DamageEnemy(enemy, damageByEnemy[enemy], player)
	end

	-- No máximo uma quebra por tiro: a part que recebeu mais projéteis (mínimo fractureMinPellets).
	local bestPart, bestEntry = nil, nil
	for part, entry in fractureHits do
		if entry.count >= (def.fractureMinPellets or 1) and (not bestEntry or entry.count > bestEntry.count) then
			bestPart, bestEntry = part, entry
		end
	end
	if bestPart and bestEntry and bestPart.Parent and Destruction then
		local ok, err = pcall(Destruction.Fracture, bestPart, bestEntry.sum / bestEntry.count, def.fractureImpulse)
		if not ok then
			warn("[Weapons] Erro ao quebrar com tiro: " .. tostring(err))
		end
	end

	-- Acabou a munição: recarrega sozinho depois da cadência (se continuar na mão).
	if ammo <= 0 then
		task.delay(def.cooldown, function()
			if tool.Parent and tool.Parent == player.Character and CombatUtil.IsPlayerAlive(player) then
				Combat.StartReload(player, tool, state, def)
			end
		end)
	end
	return true
end

-- Corpo a corpo -------------------------------------------------------------------------------------

local function closestPointOnBox(boxCFrame: CFrame, boxSize: Vector3, point: Vector3): Vector3
	local localPoint = boxCFrame:PointToObjectSpace(point)
	local half = boxSize / 2
	local clamped = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)
	return boxCFrame:PointToWorldSpace(clamped)
end

-- Linha de visão só contra o cenário sólido (ignora personagens, inimigos, pedaços e o tabuleiro).
local function newSightParams(): RaycastParams
	local list = shotExcludeList()
	local npcs = workspace:FindFirstChild("NPCs")
	if npcs then
		table.insert(list, npcs)
	end
	for _, enemy in CollectionService:GetTagged(Tags.Enemy) do
		table.insert(list, enemy)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = list
	params.RespectCanCollide = true
	params.IgnoreWater = true
	return params
end

local function hasLineOfSight(from: Vector3, to: Vector3, params: RaycastParams): boolean
	local delta = to - from
	local length = delta.Magnitude
	if length < 0.75 then
		return true
	end
	local result = workspace:Raycast(from, delta, params)
	return result == nil or (result.Position - from).Magnitude >= length - 1
end

-- Golpe do facão. Retorna quantos inimigos foram atingidos.
function Combat.Melee(player: Player, tool: Tool, state: any, def: Definitions.WeaponDef): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return 0
	end
	state.lastUse = os.clock()
	bumpCounter(tool, "SwingSeq")

	local rootCFrame = root.CFrame
	local origin = rootCFrame.Position
	local flatLook = Vector3.new(rootCFrame.LookVector.X, 0, rootCFrame.LookVector.Z)
	if flatLook.Magnitude < 1e-3 then
		return 0
	end
	flatLook = flatLook.Unit
	local minDot = math.cos(math.rad((def.coneAngle or 70) / 2))
	local range = def.range
	local maxHeight = def.maxHeightDifference or 7

	local candidates = {}
	local sightParams: RaycastParams? = nil
	for _, enemy in CollectionService:GetTagged(Tags.Enemy) do
		if enemy:IsA("Model") and enemy:IsDescendantOf(workspace) and CombatUtil.IsEnemyAlive(enemy) then
			local pivot = enemy:GetPivot().Position
			if (pivot - origin).Magnitude <= range + MELEE_PREFILTER then
				local boxCFrame, boxSize = enemy:GetBoundingBox()
				local closest = closestPointOnBox(boxCFrame, boxSize, origin)
				local offset = closest - origin
				local distance = offset.Magnitude
				if distance <= range and math.abs(offset.Y) <= maxHeight then
					local flatOffset = Vector3.new(offset.X, 0, offset.Z)
					local inCone = flatOffset.Magnitude <= Definitions.MELEE_POINT_BLANK
						or flatLook:Dot(flatOffset.Unit) >= minDot
					if inCone then
						sightParams = sightParams or newSightParams()
						-- Mira um pouco para dentro da caixa (o ponto mais próximo pode estar rente ao chão).
						local aimPoint = closest:Lerp(boxCFrame.Position, 0.3)
						if hasLineOfSight(origin, aimPoint, sightParams :: RaycastParams) then
							table.insert(candidates, { enemy = enemy, distance = distance, point = closest })
						end
					end
				end
			end
		end
	end

	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)
	local hits = math.min(#candidates, def.maxTargets or 1)
	for index = 1, hits do
		CombatUtil.DamageEnemy(candidates[index].enemy, def.damage or 0, player)
	end
	if hits > 0 and def.hitSound then
		SoundUtil.Play(def.hitSound, { Position = candidates[1].point, Volume = 0.7, RollOffMaxDistance = 120 })
	end
	return hits
end

-- Dinamite --------------------------------------------------------------------------------------------

local function projectileFolder(): Instance
	-- workspace.Debris: os raycasts de armas, NPCs e eventos já ignoram esta pasta.
	local folder = workspace:FindFirstChild("Debris")
	if folder then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "Debris"
	created.Parent = workspace
	return created
end

local function explode(position: Vector3, def: Definitions.WeaponDef, player: Player)
	local attacker = if player.Parent then player else nil
	if Destruction and type(Destruction.Explode) == "function" then
		local ok, err = pcall(Destruction.Explode, position, def.blastRadius or 14, def.blastForce or 80, {
			damageEnemies = def.damageEnemies,
			attacker = attacker,
			source = def.source,
		})
		if ok then
			return
		end
		warn("[Weapons] Erro na explosão da dinamite: " .. tostring(err))
	end
	-- Sem DestructionService: explosão só visual, com dano nos inimigos (nunca nos jogadores).
	local explosion = Instance.new("Explosion")
	explosion.BlastPressure = 0
	explosion.BlastRadius = def.blastRadius or 14
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Position = position
	explosion.Parent = workspace
	SoundUtil.Play("Explosion", { Position = position, RollOffMaxDistance = 350, Volume = 0.9 })
	CombatUtil.DamageEnemiesInRadius(position, def.blastRadius or 14, def.damageEnemies or 0, attacker)
end

local function spawnDynamite(player: Player, def: Definitions.WeaponDef, start: Vector3, target: Vector3)
	local stick = Instance.new("Part")
	stick.Name = "DinamiteAcesa"
	stick.Shape = Enum.PartType.Cylinder
	stick.Size = Vector3.new(1.15, 0.42, 0.42)
	stick.Color = DYNAMITE_COLOR
	stick.Material = Enum.Material.SmoothPlastic
	stick.TopSurface = Enum.SurfaceType.Smooth
	stick.BottomSurface = Enum.SurfaceType.Smooth
	stick.CanCollide = false
	stick.CanTouch = false
	stick.CastShadow = false
	stick.CustomPhysicalProperties = PhysicalProperties.new(0.9, 1, 0.15, 1, 1)
	stick.CFrame = CFrame.new(start) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), math.rad(80))

	-- Pavio aceso: faísca + luz fraca (criados no servidor, replicam sozinhos).
	local fuse = Instance.new("Attachment")
	fuse.Name = "Pavio"
	fuse.Position = Vector3.new(0.62, 0, 0)
	fuse.Parent = stick
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Faisca"
	sparks.Rate = 45
	sparks.Lifetime = NumberRange.new(0.15, 0.35)
	sparks.Speed = NumberRange.new(3, 7)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -14, 0)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0) })
	sparks.Color = SPARK_COLOR
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Parent = fuse
	local light = Instance.new("PointLight")
	light.Color = FUSE_LIGHT
	light.Brightness = 1.6
	light.Range = 8
	light.Shadows = false
	light.Parent = fuse

	stick.Parent = projectileFolder()
	pcall(stick.SetNetworkOwner, stick, nil)

	-- Trajetória balística: chega ao alvo em `flight` segundos (alvos longe sobem mais).
	local delta = target - start
	local flatDistance = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local flight = math.clamp(
		flatDistance / math.max(def.flightSpeed or 40, 1),
		Definitions.THROW_MIN_FLIGHT,
		Definitions.THROW_MAX_FLIGHT
	)
	local velocity = delta / flight + Vector3.new(0, 0.5 * workspace.Gravity * flight, 0)
	if velocity.Magnitude > Definitions.THROW_MAX_SPEED then
		velocity = velocity.Unit * Definitions.THROW_MAX_SPEED
	end
	stick.AssemblyLinearVelocity = velocity
	stick.AssemblyAngularVelocity =
		Vector3.new(random:NextNumber(-8, 8), random:NextNumber(-3, 3), random:NextNumber(-8, 8))

	liveDynamite += 1
	task.delay(DYNAMITE_NO_COLLIDE_TIME, function()
		if stick.Parent then
			stick.CanCollide = true
		end
	end)
	task.delay(def.fuseTime or 2.5, function()
		liveDynamite -= 1
		if not stick.Parent then
			return -- caiu para fora do mundo e foi destruída pelo motor
		end
		local position = stick.Position
		stick:Destroy()
		explode(position, def, player)
	end)
end

-- Arremesso validado (alvo dentro do alcance). Retorna true se a dinamite foi lançada.
function Combat.Throw(player: Player, tool: Tool, state: any, def: Definitions.WeaponDef, target: Vector3): boolean
	local character = player.Character
	local head = Combat.GetHeadPosition(character)
	local charges = tonumber(tool:GetAttribute("Charges")) or 0
	if not head or charges <= 0 or liveDynamite >= MAX_LIVE_DYNAMITE then
		return false
	end
	state.lastUse = os.clock()
	charges -= 1
	tool:SetAttribute("Charges", charges)
	bumpCounter(tool, "ThrowSeq")

	-- Sai da mão (Handle) se ela estiver perto da cabeça e sem parede no meio; senão, da cabeça.
	local start = head
	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		local delta = handle.Position - head
		local length = delta.Magnitude
		if length <= 5 and (length < 0.05 or castRay(head, delta / length, length, newShotParams()) == nil) then
			start = handle.Position
		end
	end
	spawnDynamite(player, def, start, target)

	-- Última carga: a arma some da mão.
	if charges <= 0 then
		task.defer(function()
			if tool.Parent then
				tool:Destroy()
			end
		end)
	end
	return true
end

return Combat
