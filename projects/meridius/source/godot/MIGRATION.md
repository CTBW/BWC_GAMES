# Meridius → Godot 4.7 migration checklist

Source of truth: the TypeScript game in `../game` at commit `dff1262`
(66/66 vitest passing). Status: `[ ]` open, `[~]` in progress, `[x]` done and
verified (with the check that proves it).

## Audit (done 21 Oct 2026)

The original is a 26k-line TypeScript + React + Canvas 2D browser game:
- Rules: tile-grid tactics (14×12 skirmish maps, ~26×22 last-stand maps), one
  squad per tile, squads of 6 (trolls 3, wolf riders 4, rabble 9, horn 4) with
  a shared HP pool, facing from movement, front/flank/rear arcs, height, cover,
  LOS, zones of control, morale/rout, stances (shield wall, spearwall,
  overwatch), abilities, enemy waves held as off-field reserves, war horn,
  warchief, hold/survive/rout objectives, relief at dawn, swarm AI.
- Meta: Amberfeld garrison with six upgradable buildings, recruitment, roster
  with XP/levels/promotions/equipment/injuries/fatigue/morale, reinforcement,
  expedition preparation (slots, command points, supplies, wagon), a
  randomised node campaign map with battles, ambushes, scouting, villages,
  events, camps and an objective; field triage; reports; saves.
- Presentation: isometric Canvas 2D (TW 128/TH 64), painted procedural terrain,
  Blender-rendered prop/building sprites (WebP), procedural Canvas figures (15
  unit types × 12 poses × 6 looks), squad formations and playback animation,
  FX, night/dawn atmosphere, minimap; React HUD and menus; WebAudio synth SFX.

The prompt's "3 columns × 2 rows, 4 squads per cell" battlefield does not
exist in the implementation; per the brief, the implemented rules are
preserved (tile grid, one squad per tile, reserves = enemy waves off-field).

## Foundation
- [x] Godot 4.7.2 found (WinGet), export templates 4.7.2 installed
- [x] Checkpoint commit `dff1262` before changes
- [x] Project skeleton, renderer, window/stretch, input map, autoload stubs
- [x] `js.gd`, `rng.gd` bit-exact (tests/parity/test_core_parity.gd)
- [x] Data tables exported to JSON, `db.gd` (tests/unit/test_db.gd)
- [x] Headless test runner that fails tests on any logged error

## Rules (parity against golden traces)
- [x] grid, squad, battle, ai — 61 golden traces (all 11 encounters, veterans,
      night, last stands with waves/horn/warchief, rare outcomes, 9 scripted
      player scenarios): 1,351 steps, 24,860 events, 39,223 query results
      identical incl. RNG state (test_battle_parity); 87 rule tests pass.
      Worst enemy turn 220 ms (26 squads), mean 117 ms.
- [x] mapgen (all templates), setup (encounters, deployment, waves) —
      120 maps, 132 rolls, 78 setups identical (test_mapgen_parity, test_setup_parity)
- [x] soldier, game (economy, buildings, recruits, upgrades, saves/migration) —
      508 economy steps identical; saves re-save byte for byte (test_meta_parity, test_save)
- [x] expedition, autoplay — 7 driven runs (662 steps) and 5 × 4-expedition
      autoplay campaigns identical to the original (test_campaign_parity)

## Assets
- [x] Figures/portraits/procedural props baked from the original renderer
      (254 keys, 1210 variants; Godot vs browser sheets differ ≤1.2/255 mean;
      `tools/bake/bake.mjs`, tests/unit/test_assets.gd)
- [x] Blender sprites and audio (31 sounds, 91 takes) imported; manifest;
      runtime load tests (tests/unit/test_assets.gd, test_sfx.gd: 18/18)
- [x] Fonts (16 woff2), 37 icons, theme from styles.css (test_ui_theme)

