"""What each battle figure looks like and how it fights, for squadgen.py and prompts.py.

Keys are the game's figure types (data/units.json `sprite`, escorts and crews).
  plural, noun   words for the prompts
  sheet          painted design reference in projects/meridius/references/characters (or None)
  design         what to draw (the game's current figures and the painted sheets agree on it)
  hands          what each figure holds in which hand, as seen in the front view
  people         the six (or fewer) individuals of a sheet, in reading order
  attack         thrust | chop | smash | crossbow | bow | cast | horn | crew | charge
  height         drawn height head to feet, native pixel-art pixels (a man is 190)
  grid           (columns, rows) of the sheet; one figure per cell
  aspect         generation aspect ratio for that grid
  shield         True: the figure leads with a shield when mirrored, so it needs its
                 own south-east and north-west drawings (battle_view.pose_key); others
                 are mirrored for those facings.
"""

GOB = "realistic goblin proportions, not chibi: lean, wiry and slightly hunched, long thin limbs, heads about one fifth of their height, small narrow yellow eyes under a heavy brow, long hooked noses, long pointed ears; "
HUMAN_KIT = "royal-blue cloth, cream tunics, blue trousers, brown leather boots, gloves, belts and pouches"

UNITS = {
    "footman": dict(
        noun="footman", plural="royal footmen", sheet="Footmen.png",
        design=("human footmen of the royal army: royal-blue hoods and long shoulder cloaks, cream medieval tunics, " + HUMAN_KIT),
        hands="a straight steel sword in the right hand and a blue kite shield with a silver rim and a white heraldic eagle on the left arm",
        people=["a young clean-shaven man with short brown hair", "a young blond man", "a man with dark swept-back hair and a short dark beard",
                "an older clean-shaven man with short brown hair", "a young man with short black hair", "a man with auburn hair and an auburn beard"],
        attack="chop", height=190, grid=(3, 2), aspect="1:1", shield=True),
    "spearman": dict(
        noun="spearman", plural="spearmen", sheet="Pikemen.png",
        design=("human pikemen of the royal army: royal-blue hooded scarf-cloaks over the shoulders, cream tunics with a long blue tabard "
                "bearing a white heraldic eagle, " + HUMAN_KIT + ", leather bracers and greaves"),
        hands="a tall ash spear with a steel leaf-shaped head and blue binding, held upright in both hands, butt on the ground",
        turn_hands="a tall ash spear with a steel leaf-shaped head held upright in his right hand on his right side, the side toward the viewer, its butt on the ground",
        people=["a man with brown hair and a short brown beard", "a man with dark hair and a full dark beard", "a young man with red-brown hair",
                "a young man with short black hair", "a young blond man", "an older man with grey-streaked brown hair and stubble"],
        attack="thrust", height=196, grid=(3, 2), aspect="1:1", shield=False),
    "crossbowman": dict(
        noun="crossbowman", plural="crossbowmen", sheet="Crossbowmen.png",
        design=("human crossbowmen of the royal army: royal-blue hoods, cream padded gambesons with a blue tabard bearing a white heraldic eagle, "
                + HUMAN_KIT + ", a quiver of bolts at the hip"),
        hands="a wooden crossbow with a steel bow held across the body in both hands, pointing forward and down",
        back_hands="a wooden crossbow carried at his right side in both hands, its front end pointing forward toward the upper right, away from the viewer",
        people=["a man with brown hair and a short beard", "a young blond man", "a man with dark hair and a moustache",
                "a young man with short black hair", "a man with auburn hair and a beard", "an older bald man with a grey beard"],
        attack="crossbow", height=190, grid=(3, 2), aspect="1:1", shield=False),
    "militia": dict(
        noun="militiaman", plural="village militiamen", sheet=None,
        design=("a village levy called to arms: peasants in patched brown, green and grey wool tunics, rope belts, brown hose, leather shoes, "
                "a few with a padded jerkin or a dented old kettle helmet"),
        hands="a farm tool used as a weapon, held in both hands: pitchforks, a wood axe, a hay scythe, a flail, a boar spear, a cudgel",
        people=["a stout bald man with a pitchfork", "a young lad with a wood axe", "a grey-bearded old man with a hay scythe",
                "a red-haired man in a kettle helmet with a flail", "a dark-haired man with a boar spear", "a burly man with a cudgel"],
        attack="chop", height=186, grid=(3, 2), aspect="1:1", shield=False),
    "collie_guard": dict(
        # Its painted sheet was pasted into the result as scenery; the game figures and the words suffice.
        noun="royal guard", plural="border collie royal guards", sheet=None,
        design=("anthropomorphic border collie dog-knights standing upright like men: black and white fur, a white blaze and muzzle, black nose, "
                "amber eyes, a white chest ruff, a feathered tail; black steel plate armour with gold trim"),
        hands="a long steel sword in the right hand and a black kite shield with a gold eagle on the left arm",
        people=["a collie with both ears pricked", "a collie with folded ears", "a collie with one ear folded",
                "a grizzled older collie", "a young collie with a broad blaze", "a collie with a scar over one eye"],
        attack="chop", height=196, grid=(3, 2), aspect="1:1", shield=True),
    "battle_mage": dict(
        noun="battle mage", plural="battle mages", sheet=None,
        design=("human war wizards of the royal army: long royal-blue robes with a hood and gold trim, a brown leather belt with pouches, "
                "a white shawl collar, soft boots"),
        hands="a tall wooden staff topped with a pale blue crystal in the right hand",
        people=["a grey-bearded old mage", "a dark-haired woman mage", "a young clean-shaven mage with red hair",
                "a bald mage with a black beard", "a blonde woman mage", "a middle-aged mage with a brown beard"],
        attack="cast", height=196, grid=(3, 2), aspect="1:1", shield=False),
    "engineer": dict(
        noun="engineer", plural="siege engineers", sheet=None,
        design=("human siege engineers: blue work tunics with crossed brown leather straps, white linen coifs, brown leather aprons, "
                "tool belts, brown trousers and boots"),
        hands="a heavy wooden mallet in the right hand",
        people=["a stocky bearded engineer", "a young engineer", "a grey-haired master engineer",
                "an engineer with a red beard", "a lean dark-haired engineer", "a burly bald engineer"],
        attack="crew", height=186, grid=(3, 2), aspect="1:1", shield=False),
    "goblin_spear": dict(
        noun="goblin spearman", plural="goblin spearmen", sheet="Goblin spearmen.png",
        design=("vicious green-skinned goblins of the horde, " + GOB +
                "dark hooded leather jerkins, red rags and loincloths, a few in crude, rusty, dented helmets hammered together from scrap, no plumes"),
        hands="a crude spear with a jagged iron head held forward in both hands",
        left_hands="a crude spear held level in both hands, its jagged iron head pointing forward toward the UPPER LEFT, the way he faces",
        back_hands="a crude spear held level in both hands at his right side, its jagged iron head pointing forward toward the UPPER RIGHT corner, away from the viewer, the butt end behind him toward the viewer",
        people=["a goblin in a rusty, dented scrap helmet", "a hooded goblin", "a goblin with a red head rag",
                "a goblin in a rusty riveted helmet", "a scarred goblin with one torn ear", "a goblin with a bone in his topknot"],
        attack="thrust", height=140, grid=(3, 2), aspect="1:1", shield=False, rel=("orc_warrior", 2 / 3), skin_sat=0.46),
    "goblin_archer": dict(
        noun="goblin archer", plural="goblin archers", sheet="Goblin archers.png",
        design=("green-skinned goblins of the horde, " + GOB + "black pointed hoods, "
                "dark leather jerkins, red rag skirts, a quiver of black-fletched arrows on the back"),
        hands="a short recurve bow in the left hand",
        people=["a goblin in a black hood", "a goblin with a red head rag", "a hooded goblin with a bone necklace",
                "a goblin with a torn ear", "a goblin with a feathered hood", "an older wrinkled goblin"],
        attack="bow", height=138, grid=(3, 2), aspect="1:1", shield=False, rel=("orc_warrior", 2 / 3), skin_sat=0.46),
    "goblin_rabble": dict(
        noun="goblin", plural="ragged goblin swarmers", sheet=None,
        design=("scrawny, wild green-skinned goblins of the horde, " + GOB +
                "ragged leather straps over bare green chests, rag loincloths, bare feet, no armour; three of them carry an improvised "
                "shield on the left arm (a barrel bottom in an iron hoop, a splintered nailed plank, a nailed crate lid)"),
        hands="a crude weapon in the right hand: rusty knives, a spiked club, a sharpened bone, a small hatchet, a sickle, a broken sword",
        people=["a goblin with a rusty knife and a barrel-bottom shield", "a goblin with a spiked club",
                "a goblin with a sharpened bone and a nailed plank shield", "a goblin with a small hatchet",
                "a goblin with a sickle and a crate-lid shield", "a goblin with a broken sword"],
        attack="chop", height=124, grid=(3, 2), aspect="1:1", shield=True, rel=("orc_warrior", 2 / 3), skin_sat=0.46),
    "goblin_horn": dict(
        noun="goblin horn-bearer", plural="goblin horn-bearers", sheet="Goblin spearmen.png",
        design=("a goblin war-herald of the horde, " + GOB + "dark spiked leather armour, red rags, a tall red war banner "
                "with a black sun strapped to his back"),
        hands="a huge curved war horn of bone held in both hands",
        left_hands="one huge curved war horn of bone raised to his mouth in both hands, its wide end pointing up toward the UPPER LEFT, the way he faces; a war banner on his back",
        back_hands="a huge curved war horn of bone raised to his mouth in both hands, its wide end pointing up and forward toward the UPPER RIGHT, away from the viewer",
        people=["a goblin herald in a rusty, dented scrap helmet", "a hooded goblin herald", "a goblin herald with a red head rag",
                "a goblin herald in a rusty cooking-pot helmet", "a goblin herald in a bone skull helm", "a goblin herald in a rusty riveted helmet"],
        attack="horn", height=146, grid=(3, 2), aspect="1:1", shield=False, rel=("orc_warrior", 2 / 3), skin_sat=0.46, kin="goblin_spear"),
    "goblin_shaman": dict(
        noun="goblin shaman", plural="goblin shamans", sheet=None,
        design=("goblin witch-doctors of the horde, " + GOB + "antlers and a beast skull worn as a headdress, a dark ragged fur "
                "cloak, bone charms and feathers, a brown leather tunic with skull trinkets"),
        hands="a gnarled bone staff topped with a horned skull in the right hand and a small feathered bone fetish in the left; no shield",
        back_hands="a gnarled bone staff topped with a horned skull, held upright in his right hand on the right side of the image; he carries no shield",
        people=["a shaman with tall antlers", "a shaman with a wolf skull headdress", "an old hunched shaman",
                "a shaman with ram horns", "a shaman with a bird skull mask", "a shaman with painted white face marks"],
        attack="cast", height=150, grid=(3, 2), aspect="1:1", shield=False, rel=("orc_warrior", 2 / 3), skin_sat=0.46, kin="goblin_spear"),
    "orc_warrior": dict(
        # Its painted sheet was pasted into the result as scenery; the game figures and the words suffice.
        noun="orc warrior", plural="orc warriors", sheet=None,
        design=("big, muscular green-skinned orcs of the horde, taller and broader than a man: tusks, heavy brows; iron helmets with a red crest, "
                "dark red scale and leather armour, red cloth, iron bracers, heavy boots"),
        hands="a heavy cleaver-sword in the right hand and a round red wooden shield with an iron boss on the left arm",
        people=["an orc in a crested helmet", "an orc with a scarred face", "an orc with a topknot and no helmet",
                "an orc with a spiked helmet", "an older grizzled orc", "an orc with a nose ring"],
        attack="chop", height=212, grid=(3, 2), aspect="1:1", shield=True),
    "orc_brute": dict(
        noun="orc brute", plural="orc brutes", sheet="Savage Orcs.png",
        design=("huge savage orc berserkers of the horde: bare muscular green chests with a crossed leather harness and skull trophies, "
                "tall red mohawks, huge spiked iron pauldrons, a black fur kilt with red rags, war paint, heavy boots"),
        hands="a massive two-handed spiked club held low in both hands",
        people=["a brute with a red mohawk", "a brute with a braided beard", "a brute with white war paint",
                "a brute with a scarred chest", "a brute with an iron jaw", "a brute with bone piercings"],
        attack="smash", height=214, grid=(3, 2), aspect="1:1", shield=False),
    "orc_warlord": dict(
        noun="orc warlord", plural="orc warlords", sheet="Savage Orcs.png",
        design=("the giant orc warlord of the horde, a head taller than his warriors: a horned iron helmet, heavy dark red plate armour with "
                "spikes, a black fur mantle, two red war banners on poles strapped to his back, trophies of skulls"),
        hands="a huge iron war-axe held in both hands",
        people=["a warlord with tusks and a horned helmet", "a warlord with a scarred face", "a warlord with a braided black beard",
                "a grizzled one-eyed warlord", "a warlord with a skull-crested helmet", "a warlord with a crown of spikes"],
        attack="chop", height=236, grid=(3, 2), aspect="1:1", shield=False),
    "troll": dict(
        noun="troll", plural="moss trolls", sheet="Trolls.png",
        design=("hulking, massive forest trolls, twice the height of a man, hunched so far forward that their knuckles nearly reach the ground: huge rounded shoulders and a great hump, the head hanging low and forward, deep-set small yellow eyes under a heavy brow, a huge long drooping nose, long stringy grey-black hair; "
                "huge hunched forest trolls, twice the height of a man: a mass of dark hair with a thick moss cap, twigs and orange fungus on the "
                "hump, big pale arms with teal spiral markings, bark-wrapped shins, bare toed feet, a long drooping nose, small yellow eyes"),
        hands="an uprooted mossy tree log carried over the shoulder in both hands",
        back_hands="an uprooted mossy tree log carried over his right shoulder in both hands, its far end pointing toward the upper right",
        people=["a troll with a huge moss cap", "a troll with a stringy beard", "a troll with orange fungus on his shoulders"],
        # Twice the height of the figure they replace: huge and intimidating on the field.
        attack="smash", height=250, grid=(3, 1), aspect="16:9", shield=False, rel=("troll", 2.0)),
    "wolf_rider": dict(
        noun="wolf rider", plural="goblin wolf riders", sheet=None,
        design=("a goblin raider riding a huge warg: the warg is a dog-legged grey-brown wolf with hackles, a snarling jaw, a brush tail with a "
                "dark tip, a leather harness and a trophy skull; the goblin rider wears dark leather and red rags"),
        hands="the goblin rider holds a short spear in his right hand and the reins in his left",
        people=["a grey warg with a hooded rider", "a brown warg with a rider in a rusty dented helmet", "a dark warg with a rider in a red head rag",
                "a pale warg with a rider in a rusty dented helmet"],
        attack="charge", height=200, grid=(2, 2), aspect="1:1", shield=False, skin_sat=0.46),
    # The Margrave's relief at dawn: drawn only (it never fights or falls), so no deaths.
    "margrave_rider": dict(
        noun="lancer", plural="mounted knights of the Margrave", sheet=None, mount="warhorse",
        design=("human knights riding armoured warhorses: steel kettle helmets, mail shirts with steel breastplates, blue surcoats, "
                "long blue saddle cloths with a white star, the horses with steel chamfrons and leather barding"),
        hands="the knight holds a long lance with a blue pennant in his right hand and the reins in his left",
        back_hands="the knight's long lance with a blue pennant held in his right hand, tilted forward toward the upper right",
        left_hands="a long lance with a blue pennant held upright, tilted forward toward the upper left; his warhorse has exactly one head, its head and neck toward the upper left and its tail toward the viewer",
        people=["a bay warhorse with a bearded knight", "a grey warhorse with a young knight", "a black warhorse with a grizzled knight",
                "a chestnut warhorse with a knight in a crested helmet"],
        attack="charge", height=240, grid=(2, 2), aspect="1:1", shield=False, deaths=False),
}

