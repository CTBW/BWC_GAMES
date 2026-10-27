// Inbound original-image downloads only. Never submits generation or uses account credentials.
// Populate .cache/terrain-art/jobs.json from original links actually observed in the website.
import { readFile, writeFile, mkdir, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../../../../', import.meta.url));
// Full-size originals stay local; build.mjs writes the card's WebP copies.
const destination = path.join(root, 'local/workspace-originals/2026-10-20_meridius/terrain/originals');
const jobs = JSON.parse(await readFile(path.join(root, '.cache/terrain-art/jobs.json'), 'utf8'));
const catalogue = JSON.parse(await readFile(path.join(root, 'workspace/2026-10-20_meridius/terrain/prompts.json'), 'utf8'));
const allowedIds = new Set(catalogue.items.map(x => x.id));
const checkOnly = process.argv.includes('--check');
const candidates = jobs.filter(x => x.url && ['completed', 'awaiting_review', 'accepted', 'rejected'].includes(x.status));
for (const job of candidates) {
  const url = new URL(job.url);
  if (url.protocol !== 'https:' || url.hostname !== 'd8j0ntlcm91z4.cloudfront.net' || url.username || url.password || !/^\/user_[A-Za-z0-9]+\/hf_\d{8}_\d{6}_[a-f0-9-]+\.png$/.test(url.pathname)) throw new Error('Unexpected original-image source; inspect the new website origin before changing this allowlist.');
  if (!allowedIds.has(job.id) || !Number.isInteger(job.take) || job.take < 1 || job.take > 99) throw new Error('Invalid prompt ID or take.');
  const filename = `${job.id}__take-${String(job.take).padStart(2, '0')}.png`;
  const target = path.resolve(destination, filename);
  if (path.dirname(target) !== destination) throw new Error('Destination outside terrain folder.');
  if (checkOnly) continue;
  try { const existing = await stat(target); if (existing.size > 0) { console.log(JSON.stringify({ filename, status: 'already_saved' })); continue; } }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  const response = await fetch(url, { signal: AbortSignal.timeout(55000), redirect: 'error' });
  if (!response.ok) throw new Error(`Download failed: ${response.status}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length < 24 || bytes.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') throw new Error('Original is not a PNG.');
  const width = bytes.readUInt32BE(16), height = bytes.readUInt32BE(20);
  if (Math.min(width, height) < 1024 || Math.max(width, height) < 1900) throw new Error('Image is smaller than the requested 2K original.');
  await mkdir(destination, { recursive: true });
  await writeFile(target, bytes, { flag: 'wx' });
  console.log(JSON.stringify({ filename, status: 'saved', bytes: bytes.length, width, height }));
}
console.log(JSON.stringify({ checkOnly, checked: candidates.length, destination: 'local/workspace-originals/2026-10-20_meridius/terrain/originals' }));
