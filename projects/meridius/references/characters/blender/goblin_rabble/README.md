# Goblin Rabble base scene and rig

`goblin_rabble_base.blend` holds the textured Tripo body and its five props, fixed
and scaled, ready for rigging. Each object's base colour is in `textures/` (4096²,
linked by relative path). The shields' straps take theirs from
`textures/goblin_rabble_straps_basecolor.jpg` (1024²), painted by
`tools/paint_straps.py` (`python tools/paint_straps.py`, numpy and Pillow). The scene is built in background Blender from the Tripo
exports in `../../tripo/goblin_rabble/` (`<model>__take-01.zip`); see
`../../goblin_rabble/prompts.md` and its `jobs.json` for where they came from.

```sh
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
D=projects/meridius/references/characters/blender/goblin_rabble
"$B" -b --factory-startup --python $D/tools/build_rabble.py -- \
  projects/meridius/references/characters/tripo/goblin_rabble $D/goblin_rabble_base.blend
"$B" -b $D/goblin_rabble_base.blend --python $D/tools/render_check.py -- <out dir> [original body.fbx]
```

Set `BLENDER_USER_RESOURCES` to an empty folder for these runs (see
`knowledge/tripo-studio.md`).

## What the build does

- **Scale:** the goblin is 1.26 m tall, with his feet on the ground and centred,
  facing -Y like the Mixamo clips. That is the 1.82 m used for the footman,
  spearman and crossbowman, times the battle view's figure heights: 34 px for the
  rabble against 49 for a man (`member_height` in
  `projects/meridius/source/godot/scripts/render/squad_view.gd`).
- **Chain:** Tripo modelled the seven links of the broken collar chain rigid,
  sticking out forward and down at 49°. They are turned about the top link, which
  passes through the collar's ring, to hang straight down. The links below it are
  moved 16 to 19 mm forward, so they clear the collar's lower edge and the chest.
  The front view is unchanged apart from the chain reaching 6 cm lower, to the
  bottom of the sternum. The links are in the vertex group `Chain`, for weighting
  them to the chest or to a dangle bone later.
- **Props:** each is scaled to its length, with its long axis on Z and its front
  facing -Y as in the Tripo front view. They stand in the `Props` collection to
  the right of the body. Lengths are read off concept B against the goblin's
  height:

  | Object | Length | Origin |
  |---|---|---|
  | `Knife` | 0.46 m | on the handle's axis, halfway between the pommel and the guard |
  | `Hatchet` | 0.50 m | on the haft's axis, at the middle of the leather wrap, 17% up |
  | `Cleaver` | 0.44 m | on the handle's axis, halfway below the blade |
  | `ShieldBarrel` | 0.50 m across | middle of the back |
  | `ShieldPlank` | 0.64 m tall | middle of the back |

  A weapon's origin is on the axis of its handle, not at the middle of the whole
  prop, because the hatchet's head and the cleaver's blade stick out to one side.

## Rig

`goblin_rabble_rig.blend` is the goblin rigged with his five props. It is built
from the base scene by `tools/rig_goblin_rabble.py`, and `tools/render_rig.py`
renders review sheets and prints the grip and clearance measurements, including
any body triangles that cut through a prop.

```sh
"$B" -b --factory-startup $D/goblin_rabble_base.blend --python $D/tools/rig_goblin_rabble.py -- \
  $D/goblin_rabble_rig.blend
"$B" -b $D/goblin_rabble_rig.blend --python $D/tools/render_rig.py -- <out dir>
```

- **Skeleton:** 87 bones with Mixamo names, so the goblin's Mixamo clips play on
  it. They include the fingers, forearm twist bones, three bones for the collar
  chain, two for each loincloth flap and the helper `ShieldFist`. 61 of them
  deform the mesh, with at most four per vertex.
- **Loadouts:** the rig's `loadout` property picks 0 knife and barrel shield,
  1 hatchet and plank shield, or 2 cleaver and barrel shield. The weapon rides the
  `Weapon` bone in the right hand. The shield rides the `Shield` bone on the
  outside of the left forearm, face out, low enough that the back of the fist
  lies on its flat middle rather than its edge. Each shield gets its own outward
  tilt (barrel 4°, plank 5.5°) and the left wrist bends 1°, chosen so the
  forearm and the fist both lie 1 to 1.5 mm under its back in the standard pose,
  with no skin through it in the T-pose either. The barrel then slides 2 cm
  further toward the hand, so its round rim stays off the upper arm above the
  elbow: no body triangle passes through either shield in either pose. The rig's
  `shield_fit` property records the fit.
- **Grips:** the fingers are solved on the skin to close round each weapon's
  handle without going into it. Each grip is a one-frame Action (`grip_knife`,
  `grip_hatchet`, `grip_cleaver`, and `grip_fist` for the left hand), applied by
  Action constraints on the finger bones.
