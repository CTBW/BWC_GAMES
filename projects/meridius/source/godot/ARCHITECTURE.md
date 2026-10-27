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
| `scripts/rules/` | Pure battle rules: `grid.gd`, `squad.gd`, `battle.gd`, `ai.gd`, `mapgen.gd`, `setup.gd`; `battlefields.gd` (the 3D battlefields as battle maps; Godot only) | `src/battle/*` |
| `scripts/meta/` | `game.gd` (GameState, base, roster economy), `soldier.gd` | `src/meta/*` |
| `scripts/campaign/` | `expedition.gd`, `autoplay.gd` | `src/campaign/*` |
| `scripts/render/` | Presentation: `iso.gd`, `assets.gd` (sprite registry), `terrain.gd`, `atmosphere.gd`, `fx.gd`, `formation.gd`, `squad_view.gd`, `soldier_anim.gd` (frame-animated figures: the footmen; Godot only), `battle_view.gd`, `base_view.gd`; Godot only: `battle3d.gd`, `battle3d_field.gd` (the expedition's 3D battle) | `src/render/*` |
| `scripts/ui/` | Godot Control UI: theme, widgets, screens, HUDs | `src/ui/*` |
| `scripts/audio/` | `sfx.gd` autoload `Sfx`; Godot only: `bank.gd` (sound bank), `placement.gd` (on-screen pan and level), `loop_deck.gd` (fading loops), `ambience.gd` (beds, positional loops, scheduled one-shots) | `src/audio/sfx.ts` |
| `scripts/app/` | `app.gd` autoload `App` (flow/store, saves), `main.gd` (root scene) | `src/ui/store.ts`, `App.tsx`, `main.tsx` |
| `scenes/` | `main.tscn` (root), plus scenes for views and UI | |
| `assets/` | `sprites/` + `sprites.json` manifest, `sprites/anim/` (frame atlases + tables, `tools/anim/`), `fonts/`, `icons/` (SVG), `audio/` (baked WAV + `sfx.json`), `audio/bank/` (`bank.json` and recorded takes), `shaders/`, `ui/` (theme) | `public/assets`, procedural art |
| `default_bus_layout.tres` | Audio buses (Godot loads it by default) | |
| `art/` | Editable masters outside the import (`.gdignore`): `footman/*.aseprite` | |
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
  dict), `screen` (`title|base|prep|battle|report`), panel/manual/
  soldier overlays; flow methods mirror `store.ts` (`new_game`, `continue_game`,
  `go_base`, `open_panel`, `go_prep`, `launch`, `go_home`, `start_battle`,
  `finish_battle`) and a `debug`-style automation API. The game is being
  redesigned around the 3D units: the campaign map is set aside, and an
  expedition is one battle shown in 3D (see *The 3D battle*). Emits
  `changed`. Saves `user://meridius_save.json` (GameState JSON, same shape as
  the original's localStorage save).
- `scenes/main.tscn` (`scripts/app/main.gd`): root Control. Children: a world
  host (SubViewportContainer or Node2D layer showing the active view) and the UI
  layer. Applies the UI theme at the root so every Control inherits it.
- Views (Node2D, world pixels = original world pixels, `iso.gd` TW 128 / TH 64 /
  LH 26): `battle_view.gd` (the 2D battle, now only in the Unit
  Playground, the Terrain Lab and tests), `base_view.gd`. Each owns its
  camera (pan with WASD/arrows/drag, wheel zoom), input on the world, and emits
  signals for the UI. Their public methods mirror the original scene classes in
  snake_case (`BattleScene.setAbility` → `set_ability`, `ui` state dict mirrors
  `BattleUiState`).
- `Sfx` autoload: `Sfx.play(name)` with the original's sound names
  (`step`, `swing`, `hit_metal`, …), `play_at(name, world_pt)`, `set_muted`,
  `is_muted`, volumes, ambience and music; see *Audio* below.
- Sprites: `assets/sprites.json` + `scripts/render/assets.gd` (static registry,
  no autoload): `Assets.sprite(key, variant)` returns a dict with `tex`
  (Texture2D), `region` (Rect2), `ax`, `ay` (anchor in source px), `scale`
  (world px per source px), `w`, `h`, `noShadow`. Keys are the original's
  sprite keys (`footman_idle_f`, `tree_oak`, `b_barracks_2`, `portrait_troll`…).
  The procedural canvas art of the original (figures, portraits, fallbacks) is
  baked to PNG by `tools/bake/` through the original renderer; Blender sprites
  are imported as is.

## The 3D battle (Godot addition)

The expedition is one battle for now: `App.launch` takes the army straight into
it, the turn-based rules fight it (`scripts/rules/battle.gd`, the AI, morale,
abilities, fog of war, as in the 2D battles) and a 3D view shows it. When its
end has played, `App.finish_battle` applies it (`Expedition.apply_battle`:
losses, experience, loot) and the company goes home (`Expedition.return_home`:
success on a victory, retreat, defeat). The encounter is a fixed warband
(`App.FIELD_ENCOUNTER`, `brute_vanguard`, no waves) on Ashby farm (`App.FIELD`),
made the expedition's pending battle and saved, so Continue comes back to it.

- `scripts/rules/battlefields.gd` (Deps `battlefields`): a field of the 3D
  battlefields (`prototypes/battlefields3d/scripts/bf_fields.gd`, already a map
  in the rules' format) as a battle map: every thing on it solid (the farm
  things without a rules prop take one; the map is `solidWoods`, so its trees
  and bushes block a move as well, `Grid.tile_passable`) and each side's
  deployment tiles. `Setup.build_battle` takes it as `opts.map`. Every field
  is ringed by woods (`bf_fields.gd`, `_border`), so its edges are closed
  except where its roads run out.
- `scripts/render/battle3d.gd` (Deps `battle3d`, `App.battle_view`): a Node3D
  view with the 2D `battle_view.gd`'s interface (`setup(battle)`, `ui`,
  `select`, `set_ability`, `begin`, `end_turn`, `retreat`, `run_rules`, `pump`,
  `resolve_pointer`, signals `ui_changed` and `ended(result)`), so the battle
  HUD drives it unchanged. Each rules squad takes the field as a squad of the
  3D sandbox's figures (`prototypes/sandbox3d`: `unit3d.gd`, `squad3d.gd`,
  `roster.gd`; `SQUAD_OF` maps the unit types; the footmen dressed by
  `prototypes/squad_looks` when it is on disk). The view plays back the rules'
  events: a march along the rules' path, an attack as a short fight in which as
  many men fall as the rules say, a volley, a spell with the casters' clips,
  words over the squads and the turn banners. Squads' events play side by
  side, turn banners alone. The ground shows the reach (light-edged squares, as
  in the 2D battle), the deployment tiles, the danger (Alt), the march's path
  and the facing it will arrive with; the field's fog (`bf_fog`) shows what the
  company sees. The shadows are the paintings' own for now; `sun_shadows`
  (off) has the sun cast those of the men, the trees, the houses and the
  things instead (the field's `sun_shadows` drops the painted ones). A man
  never stands on a tile the rules keep clear of squads.
  The view is the host `squad3d.gd` expects (`units`, `_squad_of`, `_hostile`,
  `show_route`, `_line_clear`, …).
- `scripts/render/battle3d_field.gd`: the battlefield prototype's ground plus
  what the units need: `walkable` (the rules' solid tiles), `path_to` (A* over
  the tiles, no bank steeper than a figure climbs), fading tree crowns.
- The HUD is the battle HUD (`scripts/ui/battle_hud.gd`, Deps `battle_hud`).

## Painted woodland camp (Godot addition)

`scenes/base/base_view.tscn` instantiates `scripts/render/woodland_camp.gd`, a
presentation subclass of `base_view.gd`. It retains the established setup,
signals, modal dimming, audio listener and camera interface. Its dedicated
constructor skips the old grid layout and asset warming. The original renderer
remains the reference exercised by `test_base_view.gd`; production behavior is
covered by `test_woodland_camp.gd` and the native camp review.

The selected day/night PNGs in `assets/camp/` are exact concept copies. World
coordinates in this view are source-image pixels (2752 x 1536), rather than the
original grid projection. `ANCHORS`, `ZONES` and `ROUTES` are authored in normalized
image coordinates. `building_world_position(id)` is the public interaction anchor
for automation; facility IDs and authoritative building levels remain unchanged.
The camera preserves aspect and clamps to the painting. `camp_woodland.gdshader`
blends the matching lighting plates and applies restrained forest mist. The
night toggle is transient presentation state. Figures follow surveyed polylines
instead of traversing the flattened roofs; these routes are not tactical nav.

This first stage keeps its painted architecture at every building level. Names,
costs and effects read from the current game data. Source hashes, selected takes,
review evidence and limitations live in `../../review/camp-remodel/`.

## Unit playground (Godot addition)

The title's Unit Playground button opens `App.screen = "playground"` without
mutating `App.game`, battle preferences or save files. `--playground` opens the
same screen after boot. Esc returns to the title. The screen owns a SubViewport
and `scripts/render/unit_playground.gd`, a BattleView subclass with its own flat
map and fresh practice units. It submits presentation events to the existing
move, face, attack and death scheduler; combat rules and campaign state are not
run. Pause, exact frame steps and playback rate apply only to this view.

The straw dummy is an isolated practice unit with one surrogate body and an
editable SVG. `playground_draw.gd` overrides only that body's sprite, retaining
the production depth sort, shadows and lighting. It is always invulnerable:
attack previews retain its HP and alive count. A breadth-first route avoids the
dummy and optional comparison unit, then melee troops stop adjacent and missile
troops stop three tiles away. The dummy is not registered in the campaign roster.
War machines keep crews when Single figure is selected. The screen handles
field input separately from the sidebar, disables the inherited battle input,
and suppresses combat audio, command previews, camera auto-follow and battle HUD.

## Input actions (project.godot)

`cam_up/down/left/right` (WASD, arrows), `facing_prev` (Q), `facing_next` (E),
`select_next` (Tab), `end_unit` (Space), `end_turn` (Enter), `redo_move`
(Backspace, Ctrl+Z), `cancel` (Esc), `toggle_grid` (G), `show_danger` (Alt),
`ability_1..4` (1–4), `toggle_fullscreen` (F11). Mouse: left click select/act,
right drag or middle drag pans, wheel zooms.

## Unit bar (Godot addition)

The battle HUD's selected-squad card is the unit bar
(`scripts/ui/unit_bar/unit_info_bar.gd`), after Warcraft III's console. It is
a slab in the bottom centre of the screen that rises when a squad is selected
and sinks when the selection is dropped. From the left it shows the minimap,
the squad's man (live from his 3D figure, `head_portrait.gd`), the middle
(name, rank, turn, stat plaques, status row, the men), the gear and the 4×3
command card. `battle_hud.gd` owns it in place of `Panels.unit_panel`. The hover
panels, forecasts and tile info stay in `hud_battle_panels.gd`, whose helpers
the bar reuses.

A foe can be shown in it too: a right click on a foe in sight (the selection
and a chosen ability stay), or a left click on one while nothing is selected.
Esc, the foe card's Back, a right click on the field or the selected squad's
next order go back (`battle_hud.gd` `inspect`). The HUD has those clicks
before the field; a right drag from a foe is handed back to the view.

It is a view. `bar_data.gd` reads the battle, the view's played-back squads and
the company's records into plain Dictionaries. The commands call the battle
view's own methods, and the view keeps its keys. The console takes the clicks
over it, so none reach the field. Tooltips (`bar_tips.gd`) say where each
number comes from. Placeholder art and what should replace it:
`references/ui/unit_bar_asset_list.md` (Meridius project root). Tests:
`test_unit_bar.gd`, `test_battle_hud.gd`; in a window,
`tests/visual/unit_bar_battle.gd` (the game's 3D battle on Ashby farm, foes
included).

## UI theme contract

The theme (`assets/ui/theme.tres`, built by `scripts/ui/theme_builder.gd`)
defines these type variations; screens use them by name
(`control.theme_type_variation = "ParchmentPanel"`):

| Variation | Base | Look |
| --- | --- | --- |
| `ParchmentPanel` | PanelContainer | Warm vellum, iron binding, brass fittings, dark ink text |
| `ParchmentCard` | PanelContainer | Lighter inset card inside a parchment panel |
| `DarkPanel` | PanelContainer | Charcoal-blue textured HUD panel, narrow metal rim, light text |
| `BannerPanel` | PanelContainer | Blue heading band, metal surround, cream text |
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

`styles/forged_style.gd` extends the paper surface with painted frame roles and
fixed-pixel metalwork. `styles/painted_frames.gd` slices three original RGBA
masters in `assets/ui/epic/`; corners retain their proportions while rails and
quiet centres stretch. Major panels get carved brass fittings and cloth headings;
small buttons and dark panels with less than 12 px of padding use simple rims.
Banner content reserves space for its fixed clasps, even when callers override
padding. Enemy announcements keep a red surface under their metal binding.
`UI.theme_stylebox()` checks explicit overrides before resolving an unattached
control's theme, preserving custom padding when decorating it. The title uses
`assets/ui/frontier_title.png`, a bright forest sunrise with local menu contrast
and no full-screen darkening. No new heraldic symbols are part of the interface.
See [the interface art direction](../../docs/interface-art-direction.md) and
`tools/review_ui.sh` for the native visual/input review.

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
| `scripts/render/{iso,terrain,atmosphere,fx,camera}.gd`, `assets/shaders/{terrain,atmo}*`, `base_view`, `scenes/base/*` | world-render agent |
| `scripts/render/{battle_view,squad_view,formation}.gd`, `scenes/battle/*` | battle-view agent |
| `scripts/ui/*`, `scripts/app/*`, `scenes/main.tscn`, `scenes/ui/*`, `assets/fonts/**`, `assets/icons/**`, `assets/ui/**` | UI agents |

`scripts/core/prefs.gd`: `Prefs.prefs()` → `{muted, battleSpeed, volMaster,
volMusic, volAmbience, volSfx, volVoice}`, `Prefs.set_pref(key, value)`,
`Prefs.set_prefs(dict)` (user://prefs.json).

## Audio (Godot addition)

The original synthesised every sound at play time; `tools/bake` renders those
recipes to `assets/audio/<name>_<i>.wav` + `sfx.json` (rewritten by every bake:
never put other files there). Recorded sound, ambience and music go in
`assets/audio/bank/` and are listed in `assets/audio/bank/bank.json`, which is
edited by hand and never baked.

**Recorded takes** are rendered, not hand-copied: `tools/audio/recipe.json`
names library takes (ids of the audio library's `candidates.json`, kept out of
Git: `$MERIDIUS_AUDIO_LIBRARY`, default `local/audio-library` at the repository
root, gitignored) per
group: whole files, cuts, slices of multi-take recordings, layered mixes,
seamless loops (tail crossfaded into the head), each levelled to a target RMS
with peaks at -1 dBFS. `python -I tools/audio/build_bank.py [group…]` renders
them with ffmpeg, writes their paths into bank.json (events and ambience
entries; other options stay as edited) and records sources, licences, cuts and
gains in `assets/audio/bank/provenance.json`; then `tools/import.sh`. Takes
from CC0 sources (Freesound CC0, Kenney, OpenGameArt CC0) and our own Suno
music are in Git; any take with a Sonniss source goes to
`assets/audio/bank/local/`, which is gitignored (the Sonniss licence forbids
redistribution and the repository is public), and so do the Higgsfield voices
(the owner keeps them out of the public repository). A clone without the library
plays the synth fallback for those. One-shots are mono 16-bit WAV (placed by
the engine), beds and loops Vorbis.

**Kinds**: `battle_view._kind_sfx_at(base, uid, at)` plays the first of
`<base>_<typeId>`, `<base>_<faction>`, `<base>` the bank can play (deaths,
routs, stances, shouts, swings, smashes, `mend` on heal events, `lick`), so a
troll, a hound or a goblin sounds like itself; a stance tries `stance_<id>`
first. Aliases in bank.json (`{"takes": [], "fallback": "death_goblin"}`)
share takes between types with their own pitch and level. The player's men
speak in one commander's voice (Knox): stances, `rout_player`, `victory`. A
stance two types share is voiced per type, not per stance: the footmen's
Defend is `stance_footman` (`stance_defend` would also be the collie guards'),
and the hounds' `stance_collie_guard` and `rout_collie_guard` are a growl and
a yelp, not Knox's orders.

**Orders**: `battle_view._say(line, uid, first)` is a squad answering the
player where the order is given, once per order (a click that moves and then
attacks says only the attack): `select` when the player picks a squad that can
still act (not when the selection moves on by itself: `select(uid, false)`),
`move` for a march, `attack` with `order_<ability>` first (Charge's "Forward,
shields!", Aimed Shot's "Loose!"). It plays the first of `first`,
`order_<line>_<typeId>`, `order_<line>`; flat, so a squad picked off screen is
heard too; none while the last answer still speaks; the hounds
(`QUIET_TYPES`) obey without a word.

**Voices** are generated with `python -I tools/audio/hfvoice.py <round>`
from the line list `tools/audio/voices.json` (speaker, text, model, takes):
through the Higgsfield CLI's own binary, a few jobs at a time, every job in
the library's `voices/higgsfield/receipts.json`, every take registered in its
`candidates.json` for the listening page. `--cost` estimates without creating
jobs. `python -I tools/audio/make_audition.py` rebuilds the listening page
(`audition.html` in the library) from candidates.json.

**Buses** (`default_bus_layout.tres`): Master (hard limiter, ceiling -0.5 dB)
← Music, Ambience, UI, SFX, Voice. Music and Ambience each carry two
compressors keyed (sidechain) from SFX and from Voice: a big hit or a shout
dips the bed a few dB (measured on the Ambience bus with a steady key:
-12.5 dBFS peak → -1.9 dB, -9 dBFS → -4.6 dB, nothing below -15 dBFS; Godot's
compressor doubles the overshoot, hence the low ratios). A key bus must have a
higher index than the bus it ducks (it is mixed first). The thresholds suit
today's synth levels and are revisited in the mix phase. The UI bus has no
slider of its own (Master governs it).

**Bank** (`scripts/audio/bank.gd`): `events` maps an event name to `takes`
(res paths or `{file, volume_db, weight}`) and options: `bus`, `volume_db`, `pitch`
(semitones), `pitch_jitter` (± st), `volume_jitter_db`, `max_voices`,
`min_gap_ms`, `positional`, `fallback`. An event plays its recorded takes that
exist, else the baked synth takes of the same name, else its fallback (options
are inherited along the fallback chain). Takes are picked at random, never the
one played last; a take's `weight` (default 1, a recipe take's `weight` in
recipe.json) makes it come up more or less often, as the page turn heard now
and then (`pick_take`). bank.json also holds `ambience.presets` and `music.tracks`.

```json
"step_large": {"takes": [], "fallback": "step", "pitch": -4.0, "volume_db": 1.5}
"hit_metal": {"takes": ["res://assets/audio/bank/sfx/hit_metal_01.ogg",
              {"file": "res://assets/audio/bank/sfx/hit_metal_02.ogg", "volume_db": -2}],
              "positional": true, "max_voices": 4, "pitch_jitter": 0.4}
```

**Placement** (`placement.gd`): `Sfx.play_at(name, world_pt)` asks the
listening view (`Sfx.set_listener(view)`: a CanvasItem with `cam`; the battle
and garrison views register on entering the tree) where the point is on
screen. Pan follows x (±0.75 at the screen edge, ±1 beyond); the level drops
12 dB per half screen off the edge and 4 dB per halving of zoom below 1;
below -36 dB the sound is not played. The voices are AudioStreamPlayer2D in
Sfx's own 2D space next to a current AudioListener2D, with Godot's distance
attenuation off: Godot only pans them (its 2D law, measured: right gain
0.5 + 0.25·x/width, so +6.02 dB brings a centred 2D voice level with a flat
one). Godot's own falloff is by screen distance, which would make sounds
louder when zooming out, and the views have no Camera2D. UI, banners, horns
and drums stay flat (`positional: false`).

**Voices**: 16 flat + 24 placed. Over an event's `max_voices` the event's
oldest voice makes way; a full pool gives up its oldest. Bookkeeping runs on
the take's length (not the player's state), so it also runs, and is tested,
outside the scene tree.

**Footsteps**: `SoldierAnim.footfalls(uv, m, dt)` counts the feet a man set
down (the contact of `pose()`'s stride); `battle_view._footfalls` gathers them
per squad and plays one tread at most every `STEP_BEAT` (0.19 s), from the
squad's place, a little louder for a full squad, as the first of
`step_<type>`, `step_<size>`, `step` the bank can play. Figures without frames
keep the original's one step per tile.

**Ambience** (`ambience.gd`, inside Sfx): presets `camp` / `camp_night`
(garrison view, following its Day/Night buttons: `woodland_camp.gd`
`set_night`, 6 s), `battle_day` / `battle_night` (battle view, following
`atmo.night`; dawn crossfades over 6 s). A preset has looping `beds`
(equal-power crossfade on change; a bed both presets share keeps playing; one
still fading out when its preset returns turns back, `LoopDeck.revive`),
positional `loops` heard once a view sets their anchor
(`Sfx.set_anchor("campfire", pt)`; one both presets share, same id and file,
burns on), and `oneshots` on a random schedule (`every: [min, max]` s, random
`pan` and `volume_db` ranges, pitch jitter). A preset change crossfades the
one-shots too: the last preset's calls keep coming on their schedule, ever
quieter on the same equal-power curve, and are dropped when the fade ends;
the new preset's rise from silence; going back before the fade ends picks the
same calls up where they were. Files that do not exist are skipped silently,
so the presets, which name the planned files, play nothing until they are
added. Views release their preset when they leave the tree (fade out); the
camp changes the ambience only while one of its own presets is playing.

Beds may have `cycle: {hold: [min, max], quiet: [min, max], fade: seconds}`:
wait in silence, fade in, hold, fade out, then stop/free the player for the next
quiet interval. Their schedules freeze on pause or mute and reset on a preset
change; active fades and the normal pause duck still run. Camp now uses only
the Baltic pine background. Its murmur peaks 6 dB below the previous level,
with 8-second fades, 8–16-second holds and 20–40-second silent gaps. Chaffinch
calls use `every: [10, 25]` and `initial_every: [10, 25]`; other one-shots retain
the earlier first-call spread unless `initial_every` is supplied.

**Music**: `Sfx.set_music(id)` crossfades (3 s) to a track of
`music.tracks`; `App` asks for the track of each screen (`SCREEN_MUSIC`:
title → menu, base/prep/report → camp, battle). No tracks are listed
yet, so nothing plays. Tracks come from the owner's Suno downloads
(`music/suno/<track>/` in the library), named `suno/<track>/<file>.wav` in
`recipe.json`: a group of kind `music` makes stereo Vorbis loops, and a take
`{id, start, bpm, bars}` loops on exactly that many bars from the downbeat at
`start`; its bank entry `{"music": "<track id>"}` fills `music.tracks`. The
player loops every track: stings (victory, defeat; `"loop": false`) and the
battle's tension/combat switch are not played yet.

**Pause, mute, scene change**: Sfx always processes and watches
`get_tree().paused`: world sounds hold and resume with the game, UI sounds
play on, ambience beds dip by `pause_db` (-8) and its one-shots stop, music
dips (-4). Mute mutes the Master bus and starts nothing new (beds run on
silently, so unmuting resumes them). A view leaving the screen stops its
placed voices and fades out its ambience.

**Settings**: the pause menu has a slider each for master, music, ambience,
effects and voices (0..1; dB = 40·log10(v), so half way is -12 dB; 0 mutes the
bus), applied at once and saved to prefs 0.4 s after the last change; Sfx
applies them to the buses at start.

Tests: `tests/unit/test_audio.gd` (bank, placement, voices, buses, prefs,
ambience, music, mute, pause, footsteps), `test_sfx.gd` (the baked layer
against the original's names).
