--!nonstrict
-- Cutscene do fim da partida (cliente) e tela do melhor jogador.
--   1. a câmera treme cada vez mais forte e avança até o tabuleiro;
--   2. a tela fica branca;
--   3. aparece o melhor da partida (foto, nome, bichos abatidos, jogadas no tabuleiro e pontos) e a
--      classificação de todos, com a contagem para voltar ao lobby.
--
--   EndCutscene.Init()
--   EndCutscene.IsPlaying(): boolean
--   EndCutscene.Started: Signal   -- o GameClient desliga a primeira pessoa e a corrida
--
-- Payload (Game_EndCutscene): { victory: boolean, boardPosition: Vector3, results: { MatchResult },
--   bestUserId: number?, killPoints: number, rollPoints: number }
--   MatchResult = { userId, name, kills, rolls, score }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local SoundUtil = require(ReplicatedStorage.Shared.Audio.SoundUtil)
local UIKit = require(ReplicatedStorage.Shared.UI.UIKit)

local EndCutscene = {}
EndCutscene.Started = Signal.new()

local CAMERA_STEP = "SelvaCutsceneFinal"
local APPROACH_TIME = 4.4
local WHITE_START = 3.0
local WHITE_TIME = 1.3
local FINAL_DISTANCE = 3.2 -- studs entre a câmera e o tabuleiro no fim
local PARCHMENT = Color3.fromRGB(244, 236, 214)
local INK = Color3.fromRGB(46, 34, 22)
local INK_SOFT = Color3.fromRGB(110, 88, 60)
local GOLD = Color3.fromRGB(196, 140, 46)

local LocalPlayer = Players.LocalPlayer
local Theme = UIKit.Theme

local initialized = false
local playing = false
local countdownLabel: TextLabel? = nil

local function num(value: any, default: number): number
	if type(value) == "number" and value == value then
		return value
	end
	return default
end

local function sanitize(payload)
	local results = {}
	if type(payload.results) == "table" then
		for _, entry in payload.results do
			if type(entry) == "table" and type(entry.userId) == "number" then
				table.insert(results, {
					userId = entry.userId,
					name = if type(entry.name) == "string" then entry.name else ("Jogador " .. entry.userId),
					kills = math.max(math.floor(num(entry.kills, 0)), 0),
					rolls = math.max(math.floor(num(entry.rolls, 0)), 0),
					score = math.max(math.floor(num(entry.score, 0)), 0),
				})
			end
		end
	end
	return {
		victory = payload.victory == true,
		boardPosition = if typeof(payload.boardPosition) == "Vector3" then payload.boardPosition else nil,
		results = results,
		bestUserId = if type(payload.bestUserId) == "number" then payload.bestUserId else nil,
	}
end

local function plural(count: number, one: string, many: string): string
	return ("%d %s"):format(count, if count == 1 then one else many)
end

local function statsLine(entry): string
	return ("%s · %s · %s"):format(
		plural(entry.kills, "bicho abatido", "bichos abatidos"),
		plural(entry.rolls, "jogada no tabuleiro", "jogadas no tabuleiro"),
		plural(entry.score, "ponto", "pontos")
	)
end

local function setControlsEnabled(enabled: boolean)
	pcall(function()
		local playerModule = LocalPlayer:WaitForChild("PlayerScripts"):FindFirstChild("PlayerModule")
		if playerModule then
			local controls = (require :: any)(playerModule):GetControls()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end
	end)
end

-- Câmera ----------------------------------------------------------------------------------------

local function runCamera(boardPosition: Vector3?)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local start = camera.CFrame
	local startFov = camera.FieldOfView
	local focus = (boardPosition or start.Position + start.LookVector * 20) + Vector3.new(0, 1.5, 0)
	local away = start.Position - focus
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.5 then
		away = Vector3.new(0, 0, 1)
	end
	local finalPosition = focus + away.Unit * FINAL_DISTANCE + Vector3.new(0, 2.2, 0)
	local began = os.clock()
	local seed = math.random() * 100

	camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(CAMERA_STEP, Enum.RenderPriority.Last.Value, function()
		local elapsed = os.clock() - began
		local alpha = math.clamp(elapsed / APPROACH_TIME, 0, 1)
		local eased = alpha ^ 2.2 -- acelera rumo ao tabuleiro
		local position = start.Position:Lerp(finalPosition, eased)
		local base = CFrame.lookAt(position, focus)
		-- tremor que cresce até o branco
		local strength = 0.08 + math.min(elapsed / APPROACH_TIME, 1.2) * 0.75
		local t = elapsed * 18
		local shake = CFrame.new(math.noise(seed, t) * strength, math.noise(seed + 10, t) * strength, 0)
			* CFrame.Angles(
				math.noise(seed + 20, t) * strength * 0.05,
				math.noise(seed + 30, t) * strength * 0.05,
				math.noise(seed + 40, t) * strength * 0.09
			)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = base * shake
		camera.FieldOfView = startFov + (55 - startFov) * eased
	end)
end

-- Tela de resultados ----------------------------------------------------------------------------

local function thumbnail(userId: number): string
	if userId <= 0 then
		return ""
	end
	local ok, image = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
	end)
	return if ok and type(image) == "string" then image else ""
end

