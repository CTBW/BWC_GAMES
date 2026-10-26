# Meridius (Godot 4.7)

Squad tactics on the Nordmark frontier: hold Amberfeld Garrison, recruit and
train a company, and fight the greenskin horde in squad battles. The game is
being redesigned around 3D units: an expedition is now one turn-based battle
on Ashby farm, shown with the 3D units (the campaign map is set aside).

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
| `tools/godot.sh --path . -- --playground` | Open the unit playground directly |
| `tools/godot.sh --path . -- --terrain-lab` | Open the three terrain test fields directly |
| `tools/godot.sh --path . -- --newgame --seed=7` | Start straight into a new company |
| `tools/godot.sh -e --path .` | Open the editor |
| `tools/import.sh` | Re-import resources (locked, safe with parallel agents) |
| `tools/test.sh --quick` | Headless test suite without the long campaign/battle replays (~3 min) |
| `tools/test.sh` | Full suite incl. full AI campaigns (~5 min) |
| `tools/test.sh battle facing` | Only tests whose script or name matches |
| `tools/review_ui.sh` | Rebuild themes, capture the interface at three desktop resolutions, then run the input-driven playthrough with muted audio |
| `tools/export.sh` | Windows build → `build/windows/Meridius.exe` (+ `Meridius.console.exe`) |
| `build/windows/Meridius.console.exe -- --smoke` | Self-test of the built game (exit code 0 = OK) |
| `tools/godot.sh --path . -s res://tests/visual/playthrough.gd` | Input-driven play-through in a 1920×1080 window (~2.5 min; `-- --full` adds Save and Quit on the field, a second expedition left by Retreat and New Company, ~5 min); exit code 0 = every check passed and no error was logged |
| `tools/godot.sh --path . --resolution 1920x1080 -s res://tests/visual/battle3d_flow.gd` | The 3D battle from March Out to the report: deployment, a turn played by clicks, the enemy's turn, then the AI on both sides; captures in `tests/visual/out/battle3d_flow/` |
| `tools/godot.sh --path . -s res://tests/visual/battle_open_time.gd` | Time to open the first and the second battle (boot warm-up check) |

### The play-through regression check

`tests/visual/playthrough.gd` boots `scenes/main.tscn` in a window and plays
only through synthesized input (`Input.parse_input_event`: mouse motion,
clicks, wheel, keys) at positions taken from the Controls' rects and the world
cameras: title → New Company → welcome → buildings on the camp map (Barracks:
hire) → Roster → a soldier → Sound → F11 → Esc menu → prep (army, supplies,
advice) → March Out → the turn-based battle on Ashby farm, in 3D, played to
its end by clicks and keys (deployment: two squads swap tiles; Speed, Begin
Battle; each turn the grid (G), the danger (Alt), the wheel and WASD, Tab and
the company panel; a squad selected by clicking a man, marched by a click on a
tile, turned with Q / E, set on a foe by clicking him, a move taken back with
Backspace; Done (Space), End Turn (Enter)) → the report → garrison.
`-- --full` adds Save and Quit / Continue on the field, a second expedition
left by Retreat (asked twice) and New Company over the save.
Each step is checked against the game state. It writes
`tests/visual/out/playthrough/`: `playthrough.txt` (every step, frame times per
phase, frames over 100 ms, logged errors, orphan nodes) and numbered
screenshots. It uses its own save file, restores the prefs afterwards, and
drops real mouse/key events while it runs (do not type into the window).
Run it windowed (not `--headless`).

## Woodland camp

The campaign's starting garrison now uses the selected `camp_small_woodland`
painting. Click a numbered facility in the scene or its matching **Camp Services**
button to open the existing building panel. **Day / Night** smoothly changes the
local lighting preview; it does not advance campaign time. The wheel zooms,
WASD/arrows and right/middle drag pan within the image, and **Frame camp** restores
the full enclosure. Roster and Plan Expedition work as before.

The six services keep their actual levels and effects. This first painted pass
does not change the architecture when a building is upgraded. Roster figures
walk authored open-ground paths; drifting forest mist and painted tent light
provide motion without changing the concept's layout.

Native review: `tests/visual/camp_remodel_review.gd` (append `-- --camp-motion`
for a five-second, 24 fps frame sequence); evidence and sources are in the
Workspace **Woodland camp remodel** tab. Tests: `tools/test.sh --quick
test_woodland_camp test_base_view test_screens`.

## Terrain test fields

Choose **Terrain Test Fields** on the title screen. Rolling meadow, northern
forest ford and opposing ridges test continuous slopes, material transitions
and real patrol movement. Two squads can keep walking as their movement
refills on arrival. Click a patrol, then highlighted ground; wheel to zoom,
right-drag to pan. **Heights** shows contour bands, **Grid** reveals the tactical
cells, and **Night** previews readable moonlight. **Classic tile heights** is
the comparison renderer. Escape returns to the title.

