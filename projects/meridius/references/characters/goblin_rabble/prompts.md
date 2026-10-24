# Goblin Rabble: concept, T-pose and equipment prompts

Started 24 October 2026. Route: Higgsfield MCP, Nano Banana Pro (`nano_banana_pro`),
one job per stage, paid credits (MCP has no Unlimited for this model). Job IDs, inputs and
hashes are in `jobs.json` (gitignored). In Git, every image over 2 MB is a full-size WebP
copy (quality 92) of the local PNG original named below.

## Design notes

Earlier designs checked for context (all of them, per `processes/creative-production.md`):
the unit sheets in this folder (footmen, pikemen, crossbowmen, royal guard, orc warriors,
savage orcs, trolls, goblin spearmen, goblin archers), the in-game goblin sprites
(`review/goblins-v2/`, `source/godot/art/raw/goblin_rabble/`), every modelling master and
isolated part (footman, spearman, crossbowman, succubus, wolf scout, mage), the boss
concepts and `references/text/Lore 2.png`.

What the rabble keeps from them:

- **Race** (goblin spearmen and archers sheets, `tools/anim/units.py` `GOB`): green skin,
  small narrow yellow eyes under a heavy brow, long hooked nose, long pointed ears, jagged
  underbite, realistic wiry proportions (head about a fifth of the height), not chibi.
- **Horde colours:** blood-red rags, black cloth, rusty iron, bone, red war paint; the red
  banner's black sun.
- **The unit** (`data/units.json`, current sprite): nine half-starved goblins with knives
  and hatchets, driven ahead of the host; rag loincloths, bare feet, improvised shields
  (the barrel bottom in an iron hoop).

New, proposed for this design (not canon until the user approves it): the horde keeps the
rabble chained until a battle, so each wears a riveted iron thrall collar with a broken
chain; the horde's sun daubed in red on the chest and shield; plundered scraps of the
royal army's blue-and-white-eagle tabards worn as trophies. It fits Lore 2: someone is now
directing the goblins, and the rabble are what it spends first.

## 1. Concept sheet

Inputs: image 1 `Goblin spearmen.png`, image 2 `Goblin archers.png`, image 3
`source/godot/art/raw/goblin_rabble/f_base.png`. 2K, 1:1.

```text
MERIDIUS — GOBLIN RABBLE, UNIT CONCEPT SHEET

A painted unit concept sheet for an isometric fantasy tactics game, the same kind of sheet as Image 1 and Image 2: one squad of goblins standing on a small diorama patch of grass, dirt and mossy stones, seen from a high three-quarter isometric camera about 40 degrees above the ground, sunlight from the upper left, on a plain off-white background.

Image roles: Image 1 and Image 2 are finished concept sheets of goblin spearmen and goblin archers of the same horde. Copy from them exactly the painting style (detailed painterly illustration, crisp dark outlines, warm sunlit colours and cool shadows), the camera, the diorama patch and the goblin race: green skin, small narrow glowing yellow eyes under a heavy brow, long hooked noses, long pointed ears, jagged underbite teeth, and realistic wiry proportions with heads about one fifth of their height. Copy also the horde's colours: blood-red rags, black cloth, rusty iron and bone, and the red war-paint marks on their arms. Do not copy their spears, bows, armour, trousers, boots or hoods. Image 3 is the current game sprite of this unit: keep its idea (nearly naked goblins in rag loincloths with bare feet, crude weapons and improvised shields) but not its pixel-art style or its plain brown colours.

THE UNIT: the Goblin Rabble, half-starved goblin thralls that the horde drives ahead of its host to pour into every gap. Six goblins of one squad in a loose, crowded pack, surging forward toward the LOWER LEFT of the image, crouched and ready to pounce, every figure fully visible and none hiding another. They are smaller and far scrawnier than the goblin spearmen: ribs, collarbones and knuckles show through tight green skin; long sinewy arms, knobbly knees, long bare feet with clawed toes, a hungry hunch. Wild, feral faces with snarling grins of jagged yellow teeth.

Their shared kit, the same on all six, so they read as one unit:
- a heavy rusty iron thrall collar riveted round the neck, with a short broken chain of three links hanging from a ring at the front: the horde keeps them chained until it unleashes them;
- the horde's mark: a crude blood-red war-paint sun with jagged rays daubed on the chest, and a red war-paint handprint across one side of the face;
- tattered blood-red rag strips knotted round the upper arms and the brow, their ends trailing;
- a ragged loincloth of black and blood-red rags on a knotted rope belt, hung with a few small bone charms;
- two of them wear a plundered trophy on the belt: a torn scrap of royal-blue cloth with part of a white eagle on it, ripped from an enemy soldier's tabard.

Each holds one weapon in the right hand: a long rusty notched knife, a small rusty hatchet, a curved skinning knife, a hatchet with a bone handle, a heavy cleaver, a long knife. Three of them carry an improvised shield on the left arm: a round barrel bottom of weathered planks inside a rusty iron hoop, with the red war-paint sun daubed on it. Small individual details within the same design: a torn ear, a scarred bald head, a black rag hood, a crooked broken nose, an older grey-wrinkled goblin, a young one.

STYLE: the same detailed painterly illustration as Images 1 and 2, crisp dark outlines, clean readable shapes, bright sunlit colours and cool shadows, not photorealistic. At a small size on the battlefield they must read at once as a swarm of desperate, dangerous little killers.

BACKGROUND: the diorama patch on a plain off-white background, as in Image 1. No text, no labels, no frame, no interface.
```

