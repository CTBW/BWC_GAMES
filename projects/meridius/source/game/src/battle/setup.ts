import { Rng } from '../core/rng';
import { encounterById } from '../data/encounters';
import { BATTLE_MAPS } from '../data/maps';
import { MILITIA_LEADERS, WARCHIEF_NAMES } from '../data/names';
import { makeEnemy } from '../meta/soldier';
import { INWARD } from './battle';
import { dirTo, dist, tilePassable } from './grid';
import { isBackline } from './squad';
import { OUTWARD, TRANSPOSED, generateMap } from './mapgen';
import type { BattleKind, BattleMap, BattleObjective, BattleSetup, BattleUnit, Edge, Pt, Wave, WaveUnit } from './types';

export interface EncounterRoll {
  encounterId: string;
  mapId: string;
  seed: number;
  /** Enemy type ids with levels, rolled when the node is generated. */
  enemies: { typeId: string; level: number }[];
  ambush: boolean;
  /** Reinforcements, with edges in the map template's own terms (rolls saved before the horde have none). */
  waves?: Wave[];
  /** Local defenders beside the company. */
  allies?: WaveUnit[];
}

export function rollEncounter(encounterId: string, rng: Rng, depth: number): EncounterRoll {
  const e = encounterById(encounterId);
  const level = () => Math.min(e.level[1], e.level[0] + (rng.chance(0.15 + depth * 0.1) ? 1 : 0));
  const rollUnits = (list: [string, number, number][]): WaveUnit[] => {
    const out: WaveUnit[] = [];
    for (const [typeId, min, max] of list) {
      const n = rng.int(min, max);
      for (let i = 0; i < n; i++) out.push({ typeId, level: level() });
    }
    return out;
  };
  const enemies = rollUnits(e.units);
  const mapId = rng.pick(e.ambush ? e.maps.filter((m) => !BATTLE_MAPS[m].river) : e.maps);
  const tpl = BATTLE_MAPS[mapId];
  const main = tpl.edges?.main ?? 'n';
  const flanks = tpl.edges?.flank ?? ['w', 'e'];
  const waves: Wave[] = (e.waves ?? []).map((w) => {
    const units = rollUnits(w.units);
    if (w.warchief) {
      const chief = units.find((u) => u.typeId === w.warchief);
      if (chief) chief.warchief = true;
    }
    const edge: Edge = w.edge === 'main' ? main : w.edge === 'flank' ? rng.pick(flanks) : w.edge;
    return { turn: w.turn, edge, units, horn: w.horn, final: w.final, label: w.label };
  });
  const allies = (e.allies ?? []).flatMap(([typeId, n]) => Array.from({ length: n }, () => ({ typeId, level: 1 })));
  return { encounterId, mapId, seed: rng.int(1, 2 ** 31 - 1), enemies, ambush: !!e.ambush, waves, allies };
}

/** Deployment order: shields in front, then spears and levies, missiles, casters and war machines at the back. */
function rank(u: BattleUnit): number {
  if (isBackline(u)) return 3;
  if (u.typeId === 'footman' || u.typeId === 'collie_guard') return 0;
  if (u.typeId === 'spearman') return 1;
  return 2;
}

const centre = (ps: Pt[]): Pt => ({ x: ps.reduce((s, p) => s + p.x, 0) / ps.length, y: ps.reduce((s, p) => s + p.y, 0) / ps.length });

