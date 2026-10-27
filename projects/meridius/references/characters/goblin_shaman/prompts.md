# Goblin Shamans: T-pose and equipment prompts

Started 26 October 2026. Route: the Higgsfield website with Unlimited on (the user's
preference of 24 October 2026; the MCP reported `unlim: {available: false}` for
`nano_banana_pro` that day), Nano Banana Pro, one job per stage. Job IDs, inputs and hashes
are in `jobs.json` (gitignored). In Git, every image over 2 MB is a full-size WebP copy
(quality 92) of the local PNG original named below. The user sees the images before any
Tripo mesh is made.

## Design notes

Design source: the antlered shaman, the first of the six figures in the game sprite's front
and back sheets (`source/godot/art/raw/goblin_shaman/f_base.png` and `b_base.png`), the
design the 2D game uses. Each is cropped (30,70,690,950), the two are set side by side,
front left and back right, and enlarged 2x (nearest) as `source_crop.png`.

His costume is kept as drawn: deer antlers on a leather brow band, a dark leather vest
with straps crossing at an iron ring on his back, a necklace of fangs with a small bone
skull, a belt with a bone skull buckle and a pouch, a blood-red rag loincloth over brown
leather flaps, leather wraps on his forearms, bare legs and bare feet. The horned skull
staff is drawn as its own piece of equipment, so it can be modelled and attached
separately.

The bone-and-feather charm that the sprite holds in his left hand hangs from his belt
instead. This keeps the left hand free for casting (Fireball, Bloodlust, Gutripper) and
saves a second hand-held prop. Proposed; it isn't canon until the user approves the image.

