import { Rng } from '../core/rng';
import type { Resources, SupplyId } from '../core/types';
import { campaignById, NODE_INFO, type NodeType } from '../data/campaigns';
import { ENCOUNTERS, encounterById } from '../data/encounters';
import { EVENTS, type Effect, type EventChoice, type EventDef, type Who } from '../data/events';
import { INJURIES, SUPPLIES } from '../data/items';
import { UNIT_TYPES, squadSize } from '../data/units';
import { FALL_SURVIVAL_BASE, type Battle } from '../battle/battle';
import { rollEncounter, type EncounterRoll } from '../battle/setup';
import { aliveFor, memberNoun, squadName } from '../battle/squad';
import {
  armyCommand,
  armyLimits,
  chronicle,
  effect,
  gainXp,
  nextId,
  numberWord,
  rollRecruits,
  useRng,
  type GameState,
} from '../meta/game';
import {
  commandCost,
  healSoldier,
  newSoldier,
  settleMen,
  soldierStats,
  soldierToUnit,
  squadHpCap,
  squadMaxHp,
  type Soldier,
} from '../meta/soldier';
import type { BattleUnit } from '../battle/types';

export interface CNode {
  id: string;
  stage: number;
  lane: number;
  type: NodeType;
  name: string;
  revealed: boolean;
  scouted: boolean;
  visited: boolean;
  /** World tile position on the campaign map. */
  tx: number;
  ty: number;
  encounter?: EncounterRoll;
  eventId?: string;
  night?: boolean;
}

export type Pending =
  | { kind: 'arrive'; nodeId: string }
  | { kind: 'event'; nodeId: string; eventId: string; subject?: string; result?: { text: string; changes: string[] }; followBattle?: EncounterRoll }
  | { kind: 'battle'; nodeId: string; roll: EncounterRoll; title: string; objective: boolean; surprise: boolean; night?: boolean }
  | { kind: 'battleResult'; report: BattleReport }
  | { kind: 'camp'; nodeId: string; done: string[]; raid?: boolean; messages: string[] }
  | { kind: 'village'; nodeId: string; spots: VillageSpot[]; messages: string[] }
  | { kind: 'scout'; nodeId: string }
  | { kind: 'complete' };

export interface VillageSpot {
  label: string;
  searched: boolean;
  locked: boolean;
}

export interface BattleReport {
  title: string;
  result: 'victory' | 'defeat' | 'retreat';
  objective: boolean;
  loot: Partial<Resources>;
  fallen: { name: string; typeId: string; level: number }[];
  wounded: { name: string; injury: string }[];
  routed: string[];
  levelUps: string[];
  xp: { name: string; xp: number }[];
  /** Enemy squads destroyed. */
  enemiesKilled: number;
  enemiesFled: number;
  /** Enemy soldiers slain across all squads (missing in reports saved before squads). */
  enemySoldiersSlain?: number;
  /** Soldiers each of your squads lost. `men` is what remains (0: the squad is gone). */
  losses?: SquadLoss[];
  bandagesUsed: number;
  boltsUsed: number;
}

export interface SquadLoss {
  name: string;
  typeId: string;
  lost: number;
  men: number;
  size: number;
  fate: 'fought' | 'downed' | 'dead';
  /** Fallen soldiers found alive after the battle and carried back to the ranks. */
  saved?: number;
}

export interface Expedition {
  campaignId: string;
  seed: number;
  rng: number;
  nodes: CNode[];
  edges: [string, string][];
  current: string;
  path: string[];
  army: string[];
  supplies: Record<SupplyId, number>;
  loot: Resources;
  marches: number;
  objectiveDone: boolean;
  log: { text: string; tone?: 'good' | 'bad' | 'neutral' }[];
  pending: Pending | null;
  battles: number;
  startArmy: number;
  starving: number;
  /** Soldiers lost on this expedition, in battle and on the road. */
  menLost?: number;
  /** Soldiers in the army when it marched out. */
  startMen?: number;
}

export interface ExpeditionReport {
  campaignId: string;
  outcome: 'success' | 'retreat' | 'defeat';
  loot: Resources;
  reward: Partial<Resources>;
  buyback: number;
  stipend: number;
  fallen: string[];
  survivors: string[];
  /** Strength of each returning squad (missing in reports saved before squads). */
  strength?: { name: string; typeId: string; men: number; size: number }[];
  /** Soldiers lost on the expedition. */
  menLost?: number;
  marches: number;
  battles: number;
}

const PLACE_NAMES: Record<string, string[]> = {
  battle: ['Wolfsrun Glade', 'Burnt Oak Clearing', 'The Long Meadow', 'Elk Hollow', 'Raven Copse', 'Mossback Ridge', 'Grey Stones'],
  ambush: ['Tangled Road', 'Bramble Pass', 'The Narrows', 'Darkwood Track'],
  scout: ['Watcher\'s Rock', 'The Old Tower', 'Hawk Crag', 'Signal Hill'],
  village: ['Ostby', 'Lindholm', 'Kettlewick', 'Brannsted', 'Halla', 'Mjolby'],
  event: ['Crossroads', 'Woodcutter\'s Track', 'The Mill Road', 'Fenside', 'Old Shrine Path', 'Charcoal Burners\' Clearing'],
  camp: ['Spring Hollow', 'Fir Shelter', 'The Lee of the Hill', 'Stone Circle'],
};

/** One line of news of the host per march: it is always closer than the last. */
const HORDE_NEWS = [
  'Smoke on the western skyline: the host has crossed out of the Hillsvain Woods.',
  'Refugees pass the column at a run. Ostby is burning.',
  'War drums in the distance, all through the night.',
  'Wolf riders shadow the column from the ridges, and vanish when the crossbows turn.',
  'The host is a day from Brannsted. Its fires light the whole western sky.',
  'You can hear them now: thousands of voices, and the horns.',
];

// ---------------------------------------------------------------- generation

