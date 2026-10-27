"""Prompts for the ability icons and effect sheets (Nano Banana Pro on the Higgsfield website).

Writes projects/meridius/docs/ability-art-prompts.md from data/abilities.json, data/units.json
and the subjects below. Every ability must have an effect and its icon a subject, or this fails.

    python tools/anim/ability_prompts.py

Icons follow the set's language (docs/squad-skills.md, "Icons"): a dark ink outline, flat fills,
one light from the top left, readable on the 26 px ability button. The Shield Wall icon is the
style key: it is made first and attached to every other icon prompt.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT.parents[1] / "docs" / "ability-art-prompts.md"
REFS = "projects/meridius/references/characters/"
INBOX = "inbox/meridius-abilities/"
KEY = "shield"

ROYAL = "Colours: royal blue, cream, polished steel, warm gold and dark brown leather."
GUARD = "Colours: black and white fur, warm gold, a little pink and violet."
HORDE = "Colours: blood red, rusty iron, black and bone white."

# icon -> (subject, colours, unit reference sheet in REFS or None)
ICONS = {
    "shield": ("three royal kite shields locked edge to edge in a wall, seen from the front, the middle one slightly in front: "
               "royal-blue fields with a white heraldic eagle, polished steel rims, a small gold glint on the top-left rim",
               ROYAL, "Footmen_front.png"),
    "bash": ("one royal kite shield (blue field, white eagle, steel rim) seen at an angle, slamming into the right edge of the "
             "square, where a jagged white-and-yellow impact star bursts; three short cream motion lines behind it on the left",
             ROYAL, "Footmen_front.png"),
    "shield_charge": ("one royal kite shield (blue field, white eagle, steel rim) tilted forward and driven hard toward the upper "
                      "right, a bright blue-white impact flash at its leading edge, three long gold speed lines streaming back to "
                      "the lower left", ROYAL, "Footmen_front.png"),
    "defend": ("a royal kite shield with a gold rim and a gold eagle on a blue field, raised to the front, with the dark "
               "silhouette of a smaller comrade sheltering behind it, and a bright gold arc of protection curving over both",
               ROYAL, "Footmen_front.png"),
    "spearwall": ("three long spears side by side, angled forward from the lower left to the upper right like a hedge, ash "
                  "shafts with blue binding, broad steel leaf-shaped heads with bright glints; a short gold line across their "
                  "tips marks the line no enemy may cross", ROYAL, "Pikemen.png"),
    "square": ("the spear square seen from a high isometric view: a compact square block of four blue-hooded soldiers' heads on "
               "a diamond-shaped stone tile, steel spear points sticking out of all four faces of the block like a hedgehog",
               ROYAL, "Pikemen.png"),
    "thrust": ("one very long pike thrust diagonally from the lower left to the upper right corner, its steel head ending in a "
               "sharp white thrust flash, passing over the small blue hood of a comrade at the lower middle",
               ROYAL, "Pikemen.png"),
    "eye": ("a loaded crossbow seen from the side, level and ready, dark wood stock and steel bow, a bolt in place; above it a "
            "watchful open eye drawn in gold", ROYAL, "Crossbowmen.png"),
    "aimed_shot": ("a crossbow bolt with blue fletching driven into the dead centre of a round archery target (red and cream "
                   "rings), four gold aiming brackets around the target", ROYAL, "Crossbowmen.png"),
    "bolt": ("a thick, heavy crossbow bolt with an iron head and blue fletching, flying toward the upper right and punching "
             "through a cracked steel armour plate, a few orange sparks", ROYAL, "Crossbowmen.png"),
    "growl": ("the head of a border collie in profile facing right: black-and-white fur, white blaze and muzzle, ears laid back, "
              "fangs bared in a snarl, a gold royal collar; three violet curved growl waves coming from its mouth",
              GUARD, "Collie Royal Guard.png"),
    "hound_charge": ("a large gold paw print tilted forward as if bounding toward the upper right at full tilt, three gold speed "
                     "lines and a small puff of dust behind it", GUARD, "Collie Royal Guard.png"),
    "lick_wounds": ("the white muzzle and black nose of a border collie at the top, its pink tongue out, licking; below it a "
                    "small green healing cross with two white-gold sparkles", GUARD, "Collie Royal Guard.png"),
    "lightning": ("a bright forked lightning bolt striking down from the top, then jumping sideways in two shorter zig-zag arcs "
                  "to the left and right, each arc ending in a small bright spark",
                  "Colours: white, pale blue, electric blue and a touch of violet.", None),
    "frost": ("a burst of jagged ice shards exploding outward from the centre, a small six-pointed snowflake at the core",
              "Colours: white, pale cyan and ice blue.", None),
    "heal": ("a soft golden-white beam of light falling from the top onto a green healing cross, small gold sparkles around it",
             "Colours: warm white, gold and fresh green.", None),
    "circle": ("a glowing ring of runes lying flat on the ground (an ellipse twice as wide as it is tall), three short beams of "
               "soft light rising from it", "Colours: green-gold, pale gold and fresh green.", None),
    "fire": ("a blazing fireball flying toward the lower right, a white-yellow core, orange and red flames trailing back to the "
             "upper left, two small embers", "Colours: white-yellow, orange, fire red and dark red.", None),
    "blood": ("a large dripping drop of dark red blood in front of two crossed crude goblin cleavers, a few red sparks around it",
              HORDE, None),
    "gut": ("three ragged dark red claw slashes tearing diagonally across a sickly green hex sigil (a crude spiked circle), "
            "drops of blood falling from the slashes", "Colours: dark red, blood red, sickly green and black.", None),
    "stone": ("a big round rough grey boulder in flight, arcing from the lower left toward the upper right, a dotted arc trail "
              "behind it and two small chips breaking off", "Colours: stone greys, earth brown and a little moss green.", None),
    "charge": ("a heavy iron orc helmet with a red crest and two jutting tusks below it, lowered and rushing toward the upper "
               "right like a battering ram, red speed lines and a puff of dust behind it", HORDE, "Orc Warriors.png"),
    "horn": ("a large curved war horn (a beast horn bound with iron bands and red rags), its mouth to the upper right, blasting "
             "three jagged red sound waves", HORDE, "Orc Warriors.png"),
}

GRIDS = {
    "2x2": ("a 2 by 2 grid of 4 frames in reading order", "1:1"),
    "4x2": ("a 4 by 2 grid of 8 frames in reading order", "16:9"),
    "4x3": ("a 4 by 3 grid of 12 frames in reading order", "4:3"),
}
BLACK = "solid black (#000000), one single colour, for additive blending. Nothing dark in the effect itself: no smoke, no shadows"
MAGENTA = "solid magenta (#FF00FF), one single colour, for cutting out"

# ability -> (grid, background, frames, colours)
FX = {
    "shieldwall": ("2x2", BLACK,
                   "A looping stance effect along the front edge of one isometric ground tile: a row of three faint, translucent "
                   "kite-shield shapes standing on a thin glowing line, shimmering. Frame 1: dim. Frame 2: brighter, a white "
                   "glint starts on the left shield's rim. Frame 3: brightest, the glint on the middle shield. Frame 4: fading, "
                   "the glint on the right shield.", "Colours: white, pale blue and royal blue."),
    "shieldbash": ("4x2", BLACK,
                   "A one-shot impact where a shield slams into an enemy, the blow coming from the left. Frame 1: a small white "
                   "flash. Frame 2: a jagged white-and-yellow impact star bursts and a blue-white shock crescent opens to the "
                   "right. Frames 3-4: the star at full size, three small sparks fly right, a ring of pale dust spreads on the "
                   "ground. Frames 5-6: the crescent stretches to the right and thins. Frames 7-8: only fading sparks and dust "
                   "specks, nearly empty.", "Colours: white, yellow, pale blue and cream."),
    "shield_charge": ("4x2", BLACK,
                      "A one-shot impact at the moment a charging shield wall crashes into an enemy front, the charge coming "
                      "from the lower left. Frame 1: a bright white point. Frame 2: a wide blue-white shock crescent bursts "
                      "across the front, facing the upper right. Frames 3-4: the crescent at full width, pale wood splinters "
                      "and bright sparks scatter toward the upper right. Frames 5-6: the crescent breaks into streaks, the "
                      "splinters fall. Frames 7-8: a few sparks and splinters fading out.",
                      "Colours: white, pale blue, royal blue, gold sparks and pale wood."),
    "defend": ("4x2", BLACK,
               "Row 1, frames 1-4, a looping stance effect: a faint dome of gold light over one isometric ground tile, its rim "
               "a thin gold ellipse on the ground, two thin gold lines running out from the rim to the left and right (they "
               "link the guard to the squads it protects), slowly pulsing brighter and dimmer. Row 2, frames 5-8, a one-shot "
               "block: a bright gold-white flash bursts at the centre, a ring of light expands from it and fades, small gold "
               "sparks fly outward.", "Colours: white, pale gold and warm gold."),
    "spearwall": ("4x2", BLACK,
                  "Row 1, frames 1-4, a looping stance effect: a thin gold line lies on the ground in an open arc along the "
                  "front and both sides of one isometric tile, small upward steel-white glints of spear tips flicker along it, "
                  "a different glint brightest in each frame. Row 2, frames 5-8, a one-shot trigger when an enemy steps in: a "
                  "sharp red-and-white flash where the spears strike, three steel-white thrust streaks pointing to the upper "
                  "right, sparks, then fading.", "Colours: white, steel grey, warm gold and a touch of red."),
    "square": ("4x2", BLACK,
               "Row 1, frames 1-4, a looping stance effect: a thin square of pale gold light lies on the ground around one "
               "isometric tile (seen from the high camera it is a flat diamond), a bright steel glint runs around its edge, a "
               "quarter of the way in each frame. Row 2, frames 5-8, a one-shot effect when a charge breaks on the square: "
               "bright white-and-steel spear-impact sparks burst on one face, a short jagged crack of light, then fading "
               "sparks.", "Colours: white, steel grey, pale gold and warm gold."),
    "pikethrust": ("4x2", BLACK,
                   "A one-shot thrust that reaches two tiles: a long, thin steel-white streak shoots from the lower left to the "
                   "upper right across the whole cell. Frame 1: a short streak at the lower left. Frames 2-3: the streak "
                   "lengthens toward the upper right. Frame 4: it reaches the far end and a small sharp white impact star "
                   "appears there. Frames 5-6: the star bursts with a few sparks. Frames 7-8: the streak and the star fade.",
                   "Colours: white, steel grey and pale yellow."),
    "overwatch": ("2x2", BLACK,
                  "A looping stance effect: a translucent gold wedge (a cone of watch) lying flat on the ground, opening from a "
                  "point at the lower left toward the upper right, with a thin brighter edge, and a small gold open-eye glyph "
                  "floating above its point. Frames 1-4: the wedge pulses slowly from dim to bright to dim while a faint line "
                  "of light sweeps across it from left to right.", "Colours: pale gold, warm gold and white."),
    "aimed_shot": ("4x2", BLACK,
                   "Row 1, frames 1-4, the bolt in flight toward the upper right: a bright steel bolt with a gold-white streak "
                   "trailing behind it, the streak longer in each frame. Row 2, frames 5-8, the impact: a small, sharp, "
                   "precise white flash with a thin gold ring around it, the ring expanding and thinning, a few tiny sparks, "
                   "then gone.", "Colours: white, warm gold and steel grey."),
    "heavybolt": ("4x2", BLACK,
                  "Row 1, frames 1-4, the heavy bolt in flight toward the upper right: a thick steel bolt with a long white "
                  "streak and a faint shock ring around its tip. Row 2, frames 5-8, the impact: armour bursts open with a "
                  "bright white-orange flash, steel fragments and orange sparks spray outward, then fade.",
                  "Colours: white, steel grey, orange and yellow."),
    "charge": ("4x2", MAGENTA,
               "A one-shot impact when an orc warband crashes in after a run, coming from the lower left. Frame 1: a red flash. "
               "Frame 2: a jagged red shock crescent bursts across the front, facing the upper right. Frames 3-4: a heavy "
               "brown dust cloud bursts on the ground with stones and red sparks. Frames 5-6: the dust rolls outward and the "
               "crescent breaks up. Frames 7-8: the dust thins and settles.",
               "Colours: blood red, bright red, earth brown and dust beige."),
    "warcry": ("4x2", BLACK,
               "A one-shot shout that carries four tiles: a ring of red shockwave lying flat on the ground, small at the centre "
               "at first and growing to fill the cell, with jagged red sound-wave lines rising above it. Frame 1: a red flash at "
               "the centre. Frames 2-6: the ring grows wider and thinner, the sound waves rise and spread. Frames 7-8: the ring "
               "fades at the edge of the cell.", "Colours: bright red, blood red, orange and white."),
    "chain_lightning": ("4x2", BLACK,
                        "A one-shot lightning strike from the sky onto one spot. Frame 1: a thin white line flickers down from "
                        "the top. Frame 2: the full bolt strikes, a white core with electric blue branches, a bright flash where "
                        "it hits the ground. Frame 3: the brightest frame, a blue-white burst on the ground. Frame 4: the bolt "
                        "flickers with new branches. Frames 5-6: two short arcs crackle sideways from the impact toward the "
                        "left and right edges of the cell. Frames 7-8: crackling sparks fade.",
                        "Colours: white, pale blue, electric blue and a touch of violet."),
    "frost_blast": ("4x2", BLACK,
                    "A one-shot blast of ice on one squad. Frame 1: a cyan point of light. Frames 2-3: jagged ice shards burst "
                    "outward in a star. Frame 4: a ring of frost crystals forms flat on the ground around the centre and ice "
                    "spikes jut up. Frames 5-6: the spikes crack and fine white frost drifts. Frames 7-8: a few glittering ice "
                    "motes and a pale frost ring on the ground, still faintly visible in frame 8 (it becomes the chilled mark).",
                    "Colours: white, pale cyan, ice blue and deep blue."),
    "healing_light": ("4x2", BLACK,
                      "A one-shot heal on one squad. Frame 1: a thin golden-white line of light descends from the top. Frames "
                      "2-3: it widens into a soft column of gold-white light reaching the ground, a bright gold ellipse on the "
                      "ground. Frames 4-6: green-gold motes rise inside the column, small white sparkles. Frames 7-8: the "
                      "column fades from the bottom up and the last motes rise and vanish.",
                      "Colours: warm white, pale gold, gold and fresh green."),
    "mending_circle": ("4x2", BLACK,
                       "A one-shot healing circle: a ring of runes lying flat on the ground. Frame 1: a small bright ring at "
                       "the centre. Frames 2-3: the ring expands to fill the cell and runes appear along it. Frames 4-6: soft "
                       "light rises from the ring like a short curtain and motes float upward. Frames 7-8: the light and the "
                       "runes fade, a few motes remain.", "Colours: white, pale gold, green-gold and fresh green."),
    "fireball": ("4x3", BLACK,
                 "Row 1, frames 1-4, a looping fireball flying to the right: a white-yellow core, orange flames and a red tail "
                 "streaming to the left, the flames different in each frame. Rows 2-3, frames 5-12, the explosion on the "
                 "ground: frame 5 a white-yellow flash; frames 6-7 a round burst of orange fire with a bright core; frames 8-9 "
                 "the burst at its biggest, flames licking up, embers flying; frames 10-11 it breaks into tongues of flame and "
                 "red embers; frame 12 a few embers and a faint glow on the ground.",
                 "Colours: white, yellow, orange, fire red and dark red."),
    "bloodlust": ("4x2", BLACK,
                  "Row 1, frames 1-4, a one-shot onset: a red flash, then veins of red light branch upward from the ground "
                  "like flames and a ring of red sparks bursts out. Row 2, frames 5-8, a looping aura for the squad while the "
                  "frenzy lasts: a low ring of red mist on the ground with red sparks and small red flame tongues rising, "
                  "pulsing.", "Colours: bright red, blood red, orange and a touch of white."),
    "gutripper": ("4x2", MAGENTA,
                  "Frame 1: a sickly green hex sigil (a crude spiked circle) flashes in the air. Frames 2-3: three ragged dark "
                  "red claw slashes tear diagonally through it. Frame 4: blood spurts from the slashes. Frames 5-6: the sigil "
                  "crumbles into green and black flecks and blood drops fall to the ground. Frames 7-8: a looping bleeding "
                  "mark, two drops of blood dripping down (frames 7 and 8 alternate).",
                  "Colours: dark red, blood red, sickly green and black."),
    "hurl_stone": ("4x3", MAGENTA,
                   "Row 1, frames 1-4, a looping stone in flight: a big round rough grey stone tumbling, turned a quarter turn "
                   "in each frame, a few pale specks behind it. Rows 2-3, frames 5-12, the impact on the ground: frame 5 the "
                   "stone hits and brown earth sprays up; frames 6-8 a heavy dust cloud bursts outward with flying stone chips "
                   "and clods; frames 9-11 the dust rolls out and settles; frame 12 a small ring of scattered rubble remains.",
                   "Colours: stone greys, earth brown and dust beige."),
    "lob_rock": ("4x3", MAGENTA,
                 "Row 1, frames 1-4, a looping boulder in flight: a huge jagged dark boulder with patches of moss, cruder and "
                 "bigger than a cut stone, tumbling a quarter turn in each frame. Rows 2-3, frames 5-12, the impact on the "
                 "ground: frame 5 the boulder smashes down and red-brown earth sprays up; frames 6-8 a heavy dust cloud bursts "
                 "outward with rock shards and clods; frames 9-11 the dust rolls out and settles; frame 12 a small ring of "
                 "broken rock remains.", "Colours: dark stone greys, moss green, red-brown earth and dust beige."),
    "growl": ("4x3", BLACK,
              "Rows 1-2, frames 1-8, a one-shot growl rolling out two tiles: a low shockwave ring lying flat on the ground, "
              "small at the centre at first and growing to fill the cell, the ground inside it darkened by a violet shade, "
              "jagged violet sound-wave lines rising along the ring; in frames 7-8 the ring fades at the edge and the shade "
              "lifts. Row 3, frames 9-12, a looping 'cowed' glyph that hangs over a cowed enemy: a small drooping violet "
              "banner on a short pole, hanging limp, bobbing slightly down and up.",
              "Colours: pale violet, violet, deep purple and a touch of white."),
    "hound_charge": ("4x2", MAGENTA,
                     "A one-shot impact when the royal hounds hit at full tilt, coming from the lower left. Frame 1: a gold "
                     "streak. Frames 2-3: a sweeping gold slash arc cuts from the lower left to the upper right. Frame 4: a "
                     "bright gold-white flash at the point of contact. Frames 5-6: a burst of black-and-white fur tufts and "
                     "pale dust spreads outward. Frames 7-8: the tufts drift down and fade.",
                     "Colours: white, warm gold, black, grey and dust beige."),
    "lick_wounds": ("4x2", BLACK,
                    "A quiet looping heal, played on each hound: soft green-gold motes rise slowly from the ground and fade as "
                    "they climb, a few white sparkles twinkle, and a faint warm ellipse glows on the ground and pulses gently; "
                    "frame 8 leads back into frame 1.", "Colours: warm white, pale gold, green-gold and fresh green."),
}

# (heading, abilities in kit order, note)
SECTIONS = [
    ("The royal army", None, None),
    ("Footmen", ["shieldwall", "shield_charge", "defend", "shieldbash"], None),
    ("Spearmen", ["spearwall", "square", "pikethrust"], None),
    ("Crossbowmen", ["overwatch", "aimed_shot", "heavybolt"], None),
    ("Border Collie Royal Guard", ["growl", "hound_charge", "lick_wounds"],
     "Defend is the footmen's skill with the same icon and effect: see Footmen."),
    ("Battle Mages", ["chain_lightning", "frost_blast", "healing_light", "mending_circle"], None),
    ("Mangonel", ["hurl_stone"], None),
    ("The horde", None, None),
    ("Orcs", ["charge"], None),
    ("Orc Warlord", ["warcry"], "The warlord also has Brutal Charge: see Orcs."),
    ("Goblin Shamans", ["fireball", "bloodlust", "gutripper"], None),
    ("Rock Lobber", ["lob_rock"], None),
]

STYLE = ("STYLE: genuine, expertly crafted pixel art, not a painting with a pixelation filter: designed on a 32 by 32 pixel grid "
         "and shown scaled up so every pixel is a large crisp square. Clean deliberate pixel clusters, a one-pixel dark brown "
         "outline (#2B1D10) around every shape, flat colours with one shadow and one highlight step, light from the top left, "
         "no anti-aliasing, no blur, no gradients, no dithering.")
FORM = ("FORM: one bold subject centred in the square, filling about 80% of it, with a clear silhouette that still reads at "
        "26 pixels on screen; at most three main shapes, no fine detail, no scenery.")
ICON_BG = ("BACKGROUND: perfectly flat solid magenta (#FF00FF), one single colour, for cutting out. No frame, no border, no "
           "button, no vignette, no shadow on the background, no text, no letters, no numbers.")
FX_STYLE = ("STYLE: genuine pixel art, chunky deliberate pixel clusters with hard edges, a limited palette of about eight "
            "colours, glow drawn as stepped bands of solid colour rather than soft gradients; no anti-aliasing, no blur, no "
            "photographic effects, no lens flare. Effects on the ground lie flat on it: a circle on the ground looks like an "
            "ellipse twice as wide as it is tall.")
FX_ONLY = ("ONLY THE EFFECT: no soldiers, no creatures, no weapons held by anyone, no ground tiles, no scenery, no text, no "
           "numbers, no grid lines.")


def load(name):
    return json.loads((ROOT / "data" / name).read_text(encoding="utf-8"))


def users(units):
    """ability id -> the units that have it, in data order."""
    out = {}
    for u in units.values():
        for a in u.get("abilities", []):
            out.setdefault(a, []).append(u["plural"])
        if u.get("promotion"):
            out.setdefault(u["promotion"], []).append(u["plural"] + " (promotion)")
    return out


def kind(a):
    if a["description"].startswith("Passive."):
        return "passive"
    if a.get("engine"):
        return "war machine shot"
    return ("ranged " if a.get("ranged") else "") + a["kind"]


def icon_prompt(name, icon):
    subject, colours, ref = ICONS[icon]
    if icon == KEY:
        images = ("Image 1 shows the royal footmen of this game: use it only for the colours and design of their kite "
                  "shields, not its painting style.\n\n")
    else:
        images = ("Image 1 is a finished icon from the same set: match exactly its pixel size, outline weight, shading, "
                  "palette and how much of the square the subject fills, but draw a different subject.")
        if ref:
            images += (" Image 2 shows the troops who use this skill: use it only for their colours and equipment, not its "
                       "painting style.")
        images += "\n\n"
    return (f"MERIDIUS — PIXEL-ART ABILITY ICON: {name.upper()}\n\n"
            "A single square ability icon for the skill bar of an isometric fantasy tactics game.\n\n" + images +
            f"SUBJECT: {subject}.\n\n{colours}\n\n{FORM}\n\n{STYLE}\n\n{ICON_BG}")


def fx_prompt(name, aid):
    grid, bg, frames, colours = FX[aid]
    return (f"MERIDIUS — PIXEL-ART EFFECT SPRITE SHEET: {name.upper()}\n\n"
            "A sprite sheet of one animated battle effect for an isometric fantasy tactics game, seen from a high fixed camera "
            f"about 35 degrees above the ground: {GRIDS[grid][0]}. Each frame sits in its own equal cell, centred on the same "
            "point and at the same scale, with wide empty space around it; nothing crosses a cell edge.\n\n"
            f"FRAMES: {frames}\n\n{colours}\n\n{FX_STYLE}\n\n{FX_ONLY}\n\nBACKGROUND: perfectly flat {bg}.")


def attach_icon(icon):
    ref = ICONS[icon][2]
    if icon == KEY:
        return f"image 1 `{REFS}{ref}`"
    out = f"image 1 your chosen `icon_{KEY}.png`"
    return out + (f", image 2 `{REFS}{ref}`" if ref else "")


HEAD = f"""# Meridius: ability icon and effect prompts

