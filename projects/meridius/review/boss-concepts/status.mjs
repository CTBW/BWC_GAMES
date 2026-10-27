import { readFile } from 'node:fs/promises';
import { generationOrder, imageSubjects } from './catalog.mjs';
const root = new URL('../../../../', import.meta.url);
const read = async path => JSON.parse((await readFile(new URL(path, root), 'utf8')).replace(/^\uFEFF/, ''));
const terrain = await read('.cache/terrain-art/queue.json');
const jobs = await read('.cache/terrain-art/jobs.json');
const counts = {};
for (const item of terrain.items ?? []) counts[item.status] = (counts[item.status] ?? 0) + 1;
const active = jobs.filter(j => ['queued', 'waiting', 'submitted', 'pending', 'in_progress', 'generating'].includes(j.status));
const required = (terrain.items ?? []).filter(item => !item.optional);
const requiredRemaining = required.filter(item => item.status !== 'completed');
const terrainRequiredComplete = required.length > 0 && requiredRemaining.length === 0 && active.length === 0;
console.log(JSON.stringify({
  terrainStatus: terrain.status,
  terrainUpdated: terrain.updated,
  terrainCounts: counts,
  terrainRequiredComplete,
  requiredTerrainRemaining: requiredRemaining.map(({id, status}) => ({id, status})),
  optionalTerrainRemaining: (terrain.items ?? []).filter(item => item.optional && item.status !== 'completed').length,
  activeTerrainJobs: active.map(({id, status}) => ({id, status})),
  bossConceptsPrepared: generationOrder.length,
  imagePromptsPrepared: imageSubjects.length,
  firstBoss: generationOrder[0],
  requiredMode: 'Unlimited ON; verify live green switch and credit balance',
  readyToSubmit: false,
  reason: !terrainRequiredComplete ? 'Required terrain work or an active terrain job is still unfinished.' : 'All required terrain concepts are complete. Optional materials do not block boss work. Verify browser availability and live generation settings before submission.',
  automaticWorkerInstalled: false
}, null, 2));
