--!nonstrict
-- Modelos dos inimigos, feitos só de parts (estilo blocos). Convenções:
--   * `base` é o ponto no chão sob o NPC; a FRENTE aponta para o -Z local (LookVector);
--   * terrestres: Humanoid R15 (para o HipHeight funcionar em rig próprio) + HumanoidRootPart invisível
--     que colide; o resto do corpo é soldado (WeldConstraint), sem massa e sem colisão. As pernas usam
--     Motor6D para a animação procedural barata (o NPCService só anima perto de jogadores);
--   * voadores (mosquito) e a planta: sem Humanoid; a part raiz é ancorada e as outras soldadas nela,
--     então mover a raiz por CFrame move o corpo todo (só a raiz replica).
-- Os nomes das partes evitam os nomes padrão de personagem (Head, Torso...) para o Humanoid não tratá-las
-- de forma especial.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartBuilder = require(ReplicatedStorage.Shared.Util.PartBuilder)

local Rigs = {}

export type GaitJoint = {
	motor: Motor6D,
	base: CFrame,
	mode: string, -- "swing" (gira na junta) | "lift" (levanta e avança um grupo de pernas)
	amp: number,
	lift: number,
	stride: number,
	phase: number,
}

export type Rig = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid?,
	eye: BasePart, -- origem da linha de visão
	barAdornee: BasePart,
	barOffset: number,
	feetOffset: number, -- altura do centro da raiz acima do chão
	topOffset: number, -- topo da cabeça em relação ao centro da raiz
	gait: { rate: number, joints: { GaitJoint } }?,
	extras: { [string]: any },
}

local M = Enum.Material

-- Construção ----------------------------------------------------------------------------------

local function newRig(name: string, base: CFrame)
	local model = Instance.new("Model")
	model.Name = name
	return {
		model = model,
		base = base,
		root = nil,
		humanoid = nil,
		eye = nil,
		barAdornee = nil,
		barOffset = 2,
		feetOffset = 0,
		topOffset = 2,
		gait = nil,
		extras = {},
		body = {}, -- partes a soldar na raiz
	}
end