## Presentation
- [x] Terrain painter (GPU, bit-exact hash2/fbm), atmosphere, FX, camera
      (captures within ~1–4/255 mean of the original)
- [x] Battle view: units, formations, playback, overlays, minimap, relief —
      captures within 0.8–2.7/255 mean; 55–79 FPS with the full horde;
      enemy turns on a worker thread; test_battle_view, test_formation
- [x] Base view (~170 FPS), campaign view (~100 FPS)
- [x] UI: title, top bar, garrison panels, roster, prep, campaign HUD with all
      dialogs, battle HUD, report, manual, pause menu; every button audited
      (test_screens, test_campaign_hud, test_battle_hud, test_hud_flow)

## Verification
- [x] Automated suite: lead's final full run `tools/test.sh` on the committed
      tree: 289 passed, 0 failed, 0 skipped (241 s), exit code 0.
- [x] Windows export builds (168 MB, `tools/export.sh`); the exported exe ran
      the smoke self-test: data, 1210 sprites, 31 sounds, AI expedition, all 11
      encounters, garrison/campaign/battle screens. Rerun after the smoke fix:
      passed in the editor build (13/13); re-export + rerun outstanding.
- [x] Input-driven play-through (QA, 21 Oct): `tests/visual/playthrough.gd`,
      windowed 1920×1080, only synthesized input (see README). Final default
      run: 155 checks, 0 failed, 0 errors, 0 orphan nodes, no leak warnings at
      exit, exit code 0 (92 s; one battle won by clicks). Earlier `--full`
      runs covered Save and Quit / Continue, a defeat, a second expedition,
      Retreat from battle, two turns of the last stand and New Company over the
      save (run 5: 548 checks; its remaining failures were bot picking issues,
      not game bugs). Captures in `tests/visual/out/playthrough/`.
- [x] Bugs found and fixed (each with a regression test):
      campaign map logged "Invalid polygon data, triangulation failed" while
      the company marched (zero-area slivers of the host's scorched wash;
      `campaign_view.gd horde_land_parts`, test_campaign_view);
      soldier cards without tags leaked their unparented tag row (39 orphan
      HFlowContainers per play-through = the "CanvasItem RIDs leaked" warning;
      `soldier_card.gd`, test_ui_widgets);
      background texture loads of `Assets.warm_async` never taken from the
      loader (the "ObjectDB instances leaked at exit" RefCounted tokens;
      `assets.gd collect_loaded`, App `_exit_tree`; test_assets).
- [x] Frame times at 1920×1080 windowed, vsync off (RTX 4070), play-through
      averages: garrison 126–144 fps, campaign 73–78 fps, battle 77–84 fps
      (p99 ~55 ms: playback of attacks), last stand deployment 54–60 fps, last
      stand turns 48 fps (p99 60 ms, worst 155 ms), zoomed out on the whole
      field 49 fps. Remaining hitches: opening a view (campaign 270–380 ms,
      battle ~230 ms, last stand ~500 ms), the prep screen rebuild (~100–150 ms
      per change).
- [x] Polish: the loading screen warms the battle view, its HUD, the rules,
      the campaign view/HUD and the screens, and draws one small battle in a
      hidden SubViewport (shaders, figure atlases): first battle opens in
      258 ms instead of 984 ms (second: 231 ms); boot to title 0.7 → 2.1 s
      (`main.gd warm_steps`, `_warm_battle`; test_boot_warm,
      `tests/visual/battle_open_time.gd`). Minimap: no HUD control takes clicks
      over it (checked over the whole rect in the last stand) and a click on
      it moves the camera — no change needed. Letter-spacing: `.btn` 0.03em
      rounds to 1 px for 19 px buttons, 0 at 12/14 px (FontVariation spacing
      is whole pixels); BrandLabel 0.12em = 2 px was already set; theme.tres
      rebuilt (test_ui_theme). Line-height calibration: not done, the HUDs'
      local trims stay (a global change would move every screen).
