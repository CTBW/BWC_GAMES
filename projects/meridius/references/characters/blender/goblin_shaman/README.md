# Goblin shaman base scene and rig

`goblin_shaman_base.blend` holds the textured Tripo body, his staff and the horned
skull mask, scaled and placed, with the mask fitted to his face, ready for rigging.
`goblin_shaman_rig.blend` is the goblin rigged with both. Each object's base colour is
in `textures/` (4096², linked by relative path). The mask is trimmed to a face plate
first, in `goblin_shaman_mask_plate.blend`. Everything is built in background Blender
from the Tripo exports in `../../tripo/goblin_shaman/` (`<model>__take-01.zip`); see
`../../goblin_shaman/prompts.md` and its `jobs.json` for where they came from.

```sh
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
S=projects/meridius/references/characters/blender/goblin_shaman
T=projects/meridius/references/characters/tripo/goblin_shaman
"$B" -b --factory-startup --python $S/tools/trim_mask.py -- $T $S/goblin_shaman_mask_plate.blend
"$B" -b --factory-startup --python $S/tools/build_goblin_shaman.py -- $T $S/goblin_shaman_base.blend
"$B" -b $S/goblin_shaman_base.blend --python $S/tools/render_check.py -- <out dir>
```

Set `BLENDER_USER_RESOURCES` to an empty folder for these runs (see
`knowledge/tripo-studio.md`).

## Face plate

