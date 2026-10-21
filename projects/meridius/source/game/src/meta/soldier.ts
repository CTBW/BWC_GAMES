import type { Rng } from '../core/rng';
import type { Range, Stats } from '../core/types';
import { EQUIPMENT, INJURIES } from '../data/items';
import { FIRST_NAMES, GOBLIN_NAMES, ORC_NAMES, SURNAMES, WARLORD_NAMES } from '../data/names';
import { LEVEL_COMMAND_SURCHARGE, MAX_LEVEL, PROMOTION_LEVEL, RANKS, UNIT_TYPES, XP_LEVELS, squadSize } from '../data/units';
import { aliveFor } from '../battle/squad';
import type { BattleUnit } from '../battle/types';

/**
 * A squad in the company roster, known by its sergeant's name. Persists between
 * expeditions. `hp` is the squad's shared pool; `men` are the soldiers still
 * serving. Healing refills their shares but never brings the dead back; only
 * reinforcements raise `men`.
 */
export interface Soldier {
  id: string;
  name: string;
  typeId: string;
  level: number;
  xp: number;
  hp: number;
  /** Soldiers still in the squad (full strength is squadSize(typeId)). */
  men: number;
  morale: number;
  fatigue: number;
  injuries: string[];
  weaponTier: number;
  armorTier: number;
  /** 0..1 multiplier on armour value. */
  armorCondition: number;
  promoted: boolean;
  /** Bolts in the quiver (crossbowmen). */
  ammo: number;
  portrait: number;
  variant: number;
  kills: number;
  battles: number;
  expeditions: number;
  recruitedOn: number;
  /** Benched for treatment this cycle. */
  recovering?: boolean;
  /** Has already drilled at the training yard this cycle. */
  drilled?: boolean;
  /** Offered by the barracks for free (volunteer). */
  volunteer?: boolean;
}

export function rankName(level: number): string {
  return RANKS[Math.max(0, Math.min(RANKS.length - 1, level - 1))];
}

export function levelForXp(xp: number): number {
  let lvl = 1;
  for (let i = 0; i < XP_LEVELS.length; i++) if (xp >= XP_LEVELS[i]) lvl = i + 1;
  return Math.min(MAX_LEVEL, lvl);
}

export function xpToNext(s: Soldier): { have: number; need: number } | null {
  if (s.level >= MAX_LEVEL) return null;
  const base = XP_LEVELS[s.level - 1];
  return { have: s.xp - base, need: XP_LEVELS[s.level] - base };
}

export function canPromote(s: Soldier): boolean {
  return !s.promoted && s.level >= PROMOTION_LEVEL && !!UNIT_TYPES[s.typeId].promotion;
}

function addStats(a: Stats, b: Partial<Stats>, mult = 1): Stats {
  const out = { ...a };
  for (const k of Object.keys(b) as (keyof Stats)[]) out[k] += (b[k] ?? 0) * mult;
  return out;
}

/** Full-health stats including level, equipment and lasting injuries. */
export function soldierStats(s: Soldier): Stats {
  const def = UNIT_TYPES[s.typeId];
  let st = addStats(def.base, def.perLevel, s.level - 1);
  const weapon = def.weaponLine ? EQUIPMENT[def.weaponLine].tiers[s.weaponTier - 1] : undefined;
  const armor = def.armorLine ? EQUIPMENT[def.armorLine].tiers[s.armorTier - 1] : undefined;
  if (weapon) st = addStats(st, weapon.bonus);
  if (armor) st = addStats(st, armor.bonus);
  for (const id of s.injuries) st = addStats(st, INJURIES[id].effect);
  st.move = Math.max(2, st.move);
  st.hp = Math.max(8, st.hp);
  st.morale = Math.max(20, st.morale);
  return st;
}

export function weaponBonus(s: Soldier): number {
  const def = UNIT_TYPES[s.typeId];
  const weapon = def.weaponLine ? EQUIPMENT[def.weaponLine].tiers[s.weaponTier - 1] : undefined;
  return weapon?.bonus.damage ?? 0;
}

export function soldierDamage(s: Soldier): { melee: Range; shot?: Range } {
  const def = UNIT_TYPES[s.typeId];
  const wb = weaponBonus(s);
  if (def.shot) {
    return { melee: def.melee, shot: [def.shot.damage[0] + wb, def.shot.damage[1] + wb] };
  }
  return { melee: [def.melee[0] + wb, def.melee[1] + wb] };
}

export function commandCost(s: Soldier): number {
  return UNIT_TYPES[s.typeId].commandCost + LEVEL_COMMAND_SURCHARGE[s.level];
}

export function abilitiesOf(s: Soldier): string[] {
  const def = UNIT_TYPES[s.typeId];
  return s.promoted && def.promotion ? [...def.abilities, def.promotion] : [...def.abilities];
}

export function fatigueLabel(f: number): string {
  if (f >= 85) return 'Exhausted';
  if (f >= 60) return 'Tired';
  if (f >= 30) return 'Weary';
  return 'Fresh';
}

