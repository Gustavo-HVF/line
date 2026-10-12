--!nonstrict
-- Ficha de cada tipo de inimigo: nome exibido (pt-BR), vida, dano, velocidade, alcance, ritmo da IA e
-- parâmetros de caminho. Ajuste o balanceamento aqui sem mexer na IA.

export type KindDef = {
	kind: string,
	displayName: string, -- nome na barra de vida e motivo da eliminação
	movement: string, -- "ground" (Humanoid) | "flying" (CFrame ancorado) | "static" (parado)
	health: number,
	damage: number, -- dano do ataque principal (mordida, garra, tiro, picada)
	walkSpeed: number,
	jumpPower: number,
	thinkInterval: number, -- segundos entre decisões quando há alvo
	idleInterval: number, -- segundos entre decisões sem alvo
	aggroRadius: number, -- distância em que percebe um jogador
	leashRadius: number, -- distância em que desiste do alvo atual
	attackRange: number,
	attackCooldown: number,
	agentRadius: number, -- PathfindingService
	agentHeight: number,
	waypointReach: number, -- distância (XZ) para considerar um ponto do caminho alcançado
	barMaxDistance: number, -- distância máxima em que a barra de vida aparece
	boss: boolean, -- barra de vida maior
	persistent: boolean, -- sem ninguém no raio, vai atrás do jogador vivo mais próximo onde estiver
	sound: string?, -- som característico (Config/Sounds)
}

local Kinds = {}

local Defs: { [string]: KindDef } = {
	Monkey = {
		kind = "Monkey",
		displayName = "Macaco",
		movement = "ground",
		health = 30,
		damage = 6,
		walkSpeed = 22,
		jumpPower = 65, -- pula muito
		thinkInterval = 0.15,
		idleInterval = 0.5,
		aggroRadius = 150,
		leashRadius = 220,
		attackRange = 4.5,
		attackCooldown = 1,
		agentRadius = 1.2,
		agentHeight = 3.2,
		waypointReach = 3,
		barMaxDistance = 80,
		boss = false,
		persistent = false,
		sound = "Monkey",
	},
	Lion = {
		kind = "Lion",
		displayName = "Leão",
		movement = "ground",
		health = 220,
		damage = 25,
		walkSpeed = 24,
		jumpPower = 40,
		thinkInterval = 0.15,
		idleInterval = 0.5,
		aggroRadius = 150,
		leashRadius = 230,
		attackRange = 7.5,
		attackCooldown = 1.4,
		agentRadius = 2,
		agentHeight = 6.5,
		waypointReach = 3.5,
		barMaxDistance = 120,
		boss = false,
		persistent = false,
		sound = "Roar",
	},
	Hunter = {
		kind = "Hunter",
		displayName = "O Caçador",
		movement = "ground",
		health = 250,
		damage = 30,
		walkSpeed = 14,
		jumpPower = 50,
		thinkInterval = 0.15,
		idleInterval = 0.4,
		aggroRadius = 170,
		leashRadius = 400,
		attackRange = 95, -- alcance do rifle
		attackCooldown = 2.2,
		agentRadius = 1.6,
		agentHeight = 6.2,
		waypointReach = 2.5,
		barMaxDistance = 160,
		boss = true,
		persistent = true,
		sound = "Gunshot",
	},
	Spider = {
		kind = "Spider",
		displayName = "Aranha Gigante",
		movement = "ground",
		health = 60,
		damage = 12,
		walkSpeed = 20,
		jumpPower = 50,
		thinkInterval = 0.15,
		idleInterval = 0.5,
		aggroRadius = 150,
		leashRadius = 220,
		attackRange = 5.5,
		attackCooldown = 1.1,
		agentRadius = 2,
		agentHeight = 4.6,
		waypointReach = 3,
		barMaxDistance = 100,
		boss = false,
		persistent = false,
		sound = "Spider",
	},
	Mosquito = {
		kind = "Mosquito",
		displayName = "Mosquito Gigante",
		movement = "flying",
		health = 20,
		damage = 6,
		walkSpeed = 24,
		jumpPower = 0,
		thinkInterval = 0.05, -- voo por CFrame: 20 passos por segundo
		idleInterval = 0.3,
		aggroRadius = 150,
		leashRadius = 220,
		attackRange = 3,
		attackCooldown = 1.2,
		agentRadius = 1,
		agentHeight = 2,
		waypointReach = 2,
		barMaxDistance = 70,
		boss = false,
		persistent = false,
		sound = "Mosquito",
	},
	Plant = {
		kind = "Plant",
		displayName = "Planta Carnívora",
		movement = "static",
		health = 80,
		damage = 12,
		walkSpeed = 0,
		jumpPower = 0,
		thinkInterval = 0.15,
		idleInterval = 0.5,
		aggroRadius = 18, -- acompanha o jogador com a cabeça a partir daqui
		leashRadius = 18,
		attackRange = 9,
		attackCooldown = 1.2,
		agentRadius = 1,
		agentHeight = 6,
		waypointReach = 2,
		barMaxDistance = 90,
		boss = false,
		persistent = false,
		sound = nil,
	},
}

Kinds.Defs = Defs
Kinds.List = { "Monkey", "Lion", "Hunter", "Spider", "Mosquito", "Plant" }

function Kinds.Get(kind: string): KindDef?
	return Defs[kind]
end

return Kinds
