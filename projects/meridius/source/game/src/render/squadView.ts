// The visible soldiers of a squad. Gameplay knows only the squad (one tile,
// one facing, one HP pool); this module gives each soldier a body: a slot in
// the formation, a personal idle rhythm, an attack lunge, a hit flash and a
// fall. Nothing here feeds back into the rules.

import type { Dir } from '../core/types';
import { hash2 } from '../core/rng';
import { UNIT_TYPES } from '../data/units';
import type { BattleUnit } from '../battle/types';
import { assignSlots, formationSlots, pickCasualties, type Slot } from './formation';
import { easeInOutQuad } from './iso';

export interface Member {
  /** Stable index within the squad (0 is the champion of a guard squad). */
  id: number;
  alive: boolean;
  /** Falling: 0 → 1; at 1 the body is handed over to the field as a corpse. */
  deathT: number;
  dying: boolean;
  /** Seconds to wait before starting to fall (casualties of one volley drop one by one). */
  deathDelay: number;
  /** Current offset from the squad anchor, in world pixels. */
  x: number;
  y: number;
  /** Formation tween: from → to over `dur`, after `delay`. */
  fromX: number;
  fromY: number;
  toX: number;
  toY: number;
  t: number;
  dur: number;
  delay: number;
  /** Attack offset (lunge toward the enemy, recoil, dodge). */
  lunge: Slot;
  flash: number;
  shake: number;
  pose: 'idle' | 'atk';
  /** Personal rhythm so the ranks breathe and march out of lockstep. */
  phase: number;
  /** Figure drawn for this soldier and its look. */
  type: string;
  variant: number;
  /** Which way the body falls. */
  fallFlip: boolean;
}

/** Scale of a squad soldier relative to the full-size figure sprites. */
export const MEMBER_SCALE = 0.52;
export const BIG_MEMBER_SCALE = 0.44;

/** Standing height of a soldier on screen (world px), for bars and labels. */
export function memberHeight(typeId: string): number {
  const def = UNIT_TYPES[typeId];
  if (def?.crew) return def.crew === 'goblin_rabble' ? 40 : 48;
  if (typeId === 'battle_mage') return 54;
  if (typeId === 'goblin_shaman') return 44;
  if (typeId === 'troll') return 66;
  if (typeId === 'wolf_rider') return 58;
  if (typeId === 'goblin_rabble') return 34;
  if (def?.size === 'large') return 62;
  if (def?.size === 'small') return 40;
  if (typeId.startsWith('orc')) return 54;
  return 49;
}

export function memberScale(u: BattleUnit): number {
  if (u.typeId === 'wolf_rider') return 0.5;
  if (u.typeId === 'goblin_rabble') return 0.48;
  const def = UNIT_TYPES[u.typeId];
  // War machines and their crews: goblin crews as small as the rabble they come from.
  if (def?.crew) return def.crew === 'goblin_rabble' ? 0.48 : MEMBER_SCALE;
  // Only the great beasts stand three to a tile at the smaller scale; three mages are men like any other.
  return u.size <= 3 && def?.size === 'large' ? BIG_MEMBER_SCALE : MEMBER_SCALE;
}

/** Index of the soldier who must fall last (the warlord among his guard), or -1. */
export function championOf(u: BattleUnit): number {
  return UNIT_TYPES[u.typeId]?.escort ? 0 : -1;
}

export function makeMembers(u: BattleUnit): Member[] {
  const def = UNIT_TYPES[u.typeId];
  const slots = formationSlots(u.alive, u.size, u.facing, 1, u.typeId);
  const members: Member[] = [];
  const seed = hash2(u.uid.length * 13, u.uid.charCodeAt(u.uid.length - 1));
  for (let i = 0; i < u.size; i++) {
    const alive = i < u.alive;
    const s = alive ? slots[i] : { x: 0, y: 0 };
    // A guard squad's rank and file, or a war machine's crew.
    const escort = def?.escort && i > 0 ? def.escort : def?.crew;
    members.push({
      id: i,
      alive,
      deathT: 0,
      dying: false,
      deathDelay: 0,
      x: s.x,
      y: s.y,
      fromX: s.x,
      fromY: s.y,
      toX: s.x,
      toY: s.y,
      t: 1,
      dur: 0,
      delay: 0,
      lunge: { x: 0, y: 0 },
      flash: 0,
      shake: 0,
      pose: 'idle',
      phase: hash2(i * 7 + 1, Math.floor(seed * 1000)) * Math.PI * 2,
      type: escort ?? u.typeId,
      // Each soldier gets his own face; the champion keeps the squad's look.
      variant: escort || i > 0 ? (u.variant * 5 + i * 7 + Math.floor(seed * 6)) % 6 : u.variant,
      fallFlip: hash2(i, Math.floor(seed * 97)) > 0.5,
    });
  }
  // A champion stands front and centre from the start.
  const champ = championOf(u);
  if (champ >= 0) reform(members, u.size, u.facing, { instant: true, champion: champ, typeId: u.typeId });
  return members;
}

