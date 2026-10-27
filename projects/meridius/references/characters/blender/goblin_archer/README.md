# Goblin Archer base scene and rig

`goblin_archer_base.blend` holds the textured Tripo body with his bow, quiver and
arrow, scaled and ready for rigging. Each object's base colour is in `textures/`
(4096², linked by relative path). The scene is built in background Blender from the
Tripo exports in `../../tripo/goblin_archer/` (`<model>__take-01.zip`); see
`../../goblin_archer/prompts.md` and its `jobs.json` for where they came from.

```sh
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
D=projects/meridius/references/characters/blender/goblin_archer
"$B" -b --factory-startup --python $D/tools/build_archer.py -- \
  projects/meridius/references/characters/tripo/goblin_archer $D/goblin_archer_base.blend
```

Set `BLENDER_USER_RESOURCES` to an empty folder for these runs (see
`knowledge/tripo-studio.md`), and pass the output paths as absolute Windows paths.

## What the build does

- **Scale:** the goblin is 1.486 m tall to the tip of his hood, with his feet on the
  ground and centred, facing -Y like the Mixamo clips. That is the footman's 1.82 m
  times the battle view's figure heights, 40 px for a small unit against 49 for a man
  (`member_height` in `projects/meridius/source/godot/scripts/render/squad_view.gd`).
- **Cape:** left as Tripo made it, one sheet from the shoulders hanging about 14°
  behind him, 8 to 10 cm clear of the back of his rag skirt.
- **Props:** each is scaled to its length, with its long axis on Z and its front
  facing -Y as in the Tripo front view, and its origin where the rig holds it. They
  stand in the `Props` collection beside the body. Lengths are read off the archer
  concept against the goblin's height:

  | Object | Length | Origin |
  |---|---|---|
  | `Bow` | 1.10 m | on the handle's axis at the middle of the grip, the string on +X |
  | `Quiver` | 0.62 m | middle of its back, halfway up the tube (the rim is 73% up) |
  | `Arrow` | 0.62 m | at the nock on the shaft's axis, the head up |

## Rig

`goblin_archer_rig.blend` is the goblin rigged with his bow, quiver and arrow. It is
built from the base scene by `tools/rig_goblin_archer.py`, and `tools/render_rig.py`
renders review sheets and prints the grip and clearance measurements, including any
body triangles that cut through a prop.

```sh
"$B" -b $D/goblin_archer_base.blend --factory-startup --python $D/tools/rig_goblin_archer.py -- \
  <absolute path>/goblin_archer_rig.blend
"$B" -b $D/goblin_archer_rig.blend --python $D/tools/render_rig.py -- <out dir>
```

