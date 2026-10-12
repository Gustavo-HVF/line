--!nonstrict
-- Monta as armas por código (não há assets):
--   * CreateTool: a Tool que vai para a Backpack (Handle + partes soldadas com Weld, Tool.Grip ajustado).
--   * BuildDisplay: o modelo ancorado que fica flutuando nos pontos de arma (não é Tool).
-- Também guarda o registro das Tools criadas pelo servidor, com o estado de cadência e recarga de cada uma.
--
-- Espaço da arma: a origem é o centro do Handle, que fica na mão. Com Tool.Grip sem rotação, -Z aponta
-- para a frente do personagem (cano), +Y para cima e +X para a direita. Por isso todo Handle é um bloco
-- sem rotação e as outras partes são descritas nesse espaço.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage.Shared.Tags)

local Definitions = require(script.Parent.Definitions)

local ToolFactory = {}

export type ToolState = {
	kind: string,
	ownerUserId: number,
	lastUse: number,
	reloading: boolean,
	reloadToken: number,
	connections: { RBXScriptConnection },
}

type PartSpec = {
	name: string,
	size: Vector3,
	cframe: CFrame, -- no espaço da arma (relativo ao Handle)
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?,
	wedge: boolean?,
}

type Blueprint = {
	handle: PartSpec,
	parts: { PartSpec },
	attachments: { [string]: CFrame },
	gripTilt: number, -- graus; positivo inclina o topo/cano para a frente e para baixo
	displayCenter: Vector3, -- centro aproximado do modelo (para centralizar no ponto de arma)
	displayTilt: CFrame, -- como a arma "deita" na exibição
}

-- Cores e eixos -----------------------------------------------------------------------------

local WOOD_DARK = Color3.fromRGB(74, 46, 28)
local WOOD = Color3.fromRGB(116, 74, 40)
local METAL_DARK = Color3.fromRGB(52, 54, 60)
local METAL = Color3.fromRGB(104, 108, 116)
local STEEL = Color3.fromRGB(196, 200, 206)
local STEEL_EDGE = Color3.fromRGB(234, 236, 240)
local BRASS = Color3.fromRGB(186, 146, 66)
local DYNAMITE_RED = Color3.fromRGB(176, 38, 30)
local TAPE = Color3.fromRGB(70, 56, 40)
local FUSE = Color3.fromRGB(226, 214, 180)

local M = Enum.Material
local CYLINDER = Enum.PartType.Cylinder
local ALONG_Y = CFrame.Angles(0, 0, math.rad(90)) -- cilindro (eixo X) deitado no eixo Y
local ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- cilindro (eixo X) deitado no eixo Z
local ON_SIDE = CFrame.Angles(0, 0, math.rad(90))

local function spec(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?,
	wedge: boolean?
): PartSpec
	return { name = name, size = size, cframe = cframe, color = color, material = material, shape = shape, wedge = wedge }
end

