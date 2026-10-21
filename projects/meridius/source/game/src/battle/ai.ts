import type { AiProfile, Dir } from '../core/types';
import { ABILITIES } from '../data/abilities';
import { PROPS } from '../data/terrain';
import { UNIT_TYPES } from '../data/units';
import type { Battle, ReachInfo } from './battle';
import { DIRS, canStep, dist, key, lineOfSight, manhattan, moveCost, neighbors, tileAt, tilePassable } from './grid';
import type { BattleUnit, Pt } from './types';

const PLAYER_PROFILES: Record<string, AiProfile> = {
  footman: { aggression: 0.55, caution: 0.45, swarm: 0.5 },
  spearman: { aggression: 0.45, caution: 0.5, swarm: 0.5 },
  crossbowman: { aggression: 0.2, caution: 0.8, preferRange: 5, swarm: 0.2 },
  collie_guard: { aggression: 0.6, caution: 0.4, swarm: 0.5 },
};

export function profileOf(u: BattleUnit): AiProfile {
  return UNIT_TYPES[u.typeId]?.ai ?? PLAYER_PROFILES[u.typeId] ?? { aggression: 0.5, caution: 0.5 };
}

interface Plan {
  score: number;
  tile: Pt;
  target?: BattleUnit;
  ability?: string;
}

/** Expected damage a faction could inflict on each tile next turn. */
function dangerMap(b: Battle, from: 'player' | 'enemy'): Map<number, number> {
  const out = new Map<number, number>();
  const foes = b.active(from);
  for (const t of b.map.tiles) {
    let d = 0;
    for (const f of foes) {
      // Weapon damage is per soldier; a depleted squad threatens less.
      const strength = f.alive / f.size;
      const m = manhattan(f, t);
      if (m <= f.stats.move + 1) d += ((f.melee[0] + f.melee[1]) / 2) * 0.6 * (m <= 1 ? 1.2 : 1) * strength;
      if (f.shot && f.ammo !== 0) {
        const r = dist(f, t);
        if (r >= f.shot.minRange && r <= f.shot.range) d += ((f.shot.damage[0] + f.shot.damage[1]) / 2) * 0.45 * strength;
      }
    }
    out.set(key(t.x, t.y), d);
  }
  return out;
}

/**
 * Movement-cost distance from every tile to the nearest tile adjacent to a
 * foe. `flanks` makes the tiles at a foe's sides and back nearer than those
 * at its front, so swarms and riders flow round a line rather than into it.
 * `zone` adds the ground the enemy wants to take (last stands).
 */
function approachField(b: Battle, foes: BattleUnit[], flanks = false, zone?: Pt[]): Map<number, number> {
  const out = new Map<number, number>();
  const open: { p: Pt; c: number }[] = [];
  const seed = (p: Pt, c: number) => {
    if (!tilePassable(b.map, p.x, p.y)) return;
    const k = key(p.x, p.y);
    if ((out.get(k) ?? Infinity) <= c) return;
    out.set(k, c);
    open.push({ p, c });
  };
  for (const f of foes) {
    for (const n of neighbors(b.map, f)) {
      const arc = flanks ? b.arcOf(f, n) : 'rear';
      seed(n, arc === 'rear' ? 0 : arc === 'flank' ? 0.6 : 2);
    }
  }
  for (const p of zone ?? []) seed(p, 1);
  while (open.length) {
    open.sort((a, c) => a.c - c.c);
    const cur = open.shift()!;
    if (cur.c > (out.get(key(cur.p.x, cur.p.y)) ?? Infinity)) continue;
    for (const n of neighbors(b.map, cur.p)) {
      if (!tilePassable(b.map, n.x, n.y) || !canStep(b.map, cur.p, n)) continue;
      const c = cur.c + moveCost(b.map, cur.p.x, cur.p.y);
      const k = key(n.x, n.y);
      if (c < (out.get(k) ?? Infinity)) {
        out.set(k, c);
        open.push({ p: n, c });
      }
    }
  }
  return out;
}

function pathTiles(reach: Map<number, ReachInfo>, k: number): number[] {
  const out: number[] = [];
  let cur = k;
  while (cur !== -1) {
    out.push(cur);
    cur = reach.get(cur)?.prev ?? -1;
  }
  return out.reverse();
}

