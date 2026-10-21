import { Rng } from '../core/rng';
import type { Resources, SupplyId } from '../core/types';
import { BUILDINGS, buildingById } from '../data/buildings';
import { campaignById, type CampaignDef } from '../data/campaigns';
import { EQUIPMENT, INJURIES, SUPPLIES } from '../data/items';
import { PLAYER_TYPES, UNIT_TYPES, squadSize } from '../data/units';
import { squadName } from '../battle/squad';
import type { Expedition, ExpeditionReport } from '../campaign/expedition';
import {
  canPromote,
  commandCost,
  levelForXp,
  newSoldier,
  soldierStats,
  squadHpCap,
  type Soldier,
} from './soldier';

export const SAVE_VERSION = 1;

export interface FallenRecord {
  name: string;
  typeId: string;
  level: number;
  kills: number;
  battles: number;
  cause: string;
  cycle: number;
}

export interface GameState {
  version: number;
  seed: number;
  rng: number;
  nextId: number;
  /** Number of expeditions launched so far. */
  cycle: number;
  resources: Resources;
  buildings: Record<string, number>;
  roster: Soldier[];
  recruits: Soldier[];
  fallen: FallenRecord[];
  expedition: Expedition | null;
  completed: Record<string, number>;
  chronicle: { cycle: number; text: string; tone?: 'good' | 'bad' | 'neutral' }[];
  lastReport: ExpeditionReport | null;
  /** One-time tutorial and story flags. */
  flags?: Record<string, boolean>;
}

export function useRng<T>(g: GameState, fn: (rng: Rng) => T): T {
  const rng = new Rng(g.rng);
  const out = fn(rng);
  g.rng = rng.state;
  return out;
}

export function nextId(g: GameState) {
  return () => `u${g.nextId++}`;
}

export function newGame(seed = Date.now() % 2147483647): GameState {
  const g: GameState = {
    version: SAVE_VERSION,
    seed,
    rng: new Rng(seed).state,
    nextId: 1,
    cycle: 0,
    resources: { silver: 220, timber: 2, iron: 1, trophies: 0 },
    buildings: Object.fromEntries(BUILDINGS.map((b) => [b.id, 1])),
    roster: [],
    recruits: [],
    fallen: [],
    expedition: null,
    completed: {},
    chronicle: [],
    lastReport: null,
  };
  useRng(g, (rng) => {
    for (const t of ['footman', 'footman', 'spearman', 'spearman', 'crossbowman', 'crossbowman']) {
      g.roster.push(newSoldier(rng, t, 1, nextId(g), 0));
    }
  });
  rollRecruits(g);
  chronicle(g, 'The Amberfeld Company makes camp at the edge of the Hillsvain Woods. Six squads answer the muster.');
  return g;
}

/**
 * Bring a loaded save up to the squad rules. Saves from before squads stored one
 * soldier's HP and no `men`: each entry becomes a full squad with the same share
 * of health. Every save is also clamped so `men` and `hp` stay consistent.
 */
export function migrateSave(g: GameState): GameState {
  const fix = (s: Soldier) => {
    if (!s || !UNIT_TYPES[s.typeId]) return;
    const size = squadSize(s.typeId);
    if (!Array.isArray(s.injuries)) s.injuries = [];
    const per = soldierStats(s).hp;
    if (typeof s.men !== 'number' || !Number.isFinite(s.men)) {
      s.men = size;
      const old = Number.isFinite(s.hp) && s.hp > 0 ? s.hp : per;
      s.hp = Math.round(Math.min(old * s.men, per * s.men));
    }
    s.men = Math.max(1, Math.min(size, Math.round(s.men)));
    if (!Number.isFinite(s.hp) || s.hp <= 0) s.hp = per * s.men;
    s.hp = Math.max(1, Math.min(Math.round(s.hp), squadHpCap(s)));
  };
  g.roster = (g.roster ?? []).filter((s) => s && UNIT_TYPES[s.typeId]);
  g.recruits = (g.recruits ?? []).filter((s) => s && UNIT_TYPES[s.typeId]);
  for (const s of g.roster) fix(s);
  for (const s of g.recruits) fix(s);
  // The marching army is a list of roster ids; drop any that no longer exist.
  if (g.expedition) g.expedition.army = g.expedition.army.filter((id) => g.roster.some((s) => s.id === id));
  return g;
}