export function standing(members: Member[]): Member[] {
  return members.filter((m) => m.alive);
}

/**
 * Move the standing soldiers to the formation for their number and facing,
 * each to the nearest free slot. `stagger` makes the soldiers set off one
 * after another instead of all at once.
 */
export function reform(
  members: Member[],
  size: number,
  facing: Dir,
  opts: { dur?: number; delay?: number; stagger?: number; tight?: number; instant?: boolean; champion?: number; spread?: number; typeId?: string } = {},
) {
  const live = standing(members);
  if (!live.length) return;
  const slots = formationSlots(live.length, size, facing, opts.tight ?? 1, opts.typeId);
  const pinned = opts.champion !== undefined && opts.champion >= 0 ? live.findIndex((m) => m.id === opts.champion) : -1;
  const pick = assignSlots(live.map((m) => ({ x: m.toX, y: m.toY })), slots, pinned);
  live.forEach((m, i) => {
    const s = slots[pick[i]];
    let tx = s.x;
    let ty = s.y;
    if (opts.spread) {
      // Loose, ragged order (fleeing): push outward and jitter.
      tx = tx * (1 + opts.spread) + (hash2(m.id, 31) - 0.5) * 10 * opts.spread;
      ty = ty * (1 + opts.spread * 0.6) + (hash2(m.id, 37) - 0.5) * 6 * opts.spread;
    }
    if (Math.abs(tx - m.toX) < 0.01 && Math.abs(ty - m.toY) < 0.01 && !opts.instant) return;
    m.fromX = m.x;
    m.fromY = m.y;
    m.toX = tx;
    m.toY = ty;
    if (opts.instant) {
      m.x = m.fromX = tx;
      m.y = m.fromY = ty;
      m.t = 1;
      m.dur = 0;
      return;
    }
    m.t = 0;
    m.dur = opts.dur ?? 0.4;
    m.delay = (opts.delay ?? 0) + (opts.stagger ?? 0) * i;
  });
}

/**
 * Choose who falls to a blow coming from world direction `from` (relative to
 * the squad) and start their falls, one after another.
 */
export function killMembers(members: Member[], count: number, from: Slot, champion: number, gap = 0.07): Member[] {
  const live = members.filter((m) => m.alive);
  const idx = pickCasualties(
    live.map((m) => ({ x: m.toX, y: m.toY })),
    live.map((_, i) => i),
    count,
    from,
    live.findIndex((m) => m.id === champion),
  );
  const out = idx.map((i) => live[i]);
  out.forEach((m, k) => {
    m.alive = false;
    m.dying = true;
    m.deathT = 0;
    m.deathDelay = k * gap;
    m.flash = 1;
    m.pose = 'idle';
    // Knocked back from the blow before falling.
    const len = Math.hypot(from.x, from.y) || 1;
    m.lunge = { x: (-from.x / len) * 5, y: (-from.y / len) * 3 };
    m.fallFlip = from.x > 0;
  });
  return out;
}

/** Advance tweens, flashes and falls. Calls `onCorpse` when a body comes to rest. */
export function stepMembers(members: Member[], dt: number, onCorpse: (m: Member) => void) {
  for (const m of members) {
    m.flash = Math.max(0, m.flash - dt * 4);
    m.shake = Math.max(0, m.shake - dt * 3);
    if (m.t < 1) {
      if (m.delay > 0) m.delay -= dt;
      else {
        m.t = m.dur > 0 ? Math.min(1, m.t + dt / m.dur) : 1;
        const k = easeInOutQuad(m.t);
        m.x = m.fromX + (m.toX - m.fromX) * k;
        m.y = m.fromY + (m.toY - m.fromY) * k;
      }
    }
    if (m.dying) {
      if (m.deathDelay > 0) m.deathDelay -= dt;
      else {
        m.deathT = Math.min(1, m.deathT + dt / 0.5);
        if (m.deathT >= 1) {
          m.dying = false;
          onCorpse(m);
        }
      }
    }
  }
}

/** True while any soldier is still falling or walking to a new slot. */
export function membersBusy(members: Member[]): boolean {
  return members.some((m) => m.dying || m.t < 1);
}
