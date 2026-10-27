# Meridius painted interface masters

Created 23 October 2026 for the user's request for epic panels, banners and
borders matching the Higgsfield artwork and the game's supplied references.

## Direction and provenance

The signed-in Higgsfield Assets gallery was visually inspected in a separate
browser tab. Its Meridius terrain, frontier buildings and camps show warm painted
stone, weathered timber, rich foliage and cool recessed shadows. The canonical
local references are `references/backgrounds/Battlefield 1.png` and
`references/characters/Footmen.png`, relative to the Meridius project root.
The latter supplies blue fabric and armour materials only: its eagle is excluded.

The three new masters were generated with the built-in ImageGen tool, with
`transparent_background: true`. They were **not generated on Higgsfield**.
The tool did not expose a model selector or seed. Each asset was generated once;
all three originals are kept here locally, not in Git (the `.gitignore` rule
`/art/ui/epic/*-take*.png`). No paid Higgsfield jobs were submitted.

| Stable ID | Master | Size | Runtime use |
| --- | --- | --- | --- |
| council-frame | council-frame-take01.png | 1536 × 1024 RGBA | Major vellum panels, title panel, outer title border |
| company-banner | company-banner-take01.png | 2172 × 724 RGBA | Blue cloth headings and player deployment/turn banners |
| command-panel | command-panel-take01.png | 2172 × 724 RGBA | Large dark HUD surfaces and binding for large buttons |

Runtime copies in `assets/ui/epic/` are byte-identical to the masters. No crop,
repaint, colour replacement or destructive alpha cleanup was applied. Source
regions in `scripts/ui/styles/painted_frames.gd` omit empty canvas and faint stray
alpha outside the silhouettes. The council opening has genuine zero alpha.
The command panel's centre is filled; the banner's negative space is transparent.

## Generation briefs

### Council frame

Reference order: lush battlefield, Footmen. New original UI art; use references
only for painted materials, warm highlights, cool shadow, blue cloth, weathered
steel and brass. Exclude landscapes, figures and the eagle. One front-facing
rectangular landscape frame, approximately 3:2, empty transparent interior and
exterior. Epic war-council construction: substantial dark forged iron over charred
oak, patinated pale-gold edges, layered bevels, recessed seams and four articulated
corner joints. Abstract interlaced grooves and chased flowing bronze corner
lines; small angular lapis enamel insets at the corners. Straight repeatable rail
spans, matching corner proportions, controlled upper-left light. Ornament remains
near the perimeter. All corners complete. No heraldry, animals, skulls, shields,
weapons, lettering, logos, background scene, reference insets or content.

### Company banner

Reference order: the generated council frame, Footmen. Match the frame's painted
steel, pale gold and carved ornament; use only the Footmen's blue fabric. One
straight-on wide horizontal ribbon, approximately 5:1. A blank dark lapis-blue
woven centre across the middle 75 percent, flat and quiet for cream runtime text.
Fine brass piping and stitched edges. Folded short swallowtail ends behind two
equally sized dark iron clamps, with abstract chased brass matching the frame.
Thick matte fabric, controlled warm highlights and cool shadow, no plastic sheen.
Isolated complete silhouette with real alpha outside. No text, symbol, heraldry,
figures, scene, wall, floor, detached decoration or filled example interface.

### Command panel

Reference: the generated council frame. Match its painted steel, aged gold,
carved lines and upper-left light. One flat front-facing horizontal command panel,
approximately 4:1. Unbroken dark desaturated blue-charcoal oiled leather centre
with subtle painted grain. Layered steel rails, narrow brass inner lip and dark
timber backing. Short angular corner clamps with restrained brass curls and tiny
rivets; simpler than the council corners and without blue gems. Straight consistent
rail cross-sections for slicing. Transparent exterior and filled centre. No text,
buttons, dividers, symbols, crests, weapons, skulls, animals, scenery or mockup.

## Integration contract

The renderer uses nine explicit texture regions with fixed corner sizes. It
stretches straight spans and the quiet centre only. Major council corners render
at 62 × 54 logical pixels (larger on the title border); large command corners at
34 × 25; banner caps at 62 pixels with separate stitched top/bottom regions.
The existing paper and dark fills remain beneath the frames for reliable contrast.

Controls with less than 12 pixels of dark-panel padding, small buttons, tooltips
and narrow HUD bars keep simple procedural metal rims. Large actions get painted
bindings. Banner text has at least 66 pixels of side clearance and 20/22 pixels
of top/bottom clearance. The enemy banner keeps its red surface and painted metal
binding, while the company uses blue cloth. Runtime text, values, controls,
selection cues and focus remain actual Godot controls.

Review at actual desktop scale. Check alpha over pale vellum, dark panels and
the bright sunrise; inspect long headings, compact rosters, disabled controls,
hover/focus, overflow, HUD placement and click exclusion. An attractive master
alone does not establish a successful interface. Native evidence is delivered
under `workspace/2026-10-20_meridius/interface/epic/` in the repository.

## Foe frame (26 October 2026)

The unit bar's portrait frame for a foe (`scripts/ui/unit_bar/portrait_frame.gd`):
the same footprint as the council frame round the same opening, in grim timber,
stone and rusted iron, at the user's request. Unlike the three masters above it
**was generated on Higgsfield** (MCP, `nano_banana_pro`, 3:2, 2k; the job
reported `nano_banana_2` as its model) and **paid from credits** with the
user's approval, as Unlimited was unavailable for every image model: three
takes at 2 credits each. Take 2 (job `fdfde7ec-05cc-45ca-89dc-746e0531e05a`)
was chosen and is kept here locally, not in Git, as `foe-frame-take01.png`
(2528 × 1696, RGB, on flat magenta); the other two were not kept (one painted a plank wall with a small
opening, the other planks in the middle).

The reference was the council frame flattened onto magenta, for its layout.
The prompt asked to keep that layout and repaint every material: "rails of
split dark logs and rough boards bound by rusted, pitted black iron straps with
big crude rivets; corner blocks of rough-cut stone, cracked and chipped, set in
black iron; small dull blood-red gems in place of the blue ones. Dirty and
desaturated, dim warm highlights, cool deep shadows. No brass, no gold, no
blue, no polished metal, no ornamental scrolls, no moss", with straight
repeatable rails, complete corners, flat magenta outside and in the opening,
and no text, symbols, heraldry, skulls, bones, animals, weapons, figures or
scenery.

The runtime copy `assets/ui/epic/foe-frame.png` (1444 × 912 RGBA) is **not**
byte-identical: it was keyed, cropped and scaled by

    python art/ui/epic/tools/key_magenta.py art/ui/epic/foe-frame-take01.png assets/ui/epic/foe-frame.png --margin 8 --scale 0.6

Its measures in `portrait_frame.gd` (`FOE_*`, runtime pixels): frame rect
(4.8, 4.8, 1434.4 × 902.3), corners 238 × 230 (the stone blocks and the iron
clamps beside them), rails' inner edges 136/140/134/129 from the left, top,
right and bottom, and the corner block used for the crest and clasp at (6, 5),
180 × 176. The frame is scaled per axis to the council frame's insets, so both
frames have the same outer size and opening.
