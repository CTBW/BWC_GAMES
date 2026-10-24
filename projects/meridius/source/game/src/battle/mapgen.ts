import { Rng } from '../core/rng';
import { BATTLE_MAPS, type MapTemplate, type Rect } from '../data/maps';
import { PROPS } from '../data/terrain';
import { canStep, inBounds, key, neighbors, tileAt, tilePassable } from './grid';
import type { BattleMap, BattleTile, Edge, Pt } from './types';

export interface MapGenOptions {
  ambush?: boolean;
  /** Edges reinforcements will use: the forest beyond them opens into a clearing where they mass. */
  approaches?: Edge[];
}

/** What each character of a hand-drawn layout stands for. */
const LEGEND: Record<string, { terrain?: string; prop?: string }> = {
  '.': { terrain: 'grass' },
  ',': { terrain: 'dirt' },
  ':': { terrain: 'mud' },
  '~': { terrain: 'water' },
  '=': { terrain: 'bridge' },
  _: { terrain: 'shallows' },
  T: { terrain: 'forest', prop: 'tree' },
  B: { prop: 'bush' },
  R: { prop: 'rock_large' },
  r: { prop: 'rock_small' },
  S: { prop: 'stump' },
  '#': { terrain: 'dirt', prop: 'palisade' },
  G: { terrain: 'stone', prop: 'gate' },
  '|': { prop: 'stakes' },
  W: { terrain: 'stone', prop: 'wall_ruin' },
  X: { terrain: 'stone', prop: 'wall_high' },
  F: { prop: 'fence' },
  c: { prop: 'crates' },
  k: { prop: 'cart' },
  h: { prop: 'haystack' },
  o: { terrain: 'stone', prop: 'well' },
  u: { terrain: 'rubble' },
  s: { terrain: 'stone' },
  t: { terrain: 'brush' },
};

/** Props drawn along one axis: [running along x, running along y]. */
const AXIS: Record<string, [string, string]> = {
  palisade: ['palisade', 'palisade_y'],
  fence: ['fence', 'fence_y'],
  wall_ruin: ['wall_ruin', 'wall_ruin_y'],
  gate: ['gate', 'gate_y'],
  stakes: ['stakes', 'stakes_y'],
};

/** Transposing a layout (x <-> y) swaps these edges. */
export const TRANSPOSED: Record<Edge, Edge> = { n: 'w', w: 'n', e: 's', s: 'e' };

/** Outward step beyond each edge. */
export const OUTWARD: Record<Edge, Pt> = { n: { x: 0, y: -1 }, w: { x: -1, y: 0 }, e: { x: 1, y: 0 }, s: { x: 0, y: 1 } };

/** Tiles along an edge, from `a` to `b` along it. */
function edgeTiles(w: number, h: number, edge: Edge, a: number, b: number): Pt[] {
  const out: Pt[] = [];
  for (let i = a; i <= b; i++) {
    if (edge === 'n') out.push({ x: i, y: 0 });
    else if (edge === 's') out.push({ x: i, y: h - 1 });
    else if (edge === 'w') out.push({ x: 0, y: i });
    else out.push({ x: w - 1, y: i });
  }
  return out;
}

/** Entry tiles of a stretch of edge, those nearest its middle first. */
function entryList(map: BattleMap, edge: Edge, a: number, b: number): Pt[] {
  const mid = (a + b) / 2;
  return edgeTiles(map.w, map.h, edge, a, b)
    .filter((p) => tilePassable(map, p.x, p.y))
    .sort((p, q) => {
      const ip = edge === 'n' || edge === 's' ? p.x : p.y;
      const iq = edge === 'n' || edge === 's' ? q.x : q.y;
      return Math.abs(ip - mid) - Math.abs(iq - mid);
    });
}

