# Meridius (Godot 4.7) — architecture and porting contract

This project is the Godot port of the TypeScript/Canvas game in
`../game` (the "original"; archived on 21 Oct 2026 and kept intact, see
`../game/ARCHIVED.md`). Godot is the runtime and, since the archive, the only
version developed; nothing of the original runs at play time. The original's
TypeScript is used only by offline tools (sprite baking; earlier also the data
export and the first golden traces for the parity tests).

Godot: 4.7.2 stable, `tools/godot.sh` (WinGet console binary). Renderer: GL
Compatibility. Base resolution 1920×1080, stretch `canvas_items`/`expand`.

## Layout

| Path | Contents | Original |
| --- | --- | --- |
| `data/*.json` | Content tables (units, abilities, terrain, props, maps, encounters, events, items, buildings, campaigns, names). Loaded by `scripts/data/db.gd`. Exported once by `tools/export_data.ts`; now the editable source. | `src/data/*` |
| `scripts/core/` | `js.gd` (JS-semantics helpers), `rng.gd` (bit-exact mulberry32), `prefs.gd` | `src/core/*` |
| `scripts/data/db.gd` | Static access to the tables: `DB.UNIT_TYPES`, `DB.squad_size()`, … | `src/data/*` |
| `scripts/rules/` | Pure battle rules: `grid.gd`, `squad.gd`, `battle.gd`, `ai.gd`, `mapgen.gd`, `setup.gd` | `src/battle/*` |
| `scripts/meta/` | `game.gd` (GameState, base, roster economy), `soldier.gd` | `src/meta/*` |
| `scripts/campaign/` | `expedition.gd`, `autoplay.gd` | `src/campaign/*` |
| `scripts/render/` | Presentation: `iso.gd`, `assets.gd` (sprite registry), `terrain.gd`, `atmosphere.gd`, `fx.gd`, `formation.gd`, `squad_view.gd`, `battle_view.gd`, `base_view.gd`, `campaign_view.gd` | `src/render/*` |
| `scripts/ui/` | Godot Control UI: theme, widgets, screens, HUDs | `src/ui/*` |
| `scripts/audio/sfx.gd` | Autoload `Sfx` | `src/audio/sfx.ts` |
| `scripts/app/` | `app.gd` autoload `App` (flow/store, saves), `main.gd` (root scene) | `src/ui/store.ts`, `App.tsx`, `main.tsx` |
| `scenes/` | `main.tscn` (root), plus scenes for views and UI | |
| `assets/` | `sprites/` + `sprites.json` manifest, `fonts/`, `icons/` (SVG), `audio/` (WAV), `shaders/`, `ui/` (theme) | `public/assets`, procedural art |
| `tests/` | `run_tests.gd` runner, `test_case.gd` base, `unit/`, `parity/`, `fixtures/golden/` | `tests/*.test.ts` |
| `tools/` | `godot.sh`, `import.sh` (locked import), `test.sh`, `export_data.ts`, `parity/*.ts` (golden generators), bake scripts | |

Rules (`scripts/rules`, `scripts/meta`, `scripts/campaign`, `scripts/core`,
`scripts/data`) never touch nodes, the scene tree, rendering or audio. They can
run on a worker thread and in headless tests. Presentation reads rule state and
plays back rule events; it never changes rule outcomes (the original's
"rules run ahead of the animation" principle).

## Porting conventions (mandatory)

1. **One original module → one GDScript file** at the mapped path, same
   function order, the original's comments kept where they explain rules. Each
   file starts with a `##` doc comment naming its source file.
