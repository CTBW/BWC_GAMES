# Handoff: Meridius spearman 3D rig

## Result
The spearman 3D rig is complete, committed and pushed. All three requests from 2026-10-23 are built:
- turn 90° with both hands on the shaft;
- step into lane with the head facing forward and the spear on the right shoulder;
- a cloth cape that falls over the back.

The cape is baked for all ten clips, rendered and shown in the workspace tab. **The user hasn't judged the refreshed tab yet.** The open points are under "To judge".

**Step-into-lane neck twist fixed in `e40ed6a` (2026-10-24, pushed).** The user asked to "fix the step lane neck twist". With the head held forward and the spine left as the source clip had it, the neck took the whole 64–79° turn between his chest and his head. Now:
- the spine turns the chest halfway back (`SPINE_UNTWIST` 0.5 over Spine/Spine1/Spine2, 30/35/35%);
- the neck base and the head's joint take 16–20° each.

The spear's lean is now measured 75% from his hips and 25% from his chest (`SHOULDER_CFG["travel"] = 0.75`). Measured from the chest alone, the shaft stood upright from the SE, against the user's arrows (tip to the right). At 1.0 the tip leaned right as before, but the shaft ran over his face.

Changed in `e40ed6a`:
- `tools/spear_motion.py`
- `spearman_rig.blend` (step_lane keys only)
- `cape_cache/step_lane.pc2`
- `workspace/2026-10-20_meridius/spearman-3d/sheets/step_lane_*.webp` and `frames.json`
- the tab's frames data plus its step-into-lane and "to judge" notes.

**Hit spear clearance fixed in `906687a` (2026-10-24, pushed).** The user asked to "fix the hit spear clearance". The spear stays rigid in the right fist. `wrist_clear()` in `spear_motion.py` now bends the right wrist where the flinch would swing the shaft through him:
- **The test:** the shaft's axis, plus four lines `CLEAR_R` = 2.5 cm off it, must not cross the body more than 10 cm from either fist.
- **The search:** a cheapest-path search over 2D wrist bends in the hand's X–Z plane (12 directions, 2° steps, up to `CLEAR_MAX` 30°, at most `CLEAR_STEP` 6° change per frame). It runs from a straight wrist `CLEAR_PAD` 8 frames before the crossing frames to a straight wrist 8 frames after them.
- **Result:** bends in frames 6–23 and 34–43, at most 10°. Clearance is 0 of 61 frames, down from 10. The left forearm (8, 38–41) and the belly (16–20) are clear.
- **Rejected:** one fixed bend direction for the whole stretch. It pushed the shaft into his left arm in frames 9 and 34–36, which were clear before. No single direction worked across frames 0–49.
- **Re-runs:** `wrist_clear` edits the hit's `RightHand` keys in place. It marks the action (`act["wrist_clear"]`) and asserts on a second run, so run `retarget_clips.py -- 'E:/ProjektM/BWC_GAMES-godot/projects/meridius/Animations' hit` before re-running `spear_motion.py -- hit`.

Changed in `906687a`:
- `tools/spear_motion.py`
- `spearman_rig.blend` (hit `RightHand` keys only; sha `94d4d4c23257`)
- `workspace/2026-10-20_meridius/spearman-3d/sheets/hit_*.webp` and `frames.json`
- the tab's frames data, its "Holding the spear" sentence on the hit, and the clearance line

**`906687a` kept `cape_cache/hit.pc2` on purpose.** The wrist isn't a cloth collider: bakes from the rig before and after the wrist fix are identical. Cape poke-through for hit is unchanged at 49 total, worst 3. All caches were re-baked later for the leftover-scale fix below.

