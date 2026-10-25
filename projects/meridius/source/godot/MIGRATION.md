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

## Footman animation (22 Oct 2026, Godot only)
The footmen are the first frame-animated figures: the Higgsfield pixel-art
keyframes in `../game/art/sprites/footman_anim` (read only) replace the baked
procedural footman in battle. Every other figure is unchanged.
- [x] Frames: `tools/anim/build_footman.py` (art venv: Pillow, numpy, scipy)
      writes `assets/sprites/anim/footman.png` (4096×2048 atlas, mipmaps) and
      `footman.json` (36 frames × 6 soldiers; scale 0.47981, so a footman
      stands as tall as the figure he replaces). The generated walk keys led
      with the same leg in both steps (a limp) and changed the upper body
      between keys; `tools/anim/legs.py` builds every walk key on one upper
      body and swaps only the legs: contact, passing (idle legs), other foot
      forward (the legs mirrored). `--aseprite <exe>` also writes editable
      `art/footman/footman_<f|fs|b|bs>.aseprite` (a layer per soldier, tags
      idle/walk/strike/death, the game's timing; `art/` has a `.gdignore`).
- [x] Playback: `scripts/render/soldier_anim.gd`. Each man has his own
      breath tempo and stride phase (from `phase`), joins and leaves a march a
      moment apart, rises on the passing step, leans into the march (more when
      routing) and rocks back when struck, and trails the moving anchor at his
      own pace (`Member.drift`, at most 14 px). Falls are frame by frame
      (recoil, kneel, down) over 0.95 s instead of the 0.5 s tip-over; from the
      front the last frame is the body left on the field, from behind the
      slump settles into it. Melee (`battle_view._play_drilled_melee`): every
      man winds up, cuts, holds and recovers on his own beat, front rank first;
      the squad's damage still shows once, at the first blow, and the slain drop
      as later blows land. Rules, damage and timing of other squads unchanged.
- [x] Shared code touched only through new, inert defaults: `Member.key`,
      `drift`, `death_dur` (0.5 for every other type), `UnitView.anchor_prev`.
      `test_formation::test_fall_and_reform_sequence_matches_the_original`
      stages a footman squad, so it now pins the original's 0.5 s fall
      explicitly and asserts the footman's 0.95 s; the golden still holds.
- [x] Visual check: `tests/visual/footman_lab.gd` (facings, march, melee,
      deaths), contact sheets reviewed. Base and campaign screens still show
      the procedural footman (`footman_idle_f`…), which `test_assets` pins to
      the original's bake.
- [ ] Better art, if wanted (paid): real opposite-leg walk keys and push-off
      frames (the mirrored legs are clean at game zoom, rough at native size),
      a hit/flinch frame, a raised-shield frame for the shield wall, a re-cut
      of the NE thrust (cape and blade tips clipped by the original cut).

## Every squad in pixel art (22 Oct 2026, Godot only)
All 20 battle figure types and the four war machines are now Higgsfield pixel
art (`nano_banana_pro`, 2K sheets), animated by `soldier_anim.gd` like the
footmen. The baked procedural figures remain only for garrison, campaign,
portraits and icons (`assets/sprites.json`, pinned by `test_assets`).
- [x] Pipeline (`tools/anim/`, art venv): `units.py` (what each figure looks
      like and holds, per facing), `prompts.py` (front sheet from the footman
      style sheet plus the game's figures; back view; hand swap for the
      mirrored facings of shield units; one edit per action: walk step,
      wind-up, blow, kneel, fall), `squadgen.py` (references, cutting by grid
      slot with feet registered to the standing sheet, stray-speck removal,
      falls re-laid with room, build to `assets/sprites/anim/<type>.png/.json`
      with its own `.import`), `hfgen.py` (the Higgsfield CLI's `hf.exe`
      directly, since the npm shim cuts prompts at the first line break; job
      ids in `art/raw/<type>/jobs.json`; `auto` runs a type stage by stage,
      `edit` changes a finished sheet). Second walk step: the first step's
      legs mirrored (`legs.walk_keys_any`), the generator always leads with
      the same leg. Raw sheets in `art/raw/` (ignored), cut frames in
      `art/squads/`.
- [x] Heights: each figure keeps the in-game height of the figure it
      replaces, except goblins (spearmen, archers, rabble, horn-bearers,
      shamans): two thirds of an orc warrior (`rel` in `units.py`). The
      approved goblin designs (realistic proportions, small heads and eyes)
      come from the goblin chat's sheets in `../../review/goblins-v2/`; the
      rabble carries improvised shields and is drawn in four facings.
- [x] Back views must face away: a strict orientation paragraph in the back
      prompt (back of the head to the viewer, weapon and mount pointing to the
      upper right); crossbowmen, orc brutes, trolls, wolf riders, lancers,
      mages, engineers, orc warriors and the goblins were redrawn for it.
- [x] Turning to the target (`SoldierAnim.turn_to/turn_back`, `Member.face`):
      the rules keep a squad's facing when it strikes or shoots off its front
      (flanks and rear stay where they were), but its men turn to the enemy
      one by one, front rank first, and turn back one by one afterwards;
      casters turn to the spell's target. War machines keep their line.
      `tests/visual/footman_lab.gd -- unit=<type> turn` films it.
- [x] Machines: one sheet each (ready and loosing, front and back) drawn
      through `battle_draw.engine_of`; the relief lancers gallop with frames.
- [x] The upper-right view (facing 3, the company's usual march toward the
      horde): on this camera a step up-right is two pixels right for one up,
      so the men must be turned well to the right, back and whole right side
      showing. The generator draws rear views nearly straight from behind (they
      read as walking up-left), but it reliably draws the turn toward the upper
      left: frame `base_t` (`prompts.base_back_turned`, angle references
      `art/raw/_refs/angle_n.png` and `angle_w.png` from the footman
      turnaround) asks for that, with the hands mirrored, and `hfgen.py` mirrors
      each grid cell. The company's squads were redrawn this way; the footmen
      moved into `squadgen.py` (their approved SW and SE drawings are the
      starting sheets; `build_footman.py` is superseded).
- [x] Trolls twice as big (`units.py` `rel=("troll", 2.0)`,
      `SquadView.member_height` 132, a wider triangle `Formation.TROLL_SPREAD`
      inside the tile, contact shadows doubled). The troll cases of the
      formation goldens (`formation.json` members, `formation_engines.json`
      slots and members) are retired, `test_formation::test_trolls_doubled`
      checks the new triangle; every other case still compares as recorded.

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
      2026) until fog of war was committed, and it was re-recorded then (see
      that entry). The balance figures above predate both changes and fog.
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
- [x] Charge aiming (25 Oct 2026, owner's OK): when the side under the cursor
      is too close for a charge's run (`minRun`), `battle_view._preview_against`
      takes the nearest side to the cursor whose forecast is legal, and the
      cursor's side only when none is (its reason stays, a hidden target's
      fog reason too). Other attacks still take the side under the cursor.
      Spec updated (`../../docs/squad-skills.md`, Charge). Test
      `test_battle_view::test_a_charge_aimed_too_close_runs_in_from_the_nearest_side_with_a_full_run`;
      checked in a window (`capture_skills.gd -- charge_close`).

