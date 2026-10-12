# Arquitetura: Tambores da Selva

Jogo de tabuleiro amaldiçoado (inspirado no filme de 1995) para Roblox, escrito em Luau e organizado com Rojo.
Este documento é o **contrato** entre os módulos: nomes de arquivos, APIs públicas, remotes, tags e payloads.
Quem implementa um módulo segue exatamente estas assinaturas, e quem usa um módulo pode confiar nelas.

## Convenções

- Arquivos `.luau`, cabeçalho `--!nonstrict`, indentação com tabs (StyLua: `stylua.toml`).
- Identificadores em inglês; **comentários e todo texto visível ao jogador em português do Brasil**.
- Rojo: `X.server.luau` vira Script, `X.client.luau` vira LocalScript, `X.luau` vira ModuleScript, pasta vira Folder.
- Requires:
  - código compartilhado: `require(ReplicatedStorage.Shared.Net)`, `require(ReplicatedStorage.Shared.Config.GameConfig)`, etc.
  - mesmo lado e mesma pasta: `require(script.Parent.Modulo)`.
  - servidor compartilhado entre lobby e partida: `require(ServerScriptService.ServerShared.SettingsStore)`.
- Toda geometria é gerada por código (não existem assets prontos). Use `Shared/Util/PartBuilder`.
- Servidor autoritativo: o cliente só **pede** ações; o servidor valida tudo (distância, cooldown, munição, dono do item).
- Nada de `while true do` sem `task.wait`; loops grandes de construção usam `PartBuilder.yielder()`.
- Proibido: `wait()`, `spawn()`, `delay()` (use `task.*`); `loadstring`; `getfenv`.
- **Não use Terrain para o mapa.** A ilha, o chão e o oceano são Parts. O Terrain fica livre para eventos (ex.: água da Monção).
- Somente o servidor altera `Lighting.GlobalShadows` / `ShadowSoftness` na inicialização. Depois disso, quem mexe nelas é o
  cliente (`GraphicsApplier`). Eventos podem mexer em `ClockTime`, `Brightness`, `FogEnd`/`FogStart` e `Atmosphere`.
- Verificação: `TOOLS=<bin> ROBLOX_TYPES=<globalTypes.d.luau> scripts/check.sh [arquivos...]` (luau-lsp + StyLua).

## Place único e fluxo

Um só place (`default.project.json`) contém o lobby **e** a partida. O modo de cada servidor é decidido quando ele liga,
por `Shared/PlaceMode.luau`:

```
Servidor público = LOBBY                            Servidor reservado do MESMO place = PARTIDA
  Menu: Jogar Solo | Multiplayer | Configurações  ──ReserveServer(game.PlaceId) + TeleportAsync──►  Partida
  Multiplayer → Hub: criar/entrar em salas                          Fim (vitória/derrota) ──TeleportAsync(game.PlaceId)──►
  Configurações → Áudio | Gráficos (sala de demonstração)            servidor público (lobby)
```

- `PlaceMode.Get(): "lobby" | "game"`. Servidor: `game.PrivateServerId ~= ""` e `game.PrivateServerOwnerId == 0`
  (servidor reservado) → `"game"`; qualquer outro (inclusive VIP) → `"lobby"`. No Studio vale `Places.STUDIO_MODE`.
  O servidor publica o modo em `ReplicatedStorage:GetAttribute("PlaceMode")`; no cliente, `Get()` espera esse atributo.
- **Todo script de entrada** (`LobbyMain.server`, `GameMain.server`, `MainMenu.client`, `GameClient.client`,
  `WeaponClient.client`) chama `PlaceMode.Get()` no começo e sai (`return`) se o modo não for o dele. Os ModuleScripts
  só são carregados por esses scripts, então o código do outro modo nunca roda. Script de entrada novo precisa da mesma guarda.
- `GameMain` desliga `Players.CharacterAutoLoads` logo depois da guarda (no lobby ele fica ligado).
- Teleporte sempre para `game.PlaceId`. No Studio ou com `PlaceId = 0`, o teleporte **não** é tentado: o servidor
  manda `Menu_TeleportStatus("studio", mensagem)` explicando como testar.
