--!nonstrict
-- Nomes de tags do CollectionService usados no projeto inteiro.

return {
	Destructible = "Destructible", -- BasePart que pode ser quebrada (paredes, móveis, pisos superiores)
	Enemy = "Enemy", -- Model de NPC inimigo (Humanoid ou atributos Health/MaxHealth)
	WeaponSpawn = "WeaponSpawn", -- Part invisível onde armas podem aparecer
	CullChunk = "CullChunk", -- Model que o cliente pode esconder pela distância de renderização
	StartRoomDoor = "StartRoomDoor", -- Model de porta da sala inicial (abre após a contagem)
	PlayerSpawn = "PlayerSpawn", -- Part onde jogadores nascem (sala inicial)
	BoardSpawn = "BoardSpawn", -- Part onde o tabuleiro aparece no início
	LooseProp = "LooseProp", -- Objeto solto que eventos podem arremessar/empurrar
	Debris = "Debris", -- Pedaço gerado por destruição (some sozinho)
	Indestructible = "Indestructible", -- Nunca deve ser quebrado (tabuleiro, chão da ilha)
	Water = "Water", -- Parts de água (oceano, água de enchente)
	Weapon = "Weapon", -- Tool de arma
	EventSkinned = "EventSkinned", -- BasePart que um evento físico já retexturizou (não muda de novo)
}
