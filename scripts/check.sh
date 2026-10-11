#!/usr/bin/env bash
# Verifica o código Luau dos dois places com luau-lsp (tipos do Roblox) e o formato com StyLua.
# Uso: TOOLS=/caminho/para/binarios ROBLOX_TYPES=/caminho/globalTypes.d.luau scripts/check.sh [arquivos...]
set -uo pipefail
cd "$(dirname "$0")/.."

TOOLS="${TOOLS:-}"
bin() { if [ -n "$TOOLS" ]; then echo "$TOOLS/$1"; else echo "$1"; fi; }
ROJO="$(bin rojo)"; LSP="$(bin luau-lsp)"; STYLUA="$(bin stylua)"
TYPES="${ROBLOX_TYPES:-globalTypes.d.luau}"

status=0
for place in lobby game; do
  "$ROJO" sourcemap "$place.project.json" -o "sourcemap.$place.json" >/dev/null || status=1
  if [ "$#" -gt 0 ]; then
    files=()
    for f in "$@"; do
      case "$f" in
        src/shared/*|src/serverShared/*|src/$place/*) files+=("$f");;
      esac
    done
    [ "${#files[@]}" -eq 0 ] && continue
  else
    mapfile -t files < <(find src/shared src/serverShared "src/$place" -name '*.luau' | sort)
  fi
  echo "== luau-lsp ($place: ${#files[@]} arquivos)"
  "$LSP" analyze --sourcemap="sourcemap.$place.json" --definitions="$TYPES" --base-luaurc=.luaurc \
    --no-strict-dm-types "${files[@]}" || status=1
done

echo "== stylua --check"
"$STYLUA" --check src || status=1
exit $status
