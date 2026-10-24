// Golden data for the magic-and-machines view changes (formation.ts crewSlots /
// engineOffset and the casters' triangle, squadView.ts memberScale /
// memberHeight / makeMembers with crews), kept apart from battleview_fixtures.ts
// so its setups need not be regenerated:
//   tests/fixtures/battle_view/formation_engines.json
//   cd projects/meridius/source/game && npx vite-node ../godot/tools/parity/battleview_engines.ts
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Rng } from '../../../game/src/core/rng';
import type { Dir } from '../../../game/src/core/types';
import { UNIT_TYPES } from '../../../game/src/data/units';
import { makeEnemy, newSoldier, soldierToUnit } from '../../../game/src/meta/soldier';
import { engineOffset, formationSlots } from '../../../game/src/render/formation';
import { makeMembers, memberHeight, memberScale, type Member } from '../../../game/src/render/squadView';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '..', '..', 'tests', 'fixtures', 'battle_view');
mkdirSync(out, { recursive: true });

const TYPES = ['battle_mage', 'goblin_shaman', 'ballista', 'mangonel', 'rock_lobber', 'war_wagon', 'troll'];

const slots: unknown[] = [];
for (const type of TYPES) {
  for (let n = 0; n <= 3; n++)
    for (const f of [0, 1, 2, 3] as Dir[])
      for (const tight of [0.84, 1]) slots.push({ n, size: 3, f, tight, type, slots: formationSlots(n, 3, f, tight, type) });
}
const engine = ([0, 1, 2, 3] as Dir[]).map((f) => ({ f, offset: engineOffset(f) }));

const memberFields = (m: Member) => ({ id: m.id, alive: m.alive, x: m.x, y: m.y, toX: m.toX, toY: m.toY, phase: m.phase, type: m.type, variant: m.variant, fallFlip: m.fallFlip });
const units = TYPES.map((type, i) => {
  const u = UNIT_TYPES[type].faction === 'player'
    ? soldierToUnit(newSoldier(new Rng(40 + i), type, 1, () => `s${i}`, 0))
    : makeEnemy(type, 1, `e${i}`, new Rng(60 + i));
  u.facing = (i % 4) as Dir;
  if (i === 2) u.alive = 2;
  return u;
});
const members = units.map((u) => ({
  unit: u,
  scale: memberScale(u),
  height: memberHeight(u.typeId),
  members: makeMembers(u).map(memberFields),
}));

writeFileSync(join(out, 'formation_engines.json'), JSON.stringify({ slots, engine, members }) + '\n');
console.log('formation_engines.json written:', slots.length, 'slot cases,', members.length, 'squads');
