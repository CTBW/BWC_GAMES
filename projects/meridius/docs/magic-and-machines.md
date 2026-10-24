# Meridius: magic and war machines

Spellcasters and war machines are squads like any other (one tile, one
facing, one shared HP pool, soldiers falling at each share; see `squads.md`),
three to a squad. Their powers are **spells**: abilities of kind `spell` cast
at a tile, defined in `src/data/abilities.ts` and resolved in
`src/battle/battle.ts`.

## Squads

| Type | Side | Squad | Notes |
| --- | --- | --- | --- |
| `battle_mage` | company | 3 mages | Chain Lightning, Frost Blast, Healing Light; Mending Circle on promotion. Arcane bolts (5–7, range 5, no ammunition) between spells. |
| `goblin_shaman` | host | 3 shamans | Fireball, Bloodlust, Gutripper. Hex bolts (3–5, range 5). |
| `ballista` | company | engine + 3 crew | Bolt 20–26 per crewman, range 9, pierces 80% of armour; the bolt goes on through. |
| `mangonel` | company | engine + 3 crew | Hurl Stone (its plain attack): 10–14 per crewman, range 3–9, splash. |
| `rock_lobber` | host | engine + 3 crew | Lob Rock: 11–16 per crewman, range 3–8, splash, −5 to hit. |
| `war_wagon` | host | engine + 3 crew | Melee 12–17 per crewman, armour 5, charge, smashes squads back (`smash`). |