export function generateMap(templateId: string, seed: number, opts: MapGenOptions = {}): BattleMap {
  const tpl: MapTemplate = BATTLE_MAPS[templateId];
  if (tpl.layout) return generateAuthored(tpl, seed, opts);
  const rng = new Rng(seed);
  const { w, h } = tpl;
  const tiles: BattleTile[] = [];
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) tiles.push({ x, y, h: 0, terrain: 'grass', v: rng.int(0, 9999) });
  const map: BattleMap = {
    id: tpl.id,
    name: tpl.name,
    w,
    h,
    tiles,
    playerDeploy: [],
    enemyDeploy: [],
    biome: tpl.biome,
    seed,
    border: 7,
    outer: [],
  };

  // Deployment zones first so features can avoid them.
  const mid = Math.floor(h / 2);
  if (opts.ambush) {
    for (let y = mid - 1; y <= mid + 1; y++) for (let x = 4; x < w - 4; x++) map.playerDeploy.push({ x, y });
    for (let x = 2; x < w - 2; x++) {
      map.enemyDeploy.push({ x, y: 0 }, { x, y: 1 }, { x, y: h - 1 }, { x, y: h - 2 });
    }
  } else {
    for (let y = h - 3; y < h; y++) for (let x = 3; x < w - 3; x++) map.playerDeploy.push({ x, y });
    for (let y = 0; y < 3; y++) for (let x = 2; x < w - 2; x++) map.enemyDeploy.push({ x, y });
  }
  const reserved = new Set<number>([...map.playerDeploy, ...map.enemyDeploy].map((p) => key(p.x, p.y)));
  const isReserved = (x: number, y: number) => reserved.has(key(x, y));
  const T = (x: number, y: number) => tileAt(map, x, y);
  const free = (x: number, y: number) => {
    const t = T(x, y);
    return !!t && !t.prop && !isReserved(x, y) && t.terrain !== 'water' && t.terrain !== 'bridge' && t.terrain !== 'shallows';
  };

  // River with a bridge and a ford, crossing the field between the armies.
  if (tpl.river) {
    let ry = mid + rng.int(-1, 0);
    const bridgeX = rng.int(3, 5);
    const fordX = rng.int(w - 6, w - 4);
    for (let x = 0; x < w; x++) {
      if (x > 0 && rng.chance(0.3)) ry = Math.max(mid - 2, Math.min(mid + 1, ry + rng.pick([-1, 1])));
      const cells = [ry, ry + 1];
      for (const yy of cells) {
        const t = T(x, yy);
        if (!t) continue;
        reserved.delete(key(x, yy));
        if (Math.abs(x - bridgeX) <= 0) t.terrain = 'bridge';
        else if (Math.abs(x - fordX) <= 1) t.terrain = 'shallows';
        else t.terrain = 'water';
        t.prop = undefined;
      }
    }
  }

  // Hills: raised plateaus away from the deployment rows.
  const hills = rng.int(...tpl.hills);
  for (let i = 0; i < hills; i++) {
    const cx = rng.int(2, w - 3);
    const cy = rng.int(3, h - 4);
    const rx = rng.range(1.6, 3.2);
    const ry = rng.range(1.4, 2.6);
    const peak = rng.chance(0.35) ? 2 : 1;
    for (const t of tiles) {
      if (t.terrain === 'water' || t.terrain === 'bridge' || t.terrain === 'shallows') continue;
      const d = ((t.x - cx) / rx) ** 2 + ((t.y - cy) / ry) ** 2;
      if (d < 1) t.h = Math.max(t.h, d < 0.35 ? peak : 1);
    }
  }
  // Smooth cliffs so most of the field stays walkable (allow a few 2-steps).
  for (let pass = 0; pass < 2; pass++) {
    for (const t of tiles) {
      for (const n of neighbors(map, t)) {
        const nt = T(n.x, n.y)!;
        if (t.h - nt.h > 1 && rng.chance(0.6)) t.h = nt.h + 1;
      }
    }
  }

  const scatter = (count: number, place: (x: number, y: number) => void, margin = 1) => {
    for (let i = 0; i < count; i++) {
      for (let tries = 0; tries < 30; tries++) {
        const x = rng.int(margin, w - 1 - margin);
        const y = rng.int(margin, h - 1 - margin);
        if (free(x, y)) {
          place(x, y);
          break;
        }
      }
    }
  };

  // Dirt patches (visual) and thickets.
  scatter(rng.int(...tpl.dirt), (x, y) => {
    const r = rng.range(1, 2.4);
    for (const t of tiles) if (Math.hypot(t.x - x, t.y - y) < r && t.terrain === 'grass' && rng.chance(0.8)) t.terrain = 'dirt';
  }, 0);
  scatter(rng.int(...tpl.brush), (x, y) => {
    for (const t of tiles)
      if (Math.hypot(t.x - x, t.y - y) < 1.3 && t.terrain === 'grass' && !isReserved(t.x, t.y)) t.terrain = 'brush';
  });

  // Tree clumps with undergrowth.
  scatter(rng.int(...tpl.treeClumps), (x, y) => {
    const n = rng.int(2, 4);
    let px = x;
    let py = y;
    for (let i = 0; i < n; i++) {
      if (free(px, py)) {
        const t = T(px, py)!;
        t.prop = rng.chance(0.55) ? 'tree_pine' : 'tree_oak';
        t.terrain = 'forest';
      }
      const d = rng.pick([{ x: 1, y: 0 }, { x: 0, y: 1 }, { x: -1, y: 0 }, { x: 0, y: -1 }]);
      px += d.x;
      py += d.y;
    }
    for (const t of tiles) if (Math.hypot(t.x - x, t.y - y) < 1.8 && !t.prop && t.terrain === 'grass' && !isReserved(t.x, t.y) && rng.chance(0.5)) t.terrain = 'brush';
  });

  // Rock outcrops.
  scatter(rng.int(...tpl.rockClumps), (x, y) => {
    T(x, y)!.prop = 'rock_large';
    for (const n of neighbors(map, { x, y })) if (free(n.x, n.y) && rng.chance(0.35)) T(n.x, n.y)!.prop = 'rock_small';
  });

  scatter(rng.int(...tpl.bushes), (x, y) => {
    T(x, y)!.prop = rng.chance(0.8) ? 'bush' : 'stump';
  });

  // Fences: short straight runs.
  scatter(rng.int(...tpl.fences), (x, y) => {
    const horiz = rng.chance(0.5);
    const len = rng.int(2, 3);
    for (let i = 0; i < len; i++) {
      const fx = x + (horiz ? i : 0);
      const fy = y + (horiz ? 0 : i);
      if (free(fx, fy)) T(fx, fy)!.prop = horiz ? 'fence' : 'fence_y';
    }
  }, 2);

  // Ruined walls with a gap, and a broken tower.
  for (let r = 0; r < tpl.ruins; r++) {
    scatter(1, (x, y) => {
      const horiz = rng.chance(0.5);
      const len = rng.int(3, 4);
      const gap = rng.int(1, len - 2);
      for (let i = 0; i < len; i++) {
        if (i === gap) continue;
        const fx = x + (horiz ? i : 0);
        const fy = y + (horiz ? 0 : i);
        if (free(fx, fy)) {
          T(fx, fy)!.prop = i === 0 && rng.chance(0.5) ? 'wall_high' : horiz ? 'wall_ruin' : 'wall_ruin_y';
          T(fx, fy)!.terrain = 'stone';
        }
      }
      for (const t of tiles) if (Math.hypot(t.x - x, t.y - y) < 2.2 && !t.prop && t.terrain === 'grass' && rng.chance(0.4)) t.terrain = 'stone';
    }, 2);
  }

  // The warband's camp on the enemy side.
  if (tpl.camp) {
    const cy = rng.int(2, 3);
    const tentXs = [3, 6, 9, 12].filter((x) => x < w - 1);
    for (const tx of tentXs) {
      const y = cy + rng.int(-1, 1);
      if (T(tx, y) && !T(tx, y)!.prop) {
        T(tx, y)!.prop = rng.chance(0.75) ? 'tent' : 'crates';
        reserved.delete(key(tx, y));
        map.enemyDeploy = map.enemyDeploy.filter((p) => !(p.x === tx && p.y === y));
      }
    }
    const fire = { x: Math.floor(w / 2), y: cy + 2 };
    const ft = T(fire.x, fire.y)!;
    ft.prop = 'campfire';
    ft.terrain = 'dirt';
    for (const t of tiles) if (t.y <= cy + 3 && !t.prop && rng.chance(0.55) && t.terrain === 'grass') t.terrain = 'dirt';
    for (const tx of [1, w - 2]) {
      const t = T(tx, cy + 3);
      if (t && !t.prop) t.prop = 'totem';
    }
    map.enemyDeploy = map.enemyDeploy.filter((p) => !T(p.x, p.y)!.prop);
  }

  const usable = (p: Pt) => tilePassable(map, p.x, p.y);
  map.playerDeploy = map.playerDeploy.filter(usable);
  map.enemyDeploy = map.enemyDeploy.filter(usable);
  ensureConnected(map, rng);
  // Reinforcements enter along the far edge and down the flanks, away from the company.
  map.scale = 'small';
  map.entries = {
    n: entryList(map, 'n', 1, w - 2),
    w: entryList(map, 'w', 1, Math.floor(h * 0.55)),
    e: entryList(map, 'e', 1, Math.floor(h * 0.55)),
  };
  if (opts.ambush) map.entries.s = entryList(map, 's', 2, w - 3);
  map.approaches = opts.approaches ?? ['n'];
  buildOuterRing(map, rng);
  return map;
}

