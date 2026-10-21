# Meridius: phase one plan

Outcome: a polished, browser-playable vertical slice of an isometric roguelike
tactics RPG in which the player prepares an expedition at a frontier garrison,
marches across a randomised campaign map, fights turn-based battles, returns
home, and grows the base and roster.

## What we take from the inputs

### Reference images (`projects/meridius/references`)

- **Look:** detailed painterly pixel-illustration, not flat cel shading. Warm
  sunlit greens and golds, earthy dirt patches, cool green-blue shadows, dark
  but not black outlines, small grounded details (flowers, grass tufts, mossy
  stones).
- **Camera:** high-angle isometric diorama, light from the upper left. Every
  battlefield asset shares that camera.
- **Player faction:** blue and cream tabards with a white eagle, brown leather,
  steel. Footmen carry swords and eagle kite shields; spearmen carry tall spears
  (the "Pikemen" sheet); crossbowmen wear hooded blue cloaks and carry quivers.
- **Enemies:** goblin spearmen and archers (green skin, black hoods, red rags,
  red war paint, a skull banner), orc warriors (spiked pauldrons, red-plumed
  helmets, red round shields). Savage orcs and moss trolls are later tiers.
- **Battlefields:** an open clearing ringed by dense mixed forest, rock
  outcrops, ruined stone walls, fences, a river with a bridge and a waterfall.
  The fighting area is calm and readable; the detail sits at the border.
- **World and tone:** Nordmark, a northern frontier. Goblin raids are becoming
  disciplined (lore 2) and a cult of the Great Tyrants (the eye in a triangle)
  stirs in the background (lore 3). Parchment and ink set the UI tone.
- **Rule from the art skill:** the user's reference art is canonical. Where the
  concept-art skill's "toy-like cel shading" text disagrees with the reference
  images, the images win.

### Workspace skills used

| Skill | Used for |
| --- | --- |
| `plan` | This document: deliverables and acceptance checks. |
| `fal-ai-generation`, `image-reference-workflow`, `meridius-concept-art` | Sprite, terrain, building and UI art, with references assigned by role, one camera for all grid assets, cut-out-ready plain backgrounds, receipts kept. |
| `game-level-design` | Battle maps as layers (terrain, height, cover, passage, deployment) with stable IDs. |
| `game-ui-workflow` | Real-state HUD, hover/disabled/empty states, no click-through, narrow viewports. |
| `game-vfx-workflow` | Hit, miss, death and rout effects bound to real combat events. |
| `game-animation-integration` | Key poses and procedural motion bound to the combat event clock. |
| `game-audio-workflow` | A small event-driven sound bank (optional in phase one). |
| `gameplay-visual-review` | Fixed-seed captures from the actual game for each review loop. |

### Darkest Dungeon and similar games

Darkest Dungeon's loop works because every expedition costs something and
feeds something:

- **Two currencies of loss.** Health and stress both carry between fights, so
  an expedition is a resource-management problem, not a string of fights.
- **Provisioning is a bet.** Unused supplies are wasted money; too few create a
  crisis. Dungeon length and region hints make it an informed bet.
- **Retreat is always available and always costs.** You keep loot, you fail the
  objective.
- **The hamlet converts loot into permanent power** (heirlooms upgrade
  buildings), so even a failed run makes progress.
- **Disposable people, valuable veterans.** A wide roster, a recruit coach that
  refreshes, permadeath, and level-gated dungeons (high-level heroes refuse easy
  ones) push the player to develop many units rather than one squad.
- **Downtime has a price.** Recovery in town costs money and benches the hero.

Battle Brothers adds what fits an army setting: morale states that break and
rout, losses that spread fear to neighbours, zones of control, spearwall and
shieldwall as formation tools, and a company whose named veterans matter.

**Our version:** a captain's company of named soldiers based at Amberfeld
Garrison. The two carried-over pressures are wounds and morale, plus fatigue
and supplies (rations, bandages, bolts, torches, tools). Army size is capped
by unit slots and command points; veterans cost more points. Loot is silver
and materials (timber, iron, war trophies) that upgrade buildings.

## Phase one scope

Mandatory:

1. **Home base** in isometric view: Command Tent, Barracks, Training Yard,
   Armoury, Infirmary, Quartermaster. Each has levels driven by data (cost,
   effect, visuals).
2. **Recruitment** (pool refreshes after each expedition, quality scales with
   the Barracks), **roster** (stats, level, XP, wounds, morale, equipment,
   abilities) and **upgrades** (XP levels, promotions with new abilities,
   weapon and armour tiers, repairs, injury treatment).
3. **Expedition preparation:** campaign choice with hints (enemies, terrain,
   length, rewards), 6 unit slots, a command-point budget, supplies bought
   with silver within wagon capacity, level-based reluctance.
4. **One easy campaign tier** ("The Hillsvain Raids"): a short, randomised,
   branching node map in isometric view. Nodes: battle, ambush, scouting point,
   abandoned village, event, camp, final objective. Supplies are consumed while
   marching; wounds, morale and fatigue carry over; retreat is possible.
