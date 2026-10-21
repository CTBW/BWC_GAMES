// Fixtures for the battle view from the original game:
//  - formation.json: formation slots, slot assignment, casualty picks, squad
//    members and a fall/re-form sequence (golden data for formation/squad_view);
//  - setups/<name>.json: BattleSetups of the battles the original's review
//    scripts capture (same new-game seed, encounter and seed as the scripts), so
//    the view can be built and captured before setup.gd exists.
//   cd projects/meridius/source/game && npx vite-node ../godot/tools/parity/battleview_fixtures.ts
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Rng } from '../../../game/src/core/rng';
import type { Dir } from '../../../game/src/core/types';
import { buildBattle, rollEncounter } from '../../../game/src/battle/setup';
import { newGame } from '../../../game/src/meta/game';
import { makeEnemy, newSoldier, soldierToUnit } from '../../../game/src/meta/soldier';
import { assignSlots, formationSlots, pickCasualties } from '../../../game/src/render/formation';
import { killMembers, makeMembers, reform, standing, stepMembers, type Member } from '../../../game/src/render/squadView';
import { BATTLE_MAPS } from '../../../game/src/data/maps';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '..', '..', 'tests', 'fixtures', 'battle_view');
mkdirSync(join(out, 'setups'), { recursive: true });

// ---------------------------------------------------------------- formation golden

const slots: unknown[] = [];
for (const [size, type] of [[6, undefined], [3, undefined], [9, 'goblin_rabble'], [4, 'wolf_rider'], [4, 'goblin_horn'], [6, 'goblin_rabble']] as [number, string | undefined][]) {
  for (let n = 0; n <= size; n++)
    for (const f of [0, 1, 2, 3] as Dir[])
      for (const tight of [0.84, 0.92, 1]) slots.push({ n, size, f, tight, type: type ?? '', slots: formationSlots(n, size, f, tight, type) });
}
const assign: unknown[] = [];
const rng = new Rng(99);
for (let c = 0; c < 40; c++) {
  const size = rng.pick([3, 6, 6, 9]);
  const n = rng.int(1, size);
  const f0 = rng.int(0, 3) as Dir;
  const f1 = rng.int(0, 3) as Dir;
  const from = formationSlots(Math.min(size, n + rng.int(0, 2)), size, f0, 1, size === 9 ? 'goblin_rabble' : undefined).slice(0, n);
  const to = formationSlots(n, size, f1, rng.pick([0.84, 1]), size === 9 ? 'goblin_rabble' : undefined);
  const pinned = rng.chance(0.3) ? rng.int(0, n - 1) : -1;
  assign.push({ positions: from, slots: to, pinned, out: assignSlots(from, to, pinned) });
}
const casualties: unknown[] = [];
for (let c = 0; c < 40; c++) {
  const n = rng.int(1, 6);
  const pos = formationSlots(n, 6, rng.int(0, 3) as Dir);
  const standingIdx = pos.map((_, i) => i).filter(() => rng.chance(0.8));
  const k = rng.int(0, 6);
  const from = { x: rng.range(-1, 1), y: rng.range(-1, 1) };
  const prot = rng.chance(0.3) ? rng.int(0, n - 1) : -1;
  casualties.push({ positions: pos, standing: standingIdx, k, from, protected: prot, out: pickCasualties(pos, standingIdx, k, from, prot) });
}
let nid = 0;
const footmen = (seed: number) => soldierToUnit(newSoldier(new Rng(seed), 'footman', 1, () => `f${nid++}`, 0));
const units = [footmen(7), footmen(3), makeEnemy('orc_warlord', 1, 'w', new Rng(2)), makeEnemy('troll', 1, 't3', new Rng(3)), makeEnemy('goblin_rabble', 1, 'gr', new Rng(4)), makeEnemy('wolf_rider', 1, 'wr7', new Rng(5)), makeEnemy('goblin_spear', 1, 'e12', new Rng(6))];
units[1].facing = 2;
units[6].alive = 4;
const memberFields = (m: Member) => ({ id: m.id, alive: m.alive, x: m.x, y: m.y, toX: m.toX, toY: m.toY, phase: m.phase, type: m.type, variant: m.variant, fallFlip: m.fallFlip });
const members = units.map((u) => ({ unit: u, members: makeMembers(u).map(memberFields) }));
// A sequence: two fall to a blow from the left, the rest re-form, time passes.
const seqUnit = footmen(7);
const seq = makeMembers(seqUnit);
const fallen = killMembers(seq, 2, { x: -1, y: 0 }, -1);
reform(seq, seqUnit.size, seqUnit.facing, { dur: 0.3, stagger: 0.04 });
const corpses: number[] = [];
const frames: unknown[] = [];
for (let i = 0; i < 60; i++) {
  stepMembers(seq, 1 / 30, (m) => corpses.push(m.id));
  if (i % 6 === 0) frames.push(seq.map((m) => [m.x, m.y, m.deathT, m.flash, m.t]));
}
const sequence = { unit: seqUnit, fallen: fallen.map((m) => m.id), corpses, frames, final: seq.map(memberFields), standing: standing(seq).length };

writeFileSync(join(out, 'formation.json'), JSON.stringify({ slots, assign, casualties, members, sequence }) + '\n');
console.log('formation.json written');

// ---------------------------------------------------------------- battle setups

/** The store's debug.testBattle: a new game's first six soldiers against an encounter. */
function testBattle(newGameSeed: number, encounter: string, opts: { seed?: number; mapId?: string; darkness?: boolean; night?: boolean } = {}) {
  const g = newGame(newGameSeed);
  const roll = rollEncounter(encounter, new Rng(opts.seed ?? 7), 2);
  if (opts.mapId) roll.mapId = opts.mapId;
  const army = g.roster.slice(0, 6).map((so) => soldierToUnit(so));
  const setup = buildBattle(roll, army, { survivalBonus: 0, darkness: opts.darkness });
  return { name: '', night: !!opts.night, encounter, opts, newGameSeed, setup };
}

const cases: [string, number, string, { seed?: number; mapId?: string; darkness?: boolean; night?: boolean }][] = [
  ['trolls', 7, 'moss_trolls', { seed: 7 }],
  ['overseer', 7, 'orc_overseer', { seed: 7 }],
  ['last_stand', 3, 'last_stand', { seed: 7 }],
  ['scouts_clearing', 3, 'goblin_scouts', { seed: 7, mapId: 'forest_clearing' }],
  ['lab_clearing', 3, 'raiding_party', { seed: 5, mapId: 'forest_clearing' }],
  ['night_torch', 5, 'road_ambush', { seed: 8, night: true, darkness: false }],
  ['night_dark', 5, 'road_ambush', { seed: 9, night: true, darkness: true }],
  ['river', 5, 'orc_overseer', { mapId: 'river_ruins', seed: 4 }],
  ['camp', 5, 'warband_camp', { mapId: 'goblin_camp', seed: 5 }],
  ['refugee_stand', 3, 'refugee_stand', { seed: 7 }],
];
const index: string[] = [];
for (const [name, ng, enc, opts] of cases) {
  const c = testBattle(ng, enc, opts);
  c.name = name;
  writeFileSync(join(out, 'setups', `${name}.json`), JSON.stringify(c) + '\n');
  index.push(name);
  console.log(`setups/${name}.json`, c.setup.map.id, c.setup.map.w, 'x', c.setup.map.h, c.setup.units.length, 'units', (c.setup.waves ?? []).length, 'waves');
}
writeFileSync(join(out, 'setups', 'index.json'), JSON.stringify({ cases: index, maps: Object.keys(BATTLE_MAPS) }) + '\n');
