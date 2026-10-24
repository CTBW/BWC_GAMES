// Shared type definitions. Content lives in src/data and is described by
// these shapes; systems read the tables rather than hard-coding content.

export type Faction = 'player' | 'enemy';

/** Grid facing. 0:+x (screen SE), 1:+y (screen SW), 2:-x (NW), 3:-y (NE). */
export type Dir = 0 | 1 | 2 | 3;

export interface Stats {
  hp: number;
  morale: number;
  melee: number;
  ranged: number;
  defense: number;
  rangedDefense: number;
  armor: number;
  move: number;
}

export type Range = [number, number];

export type AbilityId = string;
export type UnitTypeId = string;

export interface UnitTypeDef {
  id: UnitTypeId;
  name: string;
  plural: string;
  faction: Faction;
  role: string;
  blurb: string;
  base: Stats;
  perLevel: Partial<Stats>;
  melee: Range;
  /** Optional ranged weapon. */
  shot?: { damage: Range; range: number; minRange?: number; pierce: number; ammo?: number };
  /** Fraction of armour ignored by melee hits. */
  meleePierce?: number;
  /** Extra defense against attacks into the front arc (shields). */
  shieldFront?: number;
  /** Innate abilities. */
  abilities: AbilityId[];
  /** Ability unlocked by promotion (player units). */
  promotion?: AbilityId;
  commandCost: number;
  recruitCost: number;
  weaponLine?: string;
  armorLine?: string;
  sprite: string;
  /** Visual height class used for sprite scaling. */
  size: 'small' | 'medium' | 'large';
  /**
   * Soldiers in one squad. Every squad has DEFAULT_SQUAD_SIZE soldiers unless
   * a type overrides it here. Stats in `base` are per soldier.
   */
  squad?: number;
  /** Rank-and-file figure for a squad whose first soldier is a champion (the warlord's guard). */
  escort?: string;
  /**
   * A war machine: one engine (drawn with this type's own sprite) worked by a
   * crew of `squad` soldiers drawn as this figure. The crew is the squad: its
   * HP pool, its casualties and its strength.
   */
  crew?: string;
  /** The ability used when the squad simply attacks an enemy (a mangonel's stone). */
  primary?: AbilityId;
  ai?: AiProfile;
  /** Enemy loot and xp value. */
  value?: number;
  leader?: boolean;
  tags?: string[];
}

export interface AiProfile {
  aggression: number; // 0..1 eagerness to close in
  caution: number; // 0..1 weight on danger at a tile
  preferRange?: number; // ranged units keep this distance
  swarm?: number; // bonus for tiles adjacent to allies
  carelessness?: number; // chance to ignore spearwalls / overwatch
  /**
   * How the unit fights in the horde: swarms pile into gaps and flanks,
   * flankers hunt missile troops and exposed sides, shock troops break the
   * front, heralds keep out of reach.
   */
  role?: 'swarm' | 'flanker' | 'shock' | 'line' | 'missile' | 'herald' | 'leader' | 'caster' | 'artillery';
}

/**
 * `spell`: a targeted power cast at a tile (spells and war-machine shots).
 * Its effects are rolled once by the rules, however many casters it takes.
 */
export type AbilityKind = 'stance' | 'attack' | 'shout' | 'spell';

/** Lasting conditions on a squad. */
export type StatusId = 'chilled' | 'bloodlust' | 'bleeding';

/** How a spell looks when cast (the renderer picks its effects by this). */
export type SpellFx = 'lightning' | 'frost' | 'heal' | 'circle' | 'fire' | 'blood' | 'gut' | 'stone' | 'rock';

export interface AbilityDef {
  id: AbilityId;
  name: string;
  kind: AbilityKind;
  description: string;
  icon: string;
  /** For attacks: reach in tiles along a straight line, default 1 (melee). */
  reach?: number;
  ranged?: boolean;
  damageMult?: number;
  hitMod?: number;
  ammoCost?: number;
  ignoreArmor?: boolean;
  push?: boolean;
  moraleDamage?: number;
  /** For shouts. */
  radius?: number;
  moraleGain?: number;
  /** Stance id applied until the unit's next turn. */
  stance?: StanceId;
  cooldown?: number;
  requiresNoMove?: boolean;

