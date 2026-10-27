# Orc Brutes: T-pose, weapon and face prompts, Tripo meshes

Started 26 October 2026. Route: Higgsfield MCP, Nano Banana Pro (`nano_banana_pro`),
one job per stage, paid credits (the MCP reported `unlim: {available: false}`; the user
approved the spend for this unit). Job IDs, inputs and hashes are in `jobs.json`
(gitignored). In Git, every generated image is a full-size WebP copy (quality 92) of the
local PNG original named below.

## Design notes

Design source: the user's pixel-art Orc Brute, `source.png` (393 x 506, from
`inbox/attachments/2026-10-26/image-002630-92d03063.png`), enlarged 4x with nearest
neighbour on white as `source_x4.png`. The user's notes of 26 October 2026: remove the
white body paint, and give the legs the same colour as the upper body. In the sprite his
chest and arms are tan-brown and the bare thighs and knees between the fur kilt and the
boots are green, so the legs become the same bare brown skin.

He holds a spiked wooden club in his right hand and a long knife in his left. Both are
drawn as separate weapons, as the goblins' were, so they can be modelled and attached on
their own. The goblin spearman's T-pose (job `38a827a0-0f1b-48d7-9b34-0c9ec33cebad`,
`../goblin_spear/spear_tpose_front_v2.png`) sets the pose, camera, framing and painterly
style, so the orc reads as part of the same horde; his first spear (job
`892d33eb-2575-4f52-9395-1062bc0d7dad`) sets the style of the weapon sheets.

## 1. T-pose

Inputs: image A `source_x4.png` (upload `789e4d07-513a-4f33-9ab7-906cf9f5c30c`), image B
the goblin spearman's T-pose (job `38a827a0-0f1b-48d7-9b34-0c9ec33cebad`). 4K, 1:1.

```text
Use Image A as the character design and Image B only for the pose, the front camera, the framing and the art style. Image A is a small pixel-art sprite of an orc brute, a huge orc warrior of a savage horde in a dark fantasy tactics game. Image B is the finished T-pose reference of a goblin of the same horde: do not copy his goblin face, ears, body or costume. Redraw the orc brute as a clean T-pose character reference for turning him into a 3D model and rigging him for animation, as a matching companion to Image B: the same strict front camera, filling the page the same way, the same painterly illustration with crisp dark outlines and the same even, flat front lighting. Translate the pixel art into that detailed painterly style, with no visible pixels.

Head and face, as in Image A: a big, bald, rounded skull; a heavy, jutting brow ridge over small, deep-set, fierce dark eyes; a broad, flat nose; a massive square jaw with an underbite, two thick yellowed lower tusks curving up past his upper lip; small pointed ears close to his head, with two small gold rings through the rim of his left ear; a short, thick neck.

Skin: one warm, weathered tan-brown everywhere, exactly the brown of his chest and arms in Image A. His head, face, neck, torso, arms, hands and legs are all the same brown. No body paint, no white marks, no war paint, no tattoos: remove every white stripe and patch that Image A shows on his head, face, chest, belly and arms, and paint that skin as plain brown with the same shading and muscle detail as the rest of his body.

Body: a hulking brute far broader than a man, with massive rounded shoulders, a deep barrel chest, thick slabs of muscle on his chest and arms, huge forearms and big hands, and thick, powerful legs. Heavy, top-heavy orc proportions, the head about one seventh of his height; not chibi, not cute, not fat.

Pose, identical to Image B: standing perfectly straight, facing the camera directly from the front. Both arms stretched straight out to the sides at shoulder height, perfectly horizontal, elbows straight, palms facing down, fingers straight and together. Legs straight, feet shoulder-width apart, flat on the ground and pointing forward, with a clear gap of empty space between the legs. Head facing forward with the chin level.

His hands are empty: no club, no knife, no weapon of any kind. Keep his gear as in Image A: a huge, rounded pauldron of dark grey, battered steel on each shoulder, each set with four or five thick, sharp conical steel spikes and edged with rivets, sitting on top of the shoulder and leaving the arm free; two broad brown leather straps crossing in an X over his bare chest, joined at the breastbone by a round iron ring and studded with a few rivets; brown leather bands wrapped round both forearms, with a short row of small steel spikes along the outside of his right forearm and a riveted steel vambrace with short spikes on his left forearm; a wide brown leather belt studded with rivets, with a yellowed human skull fixed at the front as its buckle; a long strip of ragged blood-red cloth hanging from the belt in front, down to just above his knees; a short kilt of shaggy black fur round his hips, ending at mid-thigh; heavy brown leather boots up to just below the knee, bound with leather bands and topped with thick cuffs of shaggy black fur.

Legs: between the black fur kilt and the fur-topped boots his thighs and knees are bare, the same warm brown skin as his chest and arms. There is no green anywhere on him, and he wears no trousers.

Keep the pauldrons, the fur and the cloth close to the body, so the arms, legs and torso are clearly separated and nothing overlaps. Full body visible from the top of his head to the soles of his boots, centered, with space around him on every side. Plain empty white background.
```