/**
 * A hand-drawn last-stand field. Half of the seeds transpose the layout
 * (x <-> y), which mirrors it across the screen's vertical axis; the details
 * (tree kinds, bushes, prop looks) vary with every seed.
 */
function generateAuthored(tpl: MapTemplate, seed: number, opts: MapGenOptions): BattleMap {
  const L = tpl.layout!;
  const rng = new Rng(seed);
  const flip = rng.chance(0.5);
  const H0 = L.rows.length;
  const W0 = L.rows[0].length;
  const w = flip ? H0 : W0;
  const h = flip ? W0 : H0;
  const toGrid = (lx: number, ly: number): Pt => (flip ? { x: ly, y: lx } : { x: lx, y: ly });
  const tiles: BattleTile[] = [];
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const lx = flip ? y : x;
      const ly = flip ? x : y;
      const ch = L.rows[ly][lx];
      const lg = LEGEND[ch] ?? LEGEND['.'];
      const t: BattleTile = { x, y, h: Number(L.heights[ly]?.[lx] ?? 0) || 0, terrain: lg.terrain ?? 'grass', v: rng.int(0, 9999) };
      if (lg.prop === 'tree') t.prop = rng.chance(0.55) ? 'tree_pine' : 'tree_oak';
      else if (lg.prop) t.prop = lg.prop;
      tiles.push(t);
    }
  }
  const map: BattleMap = {
    id: tpl.id,
    name: tpl.name,
    w,
    h,
    tiles,
    playerDeploy: [],
    enemyDeploy: [],
    biome: tpl.biome,
    seed,
    border: 8,
    outer: [],
    scale: 'large',
  };
  const T = (x: number, y: number) => tileAt(map, x, y);
  // Walls, fences and gates run along whichever axis their neighbours do.
  const runs = (x: number, y: number, group: string) => {
    const p = T(x, y)?.prop;
    if (!p) return false;
    const base = Object.keys(AXIS).find((k) => AXIS[k].includes(p));
    return base === group || (group === 'palisade' && (p === 'wall_high' || p === 'gate' || p === 'gate_y')) || (group === 'gate' && (base === 'palisade' || p === 'wall_high'));
  };
  for (const t of tiles) {
    if (!t.prop || !AXIS[t.prop]) continue;
    const g = t.prop;
    const alongX = runs(t.x - 1, t.y, g) || runs(t.x + 1, t.y, g) || (T(t.x - 1, t.y)?.terrain === 'rubble') || (T(t.x + 1, t.y)?.terrain === 'rubble');
    const alongY = runs(t.x, t.y - 1, g) || runs(t.x, t.y + 1, g) || (T(t.x, t.y - 1)?.terrain === 'rubble') || (T(t.x, t.y + 1)?.terrain === 'rubble');
    t.prop = alongX || !alongY ? AXIS[g][0] : AXIS[g][1];
  }
  const rect = (r: Rect): Pt[] => {
    const out: Pt[] = [];
    for (let ly = r[1]; ly <= r[3]; ly++) for (let lx = r[0]; lx <= r[2]; lx++) out.push(toGrid(lx, ly));
    return out;
  };
  const open = (p: Pt) => tilePassable(map, p.x, p.y) && !T(p.x, p.y)!.prop;
  map.playerDeploy = L.deploy.flatMap(rect).filter(open);
  map.enemyDeploy = L.enemy.flatMap(rect).filter(open);
  if (L.zone) {
    map.zone = rect(L.zone).filter((p) => tilePassable(map, p.x, p.y));
    map.zoneName = L.zoneName;
  }
  // A few bushes and stumps in the open fields, never on the marked ground.
  const marked = new Set([...map.playerDeploy, ...map.enemyDeploy, ...(map.zone ?? [])].map((p) => key(p.x, p.y)));
  const extras = rng.int(...tpl.bushes);
  for (let i = 0, tries = 0; i < extras && tries < 200; tries++) {
    const t = T(rng.int(1, w - 2), rng.int(1, h - 2))!;
    if (t.prop || t.terrain !== 'grass' || marked.has(key(t.x, t.y))) continue;
    if (neighbors(map, t).some((n) => T(n.x, n.y)!.prop)) continue;
    t.prop = rng.chance(0.75) ? 'bush' : 'stump';
    i++;
  }
  map.entries = {};
  for (const [e, span] of Object.entries(L.entries) as [Edge, [number, number]][]) {
    const ge = flip ? TRANSPOSED[e] : e;
    map.entries[ge] = entryList(map, ge, span[0], span[1]);
  }
  map.transposed = flip;
  const appr = opts.approaches ?? [tpl.edges?.main ?? 'n'];
  map.approaches = appr.map((e) => (flip ? TRANSPOSED[e] : e));
  buildOuterRing(map, rng);
  return map;
}