function guardPenalty(b: Battle, u: BattleUnit, tiles: number[], careless: boolean): number {
  if (careless) return 0;
  let pen = 0;
  const foes = b.enemiesOf(u);
  for (let i = 1; i < tiles.length; i++) {
    const p = { x: tiles[i] % 1000, y: Math.floor(tiles[i] / 1000) };
    for (const s of foes) {
      if (s.stance === 'spearwall' && manhattan(s, p) === 1 && b.arcOf(s, p) !== 'rear') pen += 14;
      if (s.stance === 'overwatch' && s.shot && dist(s, p) <= s.shot.range && dist(s, p) >= s.shot.minRange) {
        if (!lineOfSight(b.map, s, p).blocked) pen += 6;
      }
    }
  }
  return pen;
}

function targetWeight(b: Battle, u: BattleUnit, t: BattleUnit): number {
  const role = profileOf(u).role;
  let w = 1;
  // Riders hunt the crossbowmen; everyone likes a soft target.
  if (t.shot) w += role === 'flanker' ? 0.9 : 0.3;
  if (t.status === 'routing') w -= 0.4;
  if (t.leader) w += 0.3;
  if (u.faction === 'enemy') {
    // The horde goes for the weak: thinned squads and shaken ones.
    w += (1 - t.hp / t.maxHp) * 0.5;
    const ms = b.moraleState(t);
    if (ms === 'shaken' || ms === 'wavering') w += 0.3;
    if (t.tags.includes('militia')) w += 0.2;
  }
  return w;
}

/**
 * Per-turn caches: the foes' threat map and approach fields only change when
 * the other side moves, and an enemy turn may run thirty squads over them.
 */
const fieldCache = new WeakMap<Battle, { stamp: string; danger: Map<string, Map<number, number>>; fields: Map<string, Map<number, number>> }>();

function cacheFor(b: Battle, side: 'player' | 'enemy') {
  const stamp = `${b.turn}|${b.phase}|${b.active(side).map((u) => `${u.uid}:${u.x},${u.y},${u.facing},${u.alive}`).join(';')}`;
  let c = fieldCache.get(b);
  if (!c || c.stamp !== stamp) {
    c = { stamp, danger: new Map(), fields: new Map() };
    fieldCache.set(b, c);
  }
  return c;
}

function cachedDanger(b: Battle, from: 'player' | 'enemy'): Map<number, number> {
  const c = cacheFor(b, from);
  let d = c.danger.get(from);
  if (!d) {
    d = dangerMap(b, from);
    c.danger.set(from, d);
  }
  return d;
}

function cachedApproach(b: Battle, u: BattleUnit, foes: BattleUnit[], flanks: boolean, zone?: Pt[]): Map<number, number> {
  const side = u.faction === 'player' ? 'enemy' : 'player';
  const c = cacheFor(b, side);
  const k = `${side}|${flanks}|${zone ? 'z' : ''}`;
  let f = c.fields.get(k);
  if (!f) {
    f = approachField(b, foes, flanks, zone);
    c.fields.set(k, f);
  }
  return f;
}

function coverAt(b: Battle, p: Pt, threat: Pt | undefined): number {
  if (!threat) return 0;
  let c = 0;
  for (const n of neighbors(b.map, p)) {
    const t = tileAt(b.map, n.x, n.y)!;
    if (t.prop && PROPS[t.prop].cover && dist(n, threat) < dist(p, threat)) c = Math.max(c, PROPS[t.prop].cover);
  }
  return c;
}

/**
 * How badly a squad on `at` facing `dir` would be caught by the foes that can
 * reach it next turn: blows into its flank count about half, into its back in
 * full; frontal blows meet its shields and spears.
 */
export function exposure(at: Pt, dir: Dir, foes: BattleUnit[]): number {
  const f = DIRS[dir];
  let pen = 0;
  for (const e of foes) {
    const strength = e.alive / e.size;
    const m = manhattan(e, at);
    let threat = 0;
    if (m <= e.stats.move + 1) threat = ((e.melee[0] + e.melee[1]) / 2) * strength * (m <= 1 ? 1.5 : 1);
    if (e.shot && e.ammo !== 0 && dist(e, at) <= e.shot.range) threat = Math.max(threat, ((e.shot.damage[0] + e.shot.damage[1]) / 2) * strength * 0.5);
    if (!threat) continue;
    const dx = e.x - at.x;
    const dy = e.y - at.y;
    const cos = (f.x * dx + f.y * dy) / (Math.hypot(dx, dy) || 1);
    pen += threat * (cos >= 0.5 ? 0 : cos > -0.5 ? 0.45 : 1);
  }
  return pen;
}

