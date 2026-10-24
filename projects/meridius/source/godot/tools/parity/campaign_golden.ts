// ARCHIVED (21 Oct 2026): do not re-run. The original is archived and the Godot
// rules have since changed on purpose; the driven runs and autoplay campaigns
// are re-recorded by the port (MERIDIUS_RECORD=1 tools/test.sh
// test_campaign_parity, which carries a port of this driver).
//
// Golden campaign data from the original (src/campaign/expedition.ts and
// autoplay.ts), recording the full GameState after every step:
// - generateExpedition for many seeds, with nodeView of every node;
// - driven runs: start, march, events and choices, camps, villages, scouting,
//   bandages, effects, battles (scripted outcomes that need no AI, or fought
//   out by the AI on both sides), the return home;
// - complete autoplay campaigns (autoPrepare + autoExpedition + upgrades over
//   several expeditions), mirroring scripts/simcampaign.ts.
//   cd projects/meridius/source/game && npx vite-node ../godot/tools/parity/campaign_golden.ts
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Rng } from '../../../game/src/core/rng';
import { EVENTS } from '../../../game/src/data/events';
import { UNIT_TYPES } from '../../../game/src/data/units';
import { Battle } from '../../../game/src/battle/battle';
import { aliveFor } from '../../../game/src/battle/squad';
import { buildBattle } from '../../../game/src/battle/setup';
import * as G from '../../../game/src/meta/game';
import type { GameState } from '../../../game/src/meta/game';
import { soldierStats, squadHpCap } from '../../../game/src/meta/soldier';
import * as X from '../../../game/src/campaign/expedition';
import * as A from '../../../game/src/campaign/autoplay';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '..', '..', 'tests', 'fixtures', 'golden');
mkdirSync(out, { recursive: true });
const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v));

// ---------------------------------------------------------------- generation
const SUP = { rations: 10, bandages: 2, bolts: 2, torches: 1, tools: 1 };
const generated: unknown[] = [];
for (let seed = 1; seed < 40; seed++) {
  const g = G.newGame(seed);
  const army = g.roster.slice(0, 5).map((s) => s.id);
  const ex = X.generateExpedition(g, 'hillsvain_raids', army, SUP);
  const views = ex.nodes.map((n) => X.nodeView(n));
  const shown = clone(ex);
  for (const n of shown.nodes) {
    n.revealed = true;
    n.scouted = true;
  }
  const viewsScouted = shown.nodes.map((n) => X.nodeView(n));
  generated.push({ seed, army, ex: clone(ex), gameRng: g.rng, views, viewsScouted, nodeTypeNames: ['start', 'battle', 'ambush', 'scout', 'village', 'event', 'camp', 'objective'].map((t) => X.nodeTypeName(t as any)) });
}

// ---------------------------------------------------------------- driven runs
type Step = { op: string; args: unknown[]; ret: unknown; state: unknown };

function battleOf(g: GameState) {
  const p = g.expedition!.pending as Extract<X.Pending, { kind: 'battle' }>;
  const night = X.prepareNight(g);
  const setup = buildBattle(p.roll, X.battleArmy(g), { survivalBonus: X.survivalBonus(g), title: p.title, darkness: night.darkness });
  return { p, night, b: new Battle(setup) };
}

function queries(g: GameState) {
  const ex = g.expedition;
  if (!ex) return { none: true };
  const p = ex.pending;
  return {
    next: X.nextNodes(ex).map((n) => n.id),
    canMarch: ex.nodes.map((n) => X.canMarch(g, n.id)),
    views: ex.nodes.map((n) => X.nodeView(n)),
    rationCost: X.rationCost(g),
    survivalBonus: X.survivalBonus(g),
    army: X.armySoldiers(g).map((s) => s.id),
    battleArmy: X.battleArmy(g),
    bandageHeal: X.armySoldiers(g).map((s) => X.bandageHeal(s)),
    choices: p && p.kind === 'event' ? EVENTS.find((e) => e.id === p.eventId)!.choices.map((ch) => X.choiceAvailable(g, ch)) : null,
  };
}

