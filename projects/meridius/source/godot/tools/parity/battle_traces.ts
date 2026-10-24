// ARCHIVED (21 Oct 2026): do not re-run. The original is archived and the Godot
// rules have since changed on purpose; the traces are re-recorded by the port
// (MERIDIUS_RECORD=1 tools/test.sh test_battle_parity, see README.md).
//
// Golden battle traces from the original rules for tests/parity/test_battle_parity.gd.
//   cd projects/meridius/source/game && npx vite-node ../godot/tools/parity/battle_traces.ts
//
// For every encounter × seeds (plus darkness, a veteran company and both
// last-stand grounds) a BattleSetup is built exactly as the game builds one
// (rollEncounter + buildBattle, the company from a newGame roster through
// soldierToUnit, like store.debug.testBattle), serialised, and fought with the
// original AI on both sides (the loop of autoBattle). Every drained event and a
// state snapshot after each step is recorded. Scripted traces drive the API the
// AI never calls (previews, reach/facing queries, explicit facings, redo,
// deployment swaps, stances, abilities, retreat) and record the results.
//
// Output: tests/fixtures/golden/battle/<group>.json
import { mkdirSync, readdirSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Rng } from '../../../game/src/core/rng';
import type { Dir } from '../../../game/src/core/types';
import { ABILITIES } from '../../../game/src/data/abilities';
import { ENCOUNTERS } from '../../../game/src/data/encounters';
import { Battle } from '../../../game/src/battle/battle';
import { actUnit, chooseFacing, exposure, runEnemyAi, runPlayerAuto } from '../../../game/src/battle/ai';
import { buildBattle, rollEncounter } from '../../../game/src/battle/setup';
import { lineOfSight, manhattan } from '../../../game/src/battle/grid';
import type { BattleSetup, BattleUnit, Pt } from '../../../game/src/battle/types';
import { newGame } from '../../../game/src/meta/game';
import { newSoldier, soldierStats, soldierToUnit, type Soldier } from '../../../game/src/meta/soldier';

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, '..', '..', 'tests', 'fixtures', 'golden', 'battle');
mkdirSync(outDir, { recursive: true });
for (const f of readdirSync(outDir)) if (f.endsWith('.json')) unlinkSync(join(outDir, f));

const clone = <T>(v: T): T => (v === undefined ? (null as T) : JSON.parse(JSON.stringify(v)));

// ------------------------------------------------------------------ companies

/** The six squads of a new game, as the debug test battle fields them. */
function freshCompany(seed: number): BattleUnit[] {
  const g = newGame(seed);
  return g.roster.slice(0, 6).map((s) => soldierToUnit(s));
}

/**
 * A company late in a campaign: levels, promotions (shield bash, pike thrust,
 * heavy bolt), better gear, worn armour, fatigue, an injury, thinned squads,
 * few bolts, and a royal guard. Fractions are binary (0.75) so the JSON is exact.
 */
function veteranCompany(seed: number): BattleUnit[] {
  const g = newGame(seed);
  const rng = new Rng(seed * 31 + 7);
  let n = 100;
  const roster: Soldier[] = g.roster.slice(0, 6);
  roster.push(newSoldier(rng, 'collie_guard', 2, () => `v${n++}`, 1));
  const levels = [4, 3, 3, 2, 4, 1, 2];
  roster.forEach((s, i) => {
    s.level = levels[i];
    s.promoted = s.level >= 3;
    s.weaponTier = 1 + (i % 3);
    s.armorTier = 1 + ((i + 1) % 2);
    s.armorCondition = i % 2 ? 0.75 : 1;
    s.fatigue = [0, 65, 90, 10, 0, 70, 0][i];
    if (i === 3) s.injuries = ['gashed_arm'];
    const st = soldierStats(s);
    if (i === 1) s.men = 4;
    s.hp = st.hp * s.men - (i === 1 ? 5 : 0);
    s.morale = i === 5 ? Math.round(st.morale * 0.5) : st.morale;
    if (s.typeId === 'crossbowman') s.ammo = i === 4 ? 3 : 8;
  });
  return roster.map((s) => soldierToUnit(s));
}

/** Eight squads at the top of their trade (level 5, promoted, the best gear). */
function eliteCompany(seed: number): BattleUnit[] {
  const g = newGame(seed);
  const rng = new Rng(seed * 17 + 3);
  let n = 200;
  const roster: Soldier[] = g.roster.slice(0, 6);
  roster.push(newSoldier(rng, 'collie_guard', 5, () => `e${n++}`, 1), newSoldier(rng, 'footman', 5, () => `e${n++}`, 1));
  for (const s of roster) {
    s.level = 5;
    s.promoted = true;
    s.weaponTier = 3;
    s.armorTier = 3;
    const st = soldierStats(s);
    s.hp = st.hp * s.men;
    s.morale = st.morale;
    if (s.typeId === 'crossbowman') s.ammo = 10;
  }
  return roster.map((s) => soldierToUnit(s));
}