/** Place the player's army in a formation: shields toward the enemy, crossbows behind. */
export function deployPlayer(map: BattleMap, units: BattleUnit[], ambush: boolean) {
  const zone = map.playerDeploy.slice();
  const sorted = units.slice().sort((a, b) => rank(a) - rank(b));
  if (ambush) {
    const mid = { x: map.w / 2 - 0.5, y: map.h / 2 - 0.5 };
    zone.sort((a, b) => dist(a, mid) - dist(b, mid));
    // Ranged in the middle, melee around them.
    const ranged = sorted.filter((u) => isBackline(u));
    const melee = sorted.filter((u) => !isBackline(u));
    let i = 0;
    for (const u of [...ranged, ...melee]) {
      const p = zone[i++];
      u.x = p.x;
      u.y = p.y;
    }
    return;
  }
  // Behind walls: hold the ways in. Each gateway, breach or gap into the
  // deployment ground gets a shield or spear squad, nearest the enemy first;
  // missiles and levies stand behind them.
  if (map.scale === 'large') {
    const inside = new Set(zone.map((p) => `${p.x},${p.y}`));
    const foeC = centre(map.enemyDeploy.length ? map.enemyDeploy : [{ x: map.w / 2, y: 0 }]);
    // A way in is a gap at most two tiles wide in a wall or fence: count the
    // open tiles across the gap, two either side.
    const narrow = (q: Pt, dx: number, dy: number) => {
      let open = 0;
      for (let s = -2; s <= 2; s++) if (tilePassable(map, q.x + dy * s, q.y + dx * s)) open++;
      return open <= 2;
    };
    const ways = zone
      .filter((p) =>
        [[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dy]) => {
          const q = { x: p.x + dx, y: p.y + dy };
          return !inside.has(`${q.x},${q.y}`) && tilePassable(map, q.x, q.y) && narrow(q, dx, dy);
        }),
      )
      .sort((a, b) => dist(a, foeC) - dist(b, foeC));
    // Only the narrow ways in: a long open edge is not a gate.
    if (ways.length > 0 && ways.length <= 8) {
      const used = new Set<string>();
      const take = (p: Pt, u: BattleUnit) => {
        used.add(`${p.x},${p.y}`);
        u.x = p.x;
        u.y = p.y;
      };
      const holders = sorted.filter((u) => !isBackline(u) && !u.tags.includes('militia'));
      const rest = sorted.filter((u) => !holders.includes(u));
      ways.forEach((p, i) => holders[i] && take(p, holders[i]));
      const spare = holders.slice(ways.length).concat(rest);
      const mid = centre(ways.length ? ways : zone);
      for (const u of spare) {
        // Behind the ways in: close to them, but not on them.
        const free = zone.filter((p) => !used.has(`${p.x},${p.y}`)).sort((a, b) => dist(a, mid) - dist(b, mid) + (u.shot ? 0 : 0));
        const p = free.find((q) => !ways.some((w) => w.x === q.x && w.y === q.y)) ?? free[0];
        if (p) take(p, u);
      }
      return;
    }
  }
  // Forward is toward the enemy's ground; ranks stand across that line.
  const foe = centre(map.enemyDeploy.length ? map.enemyDeploy : [{ x: map.w / 2, y: 0 }]);
  const mid = centre(zone);
  const len = dist(mid, foe) || 1;
  const fx = (foe.x - mid.x) / len;
  const fy = (foe.y - mid.y) / len;
  const depth = (p: Pt) => -((p.x - mid.x) * fx + (p.y - mid.y) * fy);
  const lateral = (p: Pt) => Math.abs((p.x - mid.x) * fy - (p.y - mid.y) * fx);
  const front = Math.min(...zone.map(depth));
  const used = new Set<string>();
  for (const u of sorted) {
    const want = front + [0, 1, 1.6, 2.4][rank(u)];
    let best: Pt | undefined;
    let bestCost = Infinity;
    for (const p of zone) {
      if (used.has(`${p.x},${p.y}`)) continue;
      const c = Math.abs(depth(p) - want) * 2 + lateral(p) * 0.7;
      if (c < bestCost) {
        bestCost = c;
        best = p;
      }
    }
    const p = best ?? zone[0];
    used.add(`${p.x},${p.y}`);
    u.x = p.x;
    u.y = p.y;
  }
}

export function deployEnemies(map: BattleMap, units: BattleUnit[], rng: Rng, ambush: boolean) {
  const zone = rng.shuffle(map.enemyDeploy.slice());
  const melee = units.filter((u) => !isBackline(u));
  const ranged = units.filter((u) => isBackline(u));
  const midY = map.h / 2;
  // Ranged prefer rows far from the player; melee the near rows.
  const far = (p: Pt) => (ambush ? -Math.abs(p.y - midY) : p.y);
  const byFar = zone.slice().sort((a, b) => far(a) - far(b));
  const used = new Set<string>();
  const place = (u: BattleUnit, list: Pt[]) => {
    const p = list.find((q) => !used.has(`${q.x},${q.y}`));
    if (!p) return;
    used.add(`${p.x},${p.y}`);
    u.x = p.x;
    u.y = p.y;
  };
  for (const u of ranged) place(u, byFar);
  const near = byFar.slice().reverse();
  for (const u of melee) place(u, u.leader ? byFar : near);
}

/** Every squad takes the field facing the nearest enemies (the centre of the three closest). */
export function faceEachOther(units: BattleUnit[]) {
  for (const u of units) {
    if (u.status === 'reserve') continue;
    const foes = units
      .filter((f) => f.faction !== u.faction && f.status !== 'reserve')
      .sort((a, b) => dist(a, u) - dist(b, u))
      .slice(0, 3);
    if (!foes.length) continue;
    u.facing = dirTo(u, centre(foes));
  }
}

/** A local levy fighting beside the company: player-controlled, not on the roster. */
function makeAlly(typeId: string, level: number, uid: string, rng: Rng, leader: string): BattleUnit {
  const u = makeEnemy(typeId, level, uid, rng);
  u.faction = 'player';
  u.name = `${leader}, militia`;
  return u;
}

