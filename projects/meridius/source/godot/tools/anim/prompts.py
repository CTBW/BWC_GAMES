"""Prompts for the squad sheets (Nano Banana Pro, 2K), built on the footman's.\n\nWhat worked for the footmen (knowledge/higgsfield-setup.md):\n- a finished pixel-art sheet as the style reference also fixes layout and facing;\n- an edit that changes only the action keeps every figure where it was drawn,\n  so the frames register by grid slot;\n- a pose must be clearly different from the input and visible from the camera,\n  or the edit comes back unchanged;\n- south-east and north-west views come back mirrored (weapon in the wrong\n  hand): mirror the south-west or north-east sheet and ask only for the hands\n  to be swapped;\n- no shadows, no effects, flat grey background.\n"""
import re

from units import FACING, TOWARD, UNITS

TAIL = ("Genuine crisp pixel art, no anti-aliasing, no motion blur, no speed lines, no magic effects, no glow, no dust, "
        "no shadows, no ground, no text.")
STYLE = ("STYLE: genuine, expertly crafted pixel art exactly like image 1, not a painting with a pixelation filter: clean deliberate "
         "pixel clusters, precise one-to-two-pixel dark outlines, pixel-level highlights and cloth folds, controlled dithering, crisp "
         "hard pixel edges, no anti-aliasing, no blur. Rich but controlled palette. Realistic proportions, not chibi.")
BACKGROUND = ("BACKGROUND: perfectly flat, plain, solid light grey (#C8C8C8), one single colour. No shadows, no ground, no text, "
              "no labels, no numbers, no grid lines, no frames.")


def _sides(fac):
    """Which side of the image each hand is on."""
    if fac in ("f", "fs"):
        return "his right hand is on the left side of the image and his left hand on the right side"
    return "his right hand is on the right side of the image and his left hand on the left side"


def _layout(u):
    cols, rows = u["grid"]
    n = cols * rows
    if rows == 1:
        return f"{n} separate full-body figures in one row, evenly spaced"
    return f"a {cols} by {rows} grid of {n} separate full-body figures ({cols} in each row), evenly spaced"


def _people(u):
    cols, rows = u["grid"]
    ppl = u["people"][: cols * rows]
    if rows == 1:
        return "Left to right: " + "; ".join(ppl) + "."
    out = []
    for r in range(rows):
        out.append(f"row {r + 1}, left to right: " + "; ".join(ppl[r * cols:(r + 1) * cols]))
    return "In reading order, " + "; ".join(out) + "."


def base_front(unit):
    """The squad in the front view, from the style sheet and the design references.\n    Inputs: 1 the footman style sheet in this layout, 2 the game's figures of this\n    unit in this layout, 3 the painted design sheet (when there is one)."""
    u = UNITS[unit]
    painted = ("Image 3 is a painted design reference of the same unit: follow its design, equipment and colours, but not its "
               "painting style, scenery or poses. " if u["sheet"] else "")
    return (
        f"MERIDIUS — PIXEL-ART {u['plural'].upper()} SQUAD SPRITE SHEET\n\n"
        f"A pixel-art sprite sheet for an isometric fantasy strategy game: {_layout(u)}, with wide empty space between them, "
        "nothing overlapping and nothing cropped, one figure centred in each cell.\n\n"
        "Image roles: image 1 is a finished pixel-art sprite sheet of this game (royal footmen). Copy from it exactly the layout "
        "(one figure in each cell at the same place), the fixed high orthographic isometric camera about 35 degrees above the ground, "
        "the facing of every figure (" + FACING["f"] + "), and its pixel-art style: pixel size, outline weight, shading and detail. "
        "Do not copy its soldiers: draw a different unit. "
        f"Image 2 shows the same {u['plural']} as they look in the game now, in the same layout: copy their design, colours and "
        "equipment, and redraw them in the far more detailed pixel-art style of image 1. " + painted + "\n\n"
        f"THE UNIT: {u['design']}. Each holds {u['hands']}; {_sides('f')}. "
        + ("" if u["shield"] else "Nobody carries a shield, and nothing of the footmen's kit is copied: no kite shields, no eagle "
           "emblems, no swords. ")
        + "All stand in the same ready stance, feet on the ground, "
        f"about {u['height']} pixel-art pixels tall from head to feet (a man in image 1 is about 190). Six different individuals of the "
        f"same unit with cohesive equipment and small individual details. {_people(u)}\n\n" + _kin(u) + STYLE + "\n\n" + BACKGROUND)


