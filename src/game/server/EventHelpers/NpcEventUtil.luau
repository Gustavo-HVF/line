--!nonstrict
-- Utilitários dos eventos de inimigos (Macacos, Leão, Caçador, Aranhas, Mosquitos):
--   * sessão com limpeza idempotente: threads canceladas + NPC.DespawnGroup(ctx.instanceId);
--   * quantidade de jogadores vivos (para escalar o número de inimigos);
--   * nascimento em volta do ponto do evento (GroundUtil.RandomPointNear), olhando para o centro;
--   * ondas ao longo da duração: a próxima onda vem no intervalo ou logo depois que a atual morre;
--     se o limite global de NPCs estiver cheio, os que faltam nascem assim que houver vaga;
--     quando não há mais ondas e todos morreram, chama ctx.finish().
-- Nada aqui cede dentro do Start do evento: o trabalho que espera roda em threads da sessão.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local CombatUtil = require(script.Parent.Parent.CombatUtil)
local GroundUtil = require(script.Parent.GroundUtil)

local NpcEventUtil = {}

local TICK = 0.5
local SPAWN_STAGGER = 0.25 -- um inimigo a cada 0,25 s (nada de 12 modelos no mesmo frame)
local WAVE_BREATHER = 4 -- pausa entre uma onda derrotada e a próxima
local GIVE_UP_TIME = 12 -- sem vaga para os pendentes e ninguém vivo: o evento termina
local DEFAULT_MIN_RADIUS = 12

local Session = {}
Session.__index = Session

export type WaveOptions = {
	interval: number?, -- segundos entre o começo de uma onda e o da próxima
	startDelay: number?, -- espera antes da primeira onda
	health: number?,
	damage: number?,
	minRadius: number?,
	maxRadius: number?,
	waveMessage: string?, -- aviso para todos a partir da 2ª onda
	onSpawned: ((models: { Model }, wave: number) -> ())?,
}

-- Jogadores vivos agora (no mínimo 1).
function NpcEventUtil.AlivePlayerCount(ctx): number
	local combat = (type(ctx) == "table" and type(ctx.services) == "table" and ctx.services.Combat) or CombatUtil
	local ok, list = pcall(combat.GetAlivePlayers)
	local count = if ok and type(list) == "table" then #list else 0
	return math.max(count, 1)
end

-- Divide `total` inimigos em `waves` ondas (as primeiras ficam com o resto da divisão).
function NpcEventUtil.SplitWaves(total: number, waves: number): { number }
	local amount = math.max(math.floor(total), 1)
	local count = math.clamp(math.floor(waves), 1, amount)
	local base = math.floor(amount / count)
	local extra = amount - base * count
	local list = {}
	for index = 1, count do
		list[index] = base + (if index <= extra then 1 else 0)
	end
	return list
end

local notifyRemote: RemoteEvent? = nil

function NpcEventUtil.NotifyAll(text: string, kind: string?)
	if not notifyRemote then
		notifyRemote = Net.event(Net.Names.Notify)
	end
	(notifyRemote :: RemoteEvent):FireAllClients(text, kind or "info")
end

-- Sessão ------------------------------------------------------------------------------------------

function NpcEventUtil.new(ctx, label: string)
	local services = if type(ctx.services) == "table" then ctx.services else {}
	local npc = services.NPC
	if not npc or type(npc.Spawn) ~= "function" then
		warn(("[%s] NPCService indisponível: o evento não terá inimigos."):format(label))
		npc = nil
	end
	local self = setmetatable({
		ctx = ctx,
		label = label,
		npc = npc,
		ground = services.Ground or GroundUtil,
		threads = {},
		cleaned = false,
		spawnedTotal = 0,
	}, Session)
	return self
end

function Session:Active(): boolean
	return not self.cleaned and self.ctx.isActive()
end

-- task.spawn rastreado (cancelado na limpeza); erros viram aviso no Output.
function Session:Spawn(fn: (...any) -> (), ...: any): thread
	local label = self.label
	local thread = task.spawn(function(...)
		local ok, err = pcall(fn, ...)
		if not ok then
			warn(("[%s] Erro no evento: %s"):format(label, tostring(err)))
		end
	end, ...)
	table.insert(self.threads, thread)
	return thread
end

-- Espera `seconds` em fatias; devolve false se o evento acabou no meio.
function Session:Wait(seconds: number): boolean
	local deadline = os.clock() + seconds
	while self:Active() do
		local left = deadline - os.clock()
		if left <= 0 then
			return true
		end
		task.wait(math.min(left, TICK))
	end
	return false
end

function Session:CountAlive(): number
	local npc = self.npc
	if not npc then
		return 0
	end
	local ok, count = pcall(npc.CountAlive, self.ctx.instanceId)
	return if ok and type(count) == "number" then count else 0
end

