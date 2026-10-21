#!/usr/bin/env bash
# Re-imports the project's resources and refreshes the editor caches.
# Several agents share this project, so the import runs under a directory lock
# (mkdir is atomic): only one import writes .godot/ at a time.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(cd "$HERE/.." && pwd)"
LOCK="$PROJ/.lock-import"
for i in $(seq 1 600); do
  if mkdir "$LOCK" 2>/dev/null; then break; fi
  # A lock older than 15 minutes is stale (a crashed import).
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +15 2>/dev/null)" ]; then rmdir "$LOCK" 2>/dev/null; continue; fi
  sleep 1
done
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
"$HERE/godot.sh" --headless --path "$PROJ" --import "$@" 2>&1 | grep -vE "^\s*$" | tail -40
exit "${PIPESTATUS[0]}"
