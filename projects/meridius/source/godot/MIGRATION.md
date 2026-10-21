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
- [~] Automated suite: 289 passed / 0 failed in the last full run reported by
      the battle-view agent; lead's own final full run was started but its
      result was not collected (rerun `tools/test.sh`).
- [x] Windows export builds (168 MB, `tools/export.sh`); the exported exe ran
      the smoke self-test: data, 1210 sprites, 31 sounds, AI expedition, all 11
      encounters, garrison/campaign/battle screens. Rerun after the smoke fix:
      passed in the editor build (13/13); re-export + rerun outstanding.
- [ ] Input-driven graphical play-through (real clicks through the UI, full
      battle to victory/defeat, restart, second expedition) with captures
- [ ] Memory/leak check over several battles; ObjectDB leak warnings at exit
- [ ] Polish requests: preload battle_view.tscn during boot (~280 ms first
      compile); HUD mouse_filter over the minimap; button letter-spacing
      (0.03em) and line-height calibration in the theme

## Resume here
1. `tools/test.sh` (full) — fix anything red.
2. `tools/export.sh && build/windows/Meridius.console.exe -- --smoke`.
3. Play-through QA (open items above), then fix and commit on branch
   `godot-migration`.