-- Part do corpo (solta, sem colisão, sem massa) no CFrame do MUNDO.
local function partAt(
	rig,
	name: string,
	size: Vector3,
	world: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local maxSize = math.max(size.X, size.Y, size.Z)
	local part = PartBuilder.part({
		Name = name,
		Color = color,
		Material = material or M.SmoothPlastic,
		Anchored = false,
		CanCollide = false,
		CanTouch = false,
		Massless = true,
		CastShadow = maxSize >= 1.5,
	}) :: Part
	if shape then
		part.Shape = shape
	end
	part.Size = size
	part.CFrame = world
	part.Parent = rig.model
	return part
end

-- Part do corpo com CFrame LOCAL (relativo a `base`); entra na lista de soldagem na raiz.
local function bodyPart(
	rig,
	name: string,
	size: Vector3,
	localCFrame: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local part = partAt(rig, name, size, rig.base * localCFrame, color, material, shape)
	table.insert(rig.body, part)
	return part
end

-- Segmento (bloco comprido) entre dois pontos locais; não entra na lista de soldagem.
local function segment(rig, name: string, a: Vector3, b: Vector3, thickness: number, color: Color3): Part
	local length = (b - a).Magnitude
	local localCFrame = CFrame.lookAt((a + b) / 2, b)
	return partAt(rig, name, Vector3.new(thickness, thickness, length), rig.base * localCFrame, color, M.SmoothPlastic)
end

-- Part invisível usada como "cubo" de um grupo de pernas.
local function hub(rig, name: string, localCFrame: CFrame): Part
	local part = PartBuilder.part({
		Name = name,
		Transparency = 1,
		Anchored = false,
		CanCollide = false,
		CanTouch = false,
		CastShadow = false,
		Massless = true,
	}) :: Part
	part.CanQuery = false -- só depois de CanCollide = false
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = rig.base * localCFrame
	part.Parent = rig.model
	return part
end

local function weldTo(anchor: BasePart, parts: { BasePart })
	for _, part in parts do
		if part ~= anchor then
			PartBuilder.weld(anchor, part)
		end
	end
end

-- Junta animável. `jointLocal` é o ponto da junta (relativo a `base`).
local function motor(rig, name: string, part0: BasePart, part1: BasePart, jointLocal: CFrame): Motor6D
	local jointWorld = rig.base * jointLocal
	local joint = Instance.new("Motor6D")
	joint.Name = name
	joint.Part0 = part0
	joint.Part1 = part1
	joint.C0 = part0.CFrame:ToObjectSpace(jointWorld)
	joint.C1 = part1.CFrame:ToObjectSpace(jointWorld)
	joint.Parent = part0
	return joint
end

local function swingJoint(joint: Motor6D, amp: number, phase: number): GaitJoint
	return { motor = joint, base = joint.C0, mode = "swing", amp = amp, lift = 0, stride = 0, phase = phase }
end

local function liftJoint(joint: Motor6D, lift: number, stride: number, phase: number): GaitJoint
	return { motor = joint, base = joint.C0, mode = "lift", amp = 0, lift = lift, stride = stride, phase = phase }
end

-- Raiz invisível que colide (terrestres). `centerY` = altura do centro acima do chão.
local function groundRoot(rig, size: Vector3, centerY: number): Part
	local root = PartBuilder.part({
		Name = "HumanoidRootPart",
		Transparency = 1,
		Anchored = false,
		CanCollide = true,
		CanTouch = true,
		CastShadow = false,
		Massless = false,
	}) :: Part
	root.Size = size
	root.CFrame = rig.base * CFrame.new(0, centerY, 0)
	root.Parent = rig.model
	rig.root = root
	rig.feetOffset = centerY
	rig.model.PrimaryPart = root
	return root
end

-- Raiz visível e ancorada (voadores e planta).
local function anchoredRoot(rig, name: string, size: Vector3, localCFrame: CFrame, color: Color3, material): Part
	local root = partAt(rig, name, size, rig.base * localCFrame, color, material)
	root.Anchored = true
	root.Massless = false
	rig.root = root
	rig.model.PrimaryPart = root
	return root
end

-- Humanoid R15 de rig próprio. HipHeight (R15) = distância do chão até a BASE da raiz.
local function addHumanoid(rig, hipHeight: number): Humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.AutomaticScalingEnabled = false
	humanoid.HipHeight = hipHeight
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.UseJumpPower = true
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
	humanoid.Parent = rig.model
	rig.humanoid = humanoid
	return humanoid
end

local builders = {}

-- Macaco (~2,7 studs) ------------------------------------------------------------------------------

local MONKEY = {
	fur = Color3.fromRGB(96, 62, 34),
	furDark = Color3.fromRGB(70, 44, 24),
	face = Color3.fromRGB(214, 170, 122),
	eye = Color3.fromRGB(18, 14, 12),
}

function builders.Monkey(name: string, base: CFrame)
	local rig = newRig(name, base)
	local c = MONKEY
	local rootY = 1.25
	local root = groundRoot(rig, Vector3.new(1.2, 1, 1), rootY)

	bodyPart(rig, "Corpo", Vector3.new(1.1, 1.1, 0.9), CFrame.new(0, 1.3, 0), c.fur, M.Fabric)
	bodyPart(rig, "Barriga", Vector3.new(0.75, 0.75, 0.08), CFrame.new(0, 1.25, -0.48), c.face)
	local head = bodyPart(rig, "Cabeca", Vector3.new(0.95, 0.85, 0.85), CFrame.new(0, 2.25, -0.08), c.fur, M.Fabric)
	bodyPart(rig, "Focinho", Vector3.new(0.6, 0.45, 0.2), CFrame.new(0, 2.12, -0.6), c.face)
	for _, side in { -1, 1 } do
		bodyPart(rig, "Olho", Vector3.new(0.16, 0.16, 0.06), CFrame.new(side * 0.2, 2.42, -0.53), c.eye)
		bodyPart(rig, "Orelha", Vector3.new(0.12, 0.35, 0.35), CFrame.new(side * 0.53, 2.3, -0.05), c.face)
		bodyPart(rig, "Braco", Vector3.new(0.32, 1.2, 0.32), CFrame.new(side * 0.72, 1.3, -0.05), c.furDark, M.Fabric)
	end
	bodyPart(rig, "Rabo", Vector3.new(0.2, 0.2, 0.9), CFrame.new(0, 0.95, 0.85), c.furDark)
	bodyPart(rig, "Rabo", Vector3.new(0.2, 0.9, 0.2), CFrame.new(0, 1.3, 1.2), c.furDark)
	weldTo(root, rig.body)

	local joints = {}
	for index, side in { -1, 1 } do
		local leg = partAt(
			rig,
			"Perna",
			Vector3.new(0.4, 0.8, 0.45),
			base * CFrame.new(side * 0.3, 0.4, 0),
			c.furDark,
			M.Fabric
		)
		local hip = motor(rig, "Quadril", root, leg, CFrame.new(side * 0.3, 0.8, 0))
		table.insert(joints, swingJoint(hip, 0.7, if index == 1 then 0 else math.pi))
	end
	rig.gait = { rate = 0.55, joints = joints }

	rig.eye = head
	rig.barAdornee = head
	rig.barOffset = 1.3
	rig.topOffset = 2.675 - rootY
	addHumanoid(rig, rootY - 0.5)
	return rig
end

-- Leão -----------------------------------------------------------------------------------------------

local LION = {
	body = Color3.fromRGB(212, 160, 84),
	dark = Color3.fromRGB(176, 124, 58),
	mane = Color3.fromRGB(118, 66, 28),
	muzzle = Color3.fromRGB(232, 196, 140),
	nose = Color3.fromRGB(58, 36, 26),
	eye = Color3.fromRGB(255, 186, 52),
}

function builders.Lion(name: string, base: CFrame)
	local rig = newRig(name, base)
	local c = LION
	local rootY = 3.1
	local root = groundRoot(rig, Vector3.new(2.6, 2, 4.4), rootY)

	bodyPart(rig, "Corpo", Vector3.new(2.8, 2.2, 5.6), CFrame.new(0, 3.2, 0.2), c.body, M.Fabric)
	bodyPart(rig, "Peito", Vector3.new(3, 2.5, 1.6), CFrame.new(0, 3.4, -2.2), c.body, M.Fabric)
	local mane = bodyPart(rig, "Juba", Vector3.new(3.6, 3.4, 1.8), CFrame.new(0, 4.4, -3), c.mane, M.Fabric)
	local head = bodyPart(rig, "Cabeca", Vector3.new(2.2, 2, 2), CFrame.new(0, 4.6, -3.9), c.body, M.Fabric)
	bodyPart(rig, "Focinho", Vector3.new(1.3, 0.9, 1), CFrame.new(0, 4.1, -5.2), c.muzzle)
	bodyPart(rig, "Nariz", Vector3.new(0.5, 0.35, 0.2), CFrame.new(0, 4.45, -5.72), c.nose)
	for _, side in { -1, 1 } do
		bodyPart(rig, "Olho", Vector3.new(0.3, 0.22, 0.1), CFrame.new(side * 0.55, 5.05, -4.92), c.eye, M.Neon)
		bodyPart(rig, "Orelha", Vector3.new(0.45, 0.45, 0.3), CFrame.new(side * 0.8, 5.75, -4.3), c.dark)
	end
	bodyPart(rig, "Rabo", Vector3.new(0.3, 0.3, 2.6), CFrame.new(0, 3.8, 4.3), c.dark)
	bodyPart(rig, "PontaDoRabo", Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, 3.8, 5.8), c.mane, M.Fabric)
	weldTo(root, rig.body)

	-- Pernas em pares diagonais (trote): cada par fica soldado num "cubo" com Motor6D na raiz.
	local hubA = hub(rig, "PassoA", CFrame.new(0, 2.2, 0))
	local hubB = hub(rig, "PassoB", CFrame.new(0, 2.2, 0))
	local legSize = Vector3.new(0.85, 2.2, 0.85)
	local function leg(x: number, z: number): Part
		return partAt(rig, "Pata", legSize, base * CFrame.new(x, 1.1, z), c.body, M.Fabric)
	end
	weldTo(hubA, { leg(-0.95, -2), leg(0.95, 2) })
	weldTo(hubB, { leg(0.95, -2), leg(-0.95, 2) })
	local jointA = motor(rig, "PassoA", root, hubA, CFrame.new(0, 2.2, 0))
	local jointB = motor(rig, "PassoB", root, hubB, CFrame.new(0, 2.2, 0))
	rig.gait = { rate = 0.5, joints = { liftJoint(jointA, 0.5, 0.45, 0), liftJoint(jointB, 0.5, 0.45, math.pi) } }

	rig.eye = head
	rig.barAdornee = mane
	rig.barOffset = 2.6
	rig.topOffset = 6.1 - rootY
	addHumanoid(rig, rootY - 1)
	return rig
end

-- O Caçador ------------------------------------------------------------------------------------------

local HUNTER = {
	skin = Color3.fromRGB(226, 178, 140),
	shirt = Color3.fromRGB(170, 146, 96),
	pants = Color3.fromRGB(92, 72, 48),
	boots = Color3.fromRGB(48, 34, 24),
	belt = Color3.fromRGB(64, 42, 24),
	hat = Color3.fromRGB(120, 88, 52),
	band = Color3.fromRGB(58, 38, 22),
	mustache = Color3.fromRGB(40, 28, 20),
	eye = Color3.fromRGB(26, 22, 20),
	wood = Color3.fromRGB(110, 66, 32),
	metal = Color3.fromRGB(62, 62, 66),
}

function builders.Hunter(name: string, base: CFrame)
	local rig = newRig(name, base)
	local c = HUNTER
	local rootY = 3
	local root = groundRoot(rig, Vector3.new(2, 2, 1), rootY)

	bodyPart(rig, "Tronco", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), c.shirt, M.Fabric)
	bodyPart(rig, "Cinto", Vector3.new(2.06, 0.3, 1.06), CFrame.new(0, 2.15, 0), c.belt, M.Leather)
	local head = bodyPart(rig, "Cabeca", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 4.6, 0), c.skin)
	for _, side in { -1, 1 } do
		bodyPart(rig, "Olho", Vector3.new(0.18, 0.18, 0.05), CFrame.new(side * 0.25, 4.75, -0.61), c.eye)
		bodyPart(rig, "PontaDoBigode", Vector3.new(0.16, 0.26, 0.12), CFrame.new(side * 0.46, 4.33, -0.64), c.mustache)
	end
	bodyPart(rig, "Bigode", Vector3.new(0.8, 0.18, 0.12), CFrame.new(0, 4.42, -0.64), c.mustache)
	bodyPart(rig, "AbaDoChapeu", Vector3.new(2.3, 0.15, 2.3), CFrame.new(0, 5.25, 0), c.hat, M.Fabric)
	bodyPart(rig, "CopaDoChapeu", Vector3.new(1.3, 0.7, 1.3), CFrame.new(0, 5.65, 0), c.hat, M.Fabric)
	bodyPart(rig, "FitaDoChapeu", Vector3.new(1.34, 0.18, 1.34), CFrame.new(0, 5.42, 0), c.band)
	-- Braços para a frente, segurando o rifle.
	bodyPart(rig, "BracoDireito", Vector3.new(0.75, 0.75, 1.9), CFrame.new(1, 3.55, -0.85), c.shirt, M.Fabric)
	bodyPart(rig, "BracoEsquerdo", Vector3.new(0.75, 0.75, 1.9), CFrame.new(-0.7, 3.45, -1.05), c.shirt, M.Fabric)
	bodyPart(rig, "Mao", Vector3.new(0.55, 0.55, 0.4), CFrame.new(1, 3.55, -1.95), c.skin)
	bodyPart(rig, "Mao", Vector3.new(0.55, 0.55, 0.4), CFrame.new(-0.55, 3.45, -2.15), c.skin)
	bodyPart(rig, "Rifle", Vector3.new(0.35, 0.45, 2.5), CFrame.new(0.45, 3.75, -1.75), c.wood, M.Wood)
	bodyPart(rig, "Luneta", Vector3.new(0.22, 0.22, 0.9), CFrame.new(0.45, 4.12, -1.9), c.metal, M.Metal)
	local barrel =
		bodyPart(rig, "CanoDoRifle", Vector3.new(0.2, 0.2, 2.4), CFrame.new(0.45, 3.85, -4.15), c.metal, M.Metal)
	weldTo(root, rig.body)

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Boca"
	muzzle.Position = Vector3.new(0, 0, -1.25)
	muzzle.Parent = barrel

	local joints = {}
	for index, side in { -1, 1 } do
		local leg = partAt(
			rig,
			"Perna",
			Vector3.new(0.9, 2, 0.9),
			base * CFrame.new(side * 0.5, 1, 0),
			c.pants,
			M.Fabric
		)
		local boot = partAt(
			rig,
			"Bota",
			Vector3.new(0.94, 0.45, 1.1),
			base * CFrame.new(side * 0.5, 0.225, -0.08),
			c.boots,
			M.Leather
		)
		PartBuilder.weld(leg, boot)
		local hip = motor(rig, "Quadril", root, leg, CFrame.new(side * 0.5, 2, 0))
		table.insert(joints, swingJoint(hip, 0.5, if index == 1 then 0 else math.pi))
	end
	rig.gait = { rate = 0.6, joints = joints }

	rig.eye = head
	rig.barAdornee = head
	rig.barOffset = 2
	rig.topOffset = 6 - rootY
	rig.extras.muzzle = muzzle
	rig.extras.barrel = barrel
	addHumanoid(rig, rootY - 1)
	return rig
