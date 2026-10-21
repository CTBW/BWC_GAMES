// Exports the original game's data tables (src/data/*.ts) to JSON for the Godot
// port. Run from the TypeScript project so its toolchain resolves:
//   cd projects/meridius/source/game && npx vite-node ../godot/tools/export_data.ts
// Every non-function export of each module becomes a key of data/<module>.json.

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as abilities from '../../game/src/data/abilities';
import * as buildings from '../../game/src/data/buildings';
import * as campaigns from '../../game/src/data/campaigns';
import * as encounters from '../../game/src/data/encounters';
import * as events from '../../game/src/data/events';
import * as items from '../../game/src/data/items';
import * as maps from '../../game/src/data/maps';
import * as names from '../../game/src/data/names';
import * as terrain from '../../game/src/data/terrain';
import * as units from '../../game/src/data/units';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '..', 'data');
mkdirSync(out, { recursive: true });

const modules: Record<string, Record<string, unknown>> = { abilities, buildings, campaigns, encounters, events, items, maps, names, terrain, units };

for (const [name, mod] of Object.entries(modules)) {
  const table: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(mod)) {
    if (typeof v === 'function') continue;
    table[k] = v;
  }
  const json = JSON.stringify(
    table,
    (_k, v) => {
      if (typeof v === 'number' && !Number.isFinite(v)) throw new Error(`${name}: non-finite number`);
      return v;
    },
    1,
  );
  writeFileSync(join(out, `${name}.json`), json + '\n');
  console.log(`${name}.json: ${Object.keys(table).join(', ')}`);
}
