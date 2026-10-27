#!/bin/zsh
set -eu
cd "${0:A:h}"
engine="${GODOT_BIN:-$HOME/Desktop/Godot.app/Contents/MacOS/Godot}"
if [[ ! -x "$engine" && -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
  engine=/Applications/Godot.app/Contents/MacOS/Godot
fi
node_engine="$(command -v node || true)"
if [[ -z "$node_engine" && -x "$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node" ]]; then
  node_engine="$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node"
fi
if [[ ! -x "$engine" || -z "$node_engine" ]]; then
  print '需要 Godot 4.7 和 Node.js。可通过 GODOT_BIN 指定 Godot 可执行文件。'
  exit 1
fi
mkdir -p godot/data/generated
"$node_engine" .art-preview-local/bubble-generator/generate.cjs "${1:-ALYBE-TILES}" "${2:-32}" godot/data/generated/alybe_walk.json
exec "$engine" --path godot --rendering-method gl_compatibility --resolution 1280x800 res://presentation/alybe_walk/alybe_walk.tscn -- --map res://data/generated/alybe_walk.json