- `Shared/Config/Places.luau` guarda `UNIVERSE_ID`/`PLACE_ID` (referência e publicação) e `STUDIO_MODE`.
- Publicação sem Studio: `scripts/publish.sh` (Rojo + Open Cloud Place Publishing, chave em `ROBLOX_API_KEY`).

**TeleportData** (enviado pelo lobby, lido no jogo com `player:GetJoinData().TeleportData`):

```lua
{ mode = "solo" | "multiplayer", partyId = string, hostUserId = number, expectedUserIds = { number }, partyName = string }
```

Na partida, sem TeleportData (teste no Studio com `STUDIO_MODE = "game"`) = modo `"solo"` com quem estiver no servidor.

## Árvore de arquivos e dono de cada parte

```
src/shared/                          → ReplicatedStorage.Shared               (PRONTO, exceto onde indicado)
  Net.luau, Tags.luau, PlaceMode.luau
  Config/GameConfig.luau, Config/Places.luau, Config/Sounds.luau
  Audio/SoundUtil.luau
  Util/Signal.luau, Util/PartBuilder.luau
  UI/UIKit.luau
  Settings/SettingsSchema.luau
  Settings/SettingsClient.luau       [settings]
  Settings/GraphicsApplier.luau      [settings]
  Settings/AudioApplier.luau         [settings]
src/serverShared/                    → ServerScriptService.ServerShared
  SettingsStore.luau                 [settings]
src/lobby/server/                    → ServerScriptService.Lobby
  LobbyMain.server.luau              [lobby]
  LobbyWorld.luau                    [lobby]
  PartyService.luau                  [lobby]
  TeleportHandler.luau               [lobby]
  DemoRoom.luau                      [settings]
src/lobby/client/                    → StarterPlayerScripts.Lobby
  MainMenu.client.luau               [lobby]
  HubUI.luau (+ outros módulos)      [lobby]
  SettingsUI.luau                    [settings]
src/game/server/                     → ServerScriptService.Game
  GameMain.server.luau               [flow]
  CombatUtil.luau                    (PRONTO)
  MatchService.luau, BoardService.luau, BoardModel.luau, EventService.luau, BoundaryService.luau  [flow]
  DestructionService.luau            [physical]
  EventHelpers/GroundUtil.luau       (PRONTO)
  EventHelpers/*                     [npc] e [physical] (prefixe o nome: NpcX / PhysX para não colidir)
  Map/MapBuilder.luau (+ módulos)    [map]
  Events/<Evento>.luau               [npc]: Monkeys, Lion, Hunter, Spiders, Mosquitos
                                     [physical]: Stampede, Monsoon, Earthquake, Vines, Quicksand, Tornado, Pelican
  NPC/NPCService.luau (+ módulos)    [npc]
  Weapons/WeaponService.luau (+ módulos) [weapons]
src/game/client/                     → StarterPlayerScripts.Game
  GameClient.client.luau, LoadingScreen.luau, HUD.luau, RiddleUI.luau, FxClient.luau, Spectate.luau, BoardClient.luau [flow]
  WeaponClient.client.luau (+ pasta Weapons/) [weapons]
```

## Remotes (`Shared/Net.luau`)

Sempre `Net.event(Net.Names.X)` / `Net.func(Net.Names.X)`. O servidor cria o remote na primeira chamada; o cliente espera.
**Todo servidor que usa um remote deve chamá-lo no `Init`** (para ele existir antes do cliente pedir).