  // Spells (kind 'spell'). Amounts are per caster and scale with the casters standing.
  /** What it is cast at: a foe, a friendly squad, any tile, or the caster's own ground. */
  target?: 'enemy' | 'ally' | 'tile' | 'self';
  range?: number;
  minRange?: number;
  /** Needs a clear line of sight to the target (lobbed stones do not). */
  sight?: boolean;
  /** Damage per caster. */
  power?: [number, number];
  /** Healing per caster (the dead are never raised). */
  heal?: [number, number];
  /** Fraction of armour ignored (1 = all; `ignoreArmor` also means all). */
  pierce?: number;
  /** Fraction of the damage dealt to every squad on a tile next to the one struck. */
  splash?: number;
  /** The splash strikes friend and foe alike. */
  friendly?: boolean;
  /** Arcs on from the squad struck to the nearest other foes. */
  chain?: { jumps: number; reach: number; falloff: number };
  /** Every friendly squad within this many tiles of the caster (Mending Circle). */
  aura?: number;
  status?: { id: StatusId; turns: number };
  /** Bleeding: this fraction of the damage again at the start of each of the victim's next two turns. */
  bleed?: number;
  /** A miss lands a tile astray instead of fizzling (lobbed stones, fireballs). */
  scatter?: boolean;
  /** A war machine's shot: it cannot loose in a turn the machine has moved. */
  engine?: boolean;
  /** Accuracy bonus or penalty on top of the caster's skill. */
  hitBonus?: number;
  fx?: SpellFx;
}

export type StanceId = 'shieldwall' | 'spearwall' | 'overwatch';

export interface TerrainDef {
  id: string;
  name: string;
  moveCost: number;
  passable: boolean;
  /** Penalty applied to ranged hit chance against a unit standing here. */
  rangedCover: number;
  defenseMod: number;
  /** LOS passing through this terrain accumulates this much obstruction (>=1 blocks). */
  losBlock: number;
  water?: boolean;
  color: string;
}

export interface PropDef {
  id: string;
  name: string;
  blocksMove: boolean;
  /** 0 none, 1 partial obstruction, 2 blocks line of sight. */
  los: 0 | 1 | 2;
  /** Cover granted to an adjacent unit against ranged attacks crossing this prop. */
  cover: number;
  /** Defense for a squad standing on this (passable) prop: a gateway. */
  defense?: number;
  sprite: string;
  /** Destroyable or decorative only. */
  decor?: boolean;
}

export interface EquipTier {
  tier: number;
  name: string;
  cost: { silver: number; iron?: number; timber?: number };
  armoryLevel: number;
  bonus: Partial<Stats> & { damage?: number };
}

export interface EquipLine {
  id: string;
  slot: 'weapon' | 'armor';
  tiers: EquipTier[];
}

export type ResourceId = 'silver' | 'timber' | 'iron' | 'trophies';
export type Resources = Record<ResourceId, number>;

export type SupplyId = 'rations' | 'bandages' | 'bolts' | 'torches' | 'tools';

export interface SupplyDef {
  id: SupplyId;
  name: string;
  cost: number;
  weight: number;
  description: string;
  icon: string;
}

export interface InjuryDef {
  id: string;
  name: string;
  description: string;
  effect: Partial<Stats>;
  severity: 1 | 2 | 3;
}

export interface BuildingLevel {
  level: number;
  name: string;
  cost: Partial<Resources>;
  description: string;
  effects: Record<string, number>;
}

export interface BuildingDef {
  id: string;
  name: string;
  role: string;
  levels: BuildingLevel[];
  sprite: string;
  /** Position on the base grid. */
  pos: [number, number];
}
