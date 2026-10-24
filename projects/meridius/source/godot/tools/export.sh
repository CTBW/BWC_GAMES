#!/usr/bin/env bash
# Builds the Windows desktop release into build/windows/Meridius.exe
# (plus Meridius.console.exe, which shows the log). Usage: tools/export.sh [debug]
# Shares the import lock with tools/import.sh because exporting re-imports.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(cd "$HERE/.." && pwd)"
LOCK="$PROJ/.lock-import"
MODE="--export-release"
[ "${1:-}" = "debug" ] && MODE="--export-debug"
mkdir -p "$PROJ/build/windows"
for i in $(seq 1 600); do
  if mkdir "$LOCK" 2>/dev/null; then break; fi
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +15 2>/dev/null)" ]; then rmdir "$LOCK" 2>/dev/null; continue; fi
  sleep 1
done
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
"$HERE/godot.sh" --headless --path "$PROJ" $MODE "Windows Desktop" "$PROJ/build/windows/Meridius.exe" 2>&1 | grep -vE "^\s*$" | tail -30
STATUS=${PIPESTATUS[0]}
ls -la "$PROJ/build/windows" 2>/dev/null
exit $STATUS
