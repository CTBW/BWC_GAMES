// Automated player for the whole loop. Used by tests, the balance simulator
// and the in-game debug API. It makes reasonable, not optimal, decisions.

import { Rng } from '../core/rng';
import type { SupplyId } from '../core/types';
import { Battle } from '../battle/battle';
import { runEnemyAi, runPlayerAuto } from '../battle/ai';
import { buildBattle } from '../battle/setup';
import { campaignById } from '../data/campaigns';
import { EVENTS } from '../data/events';
import {
  armyCommand,
  armyLimits,
  availableCampaigns,
  eligibility,
  grantLeave,
  hire,
  missingMen,
  recommendedSupplies,
  reinforce,
  reinforceCost,
  rosterCap,
  supplyCostTotal,
  supplyWeight,
  treat,
  wagonCapacity,
  type GameState,
} from '../meta/game';
import { commandCost, soldierStats } from '../meta/soldier';
import {
  applyBattle,
  armySoldiers,
  battleArmy,
  campRest,
  campWatch,
  chooseEvent,
  choiceAvailable,
  dismissPending,
  march,
  nextNodes,
  returnHome,
  searchSpot,
  prepareNight,
  startExpedition,
  survivalBonus,
} from './expedition';

export function autoPrepare(g: GameState, rng: Rng): boolean {
  // Bring thinned squads back to strength first (veterans first), keeping silver for supplies.
  for (const s of g.roster.slice().sort((a, b) => b.level - a.level)) {
    while (missingMen(s) > 0 && g.resources.silver - reinforceCost(g, s) >= 70) {
      if (!reinforce(g, s.id)) break;
    }
  }
  // Keep a roster of seven or eight.
  for (const r of g.recruits.slice()) {
    if (g.roster.length >= Math.min(8, rosterCap(g))) break;
    if (g.resources.silver > 150) hire(g, r.id);
  }
  // Rest the badly shaken and treat serious injuries when there is spare silver.
  for (const s of g.roster) {
    if (s.morale < soldierStats(s).morale * 0.4 && g.resources.silver > 140) grantLeave(g, s.id);
    for (const inj of s.injuries.slice()) if (g.resources.silver > 160 && !s.recovering) treat(g, s.id, inj);
  }
  const c = availableCampaigns(g)[0];
  const lim = armyLimits(g, c);
  const order = g.roster
    .filter((s) => eligibility(g, s, c).ok)
    .sort((a, b) => b.level - a.level || b.hp - a.hp);
  const army: string[] = [];
  const want = { footman: 2, spearman: 2, crossbowman: 2 } as Record<string, number>;
  // The royal guard stands in the line like footmen.
  const role = (t: string) => (t === 'collie_guard' ? 'footman' : t);
  for (const s of order) {
    if (army.length >= lim.slots) break;
    if ((want[role(s.typeId)] ?? 0) <= 0) continue;
    if (armyCommand(g, army) + commandCost(s) > lim.command) continue;
    army.push(s.id);
    want[role(s.typeId)]--;
  }
  for (const s of order) {
    if (army.includes(s.id) || army.length >= lim.slots) continue;
    if (armyCommand(g, army) + commandCost(s) <= lim.command) army.push(s.id);
  }
  if (army.length < 3) return false;
  const xb = army.filter((id) => g.roster.find((s) => s.id === id)?.typeId === 'crossbowman').length;
  const sup = recommendedSupplies(army.length, xb, wagonCapacity(g), c.stages + 1);
  while (supplyWeight(sup) > wagonCapacity(g)) sup.rations--;
  while (supplyCostTotal(g, sup) > g.resources.silver && sup.rations > 4) sup.rations--;
  while (supplyCostTotal(g, sup) > g.resources.silver) {
    const k = (['tools', 'torches', 'bandages', 'bolts'] as SupplyId[]).find((x) => sup[x] > 0);
    if (!k) break;
    sup[k]--;
  }
  void rng;
  startExpedition(g, c.id, army, sup, supplyCostTotal(g, sup));
  return true;
}

