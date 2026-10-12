--!nonstrict
-- Cliente das armas.
--   * Detecta a arma na mão: Tool com a tag Weapon dentro do personagem (Character.ChildAdded e
--     CollectionService, para o caso de a tag chegar depois).
--   * Clique/toque (Tool.Activated):
--       - armas de fogo: mira pelo Camera:ViewportPointToRay da posição do mouse (no toque/controle, do
--         centro da tela), origem na boca do cano; traço, clarão e som na hora; envia Weapon_Fire;
--       - facão: animação de Grip (estilo espada clássica) + Weapon_Melee;
--       - dinamite: Weapon_Throw com o ponto mirado (limitado ao alcance) e um marcador no chão.
--   * Recarregar: R (ContextActionService, com botão "Recarregar" no celular).
--   * Interface: mira, munição/cargas e "Recarregando..." (ver Weapons/WeaponUI).
-- O servidor valida tudo; aqui só há previsão local (munição e cadência) para a resposta ser imediata.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local Tags = require(ReplicatedStorage.Shared.Tags)

local WeaponsFolder = script.Parent.Weapons
local Aim = require(WeaponsFolder.Aim)
local PickupFx = require(WeaponsFolder.PickupFx)
local WeaponFx = require(WeaponsFolder.WeaponFx)
local WeaponUI = require(WeaponsFolder.WeaponUI)

local LocalPlayer = Players.LocalPlayer

local RELOAD_ACTION = "SelvaRecarregar"
local RESYNC_TIME = 0.6 -- depois disto sem atirar, a contagem local volta a seguir o servidor
local TURN_MIN_ANGLE = math.rad(25) -- vira o corpo para a mira se ela estiver mais longe que isto
local MAX_LOCAL_IMPACTS = 3 -- faíscas de impacto desenhadas por tiro (espingarda tem 8 projéteis)
local MARKER_REFRESH = 1 / 20

-- Os remotes das armas são criados pelo servidor só depois de o mapa ficar pronto; até lá as ações são
-- ignoradas (o personagem também só nasce depois disso).
local REMOTE_KEYS = {
	fire = Net.Names.Weapon_Fire,
	melee = Net.Names.Weapon_Melee,
	throw = Net.Names.Weapon_Throw,
	reload = Net.Names.Weapon_Reload,
}
local remotes: { [string]: RemoteEvent } = {}
local remotesReady = false

type Equipped = {
	tool: Tool,
	category: string,
	connections: { RBXScriptConnection },
	nextUse: number,
	localCount: number, -- munição/cargas previstas logo após um uso local
	lastLocalUse: number,
	localReloadUntil: number,
	lastServerCount: number,
}

local equipped: Equipped? = nil
local characterConnections: { RBXScriptConnection } = {}
local random = Random.new()
local mouseIconHidden = false
local reloadBound = false
local markerConnection: RBXScriptConnection? = nil
local lastMarkerUpdate = 0

-- Leitura dos atributos -------------------------------------------------------------------------------

local function numberAttr(tool: Tool, name: string, default: number): number
	local value = tool:GetAttribute(name)
	if type(value) == "number" and value == value then
		return value
	end
	return default
end

local function countAttribute(state: Equipped): string
	return if state.category == "throw" then "Charges" else "Ammo"
end

local function serverCount(state: Equipped): number
	return numberAttr(state.tool, countAttribute(state), 0)
end

-- Contagem mostrada: logo depois de usar, a previsão local (mais rápida que o servidor).
local function displayCount(state: Equipped): number
	local server = serverCount(state)
	if os.clock() - state.lastLocalUse < RESYNC_TIME then
		return math.max(math.min(state.localCount, server), 0)
	end
	return server
end

local function isReloading(state: Equipped): boolean
	return state.tool:GetAttribute("Reloading") == true or os.clock() < state.localReloadUntil
end

local function getHandle(tool: Tool): BasePart?
	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return handle
	end
	return nil
end

local function getAlive(): (Model?, Humanoid?, BasePart?)
	if LocalPlayer:GetAttribute("Eliminated") then
		return nil, nil, nil
	end
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

