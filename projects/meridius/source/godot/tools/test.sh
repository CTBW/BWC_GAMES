#!/usr/bin/env bash
# Runs the headless test suite. Extra arguments filter by script or test name:
#   tools/test.sh            # everything
#   tools/test.sh rng battle # only matching scripts/tests
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(cd "$HERE/.." && pwd)"
if [ $# -gt 0 ]; then
  "$HERE/godot.sh" --headless --path "$PROJ" -s res://tests/run_tests.gd -- "$@"
else
  "$HERE/godot.sh" --headless --path "$PROJ" -s res://tests/run_tests.gd
fi
