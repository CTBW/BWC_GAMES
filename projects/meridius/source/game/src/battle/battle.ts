import { Rng } from '../core/rng';
import type { AbilityDef, Dir, Faction, StatusId } from '../core/types';
import { ABILITIES } from '../data/abilities';
import { UNIT_TYPES } from '../data/units';
import { PROPS, TERRAIN } from '../data/terrain';
import { damageSquad, hasStatus, healSquad, killsFrom, memberNoun, moveOf, squadName, statusOf } from './squad';
import {
  DIRS,
  canStep,
  dirTo,
  dist,
  isEdge,
  key,
  lineOfSight,
  manhattan,
  moveCost,
  neighbors,
  tileAt,
  tilePassable,
  unitAt,
} from './grid';
import type {
  Arc,
  AttackPreview,
  BattleEvent,
  BattleMap,
  BattleObjective,
  BattleResult,
  BattleSetup,
  BattleUnit,
  Edge,
  MoraleState,
  Pt,
  SpellHit,
  SpellPreview,
  Wave,
} from './types';

/** In a rout battle, the enemy gives up at the end of this turn if no more help is coming. */
export const GIVE_UP_TURN = 14;

/** The step that carries a squad from beyond an edge onto the field: the way it faces on arrival. */
export const INWARD: Record<Edge, Dir> = { n: 1, w: 0, e: 2, s: 3 };

const DEFAULT_OBJECTIVE: BattleObjective = { kind: 'rout', title: 'Rout the enemy', brief: 'Destroy or drive off every enemy squad.' };

export interface ReachInfo {
  cost: number;
  prev: number;
  /** Zone-of-control exits along the cheapest path (free attacks provoked). */
  zoc: number;
}

/**
 * One way to end a move on a tile. A squad faces the direction of the last
 * step it took, so each tile can be reached with up to four facings, each by
 * its own path. Ending on the start tile with a new facing means stepping out
 * and back.
 */
export interface FacingOption {
  facing: Dir;
  cost: number;
  zoc: number;
  /** Tiles walked, start first; a single tile when the squad stays put. */
  path: Pt[];
}

/** Search state: a tile plus the facing the squad arrived with. */
const skey = (x: number, y: number, d: Dir) => key(x, y) * 4 + d;
const unkeyState = (s: number): Pt => {
  const k = Math.floor(s / 4);
  return { x: k % 1000, y: Math.floor(k / 1000) };
};

export interface AttackOpts {
  from?: Pt;
  ability?: string;
  reaction?: 'zoc' | 'spearwall' | 'overwatch' | 'firstStrike';
  /** Force melee for units that could also shoot. */
  forceMelee?: boolean;
  /** Assume the attacker moved this many tiles (for previews of move+attack). */
  movedTiles?: number;
}

/** Chance that a fallen soldier was only wounded (plus 5% per level and the infirmary/bandage bonus). */
export const FALL_SURVIVAL_BASE = 0.45;

export class Battle {
  map: BattleMap;
  units: BattleUnit[];
  rng: Rng;
  turn = 1;
  phase: 'deploy' | 'player' | 'enemy' | 'over' = 'deploy';
  result?: BattleResult;
  events: BattleEvent[] = [];
  setup: BattleSetup;
  /** Hits taken per unit (armour wear). */
  hitsTaken: Record<string, number> = {};
  /** This turn's player moves that can still be redone, by unit. */
  moveRecords = new Map<string, { x: number; y: number; facing: Dir; movedTiles: number; path: Pt[]; clean: boolean }>();
  /** What became of each wave of reinforcements. */
  waveState: ('pending' | 'arrived' | 'cancelled')[] = [];
  /** Waves whose arrival has been announced. */
  private waveSeen = new Set<number>();
  /** The war horn: still to be sounded, sounded (its waves are coming), or silenced with its bearer. */
  horn: 'waiting' | 'sounded' | 'silent' = 'waiting';
  /** Consecutive enemy turns that ended with the held ground taken. */
  overrun = 0;

  constructor(setup: BattleSetup) {
    this.setup = setup;
    this.map = setup.map;
    this.units = setup.units;
    this.rng = new Rng(setup.seed);
    for (const u of this.units) this.hitsTaken[u.uid] = 0;
    this.waveState = this.waves.map(() => 'pending');
  }

  get objective(): BattleObjective {
    return this.setup.objective ?? DEFAULT_OBJECTIVE;
  }

  get waves(): (Wave & { uids: string[] })[] {
    return this.setup.waves ?? [];
  }

  /** Waves still to come. A horn wave counts while the horn may yet sound. */
  pendingWaves(): number {
    return this.waveState.filter((s) => s === 'pending').length;
  }

  /** The next wave due, with the enemy turn it arrives on (horn waves only once sounded). */
  nextWave(): { index: number; wave: Wave & { uids: string[] }; turn: number } | undefined {
    let best: { index: number; wave: Wave & { uids: string[] }; turn: number } | undefined;
    this.waves.forEach((w, i) => {
      if (this.waveState[i] !== 'pending' || (w.horn && this.horn !== 'sounded')) return;
      if (!best || w.turn < best.turn) best = { index: i, wave: w, turn: w.turn };
    });
    return best;
  }

  /** Company squads (the militia fights beside them but cannot carry the day alone). */
  company(): BattleUnit[] {
    return this.active('player').filter((u) => !u.tags.includes('militia'));
  }

  // ---------------------------------------------------------------- queries

  unit(uid: string): BattleUnit {
    const u = this.units.find((x) => x.uid === uid);
    if (!u) throw new Error(`no unit ${uid}`);
    return u;
  }

  living(faction?: Faction): BattleUnit[] {
    return this.units.filter(
      (u) => (u.status === 'active' || u.status === 'routing') && (!faction || u.faction === faction),
    );
  }

  active(faction?: Faction): BattleUnit[] {
    return this.units.filter((u) => u.status === 'active' && (!faction || u.faction === faction));
  }

  enemiesOf(u: BattleUnit): BattleUnit[] {
    return this.active(u.faction === 'player' ? 'enemy' : 'player');
  }

  alliesOf(u: BattleUnit): BattleUnit[] {
    return this.active(u.faction).filter((a) => a.uid !== u.uid);
  }

  tile(p: Pt) {
    return tileAt(this.map, p.x, p.y)!;
  }

  moraleState(u: BattleUnit): MoraleState {
    if (u.status === 'routing' || u.morale <= 0) return 'broken';
    const r = u.morale / u.maxMorale;
    if (r >= 0.9) return 'confident';
    if (r >= 0.5) return 'steady';
    if (r >= 0.25) return 'shaken';
    return 'wavering';
  }

  /** Arc from which `target` is attacked by someone standing at `from`. */
  arcOf(target: BattleUnit, from: Pt): Arc {
    const f = DIRS[target.facing];
    const dx = from.x - target.x;
    const dy = from.y - target.y;
    const len = Math.hypot(dx, dy) || 1;
    const cos = (f.x * dx + f.y * dy) / len;
    const angle = (Math.acos(Math.max(-1, Math.min(1, cos))) * 180) / Math.PI;
    if (angle <= 60) return 'front';
    if (angle < 120) return 'flank';
    return 'rear';
  }

  isAdjacentEnemy(u: BattleUnit, p: Pt = u): boolean {
    return this.enemiesOf(u).some((e) => manhattan(e, p) === 1);
  }

  /** Destinations the unit can end its move on. */
  reachable(u: BattleUnit, budget = moveOf(u)): Map<number, ReachInfo> {
    const out = this.reachableFull(u, budget);
    const start = key(u.x, u.y);
    for (const [k] of out) {
      if (k === start) continue;
      if (unitAt(this.units, k % 1000, Math.floor(k / 1000))) out.delete(k);
    }
    return out;
  }

  pathFrom(reach: Map<number, ReachInfo>, x: number, y: number): Pt[] | null {
    let k = key(x, y);
    if (!reach.has(k)) return null;
    // Walk back through prev links; intermediate tiles may have been pruned
    // from the map only if occupied by allies, so rebuild via a full search.
    const path: Pt[] = [];
    const guard = new Set<number>();
    while (k !== -1) {
      if (guard.has(k)) return null;
      guard.add(k);
      path.push({ x: k % 1000, y: Math.floor(k / 1000) });
      const info = reach.get(k);
      if (!info) {
        return null;
      }
      k = info.prev;
    }
    return path.reverse();
  }

  /** Path to a tile, arriving with the default facing (see `defaultFacing`). */
  pathTo(u: BattleUnit, x: number, y: number): Pt[] | null {
    if (unitAt(this.units, x, y) && !(x === u.x && y === u.y)) return null;
    const opt = this.moveOption(u, x, y);
    return opt && opt.path.length > 1 ? opt.path : null;
  }

  /**
   * Tiles a foe can strike at a squad leaving them: its front and flanks.
   * A squad cannot strike what it cannot see, so its rear tile is free.
   */
  zocTiles(u: BattleUnit): Set<number> {
    const out = new Set<number>();
    // Skirmishers (wolf riders) wheel away before a blow can land.
    if (u.tags.includes('skirmish')) return out;
    for (const f of this.enemiesOf(u)) {
      for (const n of neighbors(this.map, f)) {
        if (this.arcOf(f, n) === 'rear') continue;
        if (Math.abs(this.tile(n).h - this.tile(f).h) > 1) continue;
        out.add(key(n.x, n.y));
      }
    }
    return out;
  }