def _kin(u):
    """A finished sheet of the same race in this game, for proportions and style (the last image)."""
    if not u.get("kin"):
        return ""
    n = 4 if u["sheet"] else 3
    return (f"Image {n} shows goblins of the same horde already finished for this game. Match them exactly in body proportions, "
            "head size (about one fifth of the height), small narrow eyes, long noses, lean wiry build, skin colour and pixel-art "
            "style; draw your own unit, not theirs.\n\n")


def base_back(unit):
    """The same individuals seen from behind. Inputs: 1 this unit's front sheet,\n    2 the footman style sheet seen from behind in this layout."""
    u = UNITS[unit]
    return (
        f"Pixel-art sprite sheet for an isometric fantasy strategy game, matching image 1 exactly in pixel-art style, pixel size, "
        f"outline weight, palette and figure scale.\n\nImage 1 shows {_layout(u)}: {u['plural']} in a front three-quarter view. "
        f"Draw the SAME individuals, each in the same cell and at the same size, now seen from behind: {FACING['b']}, exactly like the "
        "figures in image 2. Use image 2 only for the view, the layout and the pose; do not copy its soldiers.\n\n"
        f"We see each figure's back, the back of the head and his right side: {_sides('b')}. Each still holds "
        f"{u.get('back_hands', u['hands'])}, now seen from behind. Keep every individual's hair, headgear, clothes, colours and "
        "equipment exactly as in image 1.\n\n" + orientation(unit) + "\n\n" + STYLE + "\n\n" + BACKGROUND)


def _mirror_hands(text):
    """The hands of a figure drawn mirror-reversed (left and right swapped)."""
    return re.sub(r"\b(left|right)\b", lambda m: "right" if m.group(1) == "left" else "left", text)


def base_back_turned(unit):
    """The back view at the angle the upper-right march needs on this camera (a step\n    up-right is two pixels right for one up), drawn as its mirror image: turned toward\n    the upper LEFT, everything in the other hand. hfgen.py mirrors each cell (frame\n    base_t). Inputs: 1 this unit's front sheet, 2 soldiers seen straight from behind,\n    3 soldiers in side profile facing left (both only for the angle)."""
    u = UNITS[unit]
    hands = _mirror_hands(u.get("turn_hands", u["hands"]))
    return (
        f"Pixel-art sprite sheet for an isometric fantasy strategy game, matching image 1 exactly in pixel-art style, pixel size, "
        f"outline weight, palette and figure scale.\n\nImage 1 shows {_layout(u)}: {u['plural']} in a front three-quarter view. "
        "Draw the SAME individuals, each in the same cell and at the same size, turned around and walking AWAY from the viewer "
        "toward the LEFT side of the image and a little upward, toward the upper left.\n\n"
        "THE ANGLE, the most important rule. Images 2 and 3 show other soldiers of this game; use them only for the angle, do not "
        "copy them. Image 2 shows soldiers seen straight from behind. Image 3 shows soldiers in side profile facing the left edge. "
        "Draw every figure in the rear three-quarter view between them, closer to image 3 than to image 2: about two thirds of the "
        "way from the straight back view toward the side profile. We see his back and his whole left side: his left shoulder, "
        "left arm, left hip and left leg, and the back and left side of his head with his left ear and the edge of his jaw and "
        "cheek, but not his eyes or mouth. His right shoulder is mostly hidden behind his body. His chest, his feet and everything "
        "he holds point toward the left and slightly upward, the way he walks; his left foot steps forward toward the left.\n\n"
        f"This sheet is drawn mirror-reversed on purpose: each holds {hands}. Keep every individual's hair, headgear, clothes, "
        "colours and equipment exactly as in image 1; nothing doubled and nothing he does not carry in image 1.\n\n"
        + STYLE + "\n\n" + BACKGROUND)