export function generateExpedition(g: GameState, campaignId: string, army: string[], supplies: Record<SupplyId, number>): Expedition {
  const c = campaignById(campaignId);
  const seed = useRng(g, (r) => r.int(1, 2 ** 31 - 1));
  const rng = new Rng(seed);
  const nodes: CNode[] = [];
  const edges: [string, string][] = [];
  const usedNames = new Set<string>();
  const nameFor = (t: NodeType) => {
    const list = PLACE_NAMES[t] ?? ['Waypoint'];
    for (let i = 0; i < 10; i++) {
      const n = rng.pick(list);
      if (!usedNames.has(n)) {
        usedNames.add(n);
        return n;
      }
    }
    return rng.pick(list);
  };
  const total = c.stages + 1;
  const start = { x: 30, y: 30 };
  const end = { x: 7, y: 7 };
  const place = (stage: number, lane: number, lanes: number) => {
    const t = stage / total;
    const cx = start.x + (end.x - start.x) * t;
    const cy = start.y + (end.y - start.y) * t;
    const off = lanes === 1 ? 0 : (lane - (lanes - 1) / 2) * 7.5;
    return {
      tx: Math.round(cx + off * 0.7071 + rng.range(-1.2, 1.2)),
      ty: Math.round(cy - off * 0.7071 + rng.range(-1.2, 1.2)),
    };
  };
  nodes.push({ id: 'n0', stage: 0, lane: 0, type: 'start', name: 'Muster point', revealed: true, scouted: true, visited: true, ...place(0, 0, 1) });
  let prev: CNode[] = [nodes[0]];
  let campPlaced = false;
  for (let s = 1; s <= c.stages; s++) {
    const lanes = rng.int(c.lanes[0], c.lanes[1]);
    const stageNodes: CNode[] = [];
    for (let l = 0; l < lanes; l++) {
      let type = rng.weighted(Object.keys(c.weights) as NodeType[], (t) => c.weights[t] ?? 0);
      if (s === 1 && (type === 'camp' || type === 'ambush')) type = rng.pick(['event', 'village', 'battle'] as NodeType[]);
      if (type === 'camp' && s < 2) type = 'event';
      stageNodes.push({
        id: `n${nodes.length + stageNodes.length}`,
        stage: s,
        lane: l,
        type,
        name: '',
        revealed: s === 1,
        scouted: false,
        visited: false,
        ...place(s, l, lanes),
      });
    }
    // Guarantee variety: a battle in every stage after the first, a camp mid-way.
    if (s >= 2 && !stageNodes.some((n) => n.type === 'battle' || n.type === 'ambush')) rng.pick(stageNodes).type = 'battle';
    if (!campPlaced && s === Math.ceil(c.stages / 2) + 1 && !stageNodes.some((n) => n.type === 'camp')) {
      const cand = stageNodes.filter((n) => n.type !== 'battle');
      (cand.length ? rng.pick(cand) : stageNodes[stageNodes.length - 1]).type = 'camp';
    }
    if (stageNodes.some((n) => n.type === 'camp')) campPlaced = true;
    if (s === c.stages && !stageNodes.some((n) => n.type === 'camp') && stageNodes.length > 1) {
      rng.pick(stageNodes.filter((n) => n.type !== 'battle').concat(stageNodes)).type = 'camp';
    }
    for (const n of stageNodes) {
      n.name = nameFor(n.type);
      if (n.type === 'battle' || n.type === 'ambush') {
        const pool = ENCOUNTERS.filter(
          (e) =>
            e.tier === c.encounterTier &&
            !e.objective &&
            (n.type === 'ambush' ? e.ambush : !e.ambush) &&
            (e.minDepth ?? 0) <= s - 1 &&
            (e.maxDepth ?? 99) >= s - 1,
        );
        const enc = rng.weighted(pool.length ? pool : ENCOUNTERS.filter((e) => e.ambush), (e) => e.weight);
        n.encounter = rollEncounter(enc.id, rng, s - 1);
      }
      if (n.type === 'event') n.eventId = pickEvent(rng, s, nodes.concat(stageNodes)).id;
      if (n.type === 'camp') n.night = true;
      nodes.push(n);
    }
    connect(prev, stageNodes, edges, rng);
    prev = stageNodes;
  }
  // Half way, the road crosses the Vattern where Ostby's people are fleeing:
  // one road leads to the ford, and to a stand there if the company takes it.
  const fordStage = Math.min(c.stages - 1, 3);
  const fordCands = nodes.filter((n) => n.stage === fordStage && n.type !== 'camp' && n.type !== 'start');
  if (fordCands.length > 1) {
    const f = rng.pick(fordCands);
    f.type = 'battle';
    f.name = 'The Vattern Ford';
    f.encounter = rollEncounter('refugee_stand', rng, fordStage - 1);
    f.eventId = undefined;
  }
  const obj: CNode = {
    id: `n${nodes.length}`,
    stage: total,
    lane: 0,
    type: 'objective',
    name: c.objective.name,
    revealed: true,
    scouted: false,
    visited: false,
    ...place(total, 0, 1),
    encounter: rollEncounter(c.objective.encounterId, rng, c.stages),
  };
  nodes.push(obj);
  for (const p of prev) edges.push([p.id, obj.id]);

  const ex: Expedition = {
    campaignId,
    seed,
    rng: rng.state,
    nodes,
    edges,
    current: 'n0',
    path: ['n0'],
    army: army.slice(),
    supplies: { ...supplies },
    loot: { silver: 0, timber: 0, iron: 0, trophies: 0 },
    marches: 0,
    objectiveDone: false,
    log: [{ text: `The company marches for ${c.region}.` }],
    pending: null,
    battles: 0,
    startArmy: army.length,
    starving: 0,
    menLost: 0,
  };
  return ex;
}

function pickEvent(rng: Rng, stage: number, existing: CNode[]): EventDef {
  const used = new Set(existing.map((n) => n.eventId).filter(Boolean));
  const pool = EVENTS.filter((e) => (e.minStage ?? 0) <= stage - 1 && (e.maxStage ?? 99) >= stage - 1 && !used.has(e.id));
  return rng.weighted(pool.length ? pool : EVENTS, (e) => e.weight);
}