local function buildResults(gui: ScreenGui, data)
	local root = UIKit.Create("CanvasGroup", {
		Name = "Resultados",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		GroupTransparency = 1,
		Parent = gui,
	}) :: CanvasGroup

	local column = UIKit.Frame({
		Name = "Coluna",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.92, 0, 0.92, 0),
		Parent = root,
	})
	UIKit.Create("UISizeConstraint", { MaxSize = Vector2.new(720, 680), Parent = column })
	local layout = UIKit.ListLayout(column, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center

	UIKit.Title(if data.victory then "O tabuleiro foi vencido!" else "A selva venceu…", {
		TextColor3 = if data.victory then GOLD else Color3.fromRGB(150, 50, 40),
		TextStrokeTransparency = 1,
		TextSize = 44,
		TextScaled = false,
		LayoutOrder = 1,
		Parent = column,
	})

	local best = nil
	for _, entry in data.results do
		if entry.userId == data.bestUserId then
			best = entry
		end
	end
	best = best or data.results[1]

	UIKit.Label({
		Text = "MELHOR DA PARTIDA",
		Font = Theme.BoldFont,
		TextSize = 18,
		TextColor3 = INK_SOFT,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		Parent = column,
	})

	local card = UIKit.Create("Frame", {
		Name = "Melhor",
		BackgroundColor3 = Color3.fromRGB(255, 250, 236),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 132),
		LayoutOrder = 3,
		Parent = column,
	})
	UIKit.Corner(card, UDim.new(0, 14))
	UIKit.Stroke(card, GOLD, 2)
	local photo = UIKit.Create("ImageLabel", {
		Name = "Foto",
		BackgroundColor3 = Color3.fromRGB(226, 214, 184),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(104, 104),
		Image = "",
		Parent = card,
	}) :: ImageLabel
	UIKit.Corner(photo, UDim.new(1, 0))
	UIKit.Stroke(photo, GOLD, 3)
	UIKit.Label({
		Name = "Nome",
		Text = if best then best.name else "Ninguém pontuou",
		Font = Theme.TitleFont,
		TextSize = 34,
		TextColor3 = INK,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(134, 22),
		Size = UDim2.new(1, -150, 0, 42),
		Parent = card,
	})
	UIKit.Label({
		Name = "Numeros",
		Text = if best then statsLine(best) else "Ninguém abateu bichos nem jogou o dado.",
		TextSize = 18,
		TextColor3 = INK_SOFT,
		Position = UDim2.fromOffset(134, 68),
		Size = UDim2.new(1, -150, 0, 44),
		Parent = card,
	})
	if best then
		task.spawn(function()
			photo.Image = thumbnail(best.userId)
		end)
	end

	if #data.results > 1 then
		local list = UIKit.Frame({
			Name = "Classificacao",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 4,
			Parent = column,
		})
		UIKit.ListLayout(list, 4)
		for index, entry in data.results do
			local row = UIKit.Create("Frame", {
				BackgroundColor3 = if entry.userId == LocalPlayer.UserId
					then Color3.fromRGB(240, 222, 170)
					else Color3.fromRGB(250, 244, 228),
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 34),
				LayoutOrder = index,
				Parent = list,
			})
			UIKit.Corner(row, UDim.new(0, 8))
			UIKit.Label({
				Text = ("%d. %s"):format(index, entry.name),
				Font = Theme.BoldFont,
				TextSize = 18,
				TextColor3 = INK,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.fromOffset(12, 5),
				Size = UDim2.new(0.42, -12, 0, 24),
				Parent = row,
			})
			UIKit.Label({
				Text = ("%d bichos · %d jogadas · %d pts"):format(entry.kills, entry.rolls, entry.score),
				TextSize = 16,
				TextColor3 = INK_SOFT,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextWrapped = false,
				Position = UDim2.new(0.42, 0, 0, 5),
				Size = UDim2.new(0.58, -12, 0, 24),
				Parent = row,
			})
		end
	end

	countdownLabel = UIKit.Label({
		Name = "Contagem",
		Text = "Voltando ao lobby…",
		TextSize = 17,
		TextColor3 = INK_SOFT,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 5,
		Parent = column,
	})
	return root
end

-- Sequência -----------------------------------------------------------------------------------------

local function play(payload)
	if playing or type(payload) ~= "table" then
		return
	end
	playing = true
	local data = sanitize(payload)
	EndCutscene.Started:Fire()
	setControlsEnabled(false)
	pcall(SoundUtil.Play, "Drums", { Volume = 1 })

	local gui = UIKit.ScreenGui("FimDaPartida", 150)
	local white = UIKit.Create("Frame", {
		Name = "Branco",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	}) :: Frame

	runCamera(data.boardPosition)
	task.wait(WHITE_START)
	TweenService:Create(white, TweenInfo.new(WHITE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 0,
	}):Play()
	task.wait(math.max(APPROACH_TIME - WHITE_START, WHITE_TIME) + 0.3)
	RunService:UnbindFromRenderStep(CAMERA_STEP)

	local results = buildResults(gui, data)
	TweenService:Create(white, TweenInfo.new(1.2), { BackgroundColor3 = PARCHMENT }):Play()
	TweenService:Create(results, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { GroupTransparency = 0 }):Play()
end

function EndCutscene.Init()
	if initialized then
		return
	end
	initialized = true
	Net.event(Net.Names.Game_EndCutscene).OnClientEvent:Connect(function(payload)
		task.spawn(play, payload)
	end)
	-- Contagem de volta ao lobby (vem no estado da partida).
	Net.event(Net.Names.Game_State).OnClientEvent:Connect(function(payload)
		local label = countdownLabel
		if not label or type(payload) ~= "table" then
			return
		end
		if type(payload.countdown) == "number" then
			label.Text = ("Voltando ao lobby em %ds…"):format(payload.countdown)
		elseif type(payload.message) == "string" then
			label.Text = payload.message
		end
	end)
end

function EndCutscene.IsPlaying(): boolean
	return playing
end

return EndCutscene