2. **No `class_name`.** Reference scripts with
   `const Battle = preload("res://scripts/rules/battle.gd")`. (Headless test
   runs must not depend on the editor's global class cache.)
3. **Names.** Functions and methods → snake_case of the TS name
   (`reachStates` → `reach_states`, `soldierToUnit` → `soldier_to_unit`).
   Module-level TS functions → `static func` in that file. A TS class → the
   script itself (`extends RefCounted`, `Battle.new(setup)`); its fields →
   snake_case member vars (`waveState` → `wave_state`). Exported constants keep
   their UPPER_SNAKE names (`const` or `static var`).
4. **State objects stay Dictionaries with the original camelCase keys**:
   BattleUnit, BattleTile, BattleMap, BattleSetup, BattleEvent, Wave,
   Soldier, GameState, Expedition, CNode, reports… Points are
   `{"x": int, "y": int}` dictionaries. Events are `{"t": "move", …}`.
   This keeps saves JSON, and lets parity tests diff against the original.
   - An optional TS field that is `undefined` is an **absent key**. Read optional
     keys with `d.get("k")` or `JS.get_or(d, "k", fallback)` — dot access to a
     missing key is a runtime error in Godot 4.7. Delete with `d.erase("k")`.
   - TS `Map`/`Set` → Dictionary (insertion-ordered like JS). A `Set<number>` is
     `{k: true}`.
5. **Numbers.** JS numbers are doubles. Values that are always integral in the
   original (coordinates, hp, counts, ids, turns) are `int`; anything that can be
   fractional is `float`. **Division:** never write `a / b` where both may be
   ints unless the original floors it — write `float(a) / b`. `Math.round` →
   `JS.rnd()` (halves go up; `roundi` differs for negatives). `Math.floor/ceil`
   → `floori/ceili` or `floor/ceil`. `Math.max/min` → `maxi/mini` for ints,
   `maxf/minf` for floats (never mix silently). `Math.hypot` → `JS.hypot`.
   Data JSON loads integral numbers as int (`JS.normalize`).
6. **Sorting:** `arr.sort(cmp)` → `JS.sort(arr, cmp)` (stable, comparator
   returns a number). Never `sort_custom` where order can affect rules or AI.
7. **Randomness:** only through `scripts/core/rng.gd`:
   `next()`, `rint(min, max)` (TS `int`), `frange(min, max)` (TS `range`),
   `chance`, `pick`, `weighted`, `shuffle`, `fork`; static `hash_string`, `hash2`.
   It is bit-exact with the original (tests/parity/test_core_parity.gd).
8. **Text:** numbers interpolated into strings go through `JS.num_str()` or are
   ints; `toFixed` → `JS.to_fixed`. Player-facing text stays word for word.
9. **Errors:** TS `throw` → `push_error()` and return a safe value.
10. **Parity:** rules modules are verified against golden traces produced by
    running the original with the same seeds (`tools/parity/*.ts` →
    `tests/fixtures/golden/*.json`; run them from `../game` with
    `npx vite-node ../godot/tools/parity/<file>.ts`). When comparing, absent
    and null are equal, and floats may differ by 1e-12 relative (Godot's
    parsing of 17-digit numbers). Since the original was archived the battle
    traces and campaign runs are re-recorded by the port itself after a
    deliberate rule change (`MERIDIUS_RECORD=1`, see README); the TypeScript
    generators must not be re-run for them.

## Runtime architecture

- `App` autoload (`scripts/app/app.gd`): the store. Holds `game` (GameState
  dict), `screen` (`title|base|prep|campaign|battle|report`), panel/manual/
  soldier overlays; flow methods mirror `store.ts` (`new_game`, `continue_game`,
  `go_base`, `open_panel`, `go_prep`, `launch`, `go_campaign`, `click_node`,
  `dismiss`, `go_home`, `start_battle`, `finish_battle`) and a `debug`-style
  automation API. Emits `changed`. Saves `user://meridius_save.json` (GameState
  JSON, same shape as the original's localStorage save).
- `scenes/main.tscn` (`scripts/app/main.gd`): root Control. Children: a world
  host (SubViewportContainer or Node2D layer showing the active view) and the UI
  layer. Applies the UI theme at the root so every Control inherits it.
- Views (Node2D, world pixels = original world pixels, `iso.gd` TW 128 / TH 64 /
  LH 26): `battle_view.gd`, `base_view.gd`, `campaign_view.gd`. Each owns its
  camera (pan with WASD/arrows/drag, wheel zoom), input on the world, and emits
  signals for the UI. Their public methods mirror the original scene classes in
  snake_case (`BattleScene.setAbility` → `set_ability`, `ui` state dict mirrors
  `BattleUiState`).
- `Sfx` autoload: `Sfx.play(name)` with the original's sound names
  (`step`, `swing`, `hit_metal`, …), `set_muted`, `is_muted`.
- Sprites: `assets/sprites.json` + `scripts/render/assets.gd` (static registry,
  no autoload): `Assets.sprite(key, variant)` returns a dict with `tex`
  (Texture2D), `region` (Rect2), `ax`, `ay` (anchor in source px), `scale`
  (world px per source px), `w`, `h`, `noShadow`. Keys are the original's
  sprite keys (`footman_idle_f`, `tree_oak`, `b_barracks_2`, `portrait_troll`…).
  The procedural canvas art of the original (figures, portraits, fallbacks) is
  baked to PNG by `tools/bake/` through the original renderer; Blender sprites
  are imported as is.

## Input actions (project.godot)

`cam_up/down/left/right` (WASD, arrows), `facing_prev` (Q), `facing_next` (E),
`select_next` (Tab), `end_unit` (Space), `end_turn` (Enter), `redo_move`
(Backspace, Ctrl+Z), `cancel` (Esc), `toggle_grid` (G), `show_danger` (Alt),
`ability_1..4` (1–4), `toggle_fullscreen` (F11). Mouse: left click select/act,
right drag or middle drag pans, wheel zooms.

## UI theme contract

The theme (`assets/ui/theme.tres`, built by `scripts/ui/theme_builder.gd`)
defines these type variations; screens use them by name
(`control.theme_type_variation = "ParchmentPanel"`):

| Variation | Base | Look (from `src/ui/styles.css`) |
| --- | --- | --- |
| `ParchmentPanel` | PanelContainer | Cream parchment card, brown border, dark ink text |
| `ParchmentCard` | PanelContainer | Lighter inset card inside a parchment panel |
| `DarkPanel` | PanelContainer | Dark leather/wood HUD panel, gold-brown border, light text |
| `TopBar` | PanelContainer | The full-width dark top bar |
| `TitleLabel` | Label | Cinzel, large, small caps look |
| `HeadingLabel` | Label | Cinzel, section headings |
| `BodyLabel` | Label | Alegreya body text |
| `SmallLabel` / `MutedLabel` | Label | Alegreya Sans small / muted |
| `GoodLabel` / `BadLabel` | Label | Green / red tones |
| `GoldButton` | Button | Primary gold button (Hire, Build, Done) |
| `DarkButton` | Button | Dark HUD button (Retreat, End Turn, menu) |
| `RedButton` | Button | Strong red action (Plan Expedition, Retreat Home) |
| `IconButton` | Button | Square icon button |
| `HpBar` / `MoraleBar` | ProgressBar | Green squad HP / blue morale |

## Ownership during the migration

Each agent edits only the files it owns; changes needed elsewhere are reported
to the lead. `project.godot` and this file belong to the lead. Imports run only
through `tools/import.sh` (locked). Do not commit; the lead commits.

| Area | Owner |
| --- | --- |
| `scripts/core/*` (`js`, `rng`, `prefs`), `scripts/data/db.gd`, `scripts/qa/*`, `export_presets.cfg`, `tests/run_tests.gd`, `tests/test_case.gd`, `project.godot` | lead |
| `scripts/rules/{grid,squad,battle,ai}.gd`, battle parity | rules agent |
| `scripts/rules/{mapgen,setup}.gd`, `scripts/meta/*`, `scripts/campaign/*`, their parity | world/meta agent |
| `assets/sprites/**`, `assets/sprites.json`, `assets/audio/**`, `assets/shaders/sprite_*`, `tools/bake/**`, `scripts/render/assets.gd`, `scripts/audio/sfx.gd` | asset agent |
| `scripts/render/{iso,terrain,atmosphere,fx,camera}.gd`, `assets/shaders/{terrain,atmo}*`, `base_view`, `campaign_view`, `scenes/{base,campaign}/*` | world-render agent |
| `scripts/render/{battle_view,squad_view,formation}.gd`, `scenes/battle/*` | battle-view agent |
| `scripts/ui/*`, `scripts/app/*`, `scenes/main.tscn`, `scenes/ui/*`, `assets/fonts/**`, `assets/icons/**`, `assets/ui/**` | UI agents |

`scripts/core/prefs.gd`: `Prefs.prefs()` → `{muted, battleSpeed}`,
`Prefs.set_pref(key, value)` (user://prefs.json).
