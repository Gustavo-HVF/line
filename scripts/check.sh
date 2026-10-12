#!/usr/bin/env bash
# Verifica o código Luau do place com luau-lsp (tipos do Roblox) e o formato com StyLua.
# Uso: TOOLS=/caminho/para/binarios ROBLOX_TYPES=/caminho/globalTypes.d.luau scripts/check.sh [arquivos...]
set -uo pipefail
cd "$(dirname "$0")/.."

TOOLS="${TOOLS:-}"
bin() { if [ -n "$TOOLS" ]; then echo "$TOOLS/$1"; else echo "$1"; fi; }
ROJO="$(bin rojo)"; LSP="$(bin luau-lsp)"; STYLUA="$(bin stylua)"
TYPES="${ROBLOX_TYPES:-globalTypes.d.luau}"

status=0
"$ROJO" sourcemap default.project.json -o sourcemap.json >/dev/null || status=1
if [ "$#" -gt 0 ]; then
  files=("$@")
else
  mapfile -t files < <(find src -name '*.luau' | sort)
fi
echo "== luau-lsp (${#files[@]} arquivos)"
"$LSP" analyze --sourcemap=sourcemap.json --definitions="$TYPES" --base-luaurc=.luaurc \
  --no-strict-dm-types "${files[@]}" || status=1

echo "== stylua --check"
"$STYLUA" --check src || status=1
exit $status