5. **Battles** on an isometric grid: facing, flanks and rear attacks, height,
   cover, difficult ground, line of sight, zones of control, morale and rout,
   permadeath with a survival roll. Two battle maps (forest clearing, river
   ruins) with randomised props, plus an ambush variant.
6. **Three player units** (Footmen, Spearmen, Crossbowmen) and three enemies
   (Goblin Spearman, Goblin Archer, Orc Warrior, with an orc warband leader
   for the objective). Readable sprites with idle, move, attack, hit, death
   and rout feedback.
7. **Return home**: rewards, casualties report, XP, then the next expedition.
8. **Save and continue** in the browser.

Optional, after the slice is good: generated sound bank and music,
video-derived frame animation, a second campaign tier.

## Technical approach

- **Browser game** in TypeScript with Vite, in `projects/meridius/source/game`.
  Canvas 2D for the isometric world (pre-rendered terrain layers, depth-sorted
  sprites, particles, lighting overlays); React DOM overlay for menus and HUD.
  Chosen over Godot because it allows fast scripted play-tests and screenshots
  with Playwright and fast logic tests; Godot stays an option for later.
- **Data-driven content** in `src/data`: units, enemies, abilities, equipment,
  supplies, buildings, campaigns, node types, encounter tables, events,
  injuries, names, battle maps. Systems read only from these tables.
- **Deterministic seeded RNG** so a campaign or battle can be replayed for
  tests and visual comparisons.
- **Debug API** on `window.__meridius` for automated play-tests; a headless
  simulator runs many battles and campaigns to tune balance.
- **Art pipeline:** fal generation with the reference images as identity and
  style input, plain-background sprites, background removal, a manifest of
  prompts, request IDs and hashes in `source/art`. A procedural placeholder
  look keeps the game playable before and during generation. Sprite masters
  are PNG in `source/game/art/sprites`; the game loads WebP copies made by
  `scripts/art/publish.py` (see `source/game/art/ART_PLAN.md`).

## Stages and acceptance checks

| Stage | Output | Shows it works |
| --- | --- | --- |
| 1. Rules core | Battle logic, AI, morale, unit tests | Tests pass; headless AI-vs-AI battles finish with plausible outcomes |
| 2. Battlefield | Rendered iso battle with HUD and input | Full player battle playable; screenshot compared with `Battlefield 1.png` |
| 3. Campaign | Generated node map, events, camps, supplies | Fixed-seed campaign played start to objective and to retreat |
| 4. Base | Buildings, recruit, roster, upgrades, prep | New game to first expedition and back with persistent changes |
| 5. Art | Generated sprites, terrain, buildings, UI art | Side-by-side captures against the reference sheets |
| 6. Loops | Review notes, fixes, balance runs | Three full cycles played; win/loss and economy numbers recorded |

Do not call the slice done until the full loop has been played repeatedly and
the captures hold up next to the references.

## The endless horde (21 October 2026)

The battles were reworked around an endless horde and facing that comes only
from movement: waves, new enemies, last stands on large maps, and the host's
march on the campaign map. Plan, code map and lessons: `docs/plan-horde.md`.

## Lessons from the play-test loops

- **Camp layout.** The two gate towers stand on the south-east wall and are
  about four metres tall, so on screen they cover a column of the camp behind
  them. Nothing important may sit in that column; the training yard moved to
  the east corner for this reason. Front-row buildings need a wide horizontal
  offset from the ones behind them, because level 3 buildings are tall.
  `scripts/art/baselayout.py --levels all` checks all 729 level mixes offline
  (hidden share per building, nameplate clashes); `scripts/basepick.mjs`
  confirms in the game that hovering picks the visible building.
- **Enemy decisions.** An attack is taken when its expected value clears a bar
  (damage and morale both weighted by hit chance). Confident and steady troops
  take any such attack and choose the safest tile for it; shaken and wavering
  troops attack only when the whole plan, position included, clears the bar.
  A unit that ends its move within reach strikes anyway, since attacks cost
  nothing. Before this rule, a good attack from a dangerous tile was dropped
  entirely and the unit stood beside the enemy doing nothing.
  `scripts/aidiag.ts` measures passed-up attacks, idling, archers in melee,
  lone attackers, attack arcs and reactions walked into.
- **Rules run ahead of the animation.** The AI resolves a whole enemy turn
  instantly and the scene plays it back afterwards. Anything on screen that
  describes the battle state (turn, side, enemies standing) must come from the
  playback, not from the rules object.
- **Squads (October 2026).** Every unit is a squad of six (trolls three) with
  one HP pool; soldiers fall at each share and squad damage is soldiers ×
  damage per soldier. The rules roll damage once and send `strikers`,
  `aliveBefore` and `aliveAfter` in the attack event; the renderer only plays
  that back, so animation can never multiply damage. Permanent losses made the
  campaign much harder until each fallen soldier got the old survival roll
  after the battle (field triage). Spec and checks: `docs/squads.md`.
