// Golden data for src/meta/soldier.ts and src/meta/game.ts: soldier tables,
// newGame states, scripted economy actions (state after every step) and save
// migration.
//   cd projects/meridius/source/game && npx vite-node ../godot/tools/parity/meta_golden.ts
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Rng } from '../../../game/src/core/rng';
import { UNIT_TYPES } from '../../../game/src/data/units';
import { BUILDINGS } from '../../../game/src/data/buildings';
import { SUPPLY_ORDER, INJURIES } from '../../../game/src/data/items';
import { campaignById } from '../../../game/src/data/campaigns';
import * as S from '../../../game/src/meta/soldier';
import * as G from '../../../game/src/meta/game';
import type { GameState } from '../../../game/src/meta/game';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '..', '..', 'tests', 'fixtures', 'golden');
mkdirSync(out, { recursive: true });
const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v));

// ---------------------------------------------------------------- soldier tables
const ROSTER_TYPES = ['footman', 'spearman', 'crossbowman', 'collie_guard'];
const newSoldiers: unknown[] = [];
let sid = 0;
for (const t of ROSTER_TYPES) {
  for (let lvl = 1; lvl <= 5; lvl++) {
    const seed = t.length * 100 + lvl;
    const rng = new Rng(seed);
    const s = S.newSoldier(rng, t, lvl, () => `s${sid++}`, lvl);
    newSoldiers.push({ seed, typeId: t, level: lvl, cycle: lvl, id: s.id, soldier: clone(s), rngAfter: rng.state });
  }
}
// Variants: equipment, injuries, fatigue, armour wear, promotion, losses.
const soldiers: S.Soldier[] = [];
const injuryIds = Object.keys(INJURIES);
const vr = new Rng(4242);
for (let i = 0; i < 90; i++) {
  const t = ROSTER_TYPES[i % ROSTER_TYPES.length];
  const lvl = 1 + (i % 5);
  const s = S.newSoldier(vr, t, lvl, () => `v${i}`, 0);
  s.weaponTier = 1 + vr.int(0, 2);
  s.armorTier = 1 + vr.int(0, 2);
  s.armorCondition = [1, 0.3, 0.65, 0.95, 0.5][i % 5];
  s.fatigue = [0, 30, 59, 60, 84, 85, 100][i % 7];
  s.promoted = i % 3 === 0;
  s.injuries = injuryIds.filter((_, k) => ((i >> k) & 1) === 1 && k < 3 + (i % 3));
  if (i % 4 === 1) {
    s.men = Math.max(1, s.men - 1 - (i % 3));
    s.hp = Math.max(1, Math.round(S.soldierStats(s).hp * (s.men - 0.4)));
  }
  if (i % 6 === 2) s.hp = 1;
  if (i % 5 === 3) s.morale = 5;
  s.xp = S.levelForXp(s.xp) === lvl ? s.xp + (i % 4) * 7 : s.xp;
  soldiers.push(s);
}
const soldierFns = soldiers.map((s, i) => {
  const healed = clone(s);
  const healAmt = [0, 3.4, 7.5, 1000][i % 4];
  const healRet = S.healSoldier(healed, healAmt);
  const settled = clone(s);
  settled.hp = Math.max(1, settled.hp - 17);
  const settledIn = clone(settled);
  S.settleMen(settled);
  return {
    soldier: clone(s),
    stats: S.soldierStats(s),
    weaponBonus: S.weaponBonus(s),
    damage: S.soldierDamage(s),
    commandCost: S.commandCost(s),
    abilities: S.abilitiesOf(s),
    canPromote: S.canPromote(s),
    xpToNext: S.xpToNext(s),
    maxHp: S.squadMaxHp(s),
    hpCap: S.squadHpCap(s),
    unit: S.soldierToUnit(s),
    healAmt,
    healRet,
    healed,
    settledIn,
    settled,
  };
});
const enemies: unknown[] = [];
for (const t of Object.keys(UNIT_TYPES)) {
  for (let lvl = 1; lvl <= 3; lvl++) {
    const seed = t.length * 31 + lvl;
    const rng = new Rng(seed);
    const u = S.makeEnemy(t, lvl, `e-${t}-${lvl}`, rng);
    enemies.push({ typeId: t, level: lvl, seed, uid: u.uid, unit: u, rngAfter: rng.state });
  }
}
const misc = {
  rankName: [-1, 0, 1, 2, 3, 4, 5, 6, 9].map((l) => [l, S.rankName(l)]),
  levelForXp: [0, 5, 19, 20, 49, 50, 94, 95, 159, 160, 500].map((x) => [x, S.levelForXp(x)]),
  fatigueLabel: [0, 29, 30, 59, 60, 84, 85, 100].map((f) => [f, S.fatigueLabel(f)]),
  numberWord: [0, 1, 2, 3, 5, 8, 9, 12].map((n) => [n, G.numberWord(n)]),
  recommendedSupplies: [
    [6, 2, 30, 6], [5, 1, 30, 6], [8, 3, 30, 6], [10, 4, 30, 6], [3, 0, 30, 6], [6, 2, 38, 6], [8, 2, 46, 6], [12, 6, 20, 6], [1, 0, 5, 3], [7, 7, 10, 9],
  ].map(([a, x, c, m]) => [[a, x, c, m], G.recommendedSupplies(a, x, c, m)]),
  recommendedDefault: [[6, 2], [9, 3]].map(([a, x]) => [[a, x], G.recommendedSupplies(a, x)]),
  supplyWeight: [{ rations: 20, bandages: 3, bolts: 4, torches: 2, tools: 1 }, { rations: 1 }, {}].map((s) => [s, G.supplyWeight(s)]),
};

