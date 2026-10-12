--!nonstrict
-- Projéteis dos NPCs (servidor). Não têm loop próprio: o agendador do NPCService chama Step a cada frame.
--   * Teia da aranha: bola com física do servidor e sem colisão (a rede interpola, fica suave no
--     celular). Acertou um jogador → callback (lentidão); acertou o cenário → mancha de teia que some.
--   * Objeto arremessado pelo macaco: o objeto já voa com física; aqui só se verifica, ao longo do
--     trajeto, se passou por um jogador (dano ao "tocar"), até parar ou acabar o tempo.
-- A colisão com jogadores é geométrica (distância do segmento percorrido no frame até o jogador).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartBuilder = require(ReplicatedStorage.Shared.Util.PartBuilder)

local CombatUtil = require(script.Parent.Parent.CombatUtil)
local Effects = require(script.Parent.Effects)

local Projectiles = {}

local MAX_ACTIVE = 24
local MAX_SPLATS = 12
local SPLAT_LIFETIME = 4
local SPLAT_CHECK = 0.5
local PLAYER_RADIUS = 1.8 -- "espessura" do personagem
local PROP_SETTLE_TIME = 0.35 -- depois disto, objeto quase parado deixa de ser perigoso
local PROP_SETTLE_SPEED = 4
local WEB_COLOR = Color3.fromRGB(240, 240, 236)

type Entry = {
	kind: string,
	owner: any,
	part: BasePart,
	ownsPart: boolean,
	lastPos: Vector3,
	started: number,
	lifetime: number,
	radius: number,
	hitsWorld: boolean,
	onHitPlayer: (Player, Vector3) -> (),
	onHitWorld: ((RaycastResult) -> ())?,
}

local active: { Entry } = {}
local splats: { { part: BasePart, expires: number } } = {}
local lastSplatCheck = 0

local function removeAt(index: number)
	local entry = table.remove(active, index)
	if entry and entry.ownsPart and entry.part.Parent then
		entry.part:Destroy()
	end
end

local function distanceToSegment(point: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	if lengthSq < 1e-6 then
		return (point - a).Magnitude
	end
	local t = math.clamp((point - a):Dot(ab) / lengthSq, 0, 1)
	return (point - (a + ab * t)).Magnitude
end

-- Velocidade inicial para ir de `from` a `to` em `flight` segundos com a gravidade do workspace.
function Projectiles.BallisticVelocity(from: Vector3, to: Vector3, flight: number): Vector3
	local t = math.max(flight, 0.05)
	return (to - from) / t + Vector3.new(0, 0.5 * workspace.Gravity * t, 0)
end

-- Bola de teia de `origin` até `target`. `onHitPlayer(player, position)` é chamado ao acertar alguém.
function Projectiles.FireWeb(owner: any, origin: Vector3, target: Vector3, onHitPlayer: (Player, Vector3) -> ())
	if #active >= MAX_ACTIVE then
		return
	end
	local distance = (target - origin).Magnitude
	local flight = math.clamp(distance / 70, 0.25, 0.9)
	local ball = PartBuilder.part({
		Name = "Teia",
		Color = WEB_COLOR,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.1,
		Anchored = false,
		CanCollide = false,
		CanTouch = false,
		CastShadow = false,
	}) :: Part
	ball.CanQuery = false -- só depois de CanCollide = false
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(1.2, 1.2, 1.2)
	ball.CFrame = CFrame.new(origin)
	ball.Parent = Effects.Folder()
	pcall(ball.SetNetworkOwner, ball, nil)
	ball.AssemblyLinearVelocity = Projectiles.BallisticVelocity(origin, target, flight)

	table.insert(active, {
		kind = "web",
		owner = owner,
		part = ball,
		ownsPart = true,
		lastPos = origin,
		started = os.clock(),
		lifetime = flight + 1.2,
		radius = 0.6,
		hitsWorld = true,
		onHitPlayer = onHitPlayer,
		onHitWorld = function(result: RaycastResult)
			Projectiles.Splat(result.Position, result.Normal)
		end,
	})
end

-- Passa a vigiar um objeto já lançado: quem estiver no caminho leva `damage`.
function Projectiles.TrackProp(
	owner: any,
	part: BasePart,
	options: { damage: number, source: string, lifetime: number? }
)
	if #active >= MAX_ACTIVE or not part.Parent then
		return
	end
	local damage = options.damage
	local source = options.source
	table.insert(active, {
		kind = "prop",
		owner = owner,
		part = part,
		ownsPart = false,
		lastPos = part.Position,
		started = os.clock(),
		lifetime = options.lifetime or 2,
		radius = math.min(part.Size.Magnitude * 0.4, 3),
		hitsWorld = false,
		onHitPlayer = function(player: Player, _position: Vector3)
			CombatUtil.DamagePlayer(player, damage, source)
			local velocity = part.AssemblyLinearVelocity
			local push = Vector3.new(velocity.X, 0, velocity.Z)
			if push.Magnitude > 0.1 then
				CombatUtil.Knockback(player, push, 25)
			end
		end,
		onHitWorld = nil,
	})
end

-- Mancha de teia decorativa no cenário (some sozinha; no máximo MAX_SPLATS ao mesmo tempo).
function Projectiles.Splat(position: Vector3, normal: Vector3)
	if #splats >= MAX_SPLATS then
		local oldest = table.remove(splats, 1)
		if oldest and oldest.part.Parent then
			oldest.part:Destroy()
		end
	end
	local part = PartBuilder.part({
		Name = "ManchaDeTeia",
		Color = WEB_COLOR,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.3,
		CanCollide = false,
		CanTouch = false,
		CastShadow = false,
	}) :: Part
	part.CanQuery = false
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.1, 3, 3)
	-- O eixo do cilindro (X) fica alinhado com a normal da superfície.
	part.CFrame = CFrame.lookAt(position, position + normal) * CFrame.Angles(0, math.pi / 2, 0)
	part.Parent = Effects.Folder()
	table.insert(splats, { part = part, expires = os.clock() + SPLAT_LIFETIME })