## 2. Club

Inputs: image A `source_x4.png`, image B the goblin spear (job
`892d33eb-2575-4f52-9395-1062bc0d7dad`) for style only. 2K, 9:16.

```text
Use Image A only for the design, materials and colours of one weapon, and Image B only for the art style: the painterly illustration with crisp dark outlines, the flat lighting and the clean white background of a weapon reference from the same game. Do not copy Image B's shape: Image B is a spear, and you are drawing a club. Image A is a small pixel-art sprite of an orc brute; draw only the spiked wooden club in his right hand, on the left side of Image A. Draw this club on its own, as a clean reference for 3D modelling, with no orc and no hands, in a detailed painterly style with no visible pixels.

The design: a heavy orc war club carved from one thick piece of dark brown hardwood. A straight, round handle swells steadily into a big, rounded, knobbly head about three times as thick as the handle. The head is studded all round with about a dozen thick, sharp, rusty grey iron spikes driven into the wood. The lower third of the handle is wrapped in dark brown leather as a grip, and the bottom ends in a rounded knob of wood. A few dents, cracks and dark stains in the wood. The club is about as long as a man's arm.

Shown whole and perfectly straight, standing vertically down the middle of the image with the spiked head at the top and the handle at the bottom, filling most of the image height. Strict flat side view: no perspective, no tilt, no three-quarter angle. Centered with white space around it; nothing touches the image edges.

Even, soft, flat lighting with very light shadows. Plain empty white background. One club only: no second weapon, no knife, no stand, no text.
```

## 3. Knife

Inputs as for the club. 2K, 9:16.

```text
Use Image A only for the design, materials and colours of one weapon, and Image B only for the art style: the painterly illustration with crisp dark outlines, the flat lighting and the clean white background of a weapon reference from the same game. Do not copy Image B's shape: Image B is a spear, and you are drawing a knife. Image A is a small pixel-art sprite of an orc brute; draw only the long knife in his left hand, on the right side of Image A. Draw this knife on its own, as a clean reference for 3D modelling, with no orc and no hands, in a detailed painterly style with no visible pixels.

The design: a long, heavy orc fighting knife, about as long as a man's forearm and hand. A broad, single-edged blade of dark, pitted steel, slightly curved, widening a little toward the tip and ending in a sharp clipped point; the cutting edge is on one side, worn brighter, and a row of jagged saw teeth runs along the thick back. A short, plain iron crossguard. A thick grip of dark wood bound with dark brown leather thong. A round iron pommel.

Shown whole and perfectly straight, standing vertically down the middle of the image with the point at the top and the pommel at the bottom, filling most of the image height. Strict flat side view: the flat of the blade faces the viewer directly, the cutting edge on the left and the saw teeth on the right; no perspective, no tilt, no three-quarter angle. Centered with white space around it; nothing touches the image edges.

Even, soft, flat lighting with very light shadows. Plain empty white background. One knife only: no sheath, no second weapon, no club, no stand, no text.
```

## 4. Tripo meshes

Route as for the goblins: Tripo Studio web, Smart Mesh, Quad, AI model P2.0, one variant
each, one 2048 px RGB copy of each approved image. The user approved the runs, downloads
and follow-up work on 26 October 2026 without asking for each cost. Task IDs, credits and
hashes are in `jobs.json`.