  /**
   * Dijkstra over (tile, facing on arrival): the facing is always the
   * direction of the last step. Allies can be passed through, not enemies.
   * Cheapest first, then fewest free attacks provoked.
   */
  reachStates(u: BattleUnit, budget = moveOf(u)): Map<number, ReachInfo> {
    const out = new Map<number, ReachInfo>();
    const s0 = skey(u.x, u.y, u.facing);
    out.set(s0, { cost: 0, prev: -1, zoc: 0 });
    const open: { s: number; p: Pt; cost: number; zoc: number }[] = [{ s: s0, p: { x: u.x, y: u.y }, cost: 0, zoc: 0 }];
    const foeAt = new Set(this.enemiesOf(u).map((f) => key(f.x, f.y)));
    const zocTiles = this.zocTiles(u);
    while (open.length) {
      let bi = 0;
      for (let i = 1; i < open.length; i++) {
        const a = open[i];
        const b = open[bi];
        if (a.cost < b.cost || (a.cost === b.cost && a.zoc < b.zoc)) bi = i;
      }
      const cur = open[bi];
      open[bi] = open[open.length - 1];
      open.pop();
      const best = out.get(cur.s)!;
      if (cur.cost > best.cost || (cur.cost === best.cost && cur.zoc > best.zoc)) continue;
      const leaving = zocTiles.has(key(cur.p.x, cur.p.y)) ? 1 : 0;
      for (let d = 0 as Dir; d < 4; d = (d + 1) as Dir) {
        const n = { x: cur.p.x + DIRS[d].x, y: cur.p.y + DIRS[d].y };
        if (!tileAt(this.map, n.x, n.y)) continue;
        if (foeAt.has(key(n.x, n.y))) continue;
        if (!tilePassable(this.map, n.x, n.y)) continue;
        if (!canStep(this.map, cur.p, n)) continue;
        const c = cur.cost + moveCost(this.map, n.x, n.y);
        if (c > budget) continue;
        const z = cur.zoc + leaving;
        const ns = skey(n.x, n.y, d);
        const prev = out.get(ns);
        if (!prev || c < prev.cost || (c === prev.cost && z < prev.zoc)) {
          out.set(ns, { cost: c, prev: cur.s, zoc: z });
          open.push({ s: ns, p: n, cost: c, zoc: z });
        }
      }
    }
    return out;
  }

  /** Cheapest way to each tile, whatever the facing (prev links follow tiles). */
  reachableFull(u: BattleUnit, budget = moveOf(u)): Map<number, ReachInfo> {
    const states = this.reachStates(u, budget);
    const out = new Map<number, ReachInfo>();
    out.set(key(u.x, u.y), { cost: 0, prev: -1, zoc: 0 });
    for (const [s, info] of states) {
      const k = Math.floor(s / 4);
      const prev = out.get(k);
      if (!prev || info.cost < prev.cost || (info.cost === prev.cost && info.zoc < prev.zoc)) {
        out.set(k, { cost: info.cost, prev: info.prev < 0 ? -1 : Math.floor(info.prev / 4), zoc: info.zoc });
      }
    }
    return out;
  }

  /** Every facing the squad can end its move on (x, y) with, and the path for each. */
  facingOptions(u: BattleUnit, x: number, y: number, states = this.reachStates(u)): FacingOption[] {
    const home = x === u.x && y === u.y;
    if (!home && unitAt(this.units, x, y)) return [];
    const out: FacingOption[] = [];
    for (let d = 0 as Dir; d < 4; d = (d + 1) as Dir) {
      const s = skey(x, y, d);
      const info = states.get(s);
      if (!info) continue;
      const path: Pt[] = [];
      let cur = s;
      while (cur !== -1) {
        path.push(unkeyState(cur));
        cur = states.get(cur)!.prev;
      }
      path.reverse();
      out.push({ facing: d, cost: info.cost, zoc: info.zoc, path });
    }
    return out;
  }

  /**
   * The facing a squad takes when nobody chooses: never more free attacks
   * than the safest way in, then facing the nearest enemy, else turned side
   * on rather than showing its back, then the shortest walk.
   */
  defaultFacing(u: BattleUnit, x: number, y: number, options: FacingOption[]): FacingOption | undefined {
    if (!options.length) return undefined;
    const minZoc = Math.min(...options.map((o) => o.zoc));
    const safe = options.filter((o) => o.zoc === minZoc);
    const foes = this.enemiesOf(u);
    if (!foes.length) return safe.slice().sort((a, b) => a.cost - b.cost)[0];
    const at = { x, y };
    const near = foes.reduce((m, f) => (dist(f, at) < dist(m, at) ? f : m));
    const want = dirTo(at, near);
    const score = (o: FacingOption) => {
      const off = Math.abs(o.facing - want) % 2 === 0 ? (o.facing === want ? 0 : 2) : 1;
      return off * 100 + o.cost;
    };
    return safe.slice().sort((a, b) => score(a) - score(b))[0];
  }

  /** The way the squad would end a move on (x, y): with `facing` if that is possible, else the default. */
  moveOption(u: BattleUnit, x: number, y: number, facing?: Dir): FacingOption | undefined {
    const options = this.facingOptions(u, x, y);
    if (facing !== undefined) {
      const o = options.find((q) => q.facing === facing);
      if (o) return o;
    }
    return this.defaultFacing(u, x, y, options);
  }

  /** The facing toward the nearest enemies (deployment and new arrivals). */
  facingTowardFoes(u: BattleUnit, at: Pt = u): Dir {
    const foes = this.units
      .filter((f) => f.faction !== u.faction && f.status === 'active')
      .sort((a, b) => dist(a, at) - dist(b, at))
      .slice(0, 3);
    if (!foes.length) return u.facing;
    const cx = foes.reduce((s, f) => s + f.x, 0) / foes.length;
    const cy = foes.reduce((s, f) => s + f.y, 0) / foes.length;
    return dirTo(at, { x: cx, y: cy });
  }

  canMelee(a: BattleUnit, t: BattleUnit, from: Pt = a, reach = 1): boolean {
    const ta = this.tile(from);
    const tt = this.tile(t);
    if (Math.abs(ta.h - tt.h) > 1) return false;
    if (reach === 1) return manhattan(from, t) === 1;
    // Straight line, exactly two tiles, nothing solid in between.
    const dx = t.x - from.x;
    const dy = t.y - from.y;
    if (!((Math.abs(dx) === 2 && dy === 0) || (Math.abs(dy) === 2 && dx === 0))) return false;
    const mid = tileAt(this.map, from.x + dx / 2, from.y + dy / 2)!;
    if (mid.prop && PROPS[mid.prop].los === 2) return false;
    if (mid.h > Math.max(ta.h, tt.h)) return false;
    return true;
  }

  shotRange(a: BattleUnit, from: Pt, t: Pt): number {
    if (!a.shot) return 0;
    const dh = this.tile(from).h - this.tile(t).h;
    return a.shot.range + Math.max(0, dh);
  }

  canShoot(a: BattleUnit, t: BattleUnit, from: Pt = a): { ok: boolean; reason?: string } {
    if (!a.shot) return { ok: false, reason: 'No ranged weapon' };
    if (a.ammo === 0) return { ok: false, reason: 'Out of bolts' };
    const d = dist(from, t);
    if (d < a.shot.minRange) return { ok: false, reason: 'Too close to shoot' };
    if (d > this.shotRange(a, from, t) + 0.01) return { ok: false, reason: 'Out of range' };
    if (this.setup.darkness && d > a.shot.range - 2) return { ok: false, reason: 'Too dark to see' };
    const los = lineOfSight(this.map, from, t);
    if (los.blocked) return { ok: false, reason: 'No line of sight' };
    return { ok: true };
  }

  /** Whether the default attack against this target would be a shot. */
  wouldShoot(a: BattleUnit, t: BattleUnit, from: Pt = a): boolean {
    return !!a.shot && manhattan(from, t) > 1 && this.canShoot(a, t, from).ok;
  }

