--!nonstrict
-- Helpers para construir geometria por código.
--   PartBuilder.part({ Name = "Parede", Size = ..., CFrame = ..., Color = ..., Material = ..., Parent = model,
--                      Tags = { Tags.Destructible }, Attributes = { Room = "Biblioteca" } })

local CollectionService = game:GetService("CollectionService")

local PartBuilder = {}

local SPECIAL_KEYS = {
	ClassName = true,
	Parent = true,
	Tags = true,
	Attributes = true,
}

-- Cria uma part (padrão: ancorada, superfícies lisas). Qualquer propriedade de BasePart pode ser passada.
function PartBuilder.part(props: { [string]: any }): BasePart
	local part = Instance.new(props.ClassName or "Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if not SPECIAL_KEYS[key] then
			part[key] = value
		end
	end
	if props.Tags then
		for _, tag in props.Tags do
			CollectionService:AddTag(part, tag)
		end
	end
	if props.Attributes then
		for name, value in props.Attributes do
			part:SetAttribute(name, value)
		end
	end
	if props.Parent then
		part.Parent = props.Parent
	end
	return part
end

-- Atalho para WedgePart.
function PartBuilder.wedge(props: { [string]: any }): WedgePart
	props.ClassName = "WedgePart"
	return PartBuilder.part(props) :: WedgePart
end

-- Cria um Model (ou Folder) com nome e pai.
function PartBuilder.model(name: string, parent: Instance?, className: string?): Instance
	local model = Instance.new(className or "Model")
	model.Name = name
	if parent then
		model.Parent = parent
	end
	return model
end

-- Solda a em b com WeldConstraint (mantém a posição relativa atual).
function PartBuilder.weld(a: BasePart, b: BasePart): WeldConstraint
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = a
	weld.Part1 = b
	weld.Parent = a
	return weld
end

-- Adiciona várias tags a uma instância.
function PartBuilder.tag(instance: Instance, ...: string)
	for _, tag in { ... } do
		CollectionService:AddTag(instance, tag)
	end
end

-- Retorna uma função que cede (task.wait) a cada `every` chamadas.
-- Use em loops de construção grandes para não travar o servidor.
function PartBuilder.yielder(every: number?): () -> ()
	local count = 0
	local limit = every or 200
	return function()
		count += 1
		if count % limit == 0 then
			task.wait()
		end
	end
end

-- Parede horizontal entre dois pontos (no plano XZ), com altura e espessura.
-- `bottomY` é a altura da base. Retorna a part.
function PartBuilder.wallBetween(
	a: Vector3,
	b: Vector3,
	bottomY: number,
	height: number,
	thickness: number,
	props: { [string]: any }?
): BasePart
	local flatA = Vector3.new(a.X, 0, a.Z)
	local flatB = Vector3.new(b.X, 0, b.Z)
	local length = (flatB - flatA).Magnitude
	local mid = (flatA + flatB) / 2
	local cf = CFrame.lookAt(
		Vector3.new(mid.X, bottomY + height / 2, mid.Z),
		Vector3.new(flatB.X, bottomY + height / 2, flatB.Z)
	)
	local merged = table.clone(props or {})
	merged.Size = Vector3.new(thickness, height, length)
	merged.CFrame = cf
	return PartBuilder.part(merged)
end

return PartBuilder
