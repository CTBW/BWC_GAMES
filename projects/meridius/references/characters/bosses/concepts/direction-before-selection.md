# Meridius: colossal boss encounters

23 October 2026 · Concept proposal, not implemented gameplay or established canon.

The company should feel small, but its decisions should feel powerful. A shield
line receives a blow meant for the entire company; the reserves replace it; the
crossbows hold their fire until a mountain of armour opens. Victory comes from
controlling where catastrophe lands and deciding who can survive it.

## User direction

- Large, imposing, difficult encounters built around positioning, ground AoEs,
  attack sequences, movement and choosing which squad takes which hit.
- Usually one boss. All seven proposals here use one enemy and one shared health
  pool. Body parts and arena objects do not take independent enemy turns.
- Epic proportions and a believable place in Meridius's universe.
- Match the rendering style of the images generated on Higgsfield. Those images
  are **style references only**, not prescribed locations, scenery or compositions.
- The river-guardian idea has been replaced by corrupted dryads. The proposed
  encounter is Edratha, a colossal corrupted dryad matriarch.
- Preserve the original giant-spider Widow and add an Arachne variant: an adult
  female upper body organically joined to a complete spider lower body. This is
  an alternate visual form of the same encounter, not an eighth boss fight.
- Add a blood-crawler boss inspired by the supplied small Drova image. Its
  blood fungus slowly corrupts and undermines the surrounding land. Use the
  image as a creature motif, not as a new rendering-style target.
- Continue the Terrain & Battlefield image workflow only after its work finishes
  and its generation session is released. Ability icons remain paused.

## Grounding in the existing game

Current campaign data establishes Amberfeld Garrison, the Hillsvain Host, the
Hillsvain Woods, the Vattern, Brannsted and the Margrave's riders. Earlier world
direction names Nordmark and the cult of the Great Tyrants, whose symbol is an
eye inside a triangle. These are anchors; the named bosses and their histories
below are new proposals. These encounters would be optional hunts or later
campaign objectives, rather than silently replacing the existing last stand.

The company normally fields up to six squads. Soldiers share a squad HP pool;
losses reduce its damage and healing does not resurrect the dead. Facing comes
from the final step of movement. Defend catches ordered melee/missile attacks
against adjacent allies, but not spells, AoEs or reaction attacks. Square prevents
pushes and makes attacks frontal. War machines cannot fire after moving.

References checked: `source/godot/data/campaigns.json`, `data/units.json`,
`scripts/rules/battle.gd`, `docs/squads.md`, `docs/squad-skills.md`,
`docs/plan-phase-1.md`, and `docs/magic-and-machines.md`. Historical documents
describe the old TypeScript implementation; Godot data and rules govern current
behaviour. No game files were changed for this concept pass.

## A turn-based raid language

Every dangerous boss action shows its target, affected cells, impact order and
resolution turn before the player commits. One boss beat means one complete
company turn followed by the advertised boss resolution. There are no real-time
reaction checks. Several attacks may resolve in one beat, but their order is
numbered and fixed; the player gets the whole turn to solve the combination.

1. **Announce.** Show the next beat and a lighter preview of the following beat.
   A locked ground area never follows a moved squad. A marked-unit attack is
   visibly different and previews its new footprint whenever that squad moves.
2. **Plan.** Inspect damage, likely casualties, facing, displacement destinations,
   cover loss and future hazards. End Turn has an optional unresolved-danger
   summary, not repeated confirmation dialogs.
3. **Resolve.** Execute the numbered actions, then ordinary aftermath. No secret
   extra swing, retargeting or phase-transition attack after the player commits.
4. **Recover.** Announce the next beat. Every major sequence has a recovery beat
   that rewards attacking the exposed boss or restoring the formation.

### Five distinct orders

| Order | Ground language | Player decision |
| --- | --- | --- |
| Evacuate | Solid outline, crosshatching, impact number | Leave every marked cell. |
| Intercept | Arrow with a shield notch and a clearly shown stopping cell | Place one suitable squad in the hit's path, or use Defend when the attack explicitly permits it. |
| Share | Linked outlined stations with numbered participant slots | Occupy the stated separate tiles; a squad is one participant regardless of its soldier count. |
| Bait | Target marker and a dashed prospective footprint | Choose where a tracked attack will be deposited; it locks at the displayed step. |
| Shelter | Hatched occlusion shadow behind a named object | Reach genuine protection with sufficient capacity for the company. |

Shapes, labels and resolution numbers carry meaning alongside colour. A shared
hit is a new encounter rule, **not** an undocumented extension of Defend. AoEs
remain AoEs. Shield Wall and Defend are alternative stances; do not require both
on one squad. A designated guard is determined by current rules (highest HP,
then uid), so the forecast must show which adjacent guard will actually intercept.

### Heavy hits with meaningful survival

