--!nonstrict
-- Aplica as configurações gráficas no cliente. Tudo é local: nada disso replica para o servidor.
-- Funciona no lobby e na partida, com o workspace inteiro.
--
-- Sombras
--   off  → Lighting.GlobalShadows = false e nenhuma luz faz sombra;
--   low  → sombras ligadas e suaves (ShadowSoftness = 1); parts pequenas (maior dimensão < 8) e luzes sem sombra;
--   high → tudo como foi construído (valores originais) e ShadowSoftness = 0,2.
-- Redução de texturas
--   materiais (exceto Glass, Neon, ForceField e SmoothPlastic) viram SmoothPlastic; Decals e Textures ficam
--   invisíveis; GuiObjects com o atributo TextureDetail = true (detalhes "pintados" em SurfaceGuis) somem.
--   Personagens (Models com Humanoid) não são alterados, para ninguém ficar sem rosto.
-- Distância de renderização
--   Models com a tag CullChunk mais longe da câmera que o limite ficam invisíveis: LocalTransparencyModifier = 1
--   nas parts/decals e luzes, partículas e GUIs 3D desligadas. A checagem roda a cada ~0,4 s e só mexe nas
--   instâncias quando o estado do chunk muda. A distância é medida até o ponto mais próximo da caixa do Model.
--
-- Os valores originais ficam em tabelas fracas (chave = instância) para poder restaurar. Como o Roblox pode
-- coletar o objeto Lua de uma instância que ninguém referencia (e a entrada sumiria da tabela fraca), as
-- instâncias alteradas também ficam "presas" numa tabela forte, limpa periodicamente quando são destruídas.
-- Instâncias novas (mapa sendo construído, pedaços de destruição) entram numa fila processada aos poucos,
-- com limite de tempo por frame, para não travar o celular.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Tags = require(script.Parent.Parent.Tags)
local SettingsSchema = require(script.Parent.SettingsSchema)

local GraphicsApplier = {}

-- Ajustes -----------------------------------------------------------------------------------
local SMALL_PART_SIZE = 8 -- parts com maior dimensão abaixo disso não fazem sombra em "low"
local LOW_SHADOW_SOFTNESS = 1
local HIGH_SHADOW_SOFTNESS = 0.2
local CULL_INTERVAL = 0.4
local CULL_HYSTERESIS = 10 -- studs: um chunk escondido só volta quando fica 10 studs dentro do limite
local CULL_BUDGET = 3000 -- instâncias alteradas por frame ao esconder/mostrar chunks
local BOX_REFRESH_INTERVAL = 2 -- s: intervalo mínimo entre recálculos da caixa de um chunk que mudou
local QUEUE_TIME_BUDGET = 0.002 -- s por frame processando a fila de instâncias novas
local QUEUE_MIN_PER_FRAME = 64
local PASS_BATCH = 1500 -- instâncias por frame numa passada completa pelo workspace
local REGISTER_TIME_BUDGET = 0.004 -- s por frame registrando os chunks que já existiam no Init
local PIN_SWEEP_INTERVAL = 20
local DETAIL_ATTRIBUTE = "TextureDetail"
local CULL_TAG = Tags.CullChunk

local SMOOTH = Enum.Material.SmoothPlastic
local KEEP_MATERIALS = {
	[Enum.Material.Glass] = true,
	[Enum.Material.Neon] = true,
	[Enum.Material.ForceField] = true,
	[Enum.Material.SmoothPlastic] = true,
}

-- Estado ------------------------------------------------------------------------------------
local initialized = false
local hasApplied = false
local shadowMode = "high"
local reduced = false
local renderDistance = SettingsSchema.RenderDistanceStuds(SettingsSchema.Defaults())
local cullingEnabled = true

local function weakKeys()
	return setmetatable({}, { __mode = "k" })
end

-- Valores originais (só entra quem foi alterado).
local origCastShadow = weakKeys() -- [BasePart] = true
local origLightShadows = weakKeys() -- [Light] = true
local origMaterial = weakKeys() -- [BasePart] = Enum.Material
local origDecalTransparency = weakKeys() -- [Decal] = number
local origDetailVisible = weakKeys() -- [GuiObject] = true

-- Referências fortes das instâncias alteradas (ver comentário no topo).
local pinned: { [Instance]: boolean } = {}