/** Three tired, thinned squads: a company that should not be fighting. */
function weakCompany(seed: number): BattleUnit[] {
  const g = newGame(seed);
  const roster = [g.roster[0], g.roster[2], g.roster[4]];
  roster.forEach((s, i) => {
    const st = soldierStats(s);
    s.men = 3 + (i % 2);
    s.hp = st.hp * s.men - 3;
    s.fatigue = 70;
    s.morale = Math.round(st.morale * 0.6);
  });
  return roster.map((s) => soldierToUnit(s));
}

/**
 * A company with the specialists: two circles of battle mages (one promoted,
 * with the Mending Circle), a ballista and a mangonel beside four line squads.
 */
function magicCompany(seed: number): BattleUnit[] {
  const g = newGame(seed);
  const rng = new Rng(seed * 23 + 5);
  let n = 300;
  const roster: Soldier[] = g.roster.slice(0, 4);
  const mage = newSoldier(rng, 'battle_mage', 3, () => `m${n++}`, 1);
  mage.promoted = true;
  roster.push(mage, newSoldier(rng, 'battle_mage', 1, () => `m${n++}`, 1), newSoldier(rng, 'ballista', 2, () => `m${n++}`, 1), newSoldier(rng, 'mangonel', 1, () => `m${n++}`, 1));
  return roster.map((s) => soldierToUnit(s));
}

type Company = 'fresh' | 'veteran' | 'elite' | 'weak' | 'magic';
const COMPANIES: Record<Company, (seed: number) => BattleUnit[]> = { fresh: freshCompany, veteran: veteranCompany, elite: eliteCompany, weak: weakCompany, magic: magicCompany };

function makeSetup(encounterId: string, seed: number, o: { depth?: number; company?: Company; darkness?: boolean; mapId?: string; survivalBonus?: number } = {}): BattleSetup {
  const roll = rollEncounter(encounterId, new Rng(seed), o.depth ?? 2);
  if (o.mapId) roll.mapId = o.mapId;
  const army = COMPANIES[o.company ?? 'fresh'](seed);
  return buildBattle(roll, army, { survivalBonus: o.survivalBonus ?? 0, darkness: o.darkness });
}

// ------------------------------------------------------------------ recording

function snapshot(b: Battle) {
  return clone({
    turn: b.turn,
    phase: b.phase,
    result: b.result ?? null,
    horn: b.horn,
    overrun: b.overrun,
    rng: b.rng.state,
    waveState: b.waveState,
    waveTurns: b.waves.map((w) => w.turn),
    hitsTaken: b.hitsTaken,
    moveRecords: [...b.moveRecords.entries()].map(([k, r]) => [k, r.x, r.y, r.facing, r.movedTiles, r.clean, r.path]),
    units: b.units.map((u) => [
      u.uid, u.x, u.y, u.facing, u.hp, u.alive, u.morale, u.status, u.stance ?? null, u.hasMoved, u.hasActed, u.done,
      u.movedTiles, u.kills, u.damageDealt, u.xp, u.ammo, u.cooldowns, u.struck, u.statuses ?? [],
    ]),
  });
}

const eventCounts: Record<string, number> = {};
function countEvents(evs: any[]) {
  for (const e of evs) {
    const k = e.t === 'attack' ? `attack:${e.reaction ?? (e.ability ? 'ability:' + e.ability : e.ranged ? 'shot' : 'melee')}` : e.t === 'push' ? `push:${e.blocked}` : e.t === 'down' ? `down:${e.dead}` : e.t === 'horn' ? `horn:${e.sounded}` : e.t;
    eventCounts[k] = (eventCounts[k] ?? 0) + 1;
  }
}

interface Step { op: string; args?: unknown[]; ret?: unknown; events?: unknown[]; state?: unknown }

/** The loop of campaign/autoplay.ts autoBattle, recording each step. */
function autoSteps(b: Battle, steps: Step[], maxTurns = 30) {
  const step = (op: string) => {
    const events = clone(b.drain());
    steps.push({ op, events, state: snapshot(b) });
  };
  if (b.phase === 'deploy') {
    b.begin(runEnemyAi);
    step('begin');
  }
  while (!b.isOver() && b.turn <= maxTurns) {
    runPlayerAuto(b);
    step('player');
    if (b.isOver()) break;
    b.endTurn(runEnemyAi);
    step('end');
    // A sensible captain pulls out of a fight he has clearly lost, to save the company.
    if (!b.isOver() && b.phase === 'player') {
      const company = b.company();
      const foes = b.active('enemy').length;
      if (company.length && (b.strength('player') < 0.3 || (company.length <= 2 && foes >= company.length * 3))) {
        b.retreat();
        step('retreat');
      }
    }
  }
  if (!b.isOver()) {
    b.retreat();
    step('retreat');
  }
}

