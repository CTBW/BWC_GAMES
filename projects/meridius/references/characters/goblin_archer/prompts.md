# Goblin Archers: T-pose and equipment prompts

Started 24 October 2026. Route: Higgsfield MCP, Nano Banana Pro (`nano_banana_pro`),
one job per stage, paid credits. Job IDs, inputs and hashes are in `jobs.json`
(gitignored). In Git, every image over 2 MB is a full-size WebP copy (quality 92) of the
local PNG original named below.

## Design notes

Design source: the front goblin of `../Goblin archers.png`, cropped (420,140,800,600) and
enlarged 2x as `source_crop.png`. His costume is kept as drawn; the quiver comes off his
back and is drawn as its own piece of equipment, so it can be modelled and attached
separately. The face follows the user's note of 24 October 2026: every goblin gets the nose
and face of the rabble goblins (the right-hand panel of
`review/goblins-v2/goblins_v2_set.jpg`). The approved face is the one in
`../goblin_rabble/rabble_tpose_front.png`, which is also the anatomy, rendering and pose
reference.

Earlier designs checked: see `../goblin_rabble/prompts.md`.

## 1. T-pose

Inputs: image A `source_crop.png` (upload `02a9a960-5666-4959-9f5c-ca593bf3d601`), image B
the rabble T-pose (job `77f1d02c-67c4-40ad-9a6f-6aa77c048d36`). 4K, 1:1.

```text
Use Image A as the character design and Image B for his face, body anatomy, pose and art style. Image A is a crop of a concept sheet of goblin archers: draw only the hooded goblin in front who is drawing the bow. Image B is the finished T-pose reference of another goblin of the same horde. Redraw the archer as a clean T-pose character reference for turning him into a 3D model and rigging him for animation in a fantasy tactics game, as a matching companion to Image B: the same front camera, the same size on the page, the same painterly illustration with crisp dark outlines and the same even, flat front lighting.

Face, exactly like Image B: a heavy, wrinkled brow ridge; small, narrow, deep-set pale-yellow eyes; a SHORT, broad nose with a heavy rounded tip that droops down a little toward the upper lip, the same nose as in Image B and the same olive green as his skin: not long, not hooked, not pointed; a wide, thin-lipped sullen mouth, closed, with two small lower fangs showing; deep lines from the nose to the corners of the mouth; long pointed ears sticking out sideways through slits in the sides of his hood. The same olive-green skin as Image B. The hood is pulled up over his head but sits back far enough that his whole face is clearly visible and evenly lit, not in shadow.

Body: a lean, wiry goblin hunter of the same race and height as Image B, not starving: sinewy, well-defined arms and shoulders from drawing the bow, no ribs showing. Realistic goblin proportions, the head about one fifth of his height, not chibi, not cute.

Pose, identical to Image B: standing perfectly straight, facing the camera directly from the front. Both arms stretched straight out to the sides at shoulder height, perfectly horizontal, elbows straight, palms facing down, fingers straight and together. Legs straight, feet shoulder-width apart, flat on the ground and pointing forward, with a clear gap of empty space between the legs. Head facing forward with the chin level.

His hands are empty: no bow, no arrow. Nothing on his back: no quiver and no quiver strap. Keep the rest of his costume exactly as in Image A: the pointed black cloth hood with a blood-red war-paint stripe down its front; red war-paint stripes on his upper arms; a necklace of small fangs; leather bracers laced with straps on both forearms; a leather belt with a small bone skull as its buckle and a small leather pouch on the hip; a layered skirt of ragged black cloth and blood-red rag strips hung with a few small fangs; dark olive-black trousers; brown leather boots bound with straps. A short ragged blood-red rag cape hangs down his back to the knees, only its edges visible behind him.

Keep the hood, the rags and the cape close to the body, so the arms, legs and torso are clearly separated and nothing overlaps. Full body visible from the tip of the hood to the soles of the feet, centered, with space around him on every side. Plain empty white background.
```

## 2. Bow

Input: image A `source_crop.png`. 2K, 9:16.