  preview(a: BattleUnit, t: BattleUnit, opts: AttackOpts = {}): AttackPreview {
    const from = opts.from ?? { x: a.x, y: a.y };
    const ab: AbilityDef | undefined = opts.ability ? ABILITIES[opts.ability] : undefined;
    const ranged = ab ? !!ab.ranged : !opts.forceMelee && this.wouldShoot(a, t, from);
    const mods: [string, number][] = [];
    let legal = true;
    let reason: string | undefined;

    if (ranged) {
      const s = this.canShoot(a, t, from);
      if (!s.ok) {
        legal = false;
        reason = s.reason;
      } else if (a.tags.includes('engine') && !opts.reaction && (opts.movedTiles ?? a.movedTiles) > 0) {
        // A war machine has to be braced and laid before it can loose.
        legal = false;
        reason = 'Cannot loose in a turn it has moved';
      }
    } else {
      const reach = ab?.reach ?? 1;
      if (!this.canMelee(a, t, from, reach)) {
        legal = false;
        reason = reach > 1 ? 'Needs a straight line two tiles away' : 'Not adjacent';
      }
    }

    const arc = this.arcOf(t, from);
    let chance = ranged ? a.stats.ranged : a.stats.melee;
    mods.push([ranged ? 'Ranged skill' : 'Melee skill', chance]);

    let def = ranged ? t.stats.rangedDefense : t.stats.defense;
    const tTile = this.tile(t);
    def += TERRAIN[tTile.terrain].defenseMod;
    // Holding a gateway: the posts and the narrow way shelter the defenders.
    if (tTile.prop && PROPS[tTile.prop].defense) def += PROPS[tTile.prop].defense!;
    const shieldArcs: Arc[] = t.stance === 'shieldwall' ? ['front', 'flank'] : ['front'];
    if (t.shieldFront && shieldArcs.includes(arc)) def += t.shieldFront;
    if (t.stance === 'shieldwall') def += ranged ? 15 : 20;
    if (
      this.alliesOf(t).some((x) => x.stance === 'shieldwall' && manhattan(x, t) === 1) &&
      t.stance !== 'shieldwall'
    )
      def += 6;
    const tms = this.moraleState(t);
    if (tms === 'shaken') def -= 5;
    if (tms === 'wavering') def -= 10;
    chance -= def;
    mods.push(['Target defense', -def]);
    if (hasStatus(t, 'chilled')) {
      chance += 10;
      mods.push(['Target chilled', 10]);
    }
    if (hasStatus(t, 'bloodlust')) {
      chance += 8;
      mods.push(['Target in a frenzy', 8]);
    }

    if (t.status === 'routing') {
      chance += 15;
      mods.push(['Fleeing target', 15]);
    }
    if (arc === 'flank') {
      chance += 10;
      mods.push(['Flank attack', 10]);
    } else if (arc === 'rear') {
      chance += 20;
      mods.push(['Attack from behind', 20]);
    }

    const dh = this.tile(from).h - tTile.h;
    if (dh !== 0) {
      const hm = Math.max(-16, Math.min(16, dh * 8));
      chance += hm;
      mods.push([hm > 0 ? 'High ground' : 'Attacking uphill', hm]);
    }

    const ams = this.moraleState(a);
    const am = ams === 'confident' ? 5 : ams === 'shaken' ? -8 : ams === 'wavering' ? -15 : 0;
    if (am) {
      chance += am;
      mods.push([ams === 'confident' ? 'Confident' : ams === 'shaken' ? 'Shaken' : 'Wavering', am]);
    }
    if (hasStatus(a, 'chilled')) {
      chance -= 10;
      mods.push(['Chilled', -10]);
    }
    if (!ranged && hasStatus(a, 'bloodlust')) {
      chance += 10;
      mods.push(['Bloodlust', 10]);
    }

    if (ranged && legal) {
      const d = dist(from, t);
      if (d > 4) {
        const m = -Math.round((d - 4) * 4);
        chance += m;
        mods.push(['Long range', m]);
      }
      const los = lineOfSight(this.map, from, t);
      if (los.partial) {
        chance -= los.partial * 10;
        mods.push(['Obstructed view', -los.partial * 10]);
      }
      const between = los.tiles.filter((p) => unitAt(this.units, p.x, p.y)).length;
      if (between) {
        chance -= between * 12;
        mods.push(['Shooting past troops', -between * 12]);
      }
      const last = los.tiles.length ? los.tiles[los.tiles.length - 1] : undefined;
      if (last && manhattan(last, t) <= 1) {
        const lt = tileAt(this.map, last.x, last.y)!;
        if (lt.prop && PROPS[lt.prop].cover) {
          chance -= PROPS[lt.prop].cover;
          mods.push([`Behind ${PROPS[lt.prop].name.toLowerCase()}`, -PROPS[lt.prop].cover]);
        }
      }
      const tc = TERRAIN[tTile.terrain].rangedCover;
      if (tc) {
        chance -= tc;
        mods.push([`In ${TERRAIN[tTile.terrain].name.toLowerCase()}`, -tc]);
      }
      if (this.isAdjacentEnemy(a, from)) {
        chance -= 15;
        mods.push(['Engaged in melee', -15]);
      }
      const moved = opts.movedTiles !== undefined ? opts.movedTiles > 0 : a.hasMoved;
      if (!moved && !opts.reaction) {
        chance += 8;
        mods.push(['Steady aim', 8]);
      }
      if (this.setup.darkness) {
        chance -= 10;
        mods.push(['Darkness', -10]);
      }
    }

    if (!ranged && a.tags.includes('swarm')) {
      const pack = this.alliesOf(a).filter((x) => manhattan(x, t) === 1 && !(x.x === from.x && x.y === from.y)).length;
      if (pack) {
        const m = Math.min(15, pack * 5);
        chance += m;
        mods.push(['Pack tactics', m]);
      }
    }

    if (ab?.hitMod) {
      chance += ab.hitMod;
      mods.push([ab.name, ab.hitMod]);
    }
    if (opts.reaction === 'overwatch') {
      chance -= 5;
      mods.push(['Snap shot', -5]);
    }
    if (opts.reaction === 'spearwall') {
      chance += 15;
      mods.push(['Set spears', 15]);
    }

    chance = Math.max(5, Math.min(95, Math.round(chance)));

    // Damage: every surviving soldier lands one blow, each reduced by the
    // target's armour, and the squad's total is rolled once.
    const base = ranged ? a.shot!.damage : a.melee;
    let mult = ab?.damageMult ?? 1;
    if (opts.reaction === 'spearwall') mult *= 1.5;
    if (arc === 'rear') mult *= 1.25;
    // Flankers (wolf riders) tear into sides and backs.
    if (!ranged && arc !== 'front' && a.tags.includes('flanker')) mult *= 1.3;
    let flat = 0;
    const movedTiles = opts.movedTiles ?? a.movedTiles;
    const charging = !ranged && a.abilities.includes('charge') && movedTiles >= 2 && !opts.reaction;
    if (charging) flat += 3;
    // Frenzied soldiers put everything into every blow.
    if (!ranged && hasStatus(a, 'bloodlust')) flat += 3;
    const pierce = ab?.ignoreArmor ? 1 : ranged ? a.shot!.pierce : a.meleePierce;
    const armor = t.stats.armor * (1 - pierce);
    const strikers = Math.max(1, a.alive);
    const min = Math.max(1, Math.round(base[0] * mult + flat - armor)) * strikers;
    const max = Math.max(1, Math.round(base[1] * mult + flat - armor)) * strikers;
    let killing = 0;
    for (let d = min; d <= max; d++) if (d >= t.hp) killing++;
    const kill = (killing / (max - min + 1)) * (chance / 100);
    const avg = (min + max) / 2;
    const moraleHit =
      Math.round((avg / t.maxHp) * 28) +
      (arc === 'flank' ? 4 : arc === 'rear' ? 8 : 0) +
      (ab?.moraleDamage ?? 0) +
      (charging ? 8 : 0);
    const soldiers: [number, number] = [killsFrom(t, min), killsFrom(t, max)];

    return { chance, min, max, arc, mods, kill, moraleHit, legal, reason, soldiers, strikers };
  }

  /** Targets the unit could attack right now from `from` with the given ability. */
  targets(u: BattleUnit, from: Pt = u, ability?: string): BattleUnit[] {
    return this.enemiesOf(u)
      .concat(this.units.filter((x) => x.status === 'routing' && x.faction !== u.faction))
      .filter((t) => this.preview(u, t, { from, ability, movedTiles: u.movedTiles }).legal);
  }

  // ---------------------------------------------------------------- events

  private emit(e: BattleEvent) {
    this.events.push(e);
  }

  drain(): BattleEvent[] {
    const out = this.events;
    this.events = [];
    return out;
  }

  log(text: string, tone: 'good' | 'bad' | 'neutral' = 'neutral') {
    this.emit({ t: 'log', text, tone });
  }

  // ---------------------------------------------------------------- morale

  changeMorale(u: BattleUnit, delta: number, reason: string) {
    if (u.status !== 'active' || delta === 0) return;
    // A frenzied squad barely notices what would shake it.
    if (delta < 0 && hasStatus(u, 'bloodlust')) delta = Math.min(-1, Math.round(delta / 2));
    const before = this.moraleState(u);
    u.morale = Math.max(0, Math.min(u.maxMorale, Math.round(u.morale + delta)));
    this.emit({ t: 'morale', uid: u.uid, delta: Math.round(delta), value: u.morale, reason });
    const after = this.moraleState(u);
    if (after !== before) this.emit({ t: 'mstate', uid: u.uid, from: before, to: after });
    if (u.morale <= 0) this.rout(u);
  }

  private rout(u: BattleUnit) {
    if (u.status !== 'active') return;
    if (u.leader) {
      u.morale = 1;
      return;
    }
    u.status = 'routing';
    u.stance = undefined;
    this.emit({ t: 'rout', uid: u.uid });
    this.log(`${squadName(u)} ${u.leader ? 'breaks' : 'break'} and ${u.leader ? 'flees' : 'flee'}!`, u.faction === 'player' ? 'bad' : 'good');
    for (const a of this.active(u.faction)) {
      if (dist(a, u) <= 4) this.changeMorale(a, -6, 'Ally fled');
    }
    for (const e of this.active(u.faction === 'player' ? 'enemy' : 'player')) {
      if (dist(e, u) <= 5) this.changeMorale(e, 3, 'Enemy fled');
    }
  }

  // ---------------------------------------------------------------- damage

  private fall(u: BattleUnit, killer?: BattleUnit) {
    let dead = true;
    if (u.faction === 'player') {
      const p = FALL_SURVIVAL_BASE + 0.05 * (u.level - 1) + this.setup.survivalBonus;
      dead = !this.rng.chance(p);
    }
    u.status = dead ? 'dead' : 'downed';
    u.stance = undefined;
    u.hp = 0;
    u.alive = 0;
    u.statuses = [];
    this.emit({ t: 'down', uid: u.uid, dead });
    const name = squadName(u);
    this.log(
      u.leader
        ? `${name} is slain.`
        : dead
          ? `${name} are wiped out to the last.`
          : `${name} are cut down; the wounded sergeant is dragged clear.`,
      u.faction === 'player' ? 'bad' : 'good',
    );
    if (killer) {
      killer.kills++;
      if (killer.faction === 'player') killer.xp += UNIT_TYPES[u.typeId]?.value ?? 4;
      this.changeMorale(killer, 8, 'Felled a foe');
    }
    if (u.tags.includes('herald') && this.horn === 'waiting') this.silenceHorn();
    if (u.tags.includes('warchief') && u.faction === 'enemy') {
      this.hordeBreaks(u);
      return;
    }
    if (u.leader) {
      for (const a of this.active(u.faction)) this.changeMorale(a, -35, 'Leader fell');
    } else {
      for (const a of this.active(u.faction)) {
        const d = dist(a, u);
        if (d <= 1.01) this.changeMorale(a, -16, 'Comrade fell beside them');
        else if (d <= 4) this.changeMorale(a, -10, 'Comrade fell');
      }
    }
    for (const e of this.active(u.faction === 'player' ? 'enemy' : 'player')) {
      if (e !== killer && dist(e, u) <= 4) this.changeMorale(e, 4, 'Enemy fell');
    }
  }

