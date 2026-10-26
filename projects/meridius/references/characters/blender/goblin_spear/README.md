# Goblin spearman base scene and rig

`goblin_spear_base.blend` holds the textured Tripo body and his spear, scaled and
placed, ready for rigging. Each object's base colour is in `textures/` (4096²,
linked by relative path). The scene is built in background Blender from the Tripo
exports in `../../tripo/goblin_spear/` (`<model>__take-01.zip`); see
`../../goblin_spear/prompts.md` and its `jobs.json` for where they came from.

```sh
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
S=projects/meridius/references/characters/blender/goblin_spear
"$B" -b --factory-startup --python $S/tools/build_goblin_spear.py -- \
  projects/meridius/references/characters/tripo/goblin_spear $S/goblin_spear_base.blend
"$B" -b $S/goblin_spear_base.blend --python $S/tools/render_check.py -- <out dir>
```

Set `BLENDER_USER_RESOURCES` to an empty folder for these runs (see
`knowledge/tripo-studio.md`).

## What the build does

- **Scale:** the goblin is 1.49 m tall, the footman's 1.82 m times the battle
  view's figure heights, 40 px for a small unit against 49 for a man
  (`squad_view.gd`), as for the goblin archer. His feet are on the ground and he
  faces -Y like the Mixamo clips.
- **Centre:** Tripo's model is a few centimetres off his mirror plane. He is
  moved onto it, the middle of the eleven pairs of small mirrored parts (bracer
  studs, eyes, horns, rivets), 2.4 cm in x, and front to back onto the middle of
  his pelvis, so he turns on the spot.
- **Spear:** 1.80 m from butt to tip, about 1.2 times his height as in the
  concept sheet, its long axis on Z with the head up and the leaf's flat face
  toward -Y. Below the red rag the shaft is thinned from Tripo's 5.6 cm to 3.4 cm,
  the human spearman's 4 cm scaled to the goblin, so his fingers close round it;
  the butt cap and the leather grip are thinned with it, the rag, the socket and
  the head keep Tripo's size. Its origin is on the shaft's axis at the middle of
  the leather grip, 0.805 m from the butt. The properties `length`, `shaft_r` and
  `grip` (the leather grip's ends, in the spear's space) record this. It stands
  beside the body in the `Props` collection.

## Rig

`goblin_spear_rig.blend` is the goblin rigged with his spear. It is built from the
base scene by `tools/rig_goblin_spear.py`, which follows the goblin archer's rig.
`tools/render_rig.py` renders review sheets and prints the grip and clearance
measurements, including any body triangles that cut through the spear.

```sh
"$B" -b $S/goblin_spear_base.blend --factory-startup --python $S/tools/rig_goblin_spear.py -- \
  <absolute path>/goblin_spear_rig.blend
"$B" -b $S/goblin_spear_rig.blend --python $S/tools/render_rig.py -- <out dir>
```

- **Skeleton:** 84 bones with Mixamo names, so Mixamo clips play on it. 60 of them
  deform the mesh, with at most four per vertex: the Mixamo body, four fingers and a
  thumb on each hand, forearm twist bones, `Cape1` and `Cape2` down the middle of the
  cape, and `FlapFront1`, `FlapFront2`, `FlapBack1` and `FlapBack2` for the skirt
  flaps. The spear's bones, the controls and the helpers are non-deforming, each
  group in its own bone collection.
- **Skin:** bone heat on the body, with the cape and the flaps cut away where they
  hang free (the cape below z 1.0, the flaps below z 0.6); geometric weights on the
  hands, so a finger moves only its own skin. The back of the fur mantle, where the
  cape hangs from it, follows the chest, neck and collarbones, never the upper arms.
  The eyes follow the head; the studs, horns, rivets, chest boss and buckle (26
  small parts) are rigid on the skin under them.
