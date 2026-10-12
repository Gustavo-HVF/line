--!nonstrict
-- Números e textos de cada arma (servidor).
-- O cliente não lê este módulo: o que ele precisa (alcance, cadência, munição...) vai como atributo da Tool
-- (ver ToolFactory). Para balancear, ajuste só aqui.

local Definitions = {}

export type WeaponDef = {
	kind: string, -- "Machete" | "Revolver" | "Shotgun" | "Dynamite"
	category: string, -- "melee" | "gun" | "throw"
	displayName: string,
	article: string, -- artigo usado nas mensagens ("o" / "a")
	description: string, -- texto curto do ProximityPrompt
	tooltip: string,
	cooldown: number, -- segundos entre usos (cadência)
	range: number, -- studs
	spawnWeight: number, -- chance relativa de aparecer nos pontos de arma

	-- Corpo a corpo
	damage: number?,
	coneAngle: number?, -- abertura total do cone à frente do HumanoidRootPart (graus)
	maxTargets: number?,
	maxHeightDifference: number?,
	swingSound: string?,
	hitSound: string?,

	-- Armas de fogo
	maxAmmo: number?,
	reloadTime: number?,
	pellets: number?,
	spread: number?, -- meia-abertura do cone de espalhamento (graus)
	sound: string?,
	tracerColor: Color3?,
	tracerWidth: number?,
	propPush: number?, -- velocidade dada a um objeto solto atingido (por projétil)
	fractureRange: number?, -- até esta distância o tiro pode quebrar parts Destructible
	fractureImpulse: number?,
	fractureMinPellets: number?, -- projéteis na mesma part para ela quebrar

	-- Arremesso
	charges: number?, -- cargas por coleta
	maxCharges: number?,
	fuseTime: number?,
	flightSpeed: number?, -- velocidade horizontal média do arremesso (studs/s)
	blastRadius: number?,
	blastForce: number?,
	damageEnemies: number?,
	source: string?,
}

-- Regras gerais ---------------------------------------------------------------------------

Definitions.MAX_WEAPONS_PER_PLAYER = 3
Definitions.ORIGIN_MAX_DISTANCE = 10 -- a origem do tiro pode estar até isto da cabeça do atirador
Definitions.COOLDOWN_TOLERANCE = 0.85 -- aceita pedidos um pouco antes da cadência (oscilação da rede)
Definitions.THROW_RANGE_TOLERANCE = 4 -- folga no alcance do arremesso (o jogador anda durante o envio)
Definitions.PICKUP_DISTANCE = 12 -- distância máxima (servidor) para pegar uma arma do chão
Definitions.MAX_RAY_PIERCE = 4 -- parts invisíveis e sem colisão atravessadas por um tiro

-- Armas que sempre aparecem nos pontos da sala inicial (alternadas).
Definitions.START_ROOM_KINDS = { "Machete", "Revolver" }

-- Ordem usada para garantir variedade na primeira distribuição.
Definitions.ORDER = { "Machete", "Revolver", "Shotgun", "Dynamite" }

Definitions.Weapons = {
	Machete = {
		kind = "Machete",
		category = "melee",
		displayName = "Facão",
		article = "o",
		description = "Corpo a corpo",
		tooltip = "Golpeia tudo o que estiver bem à sua frente.",
		cooldown = 0.55,
		range = 8,
		spawnWeight = 3,
		damage = 35,
		coneAngle = 70,
		maxTargets = 3,
		maxHeightDifference = 7,
		swingSound = "MacheteSwing",
		hitSound = "MacheteHit",
	},
	Revolver = {
		kind = "Revolver",
		category = "gun",
		displayName = "Revólver",
		article = "o",
		description = "6 balas",
		tooltip = "6 balas, recarga rápida e longo alcance.",
		cooldown = 0.35,
		range = 300,
		spawnWeight = 3,
		damage = 34,
		maxAmmo = 6,
		reloadTime = 1.6,
		pellets = 1,
		spread = 0,
		sound = "Gunshot",
		tracerColor = Color3.fromRGB(255, 226, 140),
		tracerWidth = 0.12,
		propPush = 28,
	},
	Shotgun = {
		kind = "Shotgun",
		category = "gun",
		displayName = "Espingarda",
		article = "a",
		description = "2 cartuchos",
		tooltip = "Dois cartuchos devastadores de perto. Quebra paredes!",
		cooldown = 0.5,
		range = 90,
		spawnWeight = 2,
		damage = 11, -- por projétil
		maxAmmo = 2,
		reloadTime = 2.2,
		pellets = 8,
		spread = 6,
		sound = "Shotgun",
		tracerColor = Color3.fromRGB(255, 190, 110),
		tracerWidth = 0.07,
		propPush = 9,
		fractureRange = 25,
		fractureImpulse = 14,
		fractureMinPellets = 2,
	},
	Dynamite = {
		kind = "Dynamite",
		category = "throw",
		displayName = "Dinamite",
		article = "a",
		description = "3 cargas",
		tooltip = "Arremesse e corra! Explode depois de 2,5 s.",
		cooldown = 0.9,
		range = 60,
		spawnWeight = 2,
		charges = 3,
		maxCharges = 9,
		fuseTime = 2.5,
		flightSpeed = 42,
		blastRadius = 14,
		blastForce = 80,
		damageEnemies = 120,
		source = "Dinamite",
	},
} :: { [string]: WeaponDef }

-- Devolve a definição de um tipo (ou nil se o valor não for um tipo conhecido).
function Definitions.Get(kind: any): WeaponDef?
	if type(kind) ~= "string" then
		return nil
	end
	return Definitions.Weapons[kind]
end

-- Sorteia um tipo respeitando spawnWeight.
function Definitions.RandomKind(random: Random): string
	local total = 0
	for _, kind in Definitions.ORDER do
		total += Definitions.Weapons[kind].spawnWeight
	end
	local roll = random:NextNumber(0, total)
	for _, kind in Definitions.ORDER do
		roll -= Definitions.Weapons[kind].spawnWeight
		if roll <= 0 then
			return kind
		end
	end
	return Definitions.ORDER[#Definitions.ORDER]
end

return Definitions