## Audio engine, phase 1 (22 Oct 2026, Godot only)

Plan: `../../docs/plan-audio.md`. The engine that recorded sounds, ambience and
music will play; nothing recorded is added yet, so the game still sounds like
the original (the baked synth takes), now placed on screen and mixed on buses.
Details in ARCHITECTURE.md, *Audio*.

- [x] Buses (`default_bus_layout.tres`, loaded by Godot by default): Master
      with a hard limiter; Music, Ambience, UI, SFX, Voice. Music and Ambience
      are ducked by compressors keyed from SFX and from Voice. Godot's
      compressor doubles the overshoot (a ratio 2.5 first dipped the bed
      12 dB under a -6 dBFS key); the shipped settings were measured with a
      steady key on the Ambience bus: -12.5 dBFS → -1.9 dB, -9 dBFS → -4.6 dB,
      nothing below -15 dBFS. Steps (-37 dBFS) never duck.
- [x] Sound bank `assets/audio/bank/bank.json` (`scripts/audio/bank.gd`):
      event → takes and bus, level, pitch, jitter, voice limit, gap,
      positional, fallback. Shipped with routing only: the UI names (click,
      select, deny, page, coin, build, turn) on the UI bus, the battle's on
      SFX and placed, horns/drums/banners flat; `step_small/medium/large` and
      `step_troll`, `step_wolf_rider`, `step_collie_guard` fall back to `step`
      (pitched for size). The original's gaps (step 70 ms, else 25 ms) are
      kept. Ambience presets and music tracks name the planned files; missing
      files are skipped silently (20 listed, none added). Takes never repeat
      back to back. `Sfx.play(name)` is unchanged for its callers.