**Leftover pose scale fixed in `627c2c1` (2026-10-24, pushed).** The user asked to "fix the leftover pose scales in the cape bakes". The same clip used to bake different cloth depending on the file: a re-bake of hit from the `906687a` rig differed from the committed `hit.pc2` by up to 0.33 m.
- **Cause:** the IK steps in `spear_motion.py` set `pb.matrix` directly. That left unkeyed float noise in pose scale (up to 1.4e-4 on the right forearm and hand) and location (~1e-7) on the arm, neck and head bones. It was saved in the file, depended on which clips ran last, and moved bones by at most 0.05 mm. The chaotic cloth sim turned that into a different cape.
- **Fix in `tools/spear_motion.py`:** every pose-matrix assignment goes through `set_matrix()`, which calls `clear_unkeyed()` (scale 1, and location 0 on every bone except the hips, which is the only keyed location). The script also clears all bones at the start, which cleans files saved before the fix, and asserts a clean pose before saving. `set_bone_dir` uses the column-normalised matrix, so scale can't compound.
- **Fix in `tools/cape_cloth.py sim`:** it clears the same channels before reading the poses, so even a rig with leftovers bakes the same cloth.
- **Rig rebuilt from the sources:** `retarget_clips.py` (all ten clips) and then `spear_motion.py` (all), about 30 s in total. It prints the same results as before: step_lane wrist bend 11° and chest −40…−32°; hit wrist bend frames 8–41, up to 10°. Every clip matches the old keys within 0.39 mm (the largest is at the spear tip). No leftover scale or location remains. Objects, modifiers, cloth settings and the cape mesh are unchanged (file fingerprint).
- **Proof:** hit baked from the old `906687a` rig (leftovers still saved in it) with the fixed sim is byte-identical to the clean bake. The hit keys are identical in both rigs.
- **Re-baked and re-rendered:** all ten caches, all 40 sheets and `frames.json` (the tab's frames data is updated). Also the three figures that show the cape: `img/deaths.webp`, `img/cape_cloth.webp` (before frames from the d8823a10 scratchpad's `capeba_old`) and `img/lineup.webp`. The lineup used the 11:30 copies of the footman and crossbowman rigs (this session's scratchpad `lineup/`), because their live files changed at 17:49–17:51, so only the spearman's cape changed. The lineup is now 2526 px wide, and the tab's `width` attribute is updated.
- **The new cloth** differs from the old bakes by a mean of 1–4 cm per clip (chaotic). The largest visible change is the march from the NE, where the cape now hangs closer to his back instead of flaring wide. Lowest points and poke-through are in "Verification" below. Spear clearance is unchanged.
- **Tab:** the Cape note now gives the march's worst view as six points (f9 NE, his left hand at the cape's edge) and says why all clips were re-baked.

- Commits on `godot-migration`, pushed to `origin/godot-migration` (public repo `CTBW/BWC_GAMES`):
  - `f6c6e32` Meridius: spearman 3D rig with cloth cape, clips and report (94 files)
  - `1f5be46` Knowledge: Tripo Studio notes for the Meridius units
  - `aa697b4` Meridius: spearman helper scripts for baking, renders and report figures (14 files in `art/spearman_3d/tools/`)
  - `e40ed6a` Meridius: spearman step into lane, neck twist spread over spine, neck and head (9 files)
  - `aa82847` handoff update; `906687a` Meridius: spearman hit, wrist bends the rigid spear clear of his body (8 files), pushed by the coordinating session.
  - `2714427` handoff update and the Animations path in the tab.
  - `627c2c1` Meridius: spearman cape bakes no longer depend on leftover pose scale (59 files: the two scripts, the rebuilt rig, all ten caches, 40 sheets, `frames.json`, three figures, the tab and this handoff).
  - **Pushing:** the coordinating session (`bwc-games-godot-1c`) now pushes and opens PRs for everyone. Commit your own files by explicit path, then send it the hash. The folder and public-Git policy is in the "Where things live" section of `AGENTS.md`.
  - `origin/godot-migration` is at `627c2c1`, with another session's `f4f1110` (painted rocks) under it. The user asked to push `627c2c1` and approved `f4f1110`'s Nano Banana Pro rocks for the public repo, since pushing one publishes the other. The coordinator pushed both at the same moment, so my own push was rejected as a duplicate. Other sessions commit and push to this branch too.
- Report: `workspace/2026-10-20_meridius/spearman-3d.html`, card "Spearman 3D rig" (group Character rigs, subgroup Spearman) in `workspace/workspace.json`.
- **Not in the game.** The Godot game still draws the spearman from 2D sprites (`art/squads/spearman`, `assets/sprites/anim/spearman.*`), which another session made. No game code was changed for this work. Two earlier items were answered but not built:
  - per-figure death variant via `Rng.hash2` in `squad_view.gd` and `battle_view.gd:_drop_victim`;
  - troll overkill ragdoll.

## Files (committed in `f6c6e32`; helper scripts in `aa697b4`; neck fix in `e40ed6a`; hit fix in `906687a`; scale fix in `627c2c1`)
All paths are under `projects/meridius/source/godot/art/spearman_3d/` unless noted.

| File | sha256 (first 12) |
|---|---|
| `spearman_rig.blend` | `c1d4854542e3` (`627c2c1`, rebuilt for the scale fix; `94d4d4c23257` in `906687a`, `d4e3944f50d6` in `e40ed6a`, `a5613942478b` in `f6c6e32`) |
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
- `cape_cache/*.pc2`, re-baked 2026-10-24 ~17:40 for the leftover-scale fix (`627c2c1`):

  | Clip | sha256 (first 12) |
  |---|---|
  | attack | `4fbe212b4b85` |
  | death | `1b2ee405a07c` |
  | death_2 | `922e8d962fcd` |
  | death_3 | `71c8071b4071` |
  | hit | `13413931b2d1` |
  | idle | `4b8a6313ae5e` |
  | idle_rest | `3feaf10d105b` |
  | step_lane | `98c087cfa65b` |
  | turn_90 | `f5c17710837d` |
  | walk | `632dd2c21a78` |