// ---------------------------------------------------------------- newGame
const newGames = [1, 2, 3, 5, 9, 21, 31, 42, 77, 1000, 123456789, 2147483646].map((seed) => ({ seed, state: clone(G.newGame(seed)) }));

// ---------------------------------------------------------------- economy scripts
type Step = { op: string; args: unknown[]; ret: unknown; state: unknown };

function queries(g: GameState) {
  const c = campaignById('hillsvain_raids');
  const per = g.roster.map((s) => ({
    id: s.id,
    canReinforce1: G.canReinforce(g, s),
    canReinforce3: G.canReinforce(g, s, 3),
    reinforceCost: G.reinforceCost(g, s),
    missingMen: G.missingMen(s),
    drillCost: G.drillCost(g, s),
    canDrill: G.canDrill(g, s),
    canPromoteHere: G.canPromoteHere(g, s),
    canBuyWeapon: G.canBuyEquip(g, s, 'weapon'),
    canBuyArmor: G.canBuyEquip(g, s, 'armor'),
    nextWeapon: G.nextEquip(g, s, 'weapon') ?? null,
    nextArmor: G.nextEquip(g, s, 'armor') ?? null,
    weaponLine: G.equipLine(s, 'weapon')?.id ?? null,
    armorLine: G.equipLine(s, 'armor')?.id ?? null,
    repairCost: G.repairCost(g, s),
    eligibility: G.eligibility(g, s, c),
    commandCost: S.commandCost(s),
    stats: S.soldierStats(s),
    unit: S.soldierToUnit(s),
  }));
  const effects: Record<string, number> = {};
  for (const b of BUILDINGS) for (const k of Object.keys(b.levels[0].effects)) effects[`${b.id}.${k}`] = G.effect(g, b.id, k);
  const nextLevels = BUILDINGS.map((b) => {
    const nl = G.nextLevel(g, b.id);
    return { id: b.id, level: G.level(g, b.id), next: nl ?? null, canAfford: nl ? G.canAfford(g, nl.cost) : null };
  });
  const xb = g.roster.filter((s) => s.typeId === 'crossbowman').length;
  const rec = G.recommendedSupplies(Math.min(6, g.roster.length), xb, G.wagonCapacity(g), c.stages + 1);
  return {
    per,
    recruitCosts: g.recruits.map((r) => [r.id, G.recruitCost(r)]),
    leaveCost: G.leaveCost(g),
    promoteCost: G.promoteCost(g),
    treatCosts: Object.keys(INJURIES).map((k) => [k, G.treatCost(g, k)]),
    armyLimits: G.armyLimits(g, c),
    armyCommand: G.armyCommand(g, g.roster.map((s) => s.id).concat(['nobody'])),
    supplyPrices: SUPPLY_ORDER.map((k) => [k, G.supplyPrice(g, k)]),
    wagonCapacity: G.wagonCapacity(g),
    rosterCap: G.rosterCap(g),
    campaigns: G.availableCampaigns(g).map((x) => x.id),
    effects,
    nextLevels,
    recommended: rec,
    recWeight: G.supplyWeight(rec),
    recCost: G.supplyCostTotal(g, rec),
  };
}