/** Non-crossing edges between consecutive stages; every node gets in and out. */
function connect(a: CNode[], b: CNode[], edges: [string, string][], rng: Rng) {
  const pos = (n: CNode, arr: CNode[]) => (arr.length === 1 ? 0.5 : n.lane / (arr.length - 1));
  const hasIn = new Set<string>();
  for (const n of a) {
    const p = pos(n, a);
    const sorted = b.slice().sort((x, y) => Math.abs(pos(x, b) - p) - Math.abs(pos(y, b) - p));
    edges.push([n.id, sorted[0].id]);
    hasIn.add(sorted[0].id);
    if (sorted[1] && Math.abs(pos(sorted[1], b) - p) <= 0.55 && rng.chance(0.55)) {
      edges.push([n.id, sorted[1].id]);
      hasIn.add(sorted[1].id);
    }
  }
  for (const m of b) {
    if (hasIn.has(m.id)) continue;
    const p = pos(m, b);
    const src = a.slice().sort((x, y) => Math.abs(pos(x, a) - p) - Math.abs(pos(y, a) - p))[0];
    edges.push([src.id, m.id]);
  }
  // Remove crossing edges (keep the first of a crossing pair).
  const stageEdges = edges.filter(([f, t]) => a.some((n) => n.id === f) && b.some((n) => n.id === t));
  const lane = (id: string, arr: CNode[]) => arr.find((n) => n.id === id)!.lane;
  for (let i = 0; i < stageEdges.length; i++) {
    for (let j = i + 1; j < stageEdges.length; j++) {
      const [f1, t1] = stageEdges[i];
      const [f2, t2] = stageEdges[j];
      const cross = (lane(f1, a) - lane(f2, a)) * (lane(t1, b) - lane(t2, b)) < 0;
      if (!cross) continue;
      const outF2 = edges.filter((e) => e[0] === f2).length;
      const inT2 = edges.filter((e) => e[1] === t2).length;
      if (outF2 > 1 && inT2 > 1) {
        const k = edges.indexOf(stageEdges[j]);
        if (k >= 0) edges.splice(k, 1);
      }
    }
  }
}

// ---------------------------------------------------------------- helpers

export function exRng<T>(ex: Expedition, fn: (r: Rng) => T): T {
  const r = new Rng(ex.rng);
  const out = fn(r);
  ex.rng = r.state;
  return out;
}

export function node(ex: Expedition, id: string): CNode {
  return ex.nodes.find((n) => n.id === id)!;
}

export function nextNodes(ex: Expedition): CNode[] {
  return ex.edges.filter((e) => e[0] === ex.current).map((e) => node(ex, e[1]));
}

export function armySoldiers(g: GameState): Soldier[] {
  const ex = g.expedition!;
  return ex.army.map((id) => g.roster.find((s) => s.id === id)!).filter(Boolean);
}

export function rationCost(g: GameState): number {
  return Math.ceil(armySoldiers(g).length / 2);
}

function addLog(ex: Expedition, text: string, tone: 'good' | 'bad' | 'neutral' = 'neutral') {
  ex.log.unshift({ text, tone });
  if (ex.log.length > 40) ex.log.length = 40;
}

/** "one of Aldric's footmen dies" / "two of Aldric's footmen die". */
function lossPhrase(s: Soldier, lost: number): { who: string; verb: 'dies' | 'die' } {
  return { who: `${numberWord(lost)} of ${squadName(s)}`, verb: lost === 1 ? 'dies' : 'die' };
}

/**
 * Damage a squad outside battle. The pool loses `amount`; any soldier whose
 * share runs out dies (never the last one: the road does not wipe out a squad).
 * Deaths go to the expedition log and the chronicle. Returns soldiers lost.
 */
export function hurtSquad(g: GameState, s: Soldier, amount: number, say: (who: string, verb: string) => string): number {
  const before = s.men;
  s.hp = Math.max(1, s.hp - Math.max(0, Math.round(amount)));
  settleMen(s);
  const lost = before - s.men;
  if (lost > 0) {
    const { who, verb } = lossPhrase(s, lost);
    const text = say(who, verb);
    const ex = g.expedition;
    if (ex) {
      ex.menLost = (ex.menLost ?? 0) + lost;
      addLog(ex, text, 'bad');
    }
    chronicle(g, text, 'bad');
  }
  return lost;
}


function revealAhead(ex: Expedition, fromId: string, depth: number, scout = false) {
  let frontier = [fromId];
  for (let d = 0; d < depth; d++) {
    const next: string[] = [];
    for (const id of frontier) {
      for (const e of ex.edges.filter((x) => x[0] === id)) {
        const n = node(ex, e[1]);
        n.revealed = true;
        if (scout) n.scouted = true;
        next.push(n.id);
      }
    }
    frontier = next;
  }
}

/** What the player can see about a node. */
export function nodeView(n: CNode): { type: NodeType | 'unknown'; title: string; detail: string } {
  if (!n.revealed) return { type: 'unknown', title: 'Unexplored', detail: 'Scouts have not been this way.' };
  if (n.type === 'ambush' && !n.scouted) {
    return { type: 'event', title: n.name, detail: 'Quiet woods. Too quiet, perhaps.' };
  }
  const info = NODE_INFO[n.type];
  let detail = info.blurb;
  if (n.encounter && (n.scouted || n.type === 'objective')) {
    const counts: Record<string, number> = {};
    for (const e of n.encounter.enemies) counts[e.typeId] = (counts[e.typeId] ?? 0) + 1;
    detail = Object.entries(counts)
      .map(([t, k]) => `${k} ${k === 1 ? UNIT_TYPES[t].name : UNIT_TYPES[t].plural}`)
      .join(', ');
    const waves = n.encounter.waves ?? [];
    const more = waves.reduce((s, w) => s + w.units.length, 0);
    if (waves.length) detail += waves.some((w) => w.horn) ? `. A horn-bearer can call ${more} more squads.` : `. Then ${waves.length === 1 ? 'one more wave' : `${waves.length} more waves`}: ${more} squads.`;
  } else if (n.encounter) {
    const k = n.encounter.enemies.length + (n.encounter.waves ?? []).reduce((s, w) => s + w.units.length, 0);
    detail = k <= 6 ? 'A band of the host.' : k <= 10 ? 'A large band of the host, with more behind it.' : 'The host in force.';
    const intel = encounterById(n.encounter.encounterId).intel;
    if (intel && n.type !== 'ambush') detail += ` ${intel}`;
  }
  return { type: n.type, title: n.type === 'objective' ? n.name : `${n.name}`, detail };
}