export function newSoldier(rng: Rng, typeId: string, level: number, nextId: () => string, cycle: number): Soldier {
  const def = UNIT_TYPES[typeId];
  const s: Soldier = {
    id: nextId(),
    name: `${rng.pick(FIRST_NAMES)} ${rng.pick(SURNAMES)}`,
    typeId,
    level,
    xp: XP_LEVELS[level - 1],
    hp: 0,
    men: squadSize(typeId),
    morale: 0,
    fatigue: 0,
    injuries: [],
    weaponTier: 1,
    armorTier: 1,
    armorCondition: 1,
    promoted: false,
    ammo: def.shot?.ammo ?? 0,
    portrait: rng.int(0, 5),
    variant: rng.int(0, 2),
    kills: 0,
    battles: 0,
    expeditions: 0,
    recruitedOn: cycle,
  };
  const st = soldierStats(s);
  s.men = squadSize(typeId);
  s.hp = st.hp * s.men;
  s.morale = st.morale;
  return s;
}

/** Full-strength HP of the squad (every soldier present and unhurt). */
export function squadMaxHp(s: Soldier): number {
  return soldierStats(s).hp * squadSize(s.typeId);
}

/** Most HP the squad can heal to: one full share per soldier still serving. */
export function squadHpCap(s: Soldier): number {
  return soldierStats(s).hp * s.men;
}

/** Heal a squad's survivors (never raises the dead). Returns HP restored. */
export function healSoldier(s: Soldier, amount: number): number {
  const before = s.hp;
  s.hp = Math.max(s.hp, Math.min(squadHpCap(s), s.hp + Math.round(amount)));
  return s.hp - before;
}

/** Keep `men` consistent with the HP pool after damage outside battle. */
export function settleMen(s: Soldier) {
  s.men = Math.max(1, aliveFor(s.hp, soldierStats(s).hp, s.men));
  s.hp = Math.max(1, Math.min(s.hp, squadHpCap(s)));
}

/** Battle-ready copy of a soldier, including fatigue penalties. */
export function soldierToUnit(s: Soldier): BattleUnit {
  const def = UNIT_TYPES[s.typeId];
  const st = soldierStats(s);
  const dmg = soldierDamage(s);
  const eff = { ...st, armor: st.armor * s.armorCondition };
  if (s.fatigue >= 60) {
    eff.melee -= 5;
    eff.ranged -= 5;
  }
  if (s.fatigue >= 85) {
    eff.melee -= 5;
    eff.ranged -= 5;
    eff.move = Math.max(2, eff.move - 1);
  }
  // The squad marches out with the soldiers its HP can carry.
  const size = squadSize(s.typeId);
  const men = Math.max(1, Math.min(size, s.men ?? size));
  const hp = Math.max(1, Math.min(s.hp, st.hp * men));
  return {
    uid: `p-${s.id}`,
    soldierId: s.id,
    typeId: s.typeId,
    faction: 'player',
    name: s.name,
    level: s.level,
    x: 0,
    y: 0,
    facing: 3,
    hp,
    maxHp: st.hp * size,
    size,
    alive: aliveFor(hp, st.hp, men),
    hpPer: st.hp,
    morale: Math.max(1, Math.min(s.morale, st.morale)),
    maxMorale: st.morale,
    stats: eff,
    melee: dmg.melee,
    meleePierce: def.meleePierce ?? 0,
    shot: def.shot && dmg.shot ? { damage: dmg.shot, range: def.shot.range, minRange: def.shot.minRange ?? 2, pierce: def.shot.pierce } : undefined,
    ammo: def.shot ? s.ammo : -1,
    shieldFront: def.shieldFront ?? 0,
    abilities: abilitiesOf(s),
    cooldowns: {},
    hasMoved: false,
    hasActed: false,
    movedTiles: 0,
    done: false,
    status: 'active',
    kills: 0,
    damageDealt: 0,
    xp: 0,
    leader: false,
    tags: [...(def.tags ?? [])],
    variant: s.variant,
    struck: [],
    startMorale: s.morale,
  };
}

export function makeEnemy(typeId: string, level: number, uid: string, rng: Rng): BattleUnit {
  const def = UNIT_TYPES[typeId];
  const st = addStats(def.base, def.perLevel, level - 1);
  const name = def.leader
    ? rng.pick(WARLORD_NAMES)
    : `${typeId.startsWith('orc') ? rng.pick(ORC_NAMES) : rng.pick(GOBLIN_NAMES)}`;
  const size = squadSize(typeId);
  return {
    uid,
    typeId,
    faction: 'enemy',
    name: def.leader ? name : `${name}, ${def.name.toLowerCase()}`,
    level,
    x: 0,
    y: 0,
    facing: 1,
    hp: st.hp * size,
    maxHp: st.hp * size,
    size,
    alive: size,
    hpPer: st.hp,
    morale: st.morale,
    maxMorale: st.morale,
    stats: st,
    melee: def.melee,
    meleePierce: def.meleePierce ?? 0,
    shot: def.shot ? { damage: def.shot.damage, range: def.shot.range, minRange: def.shot.minRange ?? 2, pierce: def.shot.pierce } : undefined,
    ammo: -1,
    shieldFront: def.shieldFront ?? 0,
    abilities: [...def.abilities],
    cooldowns: {},
    hasMoved: false,
    hasActed: false,
    movedTiles: 0,
    done: false,
    status: 'active',
    kills: 0,
    damageDealt: 0,
    xp: 0,
    leader: !!def.leader,
    tags: [...(def.tags ?? [])],
    variant: rng.int(0, 2),
    struck: [],
    startMorale: st.morale,
  };
}