local function isClean(inst: Instance): boolean
	return origCastShadow[inst] == nil
		and origLightShadows[inst] == nil
		and origMaterial[inst] == nil
		and origDecalTransparency[inst] == nil
		and origDetailVisible[inst] == nil
end

local function releaseIfClean(inst: Instance)
	if pinned[inst] and isClean(inst) then
		pinned[inst] = nil
	end
end

-- Parte de um personagem (jogador ou NPC com Humanoid)?
local function belongsToCharacter(inst: Instance): boolean
	local model = inst:FindFirstAncestorWhichIsA("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

-- Sombras e texturas --------------------------------------------------------------------------

local function applyPartShadow(part: BasePart)
	if shadowMode == "low" then
		local size = part.Size
		if math.max(size.X, size.Y, size.Z) < SMALL_PART_SIZE and part.CastShadow then
			origCastShadow[part] = true
			pinned[part] = true
			part.CastShadow = false
		end
	elseif origCastShadow[part] then
		-- "off" usa GlobalShadows/luzes; "high" volta ao original. Nos dois casos a part volta como era.
		origCastShadow[part] = nil
		part.CastShadow = true
		releaseIfClean(part)
	end
end

local function applyPartMaterial(part: BasePart)
	if reduced then
		local material = part.Material
		if not KEEP_MATERIALS[material] and not belongsToCharacter(part) then
			-- Também cobre o caso do servidor ter trocado o material depois da primeira redução.
			origMaterial[part] = material
			pinned[part] = true
			part.Material = SMOOTH
		end
	else
		local original = origMaterial[part]
		if original ~= nil then
			origMaterial[part] = nil
			-- Se o servidor trocou o material nesse meio-tempo, o valor dele vale mais que o guardado.
			if part.Material == SMOOTH then
				part.Material = original
			end
			releaseIfClean(part)
		end
	end
end

local function applyDecal(decal: Decal)
	if reduced then
		if decal.Transparency < 1 and not belongsToCharacter(decal) then
			origDecalTransparency[decal] = decal.Transparency
			pinned[decal] = true
			decal.Transparency = 1
		end
	else
		local original = origDecalTransparency[decal]
		if original ~= nil then
			origDecalTransparency[decal] = nil
			if decal.Transparency >= 1 then
				decal.Transparency = original
			end
			releaseIfClean(decal)
		end
	end
end

local function applyLight(light: Light)
	if shadowMode ~= "high" then
		if light.Shadows then
			origLightShadows[light] = true
			pinned[light] = true
			light.Shadows = false
		end
	elseif origLightShadows[light] then
		origLightShadows[light] = nil
		light.Shadows = true
		releaseIfClean(light)
	end
end

local function applyDetail(gui: GuiObject)
	if reduced then
		if gui.Visible then
			origDetailVisible[gui] = true
			pinned[gui] = true
			gui.Visible = false
		end
	elseif origDetailVisible[gui] then
		origDetailVisible[gui] = nil
		gui.Visible = true
		releaseIfClean(gui)
	end
end

-- Aplica o modo atual (sombras + texturas) numa instância qualquer.
local function processInstance(inst: Instance)
	if inst.Parent == nil then
		return
	end
	if inst:IsA("BasePart") then
		if inst:IsA("Terrain") then
			return
		end
		applyPartShadow(inst)
		applyPartMaterial(inst)
	elseif inst:IsA("Decal") then
		applyDecal(inst)
	elseif inst:IsA("Light") then
		applyLight(inst)
	elseif inst:IsA("GuiObject") then
		if inst:GetAttribute(DETAIL_ATTRIBUTE) == true then
			applyDetail(inst)
		end
	end
end

local function isRelevant(inst: Instance): boolean
	if inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Light") then
		return true
	end
	return inst:IsA("GuiObject") and inst:GetAttribute(DETAIL_ATTRIBUTE) == true
end

-- Com sombras altas e texturas normais, instâncias novas não precisam de nada.
local function isDefaultMode(): boolean
	return shadowMode == "high" and not reduced
end

-- Fila de instâncias novas (processada no Heartbeat com limite de tempo) ------------------------------
local queue: { Instance } = {}
local queueHead, queueTail = 1, 0
local queueConnection: RBXScriptConnection? = nil

local function processQueue()
	local started = os.clock()
	local processed = 0
	while queueHead <= queueTail do
		local inst = queue[queueHead]
		queue[queueHead] = nil
		queueHead += 1
		processInstance(inst)
		processed += 1
		if processed >= QUEUE_MIN_PER_FRAME and os.clock() - started > QUEUE_TIME_BUDGET then
			return
		end
	end
	-- Fila vazia: para de rodar todo frame.
	queueHead, queueTail = 1, 0
	if queueConnection then
		queueConnection:Disconnect()
		queueConnection = nil
	end
end

local function enqueue(inst: Instance)
	queueTail += 1
	queue[queueTail] = inst
	if not queueConnection then
		queueConnection = RunService.Heartbeat:Connect(processQueue)
	end
end

local function onDescendantAdded(inst: Instance)
	if isDefaultMode() then
		return
	end
	if isRelevant(inst) then
		enqueue(inst)
	end
end

-- Passada completa pelo workspace (quando o modo de sombras/texturas muda). Uma passada nova cancela a anterior.
local passGeneration = 0
local function startFullPass()
	passGeneration += 1
	local generation = passGeneration
	task.spawn(function()
		local descendants = workspace:GetDescendants()
		for index, inst in descendants do
			if generation ~= passGeneration then
				return
			end
			processInstance(inst)
			if index % PASS_BATCH == 0 then
				task.wait()
			end
		end
	end)
end

local function applyLighting(mode: string)
	if mode == "off" then
		Lighting.GlobalShadows = false
	else
		Lighting.GlobalShadows = true
		Lighting.ShadowSoftness = mode == "low" and LOW_SHADOW_SOFTNESS or HIGH_SHADOW_SOFTNESS
	end
end

-- Limpa as referências de instâncias destruídas.
local function sweepPins()
	local snapshot = table.clone(pinned)
	local count = 0
	for inst in snapshot do
		if inst.Parent == nil then
			pinned[inst] = nil
			origCastShadow[inst] = nil
			origLightShadows[inst] = nil
			origMaterial[inst] = nil
			origDecalTransparency[inst] = nil
			origDetailVisible[inst] = nil
		end
		count += 1
		if count % 4000 == 0 then
			task.wait()
		end
	end
end

-- Culling por distância ------------------------------------------------------------------------

-- Tipos de membro de um chunk.
local KIND_TRANSPARENCY = 1 -- usa LocalTransparencyModifier
local KIND_ENABLED = 2 -- usa Enabled

type Chunk = {
	model: Model,
	members: { [Instance]: number },
	disabled: { [Instance]: boolean }, -- desligados por ESTE culling (para religar só esses)
	hidden: boolean,
	boxCFrame: CFrame?,
	boxHalf: Vector3?,
	boxDirty: boolean,
	boxTime: number,
	connections: { RBXScriptConnection },
	removed: boolean,
}

local chunks: { [Instance]: Chunk } = {}

local function classify(inst: Instance): number?
	if inst:IsA("BasePart") then
		return if inst:IsA("Terrain") then nil else KIND_TRANSPARENCY
	end
	if inst:IsA("Decal") or inst:IsA("Beam") then
		return KIND_TRANSPARENCY
	end
	if
		inst:IsA("Light")
		or inst:IsA("ParticleEmitter")
		or inst:IsA("LayerCollector")
		or inst:IsA("Trail")
		or inst:IsA("Fire")
		or inst:IsA("Smoke")
		or inst:IsA("Sparkles")
	then
		return KIND_ENABLED
	end
	return nil
end

-- Chunk mais próximo acima da instância (chunks aninhados: cada instância pertence ao mais interno).
local function ownerChunkModel(inst: Instance): Instance?
	local current = inst.Parent
	while current and current ~= workspace do
		if chunks[current] or (current:IsA("Model") and CollectionService:HasTag(current, CULL_TAG)) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function hideMember(chunk: Chunk, inst: any, kind: number)
	if kind == KIND_TRANSPARENCY then
		inst.LocalTransparencyModifier = 1
	elseif inst.Enabled then
		inst.Enabled = false
		chunk.disabled[inst] = true
	end
end

local function showMember(chunk: Chunk, inst: any, kind: number)
	if kind == KIND_TRANSPARENCY then
		inst.LocalTransparencyModifier = 0
	elseif chunk.disabled[inst] then
		chunk.disabled[inst] = nil
		inst.Enabled = true
	end
end

-- Esconde/mostra um chunk inteiro. Retorna quantas instâncias foram tocadas (para o orçamento por frame).
local function setChunkHidden(chunk: Chunk, hidden: boolean): number
	if chunk.hidden == hidden then
		return 0
	end
	chunk.hidden = hidden
	local count = 0
	for inst, kind in chunk.members do
		if hidden then
			hideMember(chunk, inst, kind)
		else
			showMember(chunk, inst, kind)
		end
		count += 1
	end
	if not hidden then
		table.clear(chunk.disabled)
	end
	return count
end

local function addMember(chunk: Chunk, inst: Instance)
	local kind = classify(inst)
	if not kind or chunk.members[inst] then
		return
	end
	if ownerChunkModel(inst) ~= chunk.model then
		return
	end
	chunk.members[inst] = kind
	if inst:IsA("BasePart") then
		chunk.boxDirty = true
	end
	if chunk.hidden then
		hideMember(chunk, inst, kind)
	end
end

local function removeMember(chunk: Chunk, inst: Instance)
	local kind = chunk.members[inst]
	if not kind then
		return
	end
	chunk.members[inst] = nil
	-- Saiu do chunk (destruída ou virou destroço em workspace.Debris): volta a ser visível.
	if chunk.hidden then
		showMember(chunk, inst, kind)
	end
	chunk.disabled[inst] = nil
	if kind == KIND_TRANSPARENCY then
		chunk.boxDirty = true
	end
end

local function removeChunk(model: Instance)
	local chunk = chunks[model]
	if not chunk then
		return
	end
	chunks[model] = nil
	chunk.removed = true
	for _, connection in chunk.connections do
		connection:Disconnect()
	end
	if chunk.hidden then
		setChunkHidden(chunk, false)
	end
	table.clear(chunk.members)
end

local function addChunk(model: Instance)
	if chunks[model] or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return
	end
	local chunk: Chunk = {
		model = model,
		members = {},
		disabled = {},
		hidden = false,
		boxCFrame = nil,
		boxHalf = nil,
		boxDirty = true,
		boxTime = 0,
		connections = {},
		removed = false,
	}
	chunks[model] = chunk
	for _, descendant in model:GetDescendants() do
		addMember(chunk, descendant)
	end
	table.insert(
		chunk.connections,
		model.DescendantAdded:Connect(function(descendant)
			addMember(chunk, descendant)
		end)
	)
	table.insert(
		chunk.connections,
		model.DescendantRemoving:Connect(function(descendant)
			removeMember(chunk, descendant)
		end)
	)
	-- Saiu do workspace sem ser destruído (a tag continua): para de controlar.
	table.insert(
		chunk.connections,
		model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(workspace) then
				removeChunk(model)
			end
		end)
	)