// ---------------------------------------------------------------- start / march

export function startExpedition(g: GameState, campaignId: string, army: string[], supplies: Record<SupplyId, number>, cost: number) {
  g.resources.silver -= cost;
  g.cycle++;
  const ex = generateExpedition(g, campaignId, army, supplies);
  g.expedition = ex;
  const c = campaignById(campaignId);
  for (const s of armySoldiers(g)) {
    s.fatigue = 0;
    if (s.level > c.reluctantAbove) {
      s.morale = Math.max(1, s.morale - 15);
      addLog(ex, `${s.name} grumbles about chasing goblins (-15 morale).`, 'bad');
    }
  }
  const men = armySoldiers(g).reduce((n, s) => n + s.men, 0);
  ex.startMen = men;
  chronicle(g, `Expedition ${g.cycle}: ${army.length} squads (${men} soldiers) march on ${c.name}.`);
}

export function canMarch(g: GameState, id: string): boolean {
  const ex = g.expedition;
  if (!ex || ex.pending) return false;
  return nextNodes(ex).some((n) => n.id === id);
}

export function march(g: GameState, id: string): boolean {
  const ex = g.expedition;
  if (!ex || !canMarch(g, id)) return false;
  const c = campaignById(ex.campaignId);
  const need = rationCost(g);
  const soldiers = armySoldiers(g);
  ex.marches++;
  if (ex.supplies.rations >= need) {
    ex.supplies.rations -= need;
    ex.starving = 0;
  } else {
    ex.supplies.rations = 0;
    ex.starving++;
    addLog(ex, 'The rations have run out. The army marches hungry.', 'bad');
    for (const s of soldiers) {
      s.morale = Math.max(1, s.morale - 8 - ex.starving * 2);
      s.fatigue = Math.min(100, s.fatigue + 10);
      // Hunger costs every soldier 2 HP of his share.
      hurtSquad(g, s, 2 * s.men, (who) => `Hunger takes ${who}.`);
    }
  }
  for (const s of soldiers) s.fatigue = Math.min(100, s.fatigue + c.marchFatigue);
  ex.current = id;
  ex.path.push(id);
  const n = node(ex, id);
  n.visited = true;
  n.revealed = true;
  revealAhead(ex, id, 1);
  const news = HORDE_NEWS[Math.min(HORDE_NEWS.length - 1, ex.marches - 1)];
  if (news) addLog(ex, news, 'bad');
  ex.pending = { kind: 'arrive', nodeId: id };
  resolveArrival(g);
  return true;
}

function resolveArrival(g: GameState) {
  const ex = g.expedition!;
  const n = node(ex, ex.current);
  switch (n.type) {
    case 'battle':
      ex.pending = { kind: 'battle', nodeId: n.id, roll: n.encounter!, title: `${encounterById(n.encounter!.encounterId).name} at ${n.name}`, objective: false, surprise: false };
      break;
    case 'ambush':
      addLog(ex, `Ambush at ${n.name}!`, 'bad');
      ex.pending = { kind: 'battle', nodeId: n.id, roll: n.encounter!, title: `Ambush at ${n.name}`, objective: false, surprise: true };
      break;
    case 'objective':
      ex.pending = { kind: 'battle', nodeId: n.id, roll: n.encounter!, title: n.name, objective: true, surprise: false };
      break;
    case 'event':
      ex.pending = { kind: 'event', nodeId: n.id, eventId: n.eventId!, subject: exRng(ex, (r) => r.pick(armySoldiers(g)))?.id };
      break;
    case 'camp':
      ex.pending = { kind: 'camp', nodeId: n.id, done: [], messages: [] };
      break;
    case 'village':
      ex.pending = {
        kind: 'village',
        nodeId: n.id,
        messages: [],
        spots: exRng(ex, (r) => {
          const labels = r.shuffle(['The longhouse', 'A collapsed barn', 'The smithy', 'The well house', 'A root cellar', 'The chapel']).slice(0, 3);
          return [...labels.map((label) => ({ label, searched: false, locked: false })), { label: 'A locked strongbox', searched: false, locked: true }];
        }),
      };
      break;
    case 'scout': {
      revealAhead(ex, n.id, 3, true);
      addLog(ex, `From ${n.name} the scouts map the road ahead.`, 'good');
      const obj = ex.nodes.find((q) => q.type === 'objective');
      const host = obj?.encounter ? obj.encounter.enemies.length + (obj.encounter.waves ?? []).reduce((s, w) => s + w.units.length, 0) : 0;
      if (host) addLog(ex, `Beyond the woods the host is on the move toward Brannsted: the scouts count ${host} warbands under the banners, and the warchief's own standard among them.`, 'bad');
      ex.pending = { kind: 'scout', nodeId: n.id };
      break;
    }
    default:
      ex.pending = null;
  }
}

export function dismissPending(g: GameState) {
  const ex = g.expedition;
  if (!ex?.pending) return;
  const p = ex.pending;
  if (p.kind === 'event' && p.followBattle) {
    ex.pending = { kind: 'battle', nodeId: p.nodeId, roll: p.followBattle, title: 'Ambushed!', objective: false, surprise: true };
    return;
  }
  if (p.kind === 'battleResult' && (p.report.result === 'defeat')) {
    returnHome(g, 'defeat');
    return;
  }
  if (p.kind === 'battleResult' && p.report.objective && p.report.result === 'victory') {
    ex.pending = { kind: 'complete' };
    return;
  }
  if (p.kind === 'camp' && !p.raid) {
    // Leaving camp at night without a watch risks a raid next time; handled in camp actions.
  }
  ex.pending = null;
}