- [ ] Memory soak over 5+ battles via the debug API with Performance monitors:
      not run (descoped); leaks found by the play-through are fixed above.
- [x] `tools/test.sh --quick`: 287 passed, 0 failed, 8 skipped. Re-export
      (`tools/export.sh`, Meridius.exe 168 MB) + `Meridius.console.exe -- --smoke`:
      SMOKE OK, 13/13 (9.2 s). Full `tools/test.sh` not rerun after these changes.

## Magic and war machines (port of the TS update, 21 Oct 2026)
The TypeScript game gained spellcasters and war machines after `dff1262`
(`../../docs/magic-and-machines.md`); the updated TS sources are in `../game`
on this branch (85/85 vitest) and are again the source of truth.
- [x] Data: `tools/export_data.ts` re-run; only the new content changed (units
      `battle_mage`, `goblin_shaman`, `ballista`, `mangonel`, `rock_lobber`,
      `war_wagon`; their abilities; encounters `shaman_fire`, `siege_train`;
      the last stand's final host and the refugee stand's flank wave).
- [x] Rules: `db.gd` (`is_engine`, `is_active_ability`), `squad.gd` (crew
      nouns, `status_of`/`has_status`, `is_backline`, `move_of`), `battle.gd`
      (spells: reach, chain order, forecast, cast, failure; statuses chilled,
      bloodlust, bleeding with their end-of-turn and bleed ticks; impale;
      unbraced engines; crews move with `move_of`), `ai.gd` (player profiles,
      casters and artillery in the role order, spell choice and aim, engine
      hold, artillery line of sight), `setup.gd`, `soldier.gd`, `game.gd`
      (one specialist per muster), `expedition.gd` (bolts only for `shot.ammo`).
- [x] Parity: battle traces now 77 (+ `shaman_fire`, `siege_train` and a
      scripted magic company: every spell, impale, chained and failed casts,
      `canCast`/`spellTargets`/`spellPreview`/`impaleTarget` queries); 30,361
      events and 41,064 query results identical incl. RNG state. Setup, meta and
      campaign goldens regenerated and identical. `test_spells.gd` (19 rule
      tests); `test_squad.gd` sizes; `test_save.gd` now takes the first choice an
      event allows (the new RNG path reached a pedlar the company could not pay).
- [x] Assets: `fig_battle_mage`, `fig_goblin_shaman`, `fig_engineer` (6 looks)
      and `engine_<type>` atlases (3 looks) baked from the original renderer,
      portraits, 11 new sounds (42), 10 new icons (47); test_assets, test_sfx.
- [x] Battle view: engines and crews in formation, spell and condition FX
      (`fx.gd`, `battle_fx.gdshader`), condition tints in `battle_sorted.gdshader`,
      wrecks; `tools/parity/battleview_engines.ts` →
      `tests/fixtures/battle_view/formation_engines.json`; `tests/visual/magic_lab.gd`
      (captures in `tests/visual/out/magic/`).
- [x] HUD: spell buttons and keys, spell forecast on hover, impale target,
      conditions on cards and tooltips, crews and engines on soldier cards and
      the detail screen, the Barracks' specialist, manual pages;
      `tests/visual/capture_magic.gd` (captures `tests/visual/out/magic_*.png`).
- [x] Verification (worktree, uncommitted): full `tools/test.sh` 337 passed,
      0 failed, 0 skipped (273 s), exit code 0. Its exit printed leak warnings
      from `test_ui_widgets::test_labels_and_tags` (unchanged on this branch: two
      `sign_label` Labels never freed); fixed in the test. Re-export
      (`Meridius.exe` 183 MB) + `Meridius.console.exe -- --smoke`: SMOKE OK
      13/13 (1588 sprite variants, 42 sounds, all 13 encounters, 11.3 s).
      Play-through (default): 236 checks, 0 failed, 0 errors; an earlier run
      took a different random path and failed 2 checks on the shared-tile bug
      fixed below.
