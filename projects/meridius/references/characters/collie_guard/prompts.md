# Border Collie Royal Guard: T-pose, tail and equipment prompts

Started 26 October 2026, at the user's request to start the 3D pipeline on the Collie Royal
Guard: the tail works as the succubus's does, and the clips are the footmen's. Route: the
Higgsfield website with Unlimited on (`context/preferences.md`; the MCP reported
`unlim: {available: false}` for `nano_banana_pro` the same day), Nano Banana Pro, 2K (the
largest size Unlimited covers; 4K costs credits), one job at a time. Job IDs, inputs and hashes are in `jobs.json` (gitignored). The user sees the
images before any Tripo mesh is made.

## Design notes

Design authority: the user's painting `../Collie Royal Guard.png` (five guards on a grass
tile). The in-game sprite (`source/godot/art/raw/collie_guard/f_base.png`, `b_base.png`)
shows the costume's back and the tail. Inputs:

- `painting_crop.png`: the painting's front guard and the guard on the left (whose tail
  shows), each cropped and enlarged 2x, side by side (2200 x 1160).
- `sprite_crop.png`: the fifth sprite figure (the black tricolour, closest to the painting),
  front left and back right (`(680,1190,1370,2010)` of each sheet).
- `footman_tpose_2048.png`: the approved footman T-pose (`../footman_idle/`), for the pose,
  the framing and the rendering, so the guard matches the footman it shares its clips with.

What is kept from the painting: a tall, broad-chested border collie knight; a black
tricolour coat (black, a white blaze and muzzle, a big white ruff, tan brows and cheeks,
amber eyes, semi-erect ears that tip over); blackened plate with polished gold trim; a gold
eagle on the breastplate; layered, gold-rimmed pauldrons; brown leather belts with iron
buckles; black tabard panels to the knees with gold borders and gold fleurs-de-lis at the
hem; round knee cops with gold rims; greaves; dark gauntlets; long white fur feathering at
the backs of the thighs; big white paws with dark claws; a black heater shield with a gold
rim and a gold eagle; a straight steel longsword with a gold cross-guard.

Decisions for the 3D model (proposed until the user approves the images):

- **Legs.** Human-length, plantigrade legs ending in big collie paws, as the succubus has,
  not the painting's crouched dog legs: the footmen's Mixamo clips (`footman_3d`'s
  `retarget_clips.py`) need a humanoid leg. The paws stand flat; the greaves end above them.
- **Tail.** The succubus route (`source/godot/art/succubus_3d/README.md`): the tail is its
  own Tripo model, from its own side-view image with a round root stump, mounted on the
  lower back in Blender on a chain of bones (`Tail_1`..`Tail_6`), moved by
  `secondary_motion.py`-style sway, drag and a ground pass. So: the T-pose is drawn with
  the tail (for the design), the tail alone is drawn from it, and the body is edited
  without it for Tripo.
- **Hands empty** in the T-pose; sword and shield are separate models, as the footman's.
- **Coat.** One base model in the painting's black tricolour. The sprite's other coats
  (red, blue merle, black-and-white) can be texture variants later, like the footman squad
  looks.
- No helmet (the ears stay free, as in the painting), no cape, no scabbard.

## 1. T-pose

Inputs: image A `painting_crop.png`, image B `sprite_crop.png`, image C
`footman_tpose_2048.png`. 3:4, 2K.

