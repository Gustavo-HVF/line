--!nonstrict
-- Serviço do tabuleiro (servidor): posição no mapa, carregar nas costas, jogar os dados com física,
-- andar com a peça única do grupo e avisar o resto do jogo pelo sinal BoardService.Rolled.
--
-- Regras de rolagem: a fase precisa permitir (SetRollingEnabled), o tabuleiro não pode estar travado
-- nem rolando, o cooldown precisa ter acabado e o jogador precisa estar vivo e ser o carregador
-- (ou ninguém carrega e ele está a até 12 studs).
-- Cada jogada DESLIGA a rolagem; o MatchService religa (junto com StartCooldown) quando o evento começa.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local PartBuilder = require(ReplicatedStorage.Shared.Util.PartBuilder)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local Tags = require(ReplicatedStorage.Shared.Tags)

local BoardModel = require(script.Parent.BoardModel)
local CombatUtil = require(script.Parent.CombatUtil)

local BoardService = {}

-- ({ dice: {number}, total: number, fromSpace: number, space: number, position: Vector3,
--    isFinal: boolean, isFirst: boolean })
BoardService.Rolled = Signal.new()

-- Ajustes --------------------------------------------------------------------------------

local ROLL_DISTANCE = 12 -- distância máxima para jogar sem carregar
local PICKUP_DISTANCE = 12 -- validação no servidor (o prompt usa PROMPT_DISTANCE)
local PROMPT_DISTANCE = 10
local REQUEST_DEBOUNCE = 0.4 -- intervalo mínimo entre pedidos do mesmo jogador
local NOTIFY_DEBOUNCE = 2 -- intervalo mínimo entre avisos de erro para o mesmo jogador
local SETTLE_SPEED = 0.5 -- dado "parado" abaixo desta velocidade linear
local SETTLE_ANGULAR = 1 -- ...e desta velocidade angular (rad/s)
local SETTLE_TIME = 0.4 -- tempo parado para considerar assentado
local SETTLE_TIMEOUT = 4 -- tempo máximo esperando os dados
local DICE_FAR_DISTANCE = 18 -- dado mais longe que isto do tabuleiro = valor aleatório
local DICE_LINGER = 3 -- segundos até os dados sumirem
local STEP_TIME = 0.25 -- duração de cada passo da peça
local STEP_HOP = 0.25 -- altura do pulinho da peça
local MONITOR_INTERVAL = 0.5
local SAFE_EDGE_MARGIN = 6 -- margem da borda da ilha para considerar uma posição segura
local CARRY_ROTATION = CFrame.Angles(math.rad(90), 0, 0) -- topo do tabuleiro virado para trás (costas)

-- Estado --------------------------------------------------------------------------------

local initialized = false
local mapInfo = nil
local remotes: { [string]: RemoteEvent } = {}
local board: BoardModel.Board = nil
local boardFolder: Folder = nil
local diceFolder: Folder = nil
local pickupPrompt: ProximityPrompt? = nil
local rollPrompt: ProximityPrompt? = nil

local carrier: Player? = nil
local carrierConnections: { RBXScriptConnection } = {}
local carryWelds: { Instance } = {}
local locked = false
local rollingEnabled = false
local rolling = false
local cooldownEndsAt: number? = nil
local cooldownToken = 0
local space = 0
local rollCount = 0
local lastSafeCFrame = CFrame.new()
local lastRiddle: string? = nil
local pieceTween: Tween? = nil
local lastRequest: { [Player]: number } = {}
local lastNotify: { [Player]: number } = {}
local random = Random.new()

-- Funções declaradas antes por dependerem umas das outras.
local broadcastStatus: () -> ()
local updatePrompts: () -> ()

-- Utilitários ---------------------------------------------------------------------------

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function notify(player: Player, text: string, kind: string?)
	local now = os.clock()
	local last = lastNotify[player]
	if last and now - last < NOTIFY_DEBOUNCE then
		return
	end
	lastNotify[player] = now
	remotes.notify:FireClient(player, text, kind or "info")