- Sources: `projects/meridius/references/characters/Spearman TRIPO/` (Tripo FBX files, body v1–v4 and spear v1, plus textured body v4 and spear) and `references/characters/spearman_idle/*.png` (cut sheet figure and Nano Banana T-pose references).
- Report media in `workspace/2026-10-20_meridius/spearman-3d/`:
  - `sheets/*.webp`: 10 clips × 4 facings.
  - `frames.json`: 30 fps, canvas 390×420. Its JSON is also pasted into the tab's `<script id="frames-data">`.
  - `img/`: `deaths`, `cape_cloth` (before/after), `lineup` (all three regenerated for the scale fix), and `cape`, `chain`, `spearhead`, `turnaround` (older, still valid).
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
- **Bake.** One background Blender per clip, peak 300–370 MB each. The sim is deterministic, and since the leftover-scale fix it no longer depends on unkeyed values in the file. Lowest cape point per clip (the re-bake for the scale fix; the earlier bake in brackets):

  | Clip | Lowest point |
  |---|---|
  | idle | 0.69 m (0.70) |
  | walk | 0.74 m (0.72) |
  | step_lane | 0.75 m (0.69) |
  | attack | 0.68 m (0.66) |
  | hit | 0.57 m (0.56) |
  | death | 0.11 m |
  | death_2 | 0.01 m (on the 1 cm ground clamp from f35, lying flat) |
  | death_3 | 0.25 m |
  | turn_90 | 0.69 m (0.70) |
  | idle_rest | 0.76 m (0.76) |

- **Deaths** (chest normal through `mixamorig:Spine2`):
  - Death 1 and Death 3 end face down with the cape on the back (0% in front).
  - Death 2 ends on his back with the cape under him.
  - Death 1 is relabelled "thrown back, lands face down".
  - The cape still moves up to 0.2–0.5 m/s in the last 10 frames (the game holds the last frame).
  - The hem jumps 28 cm in one frame at death f50 and 24 cm at death_2 f33, during the fall.
- **Body through the cape** (`poke_cape.sh`, step 4, all four facings): sampled body points showing through the cape, for the re-bake after the scale fix. The earlier caches, counted with the same tool on the rebuilt rig, are in brackets.

  | Clip | Total | Worst view |
  |---|---|---|
  | idle | 5 (5) | 2 at f17 NW (2) |
  | idle_rest | 136 over 260 views (144) | 2 (2) |
  | walk | 43 (43) | 6 at f9 NE, his left hand at the cape's edge (8 at f5 SW) |
  | step_lane | 15 (12) | 2 (2) |
  | attack | 25 (30) | 2 (2) |
  | hit | 49 (49) | 3 (3) |
  | turn_90 | 12 (13) | 2 (2) |
  | death | 97 (82) | 9 at f25 NE (9) |
  | death_2 | 159 (125) | 8 at f49 SW (6) |
  | death_3 | 56 (56) | 2 (2) |

  The deaths and step_lane count more than before. In side-by-side renders the cloth looks alike: Death 2's cape bunches a little more at his right shoulder while he lies on his back. These are fresh samples of a chaotic sim, not a regression in the setup.

- **Spear clearance** (frames where the spear crosses the body), unchanged by the cape bake:

  | Clips | Frames |
  |---|---|
  | idle, idle_rest, walk, step_lane, turn_90, hit (since the wrist fix) | 0 |
  | attack | 1 of 64 |
  | death | 1 of 72 |
  | death_2 | 1 of 69 |
  | death_3 | 2 of 118 |
  | hit before the wrist fix | 10 of 61 |

- **Tab in Chrome** (`python -m http.server 8765 --bind 127.0.0.1` from `workspace/`):
  - All 40 sheets and 7 figures load at their declared sizes, and the image preview offers download and close.
  - The viewer plays March in all facings and shows Death 2's last frame.
  - Narrow widths were checked in iframes only. The workspace rule is now desktop only (`processes/workspace-authoring.md` step 7), so phone checks aren't needed.

