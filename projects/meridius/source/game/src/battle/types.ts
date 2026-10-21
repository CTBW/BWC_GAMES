import type { Dir, Faction, Range, StanceId, Stats } from '../core/types';

export interface Pt {
  x: number;
  y: number;
}

export interface BattleTile {
  x: number;
  y: number;
  h: number;
  terrain: string;
  prop?: string;
  /** Visual variant seed for the prop/decals. */
  v: number;
}

/**
 * Map edges in grid terms. On screen: n (y = 0) runs along the upper right,
 * w (x = 0) along the upper left, e (x = max) along the lower right and
 * s (y = max) along the lower left, nearest the camera.
 */
export type Edge = 'n' | 'e' | 's' | 'w';

export interface BattleMap {
  id: string;
  name: string;
  w: number;
  h: number;
  tiles: BattleTile[];
  playerDeploy: Pt[];
  enemyDeploy: Pt[];
  biome: string;
  seed: number;
  /** Width of the decorative forest ring drawn outside the playable area. */
  border: number;
  /** Decorative props outside the playable grid. */
  outer: { x: number; y: number; h: number; prop: string; v: number }[];
  /** Small skirmish fields or the large grounds of a last stand. */
  scale?: 'small' | 'large';
  /** Where reinforcements march in, per edge, best tiles first. */
  entries?: Partial<Record<Edge, Pt[]>>;
  /** Edges with an open approach beyond them, where the horde masses in view. */
  approaches?: Edge[];
  /** Ground the company must hold (last stands). */
  zone?: Pt[];
  zoneName?: string;
  /** A hand-drawn layout used transposed (x <-> y): its edges n/w and e/s swap. */
  transposed?: boolean;
  /** Open ground beyond the approach edges (drawn, not played on). */
  outerGround?: { x: number; y: number; terrain: string }[];
}

/** A squad that has not reached the field yet (a later wave) is `reserve`. */
export type UnitStatus = 'active' | 'routing' | 'dead' | 'downed' | 'fled' | 'reserve';
export type MoraleState = 'confident' | 'steady' | 'shaken' | 'wavering' | 'broken';
export type Arc = 'front' | 'flank' | 'rear';

export interface BattleUnit {
  uid: string;
  soldierId?: string;
  typeId: string;
  faction: Faction;
  name: string;
  level: number;
  x: number;
  y: number;
  facing: Dir;
  /** Shared squad HP: every `hpPer` lost costs a soldier. */
  hp: number;
  /** Full-strength squad HP: `size * hpPer`. */
  maxHp: number;
  /** Soldiers in the squad at full strength (6, or 3 for trolls). */
  size: number;
  /** Soldiers still standing. Only damage lowers it; healing never raises it. */
  alive: number;
  /** HP of one soldier. */
  hpPer: number;
  morale: number;
  maxMorale: number;
  stats: Stats;
  melee: Range;
  meleePierce: number;
  shot?: { damage: Range; range: number; minRange: number; pierce: number };
  /** Remaining ammunition; -1 means unlimited. */
  ammo: number;
  shieldFront: number;
  abilities: string[];
  cooldowns: Record<string, number>;
  stance?: StanceId;
  hasMoved: boolean;
  hasActed: boolean;
  movedTiles: number;
  done: boolean;
  status: UnitStatus;
  kills: number;
  damageDealt: number;
  xp: number;
  leader: boolean;
  tags: string[];
  variant: number;
  /** Units that already took a spearwall/first-strike hit from this unit this turn. */
  struck: string[];
  /** Morale at which the unit started the battle (for reports). */
  startMorale: number;
}

export interface WaveUnit {
  typeId: string;
  level: number;
  /** The warchief of the horde: slay him and the horde breaks. */
  warchief?: boolean;
}

/** Reinforcements: a wave of a last stand, or the band a war horn calls. */
export interface Wave {
  /** Enemy turn on which the wave marches onto the field. */
  turn: number;
  edge: Edge;
  units: WaveUnit[];
  /** Comes only if the horn-bearer sounds the war horn. */
  horn?: boolean;
  /** The last wave (the warchief comes with it). */
  final?: boolean;
  label: string;
}

