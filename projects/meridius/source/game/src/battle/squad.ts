// Squad bookkeeping shared by the battle rules, the roster and the renderer.
// A squad has one HP pool. Soldiers fall as that pool crosses each soldier's
// share (`hpPer`); healing refills the survivors but never raises the dead.

import { UNIT_TYPES } from '../data/units';

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

/** "soldier" or "soldiers" in the unit's own words: "goblin spearman", "moss trolls". */
export function memberNoun(typeId: string, n: number): string {
  const def = UNIT_TYPES[typeId];
  if (!def) return n === 1 ? 'soldier' : 'soldiers';
  return (n === 1 ? def.name : def.plural).toLowerCase();
}

/** How the battle log names a squad: "Aldric's footmen", "Grukk's goblin spearmen", "Warlord Uzgash". */
export function squadName(u: { name: string; typeId: string; leader?: boolean }): string {
  if (u.leader) return u.name.split(',')[0];
  const first = u.name.split(/[ ,]/)[0];
  return `${first}'s ${memberNoun(u.typeId, 2)}`;
}