end

-- Avança tudo um frame (chamado pelo agendador do NPCService).
function Projectiles.Step(now: number)
	if now - lastSplatCheck >= SPLAT_CHECK and #splats > 0 then
		lastSplatCheck = now
		for index = #splats, 1, -1 do
			local splat = splats[index]
			if now >= splat.expires or not splat.part.Parent then
				table.remove(splats, index)
				if splat.part.Parent then
					splat.part:Destroy()
				end
			end
		end
	end
	if #active == 0 then
		return
	end

	-- Jogadores vivos com raiz, calculados uma vez por frame.
	local targets = {}
	for _, player in CombatUtil.GetAlivePlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(targets, { player = player, root = root })
		end
	end

	for index = #active, 1, -1 do
		local entry = active[index]
		local part = entry.part
		if not part.Parent or now - entry.started > entry.lifetime then
			removeAt(index)
		else
			local position = part.Position
			local from = entry.lastPos
			entry.lastPos = position
			local hitPlayer: Player? = nil
			for _, target in targets do
				if distanceToSegment(target.root.Position, from, position) <= entry.radius + PLAYER_RADIUS then
					hitPlayer = target.player
					break
				end
			end
			if hitPlayer then
				local callback = entry.onHitPlayer
				removeAt(index)
				local ok, err = pcall(callback, hitPlayer, position)
				if not ok then
					warn("[NPC] Erro no acerto de projétil: " .. tostring(err))
				end
			elseif entry.hitsWorld then
				local delta = position - from
				if delta.Magnitude > 0.05 then
					local result = workspace:Raycast(from, delta, Effects.WorldParams())
					if result then
						local callback = entry.onHitWorld
						removeAt(index)
						if callback then
							pcall(callback, result)
						end
					end
				end
			elseif
				now - entry.started > PROP_SETTLE_TIME and part.AssemblyLinearVelocity.Magnitude < PROP_SETTLE_SPEED
			then
				removeAt(index)
			end
		end
	end
end

-- Remove os projéteis de um NPC (as teias somem; objetos arremessados deixam de causar dano).
function Projectiles.ClearOwner(owner: any)
	for index = #active, 1, -1 do
		if active[index].owner == owner then
			removeAt(index)
		end
	end
end

function Projectiles.ClearAll()
	for index = #active, 1, -1 do
		removeAt(index)
	end
	for _, splat in splats do
		if splat.part.Parent then
			splat.part:Destroy()
		end
	end
	table.clear(splats)
end

return Projectiles
