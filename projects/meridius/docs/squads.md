# Meridius: squad system

Every unit on the battlefield is a squad: several soldiers who act, move and
fight as one gameplay unit on one tile. The player selects and orders the
squad, never individual soldiers.

## Size

- Every squad has 6 soldiers (`DEFAULT_SQUAD_SIZE` in `src/data/units.ts`).
- A unit type can override it with `squad`: Moss Trolls 3, Goblin Wolf Riders
  4, Goblin Horn-bearers 4 (a horn-bearer and three spears), Goblin Rabble 9.
- Formations (`src/render/formation.ts`): rabble stand in three ranks of
  three; wolf riders two abreast and two deep, with wider spacing.
- `squadSize(typeId)` is the only place the rest of the code asks.
- Stats in a unit type (`base`, `melee`, `shot`) are per soldier.

## Health

- One shared HP pool per squad: `maxHp = size × hpPer`, where `hpPer` is one
  soldier's HP (level, equipment and injuries included).
- Soldiers standing: `alive = ceil(hp / hpPer)`, never more than before. With 60
  HP and 10 per soldier: 60–51 → 6, 50–41 → 5, … 10–1 → 1, 0 → destroyed.
- One heavy blow can cross several thresholds and kill several soldiers.
- Healing (bandages, rest, troll regeneration) refills the survivors' shares
  only. The dead stay dead. Reinforcement at the Barracks is the only way to
  bring a squad back to strength.
- A squad that marches out wounded starts with the soldiers its HP can carry.
- Helpers: `src/battle/squad.ts` (`aliveFor`, `damageSquad`, `healSquad`,
  `killsFrom`); roster side in `src/meta/soldier.ts` (`men`, `squadHpCap`,
  `healSoldier`, `settleMen`).

## After the battle

- **Field triage** (`applyBattle` in `src/campaign/expedition.ts`): once the
  fighting is over, every soldier who fell gets the survival roll a lone
  soldier always had (`FALL_SURVIVAL_BASE` 45%, +5% per level, + Infirmary and
  bandage bonus), ×1.25 when the field is held, ×0.9 after a withdrawal, ×0.4
  after a defeat, capped at 85%. Those found rejoin their squad with 30% of a
  share. It happens only after the battle and is reported per squad; in battle
  the fallen stay down. A squad wiped out to the last gets no triage.
- **Downed squad**: the whole squad fell but its sergeant lives (the old
  survival roll); he keeps the squad with 1 soldier plus any found by triage.
- **Reinforcement** (Barracks, at Amberfeld only): +1 soldier or refill, about
  `recruitCost / size × 0.8` silver per soldier, more for veteran squads. New
  soldiers arrive at full health. This is the only way to raise `men`.
- Old saves are migrated on load (`migrateSave`): `men = squadSize`, HP scaled
  from one soldier to the squad.

## Damage

- Squad damage = surviving soldiers × damage per soldier. Each soldier's blow
  is reduced by the target's armour before multiplying, so armour matters
  equally at every strength.
- Hit chance, arcs, height, cover, charge, spearwall, rear multipliers and
  abilities work exactly as before; only the final damage is multiplied.
- The rules roll damage once per attack (`Battle.preview` / `resolveAttack`).
  The renderer only plays it back: however many soldiers swing or loose, there
  is one `attack` event with `strikers`, `damage`, `aliveBefore` and
  `aliveAfter`. Animation never applies damage.
- Losing soldiers shakes morale on top of the wound itself
  (`12 × lost / size`). Experience from damage is divided by squad size.
- The AI weighs squad damage in one soldier's terms (`avg / size`) and scales
  enemy threat by strength (`alive / size`), keeping its tuned trade-offs.

## Formation and movement

- The squad has one anchor (its tile), one facing and one path. Each soldier
  keeps a local offset from the anchor (`src/render/formation.ts`).
- Six stand in two ranks of three; 5 → 3 + 2; 4 → 2 × 2; 3 → 2 + 1; 2 → a
  pair; 1 → centre. Trolls stand in a triangle (two in front, one behind).
- Ranks are horizontal on screen, as in the reference sheets
  (`references/characters/Footmen.png`, `Trolls.png`), with a small lean toward
  the facing. Every slot keeps the feet inside the tile diamond (tested).
- When soldiers fall or the squad turns, survivors walk to the nearest free
  slot (exhaustive minimum-movement assignment); a champion (the warlord
  among his guard) keeps the front-centre slot and falls last.
- Shield wall closes the ranks (0.84), set spears slightly (0.92); routing
  squads scatter into ragged order.

## Animation (`src/render/squadView.ts`, `src/render/battleScene.ts`)

| Event | What the soldiers do |
| --- | --- |
| idle | Each breathes and shifts weight on his own rhythm. |
| move | One cadence for the squad with personal slack; dust per pair of boots; the formation turns at each corner; ranks dress on arrival. |
| face | Squad turns; ranks shift their lean. |
| melee | A ripple of blows from the front rank back: wind-up, lunge, recover. Damage shows once at the first blow; victims fall one by one as blows land. |
| ranged | Every surviving archer/crossbowman fires his own missile a beat apart; hits fly at the soldiers who will fall; misses stick in the ground. |
| hit | Squad flinches and flashes; armour sparks or blood. |
| death | The nearest soldiers to the blow tip over and settle into bodies that stay on the field; survivors close up. |
| stance, rout, rally | Tighten, scatter, re-form. |

Each squad shows a ground footprint (corner marks and a front chevron in its
colours), a standard carried in the rear rank, and one health bar cut into one
segment per soldier, fallen soldiers crossed out.

## Checks

- `npx vitest run` — `tests/squad.test.ts` covers sizes, thresholds,
  multi-kills, no resurrection, damage scaling, single damage roll, trolls and
  formation geometry.
- `npm run sim` — single battles at full strength: win rates within a few
  points of the pre-squad numbers (orc overseer 92% vs 96%; warband camp L1
  82% vs 78% after trimming one goblin squad; brutes 100%, trolls 97%).
- `npx vite-node scripts/simcampaign.ts` — 60 companies × 6 expeditions with
  the autoplayer: 49–68% success per cycle, against 59–79% before squads.
  Most of the gap is inherent to the rule that depleted squads hit softer;
  levers are triage factors, reinforcement price and encounter weights.
- `node scripts/formations.mjs <dir>` — formation gallery at every strength
  and facing; `node scripts/combatlab.mjs <dir> [timeScale]` — staged melee,
  troll and volley exchanges frame by frame; `node scripts/squadcheck.mjs
  <dir>` — a real battle from deployment to contact. All take `BASE_URL`.