- **The fist's hold:** the left hand keeps the turn from the forearm it has in
  `stand`, whatever a clip does to the wrist, so the fist stays on the shield's
  back and round the barrel's handle. The hidden helper bone `ShieldFist` (bone
  collection `Mechanics`) rides the forearm at that turn, and a Copy Rotation
  constraint on `mixamorig:LeftHand` follows it as much as the rig's `shield_fist`
  property says (1 by default, 0 to let the clip's wrist through).
- **Straps and handle:** two stitched leather straps, at 18% and 82% of the
  forearm's length, hold each shield. Each runs taut round the forearm 1.5 mm off
  the skin and is nailed flat to the board at both ends with two rivets. A strap
  may move up to 2.4 cm along the arm onto flatter boards; on the plank shield
  the one at the wrist moves 2 cm. The barrel shield also has a handle for the fist: a round wooden bar
  along the rod the fist was solved round, on two posts beside the fist, nailed
  to the board, in the barrel's own wood. The bar is as thick as fits inside
  the closed fingers, measured on the hand's skin along its length, and never
  thicker than the rod the fist was solved round (here 15 mm). The posts stand on
  the barrel's face, a single sheet with no thickness, so nothing shows through
  its front. They are the objects
  `ShieldBarrelStraps` and `ShieldPlankStraps`, shown with their shield's
  loadout. No body triangle passes through a strap in the standard pose or the
  T-pose, the arm's skin stays at least 1.3 mm under them, and only the left
  hand's fingers touch the handle.
- **Standard pose:** the Action `stand`, active when the file opens. The arms hang
  at the sides with the elbows a little bent, the weapon points forward and the
  shield faces out. The skin itself is bound to the T-pose.
- **Controls:** `weapon_ik`, `shield_ik` and `leg_ik` (0 by default) switch on IK
  toward `HandIK.R` (which follows `WeaponCtrl`), `HandIK.L` and the `FootIK` bones.
  `stand` keys these controls where the pose has put the hands and elbows, so
  switching the IK on keeps the pose.
- **Arm rag:** the rag tied round the left upper arm lies under both shields. Its
  two tails, which stood up to 5.5 cm through them, are removed. Its knot and
  band stay as modelled, at least 3 mm under the shields' backs.

## Clips

The goblin's Idle, Attack and Death clips are Mixamo downloads in
`projects/meridius/Animations/`, which stays local, so the retargeted motion goes
into a separate scratch copy of the rig rather than into `goblin_rabble_rig.blend`.

```sh
"$B" -b $D/goblin_rabble_rig.blend --python $D/tools/retarget_clips.py -- \
  projects/meridius/Animations <goblin_clips.blend> <measure.json>
"$B" -b <goblin_clips.blend> --python $D/tools/render_clips.py -- <renders> \
  attack_knife=attack:0 attack_hatchet=attack:1 attack_cleaver=attack:2 idle=idle:0 death=death:0
python $D/tools/pack_sheets.py <renders> workspace/2026-10-20_meridius/goblin-rabble-3d \
  attack_knife attack_hatchet attack_cleaver idle death
```

- **Retarget:** as the spearman's, bone by bone in world space, with the hips'
  motion scaled by the hip-height ratio (0.556). The fingers keep the grip
  Actions. The idle is kept in place and eases its last 10 frames into its first,
  so it loops. In the death the hips are lifted wherever the body or a prop
  would go below the ground (up to 34 cm), smoothed so the lift never pops.
- **Arms:** the clips were made for empty hands. In every frame the left fist
  is held at its standard turn on the shield, then the elbow opens, the arm lifts
  out from the chest or the forearm rolls, cheapest first, until no body
  triangle passes through either shield, its straps or the barrel's handle. The
  right arm is eased toward the standard pose where a weapon would cross the
  body, which happens only in the idle. Each correction is spread over its
  neighbouring frames.
- **Checked:** every prop of all three loadouts is clear of the body in all 201
  frames of the idle, 69 of the attack and 72 of the death.
- **Frames:** Workbench, flat-lit with an outline and cavity, an orthographic
  camera 30° above the ground in the four facings, 254.5 px per metre in a
  780 × 580 frame (wide enough for the death in every facing). The sheets are
  packed at 0.75 for the Workspace's pose viewer.

## Known limits

- The back of the body and the loincloth are painted darker and flatter than the
  front, because Tripo textures from the front image.
- The barrel shield is a flat disc with its staves painted on. The plank shield's
  nails come through at the back, and it has straps but no handle, so the fist
  closes empty against its boards.
- The thumb closes against each handle but does not yet fold over the index
  finger as in a real fist.