def base_back_left(unit):
    """The back view drawn turned toward the UPPER LEFT, for figures whose weapon the\n    generator keeps pointing left from behind (goblin spears and horns); the sheet is\n    mirrored into the upper-right view (hfgen.py, frame base_l)."""
    u = UNITS[unit]
    return (
        f"Pixel-art sprite sheet for an isometric fantasy strategy game, matching image 1 exactly in pixel-art style, pixel size, "
        f"outline weight, palette and figure scale.\n\nImage 1 shows {_layout(u)}: {u['plural']} in a front three-quarter view. "
        "Draw the SAME individuals, each in the same cell and at the same size, now seen from behind and turned toward the UPPER "
        "LEFT corner of the image, walking away from the viewer.\n\n"
        f"We see each figure's back, the back of his head and his left side. Each holds {u.get('left_hands', u['hands'])}. "
        "Keep every individual's hair, headgear, clothes, colours and equipment exactly as in image 1.\n\n"
        "ORIENTATION, the most important rule: every figure faces the UPPER LEFT corner. The back of his head is toward the "
        "viewer and his face is not visible. His head, chest and everything he holds point toward the upper left, never toward "
        "the right and never toward the viewer. Each figure holds exactly one of each thing he carries in image 1, nothing doubled, "
        "and nothing he does not carry in image 1.\n\n" + STYLE + "\n\n" + BACKGROUND)


def orientation(unit):
    """The rule the back views broke: heads turned to the viewer, weapons and mounts pointing left."""
    u = UNITS[unit]
    mount = u.get("mount", "warg") if u.get("attack") == "charge" else None
    text = ("ORIENTATION, the most important rule: every figure is turned toward the UPPER RIGHT corner of the image and faces away "
            "from the viewer. The back of his head is toward the viewer and his face is NOT visible: no eyes, no nose, no mouth, no "
            "beard from the front, at most the edge of one ear or cheek. He does not look back over his shoulder and does not turn "
            "his head to the side: his head points the same way as his body, toward the upper right. His chest and everything he "
            "holds point forward toward the upper right, never toward the left and never toward the viewer. Give nobody anything "
            "he does not carry in image 1: no shield unless he has one in image 1.")
    if mount:
        text += (f" The {mount} is seen from behind and from its right side: its head and muzzle point toward the upper right corner, "
                 "away from the viewer, and its rump and tail are toward the viewer at the lower left. Its head is never on the left.")
    return text


def swap_hands(unit, fac):
    """A mirrored sheet with weapon and shield put back in the right hands\n    (south-east from the mirrored south-west, north-west from the mirrored north-east)."""
    u = UNITS[unit]
    view = FACING[fac]
    return (
        f"Edit image 1, a pixel-art sprite sheet of separate {u['plural']} on a flat grey background, each in a {view}.\n\n"
        "Every figure in image 1 is drawn mirror-reversed: he holds his shield on his RIGHT arm and his weapon in his LEFT hand. "
        "Fix only that.\n\n"
        f"Redraw every figure so that the shield is on his LEFT arm and the weapon in his RIGHT hand: {_sides(fac)}. "
        f"Each figure keeps the same {view}. Keep everything else exactly as in image 1: the faces, hair, clothes, body pose, height, "
        "position and size of every figure, the pixel-art style and pixel size, the outlines and palette, and the perfectly flat "
        "plain light grey background. Change all figures the same way. " + TAIL)


# A mounted figure's wind-up and blow, per mount.
CHARGE = {
    "warg": lambda to: ("the warg crouches low on its haunches, snarling, ready to spring, and the rider draws his spear back.",
                        "the warg lunges forward " + to + " with its jaws wide open and front paws off the ground, and the rider stabs "
                        "his spear forward " + to + "."),
    "warhorse": lambda to: ("the warhorse gathers itself, head tucked, and the knight levels his lance " + to + ", couched under his arm.",
                            "the warhorse charges " + to + " at full gallop, front hooves off the ground, and the knight drives his "
                            "lance forward " + to + "."),
}