- A war machine (`crew` in its type) is one engine worked by a crew. The crew
  is the squad: its HP pool, its casualties and its strength; when the last
  crewman falls the engine is left as a wreck. `primary` names the ability a
  machine uses when it simply attacks an enemy (the mangonel's stone).
- **Machines cannot loose in a turn they have moved** (`engine` tag on the
  shot, `engine: true` on the stone): place them, then let them work.
- The **ballista's bolt carries through** (`impale` tag): a hit goes on into
  the next foe up to two tiles behind on the line of the shot, at half the
  damage of the same roll. A wall or one of the shooter's own squads stops it.
- Recruitment: every muster offers one specialist squad (mages twice as often
  as either machine), `SPECIALIST_TYPES` in `src/meta/game.ts`.
- Encounters: `shaman_fire` (shamans with a goblin band, from stage 2),
  `siege_train` (rock lobber and war wagon with a few spears, from stage 3).
  In the last stand a shaman marches with the warchief in place of the moss
  troll; in the refugee stand a shaman may come with the band that crosses
  upstream, in place of its spearmen. New units replace old ones there rather
  than adding to the host: a rock lobber and a shaman together in the last
  stand cost the company about six points of campaign success, so the lobber
  stays out of it.

## Spells

| Spell | Target | Effect (per caster) | Cooldown |
| --- | --- | --- | --- |
| Chain Lightning | enemy in sight, 6 | 9–12, ignores armour; arcs to the nearest other foe within 2 tiles, twice (×0.6, ×0.36) | 2 |
| Frost Blast | enemy in sight, 5 | 5–7, ignores armour; half to enemies beside it; all struck are **chilled** | 3 |
| Healing Light | friendly squad, 5 | heals 8–11, +8 morale | 2 |
| Mending Circle | the casters | every friendly squad within 2 tiles heals 4–6, +5 morale | 3 |
| Fireball | tile in sight, 6 | 7–10, half armour; half to **every** squad beside it, friend or foe; scatters | 2 |
| Bloodlust | friendly squad, 4 | **frenzy** until the end of its next turn, +10 morale | 3 |
| Gutripper | enemy in sight, 5 | 5–7, ignores armour; **bleeding** for 40% of it, twice | 2 |
| Hurl Stone | tile, 3–9, no sight needed | 10–14, 30% armour; 40% to every squad beside it; scatters | – |
| Lob Rock | tile, 3–8, no sight needed | 11–16, half to every squad beside it; scatters; −5 to hit | – |

- **Scaling.** Damage and healing are per caster and multiply by the casters
  standing, armour taken off each caster's share, like any squad attack.
- **One roll.** Each cast makes one hit roll (`spellPreview` chance: caster
  skill + bonus − the target's missile defence, halved for stones; morale,
  melee, chill and darkness modifiers; 5–95%). Then each squad it touches
  takes **one** damage (or healing) roll. The `spell` event lists every squad
  touched with its damage, HP and soldiers before and after; the renderer only
  plays it back.
- **Scatter.** A fireball or a stone that misses lands on one of the eight
  tiles around the one aimed at and strikes whoever stands there, and beside
  it, in full.
- **Healing never raises the dead**: it refills the survivors' shares only.
- Spells need a steady nerve: a wavering squad cannot cast (a machine's stone
  is its plain attack and still flies). Every spell has a cooldown.

## Conditions (`statuses` on a squad)

| Condition | Effect | Ends |
| --- | --- | --- |
| Chilled | half movement (`moveOf`), −10 to hit, −10 defence (+10 to hit it) | end of its own next turn |
| Bloodlust | +10 to hit and +3 damage per soldier in melee, morale losses halved, −8 defence | end of its next turn (2 own turn ends) |
| Bleeding | at the start of each of its turns loses `power` HP (soldiers fall), −3 morale and losses | after two turns |

Chill and frenzy count down at the end of the squad's own turns
(`endOfTurn`), bleeding at the start of them (`bleed`). Events: `status`
(on/off) and `dot`.

## AI (`src/battle/ai.ts`)

- `spellValue` weighs a spell in the same terms as an attack (squad damage in
  one caster's share): harm to foes, harm to friends counted against it ×1.6
  plus a heavy penalty for killing a friendly squad, healing where wounds are
  open (more for squads in contact or below 60%), chill by the threat it
  blunts, bleeding by its two later turns, bloodlust by the extra blows of a
  melee squad about to fight.
- Casters and machines plan casts from every tile they can reach (machines
  only from where they stand). Shamans and lobbers act first in the enemy
  turn with the missile troops, so a frenzy lands before the shock troops go.
- Enemy threat maps count a lobber's stones; deployment puts casters and
  machines at the back (`isBackline`).

## Presentation

- Mages, shamans and engine crews are figures in `src/render/figures.ts`;
  engines are drawn by `src/render/engines.ts` and stand on their tile a
  little forward of the centre (`engineOffset`), crew behind and beside them
  (`crewSlots` in `formation.ts`). The engine is depth-sorted among its crew,
  shares their flinch and lunge (a wagon ramming), shows its loosing pose, and
  is left as a wreck when the squad is destroyed.
- `playSpell` in `battleScene.ts`: casters raise their staffs while power
  gathers at the staff heads, then lightning (converging bolts, then arcs from
  squad to squad), ice shards and a frost burst, healing light, a fireball and
  its explosion, blood-red tendrils of a frenzy, the gutripper's hex, or a
  stone lobbed high that smashes down. Each squad shows its damage, healing
  and fallen soldiers when the effect reaches it. Lightning and fire flash the
  field; fire, stones and lightning leave scorch marks, craters and frost.
- Conditions show as labels beside the health bar (CHILLED, FRENZY,
  BLEEDING), a frost or red tint on the figures, and glitter, haze or dripping
  blood.
- HUD: spell buttons with cooldowns and reasons; choosing a spell shows its
  range, the squads it can be cast at, and under the cursor everything it
  would touch (friends caught in a blast in orange, lightning's arcs dashed);
  the spell forecast lists each squad touched with damage, soldiers slain and
  healing. A mangonel aims its stone at the enemy under the cursor.

## Checks

- `npx vitest run`: `tests/spells.test.ts` covers sizes, scaling with casters,
  single rolls, chain arcs, chill, healing without resurrection, the circle,
  friendly fire and scatter, bloodlust, bleeding, the machines' setup rule,
  the bolt carrying through, lobbed stones, the wagon's smash, the AI casting
  on both sides and whole battles.
- `npm run sim -- specialists [types…]`: the standard army with crossbowmen,
  mages, a ballista or a mangonel in the fifth place, against five
  encounters. After tuning (120 battles each, squad HP left): crossbowmen
  58–79%, mages 60–79%, ballista 58–77%, mangonel 63–80%; all win 95–100%.
  The new encounters with the standard army: Shamans of the host 99% won,
  the host's war engines 93% (the hardest small fight).
- Campaign (`scripts/simcampaign.ts` style, 180 companies × 6 expeditions,
  two seed sets): 39.4% and 36.9% of expeditions succeed, against 40.8% and
  41.0% before this change; the gap is within about three points and mostly
  the shaman at the warchief's side. The automated company rarely hires the
  specialist (it is last in the recruit list), so this measures the new enemies.
- `npx vite-node scripts/magicdiag.ts`: how the automated company uses each
  specialist (casts, shots, idle turns, how often the squad is lost) and what
  the host's shamans and lobbers cast. After tuning: mages cast about five
  spells a battle and are lost in about a quarter of battles; a ballista
  looses about five and a half bolts; shamans cast about three spells;
  a rock lobber strikes one of its own squads almost once a battle.
- `node scripts/magiclab.mjs <dir> [timeScale]`: every spell, shot and
  condition staged in the real renderer, frame by frame, plus every engine in
  all four facings; `node scripts/sheets.mjs <dir> <out>` turns the frames
  into contact sheets.
- `node scripts/magicui.mjs <dir>`: the same through the real interface
  (spell chosen by key, forecast on hover, cast by click; the mangonel aimed
  by hovering an enemy; the enemy turn; the Barracks' specialist offer).
- `node scripts/art/newunits.mjs <dir>` and `node scripts/lineup.mjs`: the
  new figures, engines and portraits in every pose and look.

## Godot version (`source/godot`, branch `godot-migration`)

The same squads, spells, conditions and engines are ported rule for rule:
the battle traces of `tools/parity/battle_traces.ts` (now with `shaman_fire`,
`siege_train` and a scripted magic company) replay identically in
`tests/parity/test_battle_parity.gd`, RNG state included. Figures, engines,
portraits, sounds and icons are baked from this renderer by
`tools/bake/bake.mjs`. The port, its checks and its few deliberate
differences are listed in `source/godot/MIGRATION.md` ("Magic and war
machines"). Visual review: `tests/visual/magic_lab.gd` and
`tests/visual/capture_magic.gd`.
