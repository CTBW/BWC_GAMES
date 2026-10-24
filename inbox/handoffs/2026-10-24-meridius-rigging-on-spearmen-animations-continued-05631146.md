# Handoff: Meridius spearman 3D rig

## Result
The spearman 3D rig is complete, committed and pushed. All three requests from 2026-10-23 are built:
- turn 90° with both hands on the shaft;
- step into lane with the head facing forward and the spear on the right shoulder;
- a cloth cape that falls over the back.

The cape is baked for all ten clips, rendered and shown in the workspace tab. **The user hasn't judged the refreshed tab yet.** The open points are under "To judge".

- Commits on `godot-migration`, pushed to `origin/godot-migration` (public repo `CTBW/BWC_GAMES`):
  - `f6c6e32` Meridius: spearman 3D rig with cloth cape, clips and report (94 files)
  - `1f5be46` Knowledge: Tripo Studio notes for the Meridius units
  - `aa697b4` Meridius: spearman helper scripts for baking, renders and report figures (14 files in `art/spearman_3d/tools/`)
  - At the time of writing, `aa697b4` is the head of both the local and the remote branch. Other sessions commit and push to this branch too.
- Report: `workspace/2026-10-20_meridius/spearman-3d.html`, card "Spearman 3D rig" (group Character rigs, subgroup Spearman) in `workspace/workspace.json`.
- **Not in the game.** The Godot game still draws the spearman from 2D sprites (`art/squads/spearman`, `assets/sprites/anim/spearman.*`), which another session made. No game code was changed for this work. Two earlier items were answered but not built:
  - per-figure death variant via `Rng.hash2` in `squad_view.gd` and `battle_view.gd:_drop_victim`;
  - troll overkill ragdoll.

## Files (committed in `f6c6e32`; helper scripts in `aa697b4`)
All paths are under `projects/meridius/source/godot/art/spearman_3d/` unless noted.

| File | sha256 (first 12) |
|---|---|
| `spearman_rig.blend` | `a5613942478b` |
| `spearman_base.blend` | `358886dd37fd` |
| `spear.blend` | `88330b84d248` |

- `tools/`:
  - `build_spearman.py`, `build_spear.py`, `cut_spear.py`
  - `rig_spearman.py`, `retarget_clips.py`, `spear_motion.py`
  - `cape_cloth.py` (`setup` / `sim <cache dir> [clip]`)
  - `render_preview.py`, `spear_clearance.py`, `inspect_mesh.py`, `inspect_prop.py`
  - Helpers added in `aa697b4` (listed under "Rebuilding after a change"):
    - `blender_env.sh`, `bake_cape.sh`, `render_clips.sh`, `poke_cape.sh`
    - `cape_poke.py`, `cape_inspect.py`, `cape_peek.py`, `lineup.py`, `pc2_check.py`
    - `pack_sheets.py`, `deaths_figure.py`, `cape_figure.py`, `lineup_compose.py`, `contact_strip.py`
- `cape_cache/*.pc2`, baked 2026-10-24 11:40 from the fixed setup:

  | Clip | sha256 (first 12) |
  |---|---|
  | attack | `7255ab8631e3` |
  | death | `bcf718cd0216` |
  | death_2 | `48ae010cc94a` |
  | death_3 | `f27607cca0b1` |
  | hit | `9eb388bd0e49` |
  | idle | `9df3000cdbf5` |
  | idle_rest | `8b4fdfd2aa52` |
  | step_lane | `5d628dc3601f` |
  | turn_90 | `26b10c3afd32` |
  | walk | `20e3aa11dd73` |

- Sources: `projects/meridius/references/characters/Spearman TRIPO/` (Tripo FBX files, body v1–v4 and spear v1, plus textured body v4 and spear) and `references/characters/spearman_idle/*.png` (cut sheet figure and Nano Banana T-pose references).
- Report media in `workspace/2026-10-20_meridius/spearman-3d/`:
  - `sheets/*.webp`: 10 clips × 4 facings.
  - `frames.json`: 30 fps, canvas 390×420. Its JSON is also pasted into the tab's `<script id="frames-data">`.
  - `img/`: `deaths`, `cape_cloth` (before/after), `lineup` (re-rendered today), and `cape`, `chain`, `spearhead`, `turnaround` (older, still valid).