-- Interface -----------------------------------------------------------------------------------------------

local function refreshUI()
	local state = equipped
	if not state then
		return
	end
	local tool = state.tool
	if state.category == "gun" then
		local maxAmmo = numberAttr(tool, "MaxAmmo", 0)
		local ammo = displayCount(state)
		WeaponUI.SetCount(("%d / %d"):format(ammo, maxAmmo), ammo <= 0)
		local reloading = isReloading(state)
		WeaponUI.SetReloading(reloading, numberAttr(tool, "ReloadTime", 1.5))
		if reloading then
			WeaponUI.SetHint(nil)
		elseif Aim.IsTouch() then
			WeaponUI.SetHint("Toque em Recarregar")
		else
			WeaponUI.SetHint("[R] Recarregar")
		end
	elseif state.category == "throw" then
		local charges = displayCount(state)
		WeaponUI.SetCount(if charges == 1 then "1 carga" else ("%d cargas"):format(charges), charges <= 0)
		WeaponUI.SetHint("Mire e clique para arremessar")
	else
		WeaponUI.SetCount("Corpo a corpo", false)
		WeaponUI.SetHint(nil)
	end
end

-- Mira na posição do mouse (escondendo o cursor) ou no centro da tela.
local function updateCrosshairPosition()
	local state = equipped
	local wantsCrosshair = state ~= nil and state.category ~= "melee"
	local followMouse = wantsCrosshair and not Aim.UsesCenter()
	if followMouse then
		WeaponUI.SetCrosshairPosition(UserInputService:GetMouseLocation())
	else
		WeaponUI.SetCrosshairPosition(nil)
	end
	if followMouse ~= mouseIconHidden then
		mouseIconHidden = followMouse
		UserInputService.MouseIconEnabled = not followMouse
	end
end

-- Corpo virado para a mira (só visual: o tiro vai para onde se mira de qualquer jeito).
-- Retorna a transformação aplicada (para corrigir pontos medidos antes de virar).
local function faceDirection(direction: Vector3): CFrame?
	local _, humanoid, root = getAlive()
	if not humanoid or not root or not humanoid.AutoRotate or humanoid.Sit or humanoid.PlatformStand then
		return nil
	end
	local stateType = humanoid:GetState()
	if stateType == Enum.HumanoidStateType.Climbing or stateType == Enum.HumanoidStateType.Swimming then
		return nil
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.2 then
		return nil
	end
	flat = flat.Unit
	local current = root.CFrame
	local look = Vector3.new(current.LookVector.X, 0, current.LookVector.Z)
	if look.Magnitude > 1e-3 and look.Unit:Dot(flat) >= math.cos(TURN_MIN_ANGLE) then
		return nil
	end
	local turned = CFrame.lookAt(current.Position, current.Position + flat)
	root.CFrame = turned
	return turned * current:Inverse()
end

-- Ações -------------------------------------------------------------------------------------------------

local function requestReload(auto: boolean?)
	local state = equipped
	if not remotesReady or not state or state.category ~= "gun" or not getAlive() then
		return
	end
	local tool = state.tool
	if isReloading(state) or serverCount(state) >= numberAttr(tool, "MaxAmmo", 0) then
		return
	end
	state.localReloadUntil = os.clock() + numberAttr(tool, "ReloadTime", 1.5)
	if not auto then
		local handle = getHandle(tool)
		SoundUtil.Play("Reload", { Parent = handle, Volume = 0.6 })
	end
	remotes.reload:FireServer(tool)
	refreshUI()
end