function run(g: GameState, op: string, a: any[]): unknown {
  switch (op) {
    case 'setRes': g.resources[a[0] as 'silver'] = a[1]; return null;
    case 'setBuilding': g.buildings[a[0]] = a[1]; return null;
    case 'setSoldier': { const s = g.roster.find((r) => r.id === a[0])!; (s as any)[a[1]] = clone(a[2]); return null; }
    case 'hire': return G.hire(g, a[0]);
    case 'dismiss': return G.dismiss(g, a[0]);
    case 'reinforce': return a.length > 1 ? G.reinforce(g, a[0], a[1]) : G.reinforce(g, a[0]);
    case 'drill': return G.drill(g, a[0]);
    case 'promote': return G.promote(g, a[0]);
    case 'buyEquip': return G.buyEquip(g, a[0], a[1]);
    case 'repair': return G.repair(g, a[0]);
    case 'treat': return G.treat(g, a[0], a[1]);
    case 'grantLeave': return G.grantLeave(g, a[0]);
    case 'upgradeBuilding': return G.upgradeBuilding(g, a[0]);
    case 'rollRecruits': G.rollRecruits(g); return null;
    case 'gainXp': return G.gainXp(g, g.roster.find((r) => r.id === a[0])!, a[1]);
    case 'chronicle': G.chronicle(g, a[0], a[1]); return null;
    case 'query': return queries(g);
  }
  throw new Error(op);
}