/**
 * Pick the way to arrive on `tile`: a squad faces the way it last stepped, so
 * the path decides which side it shows the enemy. Never pays extra free
 * attacks for a better facing, and turns in place (out and back) only when it
 * clearly helps.
 */
export function chooseFacing(b: Battle, u: BattleUnit, tile: Pt): Dir | undefined {
  const options = b.facingOptions(u, tile.x, tile.y);
  if (!options.length) return undefined;
  const minZoc = Math.min(...options.map((o) => o.zoc));
  const foes = b.enemiesOf(u);
  const home = tile.x === u.x && tile.y === u.y;
  let best: { facing: Dir; s: number } | null = null;
  for (const o of options) {
    if (o.zoc > minZoc) continue;
    let s = exposure(tile, o.facing, foes) + o.cost * 0.05;
    if (home && o.path.length > 1) s += 4;
    if (!best || s < best.s) best = { facing: o.facing, s };
  }
  return best?.facing;
}

export function actUnit(b: Battle, u: BattleUnit, opts: { useStances?: boolean; hold?: Set<number> } = {}) {
  if (u.status !== 'active' || b.isOver()) return;
  const prof = profileOf(u);
  const foes = b.enemiesOf(u);
  const allFoes = foes.concat(b.units.filter((x) => x.status === 'routing' && x.faction !== u.faction));
  if (!allFoes.length) return;
  const ms = b.moraleState(u);

  // Leaders shout when the warband wavers or the enemy closes in.
  for (const ab of u.abilities) {
    const def = ABILITIES[ab];
    if (def?.kind !== 'shout' || (u.cooldowns[ab] ?? 0) > 0 || u.hasActed) continue;
    const r = def.radius ?? 4;
    const shaky = b.alliesOf(u).filter((a) => dist(a, u) <= r && a.morale / a.maxMorale < 0.6).length;
    const close = foes.filter((f) => dist(f, u) <= r).length;
    if (shaky >= 2 || close >= 2) b.shout(u.uid, ab);
  }

  const careless = b.rng.chance(prof.carelessness ?? 0);
  const danger = cachedDanger(b, u.faction === 'player' ? 'enemy' : 'player');
  // The horn-bearer hangs back only until his horn has sounded; then he fights like the rest.
  const role = prof.role === 'herald' && b.horn !== 'waiting' ? 'line' : prof.role;
  // The company's own automation holds its ground in a last stand, and keeps
  // a reserve standing in the ground to hold so it is never simply walked into.
  const zoneKeys = opts.hold && b.map.zone ? new Set(b.map.zone.map((p) => key(p.x, p.y))) : undefined;
  const guards = zoneKeys ? b.alliesOf(u).filter((a) => zoneKeys.has(key(a.x, a.y))).length : 2;
  const outside = (k: number) => (opts.hold && !opts.hold.has(k) ? 12 : 0) - (zoneKeys && guards < 2 && zoneKeys.has(k) ? 8 : 0);
  const reach = u.hasMoved ? new Map([[key(u.x, u.y), { cost: 0, prev: -1, zoc: 0 } as ReachInfo]]) : b.reachable(u);
  const nearestFoe = (p: Pt) => foes.reduce((m, f) => Math.min(m, dist(f, p)), Infinity);
  const timid = ms === 'shaken' || ms === 'wavering';
  const aggression = timid ? prof.aggression * 0.4 : prof.aggression;
  const caution = timid ? Math.min(1, prof.caution + 0.4) : prof.caution;

  // An attack is worth making when its expected value clears this bar. Steady
  // troops take any worthwhile attack and pick the safest tile for it; shaken
  // ones only strike when the whole plan, position included, clears it.
  // The horde never stands idle beside the enemy: swarms hack at anything in reach.
  const horde = u.faction === 'enemy' && role !== 'herald' && role !== 'missile';
  const minAttack = horde && (role === 'swarm' || role === 'shock') ? 0.8 : 2;
  let best: Plan | null = null;
  const attackOptions: (string | undefined)[] = [undefined];
  if (ms !== 'wavering') {
    for (const ab of u.abilities) {
      const def = ABILITIES[ab];
      if (def?.kind === 'attack' && def.damageMult && (u.cooldowns[ab] ?? 0) === 0) attackOptions.push(ab);
    }
  }

  for (const [k, info] of reach) {
    const tile = { x: k % 1000, y: Math.floor(k / 1000) };
    const tiles = pathTiles(reach, k);
    const moved = tiles.length - 1;
    const zocCost = info.zoc * 6 * (1 - (prof.carelessness ?? 0) * 0.5);
    const guard = guardPenalty(b, u, tiles, careless);
    const dng = (danger.get(k) ?? 0) * caution * 0.6;
    const adjAllies = b.alliesOf(u).filter((a) => manhattan(a, tile) === 1).length;
    const tileH = tileAt(b.map, tile.x, tile.y)!.h;
    let posScore = -zocCost - guard - dng + (prof.swarm ?? 0) * adjAllies * 3 + tileH * 1.5 - outside(k);
    // The horn-bearer keeps well out of reach.
    if (role === 'herald') posScore -= Math.max(0, 6 - nearestFoe(tile)) * 4;
    if (u.shot) {
      const nf = nearestFoe(tile);
      if (nf <= 1.01) posScore -= 12;
      if (prof.preferRange) posScore -= Math.abs(nf - prof.preferRange) * 1.2;
      posScore += coverAt(b, tile, foes[0]) * 0.15;
    }

    if (!u.hasActed && role !== 'herald') {
      for (const t of allFoes) {
        if (manhattan(t, tile) > (u.shot ? u.shot.range + 3 : 3)) continue;
        for (const ab of attackOptions) {
          const pv = b.preview(u, t, { from: tile, ability: ab, movedTiles: moved });
          if (!pv.legal) continue;
          // Squad damage in one full-strength soldier's terms, so it weighs
          // against position the way a single blow always has.
          const avg = (pv.min + pv.max) / 2 / u.size;
          const p = pv.chance / 100;
          // Morale only breaks on a hit, so it counts at the hit chance like damage does.
          let s = p * avg * targetWeight(b, u, t) + pv.kill * 22 + p * pv.moraleHit * 0.35;
          if (pv.arc === 'rear') s += 3 * p;
          // Swarms and riders go round the shields: sides and backs first.
          if (role === 'swarm' || role === 'flanker') s += (pv.arc === 'flank' ? 2.5 : pv.arc === 'rear' ? 5 : 0) * p;
          if (role === 'flanker' && pv.arc === 'front' && (t.stance === 'spearwall' || t.tags.includes('firstStrike'))) s -= 4;
          // Piling onto a squad already beset breaks it.
          if (role === 'swarm') s += b.alliesOf(u).filter((a) => manhattan(a, t) === 1 && !(a.x === tile.x && a.y === tile.y)).length * 1.2;
          if (t.status === 'routing') s *= 0.5;
          // Spearmen strike first at chargers from the front.
          if (!u.shot && t.tags.includes('firstStrike') && moved > 0 && pv.arc === 'front' && !careless) s -= 7;
          const score = s * (0.6 + aggression) + posScore;
          if ((timid ? score : s) < minAttack) continue;
          if (!best || score > best.score) best = { score, tile, target: t, ability: ab };
        }
      }
    }
  }

  // Without a worthwhile attack, advance (or hold) according to temperament.
  if (!best) {
    // The horde makes for the ground it means to take as much as for the company.
    const zone = u.faction === 'enemy' && b.objective.kind === 'hold' ? b.map.zone : undefined;
    const field = cachedApproach(b, u, foes, role === 'swarm' || role === 'flanker', zone);
    let move: Plan | null = null;
    for (const [k, info] of reach) {
      const tile = { x: k % 1000, y: Math.floor(k / 1000) };
      const tiles = pathTiles(reach, k);
      const approach = field.get(k) ?? 30;
      const adjAllies = b.alliesOf(u).filter((a) => manhattan(a, tile) === 1).length;
      let s =
        -approach * aggression * 2 -
        (danger.get(k) ?? 0) * caution * 0.5 -
        info.zoc * 6 -
        guardPenalty(b, u, tiles, careless) +
        (prof.swarm ?? 0) * adjAllies * 2 +
        tileAt(b.map, tile.x, tile.y)!.h * 1.5 -
        outside(k);
      if (role === 'herald') s -= Math.max(0, 6 - nearestFoe(tile)) * 4;
      if (u.shot && prof.preferRange) {
        const nf = nearestFoe(tile);
        s -= Math.abs(nf - prof.preferRange) * 2;
        const seen = foes.some((f) => !lineOfSight(b.map, tile, f).blocked && dist(tile, f) <= u.shot!.range);
        if (seen) s += 4;
        s += coverAt(b, tile, foes[0]) * 0.15;
      }
      if (!move || s > move.score) move = { score: s, tile };
    }
    best = move;
  }
  if (!best) return;

  if (!u.hasMoved) {
    const facing = chooseFacing(b, u, best.tile);
    const home = best.tile.x === u.x && best.tile.y === u.y;
    if (!home || (facing !== undefined && facing !== u.facing)) b.move(u.uid, best.tile.x, best.tile.y, facing);
  }
  if (u.status !== 'active' || b.isOver()) return;

  if (best.target && !u.hasActed) {
    let target = best.target;
    let ability = best.ability;
    if (!b.preview(u, target, { ability }).legal || (target.status !== 'active' && target.status !== 'routing')) {
      // Re-pick from where we actually ended up.
      const options = b.targets(u).map((t) => ({ t, pv: b.preview(u, t) }));
      options.sort((a, c) => c.pv.chance * (c.pv.min + c.pv.max) - a.pv.chance * (a.pv.min + a.pv.max));
      target = options[0]?.t;
      ability = undefined;
    }
    if (target) b.attack(u.uid, target.uid, ability);
  } else if (!u.hasActed && ms !== 'wavering') {
    // Attacks cost nothing, so a unit that ends its move within reach strikes
    // anyway rather than standing idle beside the enemy.
    const options = b
      .targets(u)
      .map((t) => ({ t, pv: b.preview(u, t) }))
      .filter((o) => o.pv.legal && o.pv.chance >= (horde ? 5 : 15));
    options.sort((a, c) => c.pv.chance * (c.pv.min + c.pv.max) - a.pv.chance * (a.pv.min + a.pv.max));
    if (options[0]) b.attack(u.uid, options[0].t.uid);
  }

  if (u.status !== 'active' || b.isOver()) return;

  // Player-side automation (simulation) can use stances.
  if (opts.useStances && !u.hasActed) {
    const stance = u.abilities.find((a) => ABILITIES[a]?.kind === 'stance');
    if (stance) {
      const threat = foes.some((f) => dist(f, u) <= f.stats.move + 2);
      if (threat) b.useStance(u.uid, stance);
    }
  }
}