end

-- Aranha Gigante -------------------------------------------------------------------------------------

local SPIDER = {
	body = Color3.fromRGB(34, 28, 26),
	leg = Color3.fromRGB(46, 36, 30),
	mark = Color3.fromRGB(170, 30, 30),
	eye = Color3.fromRGB(255, 40, 40),
	fang = Color3.fromRGB(230, 220, 200),
}

function builders.Spider(name: string, base: CFrame)
	local rig = newRig(name, base)
	local c = SPIDER
	local rootY = 2.2
	local root = groundRoot(rig, Vector3.new(3, 1.6, 4), rootY)

	local thorax = bodyPart(rig, "Cabeca", Vector3.new(2.2, 1.4, 2), CFrame.new(0, 2.3, -1.4), c.body, M.Fabric)
	local abdomen = bodyPart(rig, "Abdomen", Vector3.new(3.2, 2.4, 3.2), CFrame.new(0, 2.8, 1.3), c.body, M.Fabric)
	bodyPart(rig, "Marca", Vector3.new(1.2, 0.1, 1.4), CFrame.new(0, 4.02, 1.3), c.mark)
	for _, side in { -1, 1 } do
		bodyPart(rig, "Olho", Vector3.new(0.35, 0.3, 0.1), CFrame.new(side * 0.45, 2.65, -2.42), c.eye, M.Neon)
		bodyPart(rig, "Presa", Vector3.new(0.22, 0.6, 0.22), CFrame.new(side * 0.35, 1.75, -2.35), c.fang)
	end
	weldTo(root, rig.body)

	-- 8 pernas de dois segmentos, em dois grupos alternados (como uma aranha de verdade anda).
	local hubA = hub(rig, "PassoA", CFrame.new(0, 2.4, 0))
	local hubB = hub(rig, "PassoB", CFrame.new(0, 2.4, 0))
	local groupA, groupB = {}, {}
	for index, z in { -1.8, -0.9, 0, 0.9 } do
		for _, side in { -1, 1 } do
			local hip = Vector3.new(side * 1, 2.4, z)
			local knee = Vector3.new(side * 2.6, 3.4, z * 1.25)
			local foot = Vector3.new(side * 3.9, 0.05, z * 1.6)
			local upper = segment(rig, "Perna", hip, knee, 0.32, c.leg)
			local lower = segment(rig, "Perna", knee, foot, 0.28, c.leg)
			local inA = (index % 2 == 1) == (side == -1)
			local group = if inA then groupA else groupB
			table.insert(group, upper)
			table.insert(group, lower)
		end
	end
	weldTo(hubA, groupA)
	weldTo(hubB, groupB)
	local jointA = motor(rig, "PassoA", root, hubA, CFrame.new(0, 2.4, 0))
	local jointB = motor(rig, "PassoB", root, hubB, CFrame.new(0, 2.4, 0))
	rig.gait = { rate = 0.6, joints = { liftJoint(jointA, 0.45, 0.3, 0), liftJoint(jointB, 0.45, 0.3, math.pi) } }

	rig.eye = thorax
	rig.barAdornee = abdomen
	rig.barOffset = 2.4
	rig.topOffset = 4 - rootY
	rig.extras.mouth = thorax
	addHumanoid(rig, rootY - 0.8)
	return rig