local function fireGun(state: Equipped)
	local tool = state.tool
	if isReloading(state) then
		return
	end
	if displayCount(state) <= 0 then
		requestReload()
		return
	end
	local handle = getHandle(tool)
	local muzzle = WeaponFx.GetMuzzle(tool)
	if not handle or not muzzle then
		return
	end

	local now = os.clock()
	state.nextUse = now + numberAttr(tool, "Cooldown", 0.35)
	state.localCount = displayCount(state) - 1
	state.lastLocalUse = now

	-- Direção: da boca do cano até o ponto sob a mira (ou a direção da câmera se o ponto ficar para trás).
	local range = numberAttr(tool, "Range", 300)
	local params = Aim.NewParams()
	local aimPoint, cameraDirection = Aim.GetAimPoint(range, params)
	local direction = aimPoint - muzzle
	if direction.Magnitude < 1 or direction.Unit:Dot(cameraDirection) < 0.2 then
		direction = cameraDirection
	end
	direction = direction.Unit
	local turn = faceDirection(direction)
	local origin = if turn then turn * muzzle else muzzle

	-- Desenho local imediato (o servidor sorteia o espalhamento dele; aqui é só o visual).
	local pellets = math.max(math.floor(numberAttr(tool, "Pellets", 1)), 1)
	local spread = numberAttr(tool, "Spread", 0)
	local color = tool:GetAttribute("TracerColor")
	local width = numberAttr(tool, "TracerWidth", 0.1)
	local hitEnemy = false
	local impacts = 0
	for _ = 1, pellets do
		local pelletDirection = Aim.SpreadDirection(direction, spread, random)
		local result, endPoint = Aim.Cast(origin, pelletDirection, range, params)
		WeaponFx.Tracer(origin, endPoint, if typeof(color) == "Color3" then color else nil, width)
		if result then
			if Aim.IsEnemyPart(result.Instance) then
				hitEnemy = true
			end
			if impacts < MAX_LOCAL_IMPACTS then
				impacts += 1
				WeaponFx.Impact(endPoint)
			end
		end
	end
	WeaponFx.MuzzleFlash(origin)
	WeaponFx.PlayGrip(tool, "recoil", numberAttr(tool, "Recoil", 10) / 10)
	local sound = tool:GetAttribute("UseSound")
	if type(sound) == "string" then
		SoundUtil.Play(sound, { Parent = handle, Volume = 0.8 })
	end
	if hitEnemy then
		WeaponUI.Hitmarker()
	end

	remotes.fire:FireServer(tool, origin, direction)
	refreshUI()
	task.delay(RESYNC_TIME + 0.05, refreshUI)
end

local function swingMachete(state: Equipped)
	local tool = state.tool
	state.nextUse = os.clock() + numberAttr(tool, "Cooldown", 0.55)
	WeaponFx.PlayToolAnim(tool, "Slash")
	WeaponFx.PlayGrip(tool, "swing")
	local sound = tool:GetAttribute("UseSound")
	if type(sound) == "string" then
		SoundUtil.Play(sound, { Parent = getHandle(tool), Volume = 0.6 })
	end
	remotes.melee:FireServer(tool)
end

-- Alvo do arremesso: ponto sob a mira, limitado ao alcance (o servidor recusa além dele).
local function throwTarget(tool: Tool, root: BasePart): (Vector3, boolean)
	local range = numberAttr(tool, "Range", 60)
	local point, _, result = Aim.GetAimPoint(range + 20)
	local offset = point - root.Position
	local limit = math.max(range - 1, 1)
	if offset.Magnitude > limit then
		return root.Position + offset.Unit * limit, false
	end
	return point, result ~= nil
end

local function throwDynamite(state: Equipped)
	local tool = state.tool
	local _, _, root = getAlive()
	if not root or displayCount(state) <= 0 then
		return
	end
	local now = os.clock()
	state.nextUse = now + numberAttr(tool, "Cooldown", 0.9)
	state.localCount = displayCount(state) - 1
	state.lastLocalUse = now

	local target = throwTarget(tool, root)
	faceDirection(target - root.Position)
	WeaponFx.PlayToolAnim(tool, "Slash")
	WeaponFx.PlayGrip(tool, "throw")
	local sound = tool:GetAttribute("UseSound")
	if type(sound) == "string" then
		SoundUtil.Play(sound, { Parent = getHandle(tool), Volume = 0.5, PlaybackSpeed = 0.8 })
	end
	remotes.throw:FireServer(tool, target)
	refreshUI()
	task.delay(RESYNC_TIME + 0.05, refreshUI)