  private resolveAttack(a: BattleUnit, t: BattleUnit, opts: AttackOpts): boolean {
    const ab = opts.ability ? ABILITIES[opts.ability] : undefined;
    const pv = this.preview(a, t, opts);
    const ranged = ab ? !!ab.ranged : !opts.forceMelee && this.wouldShoot(a, t, opts.from ?? a);
    if (ranged && a.ammo > 0) a.ammo = Math.max(0, a.ammo - (ab?.ammoCost ?? 1));
    // One roll for the whole squad, however many soldiers swing or loose.
    const hit = this.rng.next() * 100 < pv.chance;
    let damage = 0;
    if (hit) damage = Math.min(t.hp, this.rng.int(pv.min, pv.max));
    const aliveBefore = t.alive;
    if (hit) {
      this.hitsTaken[t.uid] = (this.hitsTaken[t.uid] ?? 0) + 1;
      damageSquad(t, damage);
      a.damageDealt += damage;
    }
    const lost = aliveBefore - t.alive;
    this.emit({
      t: 'attack',
      uid: a.uid,
      target: t.uid,
      ranged,
      ability: opts.ability,
      hit,
      damage,
      chance: pv.chance,
      arc: pv.arc,
      reaction: opts.reaction,
      targetHp: t.hp,
      strikers: pv.strikers,
      aliveBefore,
      aliveAfter: t.alive,
    });
    const how = opts.reaction === 'spearwall' ? ' (spearwall)' : opts.reaction === 'overwatch' ? ' (overwatch)' : opts.reaction === 'zoc' ? ' (free attack)' : opts.reaction === 'firstStrike' ? ' (first strike)' : '';
    const side = pv.arc === 'front' ? '' : pv.arc === 'flank' ? ' in the flank' : ' from behind';
    const fallen = lost > 0 && t.alive > 0 ? ` ${lost === 1 ? 'One' : lost} ${memberNoun(t.typeId, lost)} ${lost === 1 ? 'falls' : 'fall'}.` : '';
    this.log(
      hit
        ? `${squadName(a)} hit ${squadName(t)}${side} for ${damage}${how}.${fallen}`
        : `${squadName(a)} miss ${squadName(t)}${how} (${pv.chance}%).`,
      a.faction === 'player' ? (hit ? 'good' : 'neutral') : hit ? 'bad' : 'neutral',
    );
    if (!hit) return false;
    // A ballista bolt carries on through into the next foe behind.
    const through = ranged && !opts.reaction && a.tags.includes('impale') ? this.impaleTarget(a, t) : undefined;
    if (t.hp <= 0) {
      if (t.status === 'routing') {
        // Cut down while fleeing.
        t.status = 'active';
      }
      this.fall(t, a);
      if (through) this.impale(a, t, through, damage, pv.strikers);
      return true;
    }
    if (t.status === 'active') {
      const charging = !ranged && a.abilities.includes('charge') && (opts.movedTiles ?? a.movedTiles) >= 2 && !opts.reaction;
      // Watching comrades fall shakes a squad more than the wounds alone.
      const loss =
        Math.round((damage / t.maxHp) * 28) +
        (pv.arc === 'flank' ? 4 : pv.arc === 'rear' ? 8 : 0) +
        (ab?.moraleDamage ?? 0) +
        (charging ? 8 : 0) +
        Math.round((lost * 6) / t.size);
      const reason =
        pv.arc === 'rear'
          ? 'Struck from behind'
          : pv.arc === 'flank'
            ? 'Flanked'
            : lost > 0
              ? lost === 1 ? 'Lost a soldier' : `Lost ${lost} soldiers`
              : 'Wounded';
      this.changeMorale(t, -loss, reason);
    }
    if (ab?.push && t.status !== 'dead' && t.status !== 'downed') this.push(a, t);
    // Brutes smash a squad out of the line and shoulder into the gap.
    else if (!ranged && !opts.reaction && a.tags.includes('smash') && t.status === 'active') this.push(a, t, true);
    if (through) this.impale(a, t, through, damage, pv.strikers);
    return true;
  }

  /**
   * The next foe behind `t` on the line of a ballista's shot, within two tiles.
   * A wall stops the bolt, and so does one of the company's own squads.
   */
  impaleTarget(a: BattleUnit, t: Pt): BattleUnit | undefined {
    const dx = t.x - a.x;
    const dy = t.y - a.y;
    const len = Math.hypot(dx, dy) || 1;
    let last = { x: t.x, y: t.y };
    for (let k = 1; k <= 2; k++) {
      const p = { x: Math.round(t.x + (dx / len) * k), y: Math.round(t.y + (dy / len) * k) };
      if (p.x === last.x && p.y === last.y) continue;
      last = p;
      const tile = tileAt(this.map, p.x, p.y);
      if (!tile || (tile.prop && PROPS[tile.prop].los === 2)) return undefined;
      const u = unitAt(this.units, p.x, p.y);
      if (u) return u.faction !== a.faction ? u : undefined;
    }
    return undefined;
  }

  /** The bolt goes on through `via` into `t` at half force (no new roll: it is the same bolt). */
  private impale(a: BattleUnit, via: BattleUnit, t: BattleUnit, damage: number, strikers: number) {
    if (t.status !== 'active' && t.status !== 'routing') return;
    const dmg = Math.min(t.hp, Math.max(1, Math.round(damage * 0.5)));
    const aliveBefore = t.alive;
    this.hitsTaken[t.uid] = (this.hitsTaken[t.uid] ?? 0) + 1;
    damageSquad(t, dmg);
    a.damageDealt += dmg;
    const lost = aliveBefore - t.alive;
    this.emit({
      t: 'attack',
      uid: a.uid,
      target: t.uid,
      ranged: true,
      ability: 'impale',
      hit: true,
      damage: dmg,
      chance: 100,
      arc: this.arcOf(t, a),
      targetHp: t.hp,
      strikers,
      aliveBefore,
      aliveAfter: t.alive,
      via: via.uid,
    });
    const fallen = lost > 0 && t.alive > 0 ? ` ${lost === 1 ? 'One' : lost} ${memberNoun(t.typeId, lost)} ${lost === 1 ? 'falls' : 'fall'}.` : '';
    this.log(`The bolt goes on through into ${squadName(t)} for ${dmg}.${fallen}`, a.faction === 'player' ? 'good' : 'bad');
    this.afterDamage(a, t, dmg, lost, 4, 'Impaled');
  }

  /**
   * What follows damage outside a plain attack (spells, a bolt carrying on,
   * bleeding): the squad falls, or its morale takes the wound and the losses.
   * Friendly fire earns nobody a kill.
   */
  private afterDamage(by: BattleUnit | undefined, t: BattleUnit, damage: number, lost: number, extra: number, reason: string) {
    if (t.hp <= 0) {
      if (t.status === 'routing') t.status = 'active';
      this.fall(t, by && by.faction !== t.faction && by.status === 'active' ? by : undefined);
      return;
    }
    if (t.status !== 'active') return;
    const loss = Math.round((damage / t.maxHp) * 28) + extra + Math.round((lost * 6) / t.size);
    this.changeMorale(t, -loss, lost > 0 ? (lost === 1 ? 'Lost a soldier' : `Lost ${lost} soldiers`) : reason);
  }

  private push(a: BattleUnit, t: BattleUnit, follow = false) {
    const dx = Math.sign(t.x - a.x);
    const dy = Math.sign(t.y - a.y);
    const to = { x: t.x + dx, y: t.y + dy };
    const from = { x: t.x, y: t.y };
    const ok =
      tilePassable(this.map, to.x, to.y) &&
      !unitAt(this.units, to.x, to.y) &&
      this.tile(to).h <= this.tile(from).h + 0 &&
      this.tile(from).h - this.tile(to).h <= 2;
    if (ok) {
      t.x = to.x;
      t.y = to.y;
      this.emit({ t: 'push', uid: t.uid, from, to, blocked: false, hp: t.hp, alive: t.alive });
      if (follow && a.status === 'active' && Math.abs(this.tile(from).h - this.tile(a).h) <= 1) {
        const at = { x: a.x, y: a.y };
        a.x = from.x;
        a.y = from.y;
        a.facing = dirTo(at, from);
        this.emit({ t: 'move', uid: a.uid, path: [at, { ...from }] });
        this.log(`${squadName(a)} smash ${squadName(t)} back and force their way into the gap!`, a.faction === 'player' ? 'good' : 'bad');
      }
    } else {
      // Every soldier in the squad is slammed into the obstacle.
      const slam = Math.min(t.hp, 3 * t.alive);
      damageSquad(t, slam);
      a.damageDealt += slam;
      this.emit({ t: 'push', uid: t.uid, from, to: from, blocked: true, hp: t.hp, alive: t.alive });
      this.log(`${squadName(t)} ${t.leader ? 'is' : 'are'} slammed against the obstacle.`);
      if (t.hp <= 0) this.fall(t, a);
    }
  }

  // ---------------------------------------------------------------- actions

  deploySwap(uid: string, x: number, y: number): boolean {
    if (this.phase !== 'deploy') return false;
    const u = this.unit(uid);
    if (!this.map.playerDeploy.some((p) => p.x === x && p.y === y)) return false;
    const other = unitAt(this.units, x, y);
    if (other && other.faction !== 'player') return false;
    if (other) {
      other.x = u.x;
      other.y = u.y;
      other.facing = this.facingTowardFoes(other);
    }
    u.x = x;
    u.y = y;
    // Squads take the field facing the enemy; after that only marching turns them.
    u.facing = this.facingTowardFoes(u);
    return true;
  }

  /** Remaining fighting strength of a faction relative to the start (by HP). */
  strength(faction: Faction): number {
    const all = this.units.filter((u) => u.faction === faction && u.status !== 'reserve');
    const total = all.reduce((sum, u) => sum + u.maxHp, 0);
    const left = this.active(faction).reduce((sum, u) => sum + u.hp, 0);
    return total ? left / total : 0;
  }

  isOver(): boolean {
    return this.phase === 'over';
  }

  begin(runAi: (b: Battle) => void) {
    if (this.phase !== 'deploy') return;
    if (this.setup.enemyFirst) {
      this.phase = 'enemy';
      this.startTurn('enemy');
      if (this.isOver()) return;
      runAi(this);
      if (this.isOver()) return;
      this.endOfTurn('enemy');
    }
    this.phase = 'player';
    this.startTurn('player');
  }

  canAct(u: BattleUnit): boolean {
    return (
      u.status === 'active' &&
      this.phase === (u.faction === 'player' ? 'player' : 'enemy') &&
      !u.done
    );
  }