| Nome | Tipo | Direção | Argumentos |
|---|---|---|---|
| Settings_Get | RemoteFunction | C→S | `() -> Settings` |
| Settings_Save | RemoteEvent | C→S | `(settings)`; o servidor sanitiza e limita a 1 gravação a cada 6 s por jogador |
| Menu_RequestSolo | RemoteEvent | C→S | `()` |
| Menu_TeleportStatus | RemoteEvent | S→C | `(status: "teleporting"\|"failed"\|"studio", message: string)` |
| Hub_Enter / Hub_Leave | RemoteEvent | C→S | `()` |
| Party_Create | RemoteEvent | C→S | `({ name, privacy: "public"\|"friends", maxPlayers })` |
| Party_Join | RemoteEvent | C→S | `(partyId)` |
| Party_Leave / Party_Start | RemoteEvent | C→S | `()` |
| Party_Update | RemoteEvent | S→C | `(PartyListPayload)` |
| Party_GetList | RemoteFunction | C→S | `() -> PartyListPayload` |
| Game_ClientReady | RemoteEvent | C→S | `()` depois do carregamento |
| Game_State | RemoteEvent | S→C | `(GameStatePayload)` |
| Board_Status | RemoteEvent | S→C | `(BoardStatusPayload)` |
| Board_RollRequest | RemoteEvent | C→S | `()` |
| Board_DropRequest | RemoteEvent | C→S | `()` o carregador solta o tabuleiro |
| Board_Riddle | RemoteEvent | S→C | `(RiddlePayload)` |
| Event_Started | RemoteEvent | S→C | `(EventInfoPayload)` |
| Event_Ended | RemoteEvent | S→C | `(instanceId: string)` |
| Player_Eliminated | RemoteEvent | S→C | `(userId, reason: string)` |
| Fx_Play | RemoteEvent | S→C | `(kind, params)`, ver abaixo |
| Weapon_Fire | RemoteEvent | C→S | `(tool, origin: Vector3, direction: Vector3)` (direction unitário) |
| Weapon_Melee | RemoteEvent | C→S | `(tool)` |
| Weapon_Throw | RemoteEvent | C→S | `(tool, target: Vector3)` |
| Weapon_Reload | RemoteEvent | C→S | `(tool)` |
| Notify | RemoteEvent | S→C | `(text, kind?: "info"\|"warning"\|"danger"\|"success")`: o cliente mostra `UIKit.Toast` |
| Game_EndCutscene | RemoteEvent | S→C | `(EndCutscenePayload)` cutscene final + melhor da partida |
| Char_MoveState | RemoteEvent | C→S | `("none"\|"climb")` vira o atributo `MoveState` do personagem |
| Leaderboard_Get | RemoteFunction | C→S | `() -> LeaderboardPayload` |
| Leaderboard_Update | RemoteEvent | S→C | `(LeaderboardPayload)` |

### Payloads

```lua
-- Lobby
type PartySummary = { id: string, name: string, hostUserId: number, hostName: string, privacy: "public"|"friends",
                      maxPlayers: number, members: { { userId: number, name: string } } }
type PartyListPayload = { parties: { PartySummary }, -- somente as que ESTE jogador pode ver/entrar
                          myPartyId: string? }

-- Jogo
type GameStatePayload = { phase: "Loading"|"WaitingPlayers"|"Intro"|"Countdown"|"Playing"|"Victory"|"Defeat",
                          countdown: number?, space: number, totalSpaces: number,
                          alive: number, total: number, message: string? }
type BoardStatusPayload = { carrierUserId: number?, canRoll: boolean, cooldownEndsAt: number?, -- workspace:GetServerTimeNow()
                            space: number, locked: boolean, rolling: boolean }
type RiddlePayload = { text: string, space: number, dice: { number }, countdown: number, isFirst: boolean }
type EventInfoPayload = { id: string, eventId: string, name: string, position: Vector3, radius: number,
                          duration: number, regionName: string? }
```

### Fx_Play (tratado em `game/client/FxClient.luau`)

| kind | params | efeito no cliente |
|---|---|---|
| `"shake"` | `{ intensity: number (0.2–2), duration: number, origin: Vector3?, radius: number? }` | treme a câmera (fraco longe da origem) |
| `"tracer"` | `{ from: Vector3, to: Vector3, color: Color3?, width: number?, shooterUserId: number? }` | traço de tiro rápido (o atirador ignora o próprio eco, porque já desenhou localmente) |
| `"knockback"` | `{ velocity: Vector3 }` | soma velocidade no HumanoidRootPart do jogador local |
| `"flash"` | `{ color: Color3?, duration: number? }` | tela pisca (ex.: explosão perto) |

Efeitos de longa duração (chuva, poeira, fumaça) são criados no **servidor** com ParticleEmitter (replicam sozinhos).

## Tags (`Shared/Tags.luau`)

`Destructible`, `Indestructible`, `Enemy`, `WeaponSpawn`, `CullChunk`, `StartRoomDoor`, `PlayerSpawn`, `BoardSpawn`,
`LooseProp`, `Debris`, `Water`, `Weapon`. Veja os comentários no arquivo.

