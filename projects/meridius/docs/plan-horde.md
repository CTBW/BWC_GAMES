# Meridius: the endless horde

Outcome: every battle feels outnumbered and every large battle feels like a
desperate last stand. Orcs and goblins pour in from the map edges in waves, and
the company wins through position, terrain, formations and the right unit in
the right place, never by matching numbers. Facing comes only from movement.

## What we take from the references

| Source | What makes it work | Our version |
| --- | --- | --- |
| They Are Billions | Waves are announced with a direction and a countdown; the final swarm comes from all sides with the biggest monsters; fallback lines matter more than a perfect wall. | A wave counter with direction and turns left; edge warnings; a final wave with the warchief and trolls; maps with an outer and an inner line. |
| Into the Breach | Enemy arrivals are shown a turn ahead on the tiles where they will emerge, so losses feel like the player's own fault. | Red markers on the entry tiles one turn before a wave; the next wave is visible massing beyond the map edge before it enters. |
| Battle Brothers (greenskin crisis) | Wolfriders circle a static line to hit archers and the lightly armed from behind; orcs rush and overwhelm; spears and shields hold them; the crisis builds across the campaign until the warlord appears. | Wolf riders that hunt flanks and crossbowmen; brutes that smash a squad out of the line; spearwall as the answer; the horde's front advancing on the campaign map. |
| Helm's Deep | Dread before contact (the host seen from the wall, torches in the dark), a breach, falling back, holding until relief comes at dawn. | The massed horde in view before the first wave; brutes breaking the line; inner positions to fall back to; "hold until the relief column arrives" as a win. |
| Thermopylae, Rorke's Drift, Seven Samurai | Walls, gates and narrow ground let a few hold many: let them in one at a time. | Palisades, gates, bridges, fords, stake lines, rubble and high ground on every large map. |

## Rules

### Facing
- A squad faces the direction of the last step of its move. No facing step,
  no facing buttons, no turning when attacking or reacting.
- A move may end on the start tile (step out and back) to turn, at the cost
  of the move and any free attacks it provokes.
- When choosing a destination the game shows the path, the ghost squad and an
  arrow for the facing it will arrive with. Pointing at an edge of the
  destination tile picks the approach that faces that edge (Q / E cycle).
  Without a choice, the squad arrives facing the enemy if any path allows.
- Squads keep their weapon hand: the shield is always on the soldier's left
  arm (reference: `Facing when moving.png`, `Facing when moving 2.png`).
  Front views for +x and +y, back views for -x and -y, never mirrored.
- Systems that read facing: flank and rear attacks, shields (front arc),
  shield wall (front and flanks), spearwall and overwatch (not the rear arc),
  first strike (front), and zones of control (a squad strikes at foes leaving
  its front or flanks, not its rear).

### The horde
- New enemies: goblin rabble (nine to a squad, weak, many), goblin wolf
  riders (fast, hunt flanks and missile troops), a goblin horn-bearer (calls
  reinforcements), and an orc warchief who leads the final wave. Brutes now
  smash their target back out of the line and step into the gap.
- Every battle has an objective with clear win and loss conditions: rout,
  survive N turns (relief arrives), hold a zone, slay the warchief, or break
  out through an exit. Morale and rout apply to both sides.
- Waves and reinforcements are data (`turn`, `edge`, units). Large battles
  have four or five waves; small ones a war horn if the fight drags on.

### Battlefields
- Small maps (14 × 12) for skirmishes, raids, ambushes and patrols.
- Large maps (about 26 × 22) for last stands: a walled steading and a river
  ford, with gates, palisades, stakes, bridges, rubble and high ground.
- Camera: zoom out to the whole map, clamped panning, a minimap, off-screen
  threat markers. Rendering culls off-screen props; enemy turns play their
  moves at the same time so a turn with thirty squads stays short.

## Stages and acceptance checks

| Stage | Output | Shows it works |
| --- | --- | --- |
| 1. Facing | Rules, path/facing preview, AI, four-facing figures | Unit tests for arcs, ZOC, spearwall, overwatch, loop turns; captures of all four facings next to the reference images |
| 2. Horde rules | Objectives, waves, new enemies, brute smash, swarm AI | Unit tests; headless sims of every battle type finish with plausible win rates |
| 3. Battlefields | Large templates, new props, camera, minimap, playback | Captures of each large map; 60 FPS with the full horde on screen; enemy turns under about 15 s |
| 4. Campaign | Horde front on the map, scouting reports, events, last-stand objective | A full expedition played through the UI with captures |
| 5. Loops | Play-tests of small and large battles, honest review, fixes | Review notes with captures per loop; balance tables |