- **Skeleton:** 77 bones with Mixamo names, so the goblin's Mixamo clips play on it.
  52 of them deform the mesh, with at most four per vertex: the Mixamo body, three
  fingers and a thumb on each hand (the archer's hands have no little finger),
  forearm twist bones, `Cape1` and `Cape2` down the middle of the cape and
  `FlapFront1` and `FlapFront2` for the front rag flap. The props' bones, the
  controls and the helpers are non-deforming, each group in its own bone collection.
- **Skin:** bone heat on the body shell and on the boots; geometric weights on the
  hands, so a finger moves only its own skin. The hood and the cape follow the head,
  neck, chest and collarbones, never the upper arms. Below the quiver the cape hangs
  from its own bones. Belt, pouch, skull, fangs, necklace and eyes are rigid.
- **Grips:** solved on the skin as for the rabble. The left hand closes round the
  bow's grip, its handle across the palm at the tilt (18°) and place along the grip
  that close the three fingers best; the thumb closes the other way, toward the index
  finger. Nothing goes more than 0.3 mm into the grip. The right hand curls loosely
  round a 2 cm rod, so the arrow sits in it. Each grip is a one-frame Action
  (`grip_bow`, `grip_relax`) applied by Action constraints on the finger bones.
- **Bow:** rides the `Bow` bone in the left hand, the string toward the elbow and the
  upper limb on the thumb's side. The `String` bone, a child of `Bow` at the nocking
  point 0.177 m behind the grip's axis, pulls the string's four middle vertices (a
  Hook modifier); the string has vertices only at the tips and the middle, so it draws
  into a clean V. The left hand holds its standard turn on the bow whatever a clip
  does to the wrist (`BowHold` and the rig's `bow_hold`, 1 by default).
- **Quiver:** rides the `Quiver` bone on the chest, slung diagonally across the back
  over the cape with its opening above the right shoulder. It leans 7.8° from upright
  against the cape's 13.8°, so its top stays off the hood, 6.0 mm clear of the cape
  with no triangle through it.
- **Arrow:** rides the `Arrow` bone in the right hand and is hidden while the rig's
  `arrow` property is 0.
- **Cape:** `Cape1` swings back with the trailing thigh (a driver, 0.6 of its swing)
  and further by the rig's `cape_back` (radians, 0 by default); `FlapFront1` swings
  forward with the leading thigh.
- **Standard pose:** the Action `stand`, active when the file opens. The right arm
  hangs; the left elbow is bent so the bow is held low beside the left leg, its upper
  limb raised 35° forward. The left arm's angles were searched for the most upright
  bow that stays off the body and the cape (its limbs 4.4 cm off), with the string 6 mm
  off the hip.
  No body triangle passes through the bow in the standard pose or the T-pose the skin
  is bound to.
- **Controls:** `bow_ik`, `draw_ik` and `leg_ik` (0 by default) switch on IK for the
  left arm (toward `HandIK.L`, which follows `BowCtrl`), the right arm (`HandIK.R`)
  and the feet (`FootIK.L`, `FootIK.R`). `stand` keys the controls where the pose has
  put the hands and elbows, so switching the IK on keeps the pose.

## Clips

The goblin's clips are Mixamo downloads in `projects/meridius/Animations/`, which
stays local, so the retargeted motion goes into a separate scratch copy of the rig
rather than into `goblin_archer_rig.blend`.

```sh
"$B" -b $D/goblin_archer_rig.blend --factory-startup --python $D/tools/retarget_clips.py -- \
  projects/meridius/Animations <archer_clips.blend> <measure.json>
CLIP_H=680 "$B" -b <archer_clips.blend> --factory-startup --python $D/tools/render_clips.py -- <renders> \
  idle=idle walk=walk run=run attack=attack block=block death=death
python $D/tools/pack_sheets.py <renders> workspace/2026-10-20_meridius/goblin-archer-3d \
  idle walk run attack block death
```

| Action | Mixamo clip | Frames | Notes |
|---|---|---|---|
| `idle` | Idle - Goblin | 201 (6.67 s) | in place; the last 10 frames ease into the first |
| `walk` | Walk - Goblin | 36 (1.17 s) | in place, loops; 1.01 m/s (`root_vel`) |
| `run` | Running - Goblin Archer | 27 (0.87 s) | in place, loops; 2.39 m/s |
| `attack` | Attack - Goblin Archer | 32 + 8 held (1.30 s) | the shot; `shot_frame` 32 |
| `block` | Hit - Goblin archer | 61 (2.00 s) | the hit reaction, used as the block |
| `death` | Death - Goblin | 72 (2.37 s) | he drops the bow; `bow_release` 42 |

- **Retarget:** as the rabble's, bone by bone in world space, with the hips' motion
  scaled by the hip-height ratio (0.657). The fingers keep the grip Actions. In the
  death the hips are lifted wherever the body or a prop would go below the ground
  (up to 26 cm). In the walk, the run, the attack and the block the hips rise or
  drop so the lowest point of the soles stays at its rest height (walk ±1 cm; the
  attack and the block come down 1.5 to 3.6 cm, as his legs are shorter than the
  clip's).
- **Bow arm:** the idle, walk, run and death were made for empty hands. In every frame
  the left hand keeps its standard turn on the bow (`bow_hold` 1), and the arm is
  eased toward the standard pose, then lifted out from the chest, the least that keeps
  the bow out of the body and off the ground: the idle and the walk lift it 10°, the
  run up to 50°, the death up to 30°. The attack and the block are the archer's own
  clips, so their wrist turns as the clip says (`bow_hold` 0); the block's arm is eased
  40% toward the standard pose, the attack's not at all. Each correction is spread over
  its neighbouring frames, round the seam of a loop.
- **The shot:** the arrow shows from frame 13, where the right fist is highest, its
  head pointing up over his shoulder as it comes out of the quiver. It turns toward the
  bow while the fist comes down onto the arrow's level, and its nock goes onto the
  string at frame 18, where the fist passes nearest the nocking point. From then the
  `String` bone follows the fist (eased in over 3 frames), and the fist stops at the
  anchor 0.517 m from the arrow rest, the string drawn 0.368 m. The arrow lies on the
  rest, 10.6 cm up the bow beside the handle, as low as clears the bow hand, so it
  stays level from the string to the rest, aimed 5.6° above level. To keep the fist,
  the arrow and the string out of his head, the fist moves out to his right along the
  arrow's level, up to 16 cm, with the elbow kept in the clip's plane. The arrow is
  loosed at frame 32 (1.03 s): it is hidden from frame 33 (the rig's `arrow` is keyed
  constant), the string swings back through rest over three frames, and the last pose
  is held 8 frames.
- **The bow drop:** in the death he lets go of the bow at frame 42, 1.1 cm above the
  ground. The hand opens and the `Bow` bone is keyed so the bow turns flat about its
  lowest point (51°), lying on the ground from frame 48, spun 30° and pushed 5 cm
  away, the first of the tried ways that keeps it out of him in every later frame.
- **Quiver and cape:** the quiver tips out from his back, up to 25° in the death and
  10° in the run and the attack, so it stays at least 6 mm off the body. In the block the
  right shin swings back into the cape in frames 7 to 21; there the lower cape swings
  back up to 5° and the upper one 5° further than its driver (`cape_back`).
- **Checked:** in every frame of all six clips (437 in all), no body triangle passes
  through the bow, the quiver or the shown arrow, none through the cape below the
  quiver, and no bone is left scaled.
- **Frames:** Workbench, flat-lit with an outline and cavity, an orthographic camera
  30° above the ground in the four facings, 254.5 px per metre in a 780 × 680 frame
  (taller than the rabble's for the raised bow). The sheets are packed at 0.75 for the
  Workspace's pose viewer.

## Godot export

`tools/export_godot.py` bakes the clips scene into a GLB for the Godot sandbox,
with a JSON sidecar beside it. `tools/check_export.py` compares the GLB with
the rig it came from.

```sh
G=projects/meridius/source/godot/prototypes/goblin_archer_anim/art3d
"$B" -b <archer_clips.blend> --python $D/tools/export_godot.py -- <absolute path>/$G/goblin_archer.glb
"$B" -b <archer_clips.blend> --python $D/tools/check_export.py -- source <samples.npz>
"$B" -b --factory-startup --python $D/tools/check_export.py -- glb <absolute path>/$G/goblin_archer.glb <samples.npz>
```

Then `tools/import.sh` in the Godot project. An optional second argument sets
the textures' size (1024 px by default, JPEG).

- **Bake:** the pose of the 56 deforming bones (the rig's 52 and `Bow`,
  `String`, `Quiver` and `Arrow`) is sampled at every frame of each clip.
  Then the constraints, drivers and the rig's own Actions are removed and the
  poses keyed as new linear Actions `idle`, `walk`, `run`, `attack`, `block`
  and `death` (bake error 0.001 mm). The bone shapes are deleted and the props
  skinned whole to their bones; the string's four middle vertices go to
  `String` with the Hook modifier's weights (1), in place of the modifier.
- **Arrow:** where the clip keys the rig's `arrow` to 0 (every clip but the
  shot's frames 13 to 32), the `Arrow` bone is keyed at zero scale, as the
  crossbowman's bolt, so Godot needs no visibility track.
- **Sidecar:** fps, height (1.46 m in the standard pose, 1.49 m in the
  T-pose), forward +Z, `roles` (idle, walk, attack `attack`, hit `block`,
  death, extra `run`) and per clip its length, loop flag and events. The walk
  and the run have their `root_vel` (1.01 and 2.39 m/s forward), the speed
  under the planted foot and their footfalls. The shot has `draw` (0.4 s,
  the arrow appears), `nock` (0.567 s), `shot` (1.033 s), `arrow_shown`,
  `shot_from` (the arrow's middle as he looses, 1.10 m up, 0.43 m ahead and
  0.29 m to his right), `aim_up_deg` 5.6 and `aim_yaw_deg` -3.2. The death has
  `bow_drop` (1.367 s) and when it settles (2.2 s).
- **Checked:** reimported into an empty scene, the GLB has 56 bones, 4 meshes
  and the six clips at full length. In six frames of each clip (and the shot's
  frame), no vertex is further than 0.01 mm from the rig's. The arrow is
  0.63 m long where it shows and collapsed to a point everywhere else.
- **Sandbox:** the roster's Goblin Archer (`prototypes/sandbox3d`) shoots an
  `arrow` missile from `shot_from` at `events.shot`; the arrow is as long as
  the model's, so at the release it takes the drawn arrow's place. Struck, he
  plays `block`.
- **Local only:** the GLB carries Mixamo motion, so it and the textures Godot
  extracts beside it are gitignored; the sidecar is in Git. The sandbox leaves
  the archer out where the GLB is missing.

## Known limits

- The thumb closes against the bow's grip and round the arrow but does not fold over
  the index finger as in a real fist.
- The arrow appears in the fist above his shoulder at frame 13. The clip's hand never
  reaches the quiver's opening, so it is not shown leaving the quiver.
- The string runs to the middle of the fist; no finger hooks it on its own.
- In the run the soles dip up to 1.6 cm below the ground in some frames: the hips'
  height is averaged over three frames, which a fast stride outruns.
