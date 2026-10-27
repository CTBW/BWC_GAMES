# Meridius (Godot) — instructions for agents

Read `ARCHITECTURE.md` before changing code; `README.md` for commands.

- All Meridius work happens here, for the Windows desktop build. The original
  TypeScript game in `../game` is a frozen reference: read it or run it
  unchanged, never change it. No mobile versions or mobile optimisation.
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
- Parity tests (`tests/parity`) were recorded from the original TypeScript
  game in `../game`, which is archived (`../game/ARCHIVED.md`). The battle
  traces and the campaign runs are now the port's own regression baseline: after
  a deliberate rules or balance change, re-record them with
  `MERIDIUS_RECORD=1 tools/test.sh test_battle_parity test_campaign_parity`,
  explain what changed and why in MIGRATION.md, and say so. Other golden files
  have no recorder: retire the affected cases with a note in MIGRATION.md.
  Never re-run the TypeScript generators in `tools/parity/`, and do not change
  `../game` to match.
- A change to the game's rules gets no whole-campaign test (the owner, 26
  October 2026). After it, and before committing it, run every suite except
  `test_campaign_parity`: `tools/test.sh --quick tests/unit test_battle_parity
  test_core_parity test_mapgen_parity test_meta_parity test_setup_parity`, then
  the slow battle traces with `tools/test.sh test_battle_parity`. Re-record the
  battle traces only, and say in MIGRATION.md that the campaign baseline was
  not checked.
- Verify visual changes in a real window: capture scripts in `tests/visual/`
  save PNGs to `tests/visual/out/` (gitignored); look at them.
- Test only in the 3D sandbox (`prototypes/sandbox3d`) or on Ashby farm (the
  3D battle, or `prototypes/battlefields3d` with `--fields=ashby`), never in
  the other small simulators (the owner, 27 October 2026). See `../../../../AGENTS.md`.
- Ship: `tools/export.sh`, then `build/windows/Meridius.console.exe -- --smoke`.