function autoTrace(name: string, setup: BattleSetup) {
  const json = clone(setup);
  const b = new Battle(clone(json));
  const steps: Step[] = [];
  const t0 = performance.now();
  autoSteps(b, steps);
  const ms = performance.now() - t0;
  return { name, kind: 'auto', setup: json, steps, result: b.result, turns: b.turn, ms: Math.round(ms) };
}

// ------------------------------------------------------------------ scripted

const unkey = (k: number): Pt => ({ x: k % 1000, y: Math.floor(k / 1000) });
const entries = (m: Map<number, { cost: number; prev: number; zoc: number }>) => [...m.entries()].map(([k, v]) => [k, v.cost, v.prev, v.zoc]);

function scriptedTrace(name: string, setup: BattleSetup, seed: number, o: { turns: number; retreatAt?: number; shout?: boolean; finish?: boolean }) {
  const json = clone(setup);
  const b = new Battle(clone(json));
  const r = new Rng(seed);
  const steps: Step[] = [];
  const act = (op: string, args: unknown[], ret: unknown) => {
    const events = clone(b.drain());
    steps.push({ op, args: clone(args), ret: clone(ret), events, state: snapshot(b) });
  };
  const q = (op: string, args: unknown[], ret: unknown) => steps.push({ op, args: clone(args), ret: clone(ret) });

  // Deployment: swap squads around the deployment ground (and try tiles outside it).
  for (let i = 0; i < 8; i++) {
    const pu = r.pick(b.units.filter((u) => u.faction === 'player'));
    const zone = b.map.playerDeploy;
    const p = r.chance(0.8) ? r.pick(zone) : { x: r.int(0, b.map.w - 1), y: r.int(0, b.map.h - 1) };
    act('deploySwap', [pu.uid, p.x, p.y], b.deploySwap(pu.uid, p.x, p.y));
  }
  q('company', [], b.company().map((u) => u.uid));
  b.begin(runEnemyAi);
  act('begin', [], null);
  act('deploySwap', [b.units[0].uid, b.units[0].x, b.units[0].y], b.deploySwap(b.units[0].uid, b.units[0].x, b.units[0].y));

  const probe = () => {
    const act_ = b.active();
    const players = b.active('player');
    const enemies = b.active('enemy');
    q('strength', ['player'], b.strength('player'));
    q('strength', ['enemy'], b.strength('enemy'));
    q('pendingWaves', [], b.pendingWaves());
    const nw = b.nextWave();
    q('nextWave', [], nw ? { index: nw.index, turn: nw.turn } : null);
    for (const u of act_.slice(0, 14)) {
      q('reachStates', [u.uid], entries(b.reachStates(u)));
      q('reachable', [u.uid], entries(b.reachable(u)));
      q('zocTiles', [u.uid], [...b.zocTiles(u)]);
      q('moraleState', [u.uid], b.moraleState(u));
      q('facingTowardFoes', [u.uid], b.facingTowardFoes(u));
      q('isAdjacentEnemy', [u.uid], b.isAdjacentEnemy(u));
    }
    q('reachStates', [players[0]?.uid ?? b.units[0].uid, 2], entries(b.reachStates(players[0] ?? b.units[0], 2)));
    for (const u of players) {
      const keys = [...b.reachable(u).keys()];
      for (let i = 0; i < 4 && keys.length; i++) {
        const p = unkey(r.pick(keys));
        const opts = b.facingOptions(u, p.x, p.y);
        q('facingOptions', [u.uid, p.x, p.y], opts);
        q('defaultFacing', [u.uid, p.x, p.y], b.defaultFacing(u, p.x, p.y, opts) ?? null);
        for (const f of [undefined, 0, 1, 2, 3] as (Dir | undefined)[]) q('moveOption', [u.uid, p.x, p.y, f ?? null], b.moveOption(u, p.x, p.y, f) ?? null);
        q('pathTo', [u.uid, p.x, p.y], b.pathTo(u, p.x, p.y));
        q('chooseFacing', [u.uid, p.x, p.y], chooseFacing(b, u, p) ?? null);
        const dir = r.int(0, 3) as Dir;
        q('exposure', [p.x, p.y, dir, 'enemy'], exposure(p, dir, enemies));
      }
      // Occupied and far tiles.
      const other = r.pick(b.units.filter((x) => x.status === 'active'));
      q('facingOptions', [u.uid, other.x, other.y], b.facingOptions(u, other.x, other.y));
      q('pathTo', [u.uid, other.x, other.y], b.pathTo(u, other.x, other.y));
      q('facingOptions', [u.uid, u.x, u.y], b.facingOptions(u, u.x, u.y));
      q('targets', [u.uid, null, null], b.targets(u).map((t) => t.uid));
      for (const ab of u.abilities) q('targets', [u.uid, null, ab], b.targets(u, u, ab).map((t) => t.uid));
      for (const t of enemies) {
        if (manhattan(t, u) > 10) continue;
        q('preview', [u.uid, t.uid, {}], b.preview(u, t));
        q('arcOf', [t.uid, u.x, u.y], b.arcOf(t, u));
        q('canShoot', [u.uid, t.uid, null], b.canShoot(u, t));
        q('wouldShoot', [u.uid, t.uid, null], b.wouldShoot(u, t));
        q('los', [u.x, u.y, t.x, t.y], lineOfSight(b.map, u, t));
        q('preview', [t.uid, u.uid, {}], b.preview(t, u));
        q('preview', [u.uid, t.uid, { forceMelee: true }], b.preview(u, t, { forceMelee: true }));
        for (const reaction of ['zoc', 'spearwall', 'overwatch', 'firstStrike'] as const) {
          if (r.chance(0.35)) q('preview', [u.uid, t.uid, { reaction, forceMelee: reaction !== 'overwatch' }], b.preview(u, t, { reaction, forceMelee: reaction !== 'overwatch' }));
        }
        // From the tiles around the target that the squad could reach.
        const reach = b.reachable(u);
        for (const d of [{ x: 1, y: 0 }, { x: 0, y: 1 }, { x: -1, y: 0 }, { x: 0, y: -1 }, { x: 2, y: 0 }, { x: 0, y: -2 }]) {
          const from = { x: t.x + d.x, y: t.y + d.y };
          const k = from.y * 1000 + from.x;
          if (from.x < 0 || from.y < 0 || from.x >= b.map.w || from.y >= b.map.h) continue;
          const info = reach.get(k);
          const movedTiles = info ? info.cost : r.int(0, 4);
          q('preview', [u.uid, t.uid, { from, movedTiles }], b.preview(u, t, { from, movedTiles }));
          q('canMelee', [u.uid, t.uid, from, 2], b.canMelee(u, t, from, 2));
          q('targets', [u.uid, from, null], b.targets(u, from).map((x) => x.uid));
          for (const ab of u.abilities) {
            if (ABILITIES[ab]?.kind !== 'attack') continue;
            q('preview', [u.uid, t.uid, { from, ability: ab, movedTiles }], b.preview(u, t, { from, ability: ab, movedTiles }));
          }
        }
      }
    }
    for (let i = 0; i < 6; i++) {
      const a = { x: r.int(0, b.map.w - 1), y: r.int(0, b.map.h - 1) };
      const c = { x: r.int(0, b.map.w - 1), y: r.int(0, b.map.h - 1) };
      q('los', [a.x, a.y, c.x, c.y], lineOfSight(b.map, a, c));
    }
  };

  const playerTurn = () => {
    const order = b.active('player').map((u) => u.uid);
    for (const uid of order) {
      if (b.isOver()) return;
      const u = b.unit(uid);
      if (u.status !== 'active') continue;
      if (r.chance(0.08)) {
        b.endUnit(uid);
        act('endUnit', [uid], null);
        continue;
      }
      // A stance before moving sometimes (it uses the action).
      if (r.chance(0.12)) {
        const st = u.abilities.find((a) => ABILITIES[a]?.kind === 'stance');
        if (st) act('useStance', [uid, st], b.useStance(uid, st));
      }
      const mroll = r.next();
      if (mroll < 0.2) {
        // Turn on the spot: out and back.
        const home = b.facingOptions(u, u.x, u.y).filter((o) => o.facing !== u.facing);
        if (home.length) {
          const o = r.pick(home);
          act('move', [uid, u.x, u.y, o.facing], b.move(uid, u.x, u.y, o.facing));
        } else act('move', [uid, u.x, u.y, null], b.move(uid, u.x, u.y));
      } else if (mroll < 0.85) {
        const keys = [...b.reachable(u).keys()];
        const foes = b.enemiesOf(u);
        const near = keys.filter((k) => foes.some((f) => manhattan(f, unkey(k)) === 1));
        const pool = near.length && r.chance(0.6) ? near : keys;
        const p = unkey(r.pick(pool));
        const opts = b.facingOptions(u, p.x, p.y);
        const f = opts.length && r.chance(0.5) ? r.pick(opts).facing : undefined;
        act('move', [uid, p.x, p.y, f ?? null], b.move(uid, p.x, p.y, f));
        if (b.isOver()) return;
        if (r.chance(0.35)) {
          q('canRedo', [uid], b.canRedo(uid));
          act('redoMove', [uid], b.redoMove(uid));
          if (!u.hasMoved && u.status === 'active' && b.phase === 'player') {
            const k2 = [...b.reachable(u).keys()];
            const p2 = unkey(r.pick(k2));
            act('move', [uid, p2.x, p2.y, null], b.move(uid, p2.x, p2.y));
          }
        }
        // A second move is refused.
        if (r.chance(0.2)) act('move', [uid, u.x, u.y === 0 ? 1 : u.y - 1, null], b.move(uid, u.x, u.y === 0 ? 1 : u.y - 1));
      } else if (mroll < 0.92) {
        // Onto an occupied tile, or far beyond reach: refused.
        const other = r.pick(b.units.filter((x) => x.status === 'active' && x.uid !== uid));
        act('move', [uid, other.x, other.y, null], b.move(uid, other.x, other.y));
        act('move', [uid, (u.x + 9) % b.map.w, (u.y + 9) % b.map.h, null], b.move(uid, (u.x + 9) % b.map.w, (u.y + 9) % b.map.h));
      }
      if (b.isOver()) return;
      if (u.status !== 'active') continue;
      const ts = b.targets(u);
      const aroll = r.next();
      if (aroll < 0.75) {
        const abil = u.abilities.filter((a) => ABILITIES[a]?.kind === 'attack' && ABILITIES[a].damageMult && !((u.cooldowns[a] ?? 0) > 0));
        const ab = abil.length && r.chance(0.55) ? r.pick(abil) : undefined;
        const pool = ab ? b.targets(u, u, ab) : ts;
        if (pool.length) {
          const t = r.pick(pool);
          q('preview', [uid, t.uid, ab ? { ability: ab } : {}], b.preview(u, t, { ability: ab }));
          act('attack', [uid, t.uid, ab ?? null], b.attack(uid, t.uid, ab));
        } else if (ts.length) {
          const t = r.pick(ts);
          act('attack', [uid, t.uid, null], b.attack(uid, t.uid));
        }
      } else if (aroll < 0.9) {
        const st = u.abilities.find((a) => ABILITIES[a]?.kind === 'stance');
        if (st) act('useStance', [uid, st], b.useStance(uid, st));
      }
      if (b.isOver()) return;
      // Refused actions: a second attack, an attack out of reach, a shout without the ability.
      if (r.chance(0.25)) {
        const far = b.active('enemy').find((e) => manhattan(e, u) > 3);
        if (far) act('attack', [uid, far.uid, null], b.attack(uid, far.uid));
        act('shout', [uid, 'warcry'], b.shout(uid, 'warcry'));
        act('useStance', [uid, 'charge'], b.useStance(uid, 'charge'));
      }
    }
  };

  for (let turn = 1; turn <= o.turns && !b.isOver(); turn++) {
    if (b.phase !== 'player') break;
    probe();
    if (o.retreatAt === turn) {
      b.retreat();
      act('retreat', [], null);
      break;
    }
    if (turn % 3 === 0) {
      runPlayerAuto(b);
      act('playerAuto', [], null);
    } else playerTurn();
    if (b.isOver()) break;
    if (o.shout && turn === 2) {
      // The warlord's war cry, called directly in the enemy phase.
      const chief = b.active('enemy').find((u) => u.abilities.includes('warcry'));
      if (chief) {
        b.phase = 'enemy';
        act('setPhase', ['enemy'], null);
        const was = chief.hasActed;
        chief.hasActed = false;
        act('setFlag', [chief.uid, 'hasActed', false], was);
        act('shout', [chief.uid, 'warcry'], b.shout(chief.uid, 'warcry'));
        act('shout', [chief.uid, 'warcry'], b.shout(chief.uid, 'warcry'));
        b.phase = 'player';
        act('setPhase', ['player'], null);
      }
    }
    b.endTurn(runEnemyAi);
    act('endTurn', [], null);
  }
  if (o.finish) {
    const auto: Step[] = [];
    autoSteps(b, auto);
    for (const s of auto) steps.push({ ...s, op: s.op === 'player' ? 'playerAuto' : s.op === 'end' ? 'endTurn' : s.op });
  }
  return { name, kind: 'script', setup: json, steps, result: b.result ?? null };
}