- Deliberate differences from the original: the engine stays until its wreck
      appears (the original stops drawing it when the last crewman falls, a
      moment before the squad's `down` event leaves the wreck;
      `battle_draw.gd _engine_stands`); cancelling a spell (Esc) clears its
      forecast at once rather than on the next pointer move; tall tooltips are kept whole on screen (`widgets/tip.gd`).
- Original bug, ported as is and then fixed in Godot only (next section):
      two squads could end a move on one tile.

## Original archived; first Godot-only rule change (21 Oct 2026)
The TypeScript original is archived (`../game/ARCHIVED.md`): it stays in place
for the sprite bake, unchanged, and is no longer kept in step. Godot is the
only version developed.
- [x] Bug: two squads could end a move on one tile. A path could cross a
      routing enemy (`reach_states` skipped only active foes) while `walk`
      stops in front of any enemy, so the move ended short, sometimes on the
      ally's tile the path passed through; and a squad passing through an
      ally's tile could be broken there by a free attack (or halted by a
      spearwall) and stay. A headless stress run (every encounter, AI on both
      sides) found 9 shared tiles in 33 battles on the pre-port code; with
      routing foes blocking, 7 in 520 remained, all from free attacks.
- [x] Fix (`battle.gd`): routing enemies block paths like any enemy; and a
      walk that ends on a tile another squad holds falls back along its path,
      still facing its way, to the last tile the squad had to itself (a `move`
      event with `backward: true`; such a move cannot be redone). The view
      backs the squad off without turning it (`battle_view.gd _play_move`).
      Stress run after the fix: 520 battles (40 seeds × 13 encounters), no
      shared tile after any squad's action or enemy turn. Balance, 60
      companies × 6 autoplay expeditions (the seeds of the original's
      `scripts/simcampaign.ts`): success 37.5% → 39.8%, defeat 21.0% → 18.6%,
      deaths about 1.0 per expedition both ways; within the noise of ~355
      expeditions.
- [x] Tests: `test_battle.gd` (the old "kept as is" case now asserts the fix;
      a blocked walk and a broken squad fall back; no two squads share a tile
      in any encounter, two seeds each); `test_facing*.gd` expect the facing of
      the last step forward. Visual: `tests/visual/magic_lab.gd -- fallback`
      (footmen broken by a free attack in the spearmen's tile back off to their
      own, still facing their way; checked in the contact sheet).
- [x] Goldens: the battle traces and the campaign runs are now the port's own
      regression baseline, re-recorded with
      `MERIDIUS_RECORD=1 tools/test.sh test_battle_parity test_campaign_parity`
      (record mode in both tests; `test_campaign_parity.gd` carries a port of
      the run driver of `tools/parity/campaign_golden.ts`). Checked against the
      original's recordings: 47 of 77 battle traces and all five driven runs
      without AI battles came out identical (so the recorder and the ported
      driver are exact); the 30 other traces, the two AI-battle runs and the
      autoplay campaigns changed where the fix changes play. The TypeScript
      generators carry an "ARCHIVED: do not re-run" note.
- [x] Leak: `test_ui_widgets::test_labels_and_tags` freed two of its labels
      only at exit (warnings after the full suite); fixed.
- [x] Verification (worktree, uncommitted): full `tools/test.sh` 340 passed,
      0 failed, 0 skipped (258 s), no leak warnings at exit. Re-export +
      `Meridius.console.exe -- --smoke`: SMOKE OK 13/13. Play-through
      (default): 213 checks, 0 failed, 0 errors, exit code 0.

## Resume here
1. `tools/test.sh` (full) — green with magic, war machines and the
   shared-tile fix (340/0), not yet committed.
2. `tools/export.sh && build/windows/Meridius.console.exe -- --smoke`.
3. Commit on branch `godot-migration`.
