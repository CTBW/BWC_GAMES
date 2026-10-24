// Numeric render fixtures from the original (no browser needed):
//   cd projects/meridius/source/game && npx vite-node ../godot/tools/parity/render_fixtures_data.ts
// Writes godot/tests/fixtures/render/render_values.json: fbm samples (terrain.ts),
// the iso projection, and Atmosphere cloud layouts (atmosphere.ts).
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { fbm } from '../../../game/src/render/terrain';
import { isoX, isoY, fromIso, makeCamera, updateCamera, worldToScreen, screenToWorld } from '../../../game/src/render/iso';
import { hash2 } from '../../../game/src/core/rng';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '..', '..', 'tests', 'fixtures', 'render');
mkdirSync(out, { recursive: true });

const fbmSamples: [number, number, number, number][] = [];
for (const seed of [1, 4242, 1517650525, 2147483646, 1806701596 + 77])
  for (const [x, y] of [[0, 0], [0.13, 4.94], [12.7, 3.3], [37 * 0.13, 21 * 0.13], [5.5, 0.25], [99.9, 101.1], [-3.2, 7.7]]) fbmSamples.push([x, y, seed, fbm(x, y, seed)]);

const iso: number[][] = [];
for (const [x, y, h] of [[0, 0, 0], [3, 7, 0], [-2.5, 4.25, 1], [13, 11, 2]]) iso.push([x, y, h, isoX(x, y), isoY(x, y, h)]);
const inv: number[][] = [];
for (const [sx, sy] of [[0, 0], [128, 64], [-300, 517], [1234.5, -88]]) {
  const p = fromIso(sx, sy);
  inv.push([sx, sy, p.x, p.y]);
}

// Camera smoothing: 10 steps of 1/60 s toward a target.
const cam = makeCamera(100, 200, 1);
cam.tx = 400;
cam.ty = -50;
cam.tzoom = 0.5;
cam.shake = 0.5;
const steps: number[][] = [];
for (let i = 0; i < 10; i++) {
  updateCamera(cam, 1 / 60);
  steps.push([cam.x, cam.y, cam.zoom, cam.shake]);
}
const proj = [worldToScreen(cam, 321, -45, 1920, 1080), screenToWorld(cam, 17, 1000, 1920, 1080)];

// Atmosphere clouds for a few seeds (constructor only uses hash2).
const clouds: Record<string, unknown> = {};
for (const seed of [1, 77, 1517650525, 1130496762]) {
  const list = [];
  for (let i = 0; i < 7; i++) list.push({ x: hash2(i, 1, seed) * 3000 - 1500, y: hash2(i, 2, seed) * 2000 - 1000, r: 260 + hash2(i, 3, seed) * 380, s: 0.6 + hash2(i, 4, seed) * 0.6 });
  clouds[seed] = list;
}

writeFileSync(join(out, 'render_values.json'), JSON.stringify({ fbm: fbmSamples, iso, inv, cameraSteps: steps, proj, clouds }) + '\n');
console.log('render_values.json written');