/**
 * The warchief is cut down: the company fights until his host is on the field,
 * then a squad is set beside him, he is left with one soldier and a sliver of
 * health, and the squad attacks (as the original horde test does).
 */
function warchiefTrace(seed: number) {
  const json = clone(makeSetup('last_stand', seed, { company: 'elite', mapId: 'steading', depth: 4 }));
  const b = new Battle(clone(json));
  const steps: Step[] = [];
  const act = (op: string, args: unknown[], ret: unknown) => steps.push({ op, args: clone(args), ret: clone(ret), events: clone(b.drain()), state: snapshot(b) });
  b.begin(runEnemyAi);
  act('begin', [], null);
  const chief = b.units.find((u) => u.tags.includes('warchief'))!;
  while (!b.isOver() && !(chief.status === 'active' && b.phase === 'player')) {
    runPlayerAuto(b);
    act('playerAuto', [], null);
    if (b.isOver()) break;
    b.endTurn(runEnemyAi);
    act('endTurn', [], null);
  }
  if (b.isOver()) return null;
  const spot = [{ x: 1, y: 0 }, { x: -1, y: 0 }, { x: 0, y: 1 }, { x: 0, y: -1 }]
    .map((d) => ({ x: chief.x + d.x, y: chief.y + d.y }))
    .find((p) => p.x >= 0 && p.y >= 0 && p.x < b.map.w && p.y < b.map.h && !b.units.some((u) => u.x === p.x && u.y === p.y && (u.status === 'active' || u.status === 'routing')) && b.canMelee(chief, chief, p));
  const hero = b.active('player').find((u) => !u.shot && !u.hasActed);
  if (!spot || !hero) return null;
  for (const [uid, k, v] of [[chief.uid, 'hp', 1], [chief.uid, 'alive', 1], [hero.uid, 'x', spot.x], [hero.uid, 'y', spot.y]] as [string, string, number][]) {
    const u = b.unit(uid) as unknown as Record<string, unknown>;
    const was = u[k];
    u[k] = v;
    act('setFlag', [uid, k, v], was);
  }
  act('attack', [hero.uid, chief.uid, null], b.attack(hero.uid, chief.uid));
  if (!(steps[steps.length - 1].events as any[]).some((e) => e.t === 'broken')) return null;
  const auto: Step[] = [];
  autoSteps(b, auto);
  for (const st of auto) steps.push({ ...st, op: st.op === 'player' ? 'playerAuto' : st.op === 'end' ? 'endTurn' : st.op });
  return { name: `scripted/last_stand-warchief-s${seed}`, kind: 'script', setup: json, steps, result: b.result ?? null };
}