export function autoBattle(b: Battle, maxTurns = 30) {
  b.begin(runEnemyAi);
  while (!b.isOver() && b.turn <= maxTurns) {
    runPlayerAuto(b);
    if (b.isOver()) break;
    b.endTurn(runEnemyAi);
    // A sensible captain pulls out of a fight he has clearly lost, to save the company.
    if (!b.isOver() && b.phase === 'player') {
      const company = b.company();
      const foes = b.active('enemy').length;
      if (company.length && (b.strength('player') < 0.3 || (company.length <= 2 && foes >= company.length * 3))) b.retreat();
    }
  }
  if (!b.isOver()) b.retreat();
}

/** Play the current expedition to its end. Returns the outcome. */
/** The autoplayer turns home when its squads hold fewer than this share of the soldiers who marched out. */
export const RETREAT_STRENGTH = 0.4;

export function autoExpedition(g: GameState, rng: Rng, opts: { retreatBelow?: number; retreatStrength?: number } = {}) {
  let guard = 0;
  while (g.expedition && guard++ < 200) {
    const ex = g.expedition;
    const p = ex.pending;
    if (!p) {
      // Retreat if the army is in tatters: too few squads, or too few soldiers
      // left in them (unless the objective is the next march).
      const alive = ex.army.length;
      if (alive <= (opts.retreatBelow ?? 1)) return returnHome(g, 'retreat').outcome;
      const next = nextNodes(ex);
      const men = armySoldiers(g).reduce((n, s) => n + s.men, 0);
      const objectiveNext = next.some((n) => n.type === 'objective');
      if (ex.startMen && men < ex.startMen * (opts.retreatStrength ?? RETREAT_STRENGTH) && !objectiveNext) return returnHome(g, 'retreat').outcome;
      if (!next.length) return returnHome(g, ex.objectiveDone ? 'success' : 'retreat').outcome;
      const prefer = next.slice().sort((a, b) => score(b) - score(a));
      march(g, prefer[0].id);
      continue;
    }
    switch (p.kind) {
      case 'arrive':
      case 'scout':
        dismissPending(g);
        break;
      case 'event': {
        if (!p.result) {
          const ev = EVENTS.find((e) => e.id === p.eventId)!;
          const idx = ev.choices.findIndex((ch) => choiceAvailable(g, ch).ok);
          chooseEvent(g, Math.max(0, idx));
        }
        dismissPending(g);
        break;
      }
      case 'camp':
        if (ex.supplies.torches > 0) campWatch(g);
        campRest(g);
        if (g.expedition?.pending?.kind === 'camp') dismissPending(g);
        break;
      case 'village':
        for (let i = 0; i < p.spots.length; i++) {
          if (g.expedition?.pending?.kind !== 'village') break;
          if (!p.spots[i].locked || ex.supplies.tools > 0) searchSpot(g, i);
        }
        if (g.expedition?.pending?.kind === 'village') dismissPending(g);
        break;
      case 'battle': {
        const night = prepareNight(g);
        const setup = buildBattle(p.roll, battleArmy(g), { survivalBonus: survivalBonus(g), title: p.title, darkness: night.darkness });
        const b = new Battle(setup);
        autoBattle(b);
        applyBattle(g, b, p.title, p.objective);
        break;
      }
      case 'battleResult':
        dismissPending(g);
        break;
      case 'complete':
        return returnHome(g, 'success').outcome;
    }
  }
  void rng;
  // A defeat sends the army home from inside dismissPending; report how it ended.
  return g.expedition ? returnHome(g, 'retreat').outcome : (g.lastReport?.outcome ?? 'done');

  function score(n: { type: string }) {
    const pref: Record<string, number> = { camp: 3, village: 2.5, event: 2, scout: 2.2, battle: 1, ambush: 1, objective: 5 };
    return (pref[n.type] ?? 1) + rng.next();
  }
}

export { campaignById };