- **Cut:** Tripo modelled the mask as a whole skull, open underneath, with a strap
  band round it and a back painted dark brown. The user asked for the cut just behind
  the horns. Their bases end 0.30–0.32 of the depth from the front, so a vertical cut
  keeps the front 33% (0.288 of 0.874 in Tripo's units, where the mask is 1 high),
  0.013 behind the nearer horn base. It deletes the cranium, the painted back and the
  strap band with its pegs, which begins at 35%. The face, the brow, both horns and
  the cheekbones stay whole. A first cut at 43%, which kept the strap pegs, was
  replaced the same day.
- **Caps:** the shell is thick, so the cut leaves one horseshoe-shaped section, capped
  facing back, so the plate is watertight: 1,176 faces (1,756 before, 87 of them caps),
  with no open or non-manifold edges. Each loop is capped on its own, since a part that
  pierces the shell (as the pegs did at 43%) leaves a small section that overlaps the
  shell's. Each cap triangle takes one flat colour from the nearest outside face on the
  cut, so the rim is bone.
- **Frame:** the plate file keeps it where Tripo put it, front toward -Y and Z up, 1
  high. The base build scales it and fits it to his face (below).
- **Known limits:** the inside of the plate is dark brown, as Tripo painted the
  inside of the shell; it lies against his face. No strap holds it on: the rig keeps
  it rigid on the head.

## Base build

- **Scale:** the goblin is 1.486 m tall, the footman's 1.82 m times the battle
  view's figure heights, 40 px for a small unit against 49 for a man
  (`squad_view.gd`), as for the other goblins. His feet are on the ground and he
  faces -Y like the Mixamo clips.
- **Centre:** Tripo's model is a few centimetres off his mirror plane. He is moved
  onto it, the middle of five pairs of small mirrored parts, 3.3 cm in x, and front
  to back onto the middle of his body at the belt (12.5 cm), so he turns on the spot.
- **Staff:** 1.65 m from foot to horn tips, a little taller than him as in the brief.
  Its long axis is on Z with the skull up, facing -Y as in the Tripo front view.
  Below the rags the shaft is thinned so a goblin's three fingers close round it:
  the bare wood from 4.8 cm to 3.3 cm (the spearman's 3.4 cm less 1 mm), and the
  leather grip from 5.7 cm to 3.6 cm, so it stands 1.5 mm proud of the wood as on
  Tripo's staff. Each slice is thinned about its own middle, so the gnarled bends
  stay. The skull, the rags and the feathers keep Tripo's size. Its origin is on the
  grip's axis at its middle, 0.652 m from the foot. The properties `length`,
  `shaft_r`, `grip_r` and `grip` (the grip's ends, ±0.099 m in the staff's space)
  record this.
- **Mask:** the plate is 0.27 m tall (0.203 wide, 0.147 deep), its eye sockets level
  with his eyes and centred on his mirror plane; the sockets are 9.5 cm apart, his
  eyes 9.8 cm. It is moved back onto his face and bent round his head, so its back
  edge rests on his cheeks and brow 1.7–10 mm off the face (median 3.2 mm). The snout and brow it hides are pushed back
  behind it, up to 3.8 mm, 3 mm off its inside. No mask face passes through the body.
  The properties `scale`, `gap`, `bend` and `rim_fade` record the fit. The staff and
  the mask stand in the `Props` collection.

## Rig

`goblin_shaman_rig.blend` is built from the base scene by
`tools/rig_goblin_shaman.py`, which follows the goblin archer's rig, with the
spearman's skirt flaps. `tools/render_rig.py` renders review sheets and prints the
grip and clearance measurements, including any body triangles that cut through the
staff or the mask.

```sh
"$B" -b $S/goblin_shaman_base.blend --factory-startup --python $S/tools/rig_goblin_shaman.py -- \
  <absolute path>/goblin_shaman_rig.blend
"$B" -b $S/goblin_shaman_rig.blend --python $S/tools/render_rig.py -- <out dir>
```

- **Skeleton:** 75 bones with Mixamo names, so Mixamo clips play on it. 52 of them
  deform the mesh, with at most four per vertex: the Mixamo body, three fingers and a
  thumb on each hand (the shaman's hands have no little finger), forearm twist bones,
  and `FlapFront1`, `FlapFront2`, `FlapBack1` and `FlapBack2` down the red front flap
  and the back of the skirt. The `Staff` and `Mask` bones, the controls and the
  helper are non-deforming, each group in its own bone collection.
- **Skin:** bone heat on the body with the skirt cut away below z 0.64, where it hangs
  free of the legs, and on each leg (a separate shell) with that leg's bones and the
  hips; geometric weights on the hands, so a finger moves only its own skin. The red
  front flap hangs from its own bones. The skirt hangs from the back bones down the
  middle of its back and, toward its sides, from the hips and the thigh it covers
  (0.7 of the way at the hem), as the rabble's does. The face round the mask follows
  the head alone (237 vertices, 249 more blended into the neck), so the mask keeps
  its gap however the neck bends. The eyes and tusks follow the head; the necklace,
  its fangs and the skull pendant are rigid on the chest; the belt's skull, pouches,
  bone and feathers are rigid on the hips.
- **Grips:** solved on the skin as for the archer. The right hand closes round the
  staff's leather grip, laid across the palm at the tilt and place that close the
  three fingers best. Each finger comes within 0.2–0.4 mm of the grip on at least one
  phalanx; the fist sits 3 mm from the grip's middle. The thumb closes the other way.
  The left hand curls loosely round a 2 cm rod. Each grip is a one-frame Action
  (`grip_staff`, `grip_relax`) applied by Action constraints on the finger bones.
- **Staff:** rides the `Staff` bone in the right fist, its skull toward the thumb and
  turned 90° about its length, so the skull faces away from the wrist. The right hand
  keeps the turn it has in `stand` from the forearm, whatever a clip does to the
  wrist (`StaffHold`, `staff_hold`, 1 by default; 0 gives the wrist back to the clips
  and `HandIK.R`).
- **Mask:** rides the `Mask` bone, a child of the head. With the head and neck turned
  40° either way, nodded 25° down and up and tilted 15° either way, no body triangle
  passes through it and the face stays 0.6 mm off it at the nearest.
- **Flaps:** `FlapFront1` swings forward with the leading thigh and `FlapBack1` back
  with the trailing one (drivers, 0.8 of the swing).
- **Standard pose:** the Action `stand`, active when the file opens. The left arm
  hangs as the rabble's. The right arm's angles and the hand's roll were searched for
  the staff held beside him nearest upright, its skull facing ahead and its foot as
  low as the grip allows. The staff also has to stay 2 cm clear of the body and the
  mask and, seen from the front, 22 cm out from his middle beside his head. The upper
  arm is 32° out and 10° forward, the elbow bent 50°, the wrist turned 20° toward the
  thumb and the hand rolled 60° about its length. The staff leans 3° (ahead), its skull faces
  16° to his right, and its foot is 23 cm off the ground. It is 7.6 cm clear of the
  body and 21 cm of the mask. No body triangle other than the fist's passes through
  the staff in the standard pose or the T-pose.
- **Controls:** `staff_ik`, `cast_ik` and `leg_ik` (0 by default) switch on IK for the
  right arm (toward `HandIK.R`, which follows `StaffCtrl`, which follows the chest),
  the left arm (`HandIK.L`, which follows the chest) and the feet (`FootIK.L`,
  `FootIK.R`, with `KneePole.L` and `KneePole.R`). `stand` keys the controls where the
  pose has put the hands, the staff and the elbows, so switching the IK on keeps the
  pose (the right forearm moves 6.9 mm).
- **Known limits:** the thumb lies along the grip instead of folding over the index
  finger, as on the other goblins. Ten finger triangles cut the round grip between
  vertices that stay 0.4 mm outside it. The leather grip is at his hip height, so a
  fist that holds the staff upright cannot plant its foot on the ground. The skirt
  passes through the legs a little in a stride (11–15 leg triangles) and a high kick
  (20), none in the standard pose.