local BLUEPRINTS: { [string]: Blueprint } = {
	-- Facão: cabo na mão, lâmina para cima (levemente inclinada para a frente), fio virado para a frente.
	Machete = {
		handle = spec("Handle", Vector3.new(0.24, 0.95, 0.32), CFrame.new(), WOOD_DARK, M.Wood),
		parts = {
			spec("Pomo", Vector3.new(0.3, 0.14, 0.38), CFrame.new(0, -0.54, 0), METAL_DARK, M.Metal),
			spec("Guarda", Vector3.new(0.3, 0.12, 0.52), CFrame.new(0, 0.535, 0), METAL_DARK, M.Metal),
			spec("Lamina", Vector3.new(0.06, 2.3, 0.42), CFrame.new(0, 1.74, -0.02), STEEL, M.Metal),
			spec("Fio", Vector3.new(0.07, 2.3, 0.07), CFrame.new(0, 1.74, -0.245), STEEL_EDGE, M.Metal),
			spec("Ponta", Vector3.new(0.06, 0.55, 0.49), CFrame.new(0, 3.165, -0.055), STEEL, M.Metal, nil, true),
		},
		attachments = {
			Tip = CFrame.new(0, 3.4, -0.05),
		},
		gripTilt = 20,
		displayCenter = Vector3.new(0, 1.35, -0.03),
		displayTilt = ON_SIDE,
	},

	-- Revólver: coronha na mão, tambor e cano acima dela apontando para a frente.
	Revolver = {
		handle = spec("Handle", Vector3.new(0.3, 0.85, 0.42), CFrame.new(), WOOD, M.Wood),
		parts = {
			spec("Corpo", Vector3.new(0.32, 0.4, 0.8), CFrame.new(0, 0.6, -0.2), METAL_DARK, M.Metal),
			spec("Tambor", Vector3.new(0.5, 0.48, 0.48), CFrame.new(0, 0.6, -0.32) * ALONG_Z, METAL, M.Metal, CYLINDER),
			spec("Cano", Vector3.new(1.15, 0.2, 0.2), CFrame.new(0, 0.7, -1.15) * ALONG_Z, METAL_DARK, M.Metal, CYLINDER),
			spec("MiraFrontal", Vector3.new(0.05, 0.1, 0.08), CFrame.new(0, 0.84, -1.66), METAL, M.Metal),
			spec("Cao", Vector3.new(0.08, 0.2, 0.14), CFrame.new(0, 0.86, 0.2), METAL, M.Metal),
			spec("Guarda", Vector3.new(0.06, 0.06, 0.34), CFrame.new(0, 0.24, -0.2), BRASS, M.Metal),
			spec("Gatilho", Vector3.new(0.05, 0.18, 0.05), CFrame.new(0, 0.32, -0.12), METAL_DARK, M.Metal),
		},
		attachments = {
			Muzzle = CFrame.new(0, 0.7, -1.78),
		},
		gripTilt = 0,
		displayCenter = Vector3.new(0, 0.45, -0.6),
		displayTilt = ON_SIDE,
	},

	-- Espingarda de dois canos (dois cartuchos), segurada com uma mão.
	Shotgun = {
		handle = spec("Handle", Vector3.new(0.28, 0.6, 0.46), CFrame.new(), WOOD, M.Wood),
		parts = {
			spec(
				"Coronha",
				Vector3.new(0.3, 0.46, 0.85),
				CFrame.new(0, 0.5, 0.55) * CFrame.Angles(math.rad(-8), 0, 0),
				WOOD,
				M.Wood
			),
			spec("Receptor", Vector3.new(0.34, 0.42, 0.85), CFrame.new(0, 0.52, -0.45), METAL_DARK, M.Metal),
			spec(
				"CanoEsquerdo",
				Vector3.new(2.6, 0.2, 0.2),
				CFrame.new(-0.1, 0.6, -2.15) * ALONG_Z,
				METAL,
				M.Metal,
				CYLINDER
			),
			spec(
				"CanoDireito",
				Vector3.new(2.6, 0.2, 0.2),
				CFrame.new(0.1, 0.6, -2.15) * ALONG_Z,
				METAL,
				M.Metal,
				CYLINDER
			),
			spec("Telha", Vector3.new(0.32, 0.22, 1.1), CFrame.new(0, 0.4, -1.4), WOOD, M.Wood),
			spec("Guarda", Vector3.new(0.06, 0.06, 0.36), CFrame.new(0, 0.22, -0.25), METAL_DARK, M.Metal),
			spec("Cao", Vector3.new(0.08, 0.16, 0.12), CFrame.new(0, 0.78, -0.05), METAL, M.Metal),
		},
		attachments = {
			Muzzle = CFrame.new(0, 0.6, -3.5),
		},
		gripTilt = 0,
		displayCenter = Vector3.new(0, 0.45, -1.3),
		displayTilt = ON_SIDE,
	},

	-- Dinamite: três bananas presas por fita (a fita do meio é o Handle) e o pavio em cima.
	Dynamite = {
		handle = spec("Handle", Vector3.new(0.7, 0.16, 0.64), CFrame.new(), TAPE, M.Fabric),
		parts = {
			spec("Banana1", Vector3.new(1.15, 0.3, 0.3), CFrame.new(-0.17, 0, 0.14) * ALONG_Y, DYNAMITE_RED, M.SmoothPlastic, CYLINDER),
			spec("Banana2", Vector3.new(1.15, 0.3, 0.3), CFrame.new(0.17, 0, 0.14) * ALONG_Y, DYNAMITE_RED, M.SmoothPlastic, CYLINDER),
			spec("Banana3", Vector3.new(1.15, 0.3, 0.3), CFrame.new(0, 0, -0.14) * ALONG_Y, DYNAMITE_RED, M.SmoothPlastic, CYLINDER),
			spec("FitaDeCima", Vector3.new(0.7, 0.12, 0.64), CFrame.new(0, 0.38, 0), TAPE, M.Fabric),
			spec("Pavio", Vector3.new(0.06, 0.42, 0.06), CFrame.new(0, 0.78, -0.14), FUSE, M.Fabric),
		},
		attachments = {
			Fuse = CFrame.new(0, 0.99, -0.14),
		},
		gripTilt = 0,
		displayCenter = Vector3.new(0, 0.2, 0),
		displayTilt = CFrame.Angles(math.rad(90), 0, 0),
	},
}

-- Registro --------------------------------------------------------------------------------