  /**
   * Walk to (x, y). The squad ends facing the way its last step went; pass
   * `facing` to take the path that arrives that way (ending on the start tile
   * turns the squad by stepping out and back).
   */
  move(uid: string, x: number, y: number, facing?: Dir): boolean {
    const u = this.unit(uid);
    if (!this.canAct(u) || u.hasMoved) return false;
    if (u.x === x && u.y === y && (facing === undefined || facing === u.facing)) return false;
    const opt = this.moveOption(u, x, y, facing);
    if (!opt || (facing !== undefined && opt.facing !== facing)) return false;
    const path = opt.path;
    if (path.length < 2) return false;
    const before = { x: u.x, y: u.y, facing: u.facing, movedTiles: u.movedTiles };
    const mark = this.events.length;
    const rngBefore = this.rng.state;
    this.walk(u, path);
    u.hasMoved = true;
    // A move can be redone only if nothing reacted to it: no free attack,
    // spearwall or overwatch shot, and no dice rolled along the way.
    const clean = this.rng.state === rngBefore && this.events.slice(mark).every((e) => e.t === 'move');
    if (u.faction === 'player') this.moveRecords.set(u.uid, { ...before, path, clean: clean && u.status === 'active' });
    this.afterAction(u);
    return true;
  }

  /** Whether a soldier's move this turn can be taken back. Only before the soldier attacks or acts. */
  canRedo(uid: string): { ok: boolean; reason?: string } {
    const u = this.unit(uid);
    const r = this.moveRecords.get(uid);
    if (this.phase !== 'player' || u.status !== 'active') return { ok: false, reason: 'Only during your turn.' };
    if (!u.hasMoved || !r) return { ok: false, reason: 'This soldier has not moved yet.' };
    if (u.hasActed) return { ok: false, reason: 'This soldier has already attacked or acted.' };
    if (!r.clean) return { ok: false, reason: 'The enemy reacted to this move, so it cannot be taken back.' };
    const blocker = unitAt(this.units, r.x, r.y);
    if (blocker && blocker !== u) return { ok: false, reason: `${squadName(blocker)} now stand on the starting tile.` };
    return { ok: true };
  }

  /** Walk the soldier back to where the turn's move started, ready to move again. */
  redoMove(uid: string): boolean {
    if (!this.canRedo(uid).ok) return false;
    const u = this.unit(uid);
    const r = this.moveRecords.get(uid)!;
    u.x = r.x;
    u.y = r.y;
    u.facing = r.facing;
    u.movedTiles = r.movedTiles;
    u.hasMoved = false;
    u.done = false;
    this.moveRecords.delete(uid);
    this.emit({ t: 'move', uid, path: r.path.slice().reverse() });
    this.emit({ t: 'face', uid, facing: r.facing });
    return true;
  }

  /** Walk a path step by step, resolving reactions. Returns tiles moved. */
  walk(u: BattleUnit, path: Pt[]): number {
    let segment: Pt[] = [{ x: u.x, y: u.y }];
    const flush = () => {
      if (segment.length > 1) this.emit({ t: 'move', uid: u.uid, path: segment });
      segment = [{ x: u.x, y: u.y }];
    };
    let moved = 0;
    const fleeing = u.status === 'routing';
    const stopped = () =>
      u.status === 'dead' || u.status === 'downed' || u.status === 'fled' || (!fleeing && u.status !== 'active');
    for (let i = 1; i < path.length; i++) {
      const a = path[i - 1];
      const b = path[i];
      // Leaving a zone of control provokes free attacks.
      // Leaving a foe's front or flank provokes a free attack; its rear is blind.
      // Skirmishers slip away untouched.
      const zoc = u.tags.includes('skirmish')
        ? []
        : this.enemiesOf(u).filter(
            (e) => manhattan(e, a) === 1 && this.canMelee(e, u, e) && e.status === 'active' && this.arcOf(e, a) !== 'rear',
          );
      if (zoc.length) {
        flush();
        for (const e of zoc) {
          if (u.status !== 'active' && u.status !== 'routing') break;
          this.resolveAttack(e, u, { reaction: 'zoc', forceMelee: true });
        }
        if (stopped()) break;
      }
      const blocker = unitAt(this.units, b.x, b.y);
      if (blocker && blocker !== u && blocker.faction !== u.faction) break;
      u.x = b.x;
      u.y = b.y;
      u.facing = dirTo(a, b);
      segment.push({ x: b.x, y: b.y });
      moved++;
      // Spearwall: entering a guarded tile.
      if (u.status === 'active') {
        let halted = false;
        for (const s of this.enemiesOf(u)) {
          if (s.stance !== 'spearwall' || manhattan(s, b) !== 1) continue;
          if (this.arcOf(s, b) === 'rear' || s.struck.includes(u.uid)) continue;
          if (!this.canMelee(s, u, s)) continue;
          flush();
          s.struck.push(u.uid);
          const hit = this.resolveAttack(s, u, { reaction: 'spearwall', forceMelee: true });
          if (hit && (u.status === 'active' || u.status === 'routing')) {
            halted = true;
            this.emit({ t: 'halt', uid: u.uid, by: s.uid });
          } else if (!hit) {
            s.stance = undefined;
            this.emit({ t: 'stance', uid: s.uid, stance: null });
            this.log(`${squadName(u)} slip past the spears of ${squadName(s)}.`);
          }
          if (u.status !== 'active') break;
        }
        if (halted || u.status !== 'active') break;
      }
      // Overwatch: moving into a covered tile.
      if (u.status === 'active') {
        for (const o of this.enemiesOf(u)) {
          if (o.stance !== 'overwatch') continue;
          // Crossbowmen watch their front and flanks, not the ground behind them.
          if (this.arcOf(o, u) === 'rear') continue;
          if (!this.canShoot(o, u, o).ok) continue;
          flush();
          o.stance = undefined;
          this.emit({ t: 'stance', uid: o.uid, stance: null });
          this.resolveAttack(o, u, { reaction: 'overwatch' });
          if (u.status !== 'active') break;
        }
        if (stopped()) break;
      }
    }
    flush();
    u.movedTiles += moved;
    return moved;
  }

  attack(uid: string, targetUid: string, ability?: string): boolean {
    const a = this.unit(uid);
    const t = this.unit(targetUid);
    if (!this.canAct(a) || a.hasActed) return false;
    const ab = ability ? ABILITIES[ability] : undefined;
    if (ab && (a.cooldowns[ab.id] ?? 0) > 0) return false;
    if (ab && this.moraleState(a) === 'wavering') return false;
    if (ab?.ammoCost && a.ammo >= 0 && a.ammo < ab.ammoCost) return false;
    const pv = this.preview(a, t, { ability });
    if (!pv.legal) return false;
    // Attacking commits the soldier's move. It does not turn the squad: a
    // squad faces only the way it last stepped.
    this.moveRecords.delete(uid);
    const ranged = ab ? !!ab.ranged : this.wouldShoot(a, t);
    // Spearmen strike first at anyone who closes in and attacks from the front.
    if (
      !ranged &&
      t.status === 'active' &&
      t.tags.includes('firstStrike') &&
      a.movedTiles > 0 &&
      this.arcOf(t, a) === 'front' &&
      !t.struck.includes(a.uid) &&
      this.canMelee(t, a, t)
    ) {
      t.struck.push(a.uid);
      this.resolveAttack(t, a, { reaction: 'firstStrike', forceMelee: true });
      if (a.status !== 'active') {
        a.hasActed = true;
        this.afterAction(a);
        return true;
      }
    }
    this.resolveAttack(a, t, { ability, forceMelee: !ranged });
    if (ab?.cooldown) a.cooldowns[ab.id] = ab.cooldown;
    a.hasActed = true;
    this.afterAction(a);
    return true;
  }

  useStance(uid: string, ability: string): boolean {
    const u = this.unit(uid);
    const ab = ABILITIES[ability];
    if (!ab?.stance || !u.abilities.includes(ability)) return false;
    if (!this.canAct(u) || u.hasActed) return false;
    if (this.moraleState(u) === 'wavering') return false;
    if (ab.stance === 'overwatch' && (u.ammo === 0 || !u.shot)) return false;
    u.stance = ab.stance;
    u.hasActed = true;
    this.moveRecords.delete(uid);
    this.emit({ t: 'stance', uid, stance: ab.stance });
    this.afterAction(u);
    return true;
  }

  shout(uid: string, ability: string): boolean {
    const u = this.unit(uid);
    const ab = ABILITIES[ability];
    if (ab?.kind !== 'shout' || !u.abilities.includes(ability)) return false;
    if (!this.canAct(u) || u.hasActed || (u.cooldowns[ability] ?? 0) > 0) return false;
    this.moveRecords.delete(uid);
    this.emit({ t: 'shout', uid, ability });
    this.log(`${squadName(u)}: ${ab.name}!`, u.faction === 'player' ? 'good' : 'bad');
    const r = ab.radius ?? 4;
    for (const a of this.alliesOf(u)) if (dist(a, u) <= r) this.changeMorale(a, ab.moraleGain ?? 0, ab.name);
    for (const e of this.enemiesOf(u)) if (dist(e, u) <= r) this.changeMorale(e, -(ab.moraleDamage ?? 0), ab.name);
    u.cooldowns[ability] = ab.cooldown ?? 0;
    u.hasActed = true;
    this.afterAction(u);
    return true;
  }

  // ---------------------------------------------------------------- spells and war machines