/** How a battle is won and lost. */
export interface BattleObjective {
  /** rout: destroy or drive off every enemy. survive / hold: stand until the relief comes. */
  kind: 'rout' | 'survive' | 'hold';
  /** survive / hold: the relief arrives at the end of this turn. */
  turns?: number;
  /** Slaying the warchief breaks the horde: every foe flees. */
  warchief?: boolean;
  /** The horn-bearer sounds the horn at the start of this enemy turn if he still lives. */
  hornTurn?: number;
  /** Short title ("Hold Brannsted until dawn") and a briefing line. */
  title: string;
  brief: string;
  /** What arrives when the battle is won by holding ("the relief column"). */
  relief?: string;
  /** Fought through the night: dark at the start, dawn breaking as the relief nears. */
  dawn?: boolean;
}

export type BattleKind = 'skirmish' | 'raid' | 'patrol' | 'ambush' | 'stand';

export interface BattleSetup {
  seed: number;
  map: BattleMap;
  units: BattleUnit[];
  kind?: BattleKind;
  objective?: BattleObjective;
  /** Every wave's squads are in `units` from the start, as reserves off the field. */
  waves?: (Wave & { uids: string[] })[];
  /** Added to a player soldier's chance to survive falling. */
  survivalBonus: number;
  ambush?: boolean;
  /** Enemies take the first turn. */
  enemyFirst?: boolean;
  darkness?: boolean;
  title: string;
  encounterId?: string;
}

export type BattleResult = 'victory' | 'defeat' | 'retreat';

export type BattleEvent =
  | { t: 'move'; uid: string; path: Pt[] }
  | { t: 'face'; uid: string; facing: Dir }
  | {
      t: 'attack';
      uid: string;
      target: string;
      ranged: boolean;
      ability?: string;
      hit: boolean;
      damage: number;
      chance: number;
      arc: Arc;
      reaction?: 'zoc' | 'spearwall' | 'overwatch' | 'firstStrike';
      targetHp: number;
      /** Soldiers of the attacking squad who struck (damage was rolled once for all of them). */
      strikers: number;
      /** Target soldiers standing before and after the blow. */
      aliveBefore: number;
      aliveAfter: number;
    }
  | { t: 'heal'; uid: string; amount: number; hp: number; reason: string }
  | { t: 'push'; uid: string; from: Pt; to: Pt; blocked: boolean; hp: number; alive: number }
  | { t: 'morale'; uid: string; delta: number; value: number; reason: string }
  | { t: 'mstate'; uid: string; from: MoraleState; to: MoraleState }
  | { t: 'down'; uid: string; dead: boolean }
  | { t: 'rout'; uid: string }
  | { t: 'rally'; uid: string }
  | { t: 'fled'; uid: string }
  | { t: 'stance'; uid: string; stance: StanceId | null }
  | { t: 'shout'; uid: string; ability: string }
  | { t: 'halt'; uid: string; by: string }
  | { t: 'turn'; faction: Faction; turn: number }
  /** A wave is sighted (it marches in on enemy turn `turn`). */
  | { t: 'warn'; wave: number; edge: Edge; turn: number; label: string; count: number }
  /** A wave reaches the field; each of its squads then arrives with a `spawn`. */
  | { t: 'wave'; wave: number; edge: Edge; label: string; count: number; final: boolean }
  | { t: 'spawn'; uid: string; from: Pt; to: Pt }
  | { t: 'horn'; uid: string; sounded: boolean }
  | { t: 'overrun'; turnsLeft: number }
  /** The warchief is slain: the horde breaks and runs. */
  | { t: 'broken'; uid: string }
  | { t: 'relief'; text: string }
  | { t: 'end'; result: BattleResult }
  | { t: 'log'; text: string; tone?: 'good' | 'bad' | 'neutral' };

export interface AttackPreview {
  chance: number;
  min: number;
  max: number;
  arc: Arc;
  mods: [string, number][];
  kill: number; // probability the hit destroys the whole squad
  /** Soldiers of the target a hit would kill at minimum and maximum damage. */
  soldiers: [number, number];
  /** Soldiers of the attacking squad who would strike. */
  strikers: number;
  moraleHit: number;
  legal: boolean;
  reason?: string;
}
