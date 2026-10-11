--!nonstrict
-- Valores de balanceamento e layout. Ajuste aqui sem mexer na lógica.

local GameConfig = {}

-- Nome exibido no menu. Use um nome original: "Jumanji" é marca registrada e
-- pode fazer o jogo ser removido do Roblox por violação de propriedade intelectual.
GameConfig.GAME_TITLE = "Tambores da Selva"
GameConfig.GAME_SUBTITLE = "Um jogo de tabuleiro que ganha vida"

-- Partida -----------------------------------------------------------------
GameConfig.MAX_PLAYERS_PER_MATCH = 6
GameConfig.WAIT_FOR_PLAYERS_TIMEOUT = 30 -- segundos esperando os jogadores teleportados chegarem
GameConfig.START_COUNTDOWN = 10 -- contagem antes das portas da sala inicial abrirem
GameConfig.EVENT_WARNING_TIME = 5 -- tempo entre o enigma e o evento nas jogadas seguintes
GameConfig.ROLL_COOLDOWN = 60 -- segundos entre jogadas do dado
GameConfig.BOARD_SPACES = 40 -- casas do tabuleiro (a última é a vitória)
GameConfig.DICE_COUNT = 2
GameConfig.MAX_ACTIVE_EVENTS = 4 -- eventos simultâneos (somados); o mais antigo termina se passar disso
GameConfig.EVENT_DEFAULT_RADIUS = 60
GameConfig.RETURN_TO_LOBBY_DELAY = 15
GameConfig.PLAYER_MAX_HEALTH = 100

-- Ilha / mapa ---------------------------------------------------------------
GameConfig.ISLAND_CENTER = Vector3.new(0, 0, 0)
GameConfig.ISLAND_RADIUS = 600 -- raio da parte jogável (borda da areia)
GameConfig.GROUND_Y = 10 -- altura do topo do chão da ilha
GameConfig.WATER_LEVEL_Y = 0 -- nível do mar
GameConfig.ELIMINATION_MARGIN = 8 -- passou de ISLAND_RADIUS + margem = eliminado
GameConfig.EDGE_WARNING_DISTANCE = 40 -- aviso na tela quando chega perto da borda
GameConfig.MANSION_CENTER = Vector3.new(0, 10, 0)
GameConfig.MAZE_CENTER = Vector3.new(0, 10, -300)
GameConfig.GREENHOUSE_CENTER = Vector3.new(280, 10, 40)

-- Destruição ----------------------------------------------------------------
GameConfig.DEBRIS_LIFETIME = 20 -- segundos até um pedaço sumir
GameConfig.DEBRIS_FADE_TIME = 1.5
GameConfig.MAX_DEBRIS = 500 -- limite global de pedaços; os mais antigos somem primeiro
GameConfig.FRACTURE_CHUNK_SIZE = 4 -- tamanho aproximado de cada pedaço (studs)
GameConfig.MAX_CHUNKS_PER_FRACTURE = 24

-- NPCs ------------------------------------------------------------------------
GameConfig.MAX_NPCS = 35
GameConfig.NPC_PATH_RECOMPUTE = 0.75 -- segundos entre recálculos de caminho
GameConfig.NPC_DESPAWN_FADE = 1

-- Armas -----------------------------------------------------------------------
GameConfig.WEAPON_SPAWN_COUNT = 30 -- armas espalhadas ao mesmo tempo
GameConfig.WEAPON_RESPAWN_TIME = 90

-- Lobby -----------------------------------------------------------------------
GameConfig.MAX_PARTY_SIZE = 6
GameConfig.PARTY_NAME_MAX = 24
GameConfig.MENU_AREA_ORIGIN = Vector3.new(0, 50, 0)
GameConfig.HUB_ORIGIN = Vector3.new(0, 50, 400)
GameConfig.DEMO_ROOM_ORIGIN = Vector3.new(0, 50, 1200)

-- Gráficos --------------------------------------------------------------------
-- Opções de distância de renderização (studs). O índice é salvo nas configurações.
GameConfig.RENDER_DISTANCES = { 150, 300, 600, 2000 }
GameConfig.RENDER_DISTANCE_LABELS = { "Curta", "Média", "Longa", "Máxima" }

return GameConfig
