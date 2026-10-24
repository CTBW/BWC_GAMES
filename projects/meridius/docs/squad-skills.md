# Meridius: squad skills

Godot only, 22 Oct 2026. Every company squad type has its own kit of skills
on the ability bar (keys 1–4). Skills are abilities in `data/abilities.json`,
the kits are `abilities` (and `promotion`) in `data/units.json`, and the rules
are in `scripts/rules/battle.gd`. Squads, HP pools and arcs work as in
`squads.md`.

Status: **rules, AI, HUD and icons implemented and tested**
(`tests/unit/test_squad_skills.gd`). Animation frames and the effects described
under "Visual direction" are **not implemented yet**: the squad sprites and
their frame animations are being made in a separate session first.

## Kits

| Squad | Keys 1–4 | Promotion (Training Yard, Veteran) |
| --- | --- | --- |
| Footmen | Shield Wall, **Charge**, **Defend** | Shield Bash (key 4) |
| Spearmen | Spearwall, **Square** | Pike Thrust |
| Crossbowmen | Overwatch, **Aimed Shot** | Heavy Bolt |
| Border Collie Royal Guard | **Growl**, **Charge**, **Defend**, **Lick Wounds** | **Howl** (replaces Growl on key 1) |

New skills in bold. The Royal Guard used to borrow the footmen's Shield Wall
and Shield Bash; it now has its own four. Its four keys are full, so its
promotion **upgrades** a skill instead of adding one: an ability with
`upgrades: "<id>"` takes that ability's place on the bar
(`Soldier.kit(type_id, promoted)`, used by `abilities_of`). Every other
promotion is added at the end as before. Saves keep working: kits are read
from the data, never stored.

Owner decisions (23 Oct 2026): Defend is a bodyguard that catches one blow per
stand; Shield Bash stays the footmen's promotion; the Royal Guard's promotion
is Howl; no rebalancing for now.

## The skills

| Skill | id | Kind | Effect | Cooldown |
| --- | --- | --- | --- | --- |
| Charge (footmen) | `shield_charge` | melee attack | Needs a run of 2+ tiles this turn. +30% damage, +5 to hit, +10 morale shock. | 3 |
| Charge (Royal Guard) | `hound_charge` | melee attack | Needs a run of 2+ tiles. +20% damage, +12 to hit, +14 morale shock. | 2 |
| Defend | `defend` | stance | Until the squad's next turn it guards every friendly squad beside it: the first attack or shot ordered against one of them strikes the guard instead, always on its front (shield counts). | — |
| Square | `square` | stance | Until the next turn: no flank or rear (every attack is frontal), first strike against anyone closing in from any side, charges lose their bonus, cannot be pushed, +6 defense, −10 ranged defense. | — |
| Growl | `growl` | shout | Enemies within 2 tiles lose 12 morale and are **cowed** until the end of their next turn (−10 to hit). | 3 |
| Howl (Royal Guard promotion) | `howl` | shout | Replaces Growl. Enemies within 3 tiles lose 16 morale and are cowed until the end of their second turn. | 3 |
| Lick Wounds | `lick_wounds` | shout (self) | Heals 3–5 per hound standing, ends bleeding and chill, +6 morale. Not with an enemy beside the squad. The fallen stay dead. | 3 |
| Aimed Shot | `aimed_shot` | ranged attack | Only in a turn the squad has not moved. +20 to hit; ignores cover, an obstructed view and troops in the way; +6 morale shock. | 2 |

Rules details:
- **Charge** uses the existing move-then-strike order: choose Charge, point at
  an enemy, and the squad runs to the side under the cursor and strikes. The
  run is `movedTiles` this turn, so a squad that already moved 2+ tiles and
  stands beside the enemy can charge too. The forecast says "Needs a run of at
  least 2 tiles" when it is too short. Spearmen still strike first at chargers
  from the front (from any side in a square).
- **A square breaks a charge**: against a squad in Square, Charge keeps only a
  plain attack (forecast row "Charge broken by the square"), and the orcs'
  passive Brutal Charge loses its +3 damage and +8 morale too.