/**
 * Spells and war machines through the API the AI uses and the one it does not:
 * every caster's and machine's spell queries (canCast, spellTargets,
 * spellPreview at squads and tiles around them, from another tile after
 * moving, impaleTarget), then casts at random legal targets and refused
 * second casts; other squads act through actUnit; the enemy turn is the AI.
 */
function spellTrace(name: string, setup: BattleSetup, seed: number, turns: number) {
  const json = clone(setup);
  const b = new Battle(clone(json));
  const r = new Rng(seed);
  const steps: Step[] = [];
  const act = (op: string, args: unknown[], ret: unknown) => steps.push({ op, args: clone(args), ret: clone(ret), events: clone(b.drain()), state: snapshot(b) });
  const q = (op: string, args: unknown[], ret: unknown) => steps.push({ op, args: clone(args), ret: clone(ret) });
  const spellsOf = (u: BattleUnit) => u.abilities.filter((a) => ABILITIES[a]?.kind === 'spell');
  b.begin(runEnemyAi);
  act('begin', [], null);
  const probe = () => {
    for (const u of b.active()) {
      for (const id of spellsOf(u)) {
        q('canCast', [u.uid, id], b.canCast(u, id));
        q('spellTargets', [u.uid, id, null], b.spellTargets(u, id).map((t) => t.uid));
        const ab = ABILITIES[id];
        const range = ab.range ?? 0;
        for (const t of b.living()) {
          if (Math.hypot(t.x - u.x, t.y - u.y) > range + 2) continue;
          q('spellPreview', [u.uid, id, t.x, t.y, {}], b.spellPreview(u, id, t));
          if (ab.splash && r.chance(0.5)) {
            const p = { x: t.x + r.int(-1, 1), y: t.y + r.int(-1, 1) };
            if (p.x >= 0 && p.y >= 0 && p.x < b.map.w && p.y < b.map.h) q('spellPreview', [u.uid, id, p.x, p.y, {}], b.spellPreview(u, id, p));
          }
        }
        const keys = [...b.reachable(u).keys()];
        const living = b.living();
        if (keys.length && living.length) {
          const p = unkey(r.pick(keys));
          const t = r.pick(living);
          q('spellPreview', [u.uid, id, t.x, t.y, { from: p, movedTiles: 2 }], b.spellPreview(u, id, t, { from: p, movedTiles: 2 }));
        }
      }
      if (u.tags.includes('impale')) {
        for (const t of b.active(u.faction === 'player' ? 'enemy' : 'player')) q('impaleTarget', [u.uid, t.uid], b.impaleTarget(u, t)?.uid ?? null);
      }
    }
  };
  const playerTurn = () => {
    for (const uid of b.active('player').map((u) => u.uid)) {
      if (b.isOver()) return;
      const u = b.unit(uid);
      if (u.status !== 'active') continue;
      const spells = spellsOf(u).filter((id) => b.canCast(u, id).ok);
      if (spells.length && r.chance(0.85)) {
        const id = r.pick(spells);
        const ts = b.spellTargets(u, id);
        if (ts.length) {
          const t = r.pick(ts);
          act('cast', [uid, id, t.x, t.y], b.cast(uid, id, { x: t.x, y: t.y }));
        }
        // A second cast is refused: the squad has acted (or there was no target).
        act('cast', [uid, id, u.x, u.y], b.cast(uid, id, { x: u.x, y: u.y }));
        continue;
      }
      actUnit(b, u, { useStances: true });
      act('actUnit', [uid], null);
    }
  };
  for (let turn = 1; turn <= turns && !b.isOver(); turn++) {
    if (b.phase !== 'player') break;
    probe();
    playerTurn();
    if (b.isOver()) break;
    b.endTurn(runEnemyAi);
    act('endTurn', [], null);
  }
  return { name, kind: 'script', setup: json, steps, result: b.result ?? null };
}