-- Chaves fracas: mesmo que algum Destroying se perca, uma Tool coletada não fica presa aqui.
local registry: { [Tool]: ToolState } = setmetatable({}, { __mode = "k" }) :: any

function ToolFactory.GetState(tool: any): ToolState?
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") then
		return nil
	end
	return registry[tool]
end

local function unregister(tool: Tool)
	local state = registry[tool]
	if not state then
		return
	end
	registry[tool] = nil
	state.reloadToken += 1
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
end

-- Construção ------------------------------------------------------------------------------

local function makePart(partSpec: PartSpec, anchored: boolean): BasePart
	local part: BasePart
	if partSpec.wedge then
		part = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		if partSpec.shape then
			block.Shape = partSpec.shape
		end
		part = block
	end
	part.Name = partSpec.name
	part.Size = partSpec.size
	part.Color = partSpec.color
	part.Material = partSpec.material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = anchored
	-- A ordem importa: CanQuery só pode ficar falso com CanCollide falso.
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = not anchored
	return part
end

-- Cria a Tool de um tipo (sem pai). O chamador a coloca na Backpack.
function ToolFactory.CreateTool(kind: string, owner: Player): Tool?
	local def = Definitions.Get(kind)
	local blueprint = BLUEPRINTS[kind]
	if not def or not blueprint then
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = def.displayName
	tool.ToolTip = def.tooltip
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = false
	tool.Grip = CFrame.Angles(math.rad(blueprint.gripTilt), 0, 0)

	local handle = makePart(blueprint.handle, false)
	handle.Name = "Handle"
	handle.CFrame = CFrame.new()
	for name, offset in blueprint.attachments do
		local attachment = Instance.new("Attachment")
		attachment.Name = name
		attachment.CFrame = offset
		attachment.Parent = handle
	end
	handle.Parent = tool

	-- Weld clássico (C0 explícito): a posição relativa não depende de onde as partes estão agora.
	for _, partSpec in blueprint.parts do
		local part = makePart(partSpec, false)
		part.CFrame = partSpec.cframe
		local weld = Instance.new("Weld")
		weld.Name = "Solda"
		weld.Part0 = handle
		weld.Part1 = part
		weld.C0 = partSpec.cframe
		weld.C1 = CFrame.new()
		weld.Parent = part
		part.Parent = tool
	end

	-- Atributos lidos pelo cliente (UI, cadência e alcance da mira). Só o servidor os altera.
	tool:SetAttribute("WeaponKind", kind)
	tool:SetAttribute("DisplayName", def.displayName)
	tool:SetAttribute("Category", def.category)
	tool:SetAttribute("Cooldown", def.cooldown)
	tool:SetAttribute("Range", def.range)
	if def.category == "gun" then
		tool:SetAttribute("Ammo", def.maxAmmo)
		tool:SetAttribute("MaxAmmo", def.maxAmmo)
		tool:SetAttribute("ReloadTime", def.reloadTime)
		tool:SetAttribute("Pellets", def.pellets or 1)
		tool:SetAttribute("Spread", def.spread or 0)
		tool:SetAttribute("Reloading", false)
	elseif def.category == "throw" then
		tool:SetAttribute("Charges", def.charges)
		tool:SetAttribute("MaxCharges", def.maxCharges)
	end
	CollectionService:AddTag(tool, Tags.Weapon)

	local state: ToolState = {
		kind = kind,
		ownerUserId = owner.UserId,
		lastUse = 0,
		reloading = false,
		reloadToken = 0,
		connections = {},
	}
	registry[tool] = state
	table.insert(
		state.connections,
		tool.Destroying:Connect(function()
			unregister(tool)
		end)
	)
	return tool
end

-- Cria o modelo de exibição (ancorado, sem colisão e invisível para raycasts), centralizado em `target`.
-- Devolve o Model e a part principal (onde ficam a luz e o prompt).
function ToolFactory.BuildDisplay(kind: string, target: CFrame): (Model?, BasePart?)
	local blueprint = BLUEPRINTS[kind]
	if not blueprint or not Definitions.Get(kind) then
		return nil, nil
	end
	local model = Instance.new("Model")
	model.Name = "Arma_" .. kind
	local root = makePart(blueprint.handle, true)
	root.Name = "Empunhadura"
	root.CFrame = CFrame.new()
	root.Parent = model
	for _, partSpec in blueprint.parts do
		local part = makePart(partSpec, true)
		part.CFrame = partSpec.cframe
		part.Parent = model
	end
	model.WorldPivot = CFrame.new(blueprint.displayCenter)
	model:PivotTo(target * blueprint.displayTilt)
	return model, root
end

return ToolFactory