```text
Use Image A as the character design: an elite royal guard who is an anthropomorphic border collie knight in black-and-gold plate armour. Image B shows the same guard as a small pixel-art game sprite, from the front on the left and from the back on the right; use it only to see the back of his armour and his tail. Image C is the finished T-pose reference of a human footman of the same army; use it for the pose, the framing, the size on the page and the clean illustration style with crisp dark outlines, cel shading and flat front lighting. Do not copy the pixel-art style of Image B, and do not copy any grass, stones or ground from Image A.

Redraw the border collie guard of Image A as a clean T-pose character reference for turning him into a 3D model and rigging him for animation in a fantasy tactics game. He is tall, broad-chested and powerful, a noble veteran of the royal household: heroic proportions, broad shoulders, a deep chest, a narrow waist and long strong legs.

Pose, identical to Image C: standing perfectly straight, facing the camera directly from the front. Both arms stretched straight out to the sides at shoulder height, perfectly horizontal, elbows straight, palms facing down, fingers straight and together. Legs straight, feet shoulder-width apart, flat on the ground and pointing forward, with a clear gap of empty space between the legs. Head facing forward with the chin level. His expression is calm, proud and watchful, the steady gaze of a loyal guardian.

Head, exactly like Image A: a border collie's head with a medium muzzle and a black nose; a black tricolour coat with a clean white blaze running up the middle of the forehead and down over a white muzzle, small tan markings above the eyes and on the cheeks, and warm amber eyes; two semi-erect ears that stand up and tip over forward at the top, black with feathered fur; thick, slightly shaggy black fur on the head and down the back of the neck; a big, fluffy white ruff of fur on his throat and chest that spills over the top of his breastplate.

Armour, exactly like Image A: blackened steel plate armour with polished gold trim and small gold rivets on every edge. A black breastplate with a golden eagle with spread wings on the chest. Large, layered, rounded black pauldrons with gold rims on both shoulders. Black articulated arm plates and vambraces with gold edges, and black leather gauntlets with five fingers. A wide brown leather belt with an iron buckle at the waist and a second, narrower brown leather belt slung lower across the hips. Black tabard panels hanging from the belt at the front and the back to just above the knees, bordered in gold, with small gold fleurs-de-lis along the hem. Black thigh plates, round black knee cops with gold rims, and black greaves with gold edges down the shins. Long, soft white fur feathering shows at the backs and sides of his thighs below the tabard. His feet are big white border collie paws with dark claws, flat on the ground, the greaves ending just above them.

Tail: his long, bushy border collie tail, black on top with a white underside and a big white tip, hangs down behind him and sweeps out to his left side at knee height, with clear empty space between the tail and his leg.

His hands are empty: no sword, no shield, nothing held. No helmet, no cape, no scabbard. Keep the tabard panels, the fur and the tail close to the body and clear of the limbs, so the arms, legs, torso and tail are clearly separated and nothing overlaps. Full body visible from the tips of his ears to the claws of his paws, centered, with space around him on every side. Even, soft, flat front lighting with very light shadows. Plain empty white background.
```

## 2. Sword

Input: image A `painting_crop.png`. 9:16, 2K.

```text
Use Image A only for the design and materials of one weapon: the longsword held by the border collie guards. Draw only this sword on its own, with no hands, no dog and no ground, redrawn as a detailed illustration with crisp dark outlines and cel shading, as a reference for modelling it in 3D: a straight, double-edged steel longsword with a bright, polished blade, a narrow central fuller running most of its length, and a sharp point; a straight gold cross-guard with slightly flared ends; a grip wrapped in dark brown leather, long enough for one gauntleted hand with room to spare; and a round gold pommel.

Shown whole and perfectly straight, standing vertically down the middle of the image with the point at the top and the pommel at the bottom, filling most of the image height. Strict flat front view of the blade's flat side: no perspective, no tilt, no three-quarter angle, the cross-guard spreading evenly to the left and the right. Centered with white space around it; nothing touches the image edges. Even, soft, flat lighting with very light shadows. Plain empty white background. One sword only: no scabbard, no stand, no text.
```

## 3. Shield

Inputs: image A `painting_crop.png`, image B `sprite_crop.png`. 3:4, 2K. Made a little bulkier
than the painting's at the user's request (26 October), like the guard (section 7).