Rules from the earlier goblins: every goblin has the face of the rabble goblins, no body
paint on any goblin (the user's notes of 24 October 2026). The face, anatomy, rendering
and pose follow the approved bald spearman, `../goblin_spear/spear_tpose_front_v2.png`.

## 1. T-pose

Inputs: image A `source_crop.png`, image B `spear_tpose_front_v2.png` (a 2048 px copy).
1:1.

```text
Use Image A as the character design and Image B for his face, body anatomy, pose and art style. Image A shows the goblin shaman of a small pixel-art game sprite, from the front on the left and from the back on the right. Image B is the finished T-pose reference of another goblin of the same horde. Redraw the shaman as a clean T-pose character reference for turning him into a 3D model and rigging him for animation in a fantasy tactics game, as a matching companion to Image B: the same front camera, the same size on the page, the same painterly illustration with crisp dark outlines and the same even, flat front lighting. Do not copy the pixel-art style of Image A.

Face, exactly like Image B: a heavy, wrinkled brow ridge; small, narrow, deep-set pale-yellow eyes; a SHORT, broad nose with a heavy rounded tip that droops down a little toward the upper lip, the same nose as in Image B and the same olive green as his skin: not long, not hooked, not pointed; a wide, thin-lipped sullen mouth, closed, with two small lower fangs showing; deep lines from the nose to the corners of the mouth; long pointed ears sticking out sideways below his brow band. The same olive-green skin as Image B. A bald, rounded olive-green skull like Image B. He is older than the goblin in Image B: a few more wrinkles round the eyes and on the brow.

Body: a wiry old goblin shaman of the same race and height as Image B, lean and sinewy, not starving and no ribs showing. Realistic goblin proportions, the head about one fifth of his height, not chibi, not cute.

Pose, identical to Image B: standing perfectly straight, facing the camera directly from the front. Both arms stretched straight out to the sides at shoulder height, perfectly horizontal, elbows straight, palms facing down, fingers straight and together. Legs straight, feet shoulder-width apart, flat on the ground and pointing forward, with a clear gap of empty space between the legs. Head facing forward with the chin level.

His hands are empty: no staff, no charm, nothing held. Keep his costume as in Image A: a pair of pale, bone-white deer antlers, each with three or four tines, rising up and a little outward from the top of his head, fixed to a band of dark brown leather tied round his brow; a sleeveless vest of dark brown leather, open at the neck, with two leather straps that cross on his back at a round iron ring between the shoulder blades; a necklace of curved fangs and small bones with a small bone skull at the middle of his chest; a wide dark leather belt with a small bone skull as its buckle and a small leather pouch on his right hip; hanging from the belt on his left hip, a short bone with two white-and-grey feathers on a red thread; a blood-red rag loincloth hanging at the front, ragged at the hem, over a short skirt of dark brown leather flaps; leather wraps round both forearms; bare olive-green legs; bare feet with clawed toes. Plain olive-green skin everywhere, with no war paint, no tattoos and no markings. No cape, no shield.

Keep the antlers, the charm and the leather flaps close to the body, so the arms, legs and torso are clearly separated and nothing overlaps. Full body visible from the tips of the antlers to the soles of the feet, centered, with space around him on every side. Plain empty white background.
```

## 2. Staff

Input: image A `source_crop.png`. 9:16.

```text
Use Image A only for the design and materials of one weapon. Image A shows a goblin shaman of a small pixel-art game sprite, from the front and from the back; draw only the staff he holds in his right hand, redrawn as a detailed painterly illustration with crisp dark outlines, not as pixel art. Draw this staff on its own, with no goblin and no hands: a long, slightly crooked staff of dark brown gnarled wood with a few knots, made for a goblin about 1.4 metres tall and a little taller than him; on its top a bleached, bone-white horned animal skull without its lower jaw, its two dark curved horns sweeping out to the sides and up, bound to the top of the staff with dark leather thong; a strip of blood-red rag and a strip of faded ochre rag knotted round the staff just below the skull, their short ends hanging down; two small white-and-grey feathers hanging on a cord below the skull; a band of dark leather wrapped round the staff at the middle as a grip; the bottom end bare wood, blunt and worn.

Shown whole and perfectly straight, standing vertically down the middle of the image with the skull at the top and the foot at the bottom, filling most of the image height. Strict flat front view: the skull's face looks straight at the viewer, so both horns and both eye sockets read clearly; no perspective, no tilt, no three-quarter angle. Centered with white space around it; nothing touches the image edges.

A detailed painterly illustration with crisp dark outlines, like a 3D modelling reference sheet. Even, soft, flat lighting with very light shadows. Plain empty white background. One staff only: no second weapon, no stand, no text.
```

## 3. Leaner T-pose (edit)

The first T-pose (`shaman_tpose_front.png`) follows the costume, but his build is heavier
than the spearman's, with thick, muscular arms and legs, and his skin is a darker green.
An edit to bring him in line, made before the user had seen either. Inputs: image A
`shaman_tpose_front.png` (from the website's Generations picker), image B
`spear_tpose_front_v2.png` (the 2048 px upload). 1:1.

```text
Keep everything in Image A identical: the goblin shaman's face, the deer antlers on the leather brow band, the vest, the necklace of fangs with the small skull, the belt with the skull buckle, the pouch, the bone charm with the feathers, the red loincloth over the leather flaps, the forearm wraps, the strict front T-pose, the framing, the painterly style with crisp dark outlines, the flat front lighting and the plain white background. Change only his body and skin, to match the goblin in Image B: make him leaner and wirier, with thin, sinewy arms and legs, bony knees and elbows, narrower shoulders and a smaller frame, not muscular and not bulky, the same build and size as the goblin in Image B. His skin is the same yellowish olive green as in Image B. Give his bare toes short dark claws like Image B. No ribs showing, no war paint, no markings.
```

## 4. Skull masks

After seeing the first images, the user picked out two skull masks from the 2D sprites:
the horned skull of the fifth Horn-bearer (`source/godot/art/raw/goblin_horn/`) and the
bird skull of the fifth shaman. They asked for variants of both, and for the goblin head
without the antlers. A design sheet of six masks on the shaman's bald head: three versions
of each. Inputs: image A `mask_horn_source.png`, image B `mask_bird_source.png` (each the
fifth figure, front and back side by side, 2x nearest), image C `shaman_tpose_front_v2.png`
(from Generations). 3:2.

```text
Image A and Image B show two goblins of a small pixel-art game sprite, each from the front on the left and from the back on the right, each wearing a skull mask: Image A a horned skull, Image B a bird skull. Use them only for the design of the masks. Image C is the finished reference of our goblin shaman. Draw a design sheet of six skull masks for the shaman of Image C, to choose one for his 3D model in a fantasy tactics game: six head-and-shoulders portraits of the same goblin from Image C, three across and two down, each wearing a different mask, all in the same straight front view, at the same size, in the same painterly illustration with crisp dark outlines and even, flat front lighting as Image C. Do not copy the pixel-art style of Images A and B.

He wears no antlers and no brow band: the deer antlers of Image C are gone, and the mask sits directly on his bald head. Each mask is bleached, bone-white bone, worn like a helmet over the top of his head and the upper half of his face, tied on with dark leather thong. His long pointed ears stick out sideways beneath it, his small yellow eyes glint deep inside the dark eye sockets, and his own olive-green chin and wide, sullen mouth with two small lower fangs show below it, like Image C.

Top row, three versions of the horned skull mask of Image A, left to right:
1. The mask of Image A: a broad, cracked skull with two short, pointed horns on the brow, big round eye sockets, a small nose hole and a row of long upper fangs hanging over his mouth.
2. The same skull without its horns: a smooth, rounded, cracked brow, the same eye sockets and the same long upper fangs.
3. A heavier, older version: four short horns in a row across the brow, deep cracks, one broken fang, and a band of dark leather stitched round its edge.

Bottom row, three versions of the bird skull mask of Image B, left to right:
4. The mask of Image B: a long, slender, slightly curved beak pointing down over his nose, under a crest of brown-and-white feathers on a red band.
5. The same bird skull without the feather crest: bare bone, the long beak, bound on with leather thong.
6. A raptor skull with a short, heavy, hooked beak, and a few black feathers fanning out at the sides of his head.

He wears the same dark leather vest and necklace of fangs with a small bone skull as in Image C. No war paint and no markings. Plain empty white background, with clear white space between the portraits. No text, no numbers, no labels, no frames.
```

## 5. T-pose without antlers

The user chose mask 1 of the sheet (the Horn-bearer's horned skull) and asked for three
separate images: the mask from the front, the shaman without antlers and the staff. The
mask is a separate piece, so his head is bare: the antlers and the brow band go, and the
eyes follow the spearman's (v2's are pale and without pupils). Inputs: image A
`shaman_tpose_front_v2.png` (from Generations), image B `spear_tpose_v2_2048.png`. 1:1.

```text
Keep everything in Image A identical: the goblin shaman's face, body, build and skin, the leather vest, the necklace of fangs with the small bone skull, the belt with the skull buckle, the pouch, the bone charm with the feathers, the red loincloth over the leather flaps, the forearm wraps, the bare clawed feet, the strict front T-pose, his size and position on the page, the painterly style with crisp dark outlines, the flat front lighting and the plain white background. Change only his head: remove the deer antlers and the leather band round his brow completely, so the top of his head is a bare, bald, rounded olive-green skull like the goblin in Image B, with nothing on it. His long pointed ears stick out sideways as before. Give him the same small, narrow, deep-set yellow eyes with small dark pupils as the goblin in Image B. His hands stay empty.
```

## 6. Staff, strict front

The first staff turns its skull three-quarters and leans. Inputs: image A `staff_front.png`
(from Generations). 9:16.

```text
Keep the design of the staff in Image A identical: the bleached, bone-white horned animal skull without its lower jaw and its two dark curved horns, the dark leather thong binding it on, the strips of blood-red and faded ochre rag knotted below it, the two small white-and-grey feathers on a cord, the band of dark leather wrapped round the middle as a grip, the dark brown gnarled shaft with its knots, and the blunt, worn foot. Redraw it as a modelling reference in a strict flat front view: the skull faces the viewer straight on, symmetrical, with both eye sockets and both horns spread evenly to the left and the right, no three-quarter turn and no perspective. The whole staff stands perfectly upright, its shaft running straight down the vertical centre line of the image from the skull at the top to the foot at the bottom, with no lean and no tilt; only the small natural bends of the gnarled wood remain. It fills most of the image height, with white space all round, and nothing touches the image edges. The same painterly illustration with crisp dark outlines, even, soft, flat lighting with very light shadows, and a plain empty white background. One staff only: no goblin, no hands, no stand, no text.
```

## 7. Horned skull mask, front

Mask 1 of the sheet on its own. Inputs: image A `skull_masks_v1.png` (from Generations),
image B `mask_horn_source.png`. 1:1.

```text
Use Image A only for the design of one mask: the horned skull mask worn by the goblin at the top left of the sheet. Image B shows the same kind of mask on a goblin of a small pixel-art sprite, from the front and from the back; use it only to see how the mask covers the top and back of the head like a helmet. Do not copy its pixel-art style.

Draw this mask on its own, with no goblin and no head inside it, as a reference for modelling it in 3D and fitting it on a goblin's bald head: a bleached, bone-white skull without its lower jaw, broad and rounded, with fine cracks across the brow; two short, pointed, slightly curved horns rising from the top of the brow, one on each side; two big, round, dark, empty eye sockets; a small nose hole; and a row of long upper teeth with two long curved fangs at the corners, hanging down where the wearer's mouth would be. A short loop of thin dark leather thong passes through a small hole at each temple.

Strict flat front view: the mask faces the viewer straight on, perfectly symmetrical, with no three-quarter turn, no tilt and no perspective. Centred, filling most of the image, with white space all round; nothing touches the image edges. The same painterly illustration with crisp dark outlines as Image A, even, soft, flat lighting with very light shadows, and a plain empty white background. One mask only: no head, no goblin, no stand, no text.
```

## 8. T-pose without antlers, slimmer build

The user reviewed v3 and asked for one more edit with v2's slimmer build. Inputs: image A
`shaman_tpose_front_v3.png`, image B `shaman_tpose_front_v2.png` (both from Generations). 1:1.

```text
Keep everything in Image A identical: the goblin shaman's bare, bald, rounded head with no antlers and no brow band, his face, nose, tusks and small deep-set yellow eyes with dark pupils, his long pointed ears, the leather vest, the necklace of fangs with the small animal skull, the belt with the skull buckle, the pouch, the bone charm with the feathers, the red loincloth over the leather flaps, the forearm wraps, the bare clawed feet, the strict front T-pose, his size and position on the page, the painterly style with crisp dark outlines, the flat front lighting and the plain white background. Change only his build to match the goblin in Image B: a leaner, wirier body with narrower shoulders, a slimmer chest and waist, thinner upper arms and forearms, slimmer thighs and calves, and the same proportions of head, torso, arms and legs as in Image B. Take nothing else from Image B: no antlers, no brow band and no pale eyes. His hands stay empty.
```

Result `shaman_tpose_front_v4.png` (hf_20261026_150922_cb04e528): practically a copy of v3. The
silhouettes differ by under 0.1% and the arm and leg widths match to the pixel. The long list
of things to keep, with his size and position on the page, outweighed the one change.

## 9. T-pose without antlers, slimmer build (change first)

Section 8 again with the change leading, an explicit amount, and no lock on size and position.
Inputs: image A `shaman_tpose_front_v3.png`, image B `shaman_tpose_front_v2.png` (both from
Generations). 1:1.

```text
Make the goblin shaman in Image A noticeably thinner and wirier, with the lean build of the goblin in Image B. His shoulders are narrower, his chest and waist slimmer, and his upper arms, forearms, thighs and calves clearly thinner, about a quarter narrower than in Image A, with lean, stringy muscles instead of bulky ones. His head, hands and feet stay the same size. Everything else stays as in Image A: his bare, bald head with no antlers and no brow band, his face, his yellow eyes with dark pupils, his ears and tusks, all of his clothes and gear, the strict front T-pose with empty hands, the painterly style with crisp dark outlines, the flat front light and the plain white background. Take only the build from Image B: no antlers, no brow band and no pale eyes.
```

Result `shaman_tpose_front_v5.png` (hf_20261026_154151_d19b3e20): barely changed from v3. The
silhouette is 1% smaller, the upper arms 4% thinner, the waist unchanged.

## 10. v2 with a bald head (v2 alone)

The user chose to edit v2's head only, keeping its lean build: the antlers and brow band go, and
the yellow eyes are described in words instead of taken from a second reference. Inputs: image A
`shaman_tpose_front_v2.png` (from Generations) only. 1:1.

```text
Make an edited copy of Image A with one change, his head. Remove the deer antlers and the leather band round his brow completely, so the top of his head is a bare, bald, rounded olive-green skull with nothing on it. His long pointed ears stick out sideways as before. Give him small, narrow, deep-set yellow eyes with small dark pupils instead of the pale eyes. Everything else exactly as in Image A: his face, nose and tusks, his lean, wiry build, the leather vest, the necklace of fangs with the small skull, the belt with the skull buckle, the pouch, the bone charm with the feathers, the red loincloth over the leather flaps, the forearm wraps, the bare clawed feet, his empty hands, the strict front T-pose, his size and position on the page, the painterly style with crisp dark outlines, the flat front lighting and the plain white background.
```

Result `shaman_tpose_front_v6.png` (hf_20261026_162243_cfff25b4): the head is bald with yellow
eyes, and the body is v2's. Comparing the silhouettes below the chin showed that v2, v3 and v6
have the same body (they differ by under 0.5%), with the same arm angle and the same animal
skull on the necklace. The earlier review of v3 was wrong: v3 was never heavier than v2, so
sections 8 to 10 were not needed. v3 and v6 are interchangeable.

## 11. Bird skull mask with feather crest, front

The user chose the beak mask, no. 4 of the sheet (the bird skull from his original sprite
under a crest of feathers on a red band), for the rig, keeping the horned skull as an option.
Later they asked for one shaman in each mask, so both are rigged.
Inputs: image A `skull_masks_v1.png` (from Generations), image B `mask_bird_source.png`. 1:1.

```text
Use Image A only for the design of one mask: the bird skull mask with the feather crest worn by the goblin at the bottom left of the sheet. Image B shows the same mask on a goblin of a small pixel-art sprite, from the front and from the back; use it only to see how the crest of feathers stands up from the red band. Do not copy its pixel-art style.

Draw this mask on its own, with no goblin and no head inside it, as a reference for modelling it in 3D and fitting it on a goblin's bald head: the bleached, bone-white skull of a large bird without its lower jaw, its cranium rounded over the brow, with fine cracks; two big, round, dark, empty eye sockets, one on each side; and a long, slender, slightly curved beak of bone running straight down the middle from between the sockets, where the wearer's nose and mouth would be, with a small nostril slit on each side near its base. A band of faded blood-red cloth runs across the top of the skull above the eye sockets, and a fanned crest of long brown-and-white barred feathers stands up from behind the band, spread evenly to the left and the right.

Strict flat front view: the mask faces the viewer straight on, perfectly symmetrical, with the beak on the vertical centre line, no three-quarter turn, no tilt and no perspective. Centred, filling most of the image, with white space all round; nothing touches the image edges, not even the feather tips. The same painterly illustration with crisp dark outlines as Image A, even, soft, flat lighting with very light shadows, and a plain empty white background. One mask only: no head, no goblin, no stand, no text.
```

Result `mask_bird_front.png` (hf_20261026_203800_48748fd1): strict front and symmetric, as
asked. The red band and the crest are drawn on the skull; on the goblin the band is built round
his head in Blender.

## Delivered (26 October 2026)

Each image is a 2K PNG, fully opaque, with clear margins.

- `shaman_tpose_front_v2.png` (2048²), the leaner edit: proposed. Skin is the spearman's
  yellowish olive, with thinner arms and legs and dark claws on the toes; he's still a
  little more muscular than the spearman. His eyes are pale, almost white, without visible
  pupils. The pouch is on his left hip and the charm on his right, the other way round from
  the prompt.
- `shaman_tpose_front.png` (2048²), the first take: same costume, but a heavier build,
  darker green skin and toes without claws.
- `shaman_tpose_front_v3.png` (2048²), without antlers: **chosen by the user on 26 October
  2026 as the body for Tripo.** The antlers and brow
  band are gone and the head is bald; the eyes are yellow with dark pupils. Below the head
  it is v2: the same build, the same slight downward slope of the arms and the same animal
  skull on the necklace. (An earlier note here called the build heavier than v2; a
  silhouette comparison showed that was wrong.)
- `shaman_tpose_front_v6.png` (2048²), v2 with only the head edited: the same as v3 for
  modelling. `v4` and `v5` are failed slimming edits, kept for the record.
- `mask_horned_front.png` (2048²), mask 1 on its own: proposed. Strict front and
  symmetrical, with short horns, cracks, round dark sockets, a nose hole, long upper fangs
  and a thong loop at each temple. The horn tips nearly touch the top edge. Only the front
  is drawn.
- `staff_front_v2.png` (1536x2752), strict front: proposed. The skull faces straight out
  with both horns even, and the shaft stands upright, with only its gnarled bends.
- `skull_masks_v1.png` (2528x1696): six masks as asked, on a bald head without the
  antlers, with yellow eyes and dark pupils. The portraits are turned a little to the
  side rather than strict front, and the beaks point to his left. No. 2 lost the long
  upper fangs along with the horns. The necklace pendant became an animal skull.
- `staff_front.png` (1536x2752): proposed. Horned skull without its jaw, bound on with
  thong; red and ochre rags; two feathers on a cord; a leather grip; a gnarled shaft and a
  worn foot. The skull is in three-quarter view rather than flat front, and the shaft leans
  a few degrees.

## Tripo models (26 October 2026)

The user approved v3, the horned mask and staff v2 and asked for all three in Tripo. Smart
Mesh, Quad, P2.0, one variant each, then Texture 4K from each model's own input image (style
None, Remove Lighting off): 360 credits in all, as quoted. Receipts, task IDs and checksums are
in `jobs.json` under `tripo`; the textured FBX zips are in `../tripo/goblin_shaman/`.

- Body (polycount 5,000): 6,123 faces. Legs, belt items and feathers are separate pieces;
  three fingers and a thumb per hand; clawed feet. The texture follows v3, and the back of
  the vest, which was never drawn, came out with crossed straps.
- Mask (polycount 1,500, input padded to a 12% margin): 1,756 faces, watertight. Tripo built
  a whole skull shell, open underneath, with a strap band, rather than a face plate. The
  front is bone as drawn; the back of the shell is painted dark brown like leather. The user
  asked for a face plate cut just behind the horns, so
  `../blender/goblin_shaman/goblin_shaman_mask_plate.blend` keeps the front 33% of the shell
  with the face and both horns, without the strap, and caps the cut (see that folder's
  README). Fitting it round his ears is part of the base build.
- Staff (polycount 1,500): 1,614 faces. Skull, horns with bindings, rags, feathers, grip and
  foot are all there. The back of the skull came out darker and browner than its front.