-- Models vivos do evento (vazio se o NPCService não tiver GetGroup).
function Session:GetModels(): { Model }
	local npc = self.npc
	if not npc or type(npc.GetGroup) ~= "function" then
		return {}
	end
	local ok, models = pcall(npc.GetGroup, self.ctx.instanceId)
	return if ok and type(models) == "table" then models else {}
end

-- CFrame de nascimento: ponto no chão perto do evento, olhando para o centro.
function Session:SpawnPoint(minRadius: number?, maxRadius: number?): CFrame
	local ctx = self.ctx
	local center: Vector3 = ctx.position
	local minimum = minRadius or DEFAULT_MIN_RADIUS
	local maximum = maxRadius or math.max(ctx.radius * 0.6, minimum + 4)
	local point = self.ground.RandomPointNear(center, minimum, maximum, ctx.random)
	local flat = Vector3.new(center.X - point.X, 0, center.Z - point.Z)
	if flat.Magnitude < 0.5 then
		local angle = ctx.random:NextNumber(0, math.pi * 2)
		flat = Vector3.new(math.cos(angle), 0, math.sin(angle))
	end
	return CFrame.lookAt(point, point + flat.Unit)
end

-- Cria até `count` inimigos, um a cada SPAWN_STAGGER s (cede). Para no limite global de NPCs.
function Session:SpawnBatch(kind: string, count: number, options: WaveOptions?): (number, { Model })
	local opts = options or {}
	local models = {}
	local npc = self.npc
	if not npc then
		return 0, models
	end
	for index = 1, count do
		if not self:Active() then
			break
		end
		local cframe = self:SpawnPoint(opts.minRadius, opts.maxRadius)
		local ok, model = pcall(npc.Spawn, kind, cframe, {
			groupId = self.ctx.instanceId,
			health = opts.health,
			damage = opts.damage,
		})
		if not ok then
			warn(("[%s] Erro ao criar %s: %s"):format(self.label, kind, tostring(model)))
			break
		elseif not model then
			break -- limite de NPCs: tenta de novo depois
		end
		table.insert(models, model)
		self.spawnedTotal += 1
		if index < count then
			task.wait(SPAWN_STAGGER)
		end
	end
	return #models, models
end

-- Roda as ondas em uma thread da sessão e termina o evento quando todas forem derrotadas.
function Session:RunWaves(kind: string, waves: { number }, options: WaveOptions?)
	local opts = options or {}
	self:Spawn(function()
		local ctx = self.ctx
		if not self.npc then
			if self:Active() then
				ctx.finish()
			end
			return
		end
		if not self:Wait(opts.startDelay or 0.5) then
			return
		end
		local interval = opts.interval or 30
		local waveIndex = 0
		local pending = 0
		local nextWaveAt = 0
		local lastProgress = os.clock()
		while self:Active() do
			local now = os.clock()
			local alive = self:CountAlive()
			if waveIndex < #waves then
				if waveIndex > 0 and alive == 0 and pending == 0 then
					-- Onda derrotada antes do tempo: a próxima vem depois de um respiro.
					nextWaveAt = math.min(nextWaveAt, now + WAVE_BREATHER)
				end
				if now >= nextWaveAt then
					waveIndex += 1
					pending += waves[waveIndex]
					nextWaveAt = now + interval
					lastProgress = now
					if waveIndex > 1 and opts.waveMessage then
						NpcEventUtil.NotifyAll(opts.waveMessage, "warning")
					end
				end
			end
			if pending > 0 then
				local spawned, models = self:SpawnBatch(kind, pending, opts)
				pending -= spawned
				if spawned > 0 then
					lastProgress = os.clock()
					if opts.onSpawned then
						local ok, err = pcall(opts.onSpawned, models, waveIndex)
						if not ok then
							warn(("[%s] Erro depois de criar inimigos: %s"):format(self.label, tostring(err)))
						end
					end
				end
				alive = self:CountAlive()
			end
			if not self:Active() then
				return
			end
			if waveIndex >= #waves and alive == 0 then
				if pending == 0 or os.clock() - lastProgress >= GIVE_UP_TIME then
					ctx.finish()
					return
				end
			end
			task.wait(TICK)
		end
	end)
end

-- Limpeza idempotente: para as threads e remove os inimigos do evento.
function Session:Cleanup()
	if self.cleaned then
		return
	end
	self.cleaned = true
	local current = coroutine.running()
	for _, thread in self.threads do
		if thread ~= current and coroutine.status(thread) == "suspended" then
			pcall(task.cancel, thread)
		end
	end
	table.clear(self.threads)
	local npc = self.npc
	if npc and type(npc.DespawnGroup) == "function" then
		local ok, err = pcall(npc.DespawnGroup, self.ctx.instanceId)
		if not ok then
			warn(("[%s] Erro ao remover os inimigos: %s"):format(self.label, tostring(err)))
		end
	end
end

return NpcEventUtil