| Model | Image | Polycount set | Faces / vertices |
|---|---|---|---|
| `body` | `brute_tpose_front.png` | 8,000 | 9,434 / 8,836 |
| `club` | `club_side.png` | 1,500 | 1,555 / 1,599 (after the grip's edit) |
| `knife` | `knife_side.png` | 800 | 1,005 / 903 |

The club's first mesh (1,437 faces) had a grip of one loose spiral strip of leather round
an empty core, so one could see through the handle; the user caught it. One free Edit
Mesh retry with the box round the grip alone, from the end of the swell to the knob, gave
a solid round core with the wrap lying on it. The Blender build adds its own closed core
under the wrap as well (`../blender/orc_brute/README.md`).

Textured before downloading: the left-sidebar Texture panel with each model's own image as
reference, style None, Remove Lighting off, 4K. Cost: 3 × 100 credits for the meshes and
3 × 20 for the textures, 360 in all (balance 3,854 → 3,494). Exported free as FBX
(Blender preset) zips with a 4096 px base colour into `../tripo/orc_brute/` (`body`,
`club`, `knife` `__take-01.zip`). The knife's zip carries Tripo's conversion names
(`tripo_convert_….fbx`); it is known by its download name and its face count.

First look in Tripo's viewer: the body's front, side and back are clean, brown skin
everywhere with no white paint and no green on the legs; the hands are mittens with a
separate thumb, as the goblins'. The knife's grip is solid with the thong lying on it,
and the blade is a thin slab with the saw teeth along its back.

Later on 26 October 2026 the user had the knife taken out of the brutes' left hands, and
asked for some of the squad to fight with two clubs and some to lose a pauldron. No new
generations were needed: the second club is a copy of this club, and the pauldrons were
split off the body mesh (`../blender/orc_brute/README.md`). The knife model stays in the
base scene and the first rig, unused.

## 5. Squad face variants

The user's note of 26 October 2026: once the brute is checked, rigged, animated
and working in the sandbox, add different faces so the members of a squad can be
told apart, as circled in `ref_face_variants.png` (from
`inbox/attachments/2026-10-26/image-005824-553d82d3.png`): a metal jaw on one, a
beard on another, a scar across the eye on another. He keeps the brown skin of
this unit in every variant.

Same route and billing as above. Each bust has two inputs: image A the brute's
T-pose (job `5f541a14-cf14-4dd4-b7d5-3e11795d3c5d`) and image B the matching crop
of `ref_face_variants.png` (uploads in `jobs.json`). 4K, 1:1. The prop sheets take
their bust as the only input, at 2K. How each face is built from these is in
`../blender/orc_brute/README.md` (Squad faces).

### Beard bust (`face_beard.png`)

```text
Use Image A as the character: the same orc brute, with exactly the same face, brown skin, bald head, ears, tusks, spiked pauldrons, chest straps and painterly illustration style with crisp dark outlines and even, flat front lighting. Image B is a small pixel-art sprite that shows only the feature to add, a beard: do not copy its green skin, red eyes or pixel style.

Draw a close front view of the orc from Image A, from the top of his bald head down to his skull belt buckle, filling the image, facing the camera directly with the chin level, both arms hanging relaxed at his sides. Plain empty white background.

Give him a long, thick beard of coarse dark brown hair, as in Image B. It grows from his jawline and chin, below his lower lip, framing his jaw from ear to ear, and hangs straight down over his chest as far as the iron ring where his chest straps cross. It is gathered into one thick central braid with two thinner braids beside it, each braid bound near its end with a small iron ring. His cheeks and upper lip stay bare. His two yellowed lower tusks stay fully visible, standing up in front of the top of the beard. The beard lies on his chest in front of the straps.

Everything else exactly as in Image A: the same brown skin with no paint or marks, the gold rings in his ears, the pauldrons, the straps and their iron ring. Only the beard is new.
```

Result: the thick dark brown beard from the jaw down to the strap ring, a central
braid bound with an iron ring and a thinner braid on each side; tusks in front,
cheeks and upper lip bare. Pass.

### Iron jaw bust (`face_jaw.png`)

```text
Use Image A as the character: the same orc brute, with exactly the same face, brown skin, bald head, ears, spiked pauldrons, chest straps and painterly illustration style with crisp dark outlines and even, flat front lighting. Image B is a small pixel-art sprite that shows only the feature to add, an iron jaw: do not copy its green skin, red eyes or pixel style.

Draw a close front view of the orc from Image A, from the top of his bald head down to his skull belt buckle, filling the image, facing the camera directly with the chin level, both arms hanging relaxed at his sides. Plain empty white background.

Give him an iron jaw, as in Image B: a heavy, battered plate of dark grey iron fitted over his whole lower jaw and chin like a jaw guard, curving round his jaw from below one ear to below the other. Its top edge runs just under his lower lip, and it is fixed with a row of round rivets along its edges and a dented iron band across the chin. His two thick yellowed lower tusks rise from behind the plate's top edge and stand up over his upper lip, in front of the iron. The iron is old and scratched, with a little rust in the dents, the same dark steel as his pauldrons.

Everything else exactly as in Image A: the same brown skin with no paint or marks, the gold rings in his ears, the pauldrons, the straps and their iron ring. Only the iron jaw is new.
```

Result: a riveted dark iron guard round his whole lower jaw and chin, with a
dented band across the chin and the tusks rising in front of it. Pass. It reads
as a collar from the front more than a chin cup; the plate is modelled to the
bust's outline (see below).

### Scar bust (`face_scar.png`)

```text
Use Image A as the character: the same orc brute, with exactly the same face, brown skin, bald head, ears, tusks, spiked pauldrons, chest straps and painterly illustration style with crisp dark outlines and even, flat front lighting. Image B is a small pixel-art sprite that shows only the feature to add, a scar over one eye: do not copy its green skin, red eyes, pixel style or the marks on its chest.

Draw a close front view of the orc from Image A, from the top of his bald head down to his skull belt buckle, filling the image, facing the camera directly with the chin level, both arms hanging relaxed at his sides. Plain empty white background.

Give him a scar across his right eye, which is on the left side of the image, as in Image B: three long, parallel slash scars, like the marks of a claw or a blade, running diagonally down from the middle of his forehead above that brow, across the eye, to his cheekbone. The scars are deep red, raw and fresh, with darker red lines in the middle and lighter pink, slightly raised edges, cutting through the eyebrow. His eye under them is still open and the same as the other eye. His other eye, the rest of his face and his chest have no scars.

Everything else exactly as in Image A: the same brown skin with no paint or other marks, the gold rings in his ears, the pauldrons, the straps and their iron ring. Only the scar is new.
```

Result: two deep red claw gouges with pink rims from the forehead over the brow
and the eye to the cheek. Deviation: the prompt asked for three slashes over his
right eye (image left), and the bust shows two over his **left** eye (image
right). The game paints what the bust shows: two gouges over his left eye. Pass.

### Beard prop (`beard_prop.png`, 3:4)

```text
Use Image A only for the design and colours of one thing: the orc's beard. Draw this beard on its own, as a clean reference for 3D modelling, with no orc, no head, no face, no tusks, no lips and no body: only the hair, as if it were a separate piece, in the same painterly illustration style with crisp dark outlines.

The design, exactly as in Image A: a thick, coarse, dark brown beard that grows along the whole jawline from below one ear round the chin to below the other, leaving the mouth open above it; there is no moustache. It hangs down in a full mass that tapers and ends in one thick central braid, bound with an iron ring and ending in a tuft, with a thinner braid on each side, each bound with a small iron ring. Clumped, wavy strands painted in dark and light browns.

Shown in a three-quarter view from the front left, so the U-shaped curve of the beard along the jaw, its thickness and the hanging braids are clearly visible. Centered, the whole beard from its top edge to the tips of the braids, filling most of the image height, with white space around it; nothing touches the image edges. Even, soft, flat lighting with very light shadows. Plain empty white background. One beard only: no head, no face, no moustache, no stand, no text.
```

Result: the beard alone, front three-quarter, the U along the jaw open above, no
moustache, the three braids with their rings. Pass: it went to Tripo (below).

### Jaw guard prop, first try (`jaw_prop_v1.png`, 1:1)

```text
Use Image A only for the design, materials and colours of one piece of armour: the riveted iron jaw plate that the orc wears over his lower jaw and chin. Draw this jaw plate on its own, as a clean reference for 3D modelling, with no orc, no head, no face, no tusks, no lips and no straps: an empty piece of armour, in the same painterly illustration style with crisp dark outlines.

The design, exactly as in Image A: one thick plate of dark, battered iron bent into a deep U that cups a big jaw and chin, from below one ear round the front to below the other. Seen from the front, its bottom is a broad rounded curve under the chin, its two sides rise as narrow upright bars to where the ears would be, and its top edge runs as a smooth curve along under the lower lip. The edges are rolled and a little thicker; the plate is set with two rows of big, round, domed rivet heads; the iron is scratched, dented and spotted with orange rust. The inside of the plate is plain dark iron.

Shown in a three-quarter view from the front left, seen slightly from above, so the curve of the U, the thickness of the metal and the empty inside of the plate are clearly visible. Centered, filling most of the image, with white space around it; nothing touches the image edges. Even, soft, flat lighting with very light shadows. Plain empty white background. One jaw plate only: no head inside it, no stand, no text.
```

Result: a closed ring, a riveted collar with no open back. Fail.

### Jaw guard prop, second try (`jaw_prop.png`, 1:1)

```text
Use Image A only for the design, materials and colours of one piece of armour: the riveted iron jaw guard that the orc wears over his lower jaw and chin. Draw this jaw guard on its own, as an empty piece of armour and a clean reference for 3D modelling: no orc, no head, no face, no tusks, no lips, no straps.

Its shape: it is not a ring, not a band and not a collar. It is a curved iron chin cup like the lower half of a helmet's face guard: one thick plate of dark iron bent into a horseshoe that wraps round the front of a big jaw. Its middle is a deep, rounded cup that holds the chin from the front and from below; from there its two sides run back and up along the jawline as narrow cheek bars and end below where the ears would be. The back is completely open, with no metal behind the jaw or under the neck, and the top is open: its top edge is a smooth curve that would sit just under the lower lip. Seen from the front it is a wide U, as in Image A.

Details as in Image A: rolled, slightly thicker edges; two rows of big, round, domed rivet heads along its outside; dents, scratches and spots of orange rust on battered dark grey iron. The inside is plain dark iron.

Shown in a three-quarter view from the front left and slightly from above, so the horseshoe shape, the open back, the thickness of the metal and the inside of the cup are clearly visible. Centered, filling most of the image, with white space around it; nothing touches the image edges. Even, soft, flat lighting with very light shadows. Plain empty white background. One jaw guard only: no stand, no text.
```

Result: a closed ring again, despite "not a ring". Fail. Neither sheet is a usable
image for Tripo, so the plate is modelled in Blender (`jaw_plate.py`) on the
bust's outline and textured from the bust (`jaw_texture.py`), with 3D rivet domes.

### Tripo beard

From `beard_prop.png`, one 2048 px RGB copy (1529 × 2048,
`scratchpad brute/tripo_inputs/beard_2048.png`): Smart Mesh, Quad, P2.0,
polycount 2,500, one variant, 100 credits; 3,221 faces, 2,700 vertices. Textured in
the Texture panel with `beard_prop` as reference, style None, Remove Lighting off,
4K, 20 credits (balance 3,494 → 3,394 → 3,374). Exported free as FBX (Blender
preset) to `../tripo/orc_brute/beard__take-01.zip`, entries
`orc_brute_beard_tripo.fbx` and its 4096 px base colour.

First look in Tripo's viewer: the strands, the three braids and their rings came
through, and a small loose arc of hair floats in front of where the mouth would
be. `fit_beard.py` drops that arc (68 vertices) before fitting the beard to the
head.

Face spend: Higgsfield 3 × 4 credits for the busts and 3 × 2 for the prop sheets,
18 in all (balance 403.57 → 385.57); Tripo 120.