// ------------------------------------------------------------------ generate

const files: Record<string, unknown[]> = {};
const add = (group: string, trace: unknown) => (files[group] ??= []).push(trace);

for (const e of ENCOUNTERS) {
  for (const seed of [1, 2]) add(e.id, autoTrace(`${e.id}/s${seed}`, makeSetup(e.id, seed)));
  add(e.id, autoTrace(`${e.id}/veteran-s3`, makeSetup(e.id, 3, { company: 'veteran', depth: 4, survivalBonus: 0.25 })));
}
// Night battles without torches: darkness shortens every shot.
for (const id of ['goblin_scouts', 'raiding_party', 'road_ambush', 'archer_screen', 'last_stand']) add(id, autoTrace(`${id}/dark-s4`, makeSetup(id, 4, { darkness: true })));
// Both grounds of the last stand, with the warchief's host.
add('last_stand', autoTrace('last_stand/steading-s5', makeSetup('last_stand', 5, { mapId: 'steading', depth: 4 })));
add('last_stand', autoTrace('last_stand/ford-s6', makeSetup('last_stand', 6, { mapId: 'ford', depth: 4, company: 'veteran', survivalBonus: 0.12 })));
add('last_stand', autoTrace('last_stand/steading-s7', makeSetup('last_stand', 7, { mapId: 'steading', depth: 4, company: 'veteran' })));