- **Defend** catches only attacks ordered against the ward (`attack()`), melee
  or missile. Free attacks, spearwall and overwatch reactions, first strikes and
  spells are not caught. Each guard catches **one blow per stand**: catching
  one sets `guardSpent` on the guard, and later attacks reach their target (the
  forecast shows it). The flag clears at the start of the guard's turn and when
  it takes a stance again. A squad that stands guard itself is never guarded
  (no chains). With two guards beside a ward, the one with the most HP steps
  in (then by uid), so two guards catch two blows. Where the blow lands (range, sight, cover, height, the
  ward's ground) stays the ward's; who takes it (defense, shield, armour, HP,
  morale) is the guard. `Battle.guard_of(a, t, opts)`; `preview()` returns
  `guard: <uid>` when the numbers are the guard's; the attack event carries
  `ward: <uid>` and the log says "X step in front of Y!".
- **Square** is implemented in `arc_of()`: a squad in square has only a front,
  so free attacks (zones of control) also reach all round it.
- **Cowed** is a condition like chilled (`statuses`), shown on squad cards
  ("Cowed", −10 to hit until the end of its turn). It applies to melee and
  missile attacks; spells are unaffected.
- **Lick Wounds** is a shout with `selfHeal`, `selfMorale`, `cleanse` and
  `calm` (`Battle.can_shout` gives the reason it is unavailable). Like any
  act, the squad may still move afterwards if it has not moved yet.
- **Aimed Shot** uses `still` (no move this turn) and `ignoreCover`. "Steady
  aim" (+8) still applies on top.

## Automation (company autoplay and simulator)

`scripts/rules/ai.gd`: attack skills are weighed like any attack ability (a
charge only where the run is long enough, an aimed shot only from where the
squad stands). Growl is used when two or more foes are within its 2 tiles
(Howl: its 3);
Lick Wounds when the squad is below 65% HP with no enemy beside it, if it did
nothing else. A squad takes its first stance in its kit when threatened, as
before: Shield Wall for footmen, Spearwall for spearmen, Defend for the guard.
The enemy AI has none of these skills but reads guards and squares through
`preview()` like everything else.

## Icons

`assets/icons/<icon>.svg` (24×24, imported at 4×), in the set's language: a
dark ink outline (`#2b1d10`), flat fills from the HUD palette, one light from
the top left. They are drawn for the 26 px icon on the brown ability button.

| Icon | Reads as |
| --- | --- |
| `shield_charge` | The company's blue kite shield driven forward, gold speed lines, an impact flash at its edge. |
| `defend` | A shield raised in front of a comrade, under a gold arc of protection. |
| `square` | The formation on its isometric tile, spears out of every face. |
| `growl` | A black-and-white collie head in the royal gold collar, fangs bared, red growl waves. |
| `howl` | The same head tipped up toward a crescent moon, three red waves instead of two. |
| `hound_charge` | A gold paw print at full tilt with speed lines. |
| `lick_wounds` | A tongue under a white muzzle, a green healing cross and sparkles. |
| `aimed_shot` | A bolt driven into the centre of a target, gold aiming marks around it. |

**On the battlefield** (24 Oct 2026): beside each squad's health bar, a
stance shows the icon of the skill that takes it (Shield Wall `shield`,
Spearwall `spearwall`, Overwatch `eye`, Defend `defend`, Square `square`;
looked up from the abilities' `stance`), on a 22 px dark badge with a gold
rim. A condition shows the icon of the skill that lays it, rimmed in the
condition's colour: chilled `frost`, bloodlust `blood`, bleeding `gut`,
cowed `growl`. Fleeing, the leader's ★, Warchief and the horn countdown stay
words. A stance or condition without an icon falls back to its word.
`battle_draw.gd` (`draw_overlays`, `stance_icon`, `STATUS_ICON`, `BADGE`).

**Painted icons** (24 Oct 2026): the badges use the painted pixel-art icons
(`Icon.painted(name)`, `assets/icons/painted/<icon>.png`, 128 px with
mipmaps), falling back to the SVG where none is painted (Howl). The
paintings are 2048 px on a magenta chroma-key ground ("<Ability> - Icon.png",
kept out of Git in the repository's `local/ability-icons/`);
`tools/ui_key_icons.py [--src <folder>]` keys them (colour difference against a
per-row estimate of the ground, so Growl's pink haze and Square's darker
ground key too), unmixes the edges, crops Shield Bash's frame and shrinks each
to its shape. The stone's shadow and the fireball's glow were painted as
tints of the magenta and are recoloured (`TINT`): a dark ground shadow and an
orange glow. Lob Rock is the same painting as Hurl Stone (`stone`). The
ability bar still shows the SVGs.

## Events for animation and effects

What each skill emits, in order, for the view to play back (the rules never
wait for it):

| Skill | Events |
| --- | --- |
| Charge | `move` (2+ tiles; may be cut short by reactions) → optional `attack` with `reaction: "firstStrike"` from spearmen → `attack` with `ability: "shield_charge" \| "hound_charge"` → morale, falls. |
| Shield Bash | `attack` with `ability: "shieldbash"` → `push` (or a log "holds its ground" against a square). |
| Defend | `stance: "defend"` (lasts until `stance: null` at the start of the squad's turn). When it takes a blow: a log line, then `attack` with `target: <guard>` and `ward: <ward>`. |
| Square | `stance: "square"` (until `stance: null`). |
| Growl | `shout` (`ability: "growl"`) → `morale` per enemy → `status` `cowed` on (and off at the end of their turn). |
| Howl | As Growl with `ability: "howl"`; `status` cowed carries `turns: 2` and goes off at the end of their second turn. The view plays it in Growl's branch (without one it falls through to the War Cry's effect and sound). |
| Lick Wounds | `shout` (`ability: "lick_wounds"`) → `heal` (`reason: "Lick Wounds"`) → `status` off for bleeding/chill → `morale`. |
| Aimed Shot | `attack` with `ranged: true`, `ability: "aimed_shot"`. |

Howl in the view (`source/godot/scripts/render/battle_view.gd`, the `"shout"`
case, owned by the animation session; applied 24 Oct 2026):

```gdscript
elif e.ability == "growl" or e.ability == "howl":
	# Growl's rings are sized for its 2 tiles; Howl reaches 3.
	var k: float = float(ab.get("radius", 2)) / 2.0
	fx.ring(p.x, p.y, 150 * k, "rgba(170,110,230,0.9)", 0.8)
	fx.ring(p.x, p.y, 105 * k, "rgba(60,30,80,0.8)", 0.6)
	# … the rest of Growl's branch unchanged (text, shake, roar, focus, hop).
```

## Visual direction (not implemented)

The bar for these is high: each skill should be unmistakable at normal
battle zoom and feel spectacular without hiding the squads or the field. The
notes below follow the effect workflow (purpose, shape, colour, attachment,
timing, lifecycle) and are the brief for the effects pass once the new
squad frames exist. Timings are illustrative until measured on the real
frames.

- **Charge (footmen)** — the shield wall becomes a battering ram. Run: a low
  dust wake per pair of boots, growing with the run; the formation leans in.
  Contact (one-shot, at the first shield's contact frame): a blue-white shock
  crescent across the target's front, splinters and sparks, a short camera
  punch, the target squad rocked back a few pixels. Morale shock shown as the
  usual red number, larger.
- **Charge (Royal Guard)** — speed and grace, not weight. Bounding run with
  gold motion streaks off the armour; at the leap, a brief slow-motion beat
  (0.1–0.15 s), then a gold slash arc and fur/dust burst at contact.
- **Defend** — continuous: a faint gold shield dome over the guard and every
  ward beside it, linked by thin gold lines on the ground (only while the
  stance lasts; fades out at `stance: null`). On a caught blow: the guard
  dashes half a tile toward the ward and back, a bright shield flash and ring
  at the point of the block, "Guarded!" text.
- **Square** — continuous: the men face outward, spear tips catch a steel
  glint that runs round the formation every few seconds; a thin square of
  light on the tile. When a charge breaks on it: spear-impact sparks on that
  face and "Broken!" over the charger.
- **Growl** — one-shot: a low violet shockwave rolling out exactly two tiles
  (the rule's radius), the ground darkening briefly under it; cowed foes
  flinch back and a small drooping violet glyph hangs over them while cowed.
  Sound: real dog growls (`roar_collie_guard`, in place), not the War Cry.
- **Howl** — Growl's bigger sibling: the hounds lift their heads, a pale
  moon-silver wave rolls out three tiles with a violet core, a longer hold
  (about 1.2 s) and a cold rim light on the cowed foes. Sound: a pack howl
  rising over the growl.
- **Lick Wounds** — quiet and warm: the hounds sit, soft green-gold motes rise
  from each, wounds close with the existing heal number; bleeding and frost
  visibly wash off.
- **Aimed Shot** — one-shot: the crossbowmen kneel, a thin gold sight line
  draws from squad to target over the aim hold, the world desaturates very
  slightly for the hold, then one sharp synchronized release with a bright
  bolt trail and a precise impact flash.

Sounds (audio session, 22 Oct 2026): Growl plays `roar_collie_guard` (dog
growls and snarls), Lick Wounds a `lick` (lapping) on its shout, and Shield
Wall, Spearwall, Square and Overwatch have their own stance sounds. A guard's
caught blow plays `block`. Still to come: a heavier shield impact for the
footmen's Charge and a crank-and-release for Aimed Shot (both need the attack's
ability id at the sound call).

Effect lifecycles: stance effects (Defend, Square) live exactly as long as the
stance and are removed on `stance: null`, rout, fall or battle end; cowed's
glyph follows the `status` on/off events; everything else is one-shot and
owned by its event. None of them changes a rule outcome.

## Checks

- `tools/test.sh test_squad_skills` (17 tests: kits, promotions and icons,
  charge runs and bonuses, square arcs/first strike/push/broken charges, guards
  for melee and shots, their exclusions and one blow per stand, growl, howl and
  cowed, lick wounds, aimed shot, and both sides on automation through every
  encounter using the new skills).
- Battle parity traces (77, their setups carry the old kits) are identical, so
  the rule changes alter nothing else.
- Balance: see `source/godot/MIGRATION.md`, "Squad skills".