export function chronicle(g: GameState, text: string, tone: 'good' | 'bad' | 'neutral' = 'neutral') {
  g.chronicle.unshift({ cycle: g.cycle, text, tone });
  if (g.chronicle.length > 60) g.chronicle.length = 60;
}

// ---------------------------------------------------------------- buildings

export function level(g: GameState, id: string): number {
  return g.buildings[id] ?? 1;
}

export function effect(g: GameState, id: string, key: string): number {
  const b = buildingById(id);
  return b.levels[level(g, id) - 1].effects[key] ?? 0;
}

export function nextLevel(g: GameState, id: string) {
  const b = buildingById(id);
  return b.levels[level(g, id)];
}

export function canAfford(g: GameState, cost: Partial<Resources>): boolean {
  return (Object.keys(cost) as (keyof Resources)[]).every((k) => g.resources[k] >= (cost[k] ?? 0));
}

export function pay(g: GameState, cost: Partial<Resources>) {
  for (const k of Object.keys(cost) as (keyof Resources)[]) g.resources[k] -= cost[k] ?? 0;
}

export function upgradeBuilding(g: GameState, id: string): boolean {
  const nl = nextLevel(g, id);
  if (!nl || !canAfford(g, nl.cost)) return false;
  pay(g, nl.cost);
  g.buildings[id] = nl.level;
  chronicle(g, `The ${buildingById(id).name.toLowerCase()} is rebuilt as the ${nl.name}.`, 'good');
  return true;
}

// ---------------------------------------------------------------- recruits

/** Chance that a recruit squad is the elite Border Collie Royal Guard (Barracks level 2+). */
export const ELITE_RECRUIT_CHANCE = 0.22;

export function rollRecruits(g: GameState) {
  const pool = effect(g, 'barracks', 'pool');
  const vet = effect(g, 'barracks', 'veteranChance');
  const elite = level(g, 'barracks') >= 2;
  g.recruits = useRng(g, (rng) => {
    const out: Soldier[] = [];
    for (let i = 0; i < pool; i++) {
      const t = elite && rng.chance(ELITE_RECRUIT_CHANCE) ? 'collie_guard' : rng.pick(PLAYER_TYPES);
      const lvl = rng.chance(vet) ? (rng.chance(vet * 0.4) ? 3 : 2) : 1;
      out.push(newSoldier(rng, t, lvl, nextId(g), g.cycle));
    }
    // A thin company draws volunteers from the steadings: one joins for free.
    if (g.roster.length < 6) {
      const v = newSoldier(rng, 'spearman', 1, nextId(g), g.cycle);
      v.volunteer = true;
      out.unshift(v);
    }
    return out;
  });
}

export function recruitCost(s: Soldier): number {
  if (s.volunteer) return 0;
  return Math.round(UNIT_TYPES[s.typeId].recruitCost * (1 + (s.level - 1) * 0.6));
}

export function rosterCap(g: GameState) {
  return effect(g, 'barracks', 'rosterCap');
}

export function hire(g: GameState, id: string): boolean {
  const s = g.recruits.find((r) => r.id === id);
  if (!s) return false;
  const cost = recruitCost(s);
  if (g.resources.silver < cost || g.roster.length >= rosterCap(g)) return false;
  g.resources.silver -= cost;
  g.recruits = g.recruits.filter((r) => r.id !== id);
  g.roster.push(s);
  chronicle(g, `${s.name} signs on with ${numberWord(s.men)} ${UNIT_TYPES[s.typeId].plural.toLowerCase()}.`);
  return true;
}

