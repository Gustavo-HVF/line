#!/usr/bin/env bash
# Gera o place com o Rojo e publica na experiência pela API Open Cloud do Roblox (Place Publishing).
#
# Uso:
#   ROBLOX_API_KEY=<chave> scripts/publish.sh            # publica (versão "Published": vale para quem entrar)
#   ROBLOX_API_KEY=<chave> scripts/publish.sh Saved      # só salva uma versão nova, sem publicar
#
# A chave precisa da permissão "universe-places" → "write" para esta experiência
# (Creator Hub → Open Cloud → API Keys). Variáveis opcionais: UNIVERSE_ID, PLACE_ID, ROJO.
set -euo pipefail
cd "$(dirname "$0")/.."

UNIVERSE_ID="${UNIVERSE_ID:-2327303402}"
PLACE_ID="${PLACE_ID:-6305250851}"
VERSION_TYPE="${1:-Published}"
ROJO="${ROJO:-rojo}"

if [ -z "${ROBLOX_API_KEY:-}" ]; then
  echo "Defina a variável ROBLOX_API_KEY com a chave da Open Cloud." >&2
  exit 1
fi
case "$VERSION_TYPE" in
  Saved|Published) ;;
  *) echo "Tipo de versão inválido: $VERSION_TYPE (use Saved ou Published)" >&2; exit 1;;
esac

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
place="$workdir/TamboresDaSelva.rbxl"

"$ROJO" build default.project.json -o "$place"
echo "Enviando $(du -h "$place" | cut -f1) para o place $PLACE_ID (universe $UNIVERSE_ID, $VERSION_TYPE)…"

# A chave vai por stdin (curl -K -) para não aparecer na lista de processos nem em logs.
response="$workdir/response.json"
status=$(
  printf 'header = "x-api-key: %s"\n' "$ROBLOX_API_KEY" | curl -sS -K - \
    -X POST "https://apis.roblox.com/universes/v1/$UNIVERSE_ID/places/$PLACE_ID/versions?versionType=$VERSION_TYPE" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @"$place" \
    -o "$response" -w '%{http_code}'
)

if [ "$status" != "200" ]; then
  echo "Falhou (HTTP $status):" >&2
  cat "$response" >&2
  echo >&2
  exit 1
fi
echo "OK: $(cat "$response")"
