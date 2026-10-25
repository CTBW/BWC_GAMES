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

## Squad skills (22 Oct 2026, Godot only)
Every company squad gets its own kit (`../../docs/squad-skills.md`): footmen
Charge and Defend (beside Shield Wall, Shield Bash on promotion), spearmen
Square, crossbowmen Aimed Shot, and the Border Collie Royal Guard its own four
(Growl, Charge, Defend, Lick Wounds) in place of the footmen's Shield Wall and
Shield Bash; since 23 Oct its promotion is Howl, which replaces Growl.
- [x] Data: 7 abilities in `data/abilities.json` (`shield_charge`,
      `hound_charge`, `defend`, `square`, `growl`, `lick_wounds`,
      `aimed_shot`; new keys `minRun`, `still`, `ignoreCover`, `selfHeal`,
      `selfMorale`, `cleanse`, `calm`, `short`); kits in `data/units.json`.
- [x] Rules (`battle.gd`): `_run_short` (a charge's run, an aimed shot's
      stillness) in `preview`/`preview_legal`; `guard_of` and the guard
      taking the blow in `preview` and `_resolve_attack` (attack event
      `ward`); a square in `arc_of` (no flank or rear), its +6/−10 defense, no
      push, broken charges (`_charge_broken`, also the orcs' Brutal Charge);
      the `cowed` condition (−10 to hit); `can_shout` and `_tend` (Lick
      Wounds); Growl lays its status from `shout`. With none of these in play
      every path is unchanged: the 77 battle traces (old kits in their
      setups) still match, 41,064 query results included.
- [x] AI (`ai.gd`): Growl only when foes are close (not for shaky allies);
      Lick Wounds left out of the leaders' shouts and used by the company's
      automation below 65% HP with no enemy beside. Attack skills are weighed
      like any attack ability.
- [x] HUD: buttons disabled with the reason (Lick Wounds beside an enemy, an
      aimed shot after moving), the Cowed chip, a guard note in the attack
      forecast, short button words (Shield Wall "Wall", Shield Bash "Bash");
      manual paragraphs. Icons: 7 SVGs in `assets/icons/` (imported at 4× like
      the rest), listed in `widgets/icon.gd`.
- [x] Goldens: `campaign_golden.json` re-recorded
      (`MERIDIUS_RECORD=1 tools/test.sh test_campaign_parity`); the scripted
      runs and the generated expeditions are identical apart from the ability
      lists, the two AI-battle runs and the autoplay campaigns changed with the
      new skills. `meta_golden.json` has no recorder: instead of retiring ~100
      cases, `test_meta_support.gd` (`OLD_KITS`, `current_kits`) reads its
      recorded ability lists in today's kits and only those (any other list
      still fails). Every other field is still compared as recorded. `setup_golden.json` is unaffected
      (its armies carry their own lists).
- [x] Balance (autoplay, both kits on today's rules; the old kits patched in
      memory): 60 companies × 6 expeditions (the seeds of the original's
      `scripts/simcampaign.ts`; the old kits reproduce the last recorded
      39.8% / 18.6%): success 39.8% → 45.6%, retreat 41.5% → 38.6%, defeat
      18.6% → 15.8%, deaths per expedition 1.03 → 0.88 (354 / 360
      expeditions; about two standard errors on success). Single battles,
      12 seeds × 13 encounters with a level-2 company of footmen ×2,
      spearmen, crossbowmen ×2 and a Royal Guard: victories 155 → 154 of 156,
      soldiers lost per battle 4.79 → 3.63. The company is stronger; not
      retuned (a design call for the owner: cooldowns, Defend's coverage or
      the encounters are the levers).
- [x] Tests: `test_squad_skills.gd` (15), `test_battle_hud::test_squad_skill_buttons`.
      Full `tools/test.sh`: 356 passed, 0 failed, 0 skipped (289 s).
- [x] View (owned by the animation session): status/stance names, Growl and
      Lick Wounds shouts, no frenzy tint or blood for the cowed — applied
      there, with a "Guarded!" effect.
- [ ] Effects per `../../docs/squad-skills.md`, after the squads' frames.

Follow-up, 23 Oct 2026 (owner decisions: Defend stays a bodyguard but catches
one blow per stand; Shield Bash stays a promotion; the Royal Guard is promoted
to Howl; no rebalancing):
- [x] Defend: a guard that catches a blow is `guardSpent` until the start of
      its next turn (or its next stance), so `guard_of` passes it over and
      later attacks reach their target. Description, manual and spec updated.