function run(g: GameState, op: string, a: any[]): unknown {
  switch (op) {
    case 'startExpedition': X.startExpedition(g, a[0], a[1], a[2], a[3]); return null;
    case 'march': return X.march(g, a[0]);
    case 'dismissPending': X.dismissPending(g); return null;
    case 'chooseEvent': X.chooseEvent(g, a[0]); return null;
    case 'campRest': X.campRest(g); return null;
    case 'campWatch': X.campWatch(g); return null;
    case 'campRepair': X.campRepair(g); return null;
    case 'useBandage': return X.useBandage(g, a[0]);
    case 'searchSpot': X.searchSpot(g, a[0]); return null;
    case 'hurtSquad': return X.hurtSquad(g, g.roster.find((s) => s.id === a[0])!, a[1], (who, verb) => `Test: ${who} ${verb}.`);
    case 'applyEffect': {
      const subject = a[1] ? g.roster.find((s) => s.id === a[1]) : undefined;
      return a[2] ? X.applyEffect(g, a[0], subject, a[2]) : X.applyEffect(g, a[0], subject);
    }
    case 'battleAuto': {
      const { p, b } = battleOf(g);
      A.autoBattle(b);
      return { report: X.applyBattle(g, b, p.title, p.objective), turn: b.turn, result: b.result };
    }
    case 'battleScripted': {
      const { p, b } = battleOf(g);
      for (const c of a[0] as any[]) {
        const u = b.unit(c.uid);
        for (const k of ['status', 'hp', 'alive', 'kills', 'xp', 'morale', 'ammo']) if (c[k] !== undefined) (u as any)[k] = c[k];
        b.hitsTaken[c.uid] = c.hits;
      }
      b.result = a[1];
      b.phase = 'over';
      return X.applyBattle(g, b, p.title, p.objective);
    }
    case 'returnHome': return X.returnHome(g, a[0]);
    case 'reinforce': return G.reinforce(g, a[0], a[1]);
    case 'hire': return G.hire(g, a[0]);
    case 'upgradeBuilding': return G.upgradeBuilding(g, a[0]);
    case 'treat': return G.treat(g, a[0], a[1]);
    case 'setRes': g.resources[a[0] as 'silver'] = a[1]; return null;
    case 'autoPrepare': return A.autoPrepare(g, new Rng(a[0]));
    case 'query': return queries(g);
  }
  throw new Error(op);
}

/** Scripted battle outcome: a fate for every squad that needs no AI. */
function scriptOutcome(g: GameState, drv: Rng): [unknown[], string] {
  const ex = g.expedition!;
  const p = ex.pending as Extract<X.Pending, { kind: 'battle' }>;
  // Mirror battleOf without touching the game: build on copies to read the units.
  const copy = clone(g);
  const night = X.prepareNight(copy);
  const setup = buildBattle(clone(p.roll), X.battleArmy(copy), { survivalBonus: X.survivalBonus(copy), title: p.title, darkness: night.darkness });
  const changes: unknown[] = [];
  for (const u of setup.units) {
    if (u.status === 'reserve' && drv.chance(0.6)) continue;
    const roll = drv.next();
    const c: any = { uid: u.uid, hits: drv.int(0, 6) };
    if (u.faction === 'player') {
      if (roll < 0.12) Object.assign(c, { status: 'dead', hp: 0, alive: 0 });
      else if (roll < 0.27) Object.assign(c, { status: 'downed', hp: 0, alive: 0 });
      else {
        const hp = drv.int(1, u.hp);
        Object.assign(c, { status: roll < 0.37 ? 'fled' : 'active', hp, alive: aliveFor(hp, u.hpPer, u.alive) });
      }
      Object.assign(c, { kills: drv.int(0, 3), xp: drv.int(0, 16), morale: drv.int(1, u.maxMorale) });
      if (u.shot) c.ammo = drv.int(0, u.ammo);
    } else {
      if (roll < 0.5) Object.assign(c, { status: 'dead', hp: 0, alive: 0 });
      else if (roll < 0.7) Object.assign(c, { status: 'fled', hp: drv.int(1, u.hp), alive: 1 });
      else {
        const hp = drv.int(1, u.hp);
        Object.assign(c, { hp, alive: aliveFor(hp, u.hpPer, u.alive) });
      }
    }
    changes.push(c);
  }
  return [changes, drv.pick(['victory', 'victory', 'victory', 'retreat', 'defeat'])];
}

const EFFECTS = [
  { k: 'supply', id: 'rations', n: 3 }, { k: 'supply', id: 'torches', n: -5 }, { k: 'loot', id: 'silver', n: 12 }, { k: 'loot', id: 'iron', n: -4 },
  { k: 'morale', n: -9, who: 'all' }, { k: 'morale', n: 6, who: 'random' }, { k: 'morale', n: 4, who: 'strongest' }, { k: 'morale', n: -3, who: 'type:spearman' },
  { k: 'hp', n: -14, who: 'weakest' }, { k: 'hp', n: -7, who: 'all' }, { k: 'hp', n: 5, who: 'random' }, { k: 'hp', n: -30, who: 'type:crossbowman' },
  { k: 'fatigue', n: 25, who: 'all' }, { k: 'fatigue', n: -10, who: 'random' }, { k: 'xp', n: 12, who: 'strongest' }, { k: 'xp', n: 40, who: 'random' },
  { k: 'injury', who: 'random' }, { k: 'injury', who: 'weakest' }, { k: 'recruit', typeId: 'spearman', level: 2 }, { k: 'recruit', typeId: 'crossbowman', level: 1 },
  { k: 'reveal', stages: 2 }, { k: 'battle', encounterId: 'goblin_scouts' },
];