```text
Use Image A only for the design and materials of one shield: the shield carried by the border collie guards. Image B shows the same shield on a small pixel-art game sprite; do not copy its pixel-art style. Draw only this shield on its own, with no arm, no dog and no ground, redrawn as a detailed illustration with crisp dark outlines and cel shading, as a reference for modelling it in 3D: a large, heavy, sturdy black heater shield, tall and broad, thick and gently curved, with a straight top edge, slightly rounded upper corners and sides that curve down to a point at the bottom, big enough to cover a big guard from shoulder to knee; a thick, raised, polished gold rim all round its edge with heavy gold rivets; on its black face a large golden eagle with its wings spread wide and raised, its head turned to one side, its tail feathers fanning down, exactly as in Image A.

Strict flat front view: the shield faces the viewer straight on, upright and symmetrical in outline, with no three-quarter turn, no tilt and no perspective. Centered, filling most of the image, with white space all round; nothing touches the image edges. Even, soft, flat lighting with very light shadows. Plain empty white background. One shield only: no sword, no stand, no text.
```

## 4. T-pose fix

The first T-pose (`collie_tpose_front_v1.png`) has the design right but stands in an A-pose
with brown leather gloves. The rig measures its joints from a level T-pose silhouette, so the
arms are raised in an edit. Inputs: image A `collie_tpose_front_v1.png` (from the Higgsfield
generations), image B `footman_tpose_2048.png`. 3:4, 2K.

```text
Image A is a character reference of a border collie royal guard in black-and-gold plate armour. Image B is the finished T-pose reference of a human footman of the same army; use it only for the pose of the arms. Edit Image A into a strict T-pose. Make only these two changes.
1. Arms: both arms stretched straight out to the sides at shoulder height, perfectly horizontal exactly as in Image B, in one straight level line from the shoulder to the fingertips, elbows straight, palms facing down, fingers straight and together with the thumb alongside. The pauldrons stay on his shoulders and the arm plates and vambraces stay on his arms, with white space above and below each arm.
2. Hands: the brown leather gloves become black steel plate gauntlets with articulated black finger plates and gold-edged cuffs.
Keep everything else in Image A exactly the same: the head, face, calm proud expression, ears and coat markings, the white ruff, the breastplate and golden eagle, the pauldrons, the belts, the tabard and its fleurs-de-lis, the knee cops, greaves and white paws, the tail with its white tip and where it hangs, the proportions, the crisp dark outlines, colors, cel shading and the plain empty white background. The whole figure fits in the image with space on every side, scaled down a little if the arms need the room.
```

## 5. Tail

The succubus route: the tail alone, seen from the side, with a round root stump to mount on
the lower back. Input: image A, the approved T-pose `collie_tpose_front_v5.png` (section 11). 3:4, 2K.

```text
Use Image A only for the design, colors and art style of this character's tail. Draw his tail on its own, with no dog, no person and no armour: a long, bushy border collie tail of thick, soft, feathered fur in layered clumps, glossy black on top and along the sides, with long white feathering underneath and a big, bright white tip, exactly as in Image A. At its base it ends in a clean, round stump where it attaches to his lower back.
Seen from the side, it hangs down from the base at the top of the image in a gentle S-curve, fullest in the middle, with the white tip curling slightly upward at the bottom. Shown whole and centered with space around it; nothing touches the image edges. Same crisp dark outlines and cel shading as Image A. Even, soft, flat lighting with very light shadows. Plain empty white background.
```

## 6. Body without the tail

For the body's Tripo model. Input: image A, the approved T-pose `collie_tpose_front_v5.png` (section 11). 3:4, 2K.

```text
Edit Image A, a T-pose character reference for a 3D game model. Make only this one change: remove the tail completely. He has no tail at all, and plain white background shows beside and between his legs where the tail was.
Keep everything else in Image A exactly the same: the T-pose, the head, face, expression, ears and coat markings, the white ruff, all of the armour, the gauntlets, belts, tabard, knee cops, greaves and white paws, the proportions, size and position, the crisp dark outlines, colors, cel shading and the plain empty white background.
```

## 7. Bulkier T-pose

The user asked for the guards a little bulkier (26 October). The T-pose fix (section 4,
`collie_tpose_front_v2.png`) gave him black gauntlets but left the arms in the A-pose, so this
redraws him rather than editing: image A `collie_tpose_front_v2.png` (from the Higgsfield
generations) for the design, image B `footman_tpose_2048.png` for the pose. 3:4, 2K.

