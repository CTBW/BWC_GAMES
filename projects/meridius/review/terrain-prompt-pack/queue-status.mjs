// Read-only status check. It never controls a browser or submits a generation.
import { readFile } from 'node:fs/promises';
const root = new URL('../../../../', import.meta.url);
const load = async name => JSON.parse((await readFile(new URL(name, root), 'utf8')).replace(/^\uFEFF/, ''));
const queue = await load('.cache/terrain-art/queue.json');
const jobs = await load('.cache/terrain-art/jobs.json');
let iconState, iconQuality;
try {
  iconState = await load('.cache/ability-art/state.json');
  iconQuality = await load('.cache/ability-art/quality-plan.json');
} catch (error) { if (error.code !== 'ENOENT') throw error; }
const iconCorrections = iconQuality?.items?.filter(x => x.kind === 'Icon' && x.status !== 'accepted') ?? null;
const iconFilesComplete = Boolean(iconState && Array.isArray(iconState.remainingIcons) && iconState.remainingIcons.length === 0 && iconCorrections && iconCorrections.length === 0);
const iconSlotFree = Boolean(iconState && !iconState.currentJob);
const activeJobs = jobs.filter(x => ['queued', 'waiting', 'submitted', 'in_progress'].includes(x.status));
const nextId = queue.order.find(id => queue.items.find(x => x.id === id)?.status === 'pending');
console.log(JSON.stringify({
  status: queue.status,
  generationMode: 'unlimited',
  unlimitedRequired: true,
  iconDependency: false,
  remainingIconCorrections: iconCorrections?.length ?? 'unknown',
  iconFilesComplete,
  iconSlotFree,
  activeTerrainJobs: activeJobs.length,
  nextPreparedPrompt: nextId ?? null,
  readyToSubmit: false,
  note: 'Verify the live terrain tab, Nano Banana Pro, 2K, reference attachments and Unlimited ON (green) and the Unlimited submit label before submitting. The icon tab is independent and must remain untouched.',
  uiGate: queue.uiGate,
}, null, 2));
