# Tambores da Selva

Jogo de tabuleiro amaldiçoado para Roblox, inspirado no filme de 1995. Todo o código é Luau, organizado com
[Rojo](https://rojo.space). Mapa, interface e modelos são gerados por código, então não há assets para importar.

> **Sobre o nome:** "Jumanji" é marca registrada. Usar o nome ou a marca no Roblox pode fazer o jogo ser removido.
> O título fica em `src/shared/Config/GameConfig.luau` (`GAME_TITLE`).

## O que tem no jogo

**Lobby (place inicial)**
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

**Partida (segundo place)**
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

### Opção A: arquivos prontos (mais simples)

Na pasta `builds/` estão `Lobby.rbxlx` e `Partida.rbxlx`. Abra cada um no Roblox Studio (Arquivo → Abrir).
Para testar a partida direto, abra `Partida.rbxlx` e aperte **Play**: sem teleporte, ela começa em modo solo.

Os arquivos de `builds/` são gerados a partir de `src/`. Se você mudar o código, gere de novo com o Rojo:
```
rojo build lobby.project.json -o builds/Lobby.rbxlx
rojo build game.project.json -o builds/Partida.rbxlx
```

### Opção B: Rojo ao vivo (recomendado para continuar desenvolvendo)

1. Instale o [Rokit](https://github.com/rojo-rbx/rokit) e rode `rokit install` na pasta do projeto (instala Rojo, StyLua e luau-lsp).
2. Instale o plugin do Rojo no Studio (`rojo plugin install`).
3. Rode `rojo serve lobby.project.json` (ou `game.project.json`), abra um place vazio no Studio e clique em **Connect** no plugin.
4. Edite os arquivos em `src/`; o Studio atualiza sozinho.

## Publicar (para o teleporte funcionar)

O teleporte entre lobby e partida **não funciona no Studio**, só no jogo publicado. No Studio, o botão mostra uma
mensagem explicando isso.

1. Publique o lobby como uma nova experiência (ele vira o *start place*).
2. No [Creator Hub](https://create.roblox.com), abra a experiência → **Places** → **Add place**. Publique a partida nesse novo place.
3. Copie os dois IDs para `src/shared/Config/Places.luau` (`LOBBY_PLACE_ID` e `GAME_PLACE_ID`).
4. Publique os **dois** places de novo (o arquivo de IDs vai junto com cada um).
5. Em **Game Settings → Security**, ative **Enable Studio Access to API Services** se quiser que as configurações sejam
   salvas também nos testes do Studio.

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
lobby.project.json / game.project.json   projetos Rojo (um por place)
src/shared/        ReplicatedStorage.Shared: rede, configs, kit de UI, configurações do jogador
src/serverShared/  ServerScriptService.ServerShared: DataStore das configurações
src/lobby/         servidor e cliente do lobby (menu, hub, salas, teleporte, sala de demonstração)
src/game/server/   partida: MatchService, BoardService, EventService, Map/, Events/, NPC/, Weapons/, DestructionService
src/game/client/   tela de carregamento, HUD, enigma, efeitos, espectador, armas
docs/ARQUITETURA.md  contrato entre os módulos (remotes, payloads, tags, APIs)
scripts/check.sh   verificação estática (luau-lsp com tipos do Roblox + StyLua)
```

## Limitações conhecidas

- O código passou por verificação estática de tipos e revisão, mas **ainda não foi testado dentro do Roblox**.
  Espere ajustes de posição, tamanho e balanceamento no primeiro teste. Se aparecer erro no **Output** do Studio,
  copie a mensagem para corrigirmos.
- Não há animações com assets: NPCs e armas usam movimentos procedurais simples.
- Sons vêm vazios até você colocar os IDs.
