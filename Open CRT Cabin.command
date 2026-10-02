#!/bin/zsh
set -eu
cd "${0:A:h}"
engine="${GODOT_BIN:-$HOME/Desktop/Godot.app/Contents/MacOS/Godot}"
if [[ ! -x "$engine" && -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
 engine=/Applications/Godot.app/Contents/MacOS/Godot
fi
if [[ ! -x "$engine" ]]; then
 print '请设置 GODOT_BIN，指向 Godot 4.7 可执行文件。'
 exit 1
fi
exec "$engine" --path godot res://presentation/cabin/cabin.tscn "$@"