end

local function onActivated()
	local state = equipped
	if not remotesReady or not state or not getAlive() then
		return
	end
	if os.clock() < state.nextUse then
		return
	end
	if state.category == "gun" then
		fireGun(state)
	elseif state.category == "melee" then
		swingMachete(state)
	elseif state.category == "throw" then
		throwDynamite(state)
	end
end

-- Marcador da dinamite ------------------------------------------------------------------------------------

local function updateMarker()
	local now = os.clock()
	if now - lastMarkerUpdate < MARKER_REFRESH then
		return
	end
	lastMarkerUpdate = now
	local state = equipped
	local _, _, root = getAlive()
	if not state or state.category ~= "throw" or not root then
		WeaponFx.SetMarker(nil)
		return
	end
	local target, onSurface = throwTarget(state.tool, root)
	if not onSurface then
		-- Alvo no ar (limitado pelo alcance): mostra onde a dinamite deve cair.
		local result = Aim.Cast(target, Vector3.new(0, -1, 0), 40)
		if not result then
			WeaponFx.SetMarker(nil)
			return
		end
		target = result.Position
	end
	WeaponFx.SetMarker(target, numberAttr(state.tool, "BlastRadius", 14))
end

local function setMarkerActive(active: boolean)
	if active and not markerConnection then
		markerConnection = RunService.Heartbeat:Connect(updateMarker)
	elseif not active then
		if markerConnection then
			markerConnection:Disconnect()
			markerConnection = nil
		end
		WeaponFx.SetMarker(nil)
	end
end

-- Recarga (tecla R / botão) --------------------------------------------------------------------------------

