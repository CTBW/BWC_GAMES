import type { Dir } from '../core/types';
import { PROPS, TERRAIN } from '../data/terrain';
import type { BattleMap, BattleTile, BattleUnit, Pt } from './types';

export const DIRS: readonly Pt[] = [
  { x: 1, y: 0 },
  { x: 0, y: 1 },
  { x: -1, y: 0 },
  { x: 0, y: -1 },
];

export function tileAt(map: BattleMap, x: number, y: number): BattleTile | undefined {
  if (x < 0 || y < 0 || x >= map.w || y >= map.h) return undefined;
  return map.tiles[y * map.w + x];
}

export function inBounds(map: BattleMap, x: number, y: number): boolean {
  return x >= 0 && y >= 0 && x < map.w && y < map.h;
}

export const key = (x: number, y: number) => y * 1000 + x;
export const unkey = (k: number): Pt => ({ x: k % 1000, y: Math.floor(k / 1000) });

export function manhattan(a: Pt, b: Pt): number {
  return Math.abs(a.x - b.x) + Math.abs(a.y - b.y);
}

export function dist(a: Pt, b: Pt): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

export function dirTo(from: Pt, to: Pt): Dir {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  if (Math.abs(dx) >= Math.abs(dy)) return dx >= 0 ? 0 : 2;
  return dy >= 0 ? 1 : 3;
}

export function tilePassable(map: BattleMap, x: number, y: number): boolean {
  const t = tileAt(map, x, y);
  if (!t) return false;
  if (!TERRAIN[t.terrain].passable) return false;
  if (t.prop && PROPS[t.prop].blocksMove) return false;
  return true;
}

export function moveCost(map: BattleMap, x: number, y: number): number {
  const t = tileAt(map, x, y)!;
  return TERRAIN[t.terrain].moveCost;
}

/** Can a unit step between two adjacent tiles given heights? */
export function canStep(map: BattleMap, a: Pt, b: Pt): boolean {
  const ta = tileAt(map, a.x, a.y);
  const tb = tileAt(map, b.x, b.y);
  if (!ta || !tb) return false;
  return Math.abs(ta.h - tb.h) <= 1;
}

export function unitAt(units: BattleUnit[], x: number, y: number): BattleUnit | undefined {
  return units.find(
    (u) => u.x === x && u.y === y && (u.status === 'active' || u.status === 'routing'),
  );
}

export function neighbors(map: BattleMap, p: Pt): Pt[] {
  const out: Pt[] = [];
  for (const d of DIRS) {
    const nx = p.x + d.x;
    const ny = p.y + d.y;
    if (inBounds(map, nx, ny)) out.push({ x: nx, y: ny });
  }
  return out;
}

export function isEdge(map: BattleMap, p: Pt): boolean {
  return p.x === 0 || p.y === 0 || p.x === map.w - 1 || p.y === map.h - 1;
}

/**
 * Line of sight between tile centres. Returns blocked, the number of partial
 * obstructions crossed, and the tiles crossed (excluding endpoints).
 */
export function lineOfSight(
  map: BattleMap,
  a: Pt,
  b: Pt,
): { blocked: boolean; partial: number; tiles: Pt[] } {
  const ta = tileAt(map, a.x, a.y)!;
  const tb = tileAt(map, b.x, b.y)!;
  const ha = ta.h + 0.9;
  const hb = tb.h + 0.6;
  const steps = Math.max(Math.abs(b.x - a.x), Math.abs(b.y - a.y)) * 3;
  const seen = new Set<number>();
  const tiles: Pt[] = [];
  let partial = 0;
  let foliage = 0;
  for (let i = 1; i < steps; i++) {
    const f = i / steps;
    const fx = a.x + (b.x - a.x) * f;
    const fy = a.y + (b.y - a.y) * f;
    const x = Math.round(fx);
    const y = Math.round(fy);
    if ((x === a.x && y === a.y) || (x === b.x && y === b.y)) continue;
    const k = key(x, y);
    if (seen.has(k)) continue;
    seen.add(k);
    const t = tileAt(map, x, y);
    if (!t) continue;
    tiles.push({ x, y });
    const lineH = ha + (hb - ha) * f;
    if (t.h > lineH) return { blocked: true, partial, tiles };
    if (t.prop) {
      const p = PROPS[t.prop];
      if (p.los === 2) return { blocked: true, partial, tiles };
      if (p.los === 1) partial++;
    }
    foliage += TERRAIN[t.terrain].losBlock;
    if (foliage >= 1) return { blocked: true, partial, tiles };
    if (TERRAIN[t.terrain].losBlock > 0) partial++;
  }
  return { blocked: false, partial, tiles };
}
