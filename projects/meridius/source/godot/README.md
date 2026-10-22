# Meridius (Godot 4.7)

Isometric, turn-based squad tactics on the Nordmark frontier: hold Amberfeld
Garrison, recruit and train a company, march expeditions across a randomised
campaign map and fight the greenskin horde in squad battles.

This is the Godot port of the original TypeScript/Canvas game in `../game`,
which stays in the repository as the reference. Godot is the only runtime.
`ARCHITECTURE.md` describes the structure and the porting conventions;
`MIGRATION.md` records what was ported and how each part was verified.

## Open and run

1. Install Godot **4.7.2 stable** (standard build, not .NET). On this machine it
   is the WinGet install, wrapped by `tools/godot.sh`.
2. Open the editor, *Import*, and pick `projects/meridius/source/godot/project.godot`.
   The first import takes a minute (sprite atlases).
3. Press F5. The game starts at the title screen.

From a shell (Git Bash), in this folder:

| Command | What it does |
| --- | --- |
| `tools/godot.sh --path .` | Run the game |
| `tools/godot.sh --path . -- --newgame --seed=7` | Start straight into a new company |
| `tools/godot.sh -e --path .` | Open the editor |
| `tools/import.sh` | Re-import resources (locked, safe with parallel agents) |
| `tools/test.sh --quick` | Headless test suite without the long campaign/battle replays (~3 min) |
| `tools/test.sh` | Full suite incl. full AI campaigns (~5 min) |
| `tools/test.sh battle facing` | Only tests whose script or name matches |
| `tools/export.sh` | Windows build → `build/windows/Meridius.exe` (+ `Meridius.console.exe`) |
| `build/windows/Meridius.console.exe -- --smoke` | Self-test of the built game (exit code 0 = OK) |
| `tools/godot.sh --path . -s res://tests/visual/playthrough.gd` | Input-driven play-through in a 1920×1080 window (~2 min; `-- --full` adds a second expedition, restart and last-stand turns, ~5 min); exit code 0 = every check passed and no error was logged |
| `tools/godot.sh --path . -s res://tests/visual/battle_open_time.gd` | Time to open the first and the second battle (boot warm-up check) |

### The play-through regression check

`tests/visual/playthrough.gd` boots `scenes/main.tscn` in a window and plays
only through synthesized input (`Input.parse_input_event`: mouse motion,
clicks, wheel, keys) at positions taken from the Controls' rects and the world
cameras: title → New Company → welcome → buildings on the camp map (Barracks:
hire) → Roster → a soldier → Sound → F11 → Esc menu → prep (army, supplies,
advice) → March Out → map nodes to a battle, dialogs through their buttons →
the battle played to its end by clicks (a small bot asks `Ai.act_unit` on a
copy of the battle what to do and clicks it: select, point at a tile edge /
Q / E for the facing, move, attack, ability buttons and number keys, Redo,
Done / Space, End Turn / Enter) → result → Retreat home → report → garrison →
the last stand's minimap click → Save and Quit. `-- --full` adds Save and
Quit / Continue mid-expedition, more nodes, a second expedition with a battle
left by Retreat, two turns of the last stand and New Company over the save.
Each step is checked against the game state. It writes
`tests/visual/out/playthrough/`: `playthrough.txt` (every step, frame times per
phase, frames over 100 ms, logged errors, orphan nodes) and numbered
screenshots. It uses its own save file, restores the prefs afterwards, and
drops real mouse/key events while it runs (do not type into the window).
Run it windowed (not `--headless`).

## Controls

Left click selects a squad, moves it (point at a tile edge to choose the facing
it arrives with; Q / E cycle facings) and attacks. Right or middle drag pans,
the wheel zooms, WASD / arrows pan. Tab next squad, Space done, Enter end turn,
Backspace or Ctrl+Z redo the last move, 1–4 abilities, G grid, hold Alt for
danger tiles, Esc cancels or opens the menu, F11 fullscreen.

## Layout

```
data/            content tables (units, abilities, maps, encounters, events, items…)
scripts/core     JS-compatible maths, the seeded RNG, prefs
scripts/rules    battle rules, AI, map generation, battle setup (no nodes)
scripts/meta     company, soldiers, garrison economy, saves
scripts/campaign expeditions and the auto-player
scripts/render   iso maths, camera, terrain, FX, battle/garrison/campaign views
scripts/ui       theme, widgets, screens, HUDs
scripts/app      App autoload (game flow and saves), main scene
scripts/audio    Sfx autoload
assets           sprites (+ sprites.json), audio, fonts, icons, shaders, UI theme
tests            unit tests, parity tests against the original, golden data
tools            Godot wrappers, data export, sprite/audio bake, golden generators
```

Gameplay rules never touch nodes; the views only play back the events the
rules emit, so art and animation changes cannot alter combat outcomes.

## Changing content

- Numbers and content live in `data/*.json` (loaded by `scripts/data/db.gd`).
  Edit them directly; the JSON is now the source of truth. Parity tests replay
  golden traces first recorded from the original (now archived), so a
  deliberate rules or balance change will make them fail: re-record the battle
  traces and campaign runs from the port with
  `MERIDIUS_RECORD=1 tools/test.sh test_battle_parity test_campaign_parity`,
  review what changed, and note it in MIGRATION.md.
- Sprites: Blender renders go in `assets/sprites/blender/` with an entry in
  `assets/sprites.json` (`file`, anchor `ax`/`ay`, `scale`). The procedural
  figures were baked from the original with `tools/bake/` (see its README).
- Saves: `%APPDATA%\Godot\app_userdata\Meridius\meridius_save.json`; preferences
  in `prefs.json` beside it.

## Continuing with Claude Code

Start Claude Code in this folder (or the repository root). `CLAUDE.md` here
gives it the conventions. Useful requests: "run the quick tests", "play a test
battle with seed 7 and capture screenshots" (`App.debug_test_battle`), "add a
unit type", "export and smoke-test the build".
