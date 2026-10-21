// Golden vectors for the core helpers (Rng, hashString, hash2) from the original.
//   cd projects/meridius/source/game && npx vite-node ../godot/tools/parity/core_vectors.ts
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Rng, hashString, hash2 } from '../../../game/src/core/rng';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '..', '..', 'tests', 'fixtures', 'golden');
mkdirSync(out, { recursive: true });

const seeds: (number | string)[] = [0, 1, 7, 42, 12345, 2147483646, 4294967295, 0x9e3779b9, 'abc', 'Meridius', 1.75e9];
const rng = seeds.map((seed) => {
  const r = new Rng(seed);
  const next = Array.from({ length: 8 }, () => r.next());
  const ints = Array.from({ length: 8 }, () => r.int(-3, 11));
  const ranges = Array.from({ length: 4 }, () => r.range(0.5, 2.5));
  const chances = Array.from({ length: 6 }, () => r.chance(0.4));
  const pick = Array.from({ length: 6 }, () => r.pick(['a', 'b', 'c', 'd', 'e']));
  const weighted = Array.from({ length: 6 }, () => r.weighted([1, 2, 3, 4], (x) => (x === 2 ? 0 : x * 1.5)));
  const shuffled = r.shuffle([1, 2, 3, 4, 5, 6, 7, 8, 9]);
  const child = r.fork('child');
  const fork = [child.state, child.next(), child.next()];
  return { seed, state0: new Rng(seed).state, next, ints, ranges, chances, pick, weighted, shuffled, fork, stateEnd: r.state };
});
const hashes = ['', 'a', 'footman', 'The Hillsvain Raids', 'ÅÄÖ', 'battle:42:forest'].map((s) => [s, hashString(s)]);
const h2: [number, number, number, number][] = [];
for (const [x, y, s] of [
  [0, 0, 0],
  [1, 2, 3],
  [-5, 7, 99],
  [123, -45, 4294967295],
  [17, 23, 2654435769],
  [3.5, 2.25, 11],
  [-40, -40, 123456789],
]) h2.push([x, y, s, hash2(x, y, s)]);

writeFileSync(join(out, 'core_vectors.json'), JSON.stringify({ rng, hashes, hash2: h2 }, null, 1) + '\n');
console.log('core_vectors.json written');
