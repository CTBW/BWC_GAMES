# Goblin gear: hoods and leather helmets

Started 24 October 2026, at the user's request ("Make some hoods and leather helmets with
stitches for the gear"). Shared headgear that any of the three goblin units can wear
(`../goblin_rabble/`, `../goblin_spear/`, `../goblin_archer/`). Route: Higgsfield MCP, Nano
Banana Pro (`nano_banana_pro`), one job per item, 2K, 1:1, paid credits. Job IDs and hashes
are in `jobs.json` (gitignored). In Git, every image is a full-size WebP copy (quality 92)
of the local PNG original named below.

## Design notes

- **Fit:** the gear fits the shared goblin head of the T-poses: a bald, rounded skull with
  long pointed ears sticking out sideways. Every piece has openings where the ears go
  through.
- **Materials and colours:** from the approved T-poses. Black cloth, blood-red rags, brown
  leather, dark fur, rusty iron and bone. No paint or symbols, following the user's
  decision of 24 October 2026.
- **Stitching:** crude goblin work. Thick, uneven stitches in dark thread or leather thong,
  and mismatched patches.
- **View:** each piece is shown on its own, keeping its shape as if worn by an invisible
  head, in a strict front view for 3D modelling.

Inputs for every item: image A the archer T-pose v2 (job
`1ea479ee-4ff4-4d72-b319-cf0a206810ee`), for style, materials and colours; image B the
rabble T-pose v2 (job `bf88b20e-cb5c-4dd0-a860-b4d13cc45e38`), for head size and ear
placement.

Shared prompt ending (identical in every item prompt below):

> It keeps its shape as if worn by an invisible goblin head: empty inside, with no head,
> no face, no ears and no stand. Shown whole, seen straight from the front, as if facing a
> goblin who wears it: strict flat front view, symmetrical, no perspective, no tilt, no
> three-quarter angle. Centered with white space around it; nothing touches the image
> edges. The same painterly illustration with crisp dark outlines as Image A. Even, soft,
> flat lighting with very light shadows. Plain empty white background. One piece of
> headgear only: no weapon, no body, no text.

Each prompt starts:

> Use Image A only for the art style, the materials and the colours of the goblin horde,
> and Image B only for the size and shape of a goblin's head, so the gear fits it: a bald,
> rounded skull with long pointed ears that stick out sideways. Draw one piece of headgear
> on its own, as a clean reference for 3D modelling in a fantasy tactics game:

## Hoods

1. `hood_black_front.png`: a pointed hood of black cloth with a short cowl that covers the
   shoulders and ends in a ragged hem. Long vertical ear slits on both sides, their edges
   bound with thick, uneven stitches of blood-red thread. A crude seam of big red
   cross-stitches runs over the top from front to back. A wide face opening, dark and
   empty inside.
2. `hood_rag_front.png`: a hood pieced together from mismatched blood-red and dark rag
   scraps of different sizes, sewn with big, crooked stitches of dark thread. Frayed edges
   and a few holes. Roughly cut ear holes on both sides with loose threads. The point
   flops over to one side. A frayed cord knotted at the neck. A wide face opening, dark and
   empty inside.
3. `hood_hide_front.png`: a hood of rough brown hide with a ring of shaggy dark fur round
   the face opening. Its panels are joined by thick leather thong laced through punched
   holes. Ear slits on both sides are reinforced with stitched leather patches. The hood
   ends in a short shoulder cape with a ragged edge. A wide face opening, dark and empty
   inside.

## Leather helmets

4. `helmet_panel_front.png`: a rounded cap of dark brown leather, made of four panels
   sewn together along raised seams with thick, visible cross-stitches of pale leather
   thong. A thicker leather band round the brow, held by a row of small rusty rivets. Round
   ear holes on both sides with stitched edges. A thin leather chin strap with a small iron
   buckle.
5. `helmet_crest_front.png`: a helmet of hardened, boiled leather in two halves, joined
   by a tall stitched ridge running from front to back over the top like a low crest. A
   short nose guard of hardened leather, sewn on and fixed by two rusty rivets. Two leather
   cheek flaps hang below the ears, laced to the helmet with leather thong. The ears come
   out through stitched slits above the flaps.
6. `helmet_patched_front.png`: a crude leather cap patched together from mismatched
   scraps of different browns and one of dark grey. Big, uneven stitches of dark thread,
   some of them torn and redone. A few rusty iron studs hammered in at random, and one
   small curved bone horn sewn to the top. Lopsided ear holes cut on both sides. A blood-red
   rag knotted round the base as a band, its ends hanging short.

## Retries

First round, 24 October 2026: five of the six pieces came back with goblin ears drawn
through their openings (taken from image B), and `helmet_crest_front.png` was also drawn in
three-quarter view with softer outlines than the set. `hood_hide_front.png` passed as it
was. Each failed piece gets one retry: an edit of its own first result that removes the
ears, or, for the crest helmet, a new generation using the panel cap as the camera
reference instead of the rabble T-pose. 2K, 1:1.

`hood_black_v2`: input image A the `hood_black` job (`61c7913a-67d6-4a57-bd1e-0017a7dbb7b7`).

