--!nonstrict
-- Sons do jogo. Ids vazios ("") são ignorados sem erro.
-- Para trocar: procure um áudio na Toolbox/Creator Store, copie o ID
-- e coloque no formato "rbxassetid://123456".

return {
	Groups = {
		Music = "Musica",
		Effects = "Efeitos",
		Ambience = "Ambiente",
	},

	Ids = {
		-- Música e ambiente
		MenuMusic = "",
		GameMusic = "",
		Drums = "", -- tambores do tabuleiro (aviso de evento)
		Jungle = "",
		Rain = "",
		Wind = "",

		-- Interface
		UIClick = "rbxasset://sounds/electronicpingshort.wav",
		Countdown = "",

		-- Tabuleiro
		DiceRoll = "",
		PieceStep = "",
		DoorOpen = "",
		Victory = "",
		Defeat = "",

		-- Combate
		Gunshot = "",
		Shotgun = "",
		Reload = "",
		MacheteSwing = "rbxasset://sounds/swordslash.wav",
		MacheteHit = "rbxasset://sounds/swordlunge.wav",
		Equip = "rbxasset://sounds/unsheath.wav",
		Explosion = "",

		-- Criaturas e eventos
		Roar = "",
		Monkey = "",
		Spider = "",
		Mosquito = "",
		Stampede = "",
		Earthquake = "",
		Pelican = "",
		Crumble = "",
	},
}
