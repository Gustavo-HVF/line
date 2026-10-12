# Tambores da Selva

Jogo de tabuleiro amaldiçoado para Roblox, inspirado no filme de 1995. Todo o código é Luau, organizado com
[Rojo](https://rojo.space). Mapa, interface e modelos são gerados por código, então não há assets para importar.

> **Sobre o nome:** "Jumanji" é marca registrada. Usar o nome ou a marca no Roblox pode fazer o jogo ser removido.
> O título fica em `src/shared/Config/GameConfig.luau` (`GAME_TITLE`).

## O que tem no jogo

O jogo usa **um único place**. Servidores públicos rodam o **lobby**; quando alguém começa uma partida, o lobby
reserva um servidor do mesmo place (`TeleportService:ReserveServer`) e teleporta o grupo para lá. Servidor
reservado roda a **partida** (`src/shared/PlaceMode.luau` decide isso quando o servidor liga).

**Lobby (servidores públicos)**
- Menu principal com **Jogar Solo**, **Multiplayer** e **Configurações**, sobre um cenário de sótão com o tabuleiro.
- **Multiplayer:** leva ao hub (salão de templo na selva). Lá você pode **Criar servidor** escolhendo:
  - nome da sala;
  - privacidade: **Pública** (qualquer pessoa do servidor vê e entra) ou **Só amigos**;
  - máximo de jogadores.
  O dono inicia a partida e o grupo inteiro é teleportado junto.
- **Configurações:**
  - **Áudio:** volume geral, música, efeitos e ambiente.
  - **Gráficos:** a câmera vai para uma **sala de demonstração** e cada opção muda a sala na hora:
    - sombras (desligadas, baixas ou altas);
    - redução de texturas;
    - distância de renderização: marcos a 100, 200, 400, 800 e 1500 studs somem conforme a opção;
    - pré-carregar o jogo.
  - As escolhas são salvas no DataStore.

**Partida (servidor reservado)**
- Uma ilha com:
  - **mansão de 2 andares** com 31 cômodos, incluindo uma biblioteca de pé-direito duplo com mezanino;
  - **labirinto de cerca viva** (gerado aleatoriamente a cada partida);
  - **estufa** grande, jardins e praia.
- **Passar da borda da ilha elimina.**
- Todos começam trancados na **Sala de Jogos** com o tabuleiro sobre a mesa. Ao jogar o dado:
  1. os dados rolam com física e a **peça única do grupo** anda;
  2. aparece um **enigma** do que vai acontecer;
  3. há **10 s** de contagem;
  4. as portas se abrem e o evento acontece **onde o tabuleiro está**.
- O tabuleiro pode ser **carregado nas costas** entre os cenários. A cada 60 s o dado libera de novo, e cada jogada
  **soma** um novo evento aos que já estão ativos (até 4 ao mesmo tempo). Chegar à última casa (40) vence.
- **Cenário destrutível:** paredes, pisos do 2º andar, cercas vivas, vidros e móveis quebram em pedaços. Os pedaços somem
  depois de 20 s (com limite global) para não pesar no aparelho.
- **Armas espalhadas** pelo mapa: Facão, Revólver, Espingarda e Dinamite. Não há fogo amigo.
- **12 eventos:**

| Evento | Tipo | A partir da casa |
|---|---|---|
| Macacos Saqueadores | NPCs | 1 |
| Enxame de Mosquitos | NPCs | 1 |
| Pelicano Ladrão (rouba o tabuleiro e voa para longe) | físico | 2 |
| Areia Movediça | físico | 2 |
| Cipós Carnívoros (com plantas carnívoras) | físico + NPCs | 3 |
| Aranhas Gigantes | NPCs | 4 |
| Monção (chuva e enchente de verdade, dá para nadar e afogar) | físico | 6 |
| Debandada (rinocerontes atravessando paredes) | físico | 8 |
| Tornado | físico | 10 |
| Leão Faminto | NPC | 12 |
| Terremoto | físico | 14 |
| O Caçador | NPC | 18 |

- Morreu ou caiu da ilha: vira espectador. Todos eliminados = derrota. No fim, todos voltam ao lobby.
- Skins de peça ainda **não** existem. Há um ponto de extensão comentado em `src/game/server/BoardModel.luau`.

### Controles

| Ação | PC | Celular / console |
|---|---|---|
| Pegar tabuleiro / arma | `E` (prompt) | tocar no prompt |
| Jogar o dado | `T` | botão na tela |
| Soltar o tabuleiro | `G` | botão na tela |
| Atirar / golpear / arremessar | clique | toque |
| Recarregar | `R` | botão na tela |
| Espectador: trocar jogador | `Q` / `E` | botões ◀ ▶ |

## Como abrir no Roblox Studio

### Opção A: arquivo pronto (mais simples)

Abra `builds/TamboresDaSelva.rbxlx` no Roblox Studio (Arquivo → Abrir) e aperte **Play**: abre o lobby.
No Studio não existe servidor reservado, então o teleporte não acontece. Para testar a **partida** direto no
Studio, troque `STUDIO_MODE = "lobby"` para `"game"` em `src/shared/Config/Places.luau` (sem teleporte, ela
começa em modo solo).

O arquivo de `builds/` é gerado a partir de `src/`. Se você mudar o código, gere de novo com o Rojo:
```
rojo build default.project.json -o builds/TamboresDaSelva.rbxlx
```

### Opção B: Rojo ao vivo (recomendado para continuar desenvolvendo)

1. Instale o [Rokit](https://github.com/rojo-rbx/rokit) e rode `rokit install` na pasta do projeto (instala Rojo, StyLua e luau-lsp).
2. Instale o plugin do Rojo no Studio (`rojo plugin install`).
3. Rode `rojo serve`, abra um place vazio no Studio e clique em **Connect** no plugin.
4. Edite os arquivos em `src/`; o Studio atualiza sozinho.

## Publicar (para o teleporte funcionar)

O teleporte do lobby para a partida **não funciona no Studio**, só no jogo publicado. No Studio, o botão mostra uma
mensagem explicando isso.

### Pela API Open Cloud (sem Studio)

`scripts/publish.sh` gera o place com o Rojo e envia direto para a experiência (universe `2327303402`,
place `6305250851`):
```
ROBLOX_API_KEY=<sua chave> scripts/publish.sh          # publica para todo mundo
ROBLOX_API_KEY=<sua chave> scripts/publish.sh Saved    # só salva uma versão, sem publicar
```
A chave é criada em [Creator Hub → Open Cloud → API Keys](https://create.roblox.com/dashboard/credentials) com a
permissão **universe-places → write** para esta experiência. Nunca coloque a chave no código ou no repositório.

### Pelo Studio

Abra `builds/TamboresDaSelva.rbxlx` e use **Arquivo → Publicar no Roblox como…** escolhendo o place existente.

Em **Configurações do jogo → Segurança**, ative **Enable Studio Access to API Services** se quiser que as
configurações sejam salvas também nos testes do Studio.

## Testar pelo celular

1. Depois de publicar, abra o app do Roblox no celular, procure o jogo pelo nome ou abra
   `https://www.roblox.com/games/6305250851` e toque em **Jogar**.
2. Se o jogo estiver **privado**, só você (dono) consegue entrar. Para amigos testarem, deixe-o público em
   Creator Hub → experiência → **Configurações → Público**.
3. **Jogar Solo** reserva um servidor e leva você para a partida; **Multiplayer → Criar servidor → Iniciar** faz o
   mesmo com o grupo inteiro. No fim da partida todos voltam para um servidor de lobby.

## Ver erros (console)

- **No jogo:** digite `/console` no chat (ou aperte **F9** no PC). No celular, abra o chat, envie `/console` e
  a janela **Developer Console** aparece.
  - Aba **Client**: erros do seu aparelho (interface, câmera, armas).
  - Aba **Server**: erros do servidor (mapa, eventos, NPCs, teleporte). Só aparece para o dono do jogo.
  - Os avisos do jogo começam com o nome do módulo entre colchetes, por exemplo `[GameMain]`, `[MatchService]`,
    `[TeleportHandler]`. Ao entrar, o servidor imprime `[PlaceMode] Este servidor é o LOBBY` ou `a PARTIDA`.
- **Sem estar no jogo:** Creator Hub → experiência → **Monitoramento → Erros** (*Error Report*) mostra os erros
  agrupados de todos os servidores (demora alguns minutos para aparecer).
- Para pedir correção, copie a linha vermelha inteira (com o nome do script e o número da linha).

## Sons

Os IDs ficam em `src/shared/Config/Sounds.luau`. Quase todos estão vazios (`""`), e som vazio é simplesmente ignorado.
Para colocar um som:
1. Ache um áudio na Creator Store ou suba o seu.
2. Copie o ID.
3. Cole no formato `"rbxassetid://123456"` (música do menu, tambores, tiros, rugido, chuva...).

## Sobre "carregar o jogo antecipadamente" e shaders

O Roblox compila shaders e carrega texturas sozinho, e nenhum script consegue mandar compilar shaders diretamente.
Com **Pré-carregar jogo** ligado, a tela de carregamento faz duas coisas antes de você jogar:
- baixa os assets com `ContentProvider:PreloadAsync`;
- passa a câmera por **todas as áreas do mapa**, para o Roblox renderizar cada material e cena.

Na prática, os travamentos que aconteceriam ao entrar em um cômodo novo acontecem durante o carregamento.
O carregamento fica alguns segundos mais longo.

## Ajustes rápidos

Tudo que é número de balanceamento fica em `src/shared/Config/GameConfig.luau`:
- tempo entre jogadas, número de casas e eventos simultâneos;
- raio da ilha;
- vida dos pedaços de destruição e limite de NPCs;
- quantidade de armas.

Cada evento tem `Weight`, `MinSpace`, `Duration` e `Radius` no topo do seu arquivo em `src/game/server/Events/`.

## Estrutura do código

```
default.project.json  projeto Rojo do place único (lobby + partida)
src/shared/        ReplicatedStorage.Shared: rede, configs, kit de UI, configurações do jogador, PlaceMode
src/serverShared/  ServerScriptService.ServerShared: DataStore das configurações
src/lobby/         servidor e cliente do lobby (menu, hub, salas, teleporte, sala de demonstração)
src/game/server/   partida: MatchService, BoardService, EventService, Map/, Events/, NPC/, Weapons/, DestructionService
src/game/client/   tela de carregamento, HUD, enigma, efeitos, espectador, armas
docs/ARQUITETURA.md  contrato entre os módulos (remotes, payloads, tags, APIs)
scripts/check.sh   verificação estática (luau-lsp com tipos do Roblox + StyLua)
scripts/publish.sh gera o place e publica pela API Open Cloud
```

## Limitações conhecidas

- O código passou por verificação estática de tipos e revisão, mas **ainda não foi testado dentro do Roblox**.
  Espere ajustes de posição, tamanho e balanceamento no primeiro teste. Se aparecer erro no console
  (`/console` no chat), copie a mensagem para corrigirmos.
- Não há animações com assets: NPCs e armas usam movimentos procedurais simples.
- Sons vêm vazios até você colocar os IDs.
