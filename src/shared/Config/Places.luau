--!nonstrict
-- O jogo usa um ÚNICO place. O mesmo arquivo roda de dois jeitos:
--   * servidor público  → LOBBY (menu, hub, configurações);
--   * servidor reservado (criado pelo lobby com TeleportService:ReserveServer) → PARTIDA.
-- Quem decide o modo de cada servidor é Shared/PlaceMode. O teleporte usa sempre game.PlaceId,
-- então os IDs abaixo servem só de referência (e para o script de publicação).

return {
	UNIVERSE_ID = 2327303402,
	PLACE_ID = 6305250851,

	-- No Studio não existe servidor reservado. Troque para "game" para testar a partida direto no Play.
	STUDIO_MODE = "lobby", -- "lobby" | "game"
}
