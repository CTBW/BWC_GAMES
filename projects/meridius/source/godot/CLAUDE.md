# Meridius (Godot) — instructions for agents

Read `ARCHITECTURE.md` before changing code; `README.md` for commands.

- Godot 4.7.2 via `tools/godot.sh`. Run `tools/test.sh --quick` after every
  change and the full `tools/test.sh` before committing; never commit with
  failing tests. Re-import only through `tools/import.sh`.
- No `class_name`; reference scripts with `const X = preload("res://…")` so
  headless runs work without the editor's class cache.
- Rules (`scripts/rules`, `meta`, `campaign`, `core`, `data`) never touch nodes,
  autoloads or rendering. Views play back rule events and never change outcomes.
- State is plain Dictionaries with the original camelCase keys; read optional
  keys with `.get()` (dot access to a missing key is a runtime error).
- Integers vs floats: write `float(a) / b` unless integer division is intended;
  `JS.rnd` for JS-style rounding; `JS.sort` (stable) wherever order matters;
  randomness only through `scripts/core/rng.gd`.
- Parity tests (`tests/parity`) prove equality with the original TypeScript
  game in `../game`. A deliberate rules or balance change breaks them by design:
  say so, and either regenerate goldens from an equally changed original
  (`npx vite-node ../godot/tools/parity/<x>.ts` from `../game`) or retire the
  affected parity cases with a note in MIGRATION.md.
- Verify visual changes in a real window: capture scripts in `tests/visual/`
  save PNGs to `tests/visual/out/` (gitignored); look at them.
- Ship: `tools/export.sh`, then `build/windows/Meridius.console.exe -- --smoke`.
