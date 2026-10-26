# Wolf Scout 3: T-pose, part and dagger prompts

Started 26 October 2026. The user asked to redo the Wolf Scout: the current model and rig
look bad, she has to look and feel like part of the game, and her daggers must look like
the reference they supplied, `ref_dagger.png` (from
`inbox/attachments/2026-10-26/image-140609-cb50268d.png`). The user sees these images
before anything is made in Tripo.

Route: the Higgsfield website with Unlimited on (the user's preference of 24 October
2026; the MCP reported `unlim: {available: false}` for `nano_banana_pro` today), Nano
Banana Pro, 2K, one image per submission. Job IDs, inputs and hashes are in `jobs.json`
(gitignored). The user approved the 13 generations for the public repository on 26
October 2026: in Git each is a full-size WebP copy (quality 92) of the local PNG original
named below. `ref_dagger.png` and the cut `cloak_front_b_cut.png` stay local.

## Design notes

Design source: the user's Wolf Scout, `../wolf_scout/master.png` (strict front, A-pose) and
`../wolf_scout/design.png`. Her identity is kept: white-furred wolf-woman, short white hair,
green eyes, wolf ears through an olive hood, olive hooded cloak with a bronze clasp, ribbed
brown bodice, laced brown leather corset, brown trousers, open-toed laced gaiters over white
wolf paws, one big white tail.

What changes, to make her look like the game: the rendering and pose of the horde's T-pose
references (the Orc Brute, `../orc_brute/brute_tpose_front.png`, 2048 px copy as image B):
detailed painterly illustration with crisp dark outlines, flat front light, chunky readable
shapes, slightly oversized hands and paws. Matte, worn leather instead of the glossy
trousers. Her daggers are replaced by the user's reference dagger.

Two masters are proposed. **A** keeps the costume exactly. **B** adds scout gear and one
horde accent (the Wolf Scouts fight on the enemy side with the goblins and orcs): laced
bracers, a blood-red sash, a fang necklace, a wolf-head clasp and a weathered cloak hem.
B isn't canon until the user approves it.

The model is built from separate meshes, as before: body (no cloak, no tail), cloak with
hood, tail, and one dagger used twice. A long cloak and a big tail fused into the body mesh
can't be rigged cleanly. The parts are edits of the chosen master.

## 1. Master T-pose

Inputs: image A `../wolf_scout/master.png`, image B a 2048 px copy of
`../orc_brute/brute_tpose_front.png`. 1:1.

### 1A. Faithful (`wolf_tpose_a.png`)

```text
Use Image A as the character design and Image B only for the pose, the front camera, the framing and the art style. Image A is the front reference of the Wolf Scout, an adult wolf-woman scout in a fantasy tactics game. Image B is the finished T-pose reference of an orc from the same game: do not copy his face, body, skin or costume. Redraw the Wolf Scout as a clean T-pose character reference for turning her into a 3D model and rigging her for animation, as a matching companion to Image B: the same strict front camera, filling the page the same way, the same detailed painterly illustration with crisp dark-brown outlines and rich hand-painted shading, and the same even, flat front lighting. Do not copy the smooth, glossy rendering of Image A.

Head and face, as in Image A: a young woman's face with bright green eyes, a small straight nose, a few freckles across her cheeks, and a calm, confident, slightly sly expression with her mouth closed. Short, choppy white hair framing her face, the fringe swept to one side. Two big upright white wolf ears with grey-black fur inside and dark tips, rising through openings in the top of her hood.

Body: an agile, athletic adult woman with the same curvy figure as Image A: a full bust, a narrow waist, wide hips and strong, muscular thighs. Stylized game proportions like Image B: bold, simple, readable shapes, slightly oversized hands and paw feet, the head about one seventh of her height; not chibi, not cute, not realistic. Her arms are covered in thick white wolf fur from the shoulders to the fingertips, with soft cool-grey shading in the fur and a tuft of fur at each elbow. Her hands are white-furred, with short black claws. Her feet are big white wolf paws with black claws.

Pose, identical to Image B: standing perfectly straight, facing the camera directly from the front. Both arms stretched straight out to the sides at shoulder height, perfectly horizontal, elbows straight, palms facing down, fingers straight and together. Legs straight, feet shoulder-width apart, flat on the ground and pointing forward, with a clear gap of empty space between the legs. Head facing forward with the chin level.

Her hands are empty: no daggers, no weapon of any kind. Keep her costume as in Image A: a hooded cloak of olive-green wool, the hood up over her head, fastened at her throat with a small round bronze clasp; a fitted, strapless top of ribbed brown knit; below it, a laced brown leather underbust corset with two short straps hanging from its lower edge; fitted brown leather trousers of matte, well-worn leather with a few scuffs, not shiny; a narrow leather strap from the corset to a small leather pouch on her right hip; laced brown leather gaiters round her ankles, open at the toes, so the white paws and black claws show below them.

The cloak hangs straight down behind her from her shoulders to just below her knees, behind her arms, so her arms, hands, torso and legs are all clearly visible and nothing overlaps. One big, fluffy white wolf tail hangs down behind her from the base of her spine almost to the ground and curves out to her left side, the right side of the image, with soft cool-grey shading in its fur; it doesn't cover her feet.

Full body visible from the tips of her ears to the soles of her paws, centered, with space around her on every side. Plain empty white background.
```