// Scripted player turns.
add('scripted', scriptedTrace('scripted/raiding_party-veteran', makeSetup('raiding_party', 11, { company: 'veteran' }), 101, { turns: 5, finish: true }));
add('scripted', scriptedTrace('scripted/goblin_scouts-veteran', makeSetup('goblin_scouts', 12, { company: 'veteran' }), 102, { turns: 6, finish: true }));
add('scripted', scriptedTrace('scripted/warband_camp-veteran', makeSetup('warband_camp', 13, { company: 'veteran', survivalBonus: 0.1 }), 103, { turns: 6, shout: true, finish: true }));
add('scripted', scriptedTrace('scripted/road_ambush-dark', makeSetup('road_ambush', 14, { company: 'veteran', darkness: true }), 104, { turns: 4, finish: true }));
add('scripted', scriptedTrace('scripted/brute_vanguard-retreat', makeSetup('brute_vanguard', 15, { company: 'veteran' }), 105, { turns: 4, retreatAt: 3 }));
add('scripted', scriptedTrace('scripted/moss_trolls-fresh', makeSetup('moss_trolls', 16), 106, { turns: 5, finish: true }));
add('scripted', scriptedTrace('scripted/last_stand-veteran', makeSetup('last_stand', 17, { company: 'veteran', mapId: 'ford' }), 107, { turns: 3, shout: true, finish: true }));
add('scripted', scriptedTrace('scripted/refugee_stand-fresh', makeSetup('refugee_stand', 18), 108, { turns: 3, retreatAt: 3 }));