- Frames per clip:

  | Clip | Frames |
  |---|---|
  | idle | 43 |
  | idle_rest | 129 (rendered every 2nd of 258) |
  | walk | 42 |
  | attack | 64 |
  | hit | 61 |
  | death | 72 |
  | death_2 | 69 |
  | death_3 | 118 |
  | step_lane | 39 |
  | turn_90 | 29 |

- Left uncommitted on purpose:
  - `references/characters/spearman_idle/jobs.json` is a job receipt; `AGENTS.md` keeps receipts out of Git.
  - `references/characters/tripo/spearman/` holds copies another session collected (see its `recovered-exports.json`).

## Ownership: don't overwrite
- `workspace/2026-10-20_meridius/rig-viewer/` (`viewer.js`, `viewer.css`, `combat.css`, `combat-skills.json`) is shared by the footman, crossbowman, mage, succubus and spearman tabs. The "Add combat skills" session made it; it went into `f6c6e32` only because the tab needs it.
- The `rig-combat:start` / `rig-combat:end` section of `spearman-3d.html` also belongs to that session. Keep it intact when editing the tab.
- `workspace/workspace.json` has uncommitted cards from other sessions. Stage only your own lines.
- Other sessions own `art/footman_3d`, `art/crossbowman_3d`, `art/succubus_3d` and wolf_scout; only read or copy their files. `succubus_3d/tools/rig_succubus.py` and `retarget_clips.py` are adapted copies of the spearman scripts, so changing the spearman scripts doesn't affect them.
- Before applying anything, re-read the tab and `git log origin/godot-migration`; other sessions commit and push to this branch.

## Verification (agent, 2026-10-24)
- **Bake.** One background Blender per clip, peak 300–370 MB each. The new idle bake is bit-identical to the 2026-10-23 idle (the sim is deterministic). Lowest cape point per clip:

  | Clip | Lowest point |
  |---|---|
  | idle | 0.70 m |
  | walk | 0.72 m |
  | step_lane | 0.72 m |
  | attack | 0.66 m |
  | hit | 0.56 m |
  | death | 0.11 m |
  | death_2 | 0.01 m (on the 1 cm ground clamp from f35, lying flat) |
  | death_3 | 0.25 m |
  | turn_90 | 0.70 m |
  | idle_rest | 0.76 m |

- **Deaths** (chest normal through `mixamorig:Spine2`):
  - Death 1 and Death 3 end face down with the cape on the back (0% in front).
  - Death 2 ends on his back with the cape under him.
  - Death 1 is relabelled "thrown back, lands face down".
  - The cape still moves up to 0.2–0.5 m/s in the last 10 frames (the game holds the last frame).
  - The hem jumps 28 cm in one frame at death f50 and 24 cm at death_2 f33, during the fall.
- **Body through the cape** (counted with the scratch `poke_all.py`, now `tools/cape_poke.py` / `poke_cape.sh`; step 4, all four facings): sampled body points showing through the cape.

  | Clip | Total | Worst view |
  |---|---|---|
  | hit | 49 | 3 |
  | idle_rest | 144 (over 260 views) | 2 |
  | step_lane | 42 | 3 (was 27 before the collision group fix) |
  | walk | 43 | 9 at f5 SW, his left forearm passing the cape edge |
  | attack | 30 | 2 |

- **Spear clearance** (frames where the spear crosses the body), unchanged by the cape bake:

  | Clips | Frames |
  |---|---|
  | idle, idle_rest, walk, step_lane, turn_90 | 0 |
  | attack | 1 of 64 |
  | death | 1 of 72 |
  | death_2 | 1 of 69 |
  | death_3 | 2 of 118 |
  | hit | 10 of 61 |

