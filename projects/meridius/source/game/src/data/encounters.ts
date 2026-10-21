// Enemy groups by campaign tier. `depth` is the campaign stage (0 = first march).
// Every fight is against more squads than the company fields: small battles
// are glimpses of the host (scouts, raiders, its vanguard), and a war horn or
// the main body can bring more; the last stands bring the host itself in waves.

import type { BattleKind, BattleObjective, Edge } from '../battle/types';

/** Edge of a wave: the map's main approach, one of its flanks, or a fixed edge. */
export type WaveEdge = Edge | 'main' | 'flank';

export interface WaveDef {
  turn: number;
  edge: WaveEdge;
  units: [typeId: string, min: number, max: number][];
  label: string;
  horn?: boolean;
  final?: boolean;
  /** The first squad of this type in the wave is the warchief. */
  warchief?: string;
}

export interface EncounterDef {
  id: string;
  name: string;
  tier: number;
  kind: BattleKind;
  /** Squads on the field when the battle begins. */
  units: [typeId: string, min: number, max: number][];
  level: [number, number];
  maps: string[];
  weight: number;
  minDepth?: number;
  maxDepth?: number;
  ambush?: boolean;
  objective?: boolean;
  /** How the battle is won and lost (default: rout the enemy). */
  goal?: BattleObjective;
  waves?: WaveDef[];
  /** Local defenders fighting beside the company (not part of the roster). */
  allies?: [typeId: string, count: number][];
  /** Shown on the campaign map and before the battle. */
  intel?: string;
  /** Loot on victory (on top of per-enemy silver). */
  loot: { silver: [number, number]; iron?: [number, number]; timber?: [number, number]; trophies?: number };
}

const SMALL = ['forest_clearing', 'river_ruins'];