- [x] Howl (`howl`): a shout with `upgrades: "growl"`, radius 3, −16 morale,
      cowed for 2 turns, cooldown 3; `collie_guard.promotion`. An `upgrades`
      promotion takes the place of that ability (`Soldier.kit`, shared by
      `abilities_of` and the meta golden's `current_kit`), so the bar stays at
      four keys. Soldier panel: "Promotion: Growl becomes Howl". Icon
      `assets/icons/howl.svg`.
- [x] Meta golden: the Royal Guard is promotable again, as recorded, so the
      special case for its `canPromote` is gone; recorded promoted lists read
      as `Soldier.kit(..., true)`.
- [x] Campaign golden unchanged by these two: the skills committed on their
      own (without fog of war) pass the full suite, campaign parity included
      (24 Oct 2026: 358 passed, 0 failed, 0 skipped). With fog of war on it
      differs (its entry, "Campaign baseline recording … deferred at the
      user's request"); the owner kept that re-recording on hold (24 Oct
      2026). The balance figures above predate both changes and fog.
- [x] View (24 Oct 2026, owner's go-ahead): Howl shares Growl's branch in
      `battle_view.gd`'s `"shout"` case, its rings scaled by the radius (3
      tiles to Growl's 2); checked in a window (`capture_skills.gd --
      use_growl use_howl`). It is in the animation session's uncommitted
      view work and goes in with it; until then Howl plays the War Cry's
      effect. Its sound is still the growl's roar.
- [x] Tests: `test_squad_skills.gd` (17; new: one blow per stand, Howl).
- [x] Two forecast and panel quirks (24 Oct 2026): against a square the
      forecast shows the charge's own row (+5 / +12) and "Charge broken by the
      square" taking it back (−5 / −12) instead of a 0 row, so the rows still
      add up; the chance is unchanged. The unit panel's signature carries each
      shout's `can_shout` reason, so Lick Wounds greys out (and comes back)
      when an enemy steps beside the squad (or leaves) while it stays selected.
      Left as is: the forecast's guard note needs an enemy with Defend, and
      none has it (a design call); charge aiming tries only the side under the
      cursor (`battle_view._preview_against`, the animation session's file).
- [x] Icons on the battlefield (24 Oct 2026): the words beside a squad's bar
      for its stance (WALL, SPEARS, WATCH, GUARD, SQUARE) and its conditions
      (CHILLED, FRENZY, BLEEDING, COWED) are now the skill icons, on 22 px
      dark badges (gold rim for stances, the condition's colour for
      conditions); `battle_draw.gd` `draw_overlays`, `stance_icon`,
      `STATUS_ICON`. Fleeing, ★, Warchief and the horn stay words. Test
      `test_squad_skills::test_every_stance_and_condition_wears_its_icon_on_the_map`;
      checked in a window (`capture_skills.gd -- stances badges`).
      The badges show the painted icons (`Icon.painted`,
      `assets/icons/painted/`, keyed from the magenta-ground paintings by
      `tools/ui_key_icons.py`), the SVG where none is painted (Howl).

## Resume here
1. `tools/test.sh` (full) — green with magic, war machines and the
   shared-tile fix (340/0), not yet committed.
2. `tools/export.sh && build/windows/Meridius.console.exe -- --smoke`.
3. Commit on branch `godot-migration`.

### 2026-10-24 - Painted rocks

The `rock_small` ("Stones") and `rock_large` ("Boulders") props are now painted
in the concept A style instead of the Blender renders: four variants each from
one Nano Banana Pro sheet (`review/rocks/rocks_sheet_1.png`, sha256 in
`assets/sprites/painted/rocks_sources.json`), cut by
`tools/props/rock_cutout.py` (magenta key, pieces kept whole by the cell holding
their centre, baked soft contact shadow down and right, `noShadow`, `art`).
Rules are unchanged: tiles keep their `v` (0-9999) and the view picks
`v % 4` instead of `v % 2`. The original drew two variants, so
`test_assets` retires those two counts from `variant_counts.json` and pins
four (`REPAINTED`). Native battle, campaign and relief-lab captures: 0 errors.
With `--texture assets/terrain/rock.webp` the stone takes the terrain's rock
texture (its grass tufts and lichen filled out first): its colour and fine grain
under the painted light, outline and moss, so the props read as the same grey
stone as the relief's bank strata and fallen blocks.

### 2026-10-24 - Painted woodland

The `tree_pine`, `tree_oak` and `bush` props are now the painted woodland the
terrain lab trialled (`assets/terrain/woodland/`, `scripts/render/woodland_kit.gd`)
instead of the Blender renders, in battles, on the campaign map and in the
garrison. `tools/props/woodland_cutout.py` keys the pine, beech, oak and shrub
paintings out of their magenta backdrop (the rock cutout's key), bakes the cast
shadow the game draws for props (the silhouette skewed by (1, 0, -0.75, -0.32),
alpha 0.2 for trees and 0.16 for the shrub, softened 2.5 px) and writes
`assets/sprites/painted/woodland_<name>.webp` at 3 sprite px per world px, with
mipmaps; `woodland_sources.json` records each painting's sha256. Root anchors and
heights are the lab's (the whole painting 350, 310 and 285 world px for pine,
beech and oak), so a pine stands about a fifth taller and half again as wide as
the Blender one; the shrub is 87 rather than the lab's 66 so it covers the bush
prop's footprint. The paintings keep their own colour (the lab grades them darker
for its textured ground). Three variants each, as the original drew: one painting
at sizes 1.0, 0.9 and 1.1; `tree_oak` is beech, oak and a smaller beech.
`noShadow` keeps the game from mirroring them, since their light is painted from
the upper left. Rules are unchanged. The ferns stay in the lab: they are
presentation-only undergrowth and need a change to `battle_draw.gd` (since
made: see Terrain kit 2 below).
`test_assets` retires the original's `tree_pine` hit mask (`REPAINTED`) and pins
the new pine anchor. In the terrain lab the Painted woodland toggle now compares
the lab's keyed paintings with these sprites rather than with the Blender trees.
A sprite re-bake writes the Blender trees back (tools/bake/README.md). Native
battle (deploy, march, night), campaign and garrison captures: 0 errors; frame
times unchanged against the Blender trees (`battle_fps.gd`, campaign capture).

### 2026-10-24 - Terrain kit 2: more trees, stumps, logs, stones and ferns

A second Nano Banana Pro set in the same style (Workspace: Terrain kit 2;
originals in `local/workspace-originals/2026-10-20_meridius/terrain-kit-2/`,
sha256 in `assets/sprites/painted/woodland_sources.json` and
`stones_sources.json`) adds variety to the woodland. Rules are unchanged: tiles
keep their `v` and the view picks `v % n`, so the new variants appear wherever
the keys are drawn (battles, campaign map, garrison) with no code change.

- Trees, summer only, to match the current battlefield. `tree_pine` has 7
  variants (pine at 1.0, 0.9 and 1.1, spruce at 1.0 and 0.9, Scots pine, young
  fir) and `tree_oak` 8 (beech at 1.0 and 0.9, oak at 1.0 and 1.1, birch at 1.0
  and 0.9, willow, young oak). `tools/props/woodland_cutout.py` grades each
  painting in CIELAB to the battle's palette (`GRADE`): the birch's pale yellow
  crown is darkened and muted, the spruce and Scots pine lose their blue cast
  (more so in the light), and the bark from the trunk sheet is darkened and
  desaturated to the grey-brown of the other trees.
- Other seasons are cut and listed but not drawn yet: `tree_oak_autumn` (red
  maple, golden aspen, copper beech) and `tree_oak_spring` (blossom at 1.0 and
  0.9), for battlefields still to come.
- `stump` (3: old, sawn, rotten) and `log` (4: fallen, hollow, mossy, stacked)
  are painted pieces from one trunk sheet, cut by box (`PIECES`), with a skewed
  cast shadow for the upright stumps and a soft contact shadow for the lying
  wood. Mapgen places stumps; logs still appear only in the terrain lab's
  fields.
- `deadwood` (5: branch, mossy log, fallen and hollow logs at smaller sizes)
  and `stones` (10 small stones from a 2x5 sheet, cut by
  `tools/props/rock_cutout.py --stones` and retextured with the terrain's rock
  like the boulders) are new keys for scatter decoration.
- Battles now strew this decoration: `battle_draw.gd` `_prop_list()` adds a
  fern on about two forest tiles in three (up to a third of a tile off
  centre), fallen wood at the foot of about one tree in four (on the near side
  of the trunk, inside its tile) and small stones on about one open grass or
  dirt tile without a prop in twelve. They are `"under"` props tagged with
  their `decor` key, never mirrored and never swaying, and stand on their
  tile's own height (`_tile_h` truncates a negative offset onto the
  neighbour). Presentation only: tiles, paths, cover and line of sight are
  unchanged. `test_battle_ferns` checks where each kind stands and that the
  map is left alone.

`test_assets` pins the new counts (`REPAINTED` retires the original's stump and
log counts; `ADDED` covers the new keys) and checks every new variant is
painted, keeps its light (`noShadow`) and has its anchor inside the sprite.
The woodland sprites have mipmaps; the stones, like the rocks, do not. Native
battle deploy captures and day and night close-ups of the fallen wood: 0 errors.