```text
Use Image A as the exact character design: a border collie royal guard in black-and-gold plate armour. Image B is the finished T-pose reference of a human footman of the same army; use it for the pose, the framing and the size on the page. Redraw the guard of Image A as a clean T-pose character reference for turning him into a 3D model and rigging him for animation in a fantasy tactics game.

Pose, identical to Image B: standing perfectly straight, facing the camera directly from the front. Both arms stretched straight out to the sides at shoulder height, perfectly horizontal, in one straight level line from the shoulder to the fingertips, elbows straight, palms facing down, fingers straight and together. The arms do not slope down at all: his hands are at the same height as his shoulders. Legs straight, feet shoulder-width apart, flat on the ground and pointing forward, with a clear gap of empty space between the legs. Head facing forward with the chin level.

Build: make him a little bulkier than in Image A, a heavier and more powerful guard: broader shoulders, a deeper and wider chest, thicker upper arms and forearms, thicker thighs and calves and a sturdier neck, his black plate armour a little thicker and heavier to match and his pauldrons a little larger. Still a tall, heroic figure with a narrower waist, not fat.

Keep everything else identical to Image A: the head, face, calm proud expression, ears and coat markings, the white ruff, the breastplate and golden eagle, the gold trim and rivets, the layered pauldrons, the arm plates, the black steel gauntlets with gold-edged cuffs, the two brown belts, the tabard and its fleur-de-lis panel, the knee cops, greaves and big white paws with dark claws, and the bushy black tail with its white tip hanging behind him to one side, clear of his leg. His hands are empty. Crisp dark outlines, cel shading, even soft flat front lighting with very light shadows. Full body visible from the tips of his ears to the claws of his paws, centered, with space on every side. Plain empty white background.
```

## 8. Bulkier sword

The user asked for a bulkier shield and guard; the sword follows them. Input: image A
`collie_sword_v1.png` (from the Higgsfield generations). 9:16, 2K.

```text
Edit Image A, the reference of one longsword for 3D modelling. Make the sword a little bulkier and heavier, keeping its length: a broader and thicker blade, a wider and thicker gold cross-guard with heavier flared ends, a slightly thicker grip, and a larger round gold pommel. Keep everything else in Image A exactly the same: straight and vertical down the middle, point at the top and pommel at the bottom, a strict flat front view of the blade's flat side, the polished steel with its central fuller, the dark brown leather grip, the crisp dark outlines, cel shading, even flat lighting and the plain empty white background.
```

Not run: `source/godot/art/collie_guard_3d/tools/bulk_sword.py` made the sword heavier
locally instead (`collie_sword_v2.png`, see section 11).

## 9. Guard on the footman's T-pose

Sections 4 and 7 came back in the same A-pose, and section 7 no bulkier
(`collie_tpose_front_v3.png`): with the guard's own picture as the base, the model copies it.
Here the footman's T-pose is the picture being edited, so its pose stays, and the guard
replaces the footman. Inputs: image A `footman_tpose_2048.png`, image B
`collie_tpose_front_v2.png` (from the Higgsfield generations). 3:4, 2K.

```text
Edit Image A, the finished T-pose reference of a human footman for a 3D game model. Replace the footman with the border collie royal guard of Image B, keeping exactly the pose of Image A: standing perfectly straight and facing the front, both arms stretched straight out to the sides at shoulder height, perfectly horizontal, elbows straight, palms facing down, fingers straight and together; legs straight and apart with empty space between them, feet flat on the ground.

The guard is bigger and bulkier than the footman: a tall, heavy, powerful knight with broad shoulders, a deep and wide chest, thick muscular arms and thick strong legs, his plate armour thick and heavy, with large layered pauldrons. Draw him exactly as in Image B: the border collie head with its black tricolour coat, white blaze and muzzle, tan brows and cheeks, amber eyes and semi-erect ears that tip over; the big white ruff over his breastplate; the black plate armour with gold trim and rivets and the golden eagle on the chest; the black arm plates and black steel gauntlets with gold-edged cuffs; the two brown leather belts; the black tabard with its gold-bordered fleur-de-lis panel; the knee cops and greaves; the big white paws with dark claws; and his bushy black tail with its white tip hanging behind him to one side, clear of his leg. His hands are empty.

Nothing of the footman remains: no human face or hair, no blue tunic, no brown boots. Same crisp dark outlines, cel shading and flat front lighting as Image B. Full body visible from the tips of his ears to the claws of his paws, centered, with space on every side. Plain empty white background.
```