```text
Keep everything in Image A identical: the black cloth hood, its point, the red cross-stitched seam over the top, the red stitches binding the ear slits, the dark empty face opening, the ragged cowl, the strict flat front view, the painterly style with crisp dark outlines, the flat lighting, the framing and the plain white background. Change only one thing: remove the two pointed goblin ears completely. Where they came out, show the hood's two long vertical ear slits, still bound with red stitches, open, dark and empty inside. Where the ears stuck out beside the hood, show plain white background. No ears, no skin and no head anywhere.
```

`hood_rag_v2`: input image A the `hood_rag` job (`26963241-0311-4c66-8033-83f22bcf60e9`).

```text
Keep everything in Image A identical: the hood of patched blood-red and dark rags, its crooked stitches, holes and frayed edges, the point flopping to one side, the dark empty face opening, the knotted cord at the neck, the strict flat front view, the painterly style with crisp dark outlines, the flat lighting, the framing and the plain white background. Change only one thing: remove the two pointed goblin ears completely. Where they came out, show two roughly cut ear holes in the sides of the hood with a few loose threads, open, dark and empty inside. Where the ears stuck out beside the hood, show plain white background. No ears, no skin and no head anywhere.
```

`helmet_panel_v2`: input image A the `helmet_panel` job
(`d3a26966-b7b6-403a-ac08-147eac95e0fb`).

```text
Keep everything in Image A identical: the rounded cap of four dark brown leather panels with pale cross-stitched seams, the riveted leather brow band, the stitched side flaps, the chin strap with its iron buckle, the dark empty inside, the strict flat front view, the painterly style with crisp dark outlines, the flat lighting, the framing and the plain white background. Change only one thing: remove the two pointed goblin ears completely. Where they came out below the brow band, show a round ear hole in each side of the cap, its edge stitched, open, dark and empty inside. Where the ears stuck out beside the cap, show plain white background. No ears, no skin and no head anywhere.
```

`helmet_patched_v2`: input image A the `helmet_patched` job
(`63ac8c1f-d17a-47de-8171-4dddda1da757`). The rag band also moves up onto the rim; in the
first take it hung below the cap like a neckerchief.

```text
Keep everything in Image A identical: the crude cap patched from brown and dark grey leather scraps, its big uneven stitches, the rusty studs, the curved bone horn on top, the dark empty inside, the strict flat front view, the painterly style with crisp dark outlines, the flat lighting, the framing and the plain white background. Change two things. First, remove the two pointed goblin ears completely: show a lopsided ear hole cut in each side of the cap, open, dark and empty inside, and plain white background where the ears stuck out. Second, move the blood-red rag up so it is wrapped tightly round the lower rim of the cap itself as a headband, knotted at the front, with its two short ends hanging just below the rim. No ears, no skin and no head anywhere.
```

`helmet_crest_v2`: inputs image A the archer T-pose v2 (job
`1ea479ee-4ff4-4d72-b319-cf0a206810ee`), image B the `helmet_panel` job
(`d3a26966-b7b6-403a-ac08-147eac95e0fb`) for the camera, framing and outline weight.

```text
Use Image A only for the art style, the materials and the colours of the goblin horde, and Image B only for the camera, the size on the page, the outline weight and the flat lighting of a headgear reference; do not copy Image B's design and leave out its ears. Draw one piece of headgear on its own, as a clean reference for 3D modelling in a fantasy tactics game: a helmet of hardened, boiled leather in two halves, joined by a tall stitched ridge running from front to back over the top like a low crest. A short nose guard of hardened leather, sewn on and fixed by two rusty rivets. Two leather cheek flaps hang down the sides, laced to the helmet with leather thong. Above each flap, a vertical ear slit with stitched edges, dark and empty inside, where a goblin's long ear would pass through.

It keeps its shape as if worn by an invisible head: empty inside, with no head, no face, no ears and no stand; nothing sticks out through the ear slits. Shown whole, seen straight from the front, exactly like Image B: strict flat front view, perfectly symmetrical left to right, the crest running straight up the middle and the nose guard centred, no perspective, no tilt, no three-quarter angle. Centered with white space around it; nothing touches the image edges. The same painterly illustration with crisp dark outlines as Image A. Even, soft, flat lighting with very light shadows. Plain empty white background. One piece of headgear only: no ears, no weapon, no body, no text.
```

For later headgear: leave the T-pose out as a reference, or the generator draws its ears.
Use a finished ear-free piece as the camera reference instead.

## Delivered (24 October 2026, awaiting the user's approval)

All 2048², strict front view on white, no ears, no paint and no symbols.

- Hoods: `hood_black_front_v2.png` (black, red-stitched ear slits and crest seam),
  `hood_rag_front_v2.png` (patched red and dark rags, point flopped to one side) and
  `hood_hide_front.png` (brown hide with a fur ring and a laced shoulder cape). All pass.
- Leather helmets: `helmet_panel_front_v2.png` (four-panel cap with a riveted band and a
  chin strap), `helmet_crest_front_v2.png` (boiled leather, stitched crest ridge, nose
  guard and laced cheek flaps) and `helmet_patched_front_v2.png` (patched scraps, studs, a
  bone horn and a red rag band). All pass.
- Minor: the crest helmet's nose guard has three rivets instead of two, and its ear slits
  sit high on the dome. The patched cap's rag band sits on the lower rim rather than
  higher up.
- Superseded first takes, kept for reference: `hood_black_front.png`, `hood_rag_front.png`,
  `helmet_panel_front.png`, `helmet_crest_front.png`, `helmet_patched_front.png`.