local function onReloadAction(_actionName: string, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		requestReload()
	end
	return Enum.ContextActionResult.Sink
end

local function setReloadBound(shouldBind: boolean)
	if shouldBind == reloadBound then
		return
	end
	reloadBound = shouldBind
	if shouldBind then
		ContextActionService:BindAction(RELOAD_ACTION, onReloadAction, true, Enum.KeyCode.R, Enum.KeyCode.ButtonL2)
		ContextActionService:SetTitle(RELOAD_ACTION, "Recarregar")
	else
		ContextActionService:UnbindAction(RELOAD_ACTION)
	end
end

-- Equipar / guardar -----------------------------------------------------------------------------------------

local unequip: () -> ()

local function onCountChanged(state: Equipped)
	local server = serverCount(state)
	if server > state.lastServerCount then
		-- Recarregou ou pegou mais: a previsão local é descartada.
		state.localCount = server
		state.localReloadUntil = 0
	end
	state.lastServerCount = server
	refreshUI()
end

local function onReloadingChanged(state: Equipped)
	local reloading = state.tool:GetAttribute("Reloading") == true
	if reloading then
		if os.clock() >= state.localReloadUntil then
			-- Recarga iniciada pelo servidor (munição acabou): o som toca aqui.
			state.localReloadUntil = os.clock() + numberAttr(state.tool, "ReloadTime", 1.5)
			SoundUtil.Play("Reload", { Parent = getHandle(state.tool), Volume = 0.6 })
		end
	else
		state.localReloadUntil = 0
	end
	refreshUI()
end

local function equip(tool: Tool)
	if equipped and equipped.tool == tool then
		return
	end
	if equipped then
		unequip()
	end
	local category = tool:GetAttribute("Category")
	if category ~= "gun" and category ~= "melee" and category ~= "throw" then
		return
	end

	local state: Equipped = {
		tool = tool,
		category = category,
		connections = {},
		nextUse = 0,
		localCount = 0,
		lastLocalUse = -math.huge,
		localReloadUntil = 0,
		lastServerCount = 0,
	}
	state.lastServerCount = serverCount(state)
	state.localCount = state.lastServerCount
	equipped = state

	table.insert(state.connections, tool.Activated:Connect(onActivated))
	table.insert(
		state.connections,
		tool:GetAttributeChangedSignal(countAttribute(state)):Connect(function()
			onCountChanged(state)
		end)
	)
	if category == "gun" then
		table.insert(
			state.connections,
			tool:GetAttributeChangedSignal("Reloading"):Connect(function()
				onReloadingChanged(state)
			end)
		)
		table.insert(state.connections, tool:GetAttributeChangedSignal("MaxAmmo"):Connect(refreshUI))
	end

	local displayName = tool:GetAttribute("DisplayName")
	WeaponUI.ShowWeapon(if type(displayName) == "string" then displayName else tool.Name)
	WeaponUI.SetCrosshairVisible(category ~= "melee", if numberAttr(tool, "Spread", 0) > 0 then 14 else 6)
	updateCrosshairPosition()
	setReloadBound(category == "gun")
	setMarkerActive(category == "throw")
	refreshUI()
	SoundUtil.Play("Equip", { Parent = getHandle(tool), Volume = 0.5 })

	-- Arma de fogo sem bala ao equipar: já pede a recarga.
	if category == "gun" and serverCount(state) <= 0 and tool:GetAttribute("Reloading") ~= true then
		requestReload(false)
	end
end

function unequip()
	local state = equipped
	equipped = nil
	if state then
		for _, connection in state.connections do
			connection:Disconnect()
		end
		table.clear(state.connections)
		WeaponFx.ResetGrip(state.tool)
	end
	setReloadBound(false)
	setMarkerActive(false)
	WeaponUI.HideWeapon()
	updateCrosshairPosition()
end

local function isWeaponTool(instance: Instance): boolean
	return instance:IsA("Tool") and CollectionService:HasTag(instance, Tags.Weapon)
end

local function onCharacterAdded(character: Model)
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	unequip()

	table.insert(
		characterConnections,
		character.ChildAdded:Connect(function(child)
			if isWeaponTool(child) then
				equip(child :: Tool)
			end
		end)
	)
	table.insert(
		characterConnections,
		character.ChildRemoved:Connect(function(child)
			if equipped and equipped.tool == child then
				unequip()
			end
		end)
	)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") and LocalPlayer.Character == character then
		table.insert(characterConnections, humanoid.Died:Connect(unequip))
	end
	for _, child in character:GetChildren() do
		if isWeaponTool(child) then
			equip(child :: Tool)
		end
	end
end

-- Início ------------------------------------------------------------------------------------------------------

-- Espera os remotes em silêncio (sem o aviso do Net nem "Infinite yield") e só então os pega pelo Net.
task.spawn(function()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	while not folder do
		folder = ReplicatedStorage:WaitForChild("Remotes", 30)
	end
	for key, name in REMOTE_KEYS do
		while not folder:FindFirstChild(name) do
			folder:WaitForChild(name, 30)
		end
		remotes[key] = Net.event(name)
	end
	remotesReady = true
end)

WeaponUI.Init()
WeaponFx.Init()
PickupFx.Init()

-- A tag pode chegar depois da Tool (replicação): confere se ela já está na mão.
CollectionService:GetInstanceAddedSignal(Tags.Weapon):Connect(function(instance)
	local character = LocalPlayer.Character
	if character and instance.Parent == character and isWeaponTool(instance) then
		equip(instance :: Tool)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if equipped and input.UserInputType == Enum.UserInputType.MouseMovement then
		updateCrosshairPosition()
	end
end)
UserInputService.LastInputTypeChanged:Connect(function()
	if equipped then
		updateCrosshairPosition()
		refreshUI()
	end
end)
UserInputService:GetPropertyChangedSignal("MouseBehavior"):Connect(function()
	if equipped then
		updateCrosshairPosition()
	end
end)

LocalPlayer:GetAttributeChangedSignal("Eliminated"):Connect(function()
	if LocalPlayer:GetAttribute("Eliminated") then
		unequip()
	end
end)
LocalPlayer.CharacterRemoving:Connect(function()
	unequip()
end)
LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
if LocalPlayer.Character then
	task.spawn(onCharacterAdded, LocalPlayer.Character)
end
