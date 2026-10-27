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

## 6. Tripo meshes

The user, 25 October 2026: "I think we already have the archer images, check for them and do
the meshes in Tripo. Use the same workflow as for the Goblin Rabble." Then: "We need to redo
the bow though, it looks bad and I don't like it." The body, quiver and arrow went to Tripo
first; the bow followed once the user had approved the simplified horn bow (section 7.5) and
answered "Yes" to its mesh, texture and export.

Route as for the rabble: Tripo Studio web, Smart Mesh, Quad, AI model P2.0, one variant each,
one 2048 px RGB copy of each approved image. Task IDs, credits and hashes are in `jobs.json`.

| Model | Image | Polycount set | Faces / vertices |
|---|---|---|---|
| `body` | `archer_tpose_front_v2.png` | 5,000 | 5,720 / 5,532 |
| `quiver` | `quiver_front.png` | 1,500 | 1,767 / 1,582 |
| `arrow` | `arrow_side.png` | 500 | 624 / 556 |
| `bow` | `bow_horn_simple_side.png` | 1,000 | 1,311 / 1,085 |

Cost: 3 × 100 credits (balance 800 → 500). Textured after the user's "Texturize before
downloading": the left-sidebar Texture panel with each model's own image as reference, style
None, Remove Lighting off, 4K, 3 × 20 credits (balance 500 → 440). The bow later took 100 for
its mesh and 20 for its texture, with the same settings, making 480 credits for the archer in
all. The account stood at 120 afterwards because session 8a's spearman runs (2 × 100) were
charged in the same minutes. Exported free as FBX (Blender preset) zips with a 4096 px base
colour, saved by the user to `../FBX/` and collected into `../tripo/goblin_archer/` (`body`,
`quiver`, `arrow`, `bow` `__take-01.zip`). A Blender 5.2 import of each found one mesh of
triangles and quads, one UV layer and the 4K texture, scaled to 1 unit on its longest side.

First look in Tripo's viewer: the body's front matches the image (hood with ear slits, fang
necklace, chest strap, skull belt, pouch, rag skirt, strapped boots). In side view the cape
is one thin sheet trailing back and down from the shoulders; it can be shaped in Blender. The
quiver has its rim, buckled bands, knotted rag and about ten fletched arrows. The arrow has
its barbed head and a ragged, several-vaned fletching. The bow keeps its recurve horn limbs,
iron bands, leather grip with the red rag and hooked bone tips, and its string is one thin
strand; from the front the limbs are thick, as a horn bow's are.

## 7. Bow redesign

Three designs, one job each, on the Higgsfield website with Unlimited on (the user's
preference of 24 October 2026), Nano Banana Pro, 2K, 9:16. Input: image A `quiver_front.png`
(2048 px copy), for style, materials and colours only; a prop of the same set, so no goblin
is drawn.

Shared opening:

> Use Image A only for the painterly style with crisp dark outlines, the flat lighting, and
> the materials and colours of the goblin horde: dark brown leather, blood-red rags and rusty
> iron. Do not copy its shape: Image A is a quiver, and you are drawing a bow. Draw one weapon
> on its own, as a clean reference for 3D modelling in a fantasy tactics game: the war bow of
> a goblin archer of a savage horde. It is short, made for a goblin about 1.3 metres tall, but
> heavy, cruel and powerful, with a bold, chunky silhouette that reads at once even when it is
> tiny on the battlefield.

Shared ending:

> Shown whole and upright down the middle of the image, one tip at the top and one at the
> bottom, filling most of the image height. Strict side view in the plane of the bow, so the
> full curve of both limbs and the straight string read clearly: the string on the right, the
> back of the bow on the left; no perspective, no tilt, no three-quarter angle. Centered with
> white space around it; nothing touches the image edges. The same painterly illustration with
> crisp dark outlines as Image A. Even, soft, flat lighting with very light shadows. Plain
> empty white background. One bow only: no arrow, no quiver, no goblin, no hands, no stand, no
> text.

### 7.1 Horn bow (`bow_horn_side.png`)

