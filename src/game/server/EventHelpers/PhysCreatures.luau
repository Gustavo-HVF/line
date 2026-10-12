--!nonstrict
-- Criaturas de blocos dos eventos físicos (rinoceronte, elefante e pelicano), feitas só com parts.
-- Cada criatura tem uma part raiz ancorada (o corpo) e as outras soldadas nela: para mover, basta mudar
-- `root.CFrame` (só a raiz replica para os clientes, bem mais leve que mover cada part).
-- As medidas são relativas ao corpo; a FRENTE da criatura aponta para o -Z local.

local PhysUtil = require(script.Parent.PhysUtil)

local PhysCreatures = {}

export type Creature = {
	model: Model,
	root: BasePart,
	footOffset: number, -- distância do centro da raiz até a sola dos pés
	halfWidth: number,
	frontReach: number, -- quanto a criatura avança à frente do centro (-Z)
	backReach: number,
	topY: number, -- topo da criatura em relação ao centro da raiz
	wings: { { part: BasePart, side: number, offset: CFrame } },
}

type Spec = {
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?,
	shadow: boolean?,
	shape: Enum.PartType?,
}

local M = Enum.Material

local function spec(
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?,
	shadow: boolean?,
	shape: Enum.PartType?
): Spec
	return {
		name = name,
		size = size,
		offset = offset,
		color = color,
		material = material,
		shadow = shadow,
		shape = shape,
	}
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- Monta as parts a partir das especificações já na pose `cframe` (soldar fora do workspace exige que as
-- parts estejam na posição final relativa) e só então coloca o Model no pai.
local function assemble(name: string, parent: Instance, cframe: CFrame, specs: { Spec }): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = name
	local parts: { BasePart } = {}
	local root: BasePart = nil
	for index, item in specs do
		local part = PhysUtil.GhostPart({
			Name = item.name,
			Size = item.size,
			CFrame = cframe * item.offset,
			Color = item.color,
			Material = item.material or M.SmoothPlastic,
			CastShadow = item.shadow == true,
			Parent = model,
		})
		if item.shape then
			(part :: Part).Shape = item.shape
		end
		if index == 1 then
			root = part
		end
		table.insert(parts, part)
	end
	PhysUtil.WeldAll(root, parts)
	model.PrimaryPart = root
	model.Parent = parent
	return model, root
end

-- Rinoceronte (≈ 4 x 6,5 x 11 studs) ----------------------------------------------------------

local RHINO_SKIN = Color3.fromRGB(122, 118, 112)
local RHINO_DARK = Color3.fromRGB(92, 88, 84)
local HORN = Color3.fromRGB(222, 212, 188)

function PhysCreatures.Rhino(parent: Instance, cframe: CFrame): Creature
	local footOffset = 4.1
	local legY = -footOffset + 1.3
	local specs = {
		spec("Corpo", Vector3.new(4.2, 3.8, 7.5), at(0, 0, 0), RHINO_SKIN, M.Slate, true),
		spec("Cabeca", Vector3.new(2.6, 2.4, 2.8), at(0, -0.2, -4.9), RHINO_SKIN, M.Slate),
		spec("Focinho", Vector3.new(2, 1.6, 1.5), at(0, -0.7, -6.6), RHINO_DARK, M.Slate),
		spec("Chifre", Vector3.new(0.7, 1.9, 0.7), at(0, 0.5, -6.9) * CFrame.Angles(math.rad(-28), 0, 0), HORN),
		spec("ChifreMenor", Vector3.new(0.5, 1, 0.5), at(0, 0.5, -5.7) * CFrame.Angles(math.rad(-15), 0, 0), HORN),
		spec("OrelhaE", Vector3.new(0.35, 0.9, 0.35), at(-0.9, 1.3, -4.2), RHINO_DARK),
		spec("OrelhaD", Vector3.new(0.35, 0.9, 0.35), at(0.9, 1.3, -4.2), RHINO_DARK),
		spec("PataFE", Vector3.new(1.2, 2.6, 1.2), at(-1.4, legY, -2.4), RHINO_DARK, M.Slate),
		spec("PataFD", Vector3.new(1.2, 2.6, 1.2), at(1.4, legY, -2.4), RHINO_DARK, M.Slate),
		spec("PataTE", Vector3.new(1.2, 2.6, 1.2), at(-1.4, legY, 2.4), RHINO_DARK, M.Slate),
		spec("PataTD", Vector3.new(1.2, 2.6, 1.2), at(1.4, legY, 2.4), RHINO_DARK, M.Slate),
		spec("Rabo", Vector3.new(0.3, 1.3, 0.3), at(0, 0.6, 3.95) * CFrame.Angles(math.rad(25), 0, 0), RHINO_DARK),
	}
	local model, root = assemble("Rinoceronte", parent, cframe, specs)
	return {
		model = model,
		root = root,
		footOffset = footOffset,
		halfWidth = 2.2,
		frontReach = 7.4,
		backReach = 4.2,
		topY = 2.2,
		wings = {},
	}
