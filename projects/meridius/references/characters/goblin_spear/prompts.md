# Goblin Spearmen: T-pose and equipment prompts

Started 24 October 2026. Route: Higgsfield MCP, Nano Banana Pro (`nano_banana_pro`),
one job per stage, paid credits. Job IDs, inputs and hashes are in `jobs.json`
(gitignored). In Git, every image over 2 MB is a full-size WebP copy (quality 92) of the
local PNG original named below.

## Design notes

Design source: the middle goblin of `../Goblin spearmen.png`, cropped (420,250,870,740)
and enlarged 2x as `source_crop.png`. His costume is kept as drawn. The face follows the
user's note of 24 October 2026: every goblin gets the nose and face of the rabble goblins
(the right-hand panel of `review/goblins-v2/goblins_v2_set.jpg`), not the long hooked noses
of the painted sheets. The approved face is the one in
`../goblin_rabble/rabble_tpose_front.png`, which is also the anatomy, rendering and pose
reference, so the three goblin units read as one race.

Earlier designs checked: see `../goblin_rabble/prompts.md`.

## 1. T-pose

Inputs: image A `source_crop.png` (upload `82ce83a3-4f1f-4768-bb2f-0396631cc2f7`), image B
the rabble T-pose (job `77f1d02c-67c4-40ad-9a6f-6aa77c048d36`). 4K, 1:1.

```text
Use Image A as the character design and Image B for his face, body anatomy, pose and art style. Image A is a crop of a concept sheet of goblin spearmen: draw only the goblin in the middle, the one in the spiked steel helmet with the red plume. Image B is the finished T-pose reference of another goblin of the same horde. Redraw the spearman as a clean T-pose character reference for turning him into a 3D model and rigging him for animation in a fantasy tactics game, as a matching companion to Image B: the same front camera, the same size on the page, the same painterly illustration with crisp dark outlines and the same even, flat front lighting.

Face, exactly like Image B: a heavy, wrinkled brow ridge; small, narrow, deep-set pale-yellow eyes; a SHORT, broad nose with a heavy rounded tip that droops down a little toward the upper lip, the same nose as in Image B and the same olive green as his skin: not long, not hooked, not pointed; a wide, thin-lipped sullen mouth, closed, with two small lower fangs showing; deep lines from the nose to the corners of the mouth; long pointed ears sticking out sideways from under the helmet. The same olive-green skin as Image B. The helmet leaves the whole face clearly visible.

Body: a seasoned goblin warrior of the same race and height as Image B, but well fed and sturdier: lean, wiry muscle on the arms, shoulders and chest, no ribs showing. Realistic goblin proportions, the head about one fifth of his height, not chibi, not cute.

Pose, identical to Image B: standing perfectly straight, facing the camera directly from the front. Both arms stretched straight out to the sides at shoulder height, perfectly horizontal, elbows straight, palms facing down, fingers straight and together. Legs straight, feet shoulder-width apart, flat on the ground and pointing forward, with a clear gap of empty space between the legs. Head facing forward with the chin level.

His hands are empty: no spear and no other weapon. Keep his costume exactly as in Image A: the round steel helmet with a riveted brow band, a short pointed spike on top and cheek guards, with a crest of blood-red feathers rising at the back; a mantle of dark shaggy fur over both shoulders, set with a few curved bone horns and fangs; red war-paint marks on his upper arms; leather straps crossing his chest with a round leather boss; a wide leather belt with a square steel buckle; studded leather bracers on his forearms; a ragged skirt of blood-red rag strips over dark olive-black trousers; leather wraps round his shins and feet, with bare clawed toes showing at the front. A short ragged blood-red rag cape hangs down his back to the knees, only its edges visible behind him.

Keep the plume, the fur and the rags close to the body, so the arms, legs and torso are clearly separated and nothing overlaps. Full body visible from the tip of the plume to the soles of the feet, centered, with space around him on every side. Plain empty white background.
```

## 2. Spear

Input: image A `source_crop.png`. 2K, 9:16.