// ---------------------------------------------------------------- events

export function choiceAvailable(g: GameState, ch: EventChoice): { ok: boolean; reason?: string } {
  const ex = g.expedition!;
  const r = ch.requires;
  if (!r) return { ok: true };
  if (r.supply && ex.supplies[r.supply[0]] < Math.max(1, r.supply[1])) return { ok: false, reason: `Needs ${SUPPLIES[r.supply[0]].name.toLowerCase()}` };
  if (r.loot && ex.loot[r.loot[0]] < r.loot[1]) return { ok: false, reason: `Needs ${r.loot[1]} ${r.loot[0]} in the spoils` };
  if (r.type && !armySoldiers(g).some((s) => s.typeId === r.type)) return { ok: false, reason: `Needs a ${UNIT_TYPES[r.type].name.toLowerCase()}` };
  if (r.slot) {
    const lim = armyLimits(g, campaignById(ex.campaignId));
    if (ex.army.length >= lim.slots) return { ok: false, reason: 'No free unit slot' };
    if (armyCommand(g, ex.army) + 2 > lim.command) return { ok: false, reason: 'Not enough command points' };
  }
  return { ok: true };
}

export function chooseEvent(g: GameState, choiceIndex: number) {
  const ex = g.expedition!;
  const p = ex.pending;
  if (!p || p.kind !== 'event' || p.result) return;
  const ev = EVENTS.find((e) => e.id === p.eventId)!;
  const ch = ev.choices[choiceIndex];
  if (!choiceAvailable(g, ch).ok) return;
  const outcome = exRng(ex, (r) => r.weighted(ch.outcomes, (o) => o.weight));
  const subject = armySoldiers(g).find((s) => s.id === p.subject) ?? exRng(ex, (r) => r.pick(armySoldiers(g)));
  const changes: string[] = [];
  let battle: EncounterRoll | undefined;
  for (const e of outcome.effects) {
    const res = applyEffect(g, e, subject, ev.title);
    if (res.text) changes.push(res.text);
    if (res.extra) changes.push(...res.extra);
    if (res.battle) battle = res.battle;
  }
  const text = outcome.text.replaceAll('{name}', subject?.name ?? 'A soldier');
  p.result = { text, changes };
  if (battle) p.followBattle = battle;
  addLog(ex, `${ev.title}: ${text}`);
}

function pickWho(g: GameState, who: Who, subject?: Soldier): Soldier[] {
  const army = armySoldiers(g);
  if (who === 'all') return army;
  if (who === 'random') return subject ? [subject] : army.slice(0, 1);
  if (who === 'weakest') return army.slice().sort((a, b) => a.hp / squadMaxHp(a) - b.hp / squadMaxHp(b)).slice(0, 1);
  if (who === 'strongest') return army.slice().sort((a, b) => b.level - a.level).slice(0, 1);
  if (who.startsWith('type:')) return army.filter((s) => s.typeId === who.slice(5));
  return [];
}

export function applyEffect(
  g: GameState,
  e: Effect,
  subject?: Soldier,
  cause = 'The road',
): { text?: string; extra?: string[]; battle?: EncounterRoll } {
  const ex = g.expedition!;
  const sign = (n: number) => (n > 0 ? `+${n}` : `${n}`);
  switch (e.k) {
    case 'supply': {
      const before = ex.supplies[e.id];
      ex.supplies[e.id] = Math.max(0, before + e.n);
      const d = ex.supplies[e.id] - before;
      return d ? { text: `${sign(d)} ${SUPPLIES[e.id].name.toLowerCase()}` } : {};
    }
    case 'loot': {
      const before = ex.loot[e.id];
      ex.loot[e.id] = Math.max(0, before + e.n);
      const d = ex.loot[e.id] - before;
      return d ? { text: `${sign(d)} ${e.id}` } : {};
    }
    case 'morale': {
      const who = pickWho(g, e.who, subject);
      for (const s of who) s.morale = Math.max(1, Math.min(soldierStats(s).morale, s.morale + e.n));
      return { text: `${sign(e.n)} morale${e.who === 'all' ? ' (army)' : ` (${who.map((s) => s.name.split(' ')[0]).join(', ')})`}` };
    }
    case 'hp': {
      // Effects are written for one soldier; every soldier in the squad takes them.
      const who = pickWho(g, e.who, subject);
      const extra: string[] = [];
      for (const s of who) {
        if (e.n >= 0) healSoldier(s, e.n * s.men);
        else {
          const lost = hurtSquad(g, s, -e.n * s.men, (w, verb) => `${cause}: ${w} ${verb}.`);
          if (lost) extra.push(`-${lost} ${memberNoun(s.typeId, lost)} (${s.name.split(' ')[0]})`);
        }
      }
      return { text: `${sign(e.n)} HP each${e.who === 'all' ? ' (army)' : ` (${who.map((s) => s.name.split(' ')[0]).join(', ')})`}`, extra };
    }
    case 'fatigue': {
      const who = pickWho(g, e.who, subject);
      for (const s of who) s.fatigue = Math.max(0, Math.min(100, s.fatigue + e.n));
      return { text: `${sign(e.n)} fatigue${e.who === 'all' ? ' (army)' : ''}` };
    }
    case 'xp': {
      const who = pickWho(g, e.who, subject);
      for (const s of who) gainXp(g, s, e.n);
      return { text: `${sign(e.n)} XP (${who.map((s) => s.name.split(' ')[0]).join(', ')})` };
    }
    case 'injury': {
      const who = pickWho(g, e.who, subject);
      const out: string[] = [];
      for (const s of who) {
        const inj = exRng(ex, (r) => r.pick(Object.keys(INJURIES)));
        if (!s.injuries.includes(inj)) s.injuries.push(inj);
        out.push(`${s.name.split(' ')[0]}: ${INJURIES[inj].name}`);
      }
      return { text: out.join(', ') };
    }
    case 'recruit': {
      const s = exRng(ex, (r) => newSoldier(r, e.typeId, e.level, nextId(g), g.cycle));
      // A band met on the road is never a full squad: the Barracks can fill it later.
      s.men = Math.max(1, Math.ceil(squadSize(e.typeId) / 2));
      s.hp = squadHpCap(s);
      s.fatigue = 20;
      g.roster.push(s);
      ex.army.push(s.id);
      chronicle(g, `${s.name} and ${numberWord(s.men - 1)} more ${UNIT_TYPES[e.typeId].plural.toLowerCase()} join the company on the road.`);
      return { text: `${s.name} joins with ${s.men} ${UNIT_TYPES[e.typeId].plural.toLowerCase()} (${s.men}/${squadSize(e.typeId)}, ${commandCost(s)} CP)` };
    }
    case 'battle': {
      const roll = exRng(ex, (r) => rollEncounter(e.encounterId, r, node(ex, ex.current).stage));
      return { text: 'Battle!', battle: roll };
    }
    case 'reveal': {
      revealAhead(ex, ex.current, e.stages, true);
      return { text: `The road ahead is scouted (${e.stages} stages)` };
    }
  }
}

