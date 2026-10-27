import { readFile, writeFile, mkdir, copyFile } from 'node:fs/promises';
import { existsSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { entries, groups, pilotOrder } from './catalog.mjs';
import { imageSize, webpCopies, webpName, workspaceOriginals } from './webp.mjs';

const root = fileURLToPath(new URL('../../../../', import.meta.url));
const reportDir = path.join(root, 'workspace/2026-10-20_meridius');
const docsDir = path.join(root, 'projects/meridius/docs');
const runtimeDir = path.join(root, '.cache/terrain-art');
const items = entries();
const refs = [
  ['image-221739-055e50d8.png', 'style-lush.png', 'Reference 1 — lush forest and meadow'],
  ['image-221751-105df80c.png', 'style-golden.png', 'Reference 2 — golden grass and natural slopes'],
];
const esc = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
await mkdir(path.join(reportDir, 'terrain/references'), { recursive: true });
await mkdir(path.join(reportDir, 'terrain/originals'), { recursive: true });
await mkdir(runtimeDir, { recursive: true });
for (const [source, name] of refs) {
  await copyFile(path.join(root, 'inbox/attachments/2026-10-22', source), path.join(reportDir, 'terrain/references', name));
}
// The card shows WebP copies; the PNG originals and captures stay in local/workspace-originals/.
const localTerrain = path.join(workspaceOriginals, '2026-10-20_meridius/terrain');
await mkdir(path.join(reportDir, 'terrain/review'), { recursive: true });
webpCopies(['originals', 'review'].flatMap(folder => {
  const dir = path.join(localTerrain, folder);
  return existsSync(dir) ? readdirSync(dir).filter(name => name.endsWith('.png')).map(name => [path.join(dir, name), path.join(reportDir, 'terrain', folder, webpName(name))]) : [];
}));

const execution = `## Brave execution contract

- Use the dedicated terrain tab in the logged-in Brave session. The user updated the instruction on 23 October: keep Unlimited ON (green), check before each submission and re-enable if it changes. Leave the icon tab and its Unlimited workflow untouched.
- Use the Higgsfield website, Nano Banana Pro, 2K, one image per submission. Check the aspect ratio, references, exact prompt, quantity one and Unlimited ON before each submission. Earlier 59 regular-mode submissions displayed an estimated 2 credits each; this is not a billing reconciliation. New submissions use Unlimited as now requested. Do not buy credits or change plans.
- Night edits now use only the matching reviewed daytime original, preserving its exact layout while changing lighting. Earlier three-reference jobs retain their submitted prompts in the ignored receipts. Wider road scenes use the original two style references.
- For day concepts, attach reference 1 then reference 2 from the local reference folder. Night edits use the matching reviewed daytime original alone. The full prompt states each image's role. Do not reuse the ability-icon references. Start with the six pilot prompts below and visually check their match to the supplied art; the supplied references already establish the requested direction, so routine matching corrections do not need a new user decision.
- Save originals inside workspace/2026-10-20_meridius/terrain/originals/. Use PROMPT_ID__take-01.png, then increment the take number. Keep every original. This destination is inside the writable workspace; do not change global browser download or security settings.
- Record the submitted asset ID and status immediately in .cache/terrain-art/jobs.json. Record any original download URL only in that ignored file. On a timeout, inspect that same job. Never resubmit solely because a wait expired. If submission may have succeeded but its ID was not captured, reconcile the website history before retrying.
- The fixed local downloader validates known original-image URLs, PNG dimensions and destination names. Local writes stay inside the workspace. Restricted network access may still require a narrowly scoped download-command approval; no script can remove platform approval requirements.
- Check each original at full size and at a reduced game-like size. Accept only after reviewing camera, silhouette, complete framing, material style, lighting, unwanted reference fragments and requested content. For cutouts, inspect every gap and the background edge. For scenes, inspect movement space and continuous slopes. For materials, inspect a 3-by-3 repeat before acceptance.
- Make targeted correction takes using the failed image as an additional explicitly assigned reference, preserving everything except the named defect. After three failed takes on one item, preserve the evidence and move on to the next independent item; report the unresolved item.
- No additional user approvals are needed for already-authorized prompts, reference uploads, visual corrections or workspace saves. If the tool cannot identify the page, authentication is required, or an actual permission boundary is reached, stop the dependent action and retain progress. Do not buy credits, change account settings or bypass a blocked UI tool.
- This is an agent-run queue, not an installed unattended browser service. Generation started with regular credits and now continues in Unlimited mode; the reviewed local originals are listed in this report. Recover recorded jobs before submitting new takes.

## Generation order

First: ${pilotOrder.map(id => items.find(item => item.id === id).title).join(', ')}. Then the remaining required prompts in catalogue order. The eight ground materials are optional companions after the requested objects and scenes; existing terrain textures remain intact.

## Delivery checks

Preserve editable prompt sources and original images. Generated art is not yet a Godot-ready sprite, seamless texture or playable map. Cutouts still require extraction, scale and anchor checks; scene designs require layout and navigation work; texture seams require verification. Keep game integration as a separate step and do not edit the frozen TypeScript game.
`;

const intro = `# Meridius terrain and town art prompts

Prepared 23 October 2026. ${items.filter(x => !x.optional).length} requested object and scene prompts, plus ${items.filter(x => x.optional).length} optional ground materials. Day prompts use the two supplied style references; night prompts use the matching reviewed daytime image alone for a strict lighting edit. Generation uses Nano Banana Pro through the Higgsfield website in Brave, with Unlimited on under the latest user instruction.

## Reference images and art direction

1. [Lush battlefield reference](../../../workspace/2026-10-20_meridius/terrain/references/style-lush.png): primary camera, vegetation, materials and colour balance.
2. [Golden battlefield reference](../../../workspace/2026-10-20_meridius/terrain/references/style-golden.png): warmer grass, weathered rock and rounded slope detail.

Match the supplied terrain art: detailed painted shapes, clustered foliage, warm lit planes, cool green-blue shade, readable silhouettes and continuous hills. Exclude soldiers, creatures, health bars and movement overlays from both references. The environment style is more detailed than the 32-pixel ability icons.

The earlier terrain conversation identified [Drova — Forsaken Kin](https://store.steampowered.com/app/1585180/) and [Age of Empires II: Definitive Edition](https://store.steampowered.com/app/813780/) as inspiration. Use these as secondary reference sources for woodland atmosphere and legible settlement construction; the two user-supplied images govern this pack. The game pages were checked on 23 October 2026. No third-party screenshots are copied into the pack.

${execution}
## Prompt catalogue

Each item lists its filename, aspect ratio and image role. Day concepts use both local style references in order; night edits use only the matching reviewed daytime image. Set 2K in the website UI; prompt text alone does not set the model, resolution or Unlimited mode.
`;
let markdown = intro;
for (const [group] of groups) {
  markdown += `\n### ${group}\n`;
  for (const item of items.filter(x => x.group === group)) {
    markdown += `\n#### ${item.title}\n\nID: \`${item.id}\` · ${item.aspect} · 2K · ${item.kind}${item.optional ? ' · optional' : ''}\n\nSave as \`${item.filename}\`.\n\n\`\`\`text\n${item.prompt}\n\`\`\`\n`;
  }
}
await writeFile(path.join(docsDir, 'terrain-art-prompts.md'), markdown);
await writeFile(path.join(reportDir, 'terrain/prompts.txt'), items.map(x => `${x.title}\n${x.id} | ${x.aspect} | 2K | ${x.filename}\n\n${x.prompt}`).join('\n\n' + '='.repeat(72) + '\n\n'));
await writeFile(path.join(reportDir, 'terrain/prompts.json'), JSON.stringify({ version: 1, provider: 'Higgsfield website', browser: 'Brave', model: 'Nano Banana Pro', unlimitedRequired: true, references: refs.map(([, name]) => `references/${name}`), pilotOrder, items }, null, 2) + '\n');
await writeFile(path.join(reportDir, 'terrain/execution.md'), '# Meridius terrain generation workflow\n\n' + execution);

const requiredCount=items.filter(x=>!x.optional).length;
const review = JSON.parse(await readFile(path.join(reportDir, 'terrain/review.json'), 'utf8'));
const reviewedIds = new Set(review.images.map(image => image.id));
const remainingRequested = items.filter(item => !item.optional && !reviewedIds.has(item.id)).length;
const unresolvedConcepts = review.images.filter(image => image.status.startsWith('concept reference;'));
const referenceLibrary = JSON.parse(await readFile(path.join(reportDir, 'terrain/reference-library.json'), 'utf8'));
const referenceCollection = `<h2>Saved reference library</h2><p>${referenceLibrary.generatedOriginals} generated originals and the two supplied style guides are copied into the project reference folders. Every PNG is verified against its original. Day and night versions share a subject folder, and earlier takes are preserved.</p><p>Battlefields, roads, camps and sites: <code>projects/meridius/references/backgrounds/terrain/</code><br>Trees, rocks, buildings, terrain modules and style guides: <code>projects/meridius/references/style/terrain/</code></p><p>The local index is <code>projects/meridius/references/terrain-library.md</code>. Folder READMEs identify the selected takes and retain their review notes. <a href="terrain/reference-library.json" download>Download the complete file manifest</a>.</p>`;
// Put the latest reviewed subjects first in the long gallery.
review.images.reverse();
const gallery = '<h2>Generated sources</h2><p>Original Higgsfield outputs, reviewed on ' + review.date + '. Magenta backgrounds are not transparency. These sources have not been integrated into Godot.</p><div class="reference-grid">' + review.images.map(r => '<figure><a href="terrain/' + esc(webpName(r.file)) + '"><img src="terrain/' + esc(webpName(r.file)) + '" loading="lazy" alt="' + esc(items.find(i=>i.id===r.id).title) + '"></a><figcaption><strong>' + esc(items.find(i=>i.id===r.id).title) + '</strong> · ' + esc(r.status) + '<br>' + esc(r.note) + ' <a href="terrain/' + esc(webpName(r.file)) + '" download>Download</a></figcaption></figure>').join('') + '</div>';
const edgeGallery = '<h2>Battlefield and campaign edges</h2><p>The decorative off-map horde, its standards, torches and smoke were removed. Approaches now continue the surrounding grass with worn entry tracks. Reserves appear when they march in; wave rules and entry cells are unchanged. The campaign opens on the company, with ordinary forest and fog in the former horde corner. Native Godot captures, fixed fixture seeds, 1920 × 1080; no generated artwork is used in these views.</p><p><a href="terrain/map-edge-review.md">Change and verification record</a></p><div class="reference-grid">' + [['battle-before.webp','Before: decorative crowd beyond the battlefield'],['battle-after.webp','After: matching terrain and open approaches'],['battle_edges_river.webp','River battlefield after removal'],['campaign_edges_corner_0.webp','Campaign corner after removal']].map(([f,label])=>'<figure><a href="terrain/review/' + f + '"><img src="terrain/review/' + f + '" loading="lazy" alt="' + label + '"></a><figcaption>' + label + ' · <a href="terrain/review/' + f + '" download>Download</a></figcaption></figure>').join('') + '</div>';
const cards = groups.map(([group]) => `<section><h2>${esc(group)}</h2>${items.filter(x => x.group === group).map(item => `<details id="${item.id}" class="prompt"><summary>${esc(item.title)} <span class="meta">${item.aspect} · ${item.kind}${item.optional ? ' · optional' : ''}</span></summary><p><code>${item.filename}</code> · Nano Banana Pro · 2K · ${item.referenceCount===1?'matching reviewed daytime source only':'both style references'}</p><button type="button" class="copy">Copy full prompt</button><span class="copy-status" role="status"></span><pre>${esc(item.prompt)}</pre></details>`).join('')}</section>`).join('');
let html = `<!doctype html>
<html lang="en" data-mak-report="document"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Meridius terrain and town art prompts</title><link rel="stylesheet" href="../_shared/report.css"><link rel="stylesheet" href="../_shared/examples.css"><script defer src="../_shared/report.js"></script>
<style>
.reference-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}.reference-grid figure{margin:0}.reference-grid figcaption{font-size:13px;color:var(--mak-muted)}
.prompt{border:1px solid var(--mak-border);border-radius:10px;padding:14px 18px}.prompt summary{font-weight:600;color:var(--mak-text)}.prompt summary .meta{margin-left:12px;font-weight:400}.prompt pre{white-space:pre-wrap;overflow-wrap:anywhere;max-height:620px}.copy{font:inherit;border:1px solid var(--mak-border);border-radius:7px;padding:7px 13px;background:var(--mak-surface);color:var(--mak-text);cursor:pointer}.copy-status{margin-left:12px;color:var(--mak-muted)}.downloads{display:flex;gap:20px;flex-wrap:wrap}.prompt[hidden]{display:none}#filter{width:min(100%,540px);font:inherit;padding:10px;border:1px solid var(--mak-border);border-radius:7px;background:var(--mak-surface);color:var(--mak-text)}
html[data-terrain-theme=light]{--mak-bg:#faf8fa;--mak-surface:#fff;--mak-border:#ded8df;--mak-text:#302b34;--mak-muted:#645b6b;--mak-accent:#86405c;color-scheme:light}html[data-terrain-theme=light] :is(h1,h2,h3,strong,summary){color:var(--mak-text)}html[data-terrain-theme=light] :is(pre,code){color:#4b3341;background:#f1edf2}html[data-terrain-theme=light] .meta{color:var(--mak-muted)}
@media(prefers-color-scheme:light){html:not([data-terrain-theme=dark]){--mak-bg:#faf8fa;--mak-surface:#fff;--mak-border:#ded8df;--mak-text:#302b34;--mak-muted:#645b6b;--mak-accent:#86405c;color-scheme:light}html:not([data-terrain-theme=dark]) :is(h1,h2,h3,strong,summary){color:var(--mak-text)}html:not([data-terrain-theme=dark]) :is(pre,code){color:#4b3341;background:#f1edf2}}
</style></head><body><main class="container"><h1>Meridius terrain and town art prompts</h1><p class="lead">${requiredCount} requested images, including night locations, natural forest roads, deforested river landscapes and six palisaded army camps, plus 8 optional ground materials.</p><p><strong>Generation is underway through Higgsfield, now with Unlimited on as requested.</strong> ${review.images.length} subjects have review notes below. All original and correction takes are preserved locally. The separate icon session retains its Unlimited workflow.</p><p>Nano Banana Pro · Higgsfield website · Unlimited on · checked before each submission · 2K. WebP copies of the originals are in <code>terrain/originals/</code>; the full-size PNGs stay local.</p><p class="downloads"><a href="terrain/prompts.txt" download>Download all prompts</a><a href="terrain/prompts.json" download>Editable prompt data</a><a href="terrain/execution.md">Execution and recovery instructions</a></p><div class="reference-grid">${refs.map(([, name, label]) => `<figure><a href="terrain/references/${name}"><img src="terrain/references/${name}" alt="${esc(label)}" loading="lazy"></a><figcaption>${esc(label)} · <a href="terrain/references/${name}" download>Download</a></figcaption></figure>`).join('')}</div>${edgeGallery}${gallery}<h2>Art direction</h2><p>Keep the elevated isometric camera, layered painted foliage, worn stone and timber, warm highlights and cool forest shade. Build hills from continuous slopes and eroded banks. Remove the references' units, grids and health bars. Use single isolated objects for extraction and full landscape compositions for battlefield concepts.</p><p>The earlier terrain chat used <a href="https://store.steampowered.com/app/1585180/">Drova</a> and <a href="https://store.steampowered.com/app/813780/">Age of Empires II: Definitive Edition</a> as secondary inspiration. World of Warcraft environment concept art is additional landscape inspiration, especially organic landforms and naturally used roads; see <a href="https://www.weststudio.com/project/world-of-warcraft-tww">West Studio’s environment work</a>. The two supplied images remain the visual standard.</p><h2>Run order</h2><p>First compare the oak, meadow battlefield, cottage, arch, orc pit and dragon lair against the references. Then continue with the remaining required prompts. Ground materials are optional. Review each result before marking it accepted; keep originals and correction takes.</p><p>Each Copy button copies a complete prompt. Attach reference 1 and reference 2, and set the listed aspect ratio in the website. Magenta is an extraction background, not verified transparency. Scenes and modules still need engine preparation.</p><label for="filter">Find a prompt</label><p><input id="filter" type="search" placeholder="Tree, snow, wagon, town…"></p><p id="count" role="status">${items.length} prompts</p>${cards}</main><script>
document.querySelectorAll('.copy').forEach(button=>button.addEventListener('click',async()=>{const block=button.closest('.prompt');const text=block.querySelector('pre').textContent;try{await navigator.clipboard.writeText(text);block.querySelector('.copy-status').textContent='Copied';}catch{const selection=getSelection();const range=document.createRange();range.selectNodeContents(block.querySelector('pre'));selection.removeAllRanges();selection.addRange(range);block.querySelector('.copy-status').textContent='Prompt selected — press Ctrl+C';}}));
document.querySelector('#filter').addEventListener('input',event=>{const query=event.target.value.trim().toLowerCase();let count=0;document.querySelectorAll('.prompt').forEach(block=>{block.hidden=!block.textContent.toLowerCase().includes(query);if(!block.hidden)count++;});document.querySelector('#count').textContent=count+' prompts';});
</script></body></html>`;
// Reserve each image's space before lazy loading so long galleries do not jump.
for (const [, src] of [...html.matchAll(/<img src="([^"]+)"/g)]) {
  const { width, height } = imageSize(await readFile(path.join(reportDir, src)));
  html = html.replace(`<img src="${src}"`, `<img src="${src}" width="${width}" height="${height}" style="height:auto"`);
}
html = html.replace('deforested river landscapes and six palisaded army camps', 'deforested river landscapes, six palisaded army camps and four corrupted lands');
html = html.replace(' and four corrupted lands, plus', ', four corrupted lands and two northern forest comparisons, plus');
html = html.replace('Attach reference 1 and reference 2, and set the listed aspect ratio in the website.', 'For day concepts, attach reference 1 and reference 2. For night edits, attach only the matching reviewed daytime original. Set the listed aspect ratio in the website.');
html = html.replace('Generation is underway through Higgsfield, now with Unlimited on as requested.', remainingRequested
  ? review.generationState?.status === 'held_credit_discrepancy'
    ? `${remainingRequested} requested night view remains unsubmitted. Generation is held while a credit discrepancy is clarified, despite the form showing Unlimited.`
    : `Generation is underway through Higgsfield with Unlimited on. ${remainingRequested} requested subjects remain.`
  : 'All requested subjects now have reviewed concept images from Higgsfield.');
if (unresolvedConcepts.length) {
  html = html.replace('<h2>Generated sources</h2>', '<h2>Generated sources</h2><p><strong>' + unresolvedConcepts.length + ' isolated concepts still need cleanup:</strong> ' + unresolvedConcepts.map(image => esc(items.find(item => item.id === image.id).title)).join(', ') + '. Their review notes describe the remaining isolation or water-edge issues. All images still require normal asset preparation before engine use.</p>');
}
html = html.replace('<h2>Battlefield and campaign edges</h2>', referenceCollection + '<h2>Battlefield and campaign edges</h2>');
await writeFile(path.join(reportDir, 'terrain-prompts.html'), html);

// Initialize only. Rebuilding prompt text must never reset a live generation queue.
const queue = {
  version: 1, status: 'prepared_unlimited', browser: 'Brave', provider: 'Higgsfield website', model: 'Nano Banana Pro', quality: '2K', unlimitedRequired: true, maxConcurrent: 1,
  uiGate: 'Verify Nano Banana Pro, 2K, Unlimited on (green), and the correct references. Leave the icon session untouched.',
  destination: 'local/workspace-originals/2026-10-20_meridius/terrain/originals',
  references: refs.map(([, name]) => `workspace/2026-10-20_meridius/terrain/references/${name}`),
  order: [...pilotOrder, ...items.filter(x => !x.optional && !pilotOrder.includes(x.id)).map(x => x.id)],
  optionalOrder: items.filter(x => x.optional).map(x => x.id),
  items: items.map(x => ({ id: x.id, status: 'pending', take: 1, optional: x.optional })),
};
for (const [name, value] of [['queue.json', queue], ['jobs.json', []]]) {
  try { await writeFile(path.join(runtimeDir, name), JSON.stringify(value, null, 2) + '\n', { flag: 'wx' }); }
  catch (error) { if (error.code !== 'EEXIST') throw error; }
}
console.log(JSON.stringify({ prompts: items.length, required: items.filter(x => !x.optional).length, optional: items.filter(x => x.optional).length, report: 'workspace/2026-10-20_meridius/terrain-prompts.html', runtimePreserved: true }));