- **Grips:** solved on the skin as for the archer. Each hand closes round the shaft,
  laid across the palm at the tilt and place that close the four fingers best; the
  thumb closes the other way, toward the index finger, and both thumbs point toward
  the head. The right (rear) fist holds the bare shaft 0.394 m from the butt, the
  left (front) fist the leather grip, 0.367 m further up. Each grip is a one-frame
  Action (`grip_spear_r`, `grip_spear_l`) applied by Action constraints on the finger
  bones.
- **Spear:** rides the `Spear` bone in the right fist. The left hand holds it through
  `SpearGrip.L`, a child of `Spear` on the shaft's axis at the left fist: moving it
  along its length slides the hand along the shaft, turning it about its length turns
  the hand round the shaft. `HandIK.L`, its child, is where the left hand holds on,
  and `support_ik` (1 by default) keeps it there through IK.
- **Cape and flaps:** `Cape1` swings back with the trailing thigh (a driver, 0.6 of
  its swing), `FlapFront1` forward with the leading thigh and `FlapBack1` back with
  the trailing one (0.8).
- **Standard pose:** the Action `stand`, active when the file opens. The right fist
  is beside the right hip, the spear points 35° to his left and its head is raised
  30°, crossing in front of him, and the left hand reaches forward to the leather
  grip. This is the concept's hold mirrored, so the right hand drives the spear. The
  pose was searched (the fist's place, the spear's heading, slope and turn, the left
  hand's turn round the shaft and slide along it), both arms reaching their hands by
  IK, for wrists that bend and twist little with the spear and the forearms clear of
  the body. The left wrist bends 16° and twists 77°, the right 7° and 11°. The spear
  is 6.1 cm and the forearms and hands 3.3 cm (left) and 4.9 cm (right) clear of the
  torso, skirt, cape and legs. The blade's flat lies level. No body triangle other
  than the fists passes through the spear in the standard pose or the T-pose.
- **Controls:** `spear_ik` and `leg_ik` (0 by default) switch on IK for the right arm
  (toward `HandIK.R`, which follows `SpearCtrl`, which follows the chest) and the
  feet (`FootIK.L`, `FootIK.R`, with `KneePole.L` and `KneePole.R`). `stand` keys
  the controls where the pose has put the hands, the spear and the elbows, so
  switching the IK on keeps the pose (the right forearm moves 3.9 mm).
- **Known limits:** the right thumb lies along the shaft instead of closing round it.
  At the right grip the little finger meets the shaft's knot rings and goes up to
  4.7 mm into them. No other finger goes more than 3.4 mm into the shaft (the left
  hand's 0.9 mm), and the shaft goes no more than 2 mm into a palm.

## Clips

The goblin's Idle, the spearmen's Walk and Attack, and the goblin's Death are
Mixamo downloads in `projects/meridius/Animations/`, which stays local, so the
retargeted motion goes into a separate scratch copy of the rig rather than into
`goblin_spear_rig.blend`.

```sh
"$B" -b $S/goblin_spear_rig.blend --python $S/tools/retarget_clips.py -- \
  projects/meridius/Animations <spear_clips.blend> <measure.json>
CLIP_W=1100 CLIP_H=880 "$B" -b <spear_clips.blend> --python $S/tools/render_clips.py -- \
  <renders> idle=idle walk=walk attack=attack
CLIP_W=2080 CLIP_H=1300 "$B" -b <spear_clips.blend> --python $S/tools/render_clips.py -- \
  <renders> death=death
python $S/tools/pack_sheets.py <renders> workspace/2026-10-20_meridius/goblin-spear-3d \
  idle walk attack death
```

| Clip | Source | Frames | Notes |
|---|---|---|---|
| `idle` | Idle - Goblin | 201 (6.67 s) | in place; the last 10 frames ease into the first |
| `walk` | Walk - Spearmen | 42 (1.37 s) | in place, loops; 0.91 m a stride, 0.66 m/s |
| `attack` | Attack - Goblin Spearmen | 1–64 (2.10 s) | from and back to the idle's first pose (8 and 12 frames) |
| `death` | Death - Goblin | 72 (2.37 s) | eased in from the idle over 8 frames; drops the spear |

- **Retarget:** as the goblin rabble's, bone by bone in world space, with the hips'
  motion scaled by the hip-height ratio (0.652). The fingers keep the grip Actions.
  The walk's and the attack's hips rise or drop (up to 2 and 4 cm) so the lowest
  point of the soles stays on the ground; in the death they are lifted wherever
  the body would go below it (up to 24 cm), smoothed so the lift never pops.
- **Carry:** the idle and the walk were made for empty hands, so both arms keep
  the standard pose on the clip's chest. Their bent-kneed stance brings the right
  thigh 20.5 mm into the shaft, which no bend of the wrist clears, so the right
  arm turns 10° out at the shoulder in every frame of both (the least turn that
  clears them all, kept as `carry_arm` and in `stand` in the clips scene, not in
  `goblin_spear_rig.blend`). Least gap 7.8 mm.
- **Thrust:** the attack keeps the source's first 64 frames (the rest holds an
  upright guard to frame 99). In every frame the right wrist turns the spear onto
  the line through the clip's left fist (20–64°), and the left hand's hold slides
  and turns on the shaft to that fist. Then, each the least that clears the shaft
  off the body, the spear slides forward through the right fist (up to 0.24 m,
  frames 4–45), the right arm turns at the shoulder (up to 8°, frames 6–45, the
  left hold sliding back up to 5 cm for reach) and the right wrist bends (not
  needed). Least gap 5.8 mm (the head, frame 33).
- **Death:** the arms leave the standard pose over 12 frames and the left hand
  lets go in frames 3–9. The right fist opens at frame 46; the spear turns level,
  its blade flat, and drops to the ground, pushed 0.30 m out so it stays clear of
  him. The right forearm grazes the shaft as the fist opens, up to 4.5 mm into it
  in two frames, with no triangle crossing.
- **Checked:** no body triangle cuts through the spear (the hands holding it left
  out) in any of the 379 frames. The left wrist bends up to 82° in the thrust (the
  right 50°).
- **Frames:** Workbench, flat-lit with an outline and cavity, an orthographic
  camera 30° above the ground in the four facings, 254.5 px per metre, in a
  1100 × 880 frame (the thrust's reach) and 2080 × 1300 for the death (he falls
  far to one side and the spear lands beyond him). The sheets are packed at 0.75
  for the Workspace's pose viewer; the death gets its own `canvas` in
  `frames.json`.

## Godot export

`tools/export_godot.py` bakes the clips scene into a GLB for the Godot sandbox,
with a JSON sidecar beside it. `tools/check_export.py` compares the GLB with the
rig it came from (0.00 mm in every sampled frame).

```sh
G=projects/meridius/source/godot/prototypes/goblin_spear_anim/art3d
"$B" -b <spear_clips.blend> --python $S/tools/export_godot.py -- $G/goblin_spearman.glb
"$B" -b <spear_clips.blend> --python $S/tools/check_export.py -- source <samples.npz>
"$B" -b --factory-startup --python $S/tools/check_export.py -- glb $G/goblin_spearman.glb <samples.npz>
```

An optional second argument sets the textures' size (1024 px by default, JPEG).

- **Bake:** the 60 deforming bones and `Spear`, sampled at every frame and keyed as
  linear Actions `idle`, `walk`, `attack` and `death` (bake error under 0.001 mm);
  the constraints, drivers and the rig's own Actions go, and the spear is skinned
  whole to `Spear`. 11,497 triangles.
- **Sidecar:** fps, height (1.46 m in the standard pose, 1.49 m in the T-pose),
  forward +Z, `roles` (no hit clip) and per clip its length and loop flag. The
  walk has its `root_vel` (0.66 m/s forward) and its footfalls; the attack its
  blow (`contact`, 1.267 s, the tip furthest forward, 2.29 m from where he
  stands), the thrust's span and the tip's height and speed; the death its root
  motion, `spear_drop` (1.5 s) and when it settles (2.2 s).