These are isolated experiments using the real battle renderer and path rules;
they never create or update a company save. The first woodland pass mixes
existing pine, oak, bush, stump and log art with golden grass and drifting mist.
More foliage species and crafted compositions can be added incrementally.
Native review: `tests/visual/terrain_lab_shots.gd`; output: `tests/visual/out/terrain_lab/`.

## Unit playground

Choose **Unit Playground** on the title screen. It opens a flat practice field
with all 20 current unit types and an indestructible straw training dummy.
It uses the game's real sprite models, formation logic, movement and attack
playback, in a separate practice state. It does not create or change a save.

- Choose a unit, appearance (Look 1–6), full squad or single figure. War machines
  retain their crews. Add a second unit with **Compare with** to judge scale.
- Click the field to walk. Click the dummy or **Attack dummy** to approach and
  attack; missile units stop at firing distance. The dummy survives every hit.
- Preview **Idle**, **March**, **Turn**, **Attack dummy** or **Fall**. Toggle
  **Loop**, pause with Space, use **+1 frame** for 1/60-second steps, or Replay.
  Playback speed ranges from 0.25× to 2× and is local to the playground.
- Q/E or the four facing buttons turn the model. Wheel zooms from 0.4× to 5×;
  right/middle drag pans. **Battle zoom**, **Close up** and **Frame unit** restore
  useful views. Grid and night lighting are optional.
- Esc or **Back to title** leaves the field. Reopening starts a fresh practice.

The sandbox previews existing animations; it does not edit source models or
author new clips. Attack is the unit's regular melee, missile or magic-bolt
attack; special abilities are not separate clips. Combat audio is suppressed
for visual inspection. See the Meridius Workspace **Unit playground** tab for
native captures and a short motion clip.

Regression checks: `tools/test.sh --quick test_unit_playground`. Native input,
save-isolation and visual review:
`tools/godot.sh --path . --resolution 1920x1080 --audio-driver Dummy -s res://tests/visual/unit_playground_review.gd`.

## 3D unit sandbox

Every rigged 3D character (footman, spearman, crossbowman, battle mage, wolf
scout, succubus) on a hilly training ground in the battle's look, with the
painted woodland, the fog of war and a night light, under the game's camera:
march them, set them on each other or on the dummies, play any clip.
`tools/godot.sh --path . res://prototypes/sandbox3d/scenes/sandbox3d.tscn`.
Controls, captures and checks: `prototypes/sandbox3d/README.md`.

## 3D battlefields

Four places of the frontier in four seasons in the battle's look, without
units: a summer market town on a river, an autumn farm the war has burnt, a
winter hamlet by a frozen lake and a spring ford with ruins. Scouts lift the
fog of war by the battle's sight rules; night and weather on a key.
`tools/godot.sh --path . res://prototypes/battlefields3d/scenes/battlefields3d.tscn`.
Controls, art and checks: `prototypes/battlefields3d/README.md`.

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
scripts/render   iso maths, camera, terrain, FX, battle/garrison views, the 3D battle
scripts/ui       theme, widgets, screens, HUDs
scripts/app      App autoload (game flow and saves), main scene
scripts/audio    Sfx autoload: sound bank, placed sound, ambience, music
assets           sprites (+ sprites.json), audio (baked; recorded in audio/bank), fonts, icons, shaders, UI theme
tests            unit tests, parity tests against the original, golden data
tools            Godot wrappers, data export, sprite/audio bake, recorded sound bank (audio/), golden generators
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
- Battle figures (pixel art, `scripts/render/soldier_anim.gd`): every squad type
  and war machine is built by `tools/anim/squadgen.py build <type>` (art venv:
  `../game/.venv-art/Scripts/python.exe -I`) from the cut sheets in
  `art/squads/<type>/`, then `tools/import.sh`. New or redone sheets come from
  Higgsfield through `tools/anim/hfgen.py` (`auto <type>`, `run`, `edit`; job ids
  in `art/raw/<type>/jobs.json`). Checks: `tools/anim/headings.py` (each facing as
  drawn), `tools/anim/slotcheck.py` (swapped soldiers), `tools/anim/contact.py`,
  and in a window `tools/godot.sh --path . -s res://tests/visual/footman_lab.gd --
  unit=<type> [facings march melee deaths turn]`. (`build_footman.py` built the
  first footman frames and is superseded.)
- Sound: recorded takes, ambience and music go in `assets/audio/bank/` and are
  listed in `assets/audio/bank/bank.json` (event → takes, bus, level, jitter,
  voice limit; ambience presets; music tracks), then `tools/import.sh`. An
  event without recorded takes keeps its baked synth sound. See
  ARCHITECTURE.md, *Audio*.
- Saves: `%APPDATA%\Godot\app_userdata\Meridius\meridius_save.json`; preferences
  in `prefs.json` beside it.

## Continuing with Claude Code

Start Claude Code in this folder (or the repository root). `CLAUDE.md` here
gives it the conventions. Useful requests: "run the quick tests", "play a test
battle with seed 7 and capture screenshots" (`App.debug_test_battle`), "add a
unit type", "export and smoke-test the build".