```text
The design: a short composite recurve bow. Its two limbs are a matched pair of long, ridged beast horns, dark grey-brown, ringed with growth ridges and paler toward the tips, joined in the middle by a thick riser of blackened wood. From the grip each limb sweeps forward away from the string, then curls sharply back at the tip. Each tip is capped with a carved, yellowed bone nock shaped like a hooked fang, where the string loops on. Where horn meets wood, the joints are bound tight with pale sinew and clamped by a riveted band of rusty iron. The grip is wrapped in dark brown leather, with one strip of blood-red rag knotted just below it, its frayed ends hanging short, and three small fangs threaded on a cord beside it. A thick, twisted gut string, taut and perfectly straight from tip to tip.
```

### 7.2 Blackwood blade bow (`bow_blade_side.png`)

```text
The design: a heavy self bow carved from a single stave of black, knotted, gnarled wood, deeply recurved. From the grip each limb curves forward away from the string, then its tip sweeps back in a strong hook. A crude, curved blade of rusty, pitted iron is lashed with leather thong along the outside of each hooked tip, following its curve to a sharp point, so the bow can slash in close combat. A row of small notches is cut along the back of each limb, the archer's tally of kills. The thick grip is wrapped in dark leather and bound above and below with strips of blood-red rag, their ragged ends hanging short. A thick, dark, twisted string, taut and perfectly straight from tip to tip.
```

### 7.3 Bone-backed trophy bow (`bow_bone_side.png`)

```text
The design: a goblin war bow built from trophies. A thick recurve stave of dark brown wood, its back armoured along both limbs with a row of flat, overlapping bone plates cut from ribs, lashed on with dark sinew so the limbs look ridged like a spine. The tips curl back in tight hooks capped with yellowed bone. On the back of the riser, opposite the string, a small horned animal skull is lashed on with leather thong, facing outward, its jaw missing. The grip is wrapped in black leather, with one blood-red rag knotted below it, its frayed ends hanging short. A thick, twisted gut string, taut and perfectly straight from tip to tip.
```

### 7.4 Results

Each came back as a 1536 × 2752 PNG, fully opaque, with clear margins. Unlimited queued each
job for about five minutes before a minute of generation. Hashes are in `jobs.json`;
`bow_candidates.webp` shows the rejected bow beside the three.

- **Horn:** follows the prompt. Ridged dark horn limbs on a blackened wood riser, riveted
  rusty iron bands, pale sinew, yellowed fang tips, three fangs on a cord, red rag. The broken
  horn bases jut back beside the grip.
- **Blackwood blade:** a gnarled, knotted black recurve with a red-rag and leather grip. The
  blades are lashed along the back of each limb near the grip rather than on the tips, and the
  kill notches face the string.
- **Bone trophy:** bone plates along both limbs like a spine, a horned skull without its lower
  jaw on the back of the grip, hooked bone tips, black grip and red rag. The wood is a warmer,
  lighter brown than the horde's dark palette.

### 7.5 Simplified horn bow (`bow_horn_simple_side.png`)

The user chose the horn bow and asked: "Make the bow look more simple", in Higgsfield. An edit
of `bow_horn_side.png`, attached as image A from the website's Generations picker, with no
style reference; Nano Banana Pro, 9:16, 2K, Unlimited.

```text
Image A is the war bow of a goblin archer. Redraw this same bow, but simpler. Keep its size and proportions, its silhouette, the strict side view with the straight string on the right, and its materials: two dark grey-brown horn limbs joined by a blackened wood grip wrapped in dark brown leather, a yellowed hooked bone cap on each tip, and one blood-red rag knotted below the grip. Make it simpler: remove the cord of fangs, the broken horn stubs that jut back beside the grip, and the sinew lashings. Keep only one plain band of rusty iron where each horn meets the grip, and none further along the limbs. Smooth, clean horn limbs with only a few soft growth ridges. Fewer, larger shapes, so it reads at once when it is tiny on the battlefield and is easy to model in 3D. The same painterly illustration with crisp dark outlines as Image A, even, soft, flat lighting with very light shadows, plain empty white background. Shown whole and upright, centered, nothing touches the image edges. One bow only: no arrow, no quiver, no goblin, no hands, no text.
```

Result: the same silhouette without the fang cord, the lashings and the pointed horn stubs
(the horn bases are rounded knobs at the grip), smooth limbs, fang tips, leather grip and red
rag. A small iron band is still on each limb near the tips.