end

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureFolders()
	if not boardFolder or not boardFolder:IsDescendantOf(workspace) then
		boardFolder = getOrCreateFolder(workspace, "Board")
	end
	if not diceFolder or not diceFolder:IsDescendantOf(boardFolder) then
		diceFolder = getOrCreateFolder(boardFolder, "Dice")
	end
end

-- Raycast que ignora o próprio tabuleiro, personagens, NPCs, pedaços, eventos e volumes de região.
local function rayParams(): RaycastParams
	local exclude: { Instance } = { boardFolder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	for _, name in { "Debris", "ActiveEvents", "NPCs" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(exclude, folder)
		end
	end
	local map = workspace:FindFirstChild("Map")
	local regions = map and map:FindFirstChild("Regions")
	if regions then
		table.insert(exclude, regions)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	params.RespectCanCollide = true
	return params
end

local function findGround(position: Vector3, maxDrop: number, startAbove: number?): (Vector3?, BasePart?)
	local above = startAbove or 4
	local result =
		workspace:Raycast(position + Vector3.new(0, above, 0), Vector3.new(0, -(maxDrop + above), 0), rayParams())
	if result then
		return result.Position, result.Instance :: BasePart
	end
	return nil, nil
end

local function isWater(part: Instance?): boolean
	return part ~= nil and CollectionService:HasTag(part, Tags.Water)
end

local function isSafePosition(position: Vector3): boolean
	local center = mapInfo.islandCenter
	local flat = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
	return flat.Magnitude <= mapInfo.islandRadius - SAFE_EDGE_MARGIN and position.Y > mapInfo.waterLevelY + 0.5
end

local function flatLook(vector: Vector3?): Vector3
	if vector then
		local flat = Vector3.new(vector.X, 0, vector.Z)
		if flat.Magnitude > 1e-3 then
			return flat.Unit
		end
	end
	return Vector3.new(0, 0, -1)
end

-- CFrame "deitado" no chão, olhando na direção horizontal dada.
local function groundCFrame(position: Vector3, look: Vector3?): CFrame
	return CFrame.lookAt(position, position + flatLook(look))
end

-- Acha um lugar seguro no chão a partir de `position`; se não achar, devolve a última posição segura.
local function placementAt(position: Vector3, look: Vector3?, maxDrop: number?, startAbove: number?): CFrame
	local ground, hit = findGround(position, maxDrop or 40, startAbove)
	if ground and not isWater(hit) and isSafePosition(ground) then
		return groundCFrame(ground, look)
	end
	return lastSafeCFrame
end

local function cooldownRemaining(): number
	if not cooldownEndsAt then
		return 0
	end
	return math.max(cooldownEndsAt - workspace:GetServerTimeNow(), 0)
end

-- Contorno branco visível através das paredes: todo mundo sempre sabe onde o tabuleiro está.
local function addHighlight(model: Model)
	local highlight = Instance.new("Highlight")
	highlight.Name = "Destaque"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.OutlineTransparency = 0
	highlight.Adornee = model
	highlight.Parent = model
end

local function canRollNow(): boolean
	return rollingEnabled and not locked and not rolling and cooldownRemaining() <= 0
end

local function statusPayload()
	local remaining = cooldownRemaining()
	return {
		carrierUserId = carrier and carrier.UserId or nil,
		canRoll = canRollNow(),
		cooldownEndsAt = remaining > 0 and cooldownEndsAt or nil,
		space = space,
		locked = locked,
		rolling = rolling,
	}
end

function broadcastStatus()
	if remotes.status then
		remotes.status:FireAllClients(statusPayload())
	end
end

function updatePrompts()
	if pickupPrompt then
		pickupPrompt.Enabled = carrier == nil and not locked and not rolling
	end
	if rollPrompt then
		rollPrompt.Enabled = carrier == nil and canRollNow()
	end
end

-- Física: carregado (solto, sem colisão, sem massa) x no chão (ancorado, colisão original).
local function setCarriedPhysics(carried: boolean)
	for _, part in board.parts do
		if part.Parent then
			if carried then
				part.CanCollide = false
				part.CanQuery = false
				part.Anchored = false
			else
				part.Anchored = true
				local original = board.original[part]
				part.CanCollide = original.collide
				part.CanQuery = original.query
			end
		end
	end
end

local function clearCarrierConnections()
	for _, connection in carrierConnections do
		connection:Disconnect()
	end
	table.clear(carrierConnections)
end

-- Remove as soldas e ancora o tabuleiro onde ele estiver.
local function detach()
	clearCarrierConnections()
	for _, weld in carryWelds do
		weld:Destroy()
	end
	table.clear(carryWelds)
	carrier = nil
	if board and board.base.Parent then
		setCarriedPhysics(false)
	end
end

-- Coloca o tabuleiro (ancorado) no CFrame dado. O pivot é o centro do fundo da base.
local function placeBoard(cframe: CFrame)
	if carrier then
		detach()
	end
	if pieceTween then
		pieceTween:Cancel()
		pieceTween = nil
	end
	board.model:PivotTo(cframe)
	board.pieceRoot.CFrame = BoardModel.GetPieceCFrame(board, space)
	if isSafePosition(cframe.Position) then
		lastSafeCFrame = cframe
	end
	updatePrompts()
	broadcastStatus()
end

-- O carregador solta o tabuleiro onde está (morte, eliminação, saída, travamento).
local function dropFromCarrier()
	local player = carrier
	if not player then
		return
	end
	local root = getRoot(player)
	local position = root and root.Position or board.model:GetPivot().Position
	local look = root and root.CFrame.LookVector or nil
	placeBoard(placementAt(position, look, 60, 1))
end

-- Lugar no chão à frente do jogador (sem atravessar paredes).
local function frontPlacement(player: Player): CFrame
	local root = getRoot(player)
	if not root then
		return placementAt(board.model:GetPivot().Position, nil, 60, 1)
	end
	local look = flatLook(root.CFrame.LookVector)
	local distance = 3.6
	local wallHit = workspace:Raycast(root.Position, look * (distance + 2), rayParams())
	if wallHit then
		distance = math.clamp((wallHit.Position - root.Position).Magnitude - 1.9, 0.8, 3.6)
	end
	local ground, hit = findGround(root.Position + look * distance, 14, 1)
	local feetY = root.Position.Y - 3
	if ground and not isWater(hit) and isSafePosition(ground) and math.abs(ground.Y - feetY) < 6 then
		return groundCFrame(ground, look)
	end
	return placementAt(root.Position, look, 60, 1)
end

-- Solda o tabuleiro nas costas do jogador.
local function attach(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not humanoid or not torso or not torso:IsA("BasePart") then
		return false
	end

	if pieceTween then
		pieceTween:Cancel()
		pieceTween = nil
	end
	board.pieceRoot.CFrame = BoardModel.GetPieceCFrame(board, space)

	-- Posiciona ainda ancorado, solda tudo na base e a base no torso; só então solta a física.
	local pose = torso.CFrame * CFrame.new(0, 0.2, torso.Size.Z / 2 + 0.04) * CARRY_ROTATION
	board.model:PivotTo(pose)
	for _, part in board.parts do
		if part ~= board.base then
			table.insert(carryWelds, PartBuilder.weld(part, board.base))
		end
	end
	table.insert(carryWelds, PartBuilder.weld(board.base, torso))
	setCarriedPhysics(true)
	carrier = player

	local function dropIfStillCarrier()
		if carrier == player then
			dropFromCarrier()
		end
	end
	table.insert(carrierConnections, humanoid.Died:Connect(dropIfStillCarrier))
	table.insert(
		carrierConnections,
		player:GetAttributeChangedSignal("Eliminated"):Connect(function()
			if player:GetAttribute("Eliminated") then
				dropIfStillCarrier()
			end
		end)
	)
	table.insert(
		carrierConnections,
		character.AncestryChanged:Connect(function()
			if not character:IsDescendantOf(workspace) then
				dropIfStillCarrier()
			end
		end)
	)
	table.insert(
		carrierConnections,
		torso.AncestryChanged:Connect(function()
			if not torso:IsDescendantOf(workspace) then
				dropIfStillCarrier()
			end
		end)
	)

	updatePrompts()
	broadcastStatus()
	return true
end

local function tryPickup(player: Player)
	if not initialized or carrier or locked or rolling then
		return
	end
	if not CombatUtil.IsPlayerAlive(player) then
		return
	end
	local root = getRoot(player)
	if not root or (root.Position - board.base.Position).Magnitude > PICKUP_DISTANCE then
		return
	end
	if attach(player) then
		notify(player, "Você está carregando o tabuleiro! T (ou o botão) joga o dado, G solta.", "success")
	end
end

-- Toca uma tween e espera terminar (com limite, caso a part seja destruída).
local function playAndWait(tween: Tween, timeout: number)
	local done = false
	local connection = tween.Completed:Once(function()
		done = true
	end)
	tween:Play()
	local started = os.clock()
	while not done and os.clock() - started < timeout do
		task.wait()
	end
	connection:Disconnect()
end

local function movePieceTo(index: number)
	local root = board.pieceRoot
	local fromCFrame = root.CFrame
	local toCFrame = BoardModel.GetPieceCFrame(board, index)
	local mid = fromCFrame:Lerp(toCFrame, 0.5) + board.base.CFrame.UpVector * STEP_HOP

	local up = TweenService:Create(
		root,
		TweenInfo.new(STEP_TIME / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = mid }
	)
	pieceTween = up
	playAndWait(up, STEP_TIME * 2)
	if pieceTween ~= up then
		return -- o tabuleiro foi movido no meio do passo
	end
	local down = TweenService:Create(
		root,
		TweenInfo.new(STEP_TIME / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = toCFrame }
	)
	pieceTween = down
	playAndWait(down, STEP_TIME * 2)
	if pieceTween == down then
		pieceTween = nil
	end
	SoundUtil.Play("PieceStep", { Parent = board.base, Volume = 0.5, RollOffMaxDistance = 80 })
end

local function removeDice(dice: { BasePart })
	for _, die in dice do
		if die.Parent then
			die.Anchored = true
			for _, child in die:GetChildren() do
				if child:IsA("SurfaceGui") then
					child.Enabled = false
				end
			end
			local tween = TweenService:Create(die, TweenInfo.new(0.5), {
				Size = Vector3.new(0.05, 0.05, 0.05),
				Transparency = 1,
			})
			tween.Completed:Once(function()
				die:Destroy()
			end)
			tween:Play()
			Debris:AddItem(die, 2)
		end
	end
end

-- A jogada completa: tabuleiro no chão, dados com física, leitura, peça andando e o sinal Rolled.
local function performRoll(player: Player)
	-- 1. Se o jogador carrega o tabuleiro, ele é colocado no chão à frente dele.
	if carrier == player then
		placeBoard(frontPlacement(player))
	elseif carrier then
		dropFromCarrier()
	end
	updatePrompts()
	broadcastStatus()

	local fromSpace = space
	local isFirst = rollCount == 0
	local boardPosition = board.model:GetPivot().Position
	local top = board.base.CFrame * CFrame.new(0, BoardModel.BASE_SIZE.Y / 2, 0)
	SoundUtil.Play("DiceRoll", { Parent = board.base, RollOffMaxDistance = 120 })

	-- 2. Dados nascem acima do tabuleiro, com velocidade e giro aleatórios (física no servidor).
	ensureFolders()
	local dice: { BasePart } = {}
	local diceCount = math.clamp(math.floor(GameConfig.DICE_COUNT), 1, 6)
	for index = 1, diceCount do
		local lateral =
			top:PointToWorldSpace(Vector3.new(random:NextNumber(-1.2, 1.2), 0, random:NextNumber(-0.6, 0.6)))
		local rotation = CFrame.Angles(
			random:NextNumber(0, math.pi * 2),
			random:NextNumber(0, math.pi * 2),
			random:NextNumber(0, math.pi * 2)
		)
		local die =
			BoardModel.CreateDie(diceFolder, CFrame.new(lateral + Vector3.new(0, 2.2 + index * 0.95, 0)) * rotation)
		pcall(function()
			die:SetNetworkOwner(nil)
		end)
		die.AssemblyLinearVelocity =
			Vector3.new(random:NextNumber(-2.5, 2.5), random:NextNumber(1, 3), random:NextNumber(-2.5, 2.5))
		die.AssemblyAngularVelocity =
			Vector3.new(random:NextNumber(-20, 20), random:NextNumber(-20, 20), random:NextNumber(-20, 20))
		table.insert(dice, die)
	end

	-- 3. Espera os dados assentarem (parados por SETTLE_TIME ou até SETTLE_TIMEOUT).
	local started = os.clock()
	local stillSince: number? = nil
	while os.clock() - started < SETTLE_TIMEOUT do
		task.wait(0.1)
		local allStill = true
		for _, die in dice do
			if die:IsDescendantOf(workspace) then
				if
					die.AssemblyLinearVelocity.Magnitude > SETTLE_SPEED
					or die.AssemblyAngularVelocity.Magnitude > SETTLE_ANGULAR
				then
					allStill = false
					break
				end
			end
		end
		if allStill then
			stillSince = stillSince or os.clock()
			if os.clock() - (stillSince :: number) >= SETTLE_TIME then
				break
			end
		else
			stillSince = nil
		end
	end

	-- 4. Lê a face de cima. Dado perdido (longe, na água ou destruído) vale um número aleatório.
	local values: { number } = {}
	local total = 0
	for _, die in dice do
		local value
		if
			die:IsDescendantOf(workspace)
			and (die.Position - boardPosition).Magnitude <= DICE_FAR_DISTANCE
			and die.Position.Y > mapInfo.waterLevelY
		then
			value = BoardModel.ReadDie(die)
		else
			value = random:NextInteger(1, 6)
		end
		if die.Parent then
			die.Anchored = true
		end
		table.insert(values, value)
		total += value
	end
	task.delay(DICE_LINGER, removeDice, dice)

	-- 5. A peça anda casa a casa.
	local target = math.min(space + total, GameConfig.BOARD_SPACES)
	for step = space + 1, target do
		movePieceTo(step)
		space = step
		broadcastStatus()
	end
	board.pieceRoot.CFrame = BoardModel.GetPieceCFrame(board, space)

	local isFinal = space >= GameConfig.BOARD_SPACES
	if isFinal and board.finalLight then
		board.finalLight.Brightness = 4
		board.finalLight.Range = 8
	end

	rollCount += 1
	rolling = false
	rollingEnabled = false -- o MatchService religa quando for a hora
	updatePrompts()
	broadcastStatus()

	BoardService.Rolled:Fire({
		rollerUserId = player.UserId,
		dice = values,
		total = total,
		fromSpace = fromSpace,
		space = space,
		position = BoardService.GetBoardPosition(),
		isFinal = isFinal,
		isFirst = isFirst,
	})
end

local function requestRoll(player: Player)
	if not initialized or not player.Parent then
		return
	end
	local now = os.clock()
	local last = lastRequest[player]
	if last and now - last < REQUEST_DEBOUNCE then
		return
	end
	lastRequest[player] = now

	if rolling or not CombatUtil.IsPlayerAlive(player) then
		return
	end
	if locked then
		notify(player, "O tabuleiro está preso agora!", "warning")
		return
	end
	if not rollingEnabled then
		notify(player, "Ainda não é hora de jogar o dado.", "info")
		return
	end
	local remaining = cooldownRemaining()
	if remaining > 0 then
		notify(player, ("O dado ainda está quente! Próxima jogada em %ds."):format(math.ceil(remaining)), "info")
		return
	end
	if carrier then
		if carrier ~= player then
			notify(player, "Só quem está carregando o tabuleiro pode jogar o dado.", "info")
			return
		end
	else
		local root = getRoot(player)
		if not root or (root.Position - BoardService.GetBoardPosition()).Magnitude > ROLL_DISTANCE then
			notify(player, "Chegue mais perto do tabuleiro para jogar o dado.", "info")
			return
		end
	end

	-- Marca antes de ceder para que dois pedidos simultâneos não rolem duas vezes.
	rolling = true
	updatePrompts()
	broadcastStatus()
	task.spawn(function()
		local ok, err = pcall(performRoll, player)
		if not ok then
			warn("[BoardService] Erro durante a jogada: " .. tostring(err))
			rolling = false
			updatePrompts()
			broadcastStatus()
		end
	end)
end

local function createPrompts()
	local pickupAttachment = Instance.new("Attachment")
	pickupAttachment.Name = "PromptPegar"
	pickupAttachment.Position = Vector3.new(0, 0.9, 0)
	pickupAttachment.Parent = board.base

	local rollAttachment = Instance.new("Attachment")
	rollAttachment.Name = "PromptJogar"
	rollAttachment.Position = Vector3.new(0, 1.8, 0)
	rollAttachment.Parent = board.base

	local pickup = Instance.new("ProximityPrompt")
	pickup.Name = "PegarTabuleiro"
	pickup.ActionText = "Pegar tabuleiro"
	pickup.ObjectText = "Tabuleiro"
	pickup.KeyboardKeyCode = Enum.KeyCode.E
	pickup.GamepadKeyCode = Enum.KeyCode.ButtonX
	pickup.HoldDuration = 0.4
	pickup.MaxActivationDistance = PROMPT_DISTANCE
	pickup.RequiresLineOfSight = false
	pickup.Enabled = false
	pickup.Parent = pickupAttachment
	pickup.Triggered:Connect(tryPickup)
	pickupPrompt = pickup

	local roll = Instance.new("ProximityPrompt")
	roll.Name = "JogarDado"
	roll.ActionText = "Jogar o dado"
	roll.ObjectText = "Tabuleiro"
	roll.KeyboardKeyCode = Enum.KeyCode.T
	roll.GamepadKeyCode = Enum.KeyCode.ButtonY
	roll.HoldDuration = 0
	roll.MaxActivationDistance = PROMPT_DISTANCE
	roll.RequiresLineOfSight = false
	roll.Enabled = false
	roll.Parent = rollAttachment
	roll.Triggered:Connect(requestRoll)
	rollPrompt = roll
end

-- Reconstrói o tabuleiro se ele sumiu (ex.: personagem do carregador destruído).
local function rebuild()
	warn("[BoardService] O tabuleiro sumiu do workspace; reconstruindo na última posição segura.")
	clearCarrierConnections()
	for _, weld in carryWelds do
		weld:Destroy()
	end
	table.clear(carryWelds)
	carrier = nil
	pieceTween = nil
	if board and board.model then
		board.model:Destroy()
	end
	ensureFolders()
	board = BoardModel.Build(boardFolder, GameConfig.BOARD_SPACES)
	addHighlight(board.model)
	createPrompts()
	if lastRiddle then
		BoardModel.SetRiddle(board, lastRiddle)
	end
	placeBoard(lastSafeCFrame)
end

-- Verificações periódicas: tabuleiro inteiro, carregador válido, posição segura e chão embaixo.
local function monitorStep()
	if not board.base:IsDescendantOf(workspace) or not board.pieceRoot:IsDescendantOf(workspace) then
		rebuild()
		return
	end

	if carrier then
		local player = carrier
		local root = getRoot(player)
		if not player.Parent or not CombatUtil.IsPlayerAlive(player) or not root or #carryWelds == 0 then
			dropFromCarrier()
			return
		end
		local center = mapInfo.islandCenter
		local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
		if root.Position.Y < mapInfo.waterLevelY - 2 or flat.Magnitude > mapInfo.islandRadius then
			placeBoard(lastSafeCFrame)
			return
		end
		-- Guarda a última posição segura enquanto o tabuleiro é carregado.
		local ground, hit = findGround(root.Position, 12, 1)
		if ground and not isWater(hit) and isSafePosition(ground) then
			lastSafeCFrame = groundCFrame(ground, root.CFrame.LookVector)
		end
		return
	end

	if rolling or locked then
		-- Durante a jogada ou com o tabuleiro travado (ex.: pelicano), quem mexe é o dono da ação.
		return
	end

	local pivot = board.model:GetPivot()
	if not board.base.Anchored then
		placeBoard(placementAt(pivot.Position, pivot.LookVector, 60, 2))
		return
	end
	if not isSafePosition(pivot.Position) then
		placeBoard(lastSafeCFrame)
		remotes.notify:FireAllClients("O tabuleiro voltou para um lugar seguro.", "info")
		return
	end
	-- Chão destruído embaixo do tabuleiro: ele cai até o próximo chão.
	local support = findGround(pivot.Position, 1.5, 0.5)
	if not support then
		local below, hit = findGround(pivot.Position, 200, 0.5)
		if below and not isWater(hit) and isSafePosition(below) then
			placeBoard(groundCFrame(below, pivot.LookVector))
		else
			placeBoard(lastSafeCFrame)
		end
	end
end

local function monitorLoop()
	while true do
		task.wait(MONITOR_INTERVAL)
		local ok, err = pcall(monitorStep)
		if not ok then
			warn("[BoardService] Erro na verificação do tabuleiro: " .. tostring(err))
		end
	end
end

local function resolveSpawn(spawnCFrame: CFrame?): CFrame
	local base = typeof(spawnCFrame) == "CFrame" and spawnCFrame
		or CFrame.new(mapInfo.islandCenter.X, mapInfo.groundY, mapInfo.islandCenter.Z)
	-- O spawn fica em cima de uma mesa: ajusta a altura para o topo do que estiver embaixo.
	local ground = findGround(base.Position, 8, 2)
	if ground then
		return groundCFrame(ground, base.LookVector)
	end
	return groundCFrame(base.Position, base.LookVector)
end

local function watchReady(player: Player)
	local function sendIfReady()
		if player.Parent and player:GetAttribute("ClientReady") then
			remotes.status:FireClient(player, statusPayload())
		end
	end
	player:GetAttributeChangedSignal("ClientReady"):Connect(sendIfReady)
	sendIfReady()
end

-- API pública ----------------------------------------------------------------------------

function BoardService.Init(info)
	if initialized then
		return
	end
	mapInfo = info
	remotes.status = Net.event(Net.Names.Board_Status)
	remotes.roll = Net.event(Net.Names.Board_RollRequest)
	remotes.drop = Net.event(Net.Names.Board_DropRequest)
	remotes.notify = Net.event(Net.Names.Notify)
	remotes.ready = Net.event(Net.Names.Game_ClientReady)

	ensureFolders()
	board = BoardModel.Build(boardFolder, GameConfig.BOARD_SPACES)
	addHighlight(board.model)
	createPrompts()
	local spawnCFrame = resolveSpawn(info.boardSpawn)
	lastSafeCFrame = spawnCFrame
	initialized = true
	placeBoard(spawnCFrame)

	-- Os argumentos extras enviados pelo cliente são ignorados de propósito.
	remotes.roll.OnServerEvent:Connect(function(player)
		requestRoll(player)
	end)
	remotes.drop.OnServerEvent:Connect(function(player)
		if carrier == player and not rolling then
			BoardService.Drop()
		end
	end)
	-- Redundância: o GameMain já marca "ClientReady", mas isto garante o atributo mesmo sem ele.
	remotes.ready.OnServerEvent:Connect(function(player)
		if not player:GetAttribute("ClientReady") then
			player:SetAttribute("ClientReady", true)
		end
	end)

	Players.PlayerAdded:Connect(watchReady)
	for _, player in Players:GetPlayers() do
		watchReady(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		lastNotify[player] = nil
		if carrier == player then
			dropFromCarrier()
		end
	end)

	task.spawn(monitorLoop)
end

-- Libera ou bloqueia a rolagem (controlado pelo MatchService conforme a fase).
function BoardService.SetRollingEnabled(enabled: boolean)
	rollingEnabled = enabled == true
	if initialized then
		updatePrompts()
		broadcastStatus()
	end
end

-- Inicia o tempo de espera até a próxima jogada.
function BoardService.StartCooldown(seconds: number)
	local duration = math.max(tonumber(seconds) or 0, 0)
	cooldownToken += 1
	local token = cooldownToken
	cooldownEndsAt = workspace:GetServerTimeNow() + duration
	if initialized then
		updatePrompts()
		broadcastStatus()
	end
	task.delay(duration + 0.05, function()
		if token == cooldownToken and initialized then
			updatePrompts()
			broadcastStatus()
		end
	end)
end

function BoardService.GetSpace(): number
	return space
end

function BoardService.GetBoardModel(): Model
	return board and board.model
end

function BoardService.GetBoardPosition(): Vector3
	if not board then
		return mapInfo and mapInfo.islandCenter or Vector3.zero
	end
	if carrier and board.base.Parent then
		return board.base.Position
	end
	return board.model:GetPivot().Position
end

function BoardService.GetCarrier(): Player?
	return carrier
end

-- O carregador solta o tabuleiro no chão (na posição dada ou à frente dele).
function BoardService.Drop(position: Vector3?)
	if not initialized or not carrier then
		return
	end
	if typeof(position) == "Vector3" then
		local root = getRoot(carrier)
		placeBoard(placementAt(position, root and root.CFrame.LookVector or nil, 40, 3))
	else
		placeBoard(frontPlacement(carrier))
	end
end

-- true enquanto os dados rolam e a peça anda (o tabuleiro não deve ser movido nesse intervalo).
function BoardService.IsRolling(): boolean
	return rolling
end

-- Travado: ninguém pega nem joga. Se alguém estiver carregando, o tabuleiro cai no chão.
function BoardService.SetLocked(value: boolean)
	locked = value == true
	if not initialized then
		return
	end
	if locked and carrier then
		dropFromCarrier()
	end
	updatePrompts()
	broadcastStatus()
end

-- Coloca o tabuleiro no chão nessa posição (solta o carregador). Posição insegura = última segura.
function BoardService.PlaceAt(cframe: CFrame)
	if not initialized or typeof(cframe) ~= "CFrame" then
		return
	end
	placeBoard(placementAt(cframe.Position, cframe.LookVector, 60, 3))
end

-- Mostra o texto do enigma no vidro central do tabuleiro.
function BoardService.ShowRiddle(text: string)
	if not initialized or type(text) ~= "string" then
		return
	end
	lastRiddle = text
	BoardModel.SetRiddle(board, text)
	local light = board.glassLight
	light.Brightness = 3
	TweenService:Create(light, TweenInfo.new(6, Enum.EasingStyle.Sine), { Brightness = 0.6 }):Play()
end

return BoardService