end

-- Elefante (≈ 6 x 10,5 x 13 studs) ------------------------------------------------------------

local ELEPHANT_SKIN = Color3.fromRGB(132, 126, 124)
local ELEPHANT_DARK = Color3.fromRGB(104, 98, 96)
local TUSK = Color3.fromRGB(238, 230, 212)

function PhysCreatures.Elephant(parent: Instance, cframe: CFrame): Creature
	local footOffset = 6.6
	local legY = -footOffset + 2.1
	local specs = {
		spec("Corpo", Vector3.new(6, 5.6, 9.5), at(0, 0, 0), ELEPHANT_SKIN, M.Slate, true),
		spec("Cabeca", Vector3.new(4, 4, 3.4), at(0, 1.2, -5.8), ELEPHANT_SKIN, M.Slate),
		spec(
			"OrelhaE",
			Vector3.new(0.4, 3.8, 3.2),
			at(-2.3, 1.2, -4.9) * CFrame.Angles(0, math.rad(-20), 0),
			ELEPHANT_DARK
		),
		spec(
			"OrelhaD",
			Vector3.new(0.4, 3.8, 3.2),
			at(2.3, 1.2, -4.9) * CFrame.Angles(0, math.rad(20), 0),
			ELEPHANT_DARK
		),
		spec("Tromba1", Vector3.new(1.3, 2.4, 1.3), at(0, -1.2, -7.3), ELEPHANT_SKIN, M.Slate),
		spec("Tromba2", Vector3.new(1, 2.2, 1), at(0, -3.3, -7.6), ELEPHANT_SKIN, M.Slate),
		spec(
			"Tromba3",
			Vector3.new(0.8, 1.4, 0.8),
			at(0, -4.8, -7.2) * CFrame.Angles(math.rad(-25), 0, 0),
			ELEPHANT_DARK
		),
		spec("PresaE", Vector3.new(0.45, 0.45, 2.3), at(-0.9, -0.9, -8) * CFrame.Angles(math.rad(18), 0, 0), TUSK),
		spec("PresaD", Vector3.new(0.45, 0.45, 2.3), at(0.9, -0.9, -8) * CFrame.Angles(math.rad(18), 0, 0), TUSK),
		spec("PataFE", Vector3.new(1.9, 4.2, 1.9), at(-1.9, legY, -3.1), ELEPHANT_DARK, M.Slate),
		spec("PataFD", Vector3.new(1.9, 4.2, 1.9), at(1.9, legY, -3.1), ELEPHANT_DARK, M.Slate),
		spec("PataTE", Vector3.new(1.9, 4.2, 1.9), at(-1.9, legY, 3.1), ELEPHANT_DARK, M.Slate),
		spec("PataTD", Vector3.new(1.9, 4.2, 1.9), at(1.9, legY, 3.1), ELEPHANT_DARK, M.Slate),
		spec("Rabo", Vector3.new(0.35, 2, 0.35), at(0, 0.8, 4.95) * CFrame.Angles(math.rad(20), 0, 0), ELEPHANT_DARK),
	}
	local model, root = assemble("Elefante", parent, cframe, specs)
	return {
		model = model,
		root = root,
		footOffset = footOffset,
		halfWidth = 3.2,
		frontReach = 9.2,
		backReach = 5.2,
		topY = 3.4,
		wings = {},
	}
