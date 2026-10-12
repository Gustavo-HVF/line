--!nonstrict
-- Animação local das luzes do lobby (somente cliente, nada é replicado):
--   * atributo "Flicker" (amplitude): velas e tochas tremulam com ruído;
--   * atributo "Pulse" (amplitude): o vidro verde do tabuleiro pulsa devagar.
-- O brilho original vem do atributo "BaseBrightness" (colocado pelo LobbyWorld).
-- Só atualiza luzes perto da câmera, cerca de 20 vezes por segundo.

local RunService = game:GetService("RunService")

local LobbyAmbience = {}

local UPDATE_INTERVAL = 1 / 20
local MAX_DISTANCE = 140

type Tracked = { base: number, flicker: number, pulse: number, seed: number, part: BasePart }

local tracked: { [Light]: Tracked } = {}
local started = false

local function track(instance: Instance)
	if not instance:IsA("Light") then
		return
	end
	local flicker = instance:GetAttribute("Flicker")
	local pulse = instance:GetAttribute("Pulse")
	if type(flicker) ~= "number" and type(pulse) ~= "number" then
		return
	end
	local part = instance.Parent
	if not part or not part:IsA("BasePart") then
		return
	end
	local base = instance:GetAttribute("BaseBrightness")
	tracked[instance] = {
		base = type(base) == "number" and base or instance.Brightness,
		flicker = type(flicker) == "number" and flicker or 0,
		pulse = type(pulse) == "number" and pulse or 0,
		seed = math.random() * 1000,
		part = part,
	}
end

local function untrack(instance: Instance)
	if instance:IsA("Light") then
		tracked[instance] = nil
	end
end

local function step()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPosition = camera.CFrame.Position
	local now = os.clock()
	for light, info in tracked do
		if (info.part.Position - cameraPosition).Magnitude <= MAX_DISTANCE then
			local factor = 1
			if info.flicker > 0 then
				local noise = math.noise(now * 7, info.seed) + 0.5 * math.noise(now * 17, info.seed + 50)
				factor += noise * info.flicker
			end
			if info.pulse > 0 then
				factor += math.sin(now * 1.6 + info.seed) * info.pulse
			end
			light.Brightness = math.max(0, info.base * factor)
		end
	end
end

-- Idempotente. Espera o cenário (workspace.LobbyWorld) aparecer e começa a animar.
function LobbyAmbience.Start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local world = workspace:WaitForChild("LobbyWorld", 120)
		if not world then
			return
		end
		for _, descendant in world:GetDescendants() do
			track(descendant)
		end
		world.DescendantAdded:Connect(track)
		world.DescendantRemoving:Connect(untrack)
		local elapsed = 0
		RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed < UPDATE_INTERVAL then
				return
			end
			elapsed = 0
			step()
		end)
	end)
end

return LobbyAmbience