### 1B. With scout gear and the horde's red (`wolf_tpose_b.png`)

The 1A prompt, with this paragraph inserted before "The cloak hangs straight down":

```text
Add this scout gear to her, as part of the same design: dark brown leather bracers laced over the fur on both forearms, from the wrist to just below the elbow, edged with a few small iron rivets; a blood-red cloth sash knotted on her left hip over the top of her trousers, its two ragged ends hanging to mid-thigh; a short cord round her neck with three white wolf fangs at her collarbone; the cloak's bronze clasp shaped like a small snarling wolf's head. The olive cloak is weathered, its hem a little frayed and torn in a few places.
```

## 2. Dagger (`dagger_side.png`)

Inputs: image A `ref_dagger.png` enlarged 3x (LANCZOS) as `ref_dagger_x3.png`, image B
`../orc_brute/knife_side.png` for the layout of a weapon sheet only. 9:16.

```text
Use Image A as the exact design of one dagger, and Image B only for the layout of a weapon reference sheet from the same game: one weapon standing upright in a strict flat side view on a plain white background, drawn with crisp dark outlines and flat lighting. Do not copy Image B's knife. Image A shows the dagger at an angle on a grey background. Redraw that same dagger as a clean reference for 3D modelling: one of the twin daggers of a wolf-woman scout in a fantasy tactics game.

The design, exactly as in Image A: a short, broad, heavy blade of cool blue-grey steel, shaped like a small falchion. Its back is almost straight; its cutting edge is a convex belly that widens the blade toward the tip and sweeps up to a sharp point at the top of the back. A dark, recessed groove runs along the blade from the guard almost to the tip, curving with the belly, and between this groove and the cutting edge the edge is built from four chunky bevelled steel segments, separated by notches. The broad flat between the groove and the back has a few fine stylized cracks. At the base of the blade, just above the guard, one round steel rivet. A thick crescent-shaped crossguard of dark gunmetal steel with bevelled edges, both ends curving up toward the blade. A grip tightly wrapped in diagonal strips of dark navy leather, with bright blue highlights on each wrap. A stepped, faceted pommel of dark gunmetal steel: two angular collars, ending in a sharp four-sided spike pointing down.

The hand-painted look of Image A: chunky, bold, stylized shapes, soft painted gradients, bright worn highlights along the steel edges, with crisp dark outlines. It must read at once when it is tiny on the battlefield.

Shown whole and perfectly straight, standing vertically down the middle of the image with the point at the top and the pommel spike at the bottom, filling most of the image height. Strict flat side view: the flat of the blade faces the viewer directly, the curved cutting edge on the left and the straight back on the right; no perspective, no tilt, no three-quarter angle. Centered with white space around it; nothing touches the image edges.

Even, soft, flat lighting with very light shadows. Plain empty white background. One dagger only: no sheath, no second weapon, no hand, no stand, no text.
```

### 2b. Crossguard fix (`dagger_side_v2.png`)

`dagger_side.png` came back with an S-shaped crossguard (one end up, one down); the
reference's guard is a crescent with both ends toward the blade. Edit of `dagger_side.png`,
attached as image A from the Generations picker, no other reference. 9:16.