- [x] Placed sound: `Sfx.play_at(name, world_pt)` through the listening view's
      camera (battle and garrison views register on entering the tree).
      AudioStreamPlayer2D voices in Sfx's own space with a current
      AudioListener2D, Godot's distance attenuation off; pan and level from
      `placement.gd` (why: ARCHITECTURE.md). Godot 4.7.2's 2D pan law was
      measured with an AudioEffectCapture (right gain 0.5 + 0.25·x/width,
      centre 6.02 dB under a flat player) and is compensated. All battle
      sounds of a squad or an impact point use it: blows, swings, hits,
      blocks, misses, volleys, bolts, deaths, routs, stances, shouts, spells,
      explosions, engines, the relief's hooves, deploy steps.
- [x] Voice limits: 16 flat + 24 placed voices (was 24 flat); over an event's
      `max_voices` its oldest voice makes way; a full pool gives up its
      oldest. Far off-screen sounds (below -36 dB) take no voice.
- [x] Footsteps: from planted feet. `SoldierAnim.footfalls()` counts the
      contacts of `pose()`'s stride per man; `battle_view` plays one tread per
      squad at most every 0.19 s, from the squad, ±dB by how many men are
      left, as `step_<type>` → `step_<size>` → `step`. Before: one `step` per
      tile per squad (about 3.8 a second while marching); now about 5 a
      second, starting with the first man to move and ending with the last to
      halt. Figures without frames keep the per-tile step (none today).
      Measured: six footmen marching 2 s set down ~50 feet, 10 treads heard.
