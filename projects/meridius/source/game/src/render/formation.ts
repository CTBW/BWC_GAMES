// Squad formations on the battle grid. A squad is one gameplay unit standing on
// one tile (its anchor); each visible soldier keeps a local offset from that
// anchor. Offsets are in world pixels on the ground plane as seen on screen
// (+x right, +y toward the camera), so the rows read as orderly ranks from the
// bottom-left camera. Every slot keeps the feet well inside the tile diamond
// (|x|/64 + |y|/32 < 0.92 for a 128×64 tile).

import type { Dir } from '../core/types';

export interface Slot {
  x: number;
  y: number;
}

/** Column spacing, half the gap between ranks, and the sideways lean toward the facing. */
const COL = 30;
const ROW = 11;
const LEAN = 4;

/** Wider spacing for big creatures (trolls), fewer of them per tile. */
const BIG_COL = 27;
const BIG_ROW = 10;

/** Riders on wolves need room: two abreast, two deep. */
const MOUNT_COL = 46;
const MOUNT_ROW = 12;

/** Goblin rabble packs three ranks of three into a tile. */
const SWARM_COL = 25;
const SWARM_ROW = 11;

/** Facings 0 and 1 face the camera (front rank is the lower one on screen). */
export function facesCamera(f: Dir): boolean {
  return f === 0 || f === 1;
}

/** Screen-horizontal sign of the facing: 1 and 2 look left, 0 and 3 look right. */
function sideSign(f: Dir): number {
  return f === 1 || f === 2 ? -1 : 1;
}

/**
 * Slots for `n` standing soldiers of a squad whose full strength is `size`,
 * front rank first. Six stand in two ranks of three; casualties close up the
 * ranks so the block stays centred on the anchor. Three-strong squads (trolls)
 * stand in a triangle with one behind.
 */
export function formationSlots(n: number, size: number, facing: Dir, tight = 1, typeId?: string): Slot[] {
  const fs = facesCamera(facing) ? 1 : -1; // +y is the front rank
  const ls = sideSign(facing);
  if (typeId === 'wolf_rider') {
    const col = MOUNT_COL * tight;
    const row = MOUNT_ROW * tight;
    const lean = LEAN * tight;
    const half = col / 2;
    if (n <= 0) return [];
    if (n === 1) return [{ x: 0, y: 0 }];
    if (n === 2) return [{ x: -half + ls * lean * 0.5, y: fs * 2 }, { x: half + ls * lean * 0.5, y: fs * 2 }];
    const front = [{ x: -half + ls * lean, y: fs * row }, { x: half + ls * lean, y: fs * row }];
    if (n === 3) return [...front, { x: -ls * lean, y: -fs * row }];
    return [...front, { x: -half - ls * lean, y: -fs * row }, { x: half - ls * lean, y: -fs * row }];
  }
  if (size >= 7 && n >= 7) {
    // Three ranks: three in front, three in the middle, the rest behind.
    const col = SWARM_COL * tight;
    const row = SWARM_ROW * tight;
    const lean = LEAN * tight;
    const rank = (xs: number[], r: number): Slot[] => xs.map((x) => ({ x: x + ls * lean * r, y: fs * row * r }));
    const rest = n - 6;
    const back = rest === 3 ? [-col, 0, col] : rest === 2 ? [-col / 2, col / 2] : [0];
    return [...rank([-col, 0, col], 1), ...rank([-col, 0, col], 0), ...rank(back, -1)];
  }
  const big = size <= 3;
  const col = (big ? BIG_COL : COL) * tight;
  const row = (big ? BIG_ROW : ROW) * tight;
  const lean = LEAN * tight;
  const front = (xs: number[]): Slot[] => xs.map((x) => ({ x: x + ls * lean, y: fs * row }));
  const back = (xs: number[]): Slot[] => xs.map((x) => ({ x: x - ls * lean, y: -fs * row }));
  const half = col / 2;
  if (n <= 0) return [];
  if (n === 1) return [{ x: 0, y: 0 }];
  if (n === 2) {
    // Shoulder to shoulder, nudged toward the facing so the pair still reads as a rank.
    return [
      { x: -half * (big ? 1.7 : 1.15) + ls * lean * 0.5, y: fs * 2 },
      { x: half * (big ? 1.7 : 1.15) + ls * lean * 0.5, y: fs * 2 },
    ];
  }
  if (big) {
    // Triangle: two in front, one behind and between them.
    if (n === 3) return [...front([-col, col]), { x: -ls * lean, y: -fs * row * 1.3 }];
  }
  if (n === 3) return [...front([-half, half]), ...back([0])];
  if (n === 4) return [...front([-half, half]), ...back([-half, half])];
  if (n === 5) return [...front([-col, 0, col]), ...back([-half, half])];
  // Six (and anything larger is clamped to two ranks of three).
  return [...front([-col, 0, col]), ...back([-col, 0, col])];
}