```text
Image A is the reference of a dagger for a fantasy tactics game. Make an edited copy of Image A with one change, the crossguard. Redraw the crossguard as a symmetrical crescent seen straight from the side: a thick bar of dark gunmetal steel with bevelled edges, level under the blade, both ends curving up toward the blade by the same amount like a shallow letter U, its left and right halves mirror images of each other. Everything else exactly as in Image A: the blade, its groove, the bevelled edge segments, the cracks, the rivet, the grip, the pommel, the colours, the painted style with crisp dark outlines, and the size and position on the page. Plain empty white background.
```

## 3. Parts

Edits of a master, attached as image A from the website's Generations picker, no other
reference. 1:1. The user asked for her without the hooded cloak, and for the cloak as a
separate item (26 October 2026). The tail stays on the body for now; it can still be split
out for rigging.

The first pair was made from master B. The user then sent master A back
(`inbox/attachments/2026-10-26/image-144433-c25a63eb.png`, a 1280 px copy of
`wolf_tpose_a.png`) with "Do this character without her cloak", so the second pair is made
from master A.

### 3A. Master B without the hooded cloak (`wolf_nocloak_b.png`)

```text
Image A is the finished T-pose reference of the Wolf Scout, a wolf-woman scout in a fantasy tactics game. Make an edited copy of Image A for 3D modelling: the same character, the same pose, the same strict front camera, the same size and position on the page, the same painterly illustration style with crisp dark outlines and the same flat front light.

The only change: remove her hooded cloak completely, with its hood, the cloth hanging behind her and its bronze clasp. Her head is uncovered: her white hair, cut exactly as in Image A, shows all round her head, the fringe swept to one side as before, and her two big upright white wolf ears, with grey-black fur inside and dark tips, grow straight from the top of her head where they rose through the hood. The white fur of her arms continues up over her shoulders. Where the cloak covered something, show her body, her clothes or the plain white background. No green cloth anywhere.

Everything else exactly as in Image A: her face and expression, body, costume, bracers, sash, fang necklace, boots, hands, paws, tail, colours and pose. Plain empty white background.
```

### 3B. Master B's hooded cloak alone (`cloak_front_b.png`)

```text
Image A is the finished T-pose reference of the Wolf Scout, a wolf-woman scout in a fantasy tactics game. Make a separate reference image of only her hooded cloak, for modelling it as its own 3D part: the same olive-green wool hooded cloak as in Image A, with the same colours, folds, ragged torn hem and painted style with crisp dark outlines, seen from the same strict front camera, at the same size and in the same place on the page as in Image A, as if worn by an invisible person standing in the same T-pose.

The hood is up and empty, its opening facing the viewer and showing its shadowed inside, with two openings in the top where her wolf ears came through. The cloak drapes over the shoulders and hangs down the back to the same length as in Image A; its two front edges frame the empty space where her body was, so the inside of the cloak's back panel shows between them. It is fastened at the throat with the same bronze wolf-head clasp.

Only the cloak: no woman, no head, no face, no hair, no ears, no arms, no fur, no tail, no clothes and no body. Even, flat front light. Plain empty white background.
```

### 3C. Master A without the hooded cloak (`wolf_nocloak_a.png`)

```text
Image A is the finished T-pose reference of the Wolf Scout, a wolf-woman scout in a fantasy tactics game. Make an edited copy of Image A for 3D modelling: the same character, the same pose, the same strict front camera, the same size and position on the page, the same illustration style, colours, outlines and flat front light.

The only change: remove her hooded cloak completely, with its hood, the green cloth hanging behind her and its round bronze clasp. Her head is uncovered: her short white hair, cut exactly as in Image A with the fringe swept to one side, shows all round her head, and her two big upright white wolf ears, with grey-black fur inside and dark tips, grow straight from the top of her head where they rose through the hood. The white fur of her arms continues up over her bare shoulders. Where the cloak covered something, show her body, her clothes, her tail or the plain white background. No green cloth anywhere.

Everything else exactly as in Image A: her face, freckles and expression, her body, the strapless ribbed top, the laced corset with its two straps, the trousers, the strap and pouch on her hip, the laced boots, her hands, paws and tail, the colours and the pose. Plain empty white background.
```

### 3D. Master A's hooded cloak alone (`cloak_front_a.png`)

