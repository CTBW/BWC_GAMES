import type { Resources } from '../core/types';

export type NodeType = 'start' | 'battle' | 'ambush' | 'scout' | 'village' | 'event' | 'camp' | 'objective';

export const NODE_INFO: Record<NodeType, { name: string; icon: string; blurb: string }> = {
  start: { name: 'Muster point', icon: 'start', blurb: 'Where the company left the road.' },
  battle: { name: 'Battle', icon: 'battle', blurb: 'The horde holds this ground. Expect to be outnumbered.' },
  ambush: { name: 'Ambush', icon: 'ambush', blurb: 'The horde lies in wait here. They will strike first.' },
  scout: { name: 'Lookout', icon: 'scout', blurb: 'High ground with a view of the road ahead.' },
  village: { name: 'Abandoned village', icon: 'village', blurb: 'Empty homes. Something useful may remain.' },
  event: { name: 'Encounter', icon: 'event', blurb: 'Something on the road demands a decision.' },
  camp: { name: 'Campsite', icon: 'camp', blurb: 'A sheltered spot to rest and tend the wounded.' },
  objective: { name: 'Last stand', icon: 'objective', blurb: 'Where the company makes its stand against the host.' },
};

export interface CampaignDef {
  id: string;
  name: string;
  tier: number;
  tierName: string;
  region: string;
  blurb: string;
  hints: { enemies: string[]; terrain: string; length: string; threat: string; supplies: string };
  /** Stages between the muster point and the objective. */
  stages: number;
  lanes: [number, number];
  weights: Partial<Record<NodeType, number>>;
  encounterTier: number;
  objective: { name: string; encounterId: string; description: string };
  reward: Partial<Resources>;
  unitSlots: number;
  commandPoints: number;
  /** Soldiers above this level are reluctant (morale penalty). */
  reluctantAbove: number;
  /** Soldiers above this level refuse to go. */
  refuseAbove: number;
  requiresCommandLevel: number;
  /** Fatigue added to each soldier per march. */
  marchFatigue: number;
}

export const CAMPAIGNS: CampaignDef[] = [
  {
    id: 'hillsvain_raids',
    name: 'The Hillsvain Host',
    tier: 1,
    tierName: 'Apprentice',
    region: 'Hillsvain Woods',
    blurb:
      'A host of orcs and goblins is pouring out of the Hillsvain Woods, burning every steading west of the Vattern. The Margrave\'s riders are days away. March out, slow the horde, and hold Brannsted until they come: you are all that stands between the host and the river.',
    hints: {
      enemies: ['goblin_rabble', 'goblin_spear', 'goblin_archer', 'wolf_rider', 'orc_brute'],
      terrain: 'Forest glades, the Vattern and its ford, burning farmsteads, the walls of Brannsted.',
      length: 'Short: about five marches, then the last stand.',
      threat: 'Always outnumbered. Waves of goblins, wolf riders on the flanks, brutes that smash lines, and the warchief himself at the end.',
      supplies: 'Bring rations for every march and plenty of bolts: the last stand is long. Bandages save the fallen.',
    },
    stages: 5,
    lanes: [2, 3],
    weights: { battle: 32, event: 22, village: 14, camp: 10, scout: 10, ambush: 8 },
    encounterTier: 1,
    objective: {
      name: 'Brannsted',
      encounterId: 'last_stand',
      description: 'Hold the steading of Brannsted against the whole host until the Margrave\'s riders arrive at dawn, or slay its warchief.',
    },
    reward: { silver: 120, timber: 3, iron: 1 },
    unitSlots: 6,
    commandPoints: 14,
    reluctantAbove: 3,
    // Tier 1 is the only tier in this build; refusal starts once tier 2 exists.
    refuseAbove: 5,
    requiresCommandLevel: 1,
    marchFatigue: 6,
  },
];

export function campaignById(id: string): CampaignDef {
  const c = CAMPAIGNS.find((x) => x.id === id);
  if (!c) throw new Error(`no campaign ${id}`);
  return c;
}
