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
- [ ] Fonts, icons, theme (UI agent)

## Presentation
- [ ] Terrain painter, atmosphere, FX, camera
- [ ] Battle view: units, formations, playback, overlays, minimap, relief
- [ ] Base view, campaign view
- [ ] UI: theme, title, top bar, base panels, roster, prep, campaign HUD,
      battle HUD, report, manual, pause/menu

## Verification
- [ ] Automated suite (20 areas in the brief) green
- [ ] Graphical play-through: new game → expedition → battles → report
- [ ] Performance at 1920×1080
- [ ] Windows export builds, launches, plays