// ---------------------------------------------------------------- camp & village

export function campRest(g: GameState) {
  const ex = g.expedition!;
  const p = ex.pending;
  if (!p || p.kind !== 'camp' || p.done.includes('rest')) return;
  const army = armySoldiers(g);
  const need = army.length;
  const fed = Math.min(need, ex.supplies.rations);
  ex.supplies.rations -= fed;
  const ratio = fed / need;
  for (const s of army) {
    const st = soldierStats(s);
    // 30% of every surviving soldier's share; the dead stay dead.
    healSoldier(s, squadHpCap(s) * 0.3 * ratio);
    s.morale = Math.min(st.morale, s.morale + Math.round(15 * ratio));
    s.fatigue = Math.max(0, s.fatigue - Math.round(45 * ratio));
  }
  p.done.push('rest');
  p.messages.push(
    ratio >= 1
      ? `The army eats a hot meal and sleeps (-${fed} rations): +30% HP, +15 morale, -45 fatigue.`
      : `There is not enough food for everyone (-${fed} rations). The rest is poor.`,
  );
  // Night raid unless a watch is kept with torches.
  if (!p.done.includes('watch')) {
    const raid = exRng(ex, (r) => r.chance(0.3));
    if (raid) {
      p.raid = true;
      p.messages.push('In the dark, goblins rush the camp!');
      ex.pending = {
        kind: 'battle',
        nodeId: p.nodeId,
        roll: exRng(ex, (r) => rollEncounter('road_ambush', r, node(ex, ex.current).stage)),
        title: 'Night raid on the camp',
        objective: false,
        surprise: true,
        night: true,
      };
      addLog(ex, 'Goblins raid the camp in the night!', 'bad');
    }
  }
}

export function campWatch(g: GameState) {
  const ex = g.expedition!;
  const p = ex.pending;
  if (!p || p.kind !== 'camp' || p.done.includes('watch') || ex.supplies.torches < 1) return;
  ex.supplies.torches--;
  p.done.push('watch');
  p.messages.push('Torches are lit around the camp and a watch is set (-1 torch). No raider will catch you sleeping.');
}

export function campRepair(g: GameState) {
  const ex = g.expedition!;
  const p = ex.pending;
  if (!p || p.kind !== 'camp' || p.done.includes('repair') || ex.supplies.tools < 1) return;
  ex.supplies.tools--;
  for (const s of armySoldiers(g)) s.armorCondition = Math.min(1, s.armorCondition + 0.4);
  p.done.push('repair');
  p.messages.push('The army mends straps and hammers out dents (-1 tools): +40% armour condition.');
}

export function useBandage(g: GameState, soldierId: string): boolean {
  const ex = g.expedition;
  if (!ex || ex.supplies.bandages < 1) return false;
  const s = g.roster.find((r) => r.id === soldierId);
  if (!s) return false;
  if (s.hp >= squadHpCap(s)) return false;
  ex.supplies.bandages--;
  const healed = healSoldier(s, bandageHeal(s));
  addLog(ex, `${squadName(s)} are bandaged (+${healed} HP).`);
  return true;
}

/** HP one bandage restores to a squad: 10 for each soldier still serving. */
export function bandageHeal(s: Soldier): number {
  return 10 * s.men;
}

export function searchSpot(g: GameState, index: number) {
  const ex = g.expedition!;
  const p = ex.pending;
  if (!p || p.kind !== 'village') return;
  const spot = p.spots[index];
  if (!spot || spot.searched) return;
  if (spot.locked) {
    if (ex.supplies.tools < 1) return;
    ex.supplies.tools--;
  }
  spot.searched = true;
  const msg = exRng(ex, (r) => {
    if (spot.locked) {
      const silver = r.int(30, 55);
      ex.loot.silver += silver;
      const iron = r.int(1, 2);
      ex.loot.iron += iron;
      return `You pry the strongbox open (-1 tools): ${silver} silver and ${iron} iron.`;
    }
    const roll = r.next();
    if (roll < 0.12 && !p.spots.some((s) => s.label.includes('(raiders)'))) {
      spot.label += ' (raiders)';
      ex.pending = {
        kind: 'battle',
        nodeId: p.nodeId,
        roll: rollEncounter('goblin_scouts', r, node(ex, ex.current).stage),
        title: `Raiders in ${node(ex, ex.current).name}`,
        objective: false,
        surprise: false,
      };
      return 'Goblins burst from the ruins!';
    }
    if (roll < 0.35) {
      const n = r.int(2, 4);
      ex.supplies.rations += n;
      return `A hidden store of food: +${n} rations.`;
    }
    if (roll < 0.58) {
      const n = r.int(2, 4);
      ex.loot.timber += n;
      return `Seasoned beams worth hauling home: +${n} timber.`;
    }
    if (roll < 0.7) {
      ex.supplies.bandages += 2;
      return 'Linen and herbs: +2 bandages.';
    }
    if (roll < 0.82) {
      ex.supplies.bolts += 1;
      ex.loot.iron += 1;
      return 'A hunter\'s cache: +1 bundle of bolts, +1 iron.';
    }
    const silver = r.int(10, 25);
    ex.loot.silver += silver;
    return `A few coins under the floorboards: +${silver} silver.`;
  });
  if (ex.pending && ex.pending.kind === 'village') ex.pending.messages.push(`${spot.label}: ${msg}`);
  addLog(ex, msg);
}

