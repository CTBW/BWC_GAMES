// Squad bookkeeping shared by the battle rules, the roster and the renderer.
// A squad has one HP pool. Soldiers fall as that pool crosses each soldier's
// share (`hpPer`); healing refills the survivors but never raises the dead.

import type { StatusId } from '../core/types';
import { UNIT_TYPES } from '../data/units';
import type { Status } from './types';

export interface SquadHealth {
  hp: number;
  hpPer: number;
  alive: number;
}

/** Soldiers still standing with `hp` left, never more than `cap` (the dead stay dead). */
export function aliveFor(hp: number, hpPer: number, cap: number): number {
  if (hp <= 0) return 0;
  return Math.max(0, Math.min(cap, Math.ceil(hp / hpPer - 1e-9)));
}

/** Most HP the squad can hold: one full share per surviving soldier. */
export function hpCap(s: SquadHealth): number {
  return s.alive * s.hpPer;
}

/** Take damage from the shared pool. Returns the soldiers lost (several if the blow crosses several shares). */
export function damageSquad(s: SquadHealth, damage: number): number {
  const before = s.alive;
  s.hp = Math.max(0, s.hp - damage);
  s.alive = aliveFor(s.hp, s.hpPer, s.alive);
  return before - s.alive;
}

/** Heal the survivors, capped at their shares. Returns the HP actually restored. */
export function healSquad(s: SquadHealth, amount: number): number {
  const before = s.hp;
  s.hp = Math.min(hpCap(s), s.hp + Math.max(0, amount));
  return s.hp - before;
}

/** Soldiers a hit of `damage` would kill. */
export function killsFrom(s: SquadHealth, damage: number): number {
  return s.alive - aliveFor(s.hp - damage, s.hpPer, s.alive);
}

/** "soldier" or "soldiers" in the unit's own words: "goblin spearman", "moss trolls", "crewman" of a war machine. */
export function memberNoun(typeId: string, n: number): string {
  const def = UNIT_TYPES[typeId];
  if (!def) return n === 1 ? 'soldier' : 'soldiers';
  if (def.crew) return n === 1 ? 'crewman' : 'crewmen';
  return (n === 1 ? def.name : def.plural).toLowerCase();
}

/** How the battle log names a squad: "Aldric's footmen", "Grukk's goblin spearmen", "Warlord Uzgash", "Hild's ballista crew". */
export function squadName(u: { name: string; typeId: string; leader?: boolean }): string {
  if (u.leader) return u.name.split(',')[0];
  const first = u.name.split(/[ ,]/)[0];
  const def = UNIT_TYPES[u.typeId];
  if (def?.crew) return `${first}'s ${def.name.toLowerCase()} crew`;
  return `${first}'s ${memberNoun(u.typeId, 2)}`;
}

// ---------------------------------------------------------------- conditions

export function statusOf(u: { statuses?: Status[] }, id: StatusId): Status | undefined {
  return u.statuses?.find((s) => s.id === id);
}

export function hasStatus(u: { statuses?: Status[] }, id: StatusId): boolean {
  return !!statusOf(u, id);
}

/** Squads that fight from the back: missile troops, casters and war machines that lob stones. */
export function isBackline(u: { shot?: unknown; tags: string[] }): boolean {
  return !!u.shot || u.tags.includes('artillery') || u.tags.includes('caster');
}

/** Tiles the squad can march this turn: a chilled squad drags itself half as far. */
export function moveOf(u: { stats: { move: number }; statuses?: Status[] }): number {
  return hasStatus(u, 'chilled') ? Math.max(1, Math.ceil(u.stats.move / 2)) : u.stats.move;
}