export const ENCOUNTERS: EncounterDef[] = [
  {
    id: 'goblin_scouts',
    name: 'Scouts of the host',
    tier: 1,
    kind: 'patrol',
    units: [['goblin_spear', 2, 3], ['goblin_rabble', 2, 2], ['goblin_archer', 1, 1], ['goblin_horn', 1, 1]],
    level: [1, 1],
    maps: SMALL,
    weight: 3,
    maxDepth: 2,
    goal: {
      kind: 'rout',
      hornTurn: 3,
      title: 'Silence the horn',
      brief: 'A scouting band of the host. Its horn-bearer will call the rest if you give him three turns: cut him down first.',
    },
    waves: [{ turn: 3, edge: 'main', horn: true, units: [['goblin_rabble', 2, 2], ['goblin_spear', 1, 2], ['wolf_rider', 1, 1]], label: 'The horn is answered' }],
    intel: 'A scouting band with a horn-bearer.',
    loot: { silver: [15, 30], iron: [0, 1] },
  },
  {
    id: 'stragglers',
    name: 'Stragglers ahead of the host',
    tier: 1,
    kind: 'skirmish',
    units: [['goblin_rabble', 4, 5], ['goblin_spear', 1, 1], ['goblin_archer', 1, 1]],
    level: [1, 1],
    maps: SMALL,
    weight: 2,
    maxDepth: 1,
    goal: { kind: 'rout', title: 'Break the stragglers', brief: 'A mob of rabble running ahead of the host, burning as it goes. Their outriders are not far behind.' },
    waves: [{ turn: 3, edge: 'flank', units: [['wolf_rider', 1, 1], ['goblin_rabble', 1, 2]], label: 'Outriders of the host' }],
    intel: 'Goblin rabble, many and weak. Outriders close behind.',
    loot: { silver: [15, 30], timber: [0, 1] },
  },
  {
    id: 'raiding_party',
    name: 'Raiders burning the steadings',
    tier: 1,
    kind: 'raid',
    units: [['goblin_spear', 2, 3], ['goblin_rabble', 2, 2], ['goblin_archer', 1, 2], ['wolf_rider', 0, 1]],
    level: [1, 2],
    maps: SMALL,
    weight: 3,
    minDepth: 1,
    goal: { kind: 'rout', title: 'Drive off the raiders', brief: 'Raiders are firing the farms. Their main body is coming back down the road with the loot: finish the first band before it arrives.' },
    waves: [{ turn: 3, edge: 'main', units: [['goblin_spear', 1, 2], ['goblin_rabble', 1, 2], ['goblin_archer', 1, 1]], label: 'The raiders\' main body' }],
    intel: 'Raiders with archers; their main body returns soon after.',
    loot: { silver: [25, 45], iron: [1, 2], timber: [0, 1] },
  },
  {
    id: 'archer_screen',
    name: 'Wolf riders on the road',
    tier: 1,
    kind: 'skirmish',
    units: [['wolf_rider', 2, 2], ['goblin_archer', 2, 2], ['goblin_rabble', 2, 2], ['goblin_spear', 1, 2]],
    level: [1, 2],
    maps: ['forest_clearing'],
    weight: 2,
    minDepth: 1,
    goal: { kind: 'rout', title: 'Hold against the riders', brief: 'Wolf riders and archers. The riders will circle your line for your crossbowmen: keep your flanks closed and your spears set.' },
    waves: [{ turn: 4, edge: 'flank', units: [['goblin_rabble', 2, 2]], label: 'Rabble behind the riders' }],
    intel: 'Fast wolf riders hunting for flanks.',
    loot: { silver: [25, 40], timber: [0, 1] },
  },
  {
    id: 'orc_overseer',
    name: 'Vanguard of the host',
    tier: 1,
    kind: 'skirmish',
    units: [['orc_warrior', 1, 1], ['goblin_spear', 2, 3], ['goblin_rabble', 2, 2], ['goblin_archer', 1, 1]],
    level: [1, 2],
    maps: SMALL,
    weight: 2,
    minDepth: 2,
    goal: { kind: 'rout', title: 'Break the vanguard', brief: 'An orc drives the vanguard of the host before him. Behind it the next band is already on the road.' },
    waves: [{ turn: 3, edge: 'main', units: [['goblin_rabble', 2, 2], ['goblin_spear', 1, 1], ['wolf_rider', 0, 1]], label: 'The next band' }],
    intel: 'Orc-led vanguard; another band follows.',
    loot: { silver: [40, 60], iron: [1, 2], timber: [1, 2] },
  },
  {
    id: 'brute_vanguard',
    name: 'Orc brutes and their goblins',
    tier: 1,
    kind: 'skirmish',
    units: [['orc_brute', 1, 1], ['goblin_spear', 2, 3], ['goblin_rabble', 2, 2], ['goblin_archer', 1, 1]],
    level: [1, 2],
    maps: SMALL,
    weight: 1,
    minDepth: 2,
    goal: { kind: 'rout', title: 'Stop the brutes', brief: 'Brutes smash squads out of the line and push into the gap. Do not let the goblins follow them through.' },
    waves: [{ turn: 3, edge: 'flank', units: [['goblin_rabble', 1, 2], ['wolf_rider', 1, 1]], label: 'More from the flank' }],
    intel: 'Orc brutes that smash lines open.',
    loot: { silver: [40, 60], iron: [1, 2], timber: [0, 1] },
  },
  {
    id: 'moss_trolls',
    name: 'Moss trolls of the deep wood',
    tier: 1,
    kind: 'skirmish',
    units: [['troll', 1, 1], ['goblin_spear', 2, 2], ['goblin_rabble', 2, 2], ['goblin_archer', 1, 1]],
    level: [1, 1],
    maps: SMALL,
    weight: 1,
    minDepth: 3,
    goal: { kind: 'rout', title: 'Fell the trolls', brief: 'The host has woken the trolls of the deep wood. Their wounds close as you watch: concentrate your blows.' },
    waves: [{ turn: 4, edge: 'main', units: [['goblin_rabble', 2, 2]], label: 'The rabble behind them' }],
    intel: 'Moss trolls driven ahead of the host.',
    loot: { silver: [55, 80], iron: [1, 2], timber: [1, 2], trophies: 1 },
  },
  {
    id: 'road_ambush',
    name: 'Ambush on the road',
    tier: 1,
    kind: 'ambush',
    units: [['goblin_spear', 2, 3], ['goblin_rabble', 2, 2], ['goblin_archer', 1, 2], ['wolf_rider', 0, 1]],
    level: [1, 2],
    maps: ['forest_clearing'],
    weight: 1,
    ambush: true,
    goal: { kind: 'rout', title: 'Fight free', brief: 'They were waiting on both sides of the road. Form a ring, then break them.' },
    intel: 'An ambush from both sides of the road.',
    loot: { silver: [20, 35], iron: [0, 1] },
  },
  {
    id: 'refugee_stand',
    name: 'Cover the refugees',
    tier: 1,
    kind: 'stand',
    units: [['goblin_rabble', 2, 2], ['goblin_spear', 2, 2], ['goblin_archer', 1, 2]],
    level: [1, 1],
    maps: ['ford'],
    weight: 0,
    goal: {
      kind: 'hold',
      turns: 6,
      title: 'Hold the ford for six turns',
      brief: 'The people of Ostby are crossing behind you. Keep the horde off the road until the last cart is through.',
      relief: 'The last cart is over the hill',
    },
    waves: [
      { turn: 2, edge: 'main', units: [['goblin_rabble', 1, 2], ['goblin_spear', 1, 1]], label: 'The second band' },
      { turn: 3, edge: 'main', units: [['wolf_rider', 1, 1], ['goblin_archer', 1, 1], ['goblin_rabble', 1, 1]], label: 'Riders and bows' },
      { turn: 4, edge: 'flank', units: [['goblin_rabble', 1, 2], ['goblin_spear', 1, 1]], label: 'They have crossed upstream' },
      { turn: 5, edge: 'main', units: [['orc_warrior', 1, 1], ['goblin_rabble', 1, 2]], label: 'An orc warband' },
    ],
    allies: [['militia', 1]],
    intel: 'Refugees crossing the Vattern. The host is close behind them.',
    loot: { silver: [50, 70], iron: [1, 2], timber: [1, 2] },
  },
  {
    id: 'warband_camp',
    name: 'The vanguard\'s camp',
    tier: 1,
    kind: 'skirmish',
    units: [['orc_warlord', 1, 1], ['orc_warrior', 0, 1], ['goblin_spear', 2, 3], ['goblin_rabble', 1, 2], ['goblin_archer', 1, 2]],
    level: [1, 1],
    maps: ['goblin_camp'],
    weight: 0,
    loot: { silver: [120, 150], iron: [3, 4], timber: [2, 3], trophies: 1 },
  },
  {
    id: 'last_stand',
    name: 'The last stand at Brannsted',
    tier: 1,
    kind: 'stand',
    units: [['goblin_rabble', 2, 2], ['goblin_spear', 2, 2], ['goblin_archer', 2, 2], ['wolf_rider', 1, 1]],
    level: [1, 1],
    maps: ['steading', 'ford'],
    weight: 1,
    objective: true,
    goal: {
      kind: 'hold',
      turns: 7,
      warchief: true,
      title: 'Hold until dawn',
      brief: 'The whole host is coming, by night. Hold the ground until the Margrave\'s riders arrive at dawn, or slay the warchief and break the horde.',
      relief: 'The Margrave\'s riders crest the hill at dawn',
      dawn: true,
    },
    waves: [
      { turn: 2, edge: 'main', units: [['goblin_rabble', 1, 2], ['goblin_spear', 1, 1], ['goblin_archer', 1, 1]], label: 'The second wave' },
      { turn: 3, edge: 'flank', units: [['orc_warrior', 1, 1], ['goblin_rabble', 1, 1], ['wolf_rider', 1, 1]], label: 'An orc warband on the flank' },
      { turn: 4, edge: 'main', units: [['orc_brute', 1, 1], ['goblin_spear', 1, 2], ['goblin_rabble', 1, 2], ['goblin_archer', 1, 1]], label: 'Brutes and the main body' },
      { turn: 5, edge: 'flank', units: [['wolf_rider', 1, 1], ['goblin_rabble', 1, 1]], label: 'Riders round the flank' },
      { turn: 5, edge: 'main', units: [['orc_warlord', 1, 1], ['troll', 1, 1], ['orc_warrior', 1, 1], ['goblin_rabble', 1, 1]], label: 'The warchief\'s own host', final: true, warchief: 'orc_warlord' },
    ],
    allies: [['militia', 3]],
    intel: 'The whole host, in waves, led by its warchief.',
    loot: { silver: [140, 170], iron: [3, 4], timber: [2, 3], trophies: 2 },
  },
];

export function encounterById(id: string): EncounterDef {
  const e = ENCOUNTERS.find((x) => x.id === id);
  if (!e) throw new Error(`no encounter ${id}`);
  return e;
}
