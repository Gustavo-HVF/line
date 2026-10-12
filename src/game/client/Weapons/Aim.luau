--!nonstrict
-- Mira do cliente: ponto da tela (mouse ou centro), raio da câmera e raycasts locais com as mesmas regras
-- do servidor (atravessa personagens, pedaços, o tabuleiro e partes invisíveis ou sem colisão; para em
-- inimigos e objetos soltos). Serve para desenhar o traço na hora e para escolher a direção do tiro.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Tags = require(ReplicatedStorage.Shared.Tags)

local Aim = {}

local LocalPlayer = Players.LocalPlayer

local MAX_PIERCE = 4
local IGNORED_FOLDERS = { "Debris", "Board", "EfeitosLocais", "EfeitosArmas" }

local lastInputType: Enum.UserInputType = UserInputService:GetLastInputType()
UserInputService.LastInputTypeChanged:Connect(function(inputType)
	lastInputType = inputType
end)

-- Entrada ---------------------------------------------------------------------------------------

function Aim.IsTouch(): boolean
	return lastInputType == Enum.UserInputType.Touch
		or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
end

function Aim.IsGamepad(): boolean
	return string.find(lastInputType.Name, "Gamepad", 1, true) ~= nil
end

-- true quando a mira fica no centro da tela: toque, controle ou mouse travado (primeira pessoa / shift lock).
function Aim.UsesCenter(): boolean
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		return true
	end
	return Aim.IsTouch() or Aim.IsGamepad() or not UserInputService.MouseEnabled
end

-- Ponto mirado em coordenadas do viewport (as mesmas de GetMouseLocation e de uma ScreenGui com
-- IgnoreGuiInset = true).
function Aim.GetScreenPoint(): Vector2
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	if Aim.UsesCenter() then
		return viewport / 2
	end
	return UserInputService:GetMouseLocation()
end

-- Raycast ----------------------------------------------------------------------------------------

local function isEnemyPart(instance: Instance?): boolean
	local current = instance
	while current and current ~= workspace do
		if CollectionService:HasTag(current, Tags.Enemy) then
			return true
		end
		current = current.Parent
	end
	return false
end
Aim.IsEnemyPart = isEnemyPart

local function isLooseProp(part: BasePart): boolean
	if CollectionService:HasTag(part, Tags.LooseProp) then
		return true
	end
	local root = part.AssemblyRootPart
	return root ~= nil and root ~= part and CollectionService:HasTag(root, Tags.LooseProp)
end

local function shouldPierce(part: BasePart): boolean
	if part:IsA("Terrain") then
		return false
	end
	if part.CanCollide and part.Transparency < 0.9 then
		return false
	end
	return not isEnemyPart(part) and not isLooseProp(part)
end

-- Parâmetros novos a cada mira (a lista muda quando alguém entra, morre ou renasce).
function Aim.NewParams(): RaycastParams
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	for _, name in IGNORED_FOLDERS do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(list, folder)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = list
	params.IgnoreWater = true
	return params
end

-- Raycast que atravessa parts "vazadas". Retorna o resultado (ou nil) e o ponto final.
function Aim.Cast(
	origin: Vector3,
	direction: Vector3,
	distance: number,
	params: RaycastParams?
): (RaycastResult?, Vector3)
	local rayParams = params or Aim.NewParams()
	local start = origin
	local remaining = distance
	for _ = 0, MAX_PIERCE do
		local result = workspace:Raycast(start, direction * remaining, rayParams)
		if not result then
			break
		end
		if not shouldPierce(result.Instance) then
			return result, result.Position
		end
		rayParams:AddToFilter(result.Instance)
		remaining -= (result.Position - start).Magnitude
		start = result.Position
		if remaining <= 0.05 then
			return nil, start
		end
	end
	return nil, start + direction * remaining
end

-- Mira -----------------------------------------------------------------------------------------------

-- Ponto do mundo sob a mira. `range` é contado a partir do personagem (não da câmera).
-- Retorna o ponto, a direção do raio da câmera e o resultado do raycast (ou nil).
function Aim.GetAimPoint(range: number, params: RaycastParams?): (Vector3, Vector3, RaycastResult?)
	local camera = workspace.CurrentCamera
	local screen = Aim.GetScreenPoint()
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local direction = ray.Direction.Unit
	local origin = ray.Origin

	-- Começa o raio na altura do personagem: o que está entre a câmera e ele não conta.
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local skip = 0
	if root and root:IsA("BasePart") then
		skip = math.max((root.Position - origin):Dot(direction) - 1, 0)
	end
	local result, point = Aim.Cast(origin + direction * skip, direction, range, params)
	return point, direction, result
end

-- Direção aleatória dentro de um cone (só para o desenho local; o servidor sorteia a dele).
function Aim.SpreadDirection(direction: Vector3, degrees: number, random: Random): Vector3
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

return Aim