```text
Use Image A only for the design, materials and art style of one weapon. Image A is a crop of a concept sheet of goblin archers; draw only the bow held by the hooded goblin in front. Draw this bow on its own, with no goblin, no hands and no arrow: a strung recurve bow of dark brown wood, its two limbs curving smoothly away from the string and their tips curling back the other way; a grip in the middle wrapped in dark leather; a short, sharp steel spike fixed to the back of the bow just above the grip, pointing away from the string; a few strips of blood-red rag and leather cord tied round the limbs just above and below the grip, their ends hanging short; a thin, taut, straight bowstring joining the two tips.

Shown whole and upright down the middle of the image, one tip at the top and one at the bottom, filling most of the image height. Strict side view in the plane of the bow, so the full curve of both limbs and the straight string read clearly: the string on the right side, the back of the bow and the spike on the left; no perspective, no tilt, no three-quarter angle. Centered with white space around it; nothing touches the image edges.

The same painterly illustration with crisp dark outlines as Image A. Even, soft, flat lighting with very light shadows. Plain empty white background. One bow only: no arrow, no second weapon, no stand, no text.
```

## 3. Quiver

Input: image A `source_crop.png`. 2K, 3:4.

```text
Use Image A only for the design, materials and art style of one object. Image A is a crop of a concept sheet of goblin archers; draw only the quiver on the back of the hooded goblin in front. Draw this quiver on its own, with no goblin and no strap across a body: a tall, slightly tapering cylinder of dark brown leather with a stiff, rolled rim at the top and a closed, rounded bottom; two bands of darker leather round it, one near the top and one near the bottom, each with a small iron buckle; a few stitched seams; one blood-red rag knotted round its top band. It is full of arrows: about eight straight wooden shafts standing out of the top, each ending in three blood-red feather fletchings, slightly fanned out.

Shown whole and upright down the middle of the image, the opening and the red fletchings at the top, filling most of the image height. Strict flat front view: no perspective, no tilt, no three-quarter angle, the cylinder seen straight from the side. Centered with white space around it; nothing touches the image edges.

The same painterly illustration with crisp dark outlines as Image A. Even, soft, flat lighting with very light shadows. Plain empty white background. One quiver only: no bow, no loose arrows, no stand, no text.
```

## 4. Arrow

Input: image A `source_crop.png`. 2K, 9:16.

```text
Use Image A only for the design, materials and art style of one object. Image A is a crop of a concept sheet of goblin archers; draw only one of the arrows from the goblin's quiver. Draw this arrow on its own, with no goblin, no hands and no bow: a long, straight, thin wooden shaft; a small, sharp, barbed steel arrowhead fixed to the top; three blood-red feather fletchings near the bottom end, cut in a ragged shape; a notched nock at the very bottom, bound with a few turns of dark thread.

Shown whole and perfectly straight, standing vertically down the middle of the image with the arrowhead at the top and the nock at the bottom, filling most of the image height. Strict flat side view: the flat face of the arrowhead faces the viewer directly, so its barbed shape reads clearly; no perspective, no tilt, no three-quarter angle. Centered with white space around it; nothing touches the image edges.

The same painterly illustration with crisp dark outlines as Image A. Even, soft, flat lighting with very light shadows. Plain empty white background. One arrow only: no bow, no quiver, no second arrow, no stand, no text.
```

## Delivered (24 October 2026, awaiting the user's approval)

- `archer_tpose_front.png` (4096²): pass. Minor: a diagonal chest strap with a buckle
  came back (usable as the quiver strap).
- `bow_side.png`, `arrow_side.png` (1536x2752) and `quiver_front.png` (1792x2400): pass.

## 5. T-pose without body paint

The user, 24 October 2026, after seeing the first set: the barrel shield gets no symbol and no boss, only a barrel bottom; add a badly hammered-together plank shield; the spearman loses his helmet; no body paint on any goblin. The red stripe on the hood is on the cloth, not the skin, and is kept.

Input: image A `archer_tpose_front.png` (job `ec44dd90-6c93-4651-84a5-c9395c17684a`). 4K, 1:1.

```text
Keep everything in Image A identical: the goblin archer's face, nose, eyes, mouth and fangs, ears, body, pose, proportions and hands; the black hood exactly as it is; the fang necklace; the diagonal chest strap with its buckle; the laced leather bracers; the rope belt with the skull and the pouch; the red and black rag skirt; the dark trousers; the brown strapped boots; the red rag cape behind him; the painterly style with crisp dark outlines, the flat front lighting, the framing and the plain white background. Change only one thing: remove all the red war paint from his skin. Remove the red stripes on his upper arms and shoulders and any red marks on his face or chest. Paint those areas as plain olive-green goblin skin with the same shading and muscle detail as the rest of his body. No paint, no tattoos, no markings anywhere on his skin.
```

Delivered: `archer_tpose_front_v2.png` replaces `archer_tpose_front.png`. It passes: no
skin paint, and the stripe on the hood is kept.