function drivenRun(seed: number, expeditions: number, auto: boolean, raids = false) {
  const g = G.newGame(seed);
  const drv = new Rng(seed * 31 + 5);
  const start = clone(g);
  const steps: Step[] = [];
  const step = (op: string, ...args: unknown[]) => {
    const ret = run(g, op, clone(args));
    steps.push({ op, args: clone(args), ret: ret === undefined ? null : clone(ret), state: clone(g) });
    return ret;
  };
  let effectsDone = false;
  for (let e = 0; e < expeditions; e++) {
    // Between expeditions: refill and hire, then march out.
    if (e > 0) {
      step('setRes', 'silver', g.resources.silver + 200);
      for (const s of g.roster) if (G.missingMen(s) > 0) step('reinforce', s.id, drv.int(1, 3));
      if (g.recruits.length && g.roster.length < 8) step('hire', g.recruits[0].id);
      const inj = g.roster.find((s) => s.injuries.length);
      if (inj) step('treat', inj.id, inj.injuries[0]);
      step('upgradeBuilding', drv.pick(['infirmary', 'quartermaster', 'barracks', 'armoury']));
    }
    const c = G.availableCampaigns(g)[0];
    const army = g.roster.filter((s) => G.eligibility(g, s, c).ok).slice(0, 6).map((s) => s.id);
    const xb = army.filter((id) => g.roster.find((s) => s.id === id)!.typeId === 'crossbowman').length;
    const sup = G.recommendedSupplies(army.length, xb, G.wagonCapacity(g), c.stages + 1);
    if (e === 1) sup.rations = 4; // a hungry march
    step('startExpedition', c.id, army, sup, Math.min(g.resources.silver, G.supplyCostTotal(g, sup)));
    step('query');
    let guard = 0;
    while (g.expedition && guard++ < 150) {
      const ex = g.expedition;
      const p = ex.pending;
      if (!p) {
        const next = X.nextNodes(ex);
        if (!effectsDone && ex.marches >= 2) {
          effectsDone = true;
          for (const ef of EFFECTS) {
            const army2 = X.armySoldiers(g);
            const subj = drv.chance(0.5) && army2.length ? drv.pick(army2).id : null;
            step('applyEffect', ef, subj, drv.chance(0.5) ? 'A test' : null);
          }
          step('hurtSquad', X.armySoldiers(g)[0].id, 9.5);
          step('query');
        }
        const hurt = X.armySoldiers(g).find((s) => s.hp < squadHpCap(s));
        if (hurt && drv.chance(0.5)) step('useBandage', hurt.id);
        if (drv.chance(0.1)) step('useBandage', X.armySoldiers(g)[0]?.id ?? 'nobody');
        if (drv.chance(0.08)) step('march', ex.nodes[ex.nodes.length - 1].id); // not adjacent: refused
        if (drv.chance(0.03) && ex.marches >= 2) {
          step('returnHome', 'retreat');
          break;
        }
        if (!next.length) {
          step('returnHome', ex.objectiveDone ? 'success' : 'retreat');
          break;
        }
        step('march', drv.pick(next).id);
        if (drv.chance(0.3)) step('query');
        continue;
      }
      switch (p.kind) {
        case 'arrive':
        case 'scout':
          step('dismissPending');
          break;
        case 'event': {
          if (!p.result) {
            const ev = EVENTS.find((x) => x.id === p.eventId)!;
            if (drv.chance(0.2)) step('chooseEvent', drv.int(0, ev.choices.length - 1)); // maybe unavailable
            if (!(g.expedition?.pending as any)?.result) {
              const ok = ev.choices.map((ch, i) => [ch, i] as const).filter(([ch]) => X.choiceAvailable(g, ch).ok).map(([, i]) => i);
              step('query');
              step('chooseEvent', ok.length ? drv.pick(ok) : 0);
            }
          }
          step('dismissPending');
          break;
        }
        case 'camp': {
          // Raids mode: rest without a watch, so night raids come while torches remain.
          const acts = raids ? ['campRest'] : drv.shuffle(['campWatch', 'campRepair', 'campRest']);
          for (const a of acts) {
            if (g.expedition?.pending?.kind !== 'camp') break;
            if (drv.chance(0.85)) step(a);
          }
          if (g.expedition?.pending?.kind === 'camp') step('dismissPending');
          break;
        }
        case 'village': {
          const order = raids ? [0, 1, 2, 3] : drv.shuffle([0, 1, 2, 3, 4]);
          for (const i of order) {
            if (g.expedition?.pending?.kind !== 'village') break;
            step('searchSpot', i);
          }
          if (g.expedition?.pending?.kind === 'village') step('dismissPending');
          break;
        }
        case 'battle': {
          if (auto) step('battleAuto');
          else {
            const [changes, result] = scriptOutcome(g, drv);
            step('battleScripted', changes, result);
          }
          break;
        }
        case 'battleResult':
          step('dismissPending');
          break;
        case 'complete':
          step('returnHome', 'success');
          break;
      }
    }
    if (g.expedition) step('returnHome', 'retreat');
  }
  return { seed, auto, raids, start, steps };
}
const runs = [
  drivenRun(11, 3, false),
  drivenRun(12, 3, false),
  drivenRun(13, 2, false),
  drivenRun(14, 2, true),
  drivenRun(15, 2, true),
];
// Raids: the first seeds whose runs meet raiders in a village and a night raid with a torch to light.
{
  let found = 0;
  for (let seed = 100; seed < 400 && found < 2; seed++) {
    const r = drivenRun(seed, 2, false, true);
    const text = JSON.stringify(r.steps);
    if (text.includes('Goblins burst from the ruins') && text.includes('Torches are lit around the camp (-1 torch)')) {
      runs.push(r);
      found++;
    }
  }
}

