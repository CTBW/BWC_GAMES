# Goblin shaman base scene and rig

The goblin shaman comes in two variants, one in each mask: the user asked for one
shaman with the skull mask and one with the beak mask. A squad has three shamans.

| Variant | Base scene | Rig | Mask |
|---|---|---|---|
| Skull mask | `goblin_shaman_base.blend` | `goblin_shaman_rig.blend` | the horned skull, Tripo's mask trimmed to a face plate ([Horned face plate](#horned-face-plate)) |
| Beak mask | `goblin_shaman_beak_base.blend` | `goblin_shaman_beak_rig.blend` | the bird skull with a feather crest on a red band, built from code ([Beak mask](#beak-mask)) |

Each base scene holds the textured Tripo body, his staff and his mask, scaled and
placed, with the mask on his face, ready for rigging; each rig is the goblin rigged with
them. The two differ only in the mask and the face under it: the horned plate's fit
pushes his snout and brow back, and the beak mask is carved round his face as Tripo made
it. They share the staff and the body texture. Each object's base colour is in
`textures/` (linked by relative path), the body's with tribal markings in dried blood
painted on his skin. Everything is built in background Blender from the Tripo exports in
`../../tripo/goblin_shaman/` (`<model>__take-01.zip`); see
`../../goblin_shaman/prompts.md` and its `jobs.json` for where they came from.

```sh
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
S=projects/meridius/references/characters/blender/goblin_shaman
T=projects/meridius/references/characters/tripo/goblin_shaman
# The skull mask (MASK=horned, the default), from the trimmed plate:
"$B" -b --factory-startup --python $S/tools/trim_mask.py -- $T $S/goblin_shaman_mask_plate.blend
"$B" -b --factory-startup --python $S/tools/build_goblin_shaman.py -- $T $S/goblin_shaman_base.blend
# The beak mask:
MASK=beak "$B" -b --factory-startup --python $S/tools/build_goblin_shaman.py -- $T $S/goblin_shaman_beak_base.blend
"$B" -b $S/goblin_shaman_base.blend --python $S/tools/render_check.py -- <out dir>
```

Set `BLENDER_USER_RESOURCES` to an empty folder for these runs (see
`knowledge/tripo-studio.md`).

## Beak mask

The beak variant's mask. The user chose the bird skull mask with its feather crest
(`../../goblin_shaman/prompts.md`, 11), then asked for it to be built from code in
Blender, as the footman's captain helmet is, from the front view
`../../goblin_shaman/mask_bird_front.webp`, keeping its crest. `tools/beak_mask.py`
builds it round his face as the base build places him, and `tools/paint_beak_mask.py`
paints it. Run alone, the painter paints the base scene's mask again (the same texture,
but for a level on a few texels from Cycles' occlusion bake):

```sh
"$B" -b $S/goblin_shaman_beak_base.blend --factory-startup --python $S/tools/paint_beak_mask.py
```

- **Skull:** a signed distance field, in metres from the middle of his eyes: a domed
  cranium over his brow, two big round sockets with thick rims over his eyes, a bar
  under each to the beak's base with a small opening in it, and a long beak from
  between the sockets, hooked down to its tip, with a ridge along its top and a nostril
  slit each side. A hole goes through each socket to his eye, so his eyes show through.
  His face, 3 mm larger, is carved out of it, so it rests on him. The skull ends 7.8 cm
  below his eyes, at a slanted cut behind his temples and 1 cm above the band's middle.
  The field is meshed with surface nets on a 2.5 mm grid, smoothed back onto the
  surface three times and decimated to 3,000 triangles. Where one of the long triangles
  this leaves cuts his face (beside his snout, under the eye holes), its corners are
  moved off him, at most 1 mm (12 vertices).
- **Band:** red cloth 3.6 cm wide and 6 mm thick round his head over the skull's top
  edge, drawn tight round the skull and his head 2 mm off them and puckered a little.
- **Crest:** 23 feathers tucked into the band along its front and fanned 80° to either
  side of his front. They are 21.5 cm long in the middle and 14.5 cm at the ends, and
  about 4 cm wide. Every other feather stands 2.5 mm further back and 1.7 cm longer, a
  second row. Each rises from the band, then turns out and back, curling back toward its
  tip, 2.2 mm thick.
- **Polygons:** low-poly like the footman's helmet, shaded smooth with sharp edges
  where faces meet at 50° or more: 3,140 vertices and 4,575 faces (his body has 6,123).
  The skull is about 3,000 triangles, the band 64 sections of an 8-point profile, and
  each feather 8 segments long and 2 across.
- **Texture:** `textures/goblin_shaman_beak_mask_basecolor.jpg`, 2048², in one material
  (`GoblinShamanBeakMask`). The skull's UVs are Blender's smart projection. The bone is
  cream, mottled and grained, and stained brown in patches and in its creases (its own
  ambient occlusion, baked by Cycles out to 3 cm). The nostrils and the openings are
  dark brown. The sockets and the holes through them are dark grey, darker deeper in.
  The cracks are drawn as on the reference. The band is woven red cloth, darker along
  its edges and creased. The feathers have three patterns: cream at the root, brown
  with cream bars above, a dark tip, a pale shaft and fine barbs.
- **Fit:** the skull comes within 1.5 mm of his body at the nearest, the band 2.0 mm
  and the feathers 3.5 cm. The mask is 52 cm across the crest and reaches 16 cm above
  his crown. No body triangle passes through it. Its `eyes` property records the
  middle of his eyes it was built from.
- **Revisions:** the user asked for the eyes to be cut out in dark grey, the
  feathers to be a bit larger (they were 18 and 12 cm long and 3.2 cm wide) and the
  polygons to be simplified as on the footman's helmet (the first build had 14,777
  faces).
- **Known limits:** the inside of the skull, against his face, is painted as bone.
  No strap holds the mask on: the rig keeps it rigid on the head.

## Horned face plate

The skull variant's mask (`goblin_shaman_base.blend`, `MASK=horned`), the first one.

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
- **Beak mask** (`goblin_shaman_beak_base.blend`): see above. His face is left as
  Tripo made it.
- **Horned plate** (`goblin_shaman_base.blend`): the plate is 0.34 m tall (0.256
  wide, 0.192 deep), its eye sockets level with his eyes and centred on his mirror
  plane. It covers his face from the brow to
  below his mouth and out to his ears: the user asked for it to cover more of his face
  than the first fit (0.27 m) and chose 0.34 m over 0.31 and 0.37. The sockets are
  12 cm apart, wider than his eyes (9.8 cm). It is moved back onto his face and bent
  round his head, so its back edge rests on his cheeks and brow 0.7–7.1 mm off the face
  (median 4.0 mm). The snout and brow it hides are pushed back behind it, up to 9.4 mm,
  3 mm off its inside. That straight-back push misses where the plate runs front to
  back past him (its sides at his temples, the inside of its teeth at the corners of
  his mouth, one tusk), so what is still nearer than 3 mm is then pushed in along the
  plate's inside, up to 5.2 mm, the tusk as one piece. The bend leaves the plate's
  quads out of flat, so each is measured split along both diagonals. No mask face
  passes through the body. The properties `scale`, `gap`, `bend` and `rim_fade` record
  the fit. The staff and the mask stand in the `Props` collection.

## Body paint

Each base build paints tribal markings in dried blood on his skin
(`tools/paint_goblin_shaman.py`) over Tripo's base colour, into
`textures/goblin_shaman_body_basecolor.jpg`. The user asked for red tribal markings,
then for them to be more irregular and to look like dried blood. The build paints them
before it fits the mask, on his body as Tripo made it, so both variants come out with
the same texture (byte for byte). Run alone, it paints again from the body zip; on the
beak variant, whose face the mask leaves as it is, the texture comes out the same:

```sh
"$B" -b $S/goblin_shaman_beak_base.blend --factory-startup --python $S/tools/paint_goblin_shaman.py -- $T
```

- **Where:** each texel of the body's UV map gets the point of the T-posed body it
  shows, and the markings are drawn in metres round his limbs (from the rig's joints)
  and on his head. Only his skin is painted: texels of the body and the legs in the
  olive of his skin (hue 29–62°), not the leather, the cloth or the bone. 559,994
  texels are painted, 13.5% of his skin.
- **Markings:** on each arm, three finger marks raked down the shoulder, a band round
  the biceps with blood run from it toward the elbow, a row of diamonds between two
  rings below the elbow, and fingers stained past the knuckles. On each leg, two
  slashes across the outer thigh with a run from each, chevrons down the shin, and a
  ring above the ankle with runs toward the foot. On the head, four fingers dragged
  from the brow over the crown to the nape, a band round each ear and its tip dipped,
  and three stripes down the throat under the mask. The runs fall at random but fixed
  places (`DRIPS`) on the sides of his limbs that show.
- **Dried blood:** dark brown-red where it lies thick, in patches and along its rims,
  and thin and rusty elsewhere; cracked and chipped where it is thick. The lines
  wander, swell and thin, with ragged edges, breaks where the finger lifted, dry-brush
  gaps, thin smears and a spatter of small drops. The colour is multiplied by the
  skin's own shading. Each mark spreads 8 texels past its UV island's edge, so no green
  line shows along a seam.
- **Known limits:** from the game camera the markings read as dark marks on the skin;
  their cracks, chips and spatter show only close up.

## Rig

Each rig is built from its base scene by `tools/rig_goblin_shaman.py`, which follows
the goblin archer's rig, with the spearman's skirt flaps. `tools/render_rig.py` renders
review sheets and prints the grip and clearance measurements, including any body
triangles that cut through the staff or the mask. Both rigs have the same skeleton,
weights (but for the face round the mask), grips and standard pose.

```sh
"$B" -b $S/goblin_shaman_base.blend --factory-startup --python $S/tools/rig_goblin_shaman.py -- \
  <absolute path>/goblin_shaman_rig.blend
"$B" -b $S/goblin_shaman_beak_base.blend --factory-startup --python $S/tools/rig_goblin_shaman.py -- \
  <absolute path>/goblin_shaman_beak_rig.blend
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
  the head alone (skull mask: 199 vertices, 322 more blended into the neck; beak mask:
  478 and 136), so the mask keeps its gap however the neck bends. The eyes and tusks
  follow the head; the necklace, its fangs and the skull pendant are rigid on the
  chest; the belt's skull, pouches, bone and feathers are rigid on the hips.
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
  passes through either mask. The face stays 1.4 mm off the skull mask at the nearest
  and 1.3 mm off the beak mask.
- **Flaps:** `FlapFront1` swings forward with the leading thigh and `FlapBack1` back
  with the trailing one (drivers, 0.8 of the swing).
- **Standard pose:** the Action `stand`, active when the file opens. The left arm
  hangs as the rabble's. The right arm's angles and the hand's roll were searched for
  the staff held beside him nearest upright, its skull facing ahead and its foot as
  low as the grip allows. The staff also has to stay 2 cm clear of the body and the
  mask and, seen from the front, 22 cm out from his middle beside his head. The upper
  arm is 32° out and 10° forward, the elbow bent 50°, the wrist turned 20° toward the
  thumb and the hand rolled 60° about its length. The staff leans 3° (ahead), its
  skull faces 16° to his right, and its foot is 23 cm off the ground. It is 7.6 cm
  clear of the body, 20 cm of the skull mask and 19 cm of the beak mask. No body
  triangle other than the fist's passes through the staff in the standard pose or the
  T-pose.
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

## Clips (review)

`tools/retarget_clips.py` retargets the goblin's Mixamo idle, walk and death from
`projects/meridius/Animations/` onto either rig and saves a scratch copy with the clips
and a JSON report of every frame. The Mixamo motion is not saved in the rigs here, which
keep only `stand`. There is no attack: he will mostly cast spells (the user, 27 October
2026). `tools/render_clips.py` renders the copy's clips for the Workspace pose viewer,
and `goblin_spear/tools/pack_sheets.py` packs them. The idle, walk and death sheets
are made from the Mixamo clips, so they stay out of Git (`.gitignore`); render them
locally to see those clips in the viewer.

```sh
"$B" -b --factory-startup $S/goblin_shaman_rig.blend --python $S/tools/retarget_clips.py -- \
  projects/meridius/Animations <scratch>/skull_clips.blend <scratch>/skull_measure.json
"$B" -b --factory-startup <scratch>/skull_clips.blend --python $S/tools/render_clips.py -- \
  <out dir> skull stand,head,idle,walk
CLIP_W=1220 CLIP_H=1000 "$B" -b --factory-startup <scratch>/skull_clips.blend \
  --python $S/tools/render_clips.py -- <out dir> skull death
```

- **Retarget:** as the rabble's: rest-pose difference, bone by bone, the hips' motion
  scaled by the hip-height ratio (0.652). Only the Mixamo body bones are keyed; the
  fingers keep the grip Actions. Every clip keys the controls, `Staff` and `StaffHold`
  at rest and the right grip closed in its first frame, so switching clips leaves
  nothing behind.
- **idle:** 201 frames (6.67 s), in place, the last 10 frames eased into the first, so
  it loops.
- **walk:** 36 frames (1.17 s), a loop, in place; its speed is kept as the Action's
  `root_vel` (1.0 m/s). The hips follow the soles, so the lowest sole point keeps its
  rest height.
- **The concept's stance (idle and walk):** laid over the clip, as his concept art
  crouches (the user, 27 October 2026). The hips sink 6 cm with the feet kept where they
  are, the knees bending deeper and turned 15° outward: in the idle they bend 55° and
  64° instead of 24° and 36°, in the walk 50–92° instead of 17–76°. The back hunches
  18° further forward in the idle and 5° in the walk, shared by `Spine`, `Spine1` and
  `Spine2`. The clip's idle leans 3° back and its walk 6° forward, so the line from spine
  to neck now leans 9–10° forward in the idle and 10–13° in the walk; the user chose to
  keep this hunch (27 October 2026). The head turns 0.7 of the hunch back, so he still
  looks ahead. His left hand is held out in front of his hip, where the concept holds a
  bone fetish: `stand`'s arm with the elbow bent 71° instead of 37°, the wrist 20 cm out
  from the shoulder, 17 cm ahead of it and 33 cm below it. The idle keeps all its own
  left-arm motion about that, the walk 0.35 of its swing.
- **The carried staff (idle and walk):** his right arm keeps `stand` on the clip's
  chest, so he holds the staff upright in front of his right side with his fist at
  chest height, as his concept art does (`source/godot/art/raw/goblin_shaman/f_base.png`,
  `f_walk_a.png`). Its foot stays off the ground: the user chose that over lengthening
  the staff or lowering the hand. The chest's lean, the hunch included, would tip it up
  to 22° in the idle and 23° in the walk, so `StaffHold` (the hand's turn) takes back
  0.8 of the sway in every frame: it stays within 6° of its standard axis in the idle
  and 7° in the walk. The crouch lowers his chest, so the fist rises to keep the foot
  12 cm off the ground (the elbow bends and the arm turns at the shoulder): by up to
  14 cm in the idle and 18 cm where the walk's right footfall dips the chest. With the
  skull mask the foot stays 13 cm off the ground in the idle and 13–16 cm in the walk,
  and the staff at least 20 mm off the body and 10 mm off the mask. The beak mask's
  feathers would meet it in the walk, so its arm is turned 7° at the shoulder in every
  frame of both clips (`carry_arm`): the staff keeps 10 mm off the feathers and its
  foot 9–10 cm off the ground in the idle and 10–13 cm in the walk. No body triangle
  passes through it.
- **death:** 72 frames (2.37 s), easing in from the idle's first pose over 8 frames,
  crouched, with the left hand out and the fist raised. His neck and head keep the
  idle's turn 4 frames longer (`head_lag`), and until he lets go his shoulder keeps the
  idle arm's turn relative to his hips (`hold_turns`) and the wrist its turn: as his back
  straightens out of the hunch, the staff would otherwise tip back into his face. He
  lets go of the staff at frame 4 (the death Action's `staff_release`, which the export
  reads): the fist opens to 0.4, the wrist turns back to rest
  and the arm eases into the clip's over 6 frames. The staff topples as the spearman's
  spear does, about its foot, 45° to his right of ahead, and lies on the ground from
  frame 18, its shaft 4 cm up. It stays out of his body and at least 22 mm off the skull
  mask (54 mm off the beak mask) in every frame. The hips are raised or
  lowered so his lowest point (the open hand included) lies on the ground in every frame.
- **Export:** see [Godot export](#godot-export).

## Godot export

`tools/export_godot.py` bakes a scratch copy's clips into a GLB for the Godot sandbox,
with a JSON sidecar beside it; `tools/check_export.py` compares the GLB with the copy it
came from. Both variants export the same way: the script tells them apart by the mask's
material.

```sh
G=projects/meridius/source/godot/prototypes/goblin_shaman_anim/art3d
"$B" -b <scratch>/skull_clips.blend --python $S/tools/export_godot.py -- $G/goblin_shaman_skull.glb
"$B" -b <scratch>/beak_clips.blend --python $S/tools/export_godot.py -- $G/goblin_shaman_beak.glb
"$B" -b <scratch>/skull_clips.blend --python $S/tools/check_export.py -- source <samples.npz>
"$B" -b --factory-startup --python $S/tools/check_export.py -- glb $G/goblin_shaman_skull.glb <samples.npz>
```

An optional second argument sets the textures' size (1024 px by default, JPEG). Run
`tools/import.sh` in the Godot project after an export.

- **Bake:** the 52 deforming bones, `Staff` and `Mask`, sampled at every frame from the
  evaluated pose (the grips, the wrist's hold on the staff, the forearm twist) and keyed
  as linear Actions `idle`, `walk` and `death` (0.003 mm bake error at worst); the
  constraints, drivers and the rig's own Actions go. The staff is skinned whole to
  `Staff`, the mask plate to `Mask`. 15,168 triangles with the skull mask, 19,621 with
  the beak mask.
- **Check:** 0.01 mm at worst for both variants, in every sampled frame of the three
  clips, the frames round the staff's release included. Loaded in Godot 4.7.2, each GLB
  has 54 bones, the meshes `GoblinShaman`, `MaskPlate` and `Staff`, and the three
  animations at the sidecar's lengths; he faces +Z, the idle and the walk stay in place
  and the death's hips drift matches the sidecar. Godot names the staff's bone
  `Staff_2`, as its mesh node already has the name (the spearman's `Spear` does the
  same), so find the props by their meshes.
- **Sidecar:** fps, variant, his height in the idle's first frame with the mask (1.41 m
  with the skull, 1.51 m with the beak; 1.53 and 1.65 m in the T-pose), the staff's top
  (1.78 and 1.75 m), forward +Z, `roles` (no attack or hit clip) and per clip its length,
  loop flag and loop seam (2 mm, at the right fingertips). The idle and the walk give the
  staff foot's height (`staff_foot_m`). The walk has its `root_vel` (1.0 m/s forward) and
  its footfalls (left 0.3 s, right 0.9 s); the death its root motion, `hips_drift`,
  `staff_drop` (0.1 s), `staff_down` (0.57 s, flat on the ground) and when it settles
  (2.33 s).
- **Footfalls:** a step is the first frame in which the foot moves back with the ground,
  within 20% of the walk's speed, for at least 4 frames. The spearman's test, the ankle
  back at its lowest, finds the left step late: this crouched walk lands heel first with
  the ankle 12 cm up.
- **In Git:** the sidecars only. The GLBs carry Mixamo motion and stay local
  (`source/godot/.gitignore`), as the other goblins' do; export them to see him in Godot.
- **Not done:** he is not in the sandbox roster, and he has no cast clip.