- O chão térreo da ilha e da mansão, o oceano e o tabuleiro **não** são `Destructible`.
- Paredes (internas e externas), pisos do 2º andar, cercas vivas, vidro da estufa e móveis grandes **são** `Destructible`.
- Objetos pequenos (cadeiras, vasos, livros) são `LooseProp`. Eles nascem **ancorados** (para não pesar na física) e
  explosões ou eventos os **desancoram** quando os atingem (`DestructionService` faz isso no `Explode`/`Fracture`).
- Cada cômodo, setor do labirinto, a estufa e grupos de árvores são `Model` com tag `CullChunk`.

## Atributos

- `Player:GetAttribute("Eliminated")`: `true` quando eliminado (sem respawn).
- `Player:GetAttribute("LastDamageSource")`: texto da última fonte de dano (motivo da eliminação).
- Inimigo sem Humanoid: `Model:GetAttribute("Health")` / `"MaxHealth"`.
- `workspace:GetAttribute("MapReady")`: `true` quando o MapBuilder terminou.
- Parts em `workspace.Map.Regions`: atributo `RegionName` (string) e `Floor` (0 = térreo/externo, 1 = 2º andar).

## Pastas no workspace (jogo)

- `workspace.Map`: tudo do mapa. Inclui `Map.Regions` (Folder com Parts invisíveis, uma por região nomeada).
- `workspace.Debris`: pedaços de destruição (criado pelo DestructionService).
- `workspace.ActiveEvents`: um Folder por evento ativo (`ctx.folder`), destruído no fim do evento.
- `workspace.NPCs`: NPCs vivos.
- `workspace.Board`: o tabuleiro, os dados e a peça.

Pastas no workspace (lobby): `workspace.LobbyMarkers` com Parts invisíveis e ancoradas `MenuCamera`, `MenuSpawn`,
`HubSpawn`, `HubCamera` (do [lobby]) e `DemoCamera` (do [settings]). O CFrame de cada Part é a posição/orientação
desejada da câmera ou do spawn. Quem chega primeiro cria a pasta: `workspace:FindFirstChild("LobbyMarkers") or Instance.new(...)`.

## APIs dos módulos

### [settings] `Shared/Settings/SettingsClient.luau` (somente cliente)

```lua
SettingsClient.Init()                         -- idempotente; busca no servidor (Settings_Get, com timeout 8 s → padrão),
                                              -- aplica áudio e gráficos e inicia o GraphicsApplier
SettingsClient.Get(): Settings                -- cópia
SettingsClient.Set(settings: Settings)        -- sanitiza, aplica na hora, salva com debounce (1,5 s)
SettingsClient.Changed: Signal                -- (settings)
SettingsClient.IsLoaded(): boolean
```

### [settings] `Shared/Settings/GraphicsApplier.luau` (somente cliente)

```lua
GraphicsApplier.Init()                                 -- idempotente; escuta DescendantAdded do workspace (em lote)
GraphicsApplier.Apply(graphics: GraphicsSettings)
GraphicsApplier.SetCullingEnabled(enabled: boolean)    -- false durante a varredura de pré-carregamento
```

- **Sombras**: `off` → `Lighting.GlobalShadows = false`; `low` → sombras ligadas, `ShadowSoftness = 1`, parts pequenas
  (maior dimensão < 8) e luzes sem sombra; `high` → tudo ligado e `ShadowSoftness = 0.2`. Guarde os valores originais.
- **Redução de textura**: materiais (exceto Glass, Neon, ForceField, SmoothPlastic) viram `SmoothPlastic` localmente; Decals e
  Textures ficam invisíveis. Restaura os originais quando desligar.
- **Distância de renderização**: Models com tag `CullChunk` mais longe da câmera que `GameConfig.RENDER_DISTANCES[i]`
  ficam invisíveis via `LocalTransparencyModifier = 1` nas parts (checagem a cada ~0,4 s, só altera quando o estado muda).
- **Pré-carregar**: só é usado pela tela de carregamento do jogo.

### [settings] `Shared/Settings/AudioApplier.luau`: `AudioApplier.Apply(audio: AudioSettings)` ajusta o volume dos SoundGroups.