  /**
   * The squads a spell aimed at `at` would touch, in the order it reaches
   * them, with the share of its force each takes. Lightning arcs from the
   * squad struck to the nearest other foes; blasts and stones catch every
   * squad on the tiles beside the one struck.
   */
  spellReach(a: BattleUnit, ab: AbilityDef, at: Pt, from: Pt = a): { u: BattleUnit; role: SpellHit['role']; factor: number }[] {
    const out: { u: BattleUnit; role: SpellHit['role']; factor: number }[] = [];
    if (ab.aura !== undefined) {
      for (const u of this.active(a.faction)) if (manhattan(u, from) <= ab.aura) out.push({ u, role: 'aura', factor: 1 });
      return out;
    }
    const main = unitAt(this.units, at.x, at.y);
    if (main && (ab.target === 'tile' || (ab.target === 'enemy' ? main.faction !== a.faction : main.faction === a.faction))) {
      out.push({ u: main, role: 'main', factor: 1 });
    }
    if (ab.splash) {
      for (const n of neighbors(this.map, at)) {
        const u = unitAt(this.units, n.x, n.y);
        if (!u || (!ab.friendly && u.faction === a.faction)) continue;
        out.push({ u, role: 'splash', factor: ab.splash });
      }
    }
    if (ab.chain && out[0]?.role === 'main') {
      let last = out[0].u;
      let factor = 1;
      const struck = new Set([last.uid]);
      for (let j = 0; j < ab.chain.jumps; j++) {
        const next = this.units
          .filter((u) => (u.status === 'active' || u.status === 'routing') && u.faction !== a.faction && !struck.has(u.uid) && manhattan(u, last) <= ab.chain!.reach)
          .sort((p, q) => manhattan(p, last) - manhattan(q, last) || p.hp - q.hp || (p.uid < q.uid ? -1 : 1))[0];
        if (!next) break;
        factor *= ab.chain.falloff;
        struck.add(next.uid);
        out.push({ u: next, role: 'chain', factor });
        last = next;
      }
    }
    return out;
  }

  /** Damage range a spell's share `factor` does to `t`: each caster's blow less armour, times the casters standing. */
  private spellDamage(a: BattleUnit, ab: AbilityDef, t: BattleUnit, factor: number): [number, number] {
    const casters = Math.max(1, a.alive);
    const pierce = ab.ignoreArmor ? 1 : (ab.pierce ?? 0);
    const armor = t.stats.armor * (1 - pierce);
    const blow = (n: number) => Math.max(1, Math.round(n * factor - armor));
    return [blow(ab.power![0]) * casters, blow(ab.power![1]) * casters];
  }

  /** What casting `abilityId` at the tile `at` would do now (from `from`, after moving `movedTiles`). */
  spellPreview(a: BattleUnit, abilityId: string, at: Pt, opts: { from?: Pt; movedTiles?: number } = {}): SpellPreview {
    const ab = ABILITIES[abilityId];
    const from = opts.from ?? { x: a.x, y: a.y };
    const casters = Math.max(1, a.alive);
    const mods: [string, number][] = [];
    const base: SpellPreview = { legal: true, ability: abilityId, at: { x: at.x, y: at.y }, chance: 100, mods, casters, hits: [], scatter: !!ab?.scatter, moraleHit: 0 };
    const fail = (reason: string): SpellPreview => ({ ...base, legal: false, reason });
    if (!ab || ab.kind !== 'spell') return fail('Not a spell');
    if (!a.abilities.includes(abilityId)) return fail('Not known to this squad');
    if (!tileAt(this.map, at.x, at.y)) return fail('Off the field');
    const target = unitAt(this.units, at.x, at.y);
    const moved = (opts.movedTiles ?? a.movedTiles) > 0;
    if (ab.engine && moved) return fail('Cannot loose in a turn it has moved');
    const hostile = !!ab.power;
    if (ab.target === 'self') {
      if (at.x !== from.x || at.y !== from.y) return fail('Cast where the casters stand');
    } else {
      if (ab.target === 'enemy' && (!target || target.faction === a.faction)) return fail('Choose an enemy squad');
      if (ab.target === 'ally' && (!target || target.faction !== a.faction || target.status !== 'active')) return fail('Choose a friendly squad');
      const d = dist(from, at);
      if (hostile && d < Math.max(1, ab.minRange ?? 1)) return fail('Too close');
      if (d > (ab.range ?? 1) + 0.01) return fail('Out of range');
      if (ab.sight && d > 0 && lineOfSight(this.map, from, at).blocked) return fail('No line of sight');
      if (hostile && this.setup.darkness && d > (ab.range ?? 1) - 2) return fail('Too dark to see');
    }
    let chance = 100;
    if (hostile) {
      chance = a.stats.ranged;
      mods.push([ab.engine ? 'Crew skill' : 'Spell skill', chance]);
      if (target && target.faction !== a.faction) {
        // Squads dodge a spell; nobody dodges a falling stone, only its aim.
        const def = Math.round(target.stats.rangedDefense / (ab.engine ? 2 : 1));
        chance -= def;
        mods.push(['Target defense', -def]);
        if (target.status === 'routing') {
          chance += 15;
          mods.push(['Fleeing target', 15]);
        }
      }
      if (ab.hitBonus) {
        chance += ab.hitBonus;
        mods.push([ab.engine ? 'Crude engine' : 'The spell seeks its mark', ab.hitBonus]);
      }
      const d = dist(from, at);
      if (ab.engine && d > 5) {
        const m = -Math.round((d - 5) * 3);
        chance += m;
        mods.push(['Long range', m]);
      }
      const ams = this.moraleState(a);
      const am = ams === 'confident' ? 5 : ams === 'shaken' ? -8 : ams === 'wavering' ? -15 : 0;
      if (am) {
        chance += am;
        mods.push([ams === 'confident' ? 'Confident' : ams === 'shaken' ? 'Shaken' : 'Wavering', am]);
      }
      if (this.isAdjacentEnemy(a, from)) {
        chance -= 15;
        mods.push(['Engaged in melee', -15]);
      }
      if (hasStatus(a, 'chilled')) {
        chance -= 10;
        mods.push(['Chilled', -10]);
      }
      if (this.setup.darkness) {
        chance -= 10;
        mods.push(['Darkness', -10]);
      }
      chance = Math.max(5, Math.min(95, Math.round(chance)));
    }
    const p = chance / 100;
    const hits = this.spellReach(a, ab, at, from).map(({ u, role, factor }) => {
      const ally = u.faction === a.faction;
      if (ab.heal) {
        const missing = u.alive * u.hpPer - u.hp;
        const lo = Math.min(missing, ab.heal[0] * casters);
        const hi = Math.min(missing, ab.heal[1] * casters);
        return { uid: u.uid, role, min: lo, max: hi, heal: true, ally, soldiers: [0, 0] as [number, number], kill: 0 };
      }
      if (!ab.power) return { uid: u.uid, role, min: 0, max: 0, heal: false, ally, soldiers: [0, 0] as [number, number], kill: 0 };
      const [min, max] = this.spellDamage(a, ab, u, factor);
      let killing = 0;
      for (let dmg = min; dmg <= max; dmg++) if (dmg >= u.hp) killing++;
      // Splash from a stone that strays still lands somewhere near; the rest needs the spell to strike home.
      const reach = role === 'splash' && ab.scatter ? 0.5 + p * 0.5 : p;
      return { uid: u.uid, role, min, max, heal: false, ally, soldiers: [killsFrom(u, min), killsFrom(u, max)] as [number, number], kill: (killing / (max - min + 1)) * reach };
    });
    const main = hits.find((h) => h.role === 'main' && !h.heal);
    const moraleHit = main && target ? Math.round(((main.min + main.max) / 2 / target.maxHp) * 28) + (ab.moraleDamage ?? 0) : 0;
    return { ...base, chance, hits, moraleHit };
  }

  /** Squads (or the caster's own tile) a spell could be cast at right now. */
  spellTargets(u: BattleUnit, abilityId: string, from: Pt = u): BattleUnit[] {
    const ab = ABILITIES[abilityId];
    if (!ab || ab.kind !== 'spell') return [];
    if (ab.target === 'self') return [u];
    const pool = ab.target === 'ally' ? this.active(u.faction) : this.living().filter((x) => x.faction !== u.faction);
    return pool.filter((t) => this.spellPreview(u, abilityId, t, { from }).legal);
  }

  /** Whether the squad may use this spell at all now (cooldown, nerve, having acted). */
  canCast(u: BattleUnit, abilityId: string): { ok: boolean; reason?: string } {
    const ab = ABILITIES[abilityId];
    if (!ab || ab.kind !== 'spell' || !u.abilities.includes(abilityId)) return { ok: false, reason: 'Not known to this squad' };
    if (!this.canAct(u) || u.hasActed) return { ok: false, reason: 'Has already acted' };
    if ((u.cooldowns[abilityId] ?? 0) > 0) return { ok: false, reason: `Ready in ${u.cooldowns[abilityId]} turns` };
    // A war machine's shot is its plain attack; spells need a steady nerve.
    if (this.moraleState(u) === 'wavering' && UNIT_TYPES[u.typeId]?.primary !== abilityId) return { ok: false, reason: 'Too shaken' };
    if (ab.engine && u.movedTiles > 0) return { ok: false, reason: 'Cannot loose in a turn it has moved' };
    return { ok: true };
  }

  /** Cast a spell (or loose a war machine's stone) at the tile `at`. */
  cast(uid: string, abilityId: string, at: Pt): boolean {
    const a = this.unit(uid);
    if (!this.canCast(a, abilityId).ok) return false;
    const pv = this.spellPreview(a, abilityId, at);
    if (!pv.legal) return false;
    this.moveRecords.delete(uid);
    this.resolveSpell(a, ABILITIES[abilityId], at, pv);
    const ab = ABILITIES[abilityId];
    if (ab.cooldown) a.cooldowns[abilityId] = ab.cooldown;
    a.hasActed = true;
    this.afterAction(a);
    return true;
  }