end

-- Pelicano (≈ 17 studs de envergadura) -----------------------------------------------------------

local FEATHER = Color3.fromRGB(242, 238, 230)
local FEATHER_GRAY = Color3.fromRGB(190, 188, 182)
local BEAK = Color3.fromRGB(242, 184, 64)
local POUCH = Color3.fromRGB(232, 148, 72)
local WING_TIP = Color3.fromRGB(44, 42, 40)

local WING_LENGTH = 7
local WING_ROOT = Vector3.new(1.4, 0.6, -0.2)

function PhysCreatures.Pelican(parent: Instance, cframe: CFrame): Creature
	local specs = {
		spec("Corpo", Vector3.new(3, 2.6, 5.5), at(0, 0, 0), FEATHER, M.SmoothPlastic, true),
		spec("Pescoco", Vector3.new(1, 2.4, 1), at(0, 1.6, -2.6), FEATHER),
		spec("Cabeca", Vector3.new(1.5, 1.4, 1.8), at(0, 2.9, -3.2), FEATHER),
		spec("Bico", Vector3.new(0.7, 0.4, 4.2), at(0, 2.7, -5.9), BEAK),
		spec("Papo", Vector3.new(0.8, 1, 3.4), at(0, 2.05, -5.6), POUCH),
		spec("OlhoE", Vector3.new(0.25, 0.25, 0.25), at(-0.76, 3.1, -3.5), WING_TIP),
		spec("OlhoD", Vector3.new(0.25, 0.25, 0.25), at(0.76, 3.1, -3.5), WING_TIP),
		spec("Cauda", Vector3.new(2.2, 0.4, 1.8), at(0, 0.3, 3.5), FEATHER_GRAY),
		spec("PeE", Vector3.new(0.5, 1.3, 0.5), at(-0.7, -1.8, 0.6), POUCH),
		spec("PeD", Vector3.new(0.5, 1.3, 0.5), at(0.7, -1.8, 0.6), POUCH),
	}
	local model, root = assemble("Pelicano", parent, cframe, specs)

	-- Asas: parts ancoradas à parte (batem as asas mudando o CFrame), cada uma com a ponta preta soldada.
	local wings = {}
	for _, side in { -1, 1 } do
		local offset = CFrame.new(WING_ROOT.X * side, WING_ROOT.Y, WING_ROOT.Z)
		local wingCFrame = cframe * offset * CFrame.new(side * WING_LENGTH / 2, 0, 0)
		local wing = PhysUtil.GhostPart({
			Name = side < 0 and "AsaE" or "AsaD",
			Size = Vector3.new(WING_LENGTH, 0.35, 3.2),
			CFrame = wingCFrame,
			Color = FEATHER,
			Material = M.SmoothPlastic,
			CastShadow = true,
		})
		local tip = PhysUtil.GhostPart({
			Name = "PontaDaAsa",
			Size = Vector3.new(2.4, 0.37, 3.2),
			CFrame = wingCFrame * CFrame.new(side * (WING_LENGTH / 2 - 1.2), 0, 0),
			Color = WING_TIP,
			Material = M.SmoothPlastic,
		})
		PhysUtil.WeldAll(wing, { tip })
		tip.Parent = wing
		wing.Parent = model
		table.insert(wings, { part = wing, side = side, offset = offset })
	end

	return {
		model = model,
		root = root,
		footOffset = 2.4,
		halfWidth = WING_LENGTH + WING_ROOT.X,
		frontReach = 8,
		backReach = 4.5,
		topY = 3.6,
		wings = wings,
	}
end

-- Posiciona as asas para um ângulo de batida (radianos; positivo = asas para cima).
function PhysCreatures.SetWings(creature: Creature, angle: number)
	local rootCFrame = creature.root.CFrame
	for _, wing in creature.wings do
		if wing.part.Parent then
			wing.part.CFrame = rootCFrame
				* wing.offset
				* CFrame.Angles(0, 0, wing.side * angle)
				* CFrame.new(wing.side * WING_LENGTH / 2, 0, 0)
		end
	end
end

return PhysCreatures
