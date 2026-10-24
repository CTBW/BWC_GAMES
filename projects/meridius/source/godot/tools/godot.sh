#!/usr/bin/env bash
# Runs the Godot 4.7.2 console binary (WinGet install) with the given arguments.
# Override with GODOT=/path/to/godot if it lives elsewhere.
GODOT="${GODOT:-/c/Users/calle/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe}"
exec "$GODOT" "$@"