end

-- Caixa do chunk (cacheada; recalculada quando parts entram/saem, no máximo a cada BOX_REFRESH_INTERVAL).
local function refreshBox(chunk: Chunk, now: number)
	if not chunk.boxDirty then
		return
	end
	if chunk.boxCFrame and now - chunk.boxTime < BOX_REFRESH_INTERVAL then
		return
	end
	chunk.boxDirty = false
	chunk.boxTime = now
	if next(chunk.members) == nil then
		chunk.boxCFrame = nil
		chunk.boxHalf = nil
		return
	end
	local ok, cframe, size = pcall(function()
		return chunk.model:GetBoundingBox()
	end)
	if ok and typeof(cframe) == "CFrame" and typeof(size) == "Vector3" then
		chunk.boxCFrame = cframe
		chunk.boxHalf = size / 2
	else
		chunk.boxCFrame = nil
		chunk.boxHalf = nil
	end
end

-- Distância da câmera até o ponto mais próximo da caixa orientada do chunk (0 se estiver dentro).
local function distanceToBox(boxCFrame: CFrame, half: Vector3, point: Vector3): number
	local relative = boxCFrame:PointToObjectSpace(point)
	local dx = math.max(math.abs(relative.X) - half.X, 0)
	local dy = math.max(math.abs(relative.Y) - half.Y, 0)
	local dz = math.max(math.abs(relative.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function cullStep()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPosition = camera.CFrame.Position
	local limit = renderDistance
	local now = os.clock()

	-- Cópia da lista: o laço pode ceder e chunks podem entrar/sair nesse meio-tempo.
	local list = {}
	for _, chunk in chunks do
		table.insert(list, chunk)
	end

	local touched = 0
	for _, chunk in list do
		if not chunk.removed then
			local hide = false
			if cullingEnabled then
				refreshBox(chunk, now)
				local boxCFrame, half = chunk.boxCFrame, chunk.boxHalf
				if boxCFrame and half then
					local distance = distanceToBox(boxCFrame, half, cameraPosition)
					hide = if chunk.hidden then distance > limit - CULL_HYSTERESIS else distance > limit
				end
			end
			if hide ~= chunk.hidden then
				touched += setChunkHidden(chunk, hide)
				if touched >= CULL_BUDGET then
					task.wait()
					touched = 0
				end
			end
		end
	end
end

local cullRunning = false
local cullAgain = false

local function runCull()
	if cullRunning then
		cullAgain = true
		return
	end
	cullRunning = true
	repeat
		cullAgain = false
		local ok, err = pcall(cullStep)
		if not ok then
			warn("[GraphicsApplier] Erro no culling: " .. tostring(err))
		end
	until not cullAgain
	cullRunning = false
end

local function requestCull()
	if initialized then
		task.spawn(runCull)
	end
end

-- Registra aos poucos os chunks que já existiam (sem travar o primeiro frame).
local function registerExistingChunks()
	local started = os.clock()
	for _, model in CollectionService:GetTagged(CULL_TAG) do
		addChunk(model)
		if os.clock() - started > REGISTER_TIME_BUDGET then
			task.wait()
			started = os.clock()
		end
	end
	requestCull()
end

-- API pública ------------------------------------------------------------------------------------

-- Idempotente. Começa a escutar o workspace (em lote) e o culling por distância.
function GraphicsApplier.Init()
	if initialized then
		return
	end
	if not RunService:IsClient() then
		warn("[GraphicsApplier] Use somente no cliente.")
		return
	end
	initialized = true

	workspace.DescendantAdded:Connect(onDescendantAdded)
	-- Um evento físico trocou o material do bloco (ex.: virou areia): reaplica a redução de texturas nele.
	CollectionService:GetInstanceAddedSignal(Tags.EventSkinned):Connect(onDescendantAdded)
	CollectionService:GetInstanceAddedSignal(CULL_TAG):Connect(addChunk)
	CollectionService:GetInstanceRemovedSignal(CULL_TAG):Connect(removeChunk)
	task.spawn(registerExistingChunks)

	task.spawn(function()
		while true do
			task.wait(CULL_INTERVAL)
			runCull()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(PIN_SWEEP_INTERVAL)
			local ok, err = pcall(sweepPins)
			if not ok then
				warn("[GraphicsApplier] Erro ao limpar referências: " .. tostring(err))
			end
		end
	end)
end

-- Aplica sombras, redução de texturas e distância de renderização. Não cede.
function GraphicsApplier.Apply(graphics)
	if not RunService:IsClient() then
		return
	end
	GraphicsApplier.Init()
	local clean = SettingsSchema.Sanitize({ graphics = graphics }).graphics

	local shadowsChanged = clean.shadows ~= shadowMode
	local texturesChanged = clean.reducedTextures ~= reduced
	if shadowsChanged or not hasApplied then
		applyLighting(clean.shadows)
	end
	hasApplied = true
	shadowMode = clean.shadows
	reduced = clean.reducedTextures
	if shadowsChanged or texturesChanged then
		startFullPass()
	end

	local distance = GameConfig.RENDER_DISTANCES[clean.renderDistance] or renderDistance
	if distance ~= renderDistance then
		renderDistance = distance
		requestCull()
	end
end

-- false: mostra tudo e para de esconder (varredura de pré-carregamento). true: volta ao normal.
function GraphicsApplier.SetCullingEnabled(enabled: boolean)
	local value = enabled ~= false
	if cullingEnabled == value then
		return
	end
	cullingEnabled = value
	if not value then
		for _, chunk in chunks do
			if chunk.hidden then
				setChunkHidden(chunk, false)
			end
		end
	end
	requestCull()
end

-- Distância de renderização atual em studs.
function GraphicsApplier.GetRenderDistance(): number
	return renderDistance
end

return GraphicsApplier