/**
 * Give each soldier a slot so the whole squad moves as little as possible
 * when the formation changes (turning, closing ranks after a casualty).
 * `pinned` soldiers (a champion) take the front-centre slot.
 */
export function assignSlots(positions: Slot[], slots: Slot[], pinned = -1): number[] {
  const n = positions.length;
  const out = new Array<number>(n).fill(-1);
  if (!n) return out;
  const free = slots.map((_, i) => i);
  if (pinned >= 0 && pinned < n) {
    // Front-centre: slots come front rank first, so pick the most central of those.
    const frontCount = slots.length >= 5 ? 3 : slots.length >= 2 ? 2 : 1;
    let best = 0;
    for (let i = 1; i < frontCount; i++) if (Math.abs(slots[i].x) < Math.abs(slots[best].x)) best = i;
    out[pinned] = best;
    free.splice(free.indexOf(best), 1);
  }
  const who = positions.map((_, i) => i).filter((i) => out[i] < 0);
  // Exhaustive search is tiny (at most 6! = 720 orders); fall back to greedy beyond that.
  if (who.length <= 6) {
    let bestCost = Infinity;
    let bestPerm: number[] = [];
    const perm: number[] = [];
    const used = new Set<number>();
    const rec = (k: number, cost: number) => {
      if (cost >= bestCost) return;
      if (k === who.length) {
        bestCost = cost;
        bestPerm = perm.slice();
        return;
      }
      for (const si of free) {
        if (used.has(si)) continue;
        const p = positions[who[k]];
        const s = slots[si];
        const d = (p.x - s.x) ** 2 + (p.y - s.y) ** 2;
        used.add(si);
        perm.push(si);
        rec(k + 1, cost + d);
        perm.pop();
        used.delete(si);
      }
    };
    rec(0, 0);
    who.forEach((w, k) => (out[w] = bestPerm[k]));
    return out;
  }
  for (const w of who) {
    let best = free[0];
    let bestD = Infinity;
    for (const si of free) {
      const d = (positions[w].x - slots[si].x) ** 2 + (positions[w].y - slots[si].y) ** 2;
      if (d < bestD) {
        bestD = d;
        best = si;
      }
    }
    out[w] = best;
    free.splice(free.indexOf(best), 1);
  }
  return out;
}

/**
 * Which soldiers fall to a blow: the `k` standing nearest the attacker (by
 * their offsets plus the direction of the attack). A protected soldier (the
 * warlord among his guard) falls only when nobody else is left.
 */
export function pickCasualties(positions: Slot[], standing: number[], k: number, from: { x: number; y: number }, protectedIdx = -1): number[] {
  const len = Math.hypot(from.x, from.y) || 1;
  const dx = from.x / len;
  const dy = from.y / len;
  const order = standing.slice().sort((a, b) => {
    const pa = a === protectedIdx ? -1e6 : positions[a].x * dx + positions[a].y * dy * 2;
    const pb = b === protectedIdx ? -1e6 : positions[b].x * dx + positions[b].y * dy * 2;
    return pb - pa;
  });
  return order.slice(0, Math.max(0, Math.min(k, standing.length)));
}