### [settings] `ServerShared/SettingsStore.luau`

```lua
SettingsStore.Init()                      -- cria Settings_Get/Settings_Save; DataStore "PlayerSettings_v1" (chave "u_<userId>")
SettingsStore.Get(player): Settings
```

Funciona sem acesso ao DataStore (Studio sem API habilitada): usa o padrão e avisa uma vez no Output.

### [settings] `Lobby/DemoRoom.luau` (servidor do lobby)

`DemoRoom.Build()`: constrói a sala de demonstração em `GameConfig.DEMO_ROOM_ORIGIN` e cria `LobbyMarkers.DemoCamera`.

### [settings] `Lobby/SettingsUI.luau` (cliente do lobby)

`SettingsUI.Open(onClose: () -> ())` / `SettingsUI.Close()`. Ao abrir a aba Gráficos, a câmera vai para `DemoCamera` e
o painel fica de lado para a sala aparecer. Ao fechar, restaura `CameraType`/`CFrame` anteriores e chama `onClose`.

### [lobby] `Lobby/LobbyMain.server.luau`

Ordem: `SoundUtil.EnsureGroups()`, iluminação, `LobbyWorld.Build()`, `DemoRoom.Build()`, `SettingsStore.Init()`,
`PartyService.Init()`, `TeleportHandler.Init()`.

### [lobby] `Lobby/TeleportHandler.luau`

```lua
TeleportHandler.Init()
TeleportHandler.TeleportToGame(players: { Player }, data: TeleportData): (boolean, string?)
```

### [map] `Game/Map/MapBuilder.luau`

```lua
export type Region = { name: string, cframe: CFrame, size: Vector3, floor: number }
export type MapInfo = {
	islandCenter: Vector3, islandRadius: number, groundY: number, waterLevelY: number,
	startRoom: { cframe: CFrame, size: Vector3 },
	boardSpawn: CFrame,            -- em cima de uma mesa na sala inicial
	playerSpawns: { CFrame },      -- dentro da sala inicial (no mínimo 6)
	weaponSpawns: { BasePart },    -- Parts com tag WeaponSpawn (no mínimo 60 espalhadas)
	regions: { Region },
	mapFolder: Folder,             -- workspace.Map
}
MapBuilder.Build(): MapInfo                 -- constrói tudo; no fim, workspace:SetAttribute("MapReady", true)
MapBuilder.OpenStartDoors()                 -- abre (tween) as portas da sala inicial
MapBuilder.GetRegionAt(position: Vector3): Region?
```

### [flow] `Game/BoardService.luau`

```lua
BoardService.Init(mapInfo)
BoardService.Rolled: Signal          -- ({ dice: {number}, total: number, fromSpace: number, space: number,
                                     --    position: Vector3, isFinal: boolean, isFirst: boolean })
BoardService.SetRollingEnabled(enabled: boolean)
BoardService.StartCooldown(seconds: number)
BoardService.GetSpace(): number
BoardService.GetBoardModel(): Model
BoardService.GetBoardPosition(): Vector3
BoardService.GetCarrier(): Player?
BoardService.Drop(position: Vector3?)    -- o carregador solta o tabuleiro (no chão)
BoardService.SetLocked(locked: boolean)  -- travado: ninguém pega nem joga (ex.: pelicano carregando)
BoardService.PlaceAt(cframe: CFrame)     -- coloca o tabuleiro no chão nessa posição (solta o carregador)
BoardService.ShowRiddle(text: string)    -- texto no "vidro" central do tabuleiro
BoardService.IsRolling(): boolean         -- true enquanto dados/peça animam (não mover o tabuleiro)
```

### [flow] `Game/EventService.luau`

Carrega todo ModuleScript **filho direto** de `Game/Events` que tenha `Id` e `Start`.

```lua
EventService.Init(mapInfo)
EventService.GetDefinition(eventId): EventDefinition?
EventService.EventForSpace(space: number): string   -- plano sorteado no Init (respeita MinSpace e Weight)
EventService.GetRiddle(eventId): string
EventService.Start(eventId, position: Vector3): string  -- id do evento; ele dura até StopAll (fim da partida)
EventService.StopAll()
EventService.GetActive(): { EventInfoPayload }
```