// ---------------------------------------------------------------- battles

export function battleArmy(g: GameState): BattleUnit[] {
  return armySoldiers(g)
    .filter((s) => s.hp > 0)
    .map((s) => soldierToUnit(s));
}

/** Night battles: a carried torch lights the field (consumed); otherwise darkness hampers shooting. */
export function prepareNight(g: GameState): { night: boolean; darkness: boolean; torchUsed: boolean } {
  const ex = g.expedition!;
  const p = ex.pending;
  if (!p || p.kind !== 'battle' || !p.night) return { night: false, darkness: false, torchUsed: false };
  if (ex.supplies.torches > 0) {
    ex.supplies.torches--;
    addLog(ex, 'Torches are lit around the camp (-1 torch).');
    return { night: true, darkness: false, torchUsed: true };
  }
  return { night: true, darkness: true, torchUsed: false };
}

export function survivalBonus(g: GameState): number {
  const ex = g.expedition;
  return effect(g, 'infirmary', 'survival') + (ex && ex.supplies.bandages > 0 ? 0.12 : 0);
}

/** Apply a finished battle to the roster and expedition. */
export function applyBattle(g: GameState, b: Battle, title: string, objective: boolean): BattleReport {
  const ex = g.expedition!;
  ex.battles++;
  const result = b.result ?? 'defeat';
  const report: BattleReport = {
    title,
    result,
    objective,
    loot: {},
    fallen: [],
    wounded: [],
    routed: [],
    levelUps: [],
    xp: [],
    enemiesKilled: b.units.filter((u) => u.faction === 'enemy' && u.status === 'dead').length,
    enemiesFled: b.units.filter((u) => u.faction === 'enemy' && u.status === 'fled').length,
    enemySoldiersSlain: b.units.filter((u) => u.faction === 'enemy').reduce((n, u) => n + Math.max(0, (u.size ?? 1) - (u.alive ?? 0)), 0),
    losses: [],
    bandagesUsed: 0,
    boltsUsed: 0,
  };
  // Field triage: once the fighting is over, every soldier who fell gets the
  // same chance to have been only wounded that a single soldier always had.
  // In battle the fallen stay down; this is the one way some of them return,
  // badly hurt. Fewer are found when the field is lost.
  const outcomeFactor = result === 'victory' ? 1.25 : result === 'retreat' ? 0.9 : 0.4;
  const triage = (s: Soldier, fell: number): number => {
    if (fell <= 0) return 0;
    const p = Math.min(0.85, (FALL_SURVIVAL_BASE + 0.05 * (s.level - 1) + b.setup.survivalBonus) * outcomeFactor);
    return exRng(ex, (r) => {
      let n = 0;
      for (let i = 0; i < fell; i++) if (r.chance(p)) n++;
      return n;
    });
  };
  for (const u of b.units.filter((x) => x.faction === 'player' && x.soldierId)) {
    const s = g.roster.find((r) => r.id === u.soldierId);
    if (!s) continue;
    s.battles++;
    s.kills += u.kills;
    const st = soldierStats(s);
    const size = squadSize(s.typeId);
    // Soldiers who marched into the battle (as soldierToUnit fielded them).
    const men0 = Math.max(1, Math.min(size, s.men));
    const marched = aliveFor(Math.max(1, Math.min(s.hp, st.hp * men0)), st.hp, men0);
    if (u.status === 'dead') {
      report.fallen.push({ name: s.name, typeId: s.typeId, level: s.level });
      report.losses!.push({ name: s.name, typeId: s.typeId, lost: s.men, men: 0, size, fate: 'dead' });
      ex.menLost = (ex.menLost ?? 0) + s.men;
      g.fallen.unshift({ name: s.name, typeId: s.typeId, level: s.level, kills: s.kills, battles: s.battles, cause: `Fell at ${title}`, cycle: g.cycle });
      g.roster = g.roster.filter((r) => r.id !== s.id);
      ex.army = ex.army.filter((id) => id !== s.id);
      chronicle(g, `${s.name} and his ${UNIT_TYPES[s.typeId].plural.toLowerCase()} fell at ${title}.`, 'bad');
      continue;
    }
    if (u.status === 'downed') {
      // The squad was cut down; its sergeant was carried off alive, badly hurt.
      const inj = exRng(ex, (r) => r.pick(Object.keys(INJURIES).filter((k) => !s.injuries.includes(k))));
      if (inj) s.injuries.push(inj);
      const fell = Math.max(0, s.men - 1);
      const saved = triage(s, fell);
      const lost = fell - saved;
      s.men = 1 + saved;
      s.hp = Math.max(1, Math.round(soldierStats(s).hp * (0.5 + 0.3 * saved)));
      s.morale = Math.max(1, Math.round(st.morale * 0.3));
      report.wounded.push({ name: s.name, injury: inj ? INJURIES[inj].name : 'Grievous wounds' });
      report.losses!.push({ name: s.name, typeId: s.typeId, lost, men: s.men, size, fate: 'downed', saved });
      ex.menLost = (ex.menLost ?? 0) + lost;
      if (ex.supplies.bandages > 0) {
        ex.supplies.bandages--;
        report.bandagesUsed++;
      }
    } else {
      // Survivors keep the squad's pool and the soldiers still standing. (Men too
      // hurt to march, which only an old save can have, are not counted as slain.)
      const fell = Math.max(0, marched - Math.max(1, u.alive ?? marched));
      const saved = triage(s, fell);
      const lost = fell - saved;
      s.men = Math.max(1, Math.min(size, men0 - lost));
      // Those carried back arrive with a sliver of their strength.
      s.hp = Math.max(1, Math.min(u.hp + saved * Math.round(st.hp * 0.3), squadHpCap(s)));
      if (fell > 0) {
        report.losses!.push({ name: s.name, typeId: s.typeId, lost, men: s.men, size, fate: 'fought', saved });
        ex.menLost = (ex.menLost ?? 0) + lost;
      }
      s.morale = Math.max(1, u.morale + (result === 'victory' ? 12 : -5));
      if (u.status === 'fled') {
        s.morale = Math.max(1, Math.round(st.morale * 0.25));
        report.routed.push(s.name);
      }
    }
    s.morale = Math.min(st.morale, s.morale);
    s.fatigue = Math.min(100, s.fatigue + 6);
    const hits = b.hitsTaken[u.uid] ?? 0;
    s.armorCondition = Math.max(0.3, s.armorCondition - hits * 0.05);
    if (UNIT_TYPES[s.typeId].shot) {
      report.boltsUsed += Math.max(0, s.ammo - Math.max(0, u.ammo));
      s.ammo = Math.max(0, u.ammo);
    }
    report.xp.push({ name: s.name, xp: u.xp });
    const lv = gainXp(g, s, u.xp);
    if (lv) report.levelUps.push(lv);
  }
  // Refill quivers from spare bolts.
  for (const s of armySoldiers(g)) {
    const def = UNIT_TYPES[s.typeId];
    if (!def.shot?.ammo) continue;
    while (s.ammo < def.shot.ammo && ex.supplies.bolts > 0) {
      ex.supplies.bolts--;
      s.ammo = Math.min(def.shot.ammo, s.ammo + 6);
    }
  }
  if (result === 'victory') {
    const enc = encounterById(b.setup.encounterId ?? 'goblin_scouts');
    const loot = exRng(ex, (r) => ({
      silver: r.int(...enc.loot.silver) + b.units.filter((u) => u.faction === 'enemy' && u.status === 'dead').reduce((sum, u) => sum + (UNIT_TYPES[u.typeId].value ?? 0) * 2, 0),
      iron: enc.loot.iron ? r.int(...enc.loot.iron) : 0,
      timber: enc.loot.timber ? r.int(...enc.loot.timber) : 0,
      trophies: enc.loot.trophies ?? 0,
    }));
    for (const k of Object.keys(loot) as (keyof Resources)[]) ex.loot[k] += loot[k];
    report.loot = loot;
    if (objective) ex.objectiveDone = true;
  }
  const n = node(ex, ex.current);
  if (result === 'victory') addLog(ex, `Victory: ${title}.`, 'good');
  else if (result === 'retreat') addLog(ex, `The army withdrew from ${n.name}.`, 'bad');
  else addLog(ex, `Defeat at ${n.name}.`, 'bad');
  ex.pending = { kind: 'battleResult', report };
  // An army with nobody able to fight goes home.
  if (armySoldiers(g).length === 0) report.result = 'defeat';
  return report;
}