/**
 * Where the squads of coming waves wait beyond their edge, in view: lined up
 * behind the entry tiles, later waves further back.
 */
function stage(map: BattleMap, waves: (Wave & { uids: string[] })[], byUid: Map<string, BattleUnit>) {
  const rankAt = new Map<Edge, number>();
  for (const w of waves.slice().sort((a, b) => a.turn - b.turn)) {
    const lanes = map.entries?.[w.edge] ?? [];
    const out = OUTWARD[w.edge];
    const r = rankAt.get(w.edge) ?? 0;
    rankAt.set(w.edge, r + Math.ceil(w.uids.length / Math.max(1, Math.min(lanes.length, 4))) + 1);
    w.uids.forEach((uid, i) => {
      const u = byUid.get(uid)!;
      if (!lanes.length) return;
      const width = Math.min(lanes.length, 4);
      const lane = lanes[i % width];
      const d = 2 + r + Math.floor(i / width);
      u.x = lane.x + out.x * d;
      u.y = lane.y + out.y * d;
    });
  }
}

export function buildBattle(
  roll: EncounterRoll,
  army: BattleUnit[],
  opts: { survivalBonus: number; darkness?: boolean; title?: string },
): BattleSetup {
  const enc = encounterById(roll.encounterId);
  const rng = new Rng(roll.seed ^ 0x5bd1e995);
  const waves = (roll.waves ?? []).map((w) => ({ ...w, units: w.units.slice() }));
  const tpl = BATTLE_MAPS[roll.mapId];
  const approaches = [...new Set<Edge>([tpl.edges?.main ?? 'n', ...waves.map((w) => w.edge)])];
  const map = generateMap(roll.mapId, roll.seed, { ambush: roll.ambush, approaches });
  const toGrid = (e: Edge): Edge => (map.transposed ? TRANSPOSED[e] : e);
  const enemies = roll.enemies.map((e, i) => makeEnemy(e.typeId, e.level, `e${i}`, rng));
  const leaders = rng.shuffle(MILITIA_LEADERS.slice());
  const allies = (roll.allies ?? []).map((a, i) => makeAlly(a.typeId, a.level, `m${i}`, rng, leaders[i % leaders.length]));
  if (enc.kind === 'stand') {
    // Before a stand the company rallies: the people it defends come out to stand beside it.
    for (const u of army) u.morale = u.maxMorale;
  }
  // A badly depleted company meets a slightly thinner host: the rabble and
  // spears at the back of the waves stay behind. The warchief and his
  // monsters always come.
  const men = army.reduce((n, u) => n + u.alive, 0);
  const strength = Math.min(1, men / 34);
  const spareable = waves.flatMap((w) => w.units.map((u, i) => ({ w, i, u }))).filter((x) => !x.u.warchief && (x.u.typeId === 'goblin_rabble' || x.u.typeId === 'goblin_spear'));
  const drop = Math.round(spareable.length * (1 - strength) * 1.2);
  const dropSet = new Set(rng.shuffle(spareable.slice()).slice(0, drop));
  for (const w of waves) w.units = w.units.filter((u, i) => ![...dropSet].some((d) => d.w === w && d.i === i));
  deployPlayer(map, [...army, ...allies], roll.ambush);
  deployEnemies(map, enemies, rng, roll.ambush);
  const reserve: BattleUnit[] = [];
  const setupWaves = waves.map((w, wi) => {
    const edge = toGrid(w.edge);
    const uids = w.units.map((wu, i) => {
      const u = makeEnemy(wu.typeId, wu.level, `w${wi}-${i}`, rng);
      if (wu.warchief) {
        u.tags.push('warchief');
        u.name = rng.pick(WARCHIEF_NAMES);
      }
      u.status = 'reserve';
      u.facing = INWARD[edge];
      reserve.push(u);
      return u.uid;
    });
    return { ...w, edge, units: w.units.map((u) => ({ ...u })), uids };
  });
  stage(map, setupWaves, new Map(reserve.map((u) => [u.uid, u])));
  faceEachOther([...army, ...allies, ...enemies]);
  const objective: BattleObjective = enc.goal ? { ...enc.goal } : { kind: 'rout', title: 'Rout the enemy', brief: 'Destroy or drive off every enemy squad.' };
  const kind: BattleKind = enc.kind ?? 'skirmish';
  return {
    seed: roll.seed,
    map,
    units: [...army, ...allies, ...enemies, ...reserve],
    survivalBonus: opts.survivalBonus,
    ambush: roll.ambush,
    enemyFirst: roll.ambush,
    darkness: opts.darkness,
    title: opts.title ?? enc.name,
    encounterId: roll.encounterId,
    kind,
    objective,
    waves: setupWaves,
  };
}