**Focos (eventos até o fim da partida):** cada evento roda em focos. Um foco é uma chamada de `Start` com o seu
próprio `EventContext` (pasta, `instanceId` único, usado como groupId dos NPCs). Ele termina no `Duration` (físicos) ou
quando chama `ctx.finish()` (NPC: toda a onda morreu) e, depois de `RestartDelay`, recomeça em outro ponto:
físicos em qualquer lugar da ilha ou perto de um jogador, NPC perto de um jogador, `Spread = false` no tabuleiro.
Físicos têm `Sites` focos ao mesmo tempo (padrão `GameConfig.PHYSICAL_EVENT_SITES`); o total no mapa é limitado por
`GameConfig.MAX_EVENT_SITES`. Ao começar um foco físico com `Skin`, `EventHelpers/SurfaceSkin` retextura os blocos
em volta (tag `EventSkinned`: nunca mudam de novo; partes enormes ganham placas finas em `Map.PlacasDeEvento`).
O HUD recebe `duration = -1` (até o fim).

### Formato de um evento (`Game/Events/<Nome>.luau`)

```lua
return {
	Id = "Monkeys",                  -- igual ao nome do arquivo
	DisplayName = "Macacos Saqueadores",
	Kind = "npc",                    -- "npc" | "physical"
	Riddles = { "...", "..." },      -- 2 ou mais enigmas ORIGINAIS em pt-BR, rimados, que dão pistas do evento
	Weight = 1,                      -- chance relativa
	MinSpace = 1,                    -- primeira casa em que pode cair (eventos fortes mais para o fim)
	Duration = 90,                   -- segundos de cada foco; ao fim o EventService chama o cleanup e recomeça
	Radius = 60,
	Sites = 3,                       -- opcional: focos ao mesmo tempo (padrão: físicos 3, NPC 1)
	Spread = false,                  -- opcional: sempre no tabuleiro (pelicano)
	RestartDelay = { 3, 8 },         -- opcional: pausa entre focos (padrão: físicos 3–8 s, NPC 25–45 s)
	Skin = { Material = Enum.Material.Sand, Colors = { Color3.fromRGB(196, 162, 106) } }, -- opcional (físicos)
	Start = function(ctx: EventContext): () -> ()   -- NÃO pode ceder (yield); use task.spawn. Retorna cleanup idempotente.
}
```

```lua
type EventContext = {
	instanceId: string, eventId: string,
	position: Vector3,               -- onde o dado foi jogado
	radius: number, duration: number,
	mapInfo: MapInfo,
	folder: Folder,                  -- workspace.ActiveEvents.<instanceId>; destruído depois do cleanup
	random: Random,
	isActive: () -> boolean,         -- false depois do fim; loops do evento devem checar isto
	finish: () -> (),                -- termina o evento antes do tempo (ex.: todos os inimigos mortos)
	services: {
		Destruction: DestructionService, NPC: NPCService, Board: BoardService,
		Combat: CombatUtil, Map: MapBuilder, Ground: GroundUtil,
	},
}
```

### [physical] `Game/DestructionService.luau`

```lua
DestructionService.Init()
DestructionService.IsDestructible(part: BasePart): boolean
DestructionService.Fracture(part: BasePart, impactPoint: Vector3, impulse: number?): { BasePart }
	-- quebra a part em pedaços (grade ≈ FRACTURE_CHUNK_SIZE, no máx. MAX_CHUNKS_PER_FRACTURE);
	-- pedaços perto do impacto soltam e voam, os longe continuam ancorados (parede parcialmente quebrada)
DestructionService.Explode(position: Vector3, radius: number, force: number, opts: {
	damagePlayers: number?, damageEnemies: number?, attacker: Player?, source: string?, visual: boolean?,
}?)
DestructionService.RegisterDebris(part: BasePart, lifetime: number?)
	-- qualquer part temporária com física vai para workspace.Debris, some com fade e respeita MAX_DEBRIS
```

### [npc] `Game/NPC/NPCService.luau`

```lua
NPCService.Init()
NPCService.Spawn(kind: string, cframe: CFrame, opts: { groupId: string?, health: number?, damage: number? }?): Model?
	-- kinds: "Monkey", "Lion", "Hunter", "Spider", "Mosquito", "Plant" (planta carnívora parada)
	-- retorna nil se atingir GameConfig.MAX_NPCS
NPCService.DespawnGroup(groupId: string)
NPCService.CountAlive(groupId: string?): number
NPCService.DespawnAll()
```