function script(seed: number): { seed: number; start: unknown; steps: Step[] } {
  const g = G.newGame(seed);
  const start = clone(g);
  const steps: Step[] = [];
  const step = (op: string, ...args: unknown[]) => {
    const ret = run(g, op, clone(args));
    steps.push({ op, args: clone(args), ret: ret === undefined ? null : clone(ret), state: clone(g) });
  };
  const ids = () => g.roster.map((s) => s.id);
  step('query');
  step('hire', g.recruits[0].id);
  step('hire', g.recruits[g.recruits.length - 1].id);
  step('setRes', 'silver', 5);
  if (g.recruits.length) step('hire', g.recruits[0].id);
  step('hire', 'nobody');
  step('setRes', 'silver', 3000);
  step('setRes', 'iron', 30);
  step('setRes', 'timber', 30);
  step('setRes', 'trophies', 10);
  step('query');
  // Buildings: every level, then a failed upgrade past the top.
  for (const b of ['barracks', 'training', 'armoury', 'infirmary', 'quartermaster', 'command']) {
    step('upgradeBuilding', b);
    if (seed % 2 === 1 || b === 'armoury' || b === 'training') step('upgradeBuilding', b);
  }
  step('upgradeBuilding', 'armoury');
  step('setRes', 'trophies', 0);
  step('upgradeBuilding', 'command');
  step('query');
  step('rollRecruits');
  for (const r of g.recruits.slice()) step('hire', r.id);
  step('rollRecruits');
  step('rollRecruits');
  // Reinforcements.
  const s0 = g.roster[0];
  const per0 = S.soldierStats(s0).hp;
  step('setSoldier', s0.id, 'men', 3);
  step('setSoldier', s0.id, 'hp', per0 * 3 - 4);
  step('query');
  step('reinforce', s0.id);
  step('reinforce', s0.id, 9);
  step('reinforce', s0.id);
  const s1 = g.roster[1];
  step('setSoldier', s1.id, 'men', 2);
  step('setSoldier', s1.id, 'hp', S.soldierStats(s1).hp * 2);
  step('setRes', 'silver', 12);
  step('reinforce', s1.id, 2);
  step('setRes', 'silver', 3000);
  step('reinforce', s1.id, 2);
  // Drill: everyone once, then again (already drilled).
  for (const id of ids().slice(0, 6)) step('drill', id);
  step('drill', ids()[0]);
  // Promotion.
  const p = g.roster[2];
  step('promote', p.id);
  step('gainXp', p.id, 60);
  step('gainXp', p.id, 3);
  step('promote', p.id);
  step('promote', p.id);
  step('gainXp', g.roster[3].id, 200);
  step('setRes', 'iron', 0);
  step('promote', g.roster[3].id);
  step('setRes', 'iron', 30);
  step('promote', g.roster[3].id);
  // Armoury.
  for (const id of ids().slice(0, 5)) {
    for (const slot of ['weapon', 'armor', 'weapon', 'armor', 'weapon']) step('buyEquip', id, slot);
  }
  step('query');
  const r0 = g.roster[4];
  step('setSoldier', r0.id, 'armorCondition', 0.45);
  step('repair', r0.id);
  step('repair', r0.id);
  step('setSoldier', r0.id, 'armorCondition', 0.85);
  step('setRes', 'silver', 3);
  step('repair', r0.id);
  step('setRes', 'silver', 3000);
  // Infirmary.
  const t0 = g.roster[5] ?? g.roster[0];
  step('setSoldier', t0.id, 'injuries', ['gashed_arm', 'concussion', 'cracked_ribs']);
  step('setSoldier', t0.id, 'hp', S.squadHpCap(g.roster.find((r) => r.id === t0.id)!));
  step('treat', t0.id, 'cracked_ribs');
  step('treat', t0.id, 'concussion');
  step('treat', t0.id, 'broken_hand');
  step('query');
  // Leave.
  const l0 = g.roster[1];
  step('setSoldier', l0.id, 'morale', 10);
  step('query');
  step('grantLeave', l0.id);
  step('grantLeave', l0.id);
  // Eligibility edge cases.
  step('setSoldier', g.roster[0].id, 'morale', 3);
  step('setSoldier', g.roster[2].id, 'level', 5);
  step('setSoldier', g.roster[3].id, 'recovering', true);
  step('query');
  step('chronicle', 'A test line.', 'good');
  // Dismissals down to the last squad.
  while (g.roster.length > 1) step('dismiss', g.roster[g.roster.length - 1].id);
  step('dismiss', g.roster[0].id);
  step('rollRecruits');
  step('query');
  return { seed, start, steps };
}
const scripts = [5, 9, 21, 31].map(script);

// ---------------------------------------------------------------- save migration
const migrations = [7, 21, 33].map((seed) => {
  const g = G.newGame(seed);
  const old = clone(g) as any;
  const per = S.soldierStats(g.roster[0]).hp;
  for (const s of [...old.roster, ...old.recruits]) {
    delete s.men;
    s.hp = S.soldierStats(s).hp;
  }
  old.roster[0].hp = per - 7;
  old.roster[1].hp = null;
  old.roster[2].hp = -3;
  old.roster[3].injuries = null;
  old.recruits.push({ ...clone(old.recruits[0]), typeId: 'no_such_type' });
  const input = clone(old);
  const m = G.migrateSave(old);
  // A current save passes through unchanged; one with odd men is clamped.
  const cur = clone(g) as any;
  cur.roster[0].men = 99;
  cur.roster[1].men = 2.6;
  cur.roster[2].hp = 100000;
  const curIn = clone(cur);
  const curOut = G.migrateSave(cur);
  const plain = clone(g);
  const plainOut = G.migrateSave(clone(g));
  return { seed, input, output: clone(m), currentIn: curIn, currentOut: clone(curOut), plain, plainOut: clone(plainOut) };
});

writeFileSync(
  join(out, 'meta_golden.json'),
  JSON.stringify({ SAVE_VERSION: G.SAVE_VERSION, ELITE_RECRUIT_CHANCE: G.ELITE_RECRUIT_CHANCE, newSoldiers, soldierFns, enemies, misc, newGames, scripts, migrations }) + '\n',
);
console.log(`meta_golden.json: ${soldierFns.length} soldiers, ${enemies.length} enemies, ${scripts.reduce((n, s) => n + s.steps.length, 0)} economy steps`);