def _action_text(unit, fac, frame):
    u = UNITS[unit]
    to = TOWARD[fac]
    mount = u.get("mount", "warg")
    w = {"thrust": "spear", "chop": "weapon", "smash": "weapon", "crossbow": "crossbow", "bow": "bow", "cast": "staff",
         "horn": "horn", "crew": "mallet", "charge": "spear"}[u["attack"]]
    left_side = "right" if fac in ("f", "fs") else "left"
    right_side = "left" if fac in ("f", "fs") else "right"
    walk = ("is now walking forward " + to + " with a calm marching step, not running, caught at the moment his {lead} foot "
            "(the leg on the {lead_side} side of the image) is planted forward " + to + " and his {back} foot (the leg on the "
            "{back_side} side of the image) is behind him with the heel lifted. Body upright, " + w + " carried ready.")
    if u["attack"] == "charge":
        walk = ("is now trotting forward " + to + ": the " + mount + " is caught in mid-stride with its {lead} forepaw (on the {lead_side} side "
                "of the image) stepping forward and its {back} forepaw back, back legs pushing, the rider upright in the saddle.")
    texts = {
        "walk_a": walk.format(lead="LEFT", lead_side=left_side, back="RIGHT", back_side=right_side),
        "walk_b": walk.format(lead="RIGHT", lead_side=right_side, back="LEFT", back_side=left_side),
        "kneel": ("has just been mortally struck and is collapsing: his knees buckle and he sinks down onto both knees, his upper body "
                  "slumping forward, head drooping, eyes half closed, his weapon arm hanging limp with the weapon resting on the ground. "
                  "No blood. He stays the same size and scale (he is shorter only because he kneels), his knees where his feet were."),
        "down": ("has now collapsed forward and lies dead on the ground, fallen face down " + to + ", seen from the same high isometric "
                 "camera: head and shoulders " + to + ", legs stretched out behind him, one arm flung forward, his weapon on the ground "
                 "beside his open hand. Nothing is raised: the whole body lies flat. No blood. Lying down he is as long as he would be "
                 "tall standing; his hips stay where his knees were."),
        "slump": ("has now collapsed forward onto his hands and knees and is sinking flat onto the ground, face down " + to + ", head "
                  "hanging, his weapon dropped on the ground beside him. No blood. Same size and scale; his knees stay where they were."),
    }
    if u["attack"] == "charge":
        # A mount and its rider fall together; both stay in the picture.
        texts["down"] = ("has now fallen dead: the " + mount + " has collapsed onto its side on the ground, legs stretched out, head "
                         "down, and its rider lies sprawled across its back with his weapon dropped beside them. Both bodies lie flat, "
                         "the " + mount + " as long as it was standing. No blood. Draw each " + mount + " and its rider exactly once.")
        texts["slump"] = ("is sinking down dead: the " + mount + " has dropped onto its belly with its legs folded under it and its head "
                          "low, and its rider slumps forward over its neck. No blood. Same size and scale. Draw each " + mount
                          + " and its rider exactly once.")
    attack = {
        "thrust": ("draws the spear back for a thrust: weight on the back foot, knees bent, the spear pulled back level at his hip with its "
                   "point aimed " + to + ". The spear must be level, not upright as in image 1.",
                   "lunges " + to + " in a wide stance and thrusts the spear forward " + to + " with both arms fully extended, the spear "
                   "level and reaching far forward."),
        "chop": ("raises his weapon high above his head, ready to strike, weight on the back foot. The weapon must clearly be above his "
                 "head, not at his side as in image 1.",
                 "has just swung his weapon down hard in front of him " + to + ": his weapon arm extended forward and down, the weapon low, "
                 "leaning onto his front foot."),
        "smash": ("heaves the weapon up high over his shoulder with both hands, ready to smash it down, leaning back. The weapon must clearly "
                  "be raised high, not held low as in image 1.",
                  "has just smashed the weapon down in front of him " + to + " with both hands, bent forward, the weapon low near the ground."),
        "crossbow": ("raises the crossbow to his shoulder and aims it level " + to + ", cheek against the stock, a bolt loaded.",
                     "has just shot the crossbow " + to + ": the crossbow still at his shoulder, the bowstring released and the bolt gone, "
                     "the front of the crossbow kicking up slightly."),
        "bow": ("draws his bow to full draw, aiming " + to + ": bow arm straight out " + to + ", the drawing hand pulled back to his ear, "
                "an arrow nocked.",
                "has just loosed his arrow " + to + ": the bow arm still extended, the string straight and the arrow gone, the drawing "
                "hand open behind his ear."),
        "cast": ("raises the staff high above his head in his right hand and draws the other hand back, gathering power, leaning back.",
                 "thrusts the staff forward " + to + " and points the open other hand " + to + ", casting a spell, leaning forward."),
        "horn": ("lifts the war horn to his lips with both hands, chest filling with air.",
                 "blows the war horn with all his might, the horn raised high " + to + ", leaning back."),
        "crew": ("raises the mallet high over his shoulder with both hands.",
                 "swings the mallet down in front of him " + to + " as if driving a peg, bent forward."),
        "charge": CHARGE[mount](to),
    }[u["attack"]]
    texts["wind"], texts["hit"] = attack
    return texts[frame]