### [weapons] `Game/Weapons/WeaponService.luau`

```lua
WeaponService.Init(mapInfo)
WeaponService.GiveWeapon(player: Player, kind: "Machete"|"Revolver"|"Shotgun"|"Dynamite"): Tool?
```

### [flow] `Game/MatchService.luau`

Fases: `Loading` → `WaitingPlayers` → `Intro` (primeira jogada liberada) → `Countdown` (10 s) → portas abrem →
`Playing` → `Victory` | `Defeat` → volta ao lobby.

## Personagem, câmera e estatísticas

- `ServerShared/CharacterService`: cria o personagem R6 de cada jogador com `CreateHumanoidModelFromDescription`
  (`CharacterAutoLoads` fica desligado nos dois modos). No lobby renasce sozinho; na partida quem cria é o MatchService.
  Recebe `Char_MoveState` e grava o atributo `MoveState` ("climb") no personagem.
- `Shared/Character/R6Animator` (cliente): animação procedural de TODOS os personagens R6 via `Motor6D.Transform`.
- `Shared/Character/FirstPerson` (cliente): `LockFirstPerson`, corpo visível, balanço da câmera. Ligado no hub e na
  partida; desligado no menu, para eliminados (espectador) e na cutscene final. No hub, com o painel de salas aberto, um
  botão `Modal` solta o mouse (Q esconde/mostra o painel).
- `Shared/Character/Movement` (cliente): corrida com estamina e escalada (só na partida).
- `Game/MatchStats`: abates (sinal `CombatUtil.EnemyKilled`, golpe final) e jogadas (`Rolled.rollerUserId`).
  No fim, `Game_EndCutscene` leva `{ victory, boardPosition, results, bestUserId, killPoints, rollPoints }` e
  `ServerShared/GlobalStats.RecordMatch` soma no placar global (OrderedDataStore `PlacarGlobal_Pontos_v1` +
  DataStore `PlacarGlobal_Detalhes_v1`). No lobby, `LeaderboardService` lê o topo a cada 60 s (`Leaderboard_Get` /
  `Leaderboard_Update`) e escreve no quadro do hub.
- O tabuleiro tem um `Highlight` branco (`AlwaysOnTop`, só contorno).

## Controles

| Ação | Teclado | Celular/console |
|---|---|---|
| Interagir (pegar tabuleiro, pegar arma) | `E` (ProximityPrompt) | toque no prompt |
| Jogar o dado (carregando o tabuleiro ou perto dele) | `T` | botão "Jogar dado" na tela |
| Soltar o tabuleiro | `G` | botão "Soltar" |
| Atirar / golpear / arremessar | clique | toque (`Tool.Activated`) |
| Recarregar | `R` | botão "Recarregar" |
| Espectador: próximo/anterior | `E` / `Q` | botões ◀ ▶ |

## Regras do jogo (resumo)

1. Todos nascem na **Sala de Jogos** (sala inicial, portas fechadas). O tabuleiro está sobre a mesa.
2. Alguém joga o dado: os dados rolam com física, a **peça única do grupo** anda, aparece o **enigma** do evento e
   começa a contagem de 10 s. As portas se abrem e o evento acontece **onde o tabuleiro está**.
3. O tabuleiro pode ser carregado (preso nas costas) entre os cenários. A cada `ROLL_COOLDOWN` s o dado fica disponível.
   Cada nova jogada **soma** um evento aos que já estão ativos; os eventos duram até o fim da partida.
4. Chegar à última casa = vitória: todos os eventos acabam.
5. Morreu ou passou da borda da ilha = eliminado (assiste aos outros). Todos eliminados = derrota.
6. Armas espalhadas pelo mapa (facão, revólver, espingarda, dinamite) ajudam contra os inimigos. Não há fogo amigo.
7. O cenário quebra; os pedaços somem depois de `DEBRIS_LIFETIME` s para não pesar no aparelho.
8. Skins de peça: **não** implementar agora (deixar só um ponto de extensão comentado no BoardModel).