## Status, 21 October 2026

Built and verified in the running game. Where things live:

| Part | Code |
| --- | --- |
| Facing from the last step, per-facing paths, loop turns | `src/battle/battle.ts` (`reachStates`, `facingOptions`, `defaultFacing`, `move`) |
| Facing preview, Q / E, pointing at an edge; walls in front of the preview fade, a squad turning in place fades for its ghost | `src/render/battleScene.ts` (`arrival`, `pointing`, `drawFacingArrow`, `moveGhost`) |
| Shield-leading poses so mirrored squads keep the shield on the left arm | `src/render/figures.ts` (`_fs`, `_bs` poses), `poseKey` in the scene |
| Waves, war horn, held ground, relief, warchief, give-up rule | `src/battle/battle.ts` (`arriveWaves`, `soundHorn`, `afterEnemyTurn`, `hordeBreaks`) |
| Encounters, waves and objectives as data | `src/data/encounters.ts` |
| Large hand-drawn grounds (steading, ford), entries, approaches | `src/data/maps.ts` (`layout`), `src/battle/mapgen.ts` (`generateAuthored`) |
| Battle setup: reserves beyond the edge, militia, gate-aware deployment, depleted-company scaling | `src/battle/setup.ts` |
| Swarm AI (flanks, gaps, weak targets, roles, turn order), company auto-play in stands | `src/battle/ai.ts` |
| Concurrent playback, waves massing, warnings, host, night to dawn, minimap, camera | `src/render/battleScene.ts` |
| The dawn relief: the Margrave's riders charge down the horde's own road into its rear, sunrise light, hoofbeats | `src/render/battleScene.ts` (`startRelief`, `riderAt`, `drawSunrise`), `src/render/figures.ts` (`drawHorseRider`) |
| Wolf rider drawn as a warg (shaped legs, hackles, snarl, tail) | `src/render/figures.ts` (`wolfProfile`, `drawWolfRider`) |
| The host on the campaign map, Brannsted, news and events | `src/render/campaignScene.ts`, `src/campaign/expedition.ts`, `src/data/events.ts` |

Checks: `tests/facing.test.ts` (11), `tests/horde.test.ts` (14), 66 tests in all.
`scripts/hordesim.ts` (every encounter, headless), `scripts/campdiag.ts`
(which battles end expeditions), `scripts/simcampaign.ts` (60 companies × 6),
`scripts/hordeshots.mjs` and `scripts/hordereview.mjs` (captures),
`scripts/facingui.mjs` (facing preview through the real UI),
`scripts/facingstand.mjs` (facing at a gateway and turning in place on the
last-stand map, at its opening zoom), `scripts/reliefshots.mjs` (the dawn
relief frame by frame),
`scripts/facingsheet.mjs` (all facings of all types), `scripts/perf.mjs`,
`scripts/perfsplit.mjs` and `scripts/fpsheadless.mjs` (frame cost).

## Lessons

- **The AI-played campaign is the balance gauge, not single battles.** Fresh
  six-squad companies won every new fight in isolation, yet the first campaign
  run succeeded 12% of the time: losses compound over five battles and the
  last stand. Battle numbers had to be tuned in campaign context
  (`scripts/campdiag.ts`).
- **A held line needs a reserve.** Most last-stand defeats in the simulator
  were the yard left empty while every squad held a gate. Overrun now needs
  the attackers inside to outnumber the defenders by two, and the
  auto-commander keeps two squads in the yard.
- **A horde that stands still is not a horde.** Squads beside a shield wall
  with poor odds simply waited; swarms and shock troops now attack anything in
  reach, and a skirmish that drags past turn 14 ends with the band slinking off.
- **Measure frame rate in a real window.** Headless Edge rasterises 2D canvas
  in software, so its numbers mislead. In a real window the costs were the
  painted ground drawn with high-quality filtering, static layers drawn from
  canvases instead of bitmaps, and one skewed cast shadow per soldier. A
  texture atlas made things worse (page rewrites re-upload whole pages) and
  was removed.
- **Test previews where the walls are.** On an open field the facing arrow
  read perfectly; at a gateway the palisade in front hid it, and a squad
  turning in place hid its own arrow. Only a play-test on the large map at its
  opening zoom showed it.
- **Enemy turns play side by side.** Events about different squads run
  together; consequences (morale, falls, log lines) wait for the action that
  caused them. A crowded enemy turn also plays a little faster.
