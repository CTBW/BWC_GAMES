// Fixtures for the battle unit tests (tests/unit/test_battle*.gd, test_squad.gd,
// test_facing.gd, test_ai.gd): the squads and setups the original tests build
// with soldier.ts / mapgen.ts / setup.ts, exported so the rules tests do not
// depend on the meta and mapgen ports.
//   cd projects/meridius/source/game && npx vite-node ../godot/tools/parity/battle_fixtures.ts
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Rng } from '../../../game/src/core/rng';
import type { Dir } from '../../../game/src/core/types';
import { buildBattle, rollEncounter } from '../../../game/src/battle/setup';
import type { BattleSetup, BattleUnit } from '../../../game/src/battle/types';
import { makeEnemy, newSoldier, soldierToUnit } from '../../../game/src/meta/soldier';

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, '..', '..', 'tests', 'fixtures', 'golden', 'battle');
mkdirSync(outDir, { recursive: true });

const units: Record<string, BattleUnit | BattleUnit[]> = {};
const setups: Record<string, BattleSetup> = {};
const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v));

const DEFAULT_ARMY = ['footman', 'footman', 'spearman', 'spearman', 'crossbowman'];

/** tests/battle.test.ts army(). Key army:<seed>:<types>. */
function army(seed: number, types = DEFAULT_ARMY): BattleUnit[] {
  const rng = new Rng(seed);
  let n = 0;
  const out = types.map((t) => soldierToUnit(newSoldier(rng, t, 1, () => `s${n++}`, 0)));
  units[`army:${seed}:${types.join(',')}`] = clone(out);
  return out;
}

/** makeEnemy(type, level, uid, new Rng(seed)). Key enemy:<type>:<level>:<uid>:<seed>. */
function enemy(type: string, level: number, uid: string, seed: number): BattleUnit {
  const u = makeEnemy(type, level, uid, new Rng(seed));
  units[`enemy:${type}:${level}:${uid}:${seed}`] = clone(u);
  return u;
}

/** tests/squad.test.ts footmen(). Key footmen:<seed>. */
function footmen(seed = 1): BattleUnit {
  let n = 0;
  const u = soldierToUnit(newSoldier(new Rng(seed), 'footman', 1, () => `f${n++}`, 0));
  units[`footmen:${seed}`] = clone(u);
  return u;
}

/** tests/facing.test.ts and horde.test.ts soldier(). Key soldier:<type>:<seed>:<uid>. */
function soldier(type: string, seed: number, uid: string): BattleUnit {
  const u = { ...soldierToUnit(newSoldier(new Rng(seed), type, 1, () => uid, 0)), uid };
  units[`soldier:${type}:${seed}:${uid}`] = clone(u);
  return u;
}

/** tests/facing.test.ts enemy(): makeEnemy with new Rng(uid.length + x * 7 + y). */
function fenemy(type: string, uid: string, x: number, y: number) {
  enemy(type, 1, uid, uid.length + x * 7 + y);
}

/** tests/horde.test.ts enemy(): makeEnemy with new Rng(uid.length * 13 + x). */
function henemy(type: string, uid: string, x: number) {
  enemy(type, 1, uid, uid.length * 13 + x);
}

// battle.test.ts
army(1, ['footman']);
army(2, ['spearman']);
army(4, ['footman']);
army(5, ['spearman']);
army(30, ['footman']);
army(31, ['footman']);
army(32, ['footman', 'spearman']);
enemy('goblin_spear', 1, 'g', 1);
enemy('orc_warrior', 1, 'g', 2);
enemy('goblin_spear', 1, 'g', 3);
enemy('goblin_spear', 1, 'g', 4);
enemy('goblin_archer', 1, 'g', 5);
for (let i = 0; i < 40; i++) {
  const roll = rollEncounter('goblin_scouts', new Rng(100 + i), 0);
  setups[`scouts:${i}`] = clone(buildBattle(roll, army(200 + i), { survivalBonus: 0 }));
}
for (let i = 0; i < 30; i++) {
  const roll = rollEncounter('warband_camp', new Rng(500 + i), 4);
  setups[`camp:${i}`] = clone(buildBattle(roll, army(600 + i), { survivalBonus: 0 }));
}

// squad.test.ts
for (let seed = 1; seed < 40; seed++) {
  footmen(seed);
  enemy('goblin_spear', 1, 'g', seed);
}
enemy('troll', 1, 't', 1);
enemy('troll', 1, 't', 3);
enemy('goblin_spear', 1, 'a', 1);