def engine(unit):
    """A war machine converted to pixel art. Inputs: 1 the game's four drawings of\n    it (2 x 2), 2 the footman sheet for the pixel-art style only."""
    u = UNITS[unit]
    return (
        f"Convert image 1 into pixel art: four drawings of the same war machine for an isometric fantasy strategy game, {u['design']}.\n\n"
        "KEEP EXACTLY from image 1: the 2 by 2 layout, the position and size of each drawing, its camera view and its state. Top row: the "
        "machine in a front three-quarter view facing the lower left, (left) loaded and ready, (right) at the moment it has just loosed "
        "or struck. Bottom row: the same machine seen from behind facing the upper right, (left) ready, (right) loosing. Keep its design, "
        "colours, parts and proportions.\n\n"
        "Image 2 is a finished pixel-art sprite sheet of this game: take ONLY its rendering from it, the exact pixel-art style, pixel size, "
        "outline weight, shading and level of detail; do not draw its soldiers. Make the machine far more detailed than image 1: wood "
        "grain, iron bands, bolts, rope lashings, worn paint.\n\n" + STYLE + " No motion lines, no dust, no effects, no people.\n\n"
        + BACKGROUND)


def clean(unit):
    """Remove scenery the generator pasted in from a painted reference."""
    u = UNITS[unit]
    return (
        f"Edit image 1. It shows separate crisp pixel-art {u['plural']} on a flat light grey background, and somewhere among them a "
        "faded or painted strip of ground, plants, painted figures, shields or weapons that does not belong to the sprite sheet.\n\n"
        "Remove that painted strip and everything that belongs to it, so that the space becomes perfectly flat plain light grey "
        "background, the same single colour as the rest of the background.\n\nKeep every pixel-art figure exactly as it is, pixel for "
        "pixel: same faces, clothes, weapons, shields, poses, positions and sizes. Do not add anything. No shadows, no ground, no text.")


def swap_legs(unit, fac):
    """The other step: an edit of the first step sheet that swaps which foot leads\n    (asked for by name, the generator keeps leading with the same leg)."""
    u = UNITS[unit]
    view = FACING[fac]
    to = TOWARD[fac]
    near = "lower" if fac in ("f", "fs") else "higher"
    return (
        f"Edit image 1, a pixel-art sprite sheet of separate {u['plural']} on a flat grey background, each in a {view}, caught in "
        f"mid-step while walking {to}.\n\n"
        "Change ONLY the legs: swap them. In image 1 one boot of each figure is stepping forward and the other is behind with the heel "
        "lifted. In the new image it is the other way round: the boot that is behind in image 1 now steps forward and is planted, and the "
        "boot that is forward in image 1 is now behind with its heel lifted. Look at each figure: if his forward boot is the one on the "
        "left of his body, the forward boot must now be the one on the right of his body, and the other way round. The forward boot is "
        f"the {near} one in the image.\n\n"
        "Keep everything above the knees exactly as in image 1: face, body, arms, hands, cloak, weapon and equipment, pixel for pixel, "
        "and every figure's position and size. Same pixel-art style, pixel size, outlines and palette, perfectly flat plain light grey "
        "background. Change all figures the same way. " + TAIL)


def action(unit, fac, frame):
    """An edit of this facing's standing sheet (or, for down/slump, of the re-laid\n    kneeling sheet) that changes only the action."""
    u = UNITS[unit]
    view = FACING[fac]
    start = "kneeling" if frame in ("down", "slump") else "standing"
    return (
        f"Edit image 1, a pixel-art sprite sheet of separate {start} {u['plural']} on a flat grey background, each in a {view}; "
        f"{_sides(fac)}.\n\nChange only their action: every figure {_action_text(unit, fac, frame)}\n\n"
        f"He keeps the same {view}, keeps everything in the same hand and stays the same size, his feet at the same height in the image as in image 1. "
        "Keep everything else exactly as in image 1: every face, hair, headgear, clothes and equipment, the position of every figure, "
        "the pixel-art style and pixel size, the outlines and palette, and the perfectly flat plain light grey background. Change all "
        "figures the same way. Each figure stays inside its own space with a clear gap to its neighbours, nothing overlapping and "
        "nothing cropped. " + TAIL)