```text
Image A is the finished T-pose reference of the Wolf Scout, a wolf-woman scout in a fantasy tactics game. Make a separate reference image of only her hooded cloak, for modelling it as its own 3D part: the same olive-green wool hooded cloak as in Image A, with the same colours, folds, hem and illustration style with crisp dark outlines, seen from the same strict front camera, at the same size and in the same place on the page as in Image A, as if worn by an invisible person standing in the same T-pose.

The hood is up and empty, its opening facing the viewer and showing its shadowed inside, with two openings in the top where her wolf ears came through. The short cape over the shoulders and the long back panel hang exactly as in Image A, down to just below the knees; the two front edges frame the empty space where her body was, so the inside of the cloak's back panel shows between them. It is fastened at the throat with the same small round bronze clasp.

Only the cloak: no woman, no head, no face, no hair, no ears, no arms, no fur, no tail, no clothes and no body. Even, flat front light. Plain empty white background.
```

## 4. Chosen combination

The user chose master A's body without the cloak (`wolf_nocloak_a.png`) with master B's ragged
cloak (`cloak_front_b.png`): "I like this combo" (26 October 2026, attachments
`image-151136-0223a826.png` and `image-151158-a0802a6a.png`, 1280 px copies of those two
files). They then marked the cloak's two long front flaps in red for removal
(`image-151308-4a006d0d.png`).

### 4A. Cloak B without the front flaps (`cloak_front_b_v2.png`)

Image A is `cloak_front_b.png` from the Generations picker; image B is the user's marked
copy, uploaded. 1:1.

```text
Image A is the reference of the Wolf Scout's hooded cloak, drawn on its own as a part for 3D modelling in a fantasy tactics game. Image B is a marked-up copy of Image A: the two red lines mark the parts to remove. The red lines are only marks and are not part of the cloak.

Make an edited copy of Image A with one change: remove the two long front flaps marked in red in Image B. They are the narrow strips of cloth that hang down the front from the shoulder and from the clasp, one on each side of the opening, and end in long ragged points below the hem. With them gone, the cloak is open down the front from the clasp: between the two outer side drapes only the dark inside of the back panel shows, down to its ragged hem. Where the flaps hung below the hem, show the plain white background.

Everything else exactly as in Image A: the hood with its two ear openings and its shadowed inside, the wolf-head clasp at the throat, the cloth over the shoulders, the outer drapes at the sides, the back panel and its ragged torn hem, the olive colours, the folds, the painted style with crisp dark outlines, the flat front light, and the size and position on the page. No red anywhere. Plain empty white background.
```

Result: the edit only widened the opening between the flaps; both long flaps and their pointed
ends are still there. Retried as 4B with a solid mask instead of thin lines.

### 4B. Cloak B without the front flaps, mask (`cloak_front_b_v3.png`)

Image A is `cloak_front_b.png` from the Generations picker. Image B is a copy of it with the
two flaps marked in the user's red lines filled solid magenta (my tracing of the flap outlines,
`#FF00FF`), uploaded. 1:1.

```text
Image A is the reference of the Wolf Scout's hooded cloak, drawn on its own as a part for 3D modelling in a fantasy tactics game. Image B is the same picture with its two long front flaps painted over in flat magenta. The magenta is only a mask and is not part of the cloak.

Make an edited copy of Image A in which the two front flaps under the magenta mask are removed completely. The cloak becomes open all the way down the front from the clasp, and no cloth hangs where the magenta is. Where the flaps covered the cloak, show what was behind them: the dark shadowed inside of the back panel, framed at the sides by the outer drapes, whose inner edges get clean dark outlines. Below the back panel's ragged hem, where the long pointed ends of the flaps hung, show the plain white background, so no cloth hangs lower than the back panel's hem and the two outer drapes.

Everything else exactly as in Image A: the hood with its two ear openings and its shadowed inside, the wolf-head clasp at the throat, the cloth over the shoulders, the outer drapes at the sides with their ragged ends, the back panel and its ragged torn hem, the olive colours, the folds, the painted style with crisp dark outlines, the flat front light, and the size and position on the page. No magenta anywhere. Plain empty white background.
```