end

-- Mosquito Gigante -----------------------------------------------------------------------------------

local MOSQUITO = {
	body = Color3.fromRGB(58, 52, 46),
	stripe = Color3.fromRGB(150, 140, 120),
	wing = Color3.fromRGB(200, 220, 230),
	eye = Color3.fromRGB(150, 20, 20),
	beak = Color3.fromRGB(30, 26, 22),
}

Rigs.MOSQUITO_HOVER = 7 -- altura em que o mosquito nasce acima do ponto no chão

function builders.Mosquito(name: string, base: CFrame)
	local rig = newRig(name, base)
	local c = MOSQUITO
	local h = Rigs.MOSQUITO_HOVER
	local root = anchoredRoot(rig, "Torax", Vector3.new(0.9, 0.8, 0.9), CFrame.new(0, h, 0), c.body, M.Fabric)
	root.CanCollide = false

	bodyPart(rig, "Abdomen", Vector3.new(0.65, 0.65, 1.6), CFrame.new(0, h - 0.1, 1.15), c.body, M.Fabric)
	bodyPart(rig, "Listra", Vector3.new(0.68, 0.68, 0.25), CFrame.new(0, h - 0.1, 1.05), c.stripe)
	local head = bodyPart(rig, "Cabeca", Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, h + 0.1, -0.7), c.body)
	bodyPart(
		rig,
		"Ferrao",
		Vector3.new(0.1, 0.1, 1.3),
		CFrame.new(0, h - 0.25, -1.55) * CFrame.Angles(math.rad(-20), 0, 0),
		c.beak
	)
	for _, side in { -1, 1 } do
		bodyPart(rig, "Olho", Vector3.new(0.25, 0.3, 0.2), CFrame.new(side * 0.25, h + 0.2, -0.95), c.eye, M.Neon)
		local wing = bodyPart(
			rig,
			"Asa",
			Vector3.new(1.6, 0.05, 0.7),
			CFrame.new(side * 1, h + 0.45, 0.1) * CFrame.Angles(0, 0, side * math.rad(15)),
			c.wing,
			M.Glass
		)
		wing.Transparency = 0.45
		for _, z in { -0.2, 0.3 } do
			bodyPart(rig, "Pata", Vector3.new(0.08, 1.1, 0.08), CFrame.new(side * 0.35, h - 0.8, z), c.beak)
		end
	end
	weldTo(root, rig.body)

	rig.eye = head
	rig.barAdornee = root
	rig.barOffset = 1.6
	rig.feetOffset = h
	rig.topOffset = 0.8
	return rig
