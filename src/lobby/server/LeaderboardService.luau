--!nonstrict
-- Placar global no lobby (servidor).
--   * busca os melhores jogadores (ServerShared/GlobalStats) ao ligar e a cada REFRESH segundos;
--   * responde Leaderboard_Get e avisa os clientes com Leaderboard_Update (o menu mostra no painel "Placar");
--   * escreve no quadro de pedra da parede do hub.
--
--   LeaderboardService.Init()
--
--   LeaderboardPayload = { available: boolean, entries: { { rank, userId, name, points, kills?, wins? } },
--                          updatedAt: number }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local PartBuilder = require(ReplicatedStorage.Shared.Util.PartBuilder)

local GlobalStats = require(ServerScriptService.ServerShared.GlobalStats)

local LeaderboardService = {}

local TOP = 10
local REFRESH = 60
local BOARD_PIXELS_PER_STUD = 40

local initialized = false
local payload = { available = false, entries = {}, updatedAt = 0 }
local boardRows: { TextLabel } = {}
local boardStatus: TextLabel? = nil

-- Quadro do hub -------------------------------------------------------------------------------------

local function buildBoard()
	local origin = GameConfig.HUB_ORIGIN
	-- Parede esquerda (x = -46) do hub, entre as tochas de z = 0 e z = 27, virado para dentro.
	local position = origin + Vector3.new(-45.5, 10, 13.5)
	local cframe = CFrame.lookAt(position, position + Vector3.new(1, 0, 0))

	local model = PartBuilder.model("QuadroPlacar")
	local slab = PartBuilder.part({
		Name = "Lousa",
		Size = Vector3.new(17, 13, 0.8),
		CFrame = cframe,
		Color = Color3.fromRGB(64, 58, 50),
		Material = Enum.Material.Slate,
		Parent = model,
	})
	PartBuilder.part({
		Name = "Moldura",
		Size = Vector3.new(18.2, 14.2, 0.6),
		CFrame = cframe * CFrame.new(0, 0, 0.3),
		Color = Color3.fromRGB(150, 112, 34),
		Material = Enum.Material.Metal,
		Parent = model,
	})

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Placar"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = BOARD_PIXELS_PER_STUD
	gui.LightInfluence = 0.4
	gui.Brightness = 1.6
	gui.Parent = slab

	local title = Instance.new("TextLabel")
	title.Name = "Titulo"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 80)
	title.Font = Enum.Font.Fondamento
	title.TextSize = 58
	title.TextColor3 = Color3.fromRGB(240, 202, 96)
	title.Text = "Placar Global"
	title.Parent = gui

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(0, 74)
	status.Size = UDim2.new(1, 0, 0, 30)
	status.Font = Enum.Font.BuilderSans
	status.TextSize = 22
	status.TextColor3 = Color3.fromRGB(196, 186, 160)
	status.Text = "Carregando…"
	status.Parent = gui
	boardStatus = status

	for index = 1, TOP do
		local row = Instance.new("TextLabel")
		row.Name = "Linha" .. index
		row.BackgroundTransparency = 1
		row.Position = UDim2.new(0, 30, 0, 108 + (index - 1) * 40)
		row.Size = UDim2.new(1, -60, 0, 38)
		row.Font = if index <= 3 then Enum.Font.BuilderSansBold else Enum.Font.BuilderSans
		row.TextSize = 28
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = if index == 1
			then Color3.fromRGB(255, 214, 90)
			elseif index <= 3 then Color3.fromRGB(236, 226, 200)
			else Color3.fromRGB(206, 198, 176)
		row.Text = ""
		row.Parent = gui
		table.insert(boardRows, row)
	end

	model.Parent = workspace
end

local function updateBoard()
	if boardStatus then
		if not payload.available then
			boardStatus.Text = "Placar indisponível agora."
		elseif #payload.entries == 0 then
			boardStatus.Text = "Ninguém pontuou ainda. Seja o primeiro!"
		else
			boardStatus.Text = "Pontos somados em todas as partidas"
		end
	end
	for index, row in boardRows do
		local entry = payload.entries[index]
		row.Text = if entry then ("%d.  %s  —  %d pts"):format(index, entry.name, entry.points) else ""
	end
end

-- Atualização ---------------------------------------------------------------------------------------

local function refresh()
	local ok, entries, err = pcall(GlobalStats.GetTop, TOP)
	if ok and entries then
		payload = { available = true, entries = entries, updatedAt = os.time() }
	else
		payload = { available = false, entries = payload.entries, updatedAt = os.time() }
		warn("[LeaderboardService] Não foi possível ler o placar: " .. tostring(if ok then err else entries))
	end
	updateBoard()
	Net.event(Net.Names.Leaderboard_Update):FireAllClients(payload)
end

function LeaderboardService.Init()
	if initialized then
		return
	end
	initialized = true
	Net.event(Net.Names.Leaderboard_Update)
	Net.func(Net.Names.Leaderboard_Get).OnServerInvoke = function()
		return payload
	end
	local ok, err = pcall(buildBoard)
	if not ok then
		warn("[LeaderboardService] Erro ao montar o quadro do hub: " .. tostring(err))
	end
	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH)
		end
	end)
end

return LeaderboardService