  /**
   * The spell takes effect. One roll decides whether it strikes home; a stone
   * or fireball that misses lands a tile astray. Each squad touched then takes
   * one damage roll (or one healing roll): the casters' power is rolled once
   * per squad, never per caster.
   */
  private resolveSpell(a: BattleUnit, ab: AbilityDef, at: Pt, pv: SpellPreview) {
    const hostile = !!ab.power;
    const hit = !hostile || this.rng.next() * 100 < pv.chance;
    let impact = { x: at.x, y: at.y };
    if (!hit && ab.scatter) {
      const astray = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]
        .map(([dx, dy]) => ({ x: at.x + dx, y: at.y + dy }))
        .filter((q) => tileAt(this.map, q.x, q.y) && !(q.x === a.x && q.y === a.y));
      if (astray.length) impact = astray[this.rng.int(0, astray.length - 1)];
    }
    // A stray stone or fireball strikes whoever stands where it lands, in full.
    const reach = hit || ab.scatter ? this.spellReach(a, ab, impact) : [];
    const casters = Math.max(1, a.alive);
    const hits: SpellHit[] = [];
    const after: (() => void)[] = [];
    for (const { u: t, role, factor } of reach) {
      if (t.status !== 'active' && t.status !== 'routing') continue;
      const aliveBefore = t.alive;
      let damage = 0;
      let heal = 0;
      if (ab.power) {
        const [min, max] = this.spellDamage(a, ab, t, factor);
        damage = Math.min(t.hp, this.rng.int(min, max));
        this.hitsTaken[t.uid] = (this.hitsTaken[t.uid] ?? 0) + 1;
        damageSquad(t, damage);
        if (t.faction !== a.faction) a.damageDealt += damage;
      }
      if (ab.heal) {
        heal = healSquad(t, this.rng.int(ab.heal[0] * casters, ab.heal[1] * casters));
        // Healers learn from the wounds they close.
        if (a.faction === 'player') a.damageDealt += Math.round(heal * 0.5);
      }
      const status = ab.status && t.hp > 0 ? ab.status.id : ab.bleed && damage > 0 && t.hp > 0 ? 'bleeding' : undefined;
      hits.push({ uid: t.uid, role, damage, heal, hp: t.hp, aliveBefore, aliveAfter: t.alive, status });
      const lost = aliveBefore - t.alive;
      after.push(() => {
        if (ab.power) {
          const fallen = lost > 0 && t.alive > 0 ? ` ${lost === 1 ? 'One' : lost} ${memberNoun(t.typeId, lost)} ${lost === 1 ? 'falls' : 'fall'}.` : '';
          const friendly = t.faction === a.faction ? ' (their own side!)' : '';
          this.log(`${role === 'chain' ? 'The lightning arcs to' : role === 'splash' ? 'The blast catches' : `${ab.name} strikes`} ${squadName(t)}${friendly} for ${damage}.${fallen}`, t.faction === 'player' ? 'bad' : 'good');
          this.afterDamage(a, t, damage, lost, role === 'main' ? (ab.moraleDamage ?? 0) : Math.round((ab.moraleDamage ?? 0) / 2), ab.name);
        }
        if (ab.heal) {
          if (heal > 0) this.log(`${ab.name}: the wounds of ${squadName(t)} close (+${heal}).`, t.faction === 'player' ? 'good' : 'bad');
          if (ab.moraleGain) this.changeMorale(t, ab.moraleGain, ab.name);
        }
        if (t.status !== 'active' && t.status !== 'routing') return;
        if (ab.status) {
          this.addStatus(t, ab.status.id, ab.status.turns, a.uid);
          if (ab.status.id === 'bloodlust') this.log(`${squadName(t)} ${t.leader ? 'is' : 'are'} seized by bloodlust!`, t.faction === 'player' ? 'good' : 'bad');
          if (!ab.heal && ab.moraleGain) this.changeMorale(t, ab.moraleGain, ab.name);
        }
        if (ab.bleed && damage > 0) this.addStatus(t, 'bleeding', 2, a.uid, Math.max(1, Math.round(damage * ab.bleed)));
      });
    }
    this.emit({ t: 'spell', uid: a.uid, ability: ab.id, at: { x: at.x, y: at.y }, impact, hit, chance: pv.chance, casters, hits });
    if (hostile && !hit) {
      this.log(
        ab.scatter
          ? `${squadName(a)}: ${ab.name} goes astray${hits.length ? '' : ' and lands on empty ground'} (${pv.chance}%).`
          : `${squadName(a)}: ${ab.name} misses ${squadName(unitAt(this.units, at.x, at.y) ?? a)} (${pv.chance}%).`,
        'neutral',
      );
    } else if (!hostile && !ab.heal) this.log(`${squadName(a)}: ${ab.name}!`, a.faction === 'player' ? 'good' : 'bad');
    for (const f of after) f();
  }

  /** Lay a condition on a squad (renewing it if it is already there). */
  private addStatus(t: BattleUnit, id: StatusId, turns: number, by?: string, power?: number) {
    const cur = statusOf(t, id);
    if (cur) {
      cur.turns = Math.max(cur.turns, turns);
      if (power) cur.power = Math.max(cur.power ?? 0, power);
      cur.by = by ?? cur.by;
    } else t.statuses.push({ id, turns, by, power });
    this.emit({ t: 'status', uid: t.uid, status: id, on: true, turns });
  }

  /** Chill and frenzy wear off at the end of the squad's own turn once their time is up. */
  private endOfTurn(faction: Faction) {
    for (const u of this.units) {
      if (u.faction !== faction || !u.statuses.length) continue;
      for (const s of u.statuses.slice()) {
        if (s.id === 'bleeding') continue;
        s.turns--;
        if (s.turns > 0) continue;
        u.statuses.splice(u.statuses.indexOf(s), 1);
        if (u.status === 'active' || u.status === 'routing') this.emit({ t: 'status', uid: u.uid, status: s.id, on: false, turns: 0 });
      }
    }
  }

  /** Bleeding wounds open again at the start of the squad's turn. */
  private bleed(u: BattleUnit) {
    const s = statusOf(u, 'bleeding');
    if (!s || (u.status !== 'active' && u.status !== 'routing')) return;
    const aliveBefore = u.alive;
    const damage = Math.min(u.hp, s.power ?? 1);
    damageSquad(u, damage);
    this.emit({ t: 'dot', uid: u.uid, status: 'bleeding', damage, hp: u.hp, aliveBefore, aliveAfter: u.alive });
    const lost = aliveBefore - u.alive;
    const fallen = lost > 0 && u.alive > 0 ? ` ${lost === 1 ? 'One' : lost} ${memberNoun(u.typeId, lost)} ${lost === 1 ? 'dies' : 'die'}.` : '';
    this.log(`${squadName(u)} bleed from the gutripper hex (−${damage}).${fallen}`, u.faction === 'player' ? 'bad' : 'good');
    s.turns--;
    if (s.turns <= 0) {
      u.statuses.splice(u.statuses.indexOf(s), 1);
      if (u.hp > 0) this.emit({ t: 'status', uid: u.uid, status: 'bleeding', on: false, turns: 0 });
    }
    const by = s.by ? this.units.find((x) => x.uid === s.by) : undefined;
    this.afterDamage(by, u, damage, lost, 3, 'Bleeding');
  }

  endUnit(uid: string) {
    const u = this.unit(uid);
    u.done = true;
  }

  private afterAction(u: BattleUnit) {
    if (u.hasMoved && u.hasActed) u.done = true;
    this.checkEnd();
  }

  endTurn(runAi: (b: Battle) => void) {
    if (this.phase !== 'player') return;
    this.moveRecords.clear();
    this.endOfTurn('player');
    this.phase = 'enemy';
    this.startTurn('enemy');
    if (this.isOver()) return;
    runAi(this);
    if (this.isOver()) return;
    this.endOfTurn('enemy');
    this.afterEnemyTurn();
    if (this.isOver()) return;
    this.turn++;
    this.phase = 'player';
    this.startTurn('player');
  }

  // ---------------------------------------------------------------- the horde

  /** The horn-bearer sounds the war horn: the band he calls marches in next turn. */
  private soundHorn(h: BattleUnit) {
    this.horn = 'sounded';
    this.waves.forEach((w, i) => {
      if (w.horn && this.waveState[i] === 'pending') w.turn = Math.max(w.turn, this.turn + 1);
    });
    this.emit({ t: 'horn', uid: h.uid, sounded: true });
    this.log(`${squadName(h)} sound the war horn! More of them will come.`, 'bad');
    for (const e of this.active('enemy')) this.changeMorale(e, 6, 'The war horn');
    for (const p of this.active('player')) this.changeMorale(p, -4, 'The war horn');
  }

  /** The horn-bearer fell before he could call for help. */
  private silenceHorn() {
    if (this.horn !== 'waiting') return;
    const anyHerald = this.units.some((u) => u.faction === 'enemy' && u.tags.includes('herald') && (u.status === 'active' || u.status === 'routing'));
    if (anyHerald) return;
    this.horn = 'silent';
    const h = this.units.find((u) => u.tags.includes('herald'));
    this.waves.forEach((w, i) => {
      if (w.horn && this.waveState[i] === 'pending') this.waveState[i] = 'cancelled';
    });
    if (h) this.emit({ t: 'horn', uid: h.uid, sounded: false });
    this.log('The war horn falls silent. No help will come for them.', 'good');
    for (const p of this.active('player')) this.changeMorale(p, 4, 'The horn is silenced');
  }

  /** The warchief is slain: the horde loses heart, no more waves come and every foe runs. */
  private hordeBreaks(chief: BattleUnit) {
    this.emit({ t: 'broken', uid: chief.uid });
    this.log(`${squadName(chief)} is slain! The horde breaks and flees!`, 'good');
    this.waveState = this.waveState.map((s) => (s === 'pending' ? 'cancelled' : s));
    for (const e of this.active('enemy')) {
      e.status = 'routing';
      e.stance = undefined;
      this.emit({ t: 'rout', uid: e.uid });
    }
    for (const p of this.active('player')) this.changeMorale(p, 25, 'The warchief is slain');
  }

  /** Squads of due waves march in at their edge; those that find no room wait for the next turn. */
  private arriveWaves() {
    // With the field empty, the horde does not wait for its turn.
    const empty = this.active('enemy').length === 0;
    let hurried = false;
    this.waves.forEach((w, i) => {
      if (this.waveState[i] !== 'pending') return;
      if (w.horn && this.horn !== 'sounded') return;
      if (w.turn > this.turn && !(empty && !hurried && this.nextWave()?.index === i)) return;
      if (w.turn > this.turn) hurried = true;
      const entries = (this.map.entries?.[w.edge] ?? []).filter((p) => tilePassable(this.map, p.x, p.y) && !unitAt(this.units, p.x, p.y));
      const waiting = w.uids.map((id) => this.unit(id)).filter((u) => u.status === 'reserve');
      if (!this.waveSeen.has(i)) {
        this.waveSeen.add(i);
        this.emit({ t: 'wave', wave: i, edge: w.edge, label: w.label, count: w.uids.length, final: !!w.final });
        this.log(`${w.label}: ${w.uids.length} more squads march onto the field!`, 'bad');
        for (const p of this.active('player')) this.changeMorale(p, w.final ? -7 : -3, w.final ? 'The warchief\'s host' : 'Another wave');
      }
      for (const u of waiting) {
        const p = entries.shift();
        if (!p) break;
        const from = { x: u.x, y: u.y };
        u.x = p.x;
        u.y = p.y;
        u.status = 'active';
        u.facing = INWARD[w.edge];
        this.emit({ t: 'spawn', uid: u.uid, from, to: { x: p.x, y: p.y } });
      }
      if (w.uids.every((id) => this.unit(id).status !== 'reserve')) this.waveState[i] = 'arrived';
    });
  }

  /** Waves due on the coming enemy turn are sighted at the start of the player's turn. */
  private warnWaves() {
    this.waves.forEach((w, i) => {
      if (this.waveState[i] !== 'pending' || (w.horn && this.horn !== 'sounded')) return;
      if (w.turn !== this.turn) return;
      this.emit({ t: 'warn', wave: i, edge: w.edge, turn: w.turn, label: w.label, count: w.uids.length });
      this.log(`War horns beyond the ${EDGE_NAME[w.edge]} edge: ${w.label.toLowerCase()} will reach the field at the end of this turn.`, 'bad');
    });
  }

  /** After the enemy moves: is the held ground lost, and has the relief come? */
  private afterEnemyTurn() {
    const o = this.objective;
    const zone = this.map.zone;
    if (o.kind === 'hold' && zone?.length) {
      const inside = new Set(zone.map((p) => key(p.x, p.y)));
      const foes = this.active('enemy').filter((u) => inside.has(key(u.x, u.y))).length;
      const ours = this.active('player').filter((u) => inside.has(key(u.x, u.y))).length;
      if (foes >= 2 && foes >= ours + 2) {
        this.overrun++;
        if (this.overrun >= 2) {
          this.log(`${this.map.zoneName ?? 'The held ground'} is overrun. The line is broken.`, 'bad');
          this.finish('defeat');
          return;
        }
        this.emit({ t: 'overrun', turnsLeft: 1 });
        this.log(`The enemy is inside ${this.map.zoneName?.toLowerCase() ?? 'the line'}! Drive them out before their next turn ends.`, 'bad');
      } else this.overrun = 0;
    }
    // A band that cannot break the company in a long fight gives up and slinks off.
    if (o.kind === 'rout' && this.turn >= GIVE_UP_TURN && this.pendingWaves() === 0 && this.active('enemy').length) {
      this.log('The enemy has had enough. They slink back into the woods.', 'good');
      for (const e of this.active('enemy')) {
        e.status = 'routing';
        this.emit({ t: 'rout', uid: e.uid });
      }
      this.finish('victory');
      return;
    }
    if ((o.kind === 'survive' || o.kind === 'hold') && o.turns !== undefined && this.turn >= o.turns) {
      const text = o.relief ?? 'The relief column arrives';
      this.emit({ t: 'relief', text });
      this.log(`${text}! The horde falls back before them.`, 'good');
      this.waveState = this.waveState.map((s) => (s === 'pending' ? 'cancelled' : s));
      for (const e of this.active('enemy')) {
        e.status = 'routing';
        this.emit({ t: 'rout', uid: e.uid });
      }
      this.finish('victory');
    }
  }

  private startTurn(faction: Faction) {
    this.emit({ t: 'turn', faction, turn: this.turn });
    if (faction === 'enemy') {
      const o = this.objective;
      if (this.horn === 'waiting' && o.hornTurn !== undefined && this.turn >= o.hornTurn && this.waves.some((w) => w.horn)) {
        const herald = this.units.find((u) => u.faction === 'enemy' && u.tags.includes('herald') && (u.status === 'active' || u.status === 'routing'));
        if (herald) this.soundHorn(herald);
        else this.silenceHorn();
      }
      this.arriveWaves();
    } else {
      this.warnWaves();
      const o = this.objective;
      if (o.turns !== undefined && o.kind !== 'rout' && this.turn === o.turns) {
        this.log('Dawn is breaking. Hold them for one more turn!', 'good');
        for (const p of this.active('player')) this.changeMorale(p, 8, 'Relief is near');
      }
    }
    for (const u of this.units) u.struck = [];
    for (const u of this.units.filter((x) => x.faction === faction)) {
      u.hasMoved = false;
      u.hasActed = false;
      u.done = false;
      u.movedTiles = 0;
      for (const k of Object.keys(u.cooldowns)) u.cooldowns[k] = Math.max(0, u.cooldowns[k] - 1);
      if (u.stance) {
        u.stance = undefined;
        this.emit({ t: 'stance', uid: u.uid, stance: null });
      }
      if (u.statuses.length) this.bleed(u);
      // Trolls knit their wounds closed, but a fallen troll stays down.
      if (u.status === 'active' && u.tags.includes('regenerate')) {
        const healed = healSquad(u, Math.round(u.hpPer * 0.12) * u.alive);
        if (healed > 0) {
          this.emit({ t: 'heal', uid: u.uid, amount: healed, hp: u.hp, reason: 'Regenerates' });
          this.log(`The wounds of ${squadName(u)} close (+${healed}).`, u.faction === 'player' ? 'good' : 'bad');
        }
      }
    }
    // Morale upkeep: steady when supported, shaken when surrounded or losing.
    const strength = this.strength(faction);
    for (const u of this.active(faction)) {
      const allies = this.alliesOf(u).filter((a) => manhattan(a, u) === 1).length;
      const foes = this.enemiesOf(u).filter((e) => manhattan(e, u) === 1).length;
      let d = 0;
      let reason = 'Steadied';
      if (foes === 0) d += 2;
      d += Math.min(2, allies) * 2;
      if (foes >= 2) {
        d -= 8;
        reason = 'Surrounded';
      }
      // While more waves are coming the horde does not count its losses.
      if (!u.leader && strength < 0.5 && !(faction === 'enemy' && this.pendingWaves() > 0)) {
        d -= strength < 0.3 ? 12 : 6;
        reason = 'The battle is turning';
      }
      const nd = d > 0 ? Math.min(d, u.maxMorale - u.morale) : d;
      if (nd !== 0) this.changeMorale(u, nd, reason);
    }
    // Routing troops either rally or keep running.
    for (const u of this.units.filter((x) => x.faction === faction && x.status === 'routing')) {
      const near = this.enemiesOf(u).some((e) => dist(e, u) <= 3);
      const p = (u.faction === 'player' ? 0.4 : 0.22) + 0.05 * (u.level - 1);
      if (!near && this.rng.chance(p)) {
        u.status = 'active';
        u.morale = Math.round(u.maxMorale * 0.3);
        u.done = true;
        this.emit({ t: 'rally', uid: u.uid });
        this.log(`${squadName(u)} ${u.leader ? 'rallies' : 'rally'}!`, u.faction === 'player' ? 'good' : 'bad');
      } else {
        this.flee(u);
      }
    }
    this.checkEnd();
  }

  private flee(u: BattleUnit) {
    const reach = this.reachableFull(u);
    const foes = this.enemiesOf(u);
    let best: Pt | null = null;
    let bestScore = Infinity;
    for (const [k] of reach) {
      const p = { x: k % 1000, y: Math.floor(k / 1000) };
      if (unitAt(this.units, p.x, p.y) && !(p.x === u.x && p.y === u.y)) continue;
      const edge = Math.min(p.x, p.y, this.map.w - 1 - p.x, this.map.h - 1 - p.y);
      const foeD = foes.length ? Math.min(...foes.map((f) => dist(f, p))) : 10;
      const s = edge * 3 - Math.min(foeD, 6);
      if (s < bestScore) {
        bestScore = s;
        best = p;
      }
    }
    if (best && !(best.x === u.x && best.y === u.y)) {
      const path = this.pathFrom(reach, best.x, best.y);
      if (path) this.walk(u, path);
    }
    if (u.status === 'routing' && isEdge(this.map, u)) {
      u.status = 'fled';
      this.emit({ t: 'fled', uid: u.uid });
      // A horn-bearer who gets away raises the alarm.
      if (u.tags.includes('herald') && this.horn === 'waiting') this.soundHorn(u);
    }
  }

  checkEnd() {
    if (this.phase === 'over') return;
    if (this.company().length === 0) this.finish('defeat');
    else if (this.active('enemy').length === 0 && this.pendingWaves() === 0) this.finish('victory');
  }

  retreat() {
    if (this.phase !== 'player') return;
    for (const u of this.active('player')) {
      const foe = this.enemiesOf(u).find((e) => manhattan(e, u) === 1);
      if (foe) this.resolveAttack(foe, u, { reaction: 'zoc', forceMelee: true });
    }
    this.finish('retreat');
  }

  private finish(result: BattleResult) {
    this.phase = 'over';
    this.result = result;
    for (const u of this.units) {
      if (u.status === 'routing') {
        u.status = 'fled';
        this.emit({ t: 'fled', uid: u.uid });
      }
    }
    if (result === 'defeat') {
      for (const u of this.units.filter((x) => x.faction === 'player' && x.status === 'downed')) {
        if (this.rng.chance(0.5)) {
          u.status = 'dead';
          this.log(`The survivors of ${squadName(u)} are left behind on the field.`, 'bad');
        }
      }
    }
    // Experience.
    for (const u of this.units.filter((x) => x.faction === 'player')) {
      if (u.status === 'dead') continue;
      // Damage is counted for the whole squad; experience follows one soldier's share.
      u.xp += (result === 'victory' ? 5 : 2) + Math.floor(u.damageDealt / (8 * u.size));
    }
    this.emit({ t: 'end', result });
  }
}

export const EDGE_NAME: Record<Edge, string> = { n: 'northern', e: 'eastern', s: 'southern', w: 'western' };

export function facingToward(from: Pt, to: Pt): Dir {
  return dirTo(from, to);
}