- [x] Ambience player (`ambience.gd`): presets camp / battle_day /
      battle_night with crossfaded beds, positional loops (the camp's fire)
      and random one-shots; garrison view → camp, battle view → day or night
      (dawn crossfades over 6 s); views release their preset on leaving.
- [x] Music player: `Sfx.set_music(id)`, 3 s crossfade on the Music bus;
      `App` asks for the track of each screen. No tracks yet: nothing plays.
- [x] Pause: Sfx now always processes. Before, the Sfx autoload paused with
      the tree, so the menu's own "page" sound froze when the menu opened and
      played on closing. Now UI sounds play while paused, world sounds hold and
      resume, the ambience dips 8 dB and its one-shots stop, the music dips 4 dB.
- [x] Mute: also mutes the Master bus (ambience and music keep their place
      and resume on unmute); remembered as before.
- [x] Volume sliders in the pause menu (master, music, ambience, effects,
      voices; prefs `volMaster`…`volVoice`, 0..1, dB = 40·log10(v)), applied
      at start. Theme: HSlider styles in `theme_builder.gd` (the bars' track
      and gold fill, a brass knob); `assets/ui/theme.tres` not regenerated
      (the game builds its theme at run time).
- [x] Tests: `test_sfx.gd` changed deliberately: `names()` may now be longer
      than the original's 42 (bank events), the baked takes are checked
      through `bank.synth`, and `variant_count` equals the baked count only
      while a name has no recorded takes. New `test_audio.gd` (18): buses,
      bank resolution and fallback, no-repeat picking, voice limits,
      placement, pause, mute, volume prefs, ambience crossfade / missing
      files / one-shots / positional loop, music, the camp hooks, footfalls
      and per-squad treads. Full `tools/test.sh`: 375 passed, 0 failed,
      0 skipped (355 s).
- [x] Checked in a window (WASAPI, 48 kHz): camp → battle (day) with two AI
      turns → pause menu → night battle → camp, listener, ambience and music
      following each scene, steps by kind (step_medium, step_small,
      step_troll), no error or warning logged. Pause menu captured
      (`tests/visual/ui_capture.gd -- title base menu`). Technical checks only:
      nothing was listened to for the mix.
- [x] Phase 2 started below (recorded takes).

## Audio, phase 2: recorded sound in the game (22 Oct 2026, Godot only)

Recorded takes replace the synth ones for 34 of the original's 42 sounds plus
34 kind events (step, death, swing, stance, shout, mend and lick by type) (still synth: deny, turn, relief, defeat, hooves
and the generic roar, which no unit uses now; victory and the player's rout are voices since 24 Oct); chosen by Claude from the audio library's descriptions and
measurements, not yet by ear (the owner swaps takes on
`local/audio-library/audition.html`, where they are marked "in game").

- [x] Library kept out of Git (`local/audio-library` at the repository
      root, gitignored; `E:/ProjektM/audio-library` until 24 Oct, when it
      moved into the repository's `local/`; 625 candidates then): Sonniss GDC 2015–2020 and 2026 bundles, Freesound CC0
      previews, OpenGameArt CC0, Kenney, and Higgsfield (Eleven v4) orc war
      cries pitched down 5 semitones. Licences per source in its LICENSES.md.
- [x] `tools/audio/build_bank.py` + `recipe.json` (ARCHITECTURE.md, *Audio*):
      59 groups → 252 files (44.5 MB): cuts, slices of multi-take recordings,
      layered takes (e.g. a death = voice + armour falling 0.3 s later; a
      squad's tread = two or three boots and a little mail), seamless loops,
      levelled; `provenance.json` records every source, cut and gain.
      115 files have a Sonniss source and live in the gitignored
      `assets/audio/bank/local/` (the licence forbids redistribution and the
      repository is public); 137 (CC0, Kenney, Higgsfield) are in Git.
- [x] Kinds: `battle_view._kind_sfx_at` (hooks agreed with the animation
      session, sound calls only): deaths, routs, stances (`stance_<id>`
      first), the growl, the war cry, swings and the wagon's smash resolve
      `<base>_<typeId>` → `<base>_<faction>` → `<base>`. New: the horde's
      wave roar is `roar_wave` (was the hounds' growl), Lick Wounds plays
      `lick`, and a heal event plays `mend_<type>` (trolls only). Bank
      aliases share takes (`death_goblin_*`, `step_orc_*` with their own pitch).
- [x] Mix: `recipe.json` `levels` sets each event's volume_db. A captured
      play-through (`--write-movie`, game audio measured per second) first
      ran at -15 LUFS with the master limiter working in 74 of 104 s;
      rebalanced (steps -16 dB, hits -7, swings -10, spells -4…-10, voices
      and horns -3…-4, UI -8): -19.4 LUFS, limiter in 1 of 102 s, peaks
      typically -4…-6 dBFS. Video: `local/audio-library/captures/`.
- [x] Leak at quit: Vorbis beds and loops still playing at exit left their
      playbacks in the AudioServer ("20 ObjectDB instances leaked", "5
      resources still in use"); `Sfx._exit_tree` now stops the music, the
      ambience decks, its one-shots and every voice. Verified with
      `--verbose`: none.
- [x] Tests: `test_audio` changed deliberately: recorded takes may play
      (only files under `bank/local/` may be missing, every take has a
      provenance entry, aliases resolve), ambience plays the files a preset
      has, placement reads the event's level, and the footfall count uses
      `SoldierAnim.gait_phase` (per-type stride since the animation's gait
      change).
- [x] The owner's picks by ear (24 Oct; `../../docs/audio-picks.md`): liked
      takes replace the unrated ones of their sound, rejected ones are out
      (every sword clash: too high and loud; the goblin voices), saved ones
      wait for their feature (throwing dagger, dragon, storms, caves, falling
      trees, crows at arrival and after battle, other monsters). Edits: the
      Shield Wall is Knox's "Shield wall!" (cut at 1.49 s) with shields
      locking; the warlord's war cry stops before "KRAGH! KRAGH!" (cut at
      5.1 s); troll steps from troll_stomp_01 pitched down 3–5 st, low-passed
      at 800 Hz, +8 dB at 70 Hz; the troll's death vocal at 0.8× speed and
      pitch; soldiers' treads from boot_step_grass_04. New: orcs' attack
      grunt (`swing_orc_*`), a camp murmur bed; the camp's three forest beds
      are one bed picked per visit; day battles lost their random crows.
      build_bank.py: `af` filters per take or layer, `slice` layers, finds a
      moved library, drops the files of removed groups. 215 files.
      Quick suite: 390 passed, 1 failed: test_a_marching_squad_is_one_tread
      on a logged shader error from the new unit outline
      (`scenes/battle/battle_sorted.gdshader:34` passes TEXTURE to a
      function; not audio, owner notified); its own assertions pass.
- [x] Voices, round 2 (24 Oct): `tools/audio/hfvoice.py` + `voices.json`
      made 53 Higgsfield takes (14.06 credits): Knox (the voice the owner
      liked) giving every stance, charge, aim, select, move, attack, retreat
      and victory call, five men cheering "Hurrah! Amberfeld!", and goblins
      made three new ways (a described voice and a voice from the goblin
      picture in Seed Audio, ElevenLabs Sterling pitched up with a smaller
      throat). In the library under `voices/higgsfield/round2/`, each take in
      `candidates.json`; nothing of round 2 reviewed by ear yet. In the game,
      without new hooks: Spearwall, Square, Defend (`stance_footman`) and
      Overwatch (a cocking crossbow under the call) are Knox's calls with
      their gear; the player's rout is "Fall back!"/"Run!" with men running;
      `victory` is Knox's "Amberfeld!" answered by five men's "Hurrah!
      Amberfeld!" (after a won battle and on "Return to Amberfeld"). The
      hound's stance and rout are aliases of its roar and death. 235 files.
      `make_audition.py` and its template moved into `tools/audio/`: voices
      grouped per round and per purpose, what was reviewed on 24 Oct hidden.
      build_bank.py reads Suno music (`suno/<track>/<file>.wav`, a loop cut
      to whole bars from a bpm, or a one-shot); none downloaded yet. Tests
      (deliberate): the new voice events come from the bank on the Voice
      bus. Quick suite: 394 passed, 1 failed (the same shader error). Seen
      once: `test_last_stand_with_waves_and_relief_plays_to_the_end` failed
      on a null texture in `assets.gd` hover picking and passed alone; and
      `test_mute` / `test_ambience_crossfades_between_scenes` fail with
      "Parse JSON failed" while other Godot sessions write the same
      `user://prefs.json` (not a regression; tests share the user's prefs).
      Vorbis loops change checksum on every build (random stream serial).
- [x] The squads answer orders (24 Oct; hooks in `battle_view.gd` with the
      owner's go-ahead, sound calls only): `_say` where the order is given,
      once per order (a move-then-attack click says only the attack):
      `order_select` ("Orders?", "Ready.") when the player picks a squad that
      can act in the player's turn, `order_move`, `order_attack` with
      `order_<ability>` first (`order_shield_charge`, `order_aimed_shot`:
      only the "Loose!" of "Steady... loose!", so it comes with the bolt).
      Flat on the Voice bus at -14 dB (the owner found -8 too loud), one
      at a time (none while the last still speaks); quiet when the
      selection moves on by itself
      (`select(uid, false)` from the idle poll; `select_next(say)`); the
      hounds (`QUIET_TYPES`) obey without a word. 253 files. New test
      `test_audio::test_the_squads_answer_orders`. Quick suite: 395 passed,
      1 failed (the same shader error); test_audio, test_battle_view,
      test_battle_hud and test_sfx after the last change: 51 passed, the
      same 1 failed.
- [x] The owner's second listen (24 Oct; `docs/audio-picks.md`, *Night and
      the UI*): the night owl is `owl_tawny_02`'s four calls cut apart
      (high-passed at 300 Hz against the clip's rumble), every 10–45 s;
      page turns `ui_page_turn_01`, `_02` and, now and then, `_10`; clicks,
      select and build lose the rejected takes; gold (`coin`) is four new
      takes of coins clinking (`Ting Coins` from Sonniss GDC 2026, added to
      the library as `ui_coins_s26_01`, and single counted coins of
      `ui_coins_02` layered two or three at a time). New: a take's `weight`
      (`bank.gd` `pick_take`, recipe.json take `weight`), still never the
      take played last. The library's `integrated_in` and `state` follow
      provenance.json again. New test
      `test_audio::test_a_weighted_take_comes_up_now_and_then`. Quick
      suite: 400 passed, 1 failed (the same shader error), 10 skipped.
- [x] Day into night, slowly (24 Oct, the owner's ask): the sounds of the
      last part of the day ebb out while the other's come in. The camp has
      a night preset, `camp_night`: the pine wind made deeper and quieter
      for the night (the owner's word: `camp_night_wind`, the same cut
      pitched down about 3.9 semitones, so its gusts are slower too,
      low-passed at 1.2 kHz, at -15.7 dB: half the day's wind as heard,
      the owner's level after trying -16.5 and 70% at -12.8), the
      night crickets at -8 dB, the tawny owl as in night battles and the
      fire; no songbirds, distant calls or murmur. The camp's Day/Night
      buttons switch it over 6 s (`woodland_camp.gd` `set_night`, a
      sound call only; the light still turns in 2.4 s). `ambience.gd` now
      also crossfades the one-shots: the leaving preset's calls go on,
      ever quieter, until the fade ends, the new ones rise from silence,
      and a shared loop burns on instead of restarting; a bed still
      fading out when its preset comes back turns and fades back in from
      where it was (`loop_deck.gd` `revive`). The battle's dawn
      (night into day, 6 s) gets the same. New tests
      `test_audio::test_ambience_calls_ebb_away_as_the_next_scene_comes_in`
      and `test_the_camp_hands_day_and_night_over_slowly`; `camp_night`
      joins `test_ambience_plays_the_files_it_has`. Quick suite, with
      the night wind at 50%: 403 passed, 0 failed, 10 skipped (the
      shader error went with another session's discarded outline draft).
- [x] The voices stay local (25 Oct, the owner's word): `build_bank.py` no
      longer counts Higgsfield output as free, so the 45 voice files (Knox's
      orders, stances, rout and victory, the warlord's war cry) render into
      the gitignored `assets/audio/bank/local/sfx/voices/`: the same files,
      only their paths changed in bank.json and provenance.json. 91 files
      are in Git, 155 local. A clone without the library plays the synth
      stance, rout, war cry and victory, and the squads obey without a word.
      Tests (deliberate): `test_shipped_bank_routes_the_original_names`
      lets a voice's local takes be missing and checks that nothing outside
      `local/` has a Sonniss or Higgsfield source.
- [ ] By ear: the owner's remaining picks and round 2's voices, then levels
      (the order answers: whether -14 dB is right and whether every
      select should answer; the day battle's wind and the camp's wind,
      lowered to -10.5 dB, 30% of their level, on the owner's word),
      ducking thresholds (tuned for the
      synth) and jitter;
      campaign-map ambience; music (Suno, waiting for the owner's
      downloads); a war wagon's rumble. Thin in the library: ballista,
      catapult, wolf paws, cuckoo calls (skipped: nothing to slice).

## Interface art pass — 23 October 2026

- Warm vellum, blue header bands, dark iron and brass fittings now unify camp
  panels, menus, portraits, buttons and the campaign/battle HUD. The reusable
  `forged_style.gd` draws fixed-pixel corners and rims; small controls use less
  ornament. Existing gameplay and status meanings are retained.
- The title uses original generated forest-sunrise artwork, revised from a dusk
  study at the user's request. No full-screen dimming and no new heraldic symbol.
- Fixed custom padding being lost when decorating an unattached UI panel;
  `test_unparented_panel_preserves_explicit_padding` covers the case.
- `tools/review_ui.sh` rebuilds both themes, captures 31 desktop scenarios and
  runs the input playthrough. The capture pass logged zero rendering/runtime
  errors. The final playthrough passed 184 checks with zero failures, errors or
  warnings, including a complete battle, report, minimap and return to title.
- Final `tools/test.sh --quick`: 364 passed, 0 failed, 10 skipped (201.6 s),
  after the concurrent terrain and campaign-test changes settled.
- The playthrough now tracks physical window enter/exit separately from its
  synthetic pointer and reasserts hover before checking a target. This keeps
  physical pointer movement from invalidating scripted button checks while
  preserving normal GUI hit-testing. A diagnostic indentation error introduced
  during simultaneous terrain/test edits was also corrected.
- Artwork, source map, screenshots and verification:
  [interface art direction](../../docs/interface-art-direction.md) and
  `workspace/2026-10-20_meridius/interface.html` from the repository root.
  Report images/downloads checked at 1440 and 1024 px in light and dark themes.
  No Windows export or commit was performed for this pass.

## Painted panels, banners and borders — 23 October 2026

- Three original RGBA masters in `art/ui/epic/`, with byte-identical runtime
  copies in `assets/ui/epic/`: council frame, blue company banner and dark command
  panel. ImageGen created these from the supplied Meridius material references;
  the Higgsfield gallery was consulted visually. No heraldic symbols were added.
- `painted_frames.gd` draws fixed corner slices through `forged_style.gd`.
  Large panels, title borders, banners and major actions share the painted
  materials; compact controls retain simple rims. Banner and preparation padding
  reserve space for ornament. Both saved themes were rebuilt.
- `tools/review_ui.sh`: 31 captures, zero rendering/runtime errors; 235 input
  checks passed, zero failures/errors/warnings, including one complete battle.
- `tools/test.sh --quick`: 363 passed, 1 failed, 10 skipped. All UI tests passed.
  The audio test that loads a battlefield hits a shader-compiler custom-sampler
  error in separately modified outline work. Focused audio rerun: 17/1.
  That shader was left intact; this pass does not claim a green full quick suite.
- The current review is `workspace/2026-10-20_meridius/interface.html` from
  the repository root; masters, native captures and source checksums are under
  `interface/epic/`. The earlier report remains `interface-first-pass.html`.
  Report layouts checked at 1440/1024 in light/dark, plus preview/zoom/close.
  Download click was attempted but its browser receipt could not be confirmed.
  No application restart, Windows export or commit was performed.

## Resume here

23 October visual update: removed the decorative battlefield host, distant
smoke, waiting reserve figures and campaign horde/fire/scorched overlays.
`battle_surroundings.gd` continues grass through clear entry approaches with
worn tracks. The campaign starts on the company. Wave rules, map generation
and parity fixtures are unchanged; obsolete horde-render expectations were
retired. Native `capture_edges.gd -- edges` plus day/night captures: zero
render/runtime errors. Final `tools/test.sh --quick`: 364 passed, 0 failed,
10 slow tests skipped. Evidence: `workspace/2026-10-20_meridius/terrain/`
`map-edge-review.md` (repository root). No active application was restarted.

1. `tools/test.sh` (full) — green with magic, war machines and the
   shared-tile fix (340/0), not yet committed.
2. `tools/export.sh && build/windows/Meridius.console.exe -- --smoke`.
3. Commit on branch `godot-migration`.

## 2026-10-23 — Unit playground

Added a title-menu inspection field and `--playground` launch argument. The
screen hosts a separate BattleView subclass with a flat grass map, every current
unit type, appearance variants, single/squad views, a comparison unit, all four
facings, pause/frame step, 0.25–2× playback, extended camera zoom, grid and night.
Movement, turning, attacks and falls use the production presentation scheduler.

The invulnerable straw dummy is an editable SVG drawn in the same sorted pass
as the units. Clicking it or Attack dummy routes the subject around occupied
tiles into melee or firing range, then repeats its ordinary attack. No campaign
rules, save files or battle-speed preferences are changed by practice.

Validation: the four new regression cases cover all 20 types and five clips,
repeated attacks from four facings, pause/step/speed, interruption, path occupancy,
comparison and retained engine crews. Native input review checks title entry,
field/dummy clicks, UI exclusion, facings, transport, lighting, exit/reentry and
unchanged save bytes. Captures at 1920×1080 and 1280×720 and a fixed 30 fps clip
are linked from the Meridius Workspace Unit playground tab.

`tools/test.sh --quick`: 372 passed, 1 failed, 10 skipped. All playground tests
pass; the failure is the shared renderer's headless shader compile error
(`custom_samplers`, reported by `test_audio::test_a_marching_squad_is_one_tread`).
The native GL review runs the same playground cases without that compiler error.
No golden traces were changed. The full slow suite and Windows export were not run.


### 2026-10-23 - Fog of war and traversable woodland

Requested battlefield fog now shares faction sight, retains explored ground,
conceals distant woodland occupants and filters hidden enemies from targeting
and AI planning. Fighting reveals participants until their next turn. Scouting
prevents information-gaining move undo. The new Woodland scouting test field
uses the production renderer and the supplied black/blue fog grain.

Trees/bushes no longer block movement at squad scale. Forest move cost remains
2, and rocks/walls remain solid. Map generation and deployment use clear-ground
placement separately, preserving the existing layouts and setup positions.
Map golden comparisons remain intact. Setup parity explicitly verifies the new
fogOfWar flag and compares the remaining original setup fields unchanged.

Re-recorded battle traces only with MERIDIUS_RECORD=1 tools/test.sh
test_battle_parity: 77 traces across 16 passing groups. Reviewed changes are
woodland routes, resulting combat sequences and reach-query sets; fixture
setups and input commands remain unchanged. Campaign baseline recording and
playthrough testing were deferred at the user's request to focus on the tester
and sandbox. Native fog: 17 checks passed; focused headless: 29 passed, existing
unit-outline shader compiler failure in the first HUD test. Native exit reports
resource cleanup warnings (8 objects / 2 resources), separate from scene checks.

Committed on 25 Oct 2026 in two parts: first the rules (`visibility.gd`,
battle, AI, grid, mapgen and setup) with both baselines, then the fog renderer,
the HUD filtering and the Woodland scouting field with the rest of the view
work. The campaign baseline was re-recorded then, with `MERIDIUS_RECORD=1
tools/test.sh test_campaign_parity`: traversable woodland changes the routes of
auto-resolved battles. Inputs, generated expeditions, the V8 sort order and the
save fixtures are unchanged. Two of the seven driven runs differ (run 3, step 3:
loot silver 63 → 53; run 4, step 38: 45 → 53), and so do all five autoplay
campaigns (first differences, all in cycle 0: retreat → success twice, success
→ retreat once, silver 170 → 169, deaths 1 → 2).

### 2026-10-23 - Small woodland camp remodel

The production base scene now uses the selected `camp_small_woodland` day take02
and matching night take01 as an interactive painted isometric stage. All six
existing building services map to authored image-space polygons and numbered
HUD actions. The camera is bounded to the source image; lighting preview, forest
mist and roster figures on open-ground paths are presentation only. Building
upgrade names/effects remain live, while the first-pass architecture stays painted.
The old renderer and its original geometry fixture checks remain explicitly
available; eight new tests cover the production scene. Rules and golden traces
were not changed for this task.

Native camp review:78 checks, zero failures/runtime errors, clean shutdown,
unchanged player save and restored preferences. Focused tests:34 passed. Final
quick suite:387 passed,1 failed,10 skipped; the remaining marching-audio case
reports the previously documented headless battlefield `custom_samplers` error.
The Workspace camp report includes native stills, a five-second motion study,
source hashes and checked previews/downloads at1440/1000px in both themes.
No full slow-suite run, export or commit was made.

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

### 2026-10-25 - Forest edge in front of the field, copper beech, ground seasons

- Battle: the near side of the forest ring is sorted with the field (it stands
  in front of the edge rows) and fades over squads, the move ghost and the
  hovered tile behind it. `battle_draw.gd` `draw_outer` now bakes only the far
  side and the ring's cast shadows; `_ring_fades` gives all the trees over one
  squad together the veil of one field prop (0.28). The terrain lab draws its
  own ring and is unchanged. `test_battle_forest_edge` checks the split and the
  fades; `tests/visual/capture_forest_edge.gd` captures four battles with the
  fades settled.
- `tree_oak` has 17 variants: the eight of kit 2 again at slightly different
  sizes, and one copper beech, a rare dark red accent in summer (it stays in
  `tree_oak_autumn` too). `test_assets` pins the count.
- `terrain_relief.gdshader` has a `season` uniform (0 summer, 1 autumn, 2
  winter, 3 spring) and `frozen` for ice, for a 3D battlefield prototype that
  is still local. Season 0 is the battle's ground as before.
- `tools/props/iso_check.py` draws the 2:1 camera guides over a painting for
  the isometric art check (`processes/isometric-art-check.md`).

### 2026-10-25 - No weeping willow in the woods

- The weeping willow of terrain kit 2 is left out everywhere (the owner's
  call). In `tree_oak` its two variants became an oak (0.9) and a beech (1.1),
  so the key keeps 17 variants and every tile that drew another tree by
  `v % n` keeps it, in battles, on the campaign map and in the garrison.
  `tools/props/woodland_cutout.py` no longer cuts it; `woodland_willow.webp`
  and its entry in `woodland_sources.json` are removed.

### 2026-10-25 - 3D battlefields prototype

- `prototypes/battlefields3d/` (see its README) is the 3D battlefield the
  relief shader's `season` and `frozen` were made for: Millford (summer
  town), Ashby farm (autumn), Frosthollow (winter, frozen) and Willowford
  (spring) under the game's camera, with no units. Its fields are maps in
  the rules' format, so the fog of war over them is `visibility.gd`'s.
  Presentation only: battles, rules and saves are unchanged.
- Its paintings are in `art/`; their originals stay local and
  `tools/cut_art.py` cuts them again. `test_battlefields3d` checks the
  fields, the fog, that every painting loads, and that each field draws its
  pieces and decor without the weeping willow.
