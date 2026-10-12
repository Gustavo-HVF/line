--!nonstrict
-- "Boneco" do jogador nas cenas do lobby (só no cliente dele): uma cópia do próprio personagem R6 fica em pé
-- no sótão do menu (marcador LobbyMarkers.MenuCharacter) e na sala de demonstração dos gráficos
-- (LobbyMarkers.DemoCharacter), animada pelo R6Animator. Cada jogador vê apenas o próprio boneco; o
-- personagem de verdade continua no cubículo atrás da câmera enquanto o menu está aberto.
--
--   MenuPuppet.Start()   -- idempotente; refaz os bonecos quando o personagem muda (roupa, respawn)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local R6Animator = require(ReplicatedStorage.Shared.Character.R6Animator)

local MenuPuppet = {}

local MARKERS = { "MenuCharacter", "DemoCharacter" }
local APPEARANCE_WAIT = 1.2 -- acessórios e roupas chegam logo depois do modelo

local LocalPlayer = Players.LocalPlayer

local started = false
local puppets: { Model } = {}
local buildToken = 0

local function clearPuppets()
	for _, puppet in puppets do
		puppet:Destroy()
	end
	table.clear(puppets)
end

local function markerCFrame(name: string): CFrame?
	local markers = workspace:FindFirstChild("LobbyMarkers")
	if not markers then
		return nil
	end
	local part = markers:FindFirstChild(name)
	if part and part:IsA("BasePart") then
		return part.CFrame
	end
	local attribute = markers:GetAttribute(name .. "CFrame")
	return if typeof(attribute) == "CFrame" then attribute else nil
end

local function makeCopy(character: Model): Model?
	local wasArchivable = character.Archivable
	character.Archivable = true
	local ok, copy = pcall(function()
		return character:Clone()
	end)
	character.Archivable = wasArchivable
	if not ok or not copy then
		return nil
	end
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("Tool") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	local root = copy:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		copy:Destroy()
		return nil
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	humanoid.BreakJointsOnDeath = false
	root.Anchored = true
	copy.Name = "BonecoDoJogador"
	return copy
end

-- Altura da HumanoidRootPart acima da sola dos pés.
local function rootHeight(model: Model): number
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local leg = model:FindFirstChild("Left Leg") or model:FindFirstChild("Right Leg")
	if leg and leg:IsA("BasePart") then
		return root.Position.Y - (leg.Position.Y - leg.Size.Y / 2)
	end
	return 3
end

local function build(character: Model)
	buildToken += 1
	local token = buildToken
	clearPuppets()
	character:WaitForChild("Torso", 10)
	character:WaitForChild("HumanoidRootPart", 10)
	task.wait(APPEARANCE_WAIT)
	if token ~= buildToken or LocalPlayer.Character ~= character or not character.Parent then
		return
	end
	for _, markerName in MARKERS do
		local spot = markerCFrame(markerName)
		local deadline = os.clock() + 15
		while not spot and os.clock() < deadline do
			task.wait(0.5)
			spot = markerCFrame(markerName)
		end
		if token ~= buildToken then
			return
		end
		if spot then
			local copy = makeCopy(character)
			if copy then
				local height = rootHeight(copy)
				copy:PivotTo(CFrame.new(spot.Position + Vector3.new(0, height, 0)) * spot.Rotation)
				copy.Parent = workspace
				table.insert(puppets, copy)
				R6Animator.Register(copy, { pose = "menu" })
			end
		else
			warn(("[MenuPuppet] Marcador %s não encontrado; o boneco não vai aparecer."):format(markerName))
		end
	end
end

function MenuPuppet.Start()
	if started then
		return
	end
	started = true
	LocalPlayer.CharacterAdded:Connect(function(character)
		task.spawn(build, character)
	end)
	if LocalPlayer.Character then
		task.spawn(build, LocalPlayer.Character)
	end
end

return MenuPuppet