// facing.test.ts
soldier('footman', 1, 'f'); fenemy('goblin_archer', 'g', 12, 1);
soldier('footman', 2, 'f'); fenemy('goblin_archer', 'g', 13, 0);
soldier('footman', 3, 'f');
soldier('footman', 4, 'f');
soldier('spearman', 5, 's'); fenemy('goblin_archer', 'e', 13, 0);
soldier('footman', 6, 'f'); fenemy('goblin_spear', 'g', 6, 5);
soldier('footman', 7, 'f'); fenemy('goblin_spear', 'g', 9, 5);
soldier('footman', 8, 'f'); fenemy('goblin_spear', 'g', 5, 5);
soldier('footman', 9, 'f2'); fenemy('goblin_spear', 'g2', 5, 5);
soldier('spearman', 10, 's'); fenemy('orc_warrior', 'o', 5, 9);
soldier('spearman', 11, 's2'); fenemy('orc_warrior', 'o2', 5, 3);
soldier('crossbowman', 12, 'c'); fenemy('goblin_spear', 'g', 2, 12);
soldier('crossbowman', 13, 'c2'); fenemy('goblin_spear', 'g2', 6, 1);
soldier('spearman', 14, 's'); fenemy('goblin_spear', 'g', 5, 8);
for (let seed = 1; seed <= 12; seed++) {
  const roll = rollEncounter(seed % 2 ? 'raiding_party' : 'orc_overseer', new Rng(seed), 2);
  const a = DEFAULT_ARMY.map((t, i) => soldier(t, seed * 10 + i, `p${i}`));
  setups[`marching:${seed}`] = clone(buildBattle(roll, a, { survivalBonus: 0 }));
}

// horde.test.ts
soldier('footman', 1, 'f'); henemy('goblin_spear', 'g', 2);
henemy('goblin_rabble', 'w0-0', 5); henemy('goblin_spear', 'w0-1', 6); henemy('goblin_spear', 'w0-0', 5); henemy('goblin_rabble', 'w0-1', 6);
soldier('footman', 2, 'f'); henemy('goblin_rabble', 'g', 6);
soldier('footman', 3, 'f'); henemy('goblin_horn', 'h', 8); henemy('goblin_spear', 'g', 3);
soldier('footman', 4, 'f'); henemy('goblin_spear', 'a', 6); henemy('goblin_spear', 'c', 7);
soldier('spearman', 6, 'f2'); soldier('spearman', 7, 'f3');
soldier('footman', 8, 'f');
soldier('footman', 9, 'f'); henemy('orc_warlord', 'chief', 6);
soldier('footman', 10, 'f'); henemy('orc_brute', 'br', 6);
soldier('footman', 11, 'f'); henemy('wolf_rider', 'w', 6);
soldier('footman', 12, 'f'); henemy('goblin_archer', 'g', 12);
for (let i = 0; i < 4; i++) {
  const roll = rollEncounter('last_stand', new Rng(70 + i), 4);
  const a = ['footman', 'footman', 'spearman', 'spearman', 'crossbowman', 'crossbowman'].map((t, k) => soldier(t, 300 + i * 10 + k, `p${k}`));
  setups[`laststand:${i}`] = clone(buildBattle(roll, a, { survivalBonus: 0 }));
}

// The open field of the original tests: generateMap('forest_clearing', seed) with
// every tile turned to flat grass. Only its size and deployment ground matter.
const { generateMap } = await import('../../../game/src/battle/mapgen');
const fields: Record<string, unknown> = {};
for (const seed of [3, 5, 7, 9, 10, 11, 12, 21, 22, 23, ...Array.from({ length: 15 }, (_, i) => 41 + i)]) {
  const map = generateMap('forest_clearing', seed);
  for (const t of map.tiles) {
    t.prop = undefined;
    t.h = 0;
    t.terrain = 'grass';
  }
  map.outer = [];
  map.outerGround = undefined;
  fields[seed] = clone(map);
}

const text = JSON.stringify({ version: 1, units, setups, fields });
writeFileSync(join(outDir, 'fixtures.json'), text + '\n');
console.log(`fixtures.json ${(text.length / 1e6).toFixed(2)} MB: ${Object.keys(units).length} units, ${Object.keys(setups).length} setups, ${Object.keys(fields).length} fields`);
void (0 as unknown as Dir);