// ---------------------------------------------------------------- autoplay campaigns (scripts/simcampaign.ts)
const autos: unknown[] = [];
for (let i = 0; i < 5; i++) {
  const g = G.newGame(1000 + i * 13);
  const rng = new Rng(i);
  const start = clone(g);
  const cycles: unknown[] = [];
  for (let c = 0; c < 4; c++) {
    const before = g.fallen.length;
    const prepared = A.autoPrepare(g, rng);
    const afterPrepare = clone(g);
    if (!prepared) {
      cycles.push({ prepared, afterPrepare });
      break;
    }
    const outcome = A.autoExpedition(g, rng);
    const afterExpedition = clone(g);
    const deaths = g.fallen.length - before;
    const upgrades: string[] = [];
    for (const b of ['command', 'infirmary', 'barracks', 'training', 'armoury', 'quartermaster']) {
      const nl = G.nextLevel(g, b);
      if (nl && G.canAfford(g, nl.cost) && g.resources.silver - (nl.cost.silver ?? 0) > 150) {
        G.upgradeBuilding(g, b);
        upgrades.push(b);
      }
    }
    cycles.push({ prepared, afterPrepare, outcome, deaths, afterExpedition, upgrades, afterUpgrades: clone(g), rngState: rng.state });
  }
  autos.push({ seed: 1000 + i * 13, rngSeed: i, start, cycles });
}

// ---------------------------------------------------------------- V8 sort order
// autoExpedition sorts with a comparator that draws random numbers, so the
// exact sequence of comparator calls of V8's Array.prototype.sort matters.
const v8sort: unknown[] = [];
for (let n = 0; n <= 9; n++) {
  for (let s = 0; s < 8; s++) {
    const seed = n * 100 + s;
    const r = new Rng(seed);
    const calls: [number, number][] = [];
    const sorted = Array.from({ length: n }, (_, i) => i).sort((a, b) => {
      calls.push([a, b]);
      return r.next() - 0.5;
    });
    v8sort.push({ n, seed, calls, sorted });
  }
}

// ---------------------------------------------------------------- saves
// Save texts exactly as the original writes them (JSON.stringify(game)).
const saves: { label: string; text: string }[] = [];
{
  const g = G.newGame(77);
  saves.push({ label: 'new game', text: JSON.stringify(g) });
  const army = g.roster.slice(0, 6).map((s) => s.id);
  const sup = G.recommendedSupplies(6, 2, G.wagonCapacity(g), 6);
  X.startExpedition(g, 'hillsvain_raids', army, sup, G.supplyCostTotal(g, sup));
  X.march(g, X.nextNodes(g.expedition!)[0].id);
  saves.push({ label: 'on the march', text: JSON.stringify(g) });
  A.autoExpedition(g, new Rng(3));
  saves.push({ label: 'home with a report', text: JSON.stringify(g) });
}

writeFileSync(join(out, 'campaign_golden.json'), JSON.stringify({ RETREAT_STRENGTH: A.RETREAT_STRENGTH, generated, runs, autos, v8sort, saves }) + '\n');
console.log(`campaign_golden.json: ${generated.length} expeditions, ${runs.reduce((n, r) => n + r.steps.length, 0)} driven steps, ${autos.length} autoplay campaigns`);
for (const r of runs) console.log(`  run ${r.seed} (${r.auto ? 'auto' : 'scripted'} battles${r.raids ? ', raids' : ''}): ${r.steps.length} steps, ops: ${[...new Set(r.steps.map((s) => s.op))].join(' ')}`);
for (const a of autos as any[]) console.log(`  auto ${a.seed}: ${a.cycles.map((c: any) => c.outcome ?? 'no army').join(', ')}`);
