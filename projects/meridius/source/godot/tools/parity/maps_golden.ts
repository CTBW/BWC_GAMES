// Golden battle maps from the original generator (src/battle/mapgen.ts):
// every template, with every option combination the game uses, for many seeds.
//   cd projects/meridius/source/game && npx vite-node ../godot/tools/parity/maps_golden.ts
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { generateMap, inApproach, propBlocks, type MapGenOptions } from '../../../game/src/battle/mapgen';
import { BATTLE_MAPS } from '../../../game/src/data/maps';
import { PROPS } from '../../../game/src/data/terrain';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '..', '..', 'tests', 'fixtures', 'golden');
mkdirSync(out, { recursive: true });

// Options as buildBattle passes them (ambush flag + the unique wave edges after
// the main edge), plus the bare call the tests use.
const OPTS: (MapGenOptions | null)[] = [
  null,
  { ambush: false, approaches: ['n'] },
  { ambush: true, approaches: ['n'] },
  { ambush: false, approaches: ['n', 'w'] },
  { ambush: false, approaches: ['n', 'e'] },
  { ambush: false, approaches: ['n', 'w', 'e'] },
  { ambush: false, approaches: ['n', 'e', 'w'] },
  { ambush: true, approaches: ['n', 'w', 'e'] },
];
const SEEDS = [1, 2, 3, 7, 42, 1234, 987654321, 2147483646];

const cases: { template: string; seed: number; opts: MapGenOptions | null; map: unknown; approach: unknown[] }[] = [];
for (const id of Object.keys(BATTLE_MAPS)) {
  OPTS.forEach((opts, oi) => {
    // All seeds for the bare call, a rotating handful for each option set.
    const seeds = oi === 0 ? SEEDS : SEEDS.filter((_, i) => i % 7 === oi - 1 || (i + 3) % 7 === oi - 1);
    for (const seed of seeds) {
      const map = opts ? generateMap(id, seed, opts) : generateMap(id, seed);
      // inApproach samples just outside each edge.
      const approach: unknown[] = [];
      for (const [x, y] of [[-1, -1], [3, -2], [map.w - 2, -5], [-3, 4], [map.w + 1, 5], [5, map.h + 2], [map.w, map.h], [-8, 2], [10, -8]]) {
        approach.push([x, y, inApproach(map, x, y) ?? null]);
      }
      cases.push({ template: id, seed, opts, map, approach });
    }
  });
}
const props = Object.keys(PROPS).map((p) => [p, propBlocks(p)]);
props.push(['', propBlocks(undefined)]);

writeFileSync(join(out, 'map_golden.json'), JSON.stringify({ cases, propBlocks: props }) + '\n');
console.log(`map_golden.json: ${cases.length} maps`);