export function dismiss(g: GameState, id: string): boolean {
  const s = g.roster.find((r) => r.id === id);
  if (!s || g.roster.length <= 1) return false;
  g.roster = g.roster.filter((r) => r.id !== id);
  chronicle(g, `${squadName(s)} are discharged from the company.`);
  return true;
}

// ---------------------------------------------------------------- reinforcements

export function numberWord(n: number): string {
  return ['no', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight'][n] ?? String(n);
}

/** Soldiers a squad is short of full strength. */
export function missingMen(s: Soldier): number {
  return Math.max(0, squadSize(s.typeId) - s.men);
}

/**
 * Silver for one replacement soldier: a share of the squad's hiring price,
 * a little more for seasoned squads (the newcomer is drilled up to their rank).
 */
export function reinforceCost(g: GameState, s: Soldier): number {
  void g;
  const def = UNIT_TYPES[s.typeId];
  return Math.ceil((def.recruitCost / squadSize(s.typeId)) * 0.8 * (1 + (s.level - 1) * 0.25));
}

export function canReinforce(g: GameState, s: Soldier, count = 1): { ok: boolean; reason?: string } {
  if (g.expedition) return { ok: false, reason: 'Only at the Barracks, between expeditions' };
  const missing = missingMen(s);
  if (missing <= 0) return { ok: false, reason: 'The squad is at full strength' };
  const n = Math.min(count, missing);
  const cost = reinforceCost(g, s) * n;
  if (g.resources.silver < cost) return { ok: false, reason: `Needs ${cost} silver` };
  return { ok: true };
}

/**
 * Fill a squad's empty places (one soldier by default; `count` for more). New
 * soldiers arrive fit, each with a full share of HP. The only way to raise `men`.
 */
export function reinforce(g: GameState, id: string, count = 1): boolean {
  const s = g.roster.find((r) => r.id === id);
  if (!s || !canReinforce(g, s, count).ok) return false;
  const n = Math.min(count, missingMen(s));
  const per = soldierStats(s).hp;
  g.resources.silver -= reinforceCost(g, s) * n;
  s.men += n;
  s.hp = Math.min(squadHpCap(s), s.hp + per * n);
  const def = UNIT_TYPES[s.typeId];
  chronicle(
    g,
    `${n === 1 ? `A new ${def.name.toLowerCase()} joins` : `${numberWord(n)[0].toUpperCase()}${numberWord(n).slice(1)} new ${def.plural.toLowerCase()} join`} ${s.name}'s squad (${s.men}/${squadSize(s.typeId)}).`,
  );
  return true;
}

// ---------------------------------------------------------------- training

export function drillCost(g: GameState, s: Soldier) {
  return effect(g, 'training', 'drillCost') + (s.level - 1) * 15;
}

export function canDrill(g: GameState, s: Soldier): { ok: boolean; reason?: string } {
  if (s.drilled) return { ok: false, reason: 'Already drilled this cycle' };
  if (s.level >= effect(g, 'training', 'drillMaxLevel')) return { ok: false, reason: 'Yard cannot teach this rank' };
  if (g.resources.silver < drillCost(g, s)) return { ok: false, reason: 'Not enough silver' };
  return { ok: true };
}

export function drill(g: GameState, id: string): boolean {
  const s = g.roster.find((r) => r.id === id)!;
  if (!canDrill(g, s).ok) return false;
  g.resources.silver -= drillCost(g, s);
  s.drilled = true;
  gainXp(g, s, 10);
  return true;
}

export function gainXp(g: GameState, s: Soldier, xp: number): string | null {
  const before = s.level;
  s.xp += xp;
  const lvl = levelForXp(s.xp);
  if (lvl > before) {
    const old = soldierStats(s);
    s.level = lvl;
    const now = soldierStats(s);
    // Every soldier still serving gains the new rank's toughness.
    s.hp = Math.min(squadHpCap(s), s.hp + (now.hp - old.hp) * s.men);
    s.morale = Math.min(now.morale, s.morale + (now.morale - old.morale));
    const msg = `${squadName(s)} rise to ${rankLabel(lvl)}.`;
    chronicle(g, msg, 'good');
    return msg;
  }
  return null;
}

function rankLabel(lvl: number) {
  return ['Recruit', 'Soldier', 'Veteran', 'Sergeant', 'Champion'][lvl - 1];
}

export function promoteCost(g: GameState) {
  return { silver: effect(g, 'training', 'promoteCost'), iron: 1 };
}

export function canPromoteHere(g: GameState, s: Soldier): { ok: boolean; reason?: string } {
  if (!canPromote(s)) return { ok: false, reason: s.promoted ? 'Already promoted' : 'Needs Veteran rank' };
  if (!effect(g, 'training', 'promote')) return { ok: false, reason: 'Needs Training Yard level 2' };
  if (!canAfford(g, promoteCost(g))) return { ok: false, reason: 'Cannot afford' };
  return { ok: true };
}

export function promote(g: GameState, id: string): boolean {
  const s = g.roster.find((r) => r.id === id)!;
  if (!canPromoteHere(g, s).ok) return false;
  pay(g, promoteCost(g));
  s.promoted = true;
  chronicle(g, `${squadName(s)} are promoted and learn a new skill.`, 'good');
  return true;
}

// ---------------------------------------------------------------- armoury

export function equipLine(s: Soldier, slot: 'weapon' | 'armor') {
  const def = UNIT_TYPES[s.typeId];
  const lineId = slot === 'weapon' ? def.weaponLine : def.armorLine;
  return lineId ? EQUIPMENT[lineId] : undefined;
}

export function nextEquip(g: GameState, s: Soldier, slot: 'weapon' | 'armor') {
  const line = equipLine(s, slot);
  const cur = slot === 'weapon' ? s.weaponTier : s.armorTier;
  return line?.tiers[cur];
}

export function canBuyEquip(g: GameState, s: Soldier, slot: 'weapon' | 'armor'): { ok: boolean; reason?: string } {
  const next = nextEquip(g, s, slot);
  if (!next) return { ok: false, reason: 'Best available' };
  if (effect(g, 'armoury', 'tier') < next.tier) return { ok: false, reason: `Needs Armoury level ${next.armoryLevel}` };
  if (!canAfford(g, next.cost)) return { ok: false, reason: 'Cannot afford' };
  return { ok: true };
}

export function buyEquip(g: GameState, id: string, slot: 'weapon' | 'armor'): boolean {
  const s = g.roster.find((r) => r.id === id)!;
  if (!canBuyEquip(g, s, slot).ok) return false;
  const next = nextEquip(g, s, slot)!;
  pay(g, next.cost);
  const wasFull = s.hp >= squadHpCap(s);
  if (slot === 'weapon') s.weaponTier++;
  else {
    s.armorTier++;
    s.armorCondition = 1;
  }
  // Armour that adds toughness tops up a squad resting at full health.
  if (wasFull) s.hp = squadHpCap(s);
  const many = /^coat of /i.test(next.name) ? next.name.replace(/^coat/i, 'coats') : `${next.name}s`;
  chronicle(g, `${squadName(s)} are issued ${many.toLowerCase()}.`);
  return true;
}

export function repairCost(g: GameState, s: Soldier) {
  return Math.ceil((1 - s.armorCondition) * 60 * effect(g, 'armoury', 'repairCost'));
}

export function repair(g: GameState, id: string): boolean {
  const s = g.roster.find((r) => r.id === id)!;
  const c = repairCost(g, s);
  if (c <= 0 || g.resources.silver < c) return false;
  g.resources.silver -= c;
  s.armorCondition = 1;
  return true;
}

// ---------------------------------------------------------------- infirmary / leave

export function treatCost(g: GameState, injuryId: string) {
  return effect(g, 'infirmary', 'treatCost') * INJURIES[injuryId].severity;
}

export function treat(g: GameState, id: string, injuryId: string): boolean {
  const s = g.roster.find((r) => r.id === id)!;
  const c = treatCost(g, injuryId);
  if (!s.injuries.includes(injuryId) || g.resources.silver < c) return false;
  g.resources.silver -= c;
  const wasFull = s.hp >= squadHpCap(s);
  s.injuries = s.injuries.filter((x) => x !== injuryId);
  if (wasFull) s.hp = squadHpCap(s);
  s.recovering = true;
  chronicle(g, `The surgeons treat ${s.name}'s ${INJURIES[injuryId].name.toLowerCase()}.`);
  return true;
}

export function leaveCost(g: GameState) {
  return effect(g, 'barracks', 'leaveCost');
}

export function grantLeave(g: GameState, id: string): boolean {
  const s = g.roster.find((r) => r.id === id)!;
  const max = soldierStats(s).morale;
  if (s.morale >= max || g.resources.silver < leaveCost(g)) return false;
  g.resources.silver -= leaveCost(g);
  s.morale = max;
  s.recovering = true;
  return true;
}

// ---------------------------------------------------------------- expedition limits

export function armyLimits(g: GameState, c: CampaignDef) {
  return {
    slots: c.unitSlots + effect(g, 'command', 'slotBonus'),
    command: c.commandPoints + effect(g, 'command', 'commandBonus'),
  };
}

export function eligibility(
  g: GameState,
  s: Soldier,
  c: CampaignDef,
): { ok: boolean; reluctant: boolean; reason?: string } {
  if (s.recovering) return { ok: false, reluctant: false, reason: 'Recovering' };
  if (s.level > c.refuseAbove) return { ok: false, reluctant: false, reason: `Refuses: beneath a ${rankLabel(s.level)}` };
  const st = soldierStats(s);
  if (s.morale < st.morale * 0.2) return { ok: false, reluctant: false, reason: 'Morale broken' };
  return { ok: true, reluctant: s.level > c.reluctantAbove };
}

export function armyCommand(g: GameState, ids: string[]): number {
  return ids.reduce((sum, id) => {
    const s = g.roster.find((r) => r.id === id);
    return sum + (s ? commandCost(s) : 0);
  }, 0);
}

export function supplyPrice(g: GameState, id: SupplyId): number {
  return Math.max(1, Math.round(SUPPLIES[id].cost * effect(g, 'quartermaster', 'priceMult')));
}

export function wagonCapacity(g: GameState): number {
  return effect(g, 'quartermaster', 'capacity');
}

export function supplyWeight(supplies: Partial<Record<SupplyId, number>>): number {
  return (Object.keys(supplies) as SupplyId[]).reduce((s, k) => s + (supplies[k] ?? 0) * SUPPLIES[k].weight, 0);
}

export function supplyCostTotal(g: GameState, supplies: Partial<Record<SupplyId, number>>): number {
  return (Object.keys(supplies) as SupplyId[]).reduce((s, k) => s + (supplies[k] ?? 0) * supplyPrice(g, k), 0);
}

export function availableCampaigns(g: GameState) {
  return ['hillsvain_raids'].map(campaignById).filter((c) => level(g, 'command') >= c.requiresCommandLevel);
}

/**
 * The quartermaster's advice: rations for every march plus one camp meal,
 * then trimmed until it fits the wagon. Marches = campaign stages + 1.
 */
export function recommendedSupplies(armySize: number, crossbows: number, capacity = 30, marches = 6): Record<SupplyId, number> {
  const sup: Record<SupplyId, number> = {
    rations: Math.ceil(armySize / 2) * marches + armySize,
    bandages: 3,
    bolts: Math.max(0, crossbows * 2),
    torches: 2,
    tools: 1,
  };
  const trim: SupplyId[] = ['torches', 'bandages', 'bolts', 'tools', 'rations'];
  let guard = 0;
  while (supplyWeight(sup) > capacity && guard++ < 200) {
    const k = trim.find((t) => sup[t] > (t === 'rations' ? Math.ceil(armySize / 2) * marches : t === 'torches' || t === 'bandages' ? 1 : 0));
    if (!k) break;
    sup[k]--;
  }
  return sup;
}

export { BUILDINGS };