/** Remove props until every enemy deploy tile is reachable from the player zone. */
function ensureConnected(map: BattleMap, rng: Rng) {
  for (let guard = 0; guard < 40; guard++) {
    const start = map.playerDeploy.find((p) => tilePassable(map, p.x, p.y))!;
    const seen = new Set<number>([key(start.x, start.y)]);
    const q: Pt[] = [start];
    while (q.length) {
      const c = q.shift()!;
      for (const n of neighbors(map, c)) {
        const k = key(n.x, n.y);
        if (seen.has(k) || !tilePassable(map, n.x, n.y) || !canStep(map, c, n)) continue;
        seen.add(k);
        q.push(n);
      }
    }
    const missing = map.enemyDeploy.find((p) => tilePassable(map, p.x, p.y) && !seen.has(key(p.x, p.y)));
    const missingPlayer = map.playerDeploy.find((p) => tilePassable(map, p.x, p.y) && !seen.has(key(p.x, p.y)));
    const target = missing ?? missingPlayer;
    if (!target) return;
    // Carve a straight-ish corridor from the target toward the start.
    let c = { ...target };
    while (!seen.has(key(c.x, c.y))) {
      const t = tileAt(map, c.x, c.y)!;
      if (t.prop) t.prop = undefined;
      if (t.terrain === 'water') t.terrain = 'shallows';
      const dx = Math.sign(start.x - c.x);
      const dy = Math.sign(start.y - c.y);
      const n = rng.chance(0.5) && dx !== 0 ? { x: c.x + dx, y: c.y } : dy !== 0 ? { x: c.x, y: c.y + dy } : { x: c.x + dx, y: c.y };
      const nt = tileAt(map, n.x, n.y)!;
      if (Math.abs(nt.h - t.h) > 1) nt.h = t.h + Math.sign(nt.h - t.h);
      c = n;
    }
  }
}