## To judge (owner acceptance pending)
1. **Step into lane** (fix in `e40ed6a`): is the twist now spread well enough over his spine, neck and head? And is the SE spear acceptable? It now stands nearly upright with the tip a little to the right; before, it leaned further right. `travel` 1.0 gives the old lean but runs the shaft over his face.
2. **Hit** (wrist fix in `906687a`): does the up-to-10° wrist bend read naturally? It is subtle from the battle camera: the shaft lies a little further from his belly at frames 17–19 and from his left forearm at frames 39–41.
3. **Death 1:** from above, the cape ends bunched on the upper back and shoulders, because it is flung up as he pitches forward. From the battle camera it reads as lying on his back.
4. The death caches are still settling slightly in their last frames.
5. **The re-baked cape** (leftover-scale fix in `627c2c1`): every clip's cloth is a new sample. Check the march from the NE, where the cape now hangs closer to his back instead of flaring wide, and the deaths, which count more poke-through (Death 2 159 vs 125). If an old bake looked better, its cache can't be reproduced from the fixed rig; the alternative is a deliberate change to the cloth settings.

Items 3–5 have no decided fix. Wait for the user's verdict before changing anything.

## Accepted decisions (keep)
- **Shoulder carry:** `SHOULDER_CFG = contact [-0.20,-0.11,1.55], len 0.16, fwd -22, out 3, butt_z 0.85, pole [-0.3,0.6,-1.0], travel 0.75`. The palm faces the chest.
  - Until the neck fix, the lean was measured from the chest (Spine2) alone, with the wrist bending 11–15°.
  - With the spine untwisted, the chest faces about 35° left of the hips. "travel" mixes in the hips (his walking direction) so the SE tip still leans right. The wrist now bends up to 11°.
  - `SPINE_UNTWIST` and the `SPEAR_SHOULDER` JSON can be overridden through environment variables for trials.
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
- The Mixamo FBX sources are in `projects/meridius/Animations/`, their final location since 2026-10-24 (formerly `E:\Animations`). The folder is gitignored; never commit raw Mixamo files.
- Python with Pillow and numpy: `C:\Users\calle\AppData\Local\Temp\claude\E--ProjektM-BWC-GAMES-godot\d8823a10-5e83-448e-b4e6-5c6ea96da2ae\scratchpad\venv-art\Scripts\python.exe` (run it with `-I`). It is a temp folder, so any Python with Pillow and numpy will do.
- The old skinned-cape rig (`rig_tw.blend`, used for the figure's "before" frames) stays only in that scratchpad.
- `spear_motion.py` edits the clip's keys in place (spine untwist, neck, arm). Always re-run the retarget before it. For step_lane, run `retarget_clips.py -- 'E:/ProjektM/BWC_GAMES-godot/projects/meridius/Animations' step_lane` (source `projects/meridius/Animations/Standing Walk Right.fbx`), then `spear_motion.py -- step_lane`. It prints the wrist bend and the chest's turn (−40…−32° now).

**Checked 2026-10-24 against the committed results** (see `cape_poke.py` for why the cape read is now unconditional):
- `pack_sheets.py` reproduced all 40 sheets and `frames.json` byte for byte.
- The three figure scripts reproduced the deaths, cape and lineup images byte for byte.
- A re-bake of turn_90 matched the installed cache exactly.
- turn_90 renders matched pixel for pixel.
- `poke_cape.sh` gave attack 30 / worst 2 without `DBG`.
- `cape_inspect.py` gave Death 1 at f72 with the cape on his back.
- The lineup renders matched pixel for pixel.

**Godot tests at `aa697b4`.** `tools/test.sh --quick` gave 398 passed and 1 failed: `test_audio::test_a_marching_squad_is_one_tread` (6 footmen marching 2 s, 10 treads heard). That test file, `tests/unit/test_audio.gd`, is untracked. It belongs to another session's uncommitted audio work (`scripts/audio/sfx.gd`, `battle_view.gd`, `battle_draw.gd`). It isn't part of the spearman commits; leave it to that session.

**`906687a`** was committed after a full `tools/test.sh` run that gave 389 passed and 4 failed: two campaign parity tests, `test_audio`, and `test_squad_skills.gd`, which doesn't parse because `icon.gd` has no `painted()`. All four come from other sessions' uncommitted game code. The commit changes only `art/` and `workspace/`.

**`627c2c1`** was committed at the user's request ("commit now, don't wait") without waiting for the full `tools/test.sh`. `tools/test.sh --quick` on the same files gave 402 passed and 1 failed: `test_audio::test_a_marching_squad_is_one_tread`. Per the coordinator, that failure comes from another session's unit-outline shader draft (the `custom_samplers` shader error), which the user chose to discard; the coordinator is removing it. The commit changes only `art/` (which Godot ignores via `.gdignore`) and `workspace/`.

**`e40ed6a`** was committed at the user's request ("commit now, don't wait") before the full `tools/test.sh` run finished. It changes only `art/spearman_3d/` (Godot ignores `art/` through `.gdignore`) and `workspace/`, outside the Godot project, so no game code or imported asset changed.

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
