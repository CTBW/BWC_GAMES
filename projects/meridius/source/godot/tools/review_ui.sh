#!/usr/bin/env bash
# Validate the UI in the actual game, with captures at desktop aspect ratios.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(cd "$HERE/.." && pwd)"
if [[ "${1:-}" != "--input-only" ]]; then
  "$HERE/godot.sh" --headless --path "$PROJ" -s res://scripts/ui/theme_build_cli.gd
  "$HERE/godot.sh" --path "$PROJ" --resolution 1920x1080 -s res://tests/visual/ui_art_review.gd
fi
"$HERE/godot.sh" --path "$PROJ" --audio-driver Dummy --resolution 1920x1080 -s res://tests/visual/playthrough.gd