Result (`cloak_front_b_v3.png`, run on credits after the user's go-ahead): the model ignored the
mask and redrew the cloak with both long flaps, close to the original. No magenta left.

### 4C. Hand cut, then a polish pass (`cloak_front_b_cut.png`, `cloak_front_b_v4.png`)

`tools/cut_flaps.py` cuts the two flaps out of `cloak_front_b.png` by hand: the flap outlines
are traced from the user's red marks, the space above the back panel's hem gets the dark
inside colour, and everything of the flaps below the hem becomes white. The result is
`cloak_front_b_cut.png`, uploaded as image A, the only reference. 1:1, credits.

```text
Image A is a hand-edited reference of the Wolf Scout's hooded cloak, drawn on its own as a part for 3D modelling in a fantasy tactics game. Its two long front flaps were cut out by hand, so the cloak is open all the way down the front from the wolf-head clasp, but the edited areas look rough: flat dark patches with square tops under the shoulder cape, and a hand-cut ragged hem.

Repaint Image A into a clean, finished illustration with exactly the same outline and parts. Keep the cloak open down the front: under the shoulder cape, the dark shadowed inside of the back panel fills the whole space between the two outer side drapes, with soft vertical fold shading, and meets the underside of the shoulder cape cleanly. Nothing hangs in front of it: no front flaps, no strips of cloth and no long pointed ends below the hem. Give the back panel's ragged torn hem crisp dark outlines at the same height as in Image A.

Keep everything else exactly as in Image A: the silhouette, the hood with its two ear openings and its shadowed inside, the wolf-head clasp, the cloth over the shoulders, the two outer drapes and their ragged ends, the olive colours, the painted style with crisp dark outlines, the flat front light, and the size and position on the page. Plain empty white background.
```

Result (`cloak_front_b_v4.png`, credits): clean. Both flaps are gone and the cloak is open down
the front; the dark inside of the back panel fills the opening under the shoulder cape with soft
folds, and the ragged hem, outer drapes, hood, ear openings and clasp match the hand cut.

### 2c. Strict front view (`dagger_front.png`, `dagger_front_alt.png`)

`dagger_side_v2.png` is drawn at a slight angle: the guard shows its top faces and sits off
the grip's centre line. Edit of `dagger_side_v2.png`, uploaded as image A through the MCP,
no other reference. Nano Banana Pro, 2k, 9:16, two variants, credits (4).

```text
Image A is the reference of one dagger for a fantasy tactics game, drawn for 3D modelling. It is seen at a slight angle. Make an edited copy of Image A that shows the same dagger in a strict orthographic front view, like a modelling blueprint: the camera looks straight at the flat of the blade, perfectly level and square-on, with no perspective, no tilt and no three-quarter angle, so that no top, bottom or side surface of any part shows.

The dagger stands perfectly straight and upright, point at the top and pommel spike at the bottom. The grip, the pommel and the spike run exactly down the vertical centre line of the image. The crossguard is seen square-on from the front as a flat, symmetrical crescent: a thick bar of dark gunmetal steel, level and centred on the grip, its left and right arms equally long mirror images, both ends curving up toward the blade like a shallow letter U; only its front face shows, its bevels drawn as thin bands along its outline, and its square-cut tips seen flat from the front. The pommel's two angular collars and the four-sided spike are symmetrical about the centre line and seen flat from the front. The grip is a straight cylinder wrapped in diagonal strips of dark navy leather with bright blue highlights, symmetrical about the centre line. The blade's flat faces the viewer directly, with the same outline as in Image A and no visible thickness along its edges.

Everything else exactly as in Image A: the blade's falchion shape, width and length, the dark curved groove, the four chunky bevelled edge segments and their notches, the fine cracks, the round rivet just above the guard, the cool blue-grey and gunmetal colours, the hand-painted style with crisp dark outlines, the even flat light, and the size of the dagger on the page, centred with white space around it. Plain empty white background. One dagger only: no sheath, no hand, no shadow, no text.
```

Result: both variants are square-on. Grip, pommel and spike stand on the page's centre line
(x 766-770 of 1536) and the guard is a flat crescent with only its front face showing.
`dagger_front.png` (variant 2) is chosen: guard centred within 3 px of the grip, wraps drawn as
diagonal spiral strips. `dagger_front_alt.png` (variant 1): guard 8 px off centre, wraps drawn
as chevrons.