- **Tab in Chrome** (`python -m http.server 8765 --bind 127.0.0.1` from `workspace/`):
  - All 40 sheets and 7 figures load at their declared sizes, and the image preview offers download and close.
  - The viewer plays March in all facings and shows Death 2's last frame.
  - Narrow widths were checked in iframes only. The workspace rule is now desktop only (`processes/workspace-authoring.md` step 7), so phone checks aren't needed.

## To judge (owner acceptance pending)
1. **Step into lane:** the neck turns about 70° between the turned chest (the source clip "Standing Walk Right") and the forward head (`head_forward()`: Neck 50%, Head 100%).
2. **Hit:** the left forearm sweeps across the shaft in 10 of 61 frames.
3. **Death 1:** from above, the cape ends bunched on the upper back and shoulders, because it is flung up as he pitches forward. From the battle camera it reads as lying on his back.
4. The death caches are still settling slightly in their last frames.

None of these has a decided fix. Wait for the user's verdict before changing anything.

## Accepted decisions (keep)
- **Shoulder carry:** the lean is measured from the chest (Spine2), not the unit's facing. `SHOULDER_CFG = contact [-0.20,-0.11,1.55], len 0.16, fwd -22, out 3, butt_z 0.85, pole [-0.3,0.6,-1.0]`. The wrist bends 11–15° and the palm faces the chest.
- **Turn:** `turn_two_handed` dips the spear 16°, eased over 6 frames.
- **Chain order:** `rig_spearman` → `cape_cloth setup` → `retarget_clips` → `spear_motion` → `cape_cloth sim`.
  - `ground_lift` (deaths) needs the cape off the body, and it asserts that `Cape` exists.
  - The Cloth modifier is kept `show_viewport=False` outside `sim`.
- **Cape collisions:** `cs.vertex_group_object_collisions` names faces **excluded** from collisions, so it is the `"pinned"` group (pin weight ≥ 0.3). This bug was the root cause of the earlier poke-through.
- **Cape colliders:** ellipsoids in the torso, pelvis, thighs and shins, plus `skirt` (upright, parented to Hips, `SKIRT_Z = (0.78, 1.12)` + 2 cm).
  - `flatten_back()` runs first; it presses `BACK_BOX x ±0.30, z 0.90–1.30` flat behind `y = 0.10`.
  - The ground is a single-sided collider plus a `GROUND_CLEAR = 0.01` clamp.
- **Rejected; don't retry:**
  - arm colliders;
  - a skinned copy of the back as a collider;
  - BVH push-out;
  - longer pre-roll or higher collision quality as a fix;
  - moving the elbow pole for the poke.

## Rebuilding after a change
Blender: `"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"`.

- **Always** set `BLENDER_USER_RESOURCES` to an empty scratch folder. `-b --factory-startup` against the user profile deleted the extension wheels once. The runners below do this for you.
- Run at most 2 Blender instances; other sessions also run Blender. Their wolf scout GUIs are not yours.
- Memory was the blocker on 2026-10-23. Run one clip per process and watch commit free; the runners stop Blender below 1.2 GB (`MIN_COMMIT_MB`).

The helper scripts are in the repo, in `art/spearman_3d/tools/` (commit `aa697b4`). Each file's docstring gives its usage.