```text
Use Image A only for the design, materials and art style of one weapon. Image A is a crop of a concept sheet of goblin spearmen; draw only the spear held by the goblin in the spiked steel helmet in the middle. Draw this spear on its own, with no goblin and no hands: a long, straight shaft of dark brown wood with a few small knots; a broad, leaf-shaped steel spearhead with a raised ridge down its middle and a few small nicks along its edges, fixed to the top of the shaft by a riveted iron socket; a strip of blood-red rag knotted round the shaft just below the spearhead, its two short ends hanging down along the shaft; a band of dark leather wrapped round the shaft at the middle as a grip; a pointed iron butt cap at the bottom end.

Shown whole and perfectly straight, standing vertically down the middle of the image with the spearhead at the top and the butt cap at the bottom, filling most of the image height. Strict flat front view: the flat face of the spearhead faces the viewer directly, so its full leaf shape reads clearly; no perspective, no tilt, no three-quarter angle. Centered with white space around it; nothing touches the image edges.

The same painterly illustration with crisp dark outlines as Image A. Even, soft, flat lighting with very light shadows. Plain empty white background. One spear only: no second weapon, no stand, no text.
```

## 2b. Spear edit

The first spear (`spear_front.png`, job `892d33eb-2575-4f52-9395-1062bc0d7dad`) came back
with a narrow, small head. Inputs: image A that spear (job ID), image B `source_crop.png`.
2K, 9:16.

```text
Keep everything in Image A identical: the knotted wooden shaft, the blood-red rag knotted below the head, the dark leather grip band, the iron butt cap, the vertical position, the strict flat front view, the painterly style with crisp dark outlines, the flat lighting and the plain white background. Change only the spearhead: make it about twice as long and twice as broad, a broad leaf-shaped steel blade like the spearheads in Image B, widest about a third of the way up from its riveted iron socket and tapering to a sharp point, with a raised ridge down its middle and a few small nicks along its edges. The flat face of the blade faces the viewer directly. The whole spear stays inside the image with white space around it; nothing touches the image edges. One spear only, no text.
```

## Delivered (24 October 2026, awaiting the user's approval)

- `spear_tpose_front.png` (4096²): pass. Minor: the red war paint on the upper arms was
  left out.
- `spear_front_v2.png` (1536x2752): selected. `spear_front.png` is the first take, with
  too small a head.

## 3. T-pose without the helmet

The user, 24 October 2026, after seeing the first set: the barrel shield gets no symbol and no boss, only a barrel bottom; add a badly hammered-together plank shield; the spearman loses his helmet; no body paint on any goblin.

Inputs: image A `spear_tpose_front.png` (job `e17021da-ee11-44d9-957f-a70e681f54e8`), image B the rabble T-pose (job `77f1d02c-67c4-40ad-9a6f-6aa77c048d36`) for the bare head. 4K, 1:1.

```text
Keep everything in Image A identical: the goblin spearman's face, nose, eyes, mouth and fangs, his body, pose, proportions and hands; the dark fur mantle with the bone horns and fangs; the crossed leather straps with the round boss; the wide belt with the steel buckle; the studded bracers; the red rag skirt and the red rag cape behind him; the dark olive trousers; the leather shin wraps and bare clawed toes; the painterly style with crisp dark outlines, the flat front lighting, the framing and the plain white background. Change only his head: remove the steel helmet completely, together with its spike, its riveted band, its cheek guards and the red feather plume. Show his bare head instead, shaped like the goblin's head in Image B: a bald, rounded olive-green skull with a heavy, wrinkled brow ridge, and his long pointed ears now fully visible, sticking out sideways and a little upward. Keep his face exactly as it is in Image A. His skin is plain olive green everywhere, with no war paint, no tattoos and no markings.
```

Delivered: `spear_tpose_front_v2.png` replaces `spear_tpose_front.png`. It passes: bald,
with his ears free and no paint.

## Chosen for 3D (25 October 2026)

The user picked `spear_tpose_front_v2.png` and the first spear, `spear_front.png` (job
`892d33eb-2575-4f52-9395-1062bc0d7dad`), with its narrower head, over `spear_front_v2.png`.
These two go to Tripo.