end

-- Planta Carnívora -----------------------------------------------------------------------------------

local PLANT = {
	pot = Color3.fromRGB(150, 84, 50),
	soil = Color3.fromRGB(70, 48, 30),
	stem = Color3.fromRGB(52, 120, 46),
	leaf = Color3.fromRGB(70, 150, 60),
	head = Color3.fromRGB(168, 44, 66),
	inner = Color3.fromRGB(236, 104, 124),
	teeth = Color3.fromRGB(240, 236, 220),
}

Rigs.PLANT_HEAD_Y = 5 -- altura do centro da cabeça acima do chão
Rigs.PLANT_REST_OPEN = 0.12 -- abertura da boca em repouso (radianos)
local PLANT_HINGE_BACK = 0.9
local PLANT_JAW_LENGTH = 2.2
local PLANT_JAW_HALF = 0.35

-- CFrames das duas mandíbulas para a cabeça virada (`yaw`, `pitch`) e aberta (`open`, radianos).
function Rigs.PlantJawCFrames(base: CFrame, yaw: number, pitch: number, open: number): (CFrame, CFrame)
	local hinge = base
		* CFrame.new(0, Rigs.PLANT_HEAD_Y, 0)
		* CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(pitch, 0, 0)
		* CFrame.new(0, 0, PLANT_HINGE_BACK)
	local upper = hinge * CFrame.Angles(open, 0, 0) * CFrame.new(0, PLANT_JAW_HALF, -PLANT_JAW_LENGTH / 2)
	local lower = hinge * CFrame.Angles(-open * 0.6, 0, 0) * CFrame.new(0, -PLANT_JAW_HALF, -PLANT_JAW_LENGTH / 2)
	return upper, lower
