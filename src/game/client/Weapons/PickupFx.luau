--!nonstrict
-- Armas no chão giram e flutuam devagar (só no cliente, só as mais próximas da câmera).
-- O servidor cria os modelos ancorados em workspace.Map.ArmasNoChao; aqui eles são movidos localmente
-- (nada replica). Para não pesar no celular: no máximo MAX_ANIMATED modelos e a lista de próximos é
-- refeita só a cada REFRESH_INTERVAL segundos.

local RunService = game:GetService("RunService")

local PickupFx = {}

local FOLDER_NAME = "ArmasNoChao"
local MAX_ANIMATED = 8
local MAX_DISTANCE = 45
local REFRESH_INTERVAL = 0.5
local SPIN_SPEED = 1.2 -- rad/s
local BOB_HEIGHT = 0.18
local BOB_SPEED = 2.2

type Item = { model: Model, base: CFrame?, phase: number }

local initialized = false
local items: { [Model]: Item } = {}
local nearby: { Item } = {}
local lastRefresh = 0
local connections: { RBXScriptConnection } = {}
local stepConnection: RBXScriptConnection? = nil
local random = Random.new()

local function track(child: Instance)
	if not child:IsA("Model") or items[child] then
		return
	end
	-- O pivô original é lido na primeira atualização (as parts podem ainda estar chegando agora).
	items[child] = { model = child, base = nil, phase = random:NextNumber(0, math.pi * 2) }
end

local function untrack(child: Instance)
	if child:IsA("Model") then
		items[child] = nil
	end
end

local function refreshNearby(cameraPosition: Vector3)
	table.clear(nearby)
	local candidates = {}
	for model, item in items do
		if model.Parent then
			if not item.base and model.PrimaryPart then
				item.base = model:GetPivot()
			end
			local base = item.base or model:GetPivot()
			local distance = (base.Position - cameraPosition).Magnitude
			if distance <= MAX_DISTANCE then
				table.insert(candidates, { item = item, distance = distance })
			end
		else
			items[model] = nil
		end
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)
	for index = 1, math.min(#candidates, MAX_ANIMATED) do
		table.insert(nearby, candidates[index].item)
	end
end

local function step()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	if now - lastRefresh >= REFRESH_INTERVAL then
		lastRefresh = now
		refreshNearby(camera.CFrame.Position)
	end
	for _, item in nearby do
		local model = item.model
		local base = item.base
		if model.Parent and base then
			local bob = math.sin(now * BOB_SPEED + item.phase) * BOB_HEIGHT
			local spin = CFrame.Angles(0, now * SPIN_SPEED + item.phase, 0)
			model:PivotTo(CFrame.new(base.Position + Vector3.new(0, bob, 0)) * spin * base.Rotation)
		end
	end
end

local function attach(folder: Instance)
	for _, child in folder:GetChildren() do
		track(child)
	end
	table.insert(connections, folder.ChildAdded:Connect(track))
	table.insert(connections, folder.ChildRemoved:Connect(untrack))
	if not stepConnection then
		stepConnection = RunService.Heartbeat:Connect(step)
	end
end

function PickupFx.Init()
	if initialized then
		return
	end
	initialized = true
	task.spawn(function()
		-- O mapa (e só depois as armas) pode demorar a ficar pronto: espera sem desistir.
		local map = workspace:FindFirstChild("Map")
		while not map do
			map = workspace:WaitForChild("Map", 30)
		end
		local folder = map:FindFirstChild(FOLDER_NAME)
		while not folder and map.Parent do
			folder = map:WaitForChild(FOLDER_NAME, 30)
		end
		if folder then
			attach(folder)
		end
	end)
end

return PickupFx