// Battle mages, ballistae and mangonels with the company; shamans, rock lobbers and war wagons with the host.
const MAGIC: [string, number, string?][] = [['shaman_fire', 41], ['siege_train', 42], ['raiding_party', 43], ['moss_trolls', 44], ['last_stand', 45, 'steading'], ['refugee_stand', 46], ['orc_overseer', 47]];
for (const [id, seed, mapId] of MAGIC) add('magic', autoTrace(`magic/${id}-s${seed}`, makeSetup(id, seed, { company: 'magic', depth: 4, mapId })));
add('magic', spellTrace('magic/spells-shaman_fire', makeSetup('shaman_fire', 51, { company: 'magic' }), 151, 6));
add('magic', spellTrace('magic/spells-siege_train', makeSetup('siege_train', 52, { company: 'magic', depth: 4 }), 152, 6));
add('magic', spellTrace('magic/spells-moss_trolls', makeSetup('moss_trolls', 53, { company: 'magic', depth: 4 }), 153, 5));

// Rare outcomes: search seeds for battles that show them (first hit of each).
function features(t: { steps: Step[]; result: string | null | undefined }): Set<string> {
  const f = new Set<string>();
  if (t.result === 'defeat') f.add('defeat');
  if (t.result === 'retreat') f.add('captain-retreat');
  for (const st of t.steps) {
    for (const e of (st.events ?? []) as any[]) {
      if (e.t === 'broken' || e.t === 'overrun' || e.t === 'rally' || e.t === 'halt') f.add(e.t);
      if (e.t === 'down' && !e.dead) f.add('downed');
      if (e.t === 'horn') f.add(`horn:${e.sounded}`);
      if (e.t === 'push') f.add(`push:${e.blocked}`);
      if (e.t === 'log' && e.text.startsWith('The enemy has had enough')) f.add('give-up');
      if (e.t === 'log' && e.text.startsWith('The survivors of')) f.add('left-behind');
      if (e.t === 'attack' && e.reaction === 'firstStrike') f.add('first-strike');
      if (e.t === 'shout') f.add('shout');
    }
  }
  return f;
}
const WANT = ['broken', 'overrun', 'defeat', 'captain-retreat', 'give-up', 'rally', 'downed', 'horn:false', 'horn:true', 'halt', 'left-behind', 'first-strike', 'push:true', 'shout'];
const found = new Set<string>();
const CANDIDATES: [string, Company, string | undefined][] = [
  ['last_stand', 'elite', 'steading'], ['last_stand', 'weak', 'ford'], ['refugee_stand', 'weak', undefined], ['last_stand', 'elite', 'ford'],
  ['moss_trolls', 'weak', undefined], ['goblin_scouts', 'weak', undefined], ['brute_vanguard', 'fresh', undefined], ['warband_camp', 'weak', undefined],
  ['orc_overseer', 'weak', undefined], ['archer_screen', 'weak', undefined], ['last_stand', 'weak', 'steading'], ['warband_camp', 'elite', undefined],
];
search: for (let seed = 20; seed < 200; seed++) {
  for (const [id, company, mapId] of CANDIDATES) {
    const tr = autoTrace(`${id}/${company}${mapId ? '-' + mapId : ''}-s${seed}`, makeSetup(id, seed, { company, mapId, depth: 4, survivalBonus: company === 'weak' ? 0.3 : 0 }));
    const fresh = [...features(tr)].filter((f) => WANT.includes(f) && !found.has(f));
    if (!fresh.length) continue;
    for (const f of fresh) found.add(f);
    tr.name += ` [${fresh.join(',')}]`;
    add('extra', tr);
    if (found.size === WANT.length) break search;
  }
}

for (let seed = 30; seed < 60; seed++) {
  const t = warchiefTrace(seed);
  if (t) {
    add('scripted', t);
    found.add('broken');
    break;
  }
}

console.log(`rare outcomes found: ${[...found].join(' ')}; missing: ${WANT.filter((w) => !found.has(w)).join(' ') || 'none'}`);

let total = 0;
let traces = 0;
let events = 0;
for (const [group, list] of Object.entries(files)) {
  const text = JSON.stringify({ version: 1, traces: list });
  writeFileSync(join(outDir, `${group}.json`), text + '\n');
  total += text.length;
  for (const t of list as any[]) {
    traces++;
    for (const st of t.steps) {
      events += st.events?.length ?? 0;
      countEvents(st.events ?? []);
    }
  }
  console.log(`${group}.json  ${(text.length / 1e6).toFixed(2)} MB  ${(list as any[]).map((t) => `${t.name.split('/')[1]}:${t.result}@${t.turns ?? '-'}${t.ms !== undefined ? `/${t.ms}ms` : ''}`).join(' ')}`);
}
console.log(`${traces} traces, ${events} events, ${(total / 1e6).toFixed(1)} MB`);
console.log(Object.entries(eventCounts).sort().map(([k, v]) => `${k}=${v}`).join(' '));