end

function builders.Plant(name: string, base: CFrame)
	local rig = newRig(name, base)
	local c = PLANT
	local root = anchoredRoot(rig, "Vaso", Vector3.new(2.8, 1.6, 2.8), CFrame.new(0, 0.8, 0), c.pot, M.Slate)
	root.CanCollide = true
	root.CanTouch = true

	bodyPart(rig, "Terra", Vector3.new(2.5, 0.1, 2.5), CFrame.new(0, 1.62, 0), c.soil, M.Ground)
	local stem = bodyPart(rig, "Caule", Vector3.new(0.6, 3.6, 0.6), CFrame.new(0, 3.4, 0), c.stem, M.Grass)
	for _, side in { -1, 1 } do
		bodyPart(
			rig,
			"Folha",
			Vector3.new(1.8, 0.12, 0.8),
			CFrame.new(side * 1, 2.6, 0) * CFrame.Angles(0, 0, side * math.rad(20)),
			c.leaf,
			M.Grass
		)
	end
	weldTo(root, rig.body)

	-- Mandíbulas ancoradas (animadas por tween); dentes e "boca" soldados em cada uma.
	local upperCFrame, lowerCFrame = Rigs.PlantJawCFrames(base, 0, 0, Rigs.PLANT_REST_OPEN)
	local jawSize = Vector3.new(2.2, 0.7, 2.2)
	local upper = partAt(rig, "MandibulaDeCima", jawSize, upperCFrame, c.head)
	local lower = partAt(rig, "MandibulaDeBaixo", jawSize, lowerCFrame, c.head)
	upper.Anchored = true
	lower.Anchored = true
	local upperExtras = { partAt(rig, "Boca", Vector3.new(1.9, 0.08, 1.9), upperCFrame * CFrame.new(0, -0.36, 0), c.inner) }
	local lowerExtras = { partAt(rig, "Boca", Vector3.new(1.9, 0.08, 1.9), lowerCFrame * CFrame.new(0, 0.36, 0), c.inner) }
	for _, x in { -0.6, 0, 0.6 } do
		local toothSize = Vector3.new(0.25, 0.35, 0.25)
		table.insert(upperExtras, partAt(rig, "Dente", toothSize, upperCFrame * CFrame.new(x, -0.5, -0.9), c.teeth))
		table.insert(lowerExtras, partAt(rig, "Dente", toothSize, lowerCFrame * CFrame.new(x, 0.5, -0.9), c.teeth))
	end
	weldTo(upper, upperExtras)
	weldTo(lower, lowerExtras)

	rig.eye = stem
	rig.barAdornee = stem
	rig.barOffset = 4
	rig.feetOffset = 0.8
	rig.topOffset = Rigs.PLANT_HEAD_Y + 1 - 0.8
	rig.extras.upperJaw = upper
	rig.extras.lowerJaw = lower
	rig.extras.base = base
	return rig
end

-- API ----------------------------------------------------------------------------------------------

-- Monta o modelo do tipo `kind` com o nome `name` em `base` (ponto no chão, frente = LookVector).
-- O modelo volta SEM pai: quem chama configura e coloca em workspace.NPCs.
function Rigs.Build(kind: string, name: string, base: CFrame): Rig?
	local builder = builders[kind]
	if not builder then
		return nil
	end
	local rig = builder(name, base)
	rig.body = nil
	return rig :: any
end

return Rigs