22 Oct 2026. One icon prompt and one effect-sheet prompt for every ability in
`source/godot/data/abilities.json`, for **Nano Banana Pro on the Higgsfield
website**. Generated by `source/godot/tools/anim/ability_prompts.py`: change
the subjects or style there and run it again rather than editing this file.

## How to use

- **Use the website, not the MCP or the CLI.** The one-day unlimited Nano
  Banana Pro pass covers standard generation only ("Excludes MCP,
  Supercomputer, Canvas, & CLI"). Through the MCP each image costs 2 credits
  at 2K.
- Settings: Nano Banana Pro, **2K**, the aspect ratio given with each prompt.
  Two run at a time; make 2–4 of each and keep the best.
- **Order:**
  1. The style key, the **Shield Wall icon** (`icon_{KEY}.png`). Redo it until you
     like it: every other icon copies its pixel size, outline and palette.
  2. Every other icon, with that icon attached as image 1 (and the unit sheet
     as image 2 where one is listed).
  3. The effect sheets. Once one looks right, you can attach it as image 1 to
     the rest and add at the top: *"Image 1 is a finished effect sheet of this
     game: match its pixel size, number of colours and pixel-art style exactly;
     draw a different effect."*
- **Save** the keepers to `{INBOX}` under the names given
  (`icon_<icon>.png`, `fx_<ability>.png`; extra takes as `_b`, `_c`). They are
  then snapped to the pixel grid, cut out from the magenta or black
  background, and wired into `assets/icons/` and the effects pass of
  `docs/squad-skills.md`.
- Backgrounds: icons and solid effects (dust, rock, blood) on flat magenta
  for cutting out; glowing effects on black for additive blending.
- The icons are drawn on a 32-pixel grid. The ability button shows them at 26 px
  today (`assets/icons/*.svg`, 24×24), so pixel art needs an integer scale:
  decide at integration whether the button grows to 32 px or the icons are
  redrawn on 24 pixels.
"""


def main():
    abilities = load("abilities.json")["ABILITIES"]
    used = users(load("units.json")["UNIT_TYPES"])
    listed = [a for _, kit, _ in SECTIONS for a in (kit or [])] + ["defend"]
    missing = set(abilities) - set(listed)
    assert not missing, f"abilities without a section: {sorted(missing)}"
    assert not set(abilities) - set(FX), f"abilities without an effect: {sorted(set(abilities) - set(FX))}"
    icons = {a["icon"] for a in abilities.values()}
    assert not icons - set(ICONS), f"icons without a subject: {sorted(icons - set(ICONS))}"

    out = [HEAD, "## All abilities\n",
           "| Ability | id | Kind | Used by | Icon | Effect sheet |", "| --- | --- | --- | --- | --- | --- |"]
    for _, kit, _ in SECTIONS:
        for aid in kit or []:
            a = abilities[aid]
            out.append(f"| {a['name']} | `{aid}` | {kind(a)} | {', '.join(used.get(aid, []))} | `icon_{a['icon']}.png` | "
                       f"`fx_{aid}.png` |")
    out.append(f"\n{len(abilities)} abilities, {len(icons)} icons (Hurl Stone and Lob Rock share one), "
               f"{len(abilities)} effect sheets.\n")

    done = set()
    for title, kit, note in SECTIONS:
        if kit is None:
            out.append(f"## {title}\n")
            continue
        out.append(f"### {title}\n")
        if note:
            out.append(f"{note}\n")
        for aid in kit:
            a = abilities[aid]
            out.append(f"#### {a['name']} · `{aid}`\n")
            out.append(f"*{kind(a).capitalize()}. {', '.join(used.get(aid, []))}.* {a['description']}\n")
            icon = a["icon"]
            if icon in done:
                out.append(f"**Icon:** shared, `icon_{icon}.png` above.\n")
            else:
                done.add(icon)
                out.append(f"**Icon** → `icon_{icon}.png` · 1:1 · attach: {attach_icon(icon)}\n")
                out.append("```text\n" + icon_prompt(a["name"], icon) + "\n```\n")
            out.append(f"**Effect** → `fx_{aid}.png` · {GRIDS[FX[aid][0]][1]} · no attachment\n")
            out.append("```text\n" + fx_prompt(a["name"], aid) + "\n```\n")

    DOC.write_text("\n".join(out), encoding="utf-8")
    print(f"wrote {DOC} ({len(abilities)} abilities, {len(done)} icons)")


if __name__ == "__main__":
    main()
