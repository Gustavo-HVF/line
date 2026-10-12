--!nonstrict
-- Painel "Placar" do menu: os melhores jogadores somando todas as partidas (dados do LeaderboardService).
--
--   LeaderboardUI.Open(onClose: () -> ())
--   LeaderboardUI.Close()
--   LeaderboardUI.IsOpen(): boolean

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local UIKit = require(ReplicatedStorage.Shared.UI.UIKit)

local LobbyUIUtil = require(script.Parent.LobbyUIUtil)

local LeaderboardUI = {}

local Theme = UIKit.Theme
local LocalPlayer = Players.LocalPlayer

local ui = nil
local isOpen = false
local onCloseCallback: (() -> ())? = nil
local latest = nil
local listening = false

local function render()
	if not ui then
		return
	end
	for _, child in ui.list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local payload = latest
	if not payload then
		ui.status.Text = "Carregando o placar…"
		return
	end
	local entries = if type(payload.entries) == "table" then payload.entries else {}
	if payload.available == false and #entries == 0 then
		ui.status.Text = "O placar não está disponível agora. Tente de novo mais tarde."
	elseif #entries == 0 then
		ui.status.Text = "Ninguém pontuou ainda. Vença o tabuleiro e seja o primeiro!"
	else
		ui.status.Text = "Pontos: 10 por bicho abatido, 15 por jogada no tabuleiro e 50 por vitória."
	end
	for index, entry in entries do
		if type(entry) == "table" then
			local mine = entry.userId == LocalPlayer.UserId
			local row = UIKit.Create("Frame", {
				Name = "Linha" .. index,
				BackgroundColor3 = if mine then Theme.GoldDark else Theme.PanelLight,
				BackgroundTransparency = if mine then 0.2 else 0.35,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -8, 0, 40),
				LayoutOrder = index,
				Parent = ui.list,
			})
			UIKit.Corner(row, UDim.new(0, 8))
			UIKit.Label({
				Text = ("%d."):format(index),
				Font = Theme.BoldFont,
				TextSize = 20,
				TextColor3 = if index == 1 then Theme.Gold else Theme.Text,
				TextXAlignment = Enum.TextXAlignment.Right,
				Position = UDim2.fromOffset(0, 8),
				Size = UDim2.fromOffset(36, 24),
				Parent = row,
			})
			UIKit.Label({
				Text = tostring(entry.name or "?"),
				Font = Theme.BoldFont,
				TextSize = 20,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.fromOffset(46, 8),
				Size = UDim2.new(0.5, -46, 0, 24),
				Parent = row,
			})
			local details = ("%d pts"):format(tonumber(entry.points) or 0)
			if type(entry.kills) == "number" then
				details ..= (" · %d bichos"):format(entry.kills)
			end
			if type(entry.wins) == "number" then
				details ..= (" · %d vitórias"):format(entry.wins)
			end
			UIKit.Label({
				Text = details,
				TextSize = 17,
				TextColor3 = Theme.TextMuted,
				TextWrapped = false,
				TextXAlignment = Enum.TextXAlignment.Right,
				Position = UDim2.new(0.5, 0, 0, 9),
				Size = UDim2.new(0.5, -12, 0, 22),
				Parent = row,
			})
		end
	end
end

local function build()
	local gui = UIKit.ScreenGui("PlacarGlobal", 30)
	LobbyUIUtil.UseSafeInsets(gui)
	LobbyUIUtil.Blocker(gui, 0.45)
	local panel = UIKit.Panel({
		Name = "Painel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 560),
		Parent = gui,
	})
	LobbyUIUtil.AutoScale(panel, 1100, 680, 0.6, 1.25)
	UIKit.Title("Placar Global", {
		TextSize = 38,
		Size = UDim2.new(1, 0, 0, 44),
		Parent = panel,
	})
	local status = UIKit.Label({
		Name = "Status",
		TextSize = 16,
		TextColor3 = Theme.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = panel,
	})
	local list = UIKit.List({
		Name = "Lista",
		Position = UDim2.fromOffset(0, 94),
		Size = UDim2.new(1, 0, 1, -158),
		Spacing = 6,
		Parent = panel,
	})
	UIKit.Button({
		Name = "Voltar",
		Text = "Voltar",
		Style = "primary",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0.5, 0, 0, 48),
		OnClick = function()
			LeaderboardUI.Close()
		end,
		Parent = panel,
	})
	ui = { gui = gui, status = status, list = list }
end

local function listen()
	if listening then
		return
	end
	listening = true
	Net.event(Net.Names.Leaderboard_Update).OnClientEvent:Connect(function(payload)
		if type(payload) == "table" then
			latest = payload
			if isOpen then
				render()
			end
		end
	end)
end

function LeaderboardUI.Open(onClose: () -> ())
	onCloseCallback = onClose
	listen()
	if not ui or not ui.gui.Parent then
		build()
	end
	ui.gui.Enabled = true
	isOpen = true
	render()
	task.spawn(function()
		local ok, payload = pcall(function()
			return Net.func(Net.Names.Leaderboard_Get):InvokeServer()
		end)
		if ok and type(payload) == "table" then
			latest = payload
		elseif not latest then
			latest = { available = false, entries = {} }
		end
		if isOpen then
			render()
		end
	end)
end

function LeaderboardUI.Close()
	if not isOpen then
		return
	end
	isOpen = false
	if ui then
		ui.gui.Enabled = false
	end
	local callback = onCloseCallback
	onCloseCallback = nil
	if callback then
		task.spawn(callback)
	end
end

function LeaderboardUI.IsOpen(): boolean
	return isOpen
end

return LeaderboardUI