/**
 * The stretch beyond an approach edge where a coming wave masses in view: as
 * wide as the edge's entries (plus a margin) and as deep as the border.
 */
export function inApproach(map: BattleMap, x: number, y: number): Edge | undefined {
  for (const e of map.approaches ?? []) {
    const list = map.entries?.[e];
    if (!list?.length) continue;
    const along = e === 'n' || e === 's' ? x : y;
    const span = list.map((p) => (e === 'n' || e === 's' ? p.x : p.y));
    const lo = Math.min(...span) - 1;
    const hi = Math.max(...span) + 1;
    if (along < lo || along > hi) continue;
    if (e === 'n' && y < 0) return e;
    if (e === 's' && y >= map.h) return e;
    if (e === 'w' && x < 0) return e;
    if (e === 'e' && x >= map.w) return e;
  }
  return undefined;
}

/** Dense decorative forest around the playable area (not part of the grid). */
function buildOuterRing(map: BattleMap, rng: Rng) {
  const b = map.border;
  map.outerGround = [];
  for (let y = -b; y < map.h + b; y++) {
    for (let x = -b; x < map.w + b; x++) {
      if (inBounds(map, x, y)) continue;
      const d = Math.max(-x, -y, x - (map.w - 1), y - (map.h - 1));
      // Approaches: an open, trampled field where the horde masses, edged by brush.
      if (inApproach(map, x, y)) {
        map.outerGround.push({ x, y, terrain: rng.chance(0.55) ? 'dirt' : 'grass' });
        if (rng.chance(0.04)) map.outer.push({ x, y, h: 0, prop: rng.pick(['bush', 'rock_small', 'stump']), v: rng.int(0, 9999) });
        continue;
      }
      // Keep the near-camera edges open so trees never hide the troops.
      const front = x >= map.w || y >= map.h;
      if (front && d <= 2) {
        if (rng.chance(0.18)) map.outer.push({ x, y, h: 0, prop: rng.pick(['bush', 'rock_small', 'bush']), v: rng.int(0, 9999) });
        continue;
      }
      const density = d <= 1 ? 0.35 : d <= 2 ? 0.6 : 0.85;
      if (!rng.chance(density)) {
        if (rng.chance(0.25)) map.outer.push({ x, y, h: 0, prop: rng.pick(['bush', 'rock_small', 'bush']), v: rng.int(0, 9999) });
        continue;
      }
      const prop = rng.chance(0.08) ? 'rock_large' : rng.chance(0.6) ? 'tree_pine' : 'tree_oak';
      map.outer.push({ x, y, h: 0, prop, v: rng.int(0, 9999) });
    }
  }
}

export function propBlocks(prop?: string) {
  return !!prop && PROPS[prop].blocksMove;
}
