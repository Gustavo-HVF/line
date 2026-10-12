--!nonstrict
-- Liga/desliga o controle do personagem: teclado/mouse, gamepad e os botões de toque do celular
-- (analógico e pulo). No menu os controles ficam desligados (o personagem está no cubículo, fora da tela)
-- e os botões de toque somem para não cobrir o menu; no hub eles voltam.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local LobbyControls = {}

local desired = true
local controls = nil
local loading = false

local function apply()
	local enabled = desired
	pcall(function()
		GuiService.TouchControlsEnabled = enabled
	end)
	if controls then
		local ok, err = pcall(function()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end)
		if not ok then
			warn("[LobbyControls] Não foi possível alterar os controles: " .. tostring(err))
		end
	end
end

-- O PlayerModule padrão do Roblox expõe os controles (ControlModule) via GetControls().
local function loadControls()
	if controls or loading then
		return
	end
	loading = true
	task.spawn(function()
		local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts", 15)
		local playerModule = playerScripts and playerScripts:WaitForChild("PlayerModule", 15)
		if playerModule and playerModule:IsA("ModuleScript") then
			local ok, result = pcall(function()
				return (require :: any)(playerModule):GetControls()
			end)
			if ok and result then
				controls = result
			else
				warn("[LobbyControls] PlayerModule indisponível: " .. tostring(result))
			end
		end
		loading = false
		apply()
	end)
end

function LobbyControls.SetEnabled(enabled: boolean)
	desired = enabled == true
	apply()
	loadControls()
end

function LobbyControls.IsEnabled(): boolean
	return desired
end

return LobbyControls