FACING = {
    "f": "front three-quarter view, turned toward the LOWER LEFT of the image",
    "b": "rear three-quarter view seen from behind, turned toward the UPPER RIGHT of the image, back toward the viewer",
    "fs": "front three-quarter view, turned toward the LOWER RIGHT of the image",
    "bs": "rear three-quarter view seen from behind, turned toward the UPPER LEFT of the image, back toward the viewer",
}
TOWARD = {"f": "toward the lower left", "b": "toward the upper right", "fs": "toward the lower right", "bs": "toward the upper left"}


def facings(unit):
    if UNITS[unit].get("kind") == "engine":
        return ["e"]
    return ["f", "fs", "b", "bs"] if UNITS[unit]["shield"] else ["f", "b"]


# War machines: one sheet each, 2 x 2 (front ready, front loosing; back ready,
# back loosing), a pixel-art conversion of the game's drawings.
ENGINES = {
    "ballista": dict(noun="ballista", plural="ballistas", height=150,
                     design="a royal field ballista: a heavy oak frame on two spoked wheels, a huge blue-painted bow with gold fittings, "
                            "twisted rope springs, a long iron-tipped bolt, a small blue pennant with a white star"),
    "mangonel": dict(noun="mangonel", plural="mangonels", height=170,
                     design="a royal mangonel: a tall oak A-frame painted royal blue with gold caps, four small wheels, a throwing arm with a "
                            "sling cup and a stone, a rope windlass, a blue pennant with a white star"),
    "rock_lobber": dict(noun="rock lobber", plural="goblin rock lobbers", height=180,
                        design="a crude goblin catapult of lashed logs, bone and skull trophies tied to it, a counterweight sack, a heap of "
                               "rocks in its cup, a ragged red war flag"),
    "war_wagon": dict(noun="war wagon", plural="goblin war wagons", height=190,
                      design="a goblin war wagon: a wooden cart bristling with iron spikes and wooden stakes, an iron ram plate with great "
                             "spikes at the front, skulls nailed on its sides, two ragged red war flags"),
}
for _k, _v in ENGINES.items():
    _v.update(kind="engine", grid=(2, 2), aspect="1:1", shield=False, sheet=None, people=[], attack="engine")
    UNITS[_k] = _v