| Script | Kind | What it does |
|---|---|---|
| `blender_env.sh` | sourced by the three runners | Work dir, Blender path (`BLENDER` overrides), scratch profile, memory watchdog |
| `bake_cape.sh <work> <clip>...` | runner | Bakes on a fresh copy of the rig into `<work>/cape_cache` and prints `CAPE_SIM ... lowest` |
| `render_clips.sh <work> <clip>...` | runner | Four facings into `<work>/renders`; `CAPE_CACHE` defaults to `art/spearman_3d/cape_cache`; step 2 for `idle_rest` |
| `poke_cape.sh <work> <clip>...` | runner | Runs `cape_poke.py` and prints `POKEALL` (`STEP`, default 4) |
| `cape_poke.py`, `cape_inspect.py`, `cape_peek.py` | Blender | Poke-through count; where the cape lies relative to the chest (deaths); with/without-cape close-up (`ORTHO` sets the zoom) |
| `lineup.py` | Blender | Footman, crossbowman and spearman lineup; pass copies of the other rigs |
| `pc2_check.py low` / `diff` | numpy | Lowest point, ground clamp and pops; difference between two bakes |
| `pack_sheets.py`, `deaths_figure.py`, `cape_figure.py`, `lineup_compose.py`, `contact_strip.py` | Pillow | Report sheets plus `frames.json`, and the report figures |

```bash
T=projects/meridius/source/godot/art/spearman_3d/tools
bash $T/bake_cape.sh <work> walk                 # then: python $T/pc2_check.py low <work>/cape_cache walk
CAPE_CACHE=<work>/cape_cache bash $T/render_clips.sh <work> walk
python $T/pack_sheets.py <work>/renders workspace/2026-10-20_meridius/spearman-3d
```

Notes:
- `render_preview.py` reads `CLIP_SCALE` / `CLIP_Z` for close-ups (default 3.7 / 1.25; the cape figure used 2.6 / 1.0).
- Call Blender with absolute paths. Relative ones resolved to `C:\` in a test.
- Python with Pillow and numpy: `C:\Users\calle\AppData\Local\Temp\claude\E--ProjektM-BWC-GAMES-godot\d8823a10-5e83-448e-b4e6-5c6ea96da2ae\scratchpad\venv-art\Scripts\python.exe` (run it with `-I`). It is a temp folder, so any Python with Pillow and numpy will do.
- The old skinned-cape rig (`rig_tw.blend`, used for the figure's "before" frames) stays only in that scratchpad.

**Checked 2026-10-24 against the committed results** (see `cape_poke.py` for why the cape read is now unconditional):
- `pack_sheets.py` reproduced all 40 sheets and `frames.json` byte for byte.
- The three figure scripts reproduced the deaths, cape and lineup images byte for byte.
- A re-bake of turn_90 matched the installed cache exactly.
- turn_90 renders matched pixel for pixel.
- `poke_cape.sh` gave attack 30 / worst 2 without `DBG`.
- `cape_inspect.py` gave Death 1 at f72 with the cape on his back.
- The lineup renders matched pixel for pixel.

**Godot tests at `aa697b4`.** `tools/test.sh --quick` gave 398 passed and 1 failed: `test_audio::test_a_marching_squad_is_one_tread` (6 footmen marching 2 s, 10 treads heard). That test file, `tests/unit/test_audio.gd`, is untracked. It belongs to another session's uncommitted audio work (`scripts/audio/sfx.gd`, `battle_view.gd`, `battle_draw.gd`). It isn't part of the spearman commits; leave it to that session.

**Acceptance for any change:**
- The cape's lowest point is ≥ 0.01 m in every clip.
- Poke-through and spear clearance are no worse than the tables above.
- The deaths end with the cape on the back (Death 1 and 3) or under him (Death 2).
- Re-render the clips, pack the sheets, and paste `frames.json` into the tab.
- Check the tab in Chrome at desktop width.
- Ask before committing.

## Accounts and rules
- **Tripo:** character task `061d5fe7-00b3-4235-a4e4-01356695cd72`, spear task `3d0a31ed-85f8-4bfd-9767-79788912872b`. 240 credits were spent (disclosed). Ask before each paid Tripo action and state its cost.
- **Higgsfield:** 12 credits were spent.
- Never sign in on sites for the user.
- No app or session restarts without permission.
- Commit only when asked. Commits use `-c user.name=CTBW -c user.email=135850159+CTBW@users.noreply.github.com` (no Git identity is configured).

---
From the Claude Code chat continuing "Meridius - Rigging on Spearmen animations" in E:\ProjektM\BWC_GAMES-godot, 2026-10-24.