Use absolute damage values tuned to campaign tier; never secretly scale an attack
to the victim's current HP. The intent is a few costly signature impacts, with
movement and facing determining the rest. A correctly handled hit may still fell
soldiers. Repeated unavoidable losses must not make a depleted company unwinnable.

For a paper example only, a level-one footman squad has 192 HP (six at 32). A
post-mitigation hit of 45 leaves 147 HP and five soldiers; healing can only refill
those five soldiers' shares. This is why a warning cannot merely say "healable
damage." Preview casualties and cumulative loss. That number is an illustration,
not an approved boss damage value.

Target a typical hunt of 10–14 boss beats, with two or three major hit-assignment
moments and recovery between them. Initially test no-mage companies, no-machine
companies, depleted squads, injured movement and different front-line mixes.
Abilities improve solutions but must not make one exact roster mandatory. Arena
braces and shelter provide alternatives when a particular stance is unavailable.
Hard modes can later remove forgiving options after the base encounters work.

### Fair movement and phases

- Mark the boss's entire collision footprint, swept movement path and landing
  footprint. An illustration's leg span is not its navigable footprint.
- Never move the boss through occupied squads without a forecast displacement
  rule. Retreats use vacated lanes or wait; body overlap is not a hidden attack.
- Warn new lethal terrain at least one full company turn ahead. Do not combine
  forced movement with an unseen hazard. Falling into a void is never an
  unannounced instant kill.
- Account for zones of control and facing changes. A safe cell is not a fair
  solution if reaching it requires an unforecast lethal free attack.
- Telegraph a phase at the next announcement; finish or explicitly cancel the
  old sequence. Crossing an HP threshold does not add damage in the same beat.
- Each boss has a distinct movement rule. No generic teleporting to the nearest
  ranged squad and no permanent safe position behind every boss.
- A failed share or intercept hurts, but its first failure should usually leave
  a recovery decision. Reserve encounter-ending attacks for extensively warned
  repeated failures or a late soft enrage.

## Roster and first production pass

| Boss | Encounter identity | Core question |
| --- | --- | --- |
| Rauk, the Last Bell | Grey siege ogre carrying a stolen bell tower | Which two squads take the swing, and who replaces them? |
| The Widow of the King's Road | Giant arachnid weaving the battlefield | Which routes will still be open after the next pull? |
| Edratha, Mother of the Blight | Colossal corrupted dryad matriarch | Who bears the blight, and where can it be safely planted? |
| The Oath-Eater | Giant wolf-man wearing broken royal heraldry | Who intercepts the hunt without trapping the marked squad? |
| Veyr, the Cinder-Crowned | Ancient dragon with a furnace-like breast | Where will the company shelter after it chooses the breath lane? |
| The Crown Beneath the Hill | Buried tyrant whose emerging body forms the arena | Can both wings of the company execute one plan across a moving battlefield? |
| The Sanguine Delver | Colossal blood-crawler carrying a fungal ecosystem | Where can you afford to wound it without losing your next route? |

Detailed moves, phases, opening sequences, counters and image prompts are in
`../review/boss-concepts/catalog.mjs` and the generated `boss-concepts.md`.
The Workspace presentation is `workspace/2026-10-20_meridius/bosses.html`.

Start art with one encounter composition for each boss plus the Arachne Widow
variant, eight images total for seven encounters. The alternate Widow has a
female head, torso and two arms, an organic waist-to-carapace transition, eight
spider legs and no human legs. Her hand-weaving changes attack presentation;
retain the original Widow's mechanics and arena for a direct comparison.
The Sanguine Delver comes first to explore the latest supplied creature motif.
Rauk, Edratha and Veyr follow: heavy flesh/metal, corrupted organic wood, and a
winged creature establish useful stylistic range. Then the Widow, Oath-Eater
and Crown, placing the Arachne immediately after the original Widow. Extra
poses, isolated bodies, parts and animation sheets
come after selecting a concept; the initial queue does not silently multiply
into a full asset-production run.

## What a prototype must prove

Begin implementation with Rauk only, in a later authorised game-development task.
It proves large footprints, fixed intents, a two-station shared hit, guarded
attacks, timed debris, movement previews and a phase change without seven bespoke
systems at once. Keep rule state pure and seeded; render only recorded outcomes.

Acceptance must include: a new player can explain the warning; a valid route
exists for an ordinary six-squad company; damage forecasts match execution;
Defend and AoE rules remain distinct; shared damage resolves once per squad;
phases cannot double-act; forced movement respects Square and obstruction; the
camera shows the full relevant telegraph; a depleted company has meaningful
retreat and recovery choices. Then test attrition over a full expedition.

Artwork acceptance is separate: complete creature anatomy, imposing but readable
scale, the intended silhouette, coherent light, sufficient arena space, accurate
reference rendering, and no imported terrain composition. A successful image
generation is not an implemented or balanced encounter.