The user, 24 October 2026, after the concept was submitted: the rabble, the spearmen and
the archers are three separate units, each gets its own T-pose and equipment; every goblin
gets the nose and style of the rabble goblins (the right-hand panel of
`review/goblins-v2/goblins_v2_set.jpg`), not the long hooked noses of the painted sheets.
`ref_rabble_faces.png` is that face reference: the six rabble heads from
`source/godot/art/raw/goblin_rabble/f_base.png`, enlarged 2x (nearest).

Concept B (`concept_b.png`) is the design basis. Its noses are still long and hooked
(written before the user's note); the T-poses take the face from `ref_rabble_faces.png`.

## 2. Rabble T-pose

Inputs: image A concept B (job `06154672-97c9-4ced-a550-44b3786aef4f`), image B
`ref_rabble_faces.png` (upload `0f7ef019-d79a-4367-acd2-d5361dda6f34`). 4K, 1:1.

```text
Use Image A as the character design and Image B for his face. Image A is a concept sheet of six goblins of one unit, the Goblin Rabble: draw only ONE of them, the bald goblin in the front middle with the red war-paint sun on his chest, the red rag tied round his upper arm and the red and black rag loincloth with a small skull charm. Redraw him as a clean T-pose character reference for turning him into a 3D model and rigging him for animation in a fantasy tactics game.

Face and head, the most important part, exactly like the goblins in Image B (use Image B only for the face and head shape, not its pixel-art style): a bald, rounded skull with a heavy, wrinkled brow ridge; small, narrow, deep-set pale-yellow eyes under the brow; a SHORT, broad nose with a heavy rounded tip that droops down a little toward the upper lip, the same nose as in Image B: not long, not hooked, not pointed; a wide, thin-lipped sullen mouth, closed, with two small lower fangs showing; deep lines from the nose to the corners of the mouth; long pointed ears that stick out sideways and a little upward. Keep from Image A the red war-paint handprint across one side of his face and the scar on his scalp.

Pose: standing perfectly straight, facing the camera directly from the front. Both arms stretched straight out to the sides at shoulder height, perfectly horizontal, elbows straight, palms facing down, fingers straight and together. Legs straight, feet shoulder-width apart, flat on the ground and pointing forward, with a clear gap of empty space between the legs. Head facing forward with the chin level.

His hands are empty: no weapon and no shield. Keep everything else identical to Image A: the scrawny, half-starved body, ribs, collarbones and knuckles showing through tight olive-green skin, long sinewy arms, knobbly knees and long bare feet with clawed toes; the heavy rusty iron collar riveted round his neck, with a short broken chain of three links hanging from the ring at the front onto his chest; the blood-red war-paint sun with jagged rays on his chest and the red handprint on his shoulder; the blood-red rag knotted round his upper arm with short ends; the brown leather wraps on his wrists; the knotted rope belt with small bone charms and fangs; and the ragged loincloth of black and blood-red rags hanging to mid-thigh. Realistic wiry goblin proportions, the head about one fifth of his height, not chibi, not cute.

Keep the rags and the chain short and close to the body, so the arms, legs and torso are clearly separated and nothing overlaps. Full body visible from the top of the head and the ear tips to the soles of the feet, centered, with space around him on every side. The same painterly illustration with crisp dark outlines as Image A, with even, soft, flat front lighting and very light shadows. Plain empty white background.
```

## 3. Rabble equipment

Input for each: image A concept B (job `06154672-97c9-4ced-a550-44b3786aef4f`). One job per item.

### 3.1 Knife

2K, 3:4. File `rabble_knife_front.png`.

```text
Use Image A only for the design, materials and art style of one weapon. Image A is a concept sheet of goblin thralls; draw only the long rusty notched knife held by the bald goblin at the top left. Draw this knife on its own, with no goblin and no hands: a long, slightly curved, single-edged iron blade like a short machete, pitted with orange-brown rust, with a few chipped notches along its cutting edge and a pointed tip; a simple short iron crossguard; a round wooden grip wrapped in strips of dark brown leather, ending in a small round iron pommel.

Shown whole and perfectly straight, standing vertically down the middle of the image with the tip at the top and the pommel at the bottom, filling most of the image height. Strict flat front view: the flat face of the blade faces the viewer directly, so its full shape and the notches read clearly; no perspective, no tilt, no three-quarter angle. Centered with white space around it; nothing touches the image edges.

The same painterly illustration with crisp dark outlines as Image A. Even, soft, flat lighting with very light shadows. Plain empty white background. One knife only: no second weapon, no sheath, no stand, no text.
```

### 3.2 Hatchet

2K, 3:4. File `rabble_hatchet_front.png`.

```text
Use Image A only for the design, materials and art style of one weapon. Image A is a concept sheet of goblin thralls; draw only the small rusty hatchet held by the hooded goblin at the top middle. Draw this hatchet on its own, with no goblin and no hands: a short, straight wooden haft about as long as a forearm, darkened with grime, with a few turns of leather cord wrapped round the grip near the bottom; a rusty iron axe head with a broad, curved, chipped cutting edge and a short flat back, fixed to the top of the haft and bound with a criss-cross of dark leather cord.

Shown whole, the haft standing perfectly straight and vertical down the middle of the image, the axe head at the top with its cutting edge pointing to the left. Strict flat side view of the axe: the flat face of the axe head faces the viewer directly, so its full outline reads clearly; no perspective, no tilt, no three-quarter angle. Centered with white space around it; nothing touches the image edges.

The same painterly illustration with crisp dark outlines as Image A. Even, soft, flat lighting with very light shadows. Plain empty white background. One hatchet only: no second weapon, no stand, no text.
```

### 3.3 Cleaver

2K, 3:4. File `rabble_cleaver_front.png`.

```text
Use Image A only for the design, materials and art style of one weapon. Image A is a concept sheet of goblin thralls; draw only the heavy rusty butcher's cleaver held by the bald goblin in the front middle. Draw this cleaver on its own, with no goblin and no hands: a broad, flat, roughly rectangular iron blade, thick along its straight back and slightly curved along its chipped cutting edge, pitted with orange-brown rust, with a round hole near the top back corner; a sturdy wooden handle fixed with two iron rivets, its end wrapped in a few turns of dark leather.

Shown whole, standing vertically down the middle of the image, the blade at the top and the handle pointing straight down, the cutting edge on the left. Strict flat side view: the flat face of the blade faces the viewer directly, so its full outline reads clearly; no perspective, no tilt, no three-quarter angle. Centered with white space around it; nothing touches the image edges.

The same painterly illustration with crisp dark outlines as Image A. Even, soft, flat lighting with very light shadows. Plain empty white background. One cleaver only: no second weapon, no stand, no text.
```

### 3.4 Barrel shield

2K, 1:1. File `rabble_shield_front.png`.

```text
Use Image A only for the design, materials and art style of one shield. Image A is a concept sheet of goblin thralls; draw only the improvised round shield carried by the goblin at the right: the bottom of an old barrel. Draw this shield on its own, with no goblin, no arm and no hands: a perfectly round disc of weathered vertical wooden planks with dark seams between them, held inside a rusty riveted iron hoop round the rim, a domed rusty iron boss in the middle, and the horde's mark daubed across the planks in blood-red war paint: a crude sun, a ring round the boss with jagged rays reaching out toward the rim, rough brush strokes with drips.

Shown whole, seen dead-on from the front, so the shield is a perfect circle with no perspective, no tilt and no three-quarter angle. Centered with white space around it; nothing touches the image edges.

The same painterly illustration with crisp dark outlines as Image A. Even, soft, flat lighting with very light shadows. Plain empty white background. One shield only: no weapon, no stand, no text.
```

## Delivered (24 October 2026, awaiting the user's approval)

- `rabble_tpose_front.png` (4096²): pass. The face follows `ref_rabble_faces.png`. Minor:
  the nose tip is pinkish-tan rather than skin green, and the toes are not clawed.
- `rabble_knife_front.png`, `rabble_hatchet_front.png`, `rabble_cleaver_front.png`
  (1792x2400) and `rabble_shield_front.png` (2048²): pass.
- `concept_a.png`: the alternative concept, not chosen. `concept_b.png` is the basis.

## 4. Revisions

The user, 24 October 2026, after seeing the first set: the barrel shield gets no symbol and no boss, only a barrel bottom; add a badly hammered-together plank shield; the spearman loses his helmet; no body paint on any goblin.

### 4.1 Plain barrel shield

Input: image A `rabble_shield_front.png` (job `9219f6d5-428e-4efd-b9db-cc722d3145ad`). 2K, 1:1.

```text
Keep the round shape, size, strict front view, the rusty riveted iron hoop round the rim, the weathered vertical wooden planks with dark seams, the painterly style with crisp dark outlines, the flat lighting and the plain white background of Image A. Change only two things: remove the red painted sun completely, and remove the domed iron boss and its ring of rivets from the middle. The shield is now only the bottom of an old barrel: a plain round disc of weathered vertical wooden planks inside the rusty iron hoop. Where the paint and the boss were, show the same bare, weathered wood as the rest of the planks, with its grain, a few knots and small cracks. No symbol, no paint, no boss, no knob, no handle on the front. One shield only, centered, with white space around it; nothing touches the image edges. No text.
```

### 4.2 Plank shield

Input: image A `rabble_shield_front.png`, for style and materials only. 2K, 3:4.

```text
Use Image A only for the painterly style with crisp dark outlines, the flat lighting and the weathered wood and rusty iron materials; do not copy its round shape, its iron hoop, its boss or its red symbol. Draw a different shield for the same goblin thralls: a crude, badly made shield hammered together from scrap planks. Four or five mismatched wooden boards of different widths, lengths and shades of grey-brown weathered wood, laid side by side vertically with uneven gaps between them; the ends ragged, split and broken off at different heights, so the outline is a lopsided, roughly rectangular shape. Two crooked wooden crossbars nailed across the front, one near the top and one near the bottom, at slightly different angles; fixed with too many rusty nails, some hammered in crooked, some bent over, a few sticking out half-way. A loose corner of one board lashed on with a few turns of frayed rope. A crack running down one board. No paint, no symbol, no boss, no metal rim.

Shown whole, seen dead-on from the front: strict flat front view, no perspective, no tilt, no three-quarter angle. Centered with white space around it; nothing touches the image edges. Even, soft, flat lighting with very light shadows. Plain empty white background. One shield only: no weapon, no arm, no hands, no stand, no text.
```

### 4.3 T-pose without body paint

Input: image A `rabble_tpose_front.png` (job `77f1d02c-67c4-40ad-9a6f-6aa77c048d36`). 4K, 1:1.

```text
Keep everything in Image A identical: the goblin's face, nose, eyes, ears, bald head, body, pose, proportions and hands; the iron collar with the broken chain; the red rag knotted round his upper arm; the leather wrist wraps; the rope belt with the skull charm and fangs; the red and black rag loincloth; the bare feet; the small healed scar on his scalp; the painterly style with crisp dark outlines, the flat front lighting, the framing and the plain white background. Change only one thing: remove all the red war paint from his skin. Remove the red handprint across his forehead, eye and cheek, the red sun painted on his chest, the red handprint on his shoulder and any red marks on his arms. Paint those areas as plain olive-green goblin skin with the same shading, wrinkles, ribs and muscle detail as the rest of his body. No paint, no tattoos, no markings anywhere on his skin.
```

Delivered revisions (24 October 2026): `rabble_shield_plain_front.png` replaces the
painted shield, `rabble_plank_shield_front.png` is new, and `rabble_tpose_front_v2.png`
replaces the painted T-pose. All three pass; the scalp scar is kept because it is a scar,
not paint. The earlier files stay as history. With the paint gone, the proposed red sun on
the chest and shield is dropped.

## 5. Tripo meshes and textures

The user approved the images on 24 October 2026 ("These looks good") and asked for six
separate Tripo models, with a check-in before texturing. They approved texturing the same
day ("Don't forget to texturize the units and equipment"). Route: Tripo Studio web,
Smart Mesh, Quad, AI model P2.0, one variant each. Each model took one 2048 px RGB copy of
its approved image. Texture panel: the model's own image as reference, style None,
Remove Lighting off, 4K. Task IDs, credits and hashes are in `jobs.json`.

| Model | Image | Polycount set | Faces / vertices |
|---|---|---|---|
| `body` | `rabble_tpose_front_v2.png` | 5,000 | 5,841 / 5,539 |
| `knife` | `rabble_knife_front.png` | 500 | 627 / 561 |
| `hatchet` | `rabble_hatchet_front.png` | 500 | 618 / 526 |
| `cleaver` | `rabble_cleaver_front.png` | 500 | 556 / 515 |
| `shield_barrel` | `rabble_shield_plain_front.png` | 1,000 | 917 / 975 |
| `shield_plank` | `rabble_plank_shield_front.png` | 1,000 | 1,254 / 1,143 |

Cost: 6 × 100 for the meshes and 6 × 20 for the textures, 720 Tripo credits in all
(balance 1,520 → 800).

Exports (free) are in `../tripo/goblin_rabble/`: `<model>__take-01.zip`, each an FBX
(Blender preset) with a 4096² base colour in its `.fbm` folder. There are also untextured
FBX files of the cleaver and both shields. The user's save folder `../FBX/` holds the
same downloads and stays out of Git.

Blender check (5.2, background import): every model is one mesh with UVs and no n-gons.
Each is normalised to 1 unit on its longest side, so it must be scaled when assembled.
Findings:

- Body: the broken chain on the collar is modelled rigid and sticks out forward and down
  in side view. Fixed, and all six models scaled, in
  `../blender/goblin_rabble/goblin_rabble_base.blend` (see its README). The back of the
  body and the loincloth are painted darker and flatter than the front, because the
  texture is inferred from the front image.
- Barrel shield: the front is a flat disc with the staves painted on, and the back has no
  grip or strap.
- Plank shield: the nails come through at the back, which suits a hammered-together
  shield.