/**
 * Who acts first in the horde: archers loose, the heavy orcs crash into the
 * front, riders slip round it, the swarm floods the gaps they opened, and the
 * leaders and the horn-bearer come last.
 */
const ROLE_ORDER: Record<string, number> = { missile: 0, shock: 1, line: 2, flanker: 3, swarm: 4, leader: 5, herald: 6 };

export function runEnemyAi(b: Battle) {
  const rank = (u: BattleUnit) => {
    if (u.shot) return 0;
    if (u.leader) return 5;
    return ROLE_ORDER[profileOf(u).role ?? 'line'] ?? 2;
  };
  const order = b
    .active('enemy')
    .slice()
    .sort((a, c) => {
      const ra = rank(a);
      const rc = rank(c);
      if (ra !== rc) return ra - rc;
      const da = Math.min(...b.active('player').map((p) => dist(p, a)), 99);
      const dc = Math.min(...b.active('player').map((p) => dist(p, c)), 99);
      return da - dc;
    });
  for (const u of order) {
    if (b.isOver()) return;
    if (u.status !== 'active') continue;
    actUnit(b, u);
  }
}

/**
 * Plays the player's side automatically (used by the simulator and tests).
 * In a last stand it holds the deployment ground and the ground to keep, as a
 * sensible commander would, instead of marching out to meet the horde.
 */
export function runPlayerAuto(b: Battle) {
  const o = b.objective;
  const hold = o.kind === 'hold' || o.kind === 'survive' ? new Set([...b.map.playerDeploy, ...(b.map.zone ?? [])].map((p) => key(p.x, p.y))) : undefined;
  const order = b
    .active('player')
    .slice()
    .sort((a, c) => (a.shot ? 0 : 1) - (c.shot ? 0 : 1));
  for (const u of order) {
    if (b.isOver()) return;
    if (u.status !== 'active') continue;
    actUnit(b, u, { useStances: true, hold });
  }
}