## 10. Clean-up of the raised-arm paste-up

The fallback for the pose: `source/godot/art/collie_guard_3d/tools/raise_arms.py` cuts the
arms of `collie_tpose_front_v2.png` off at the armpits and raises them 42 degrees to level
(`collie_tpose_pasteup.png`, 1800 x 2400); this edit repaints the joins and adds the bulk the
user asked for. Input: image A `collie_tpose_pasteup.png`. 3:4, 2K.

```text
Image A is a rough paste-up of a T-pose character reference for a 3D game model: his arms were cut out and raised to shoulder height, so the joins at the shoulders and armpits are rough. Redraw it as a clean, finished T-pose character reference, keeping the pose of Image A exactly: both arms stretched straight out to the sides, perfectly horizontal at shoulder height, elbows straight, palms facing down. Fix the shoulders: the large, layered, gold-rimmed pauldrons sit naturally over the tops of the raised arms, the arm plates continue smoothly out of them, and the undersides of the arms join the body cleanly at the armpits, with no white notches or cut edges. His fingers are straight and together.

Make him bulkier, a heavier and more powerful royal guard: broader shoulders, a wider and deeper chest, thicker upper arms and forearms, thicker thighs and calves and a sturdier neck, with his plate armour thicker and heavier to match and his pauldrons larger. He stays a tall, heroic figure with a narrower waist, not fat.

Keep everything else as in Image A: the border collie head, face, calm proud expression, ears and coat markings, the white ruff, the black plate armour with gold trim and rivets, the golden eagle on the chest, the black steel gauntlets with gold-edged cuffs, the two brown belts, the tabard and its fleur-de-lis panel, the knee cops, greaves and big white paws with dark claws, the bushy black tail with its white tip, the crisp dark outlines, colors, cel shading and flat front lighting. Full body visible from the tips of his ears to the claws of his paws, centered, with space on every side. Plain empty white background.
```

Result: `collie_tpose_front_v4.png`, a clean T-pose, but no bulkier. An edit keeps the
silhouette it is given.

## 11. Bulk-up (local, no generation)

`source/godot/art/collie_guard_3d/tools/bulk_up.py collie_tpose_front_v4.png
collie_tpose_front_v5.png 1.12` widens everything below the neck within the pauldrons by
12 %, moves the arms out with it and makes them 12 % thicker, and leaves the head alone. The
warp came out clean, so `collie_tpose_front_v5.png` is the approved T-pose: the input for
sections 5 and 6. Section 6 gave `collie_tpose_notail_v1.png`, the body's Tripo input.

The sword the same way: `bulk_sword.py collie_sword_v1.png collie_sword_v2.png` makes the
blade 1.3 times as broad, the cross-guard 1.2 times as wide and 1.3 times as thick, the
grip 1.2 times as thick and the pommel 1.3 times as big, keeping the sword's length.

## 12. To 3D

On 26 October, after the user approved the Tripo spend, Tripo Studio made four Smart Mesh models in quads
from `collie_tpose_notail_v1.png` (body), `collie_tail_v1.png`, `collie_sword_v2.png` and
`collie_shield_v1.png`, each textured from its own input: 480 credits, approved by the user
(task IDs and hashes in `jobs.json`; the exports in `../tripo/collie_guard/`). The model,
rig, clips and Godot export are in `source/godot/art/collie_guard_3d/README.md`.
