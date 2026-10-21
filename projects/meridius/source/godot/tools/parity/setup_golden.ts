// Golden battle setups from the original (src/battle/setup.ts): rollEncounter
// for every encounter at several depths and seeds, and buildBattle with full,
// small, depleted and veteran companies (deployment, enemy placement, allies,
// waves staged off-field as reserves, facing).
//   cd projects/meridius/source/game && npx vite-node ../godot/tools/parity/setup_golden.ts
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Rng } from '../../../game/src/core/rng';
import { ENCOUNTERS } from '../../../game/src/data/encounters';
import { buildBattle, rollEncounter, type EncounterRoll } from '../../../game/src/battle/setup';
import { newSoldier, soldierStats, soldierToUnit } from '../../../game/src/meta/soldier';
import type { BattleMap, BattleSetup, BattleUnit } from '../../../game/src/battle/types';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '..', '..', 'tests', 'fixtures', 'golden');
mkdirSync(out, { recursive: true });
const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v));

const DEPTHS = [0, 1, 2, 4];
const SEEDS = [1, 2, 3];

const rolls: unknown[] = [];
for (const e of ENCOUNTERS) {
  for (const depth of DEPTHS) {
    for (const s of SEEDS) {
      const seed = s * 7919 + depth;
      const rng = new Rng(seed);
      const roll = rollEncounter(e.id, rng, depth);
      rolls.push({ encounterId: e.id, depth, seed, roll: clone(roll), rngAfter: rng.state });
    }
  }
}

// Companies the battles are built with.
function company(kind: string, seed: number): BattleUnit[] {
  const rng = new Rng(seed);
  let n = 0;
  const id = () => `${kind[0]}${n++}`;
  const make = (t: string, lvl = 1) => newSoldier(rng, t, lvl, id, 0);
  if (kind === 'full') return ['footman', 'footman', 'spearman', 'spearman', 'crossbowman', 'crossbowman'].map((t) => soldierToUnit(make(t)));
  if (kind === 'small') return ['footman', 'spearman', 'crossbowman'].map((t) => soldierToUnit(make(t)));
  if (kind === 'depleted') {
    return ['footman', 'spearman', 'spearman', 'crossbowman', 'footman'].map((t, i) => {
      const s = make(t, 1 + (i % 2));
      s.men = Math.max(1, s.men - 2 - i);
      s.hp = Math.max(1, soldierStats(s).hp * s.men - 3 * i);
      s.morale = Math.max(5, s.morale - 20);
      s.fatigue = [0, 65, 90, 30, 85][i];
      s.armorCondition = 0.6;
      return soldierToUnit(s);
    });
  }
  // guard: a seasoned company with the royal guard and promotions.
  return ['collie_guard', 'footman', 'spearman', 'spearman', 'crossbowman', 'crossbowman', 'collie_guard'].map((t, i) => {
    const s = make(t, 2 + (i % 3));
    s.promoted = i % 2 === 0;
    s.weaponTier = 1 + (i % 3);
    return soldierToUnit(s);
  });
}
const KINDS = ['full', 'small', 'depleted', 'guard'];

function mapSummary(m: BattleMap) {
  const { tiles, outer, outerGround, ...rest } = m;
  return { ...rest, tileCount: tiles.length, outerCount: outer.length, outerGroundCount: outerGround?.length ?? 0 };
}

const setups: unknown[] = [];
let k = 0;
for (const e of ENCOUNTERS) {
  for (const depth of [0, 2, 4]) {
    for (const s of [1, 2]) {
      const seed = s * 104729 + depth * 31 + e.id.length;
      const roll = rollEncounter(e.id, new Rng(seed), depth);
      const kind = KINDS[k % KINDS.length];
      const army = company(kind, seed + 17);
      const opts = k % 3 === 0 ? { survivalBonus: 0 } : k % 3 === 1 ? { survivalBonus: 0.12, darkness: true } : { survivalBonus: 0.08, darkness: false, title: `Test ${k}` };
      const input = clone(army);
      const setup: BattleSetup = buildBattle(roll, army, opts);
      const full = depth === 0 && s === 1;
      setups.push({ roll: clone(roll), army: input, kind, opts, setup: { ...clone(setup), map: full ? clone(setup.map) : mapSummary(setup.map) }, fullMap: full });
      k++;
    }
  }
}
// The debug path: a roll forced onto another field.
const overrides: [string, string][] = [['last_stand', 'ford'], ['last_stand', 'steading'], ['refugee_stand', 'steading'], ['goblin_scouts', 'goblin_camp'], ['warband_camp', 'forest_clearing'], ['road_ambush', 'goblin_camp']];
for (const [id, mapId] of overrides) {
  for (const s of [7, 8]) {
    const roll: EncounterRoll = rollEncounter(id, new Rng(s), 2);
    roll.mapId = mapId;
    const army = company(KINDS[s % KINDS.length], s * 3);
    const input = clone(army);
    const setup = buildBattle(roll, army, { survivalBonus: 0 });
    setups.push({ roll: clone(roll), army: input, kind: KINDS[s % KINDS.length], opts: { survivalBonus: 0 }, setup: { ...clone(setup), map: mapSummary(setup.map) }, fullMap: false });
  }
}

writeFileSync(join(out, 'setup_golden.json'), JSON.stringify({ rolls, setups }) + '\n');
console.log(`setup_golden.json: ${rolls.length} rolls, ${setups.length} setups`);