// ---------------------------------------------------------------- return

export function returnHome(g: GameState, outcome: 'success' | 'retreat' | 'defeat'): ExpeditionReport {
  const ex = g.expedition!;
  const c = campaignById(ex.campaignId);
  const loot = { ...ex.loot };
  if (outcome === 'defeat') for (const k of Object.keys(loot) as (keyof Resources)[]) loot[k] = Math.floor(loot[k] / 2);
  const reward = outcome === 'success' ? c.reward : {};
  for (const k of Object.keys(loot) as (keyof Resources)[]) g.resources[k] += loot[k] + (reward[k] ?? 0);
  let buyback = 0;
  for (const k of Object.keys(ex.supplies) as SupplyId[]) {
    buyback += ex.supplies[k] * SUPPLIES[k].cost * effect(g, 'quartermaster', 'buyback');
  }
  buyback = Math.floor(buyback);
  g.resources.silver += buyback;
  const stipend = effect(g, 'command', 'stipend');
  g.resources.silver += stipend;
  const survivors = armySoldiers(g);
  for (const s of g.roster) {
    const st = soldierStats(s);
    // Home again, the survivors heal fully. The fallen are only replaced by reinforcements.
    if (ex.army.includes(s.id)) {
      s.expeditions++;
      s.hp = squadHpCap(s);
      s.fatigue = 0;
      s.morale = Math.min(st.morale, s.morale + (outcome === 'success' ? 25 : 12));
    } else {
      if (!s.recovering) s.morale = Math.min(st.morale, s.morale + 20);
      s.recovering = false;
      s.hp = squadHpCap(s);
    }
    s.drilled = false;
    if (UNIT_TYPES[s.typeId].shot?.ammo) s.ammo = UNIT_TYPES[s.typeId].shot!.ammo!;
  }
  if (outcome === 'success') g.completed[c.id] = (g.completed[c.id] ?? 0) + 1;
  const fallenNow = g.fallen.filter((f) => f.cycle === g.cycle).map((f) => f.name);
  const report: ExpeditionReport = {
    campaignId: c.id,
    outcome,
    loot,
    reward,
    buyback,
    stipend,
    fallen: fallenNow,
    survivors: survivors.map((s) => s.name),
    strength: survivors.map((s) => ({ name: s.name, typeId: s.typeId, men: s.men, size: squadSize(s.typeId) })),
    menLost: ex.menLost ?? 0,
    marches: ex.marches,
    battles: ex.battles,
  };
  chronicle(
    g,
    outcome === 'success'
      ? `The company returns victorious from ${c.name}.`
      : outcome === 'retreat'
        ? `The company retreats from ${c.name}, the objective unmet.`
        : `The company is broken in ${c.name}. Survivors straggle home.`,
    outcome === 'success' ? 'good' : 'bad',
  );
  g.expedition = null;
  g.lastReport = report;
  rollRecruits(g);
  return report;
}

export function nodeTypeName(t: NodeType) {
  return NODE_INFO[t].name;
}
