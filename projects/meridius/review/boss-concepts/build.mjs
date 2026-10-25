import { readFile, writeFile, mkdir, copyFile, access } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { bosses, bossVariants, imageSubjects, generationOrder, newBossConcepts, imagePrompt } from './catalog.mjs';
import { webpCopies, webpName, workspaceOriginals } from '../terrain-prompt-pack/webp.mjs';

const root = fileURLToPath(new URL('../../../../', import.meta.url));
const reportDir = path.join(root, 'workspace/2026-10-20_meridius');
const out = path.join(reportDir, 'bosses');
const runtime = path.join(root, '.cache/boss-art');
const canonical = 'projects/meridius/references/characters/bosses/concepts';
const esc = s => String(s).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const selection = JSON.parse(await readFile(new URL('selection.json',import.meta.url),'utf8'));
const activeSubjects = selection.active.map(id=>imageSubjects.find(b=>b.id===id));
const ordered = activeSubjects.filter(b=>b.moves);
const activeVariants = bossVariants.filter(b=>selection.active.includes(b.id));
const production = JSON.parse(await readFile(new URL('production.json', import.meta.url), 'utf8'));
let delivered = [];
try { delivered = JSON.parse(await readFile(path.join(out,'delivery-manifest.json'),'utf8')).images; }
catch(error) { if(error.code!=='ENOENT')throw error; }
// Full-size PNGs stay in local/workspace-originals/; the report links WebP copies.
webpCopies(delivered.map(image=>[path.join(workspaceOriginals,'2026-10-20_meridius/bosses',image.file),path.join(out,webpName(image.file))]));
delivered.sort((a,b)=>imageSubjects.findIndex(s=>`boss_${s.id}`===a.subject)-imageSubjects.findIndex(s=>`boss_${s.id}`===b.subject)||a.take-b.take);
const reviews = JSON.parse(await readFile(new URL('reviews.json',import.meta.url),'utf8'));
const artwork = id => delivered.filter(image=>image.subject===`boss_${id}`).sort((a,b)=>['pale_colossus','giant_troll'].includes(id)?b.take-a.take:0).map(image=>{
  const review=reviews.find(r=>r.subject===image.subject&&r.take===image.take);
  return `<figure class="concept-art"><a href="bosses/${esc(webpName(image.file))}"><img loading="lazy" src="bosses/${esc(webpName(image.file))}" alt="${esc(imageSubjects.find(b=>b.id===id).name)} concept, take ${image.take}"></a><figcaption><strong>Take ${image.take} · ${image.width} × ${image.height}</strong> · ${image.inputMode==='text-only'?'Text-only design':image.inputMode==='targeted-reference-edit'?'Targeted correction':image.inputMode==='user-reference-redesign'?'User reference remake':'Earlier style-reference design'}<br>${esc(review?.summary||'Visual review pending.')} <a href="bosses/${esc(webpName(image.file))}" download>Download</a> · <a href="bosses/${esc(image.prompt)}" download>Submitted prompt</a></figcaption></figure>`;
}).join('');
const galleryImages = activeSubjects.map(s=>delivered.filter(i=>i.subject===`boss_${s.id}`).at(-1)).filter(Boolean);
const gallery = delivered.length ? `<section class="concept-gallery" id="concept-gallery"><h2>Current boss concepts</h2><p>Six active designs, including the ancient woodland troll revision and the aqua-eyed colossus. Click an image for the full-size preview. The latest troll image is an intermediate material study; its review notes identify remaining ear and composition issues. The next correction is prepared. The aqua-eye colossus awaits your review.</p><div class="reference-grid">${galleryImages.map(image=>{const b=imageSubjects.find(b=>`boss_${b.id}`===image.subject);return `<figure><a href="bosses/${esc(webpName(image.file))}"><img loading="lazy" src="bosses/${esc(webpName(image.file))}" alt="${esc(b.name)}, take ${image.take}"></a><figcaption><a href="#${b.id}">${esc(b.name)}</a> · take ${image.take}${b.id==='giant_troll'&&[5,6].includes(image.take)?' · intermediate study':selection.retained.includes(b.id)?' · retained':' · new'}</figcaption></figure>`;}).join('')}</div></section>`:'';
let verificationHtml = 'Report verification is recorded separately after visual review.';
try {
  const verified = JSON.parse(await readFile(path.join(runtime, 'verification.json'), 'utf8'));
  if (verified.errors.length === 0 && verified.promptCount === activeSubjects.length && verified.verifiedOriginals === delivered.length) verificationHtml = ['colossus-take-04','giant-troll-take-02','giant-troll-take-03','giant-troll-take-04','giant-troll-take-05','giant-troll-take-06','giant-troll-take-07'].includes(verified.scope) ? 'Latest boss revision checked in the desktop gallery: current take, preserved original, full-size preview, close controls, exact prompt, download links and local image hashes. Artwork was visually reviewed; gameplay has not been tested. <a href="bosses/report-checks.json">Verification record</a>.' : 'Checked at 1440 and 960 desktop widths in light and dark: local links, active prompts, eight erosion-diagram states, expandable details, full-size image previews, close controls, prompt copying and file downloads. This record checks report behavior. Artwork review notes appear beside each image; gameplay has not been tested. <a href="bosses/report-checks.json">Verification record</a>.';
} catch (error) { if (error.code !== 'ENOENT') throw error; }
for (const dir of [out, path.join(out, 'prompts'), path.join(out, 'references'), path.join(out, 'originals'), path.join(root,canonical,'briefs'), runtime]) await mkdir(dir, {recursive:true});
await copyFile(path.join(root, bosses.find(b => b.creatureReference).creatureReference), path.join(out, 'references/blood-crawler-user-reference.png'));
await copyFile(path.join(root, 'projects/meridius/docs/boss-encounter-direction.md'), path.join(out, 'direction.md'));
await copyFile(new URL('README.md', import.meta.url), path.join(out, 'generation-handoff.md'));
await copyFile(new URL('catalog.mjs', import.meta.url), path.join(out, 'catalog.mjs'));
await copyFile(new URL('revision-2026-10-24.mjs', import.meta.url), path.join(out, 'revision-2026-10-24.mjs'));
await copyFile(new URL('selection.json', import.meta.url), path.join(out, 'selection.json'));
await copyFile(new URL('production.json', import.meta.url), path.join(out, 'production.json'));
await copyFile(new URL('corrections.json', import.meta.url), path.join(out, 'corrections.json'));
await copyFile(new URL('stone-troll-style-review.json', import.meta.url), path.join(out, 'stone-troll-style-review.json'));
await copyFile(path.join(root,canonical,'references/approved-troll-shoulder-ruins.png'),path.join(out,'references/approved-troll-shoulder-ruins.png'));
webpCopies([[path.join(root,canonical,'references/meridius-footmen-style.png'),path.join(out,'references/meridius-footmen-style.webp')]]);
await copyFile(path.join(root,'projects/meridius/references/characters/bosses/README.md'),path.join(out,'asset-folders.md'));
await copyFile(path.join(root,'projects/meridius/references/characters/tripo/recovered-exports.json'),path.join(out,'tripo-recovered-exports.json'));

const prompts = activeSubjects.map(b => ({id:`boss_${b.id}`, name:b.name, ...(b.parentId ? {variantOf:`boss_${b.parentId}`} : {}), file:`boss_${b.id}__take-${String(b.take||1).padStart(2,'0')}.png`, aspect:'16:9', quality:'2K', inputMode:b.inputMode||'text-only', references:b.references||[], prompt:imagePrompt(b)}));
for (const p of prompts) {
  await writeFile(path.join(out, `prompts/${p.id}.txt`), p.prompt + '\n');
  await writeFile(path.join(root,canonical,`briefs/${p.id}.txt`),p.prompt+'\n');
}
await writeFile(path.join(out, 'prompts.json'), JSON.stringify({provider:'Higgsfield website', browser:'Brave', model:'Nano Banana Pro', unlimitedRequired:true, inputMode:'per-prompt', order:selection.active, prompts}, null, 2) + '\n');

let markdown = '# Meridius: current boss concepts\n\nUpdated 24 October 2026 from the user’s marked selection. The Giant Troll revision follows the supplied woodland troll species more closely, with living-stone surfaces, no ears and a shaggy dark beard. His smaller upright hulking silhouette and approved shoulder ruins remain central. The original unit sheets control painted style and the earlier terrain cottage controls ruin materials. The Pale Colossus replaces the buried Crown design. The user approved colossus take 3 and requested glowing aqua eyes. The colossus palette edit uses its pale first take; the focused head correction uses the darker second take. Take 4 edits only the eyes of the approved third take to glowing aqua. The plain mask without a nose or mouth, black and charcoal materials and dark-red details remain. Removed designs remain archived outside this active report.\n\nOriginal encounter proposals are not implemented gameplay or established canon. The two new visuals do not yet have encounter rule sets. See [design direction](boss-encounter-direction.md) for existing combat principles.\n';
for (const b of ordered) {
  markdown += `\n## ${b.name}\n\n*${b.kind}*\n\n**${b.hook}**\n\n**Tactical question:** ${b.question}\n\n**Scale:** ${b.scale}\n\n**Appearance:** ${b.silhouette}\n\n**Place in the world:** ${b.lore}\n\n**Arena:** ${b.arena}\n\n**Movement:** ${b.movement}\n\n**Who takes which hit:** ${b.assignment}\n\n### Attack set\n\n| Attack | Warning | Resolution | Player response |\n| --- | --- | --- | --- |\n${b.moves.map(m=>'| '+m.join(' | ')+' |').join('\n')}\n\n### Phases\n\n${b.phases.map((p,i)=>`${i+1}. ${p}`).join('\n')}\n\n### Opening sequence\n\n${b.opening.map(s=>'- '+s).join('\n')}\n\n**Typical failure:** ${b.failure}\n\n**Recovery:** ${b.recovery}\n\n**Signature spectacle:** ${b.spectacle}\n\n**Prototype requirements:** ${b.production}\n\n### Image prompt\n\nNano Banana Pro · Unlimited ON · 2K · 16:9 · one image\n\n\`\`\`text\n${imagePrompt(b)}\n\`\`\`\n`;
}
for (const b of newBossConcepts) markdown += `\n## ${b.name}\n\n*${b.kind}; new visual concept, encounter rules pending.*\n\n**${b.hook}**\n\n${b.silhouette}\n\n**Scale:** ${b.scale}\n\n**Arena:** ${b.arena}\n\n**Reference:** ${b.referenceNote||(b.references.length?'Approved colossus take 3; change only the eyes to glowing aqua.':'Written brief only.')}\n\n### Image prompt\n\n\`\`\`text\n${imagePrompt(b)}\n\`\`\`\n`;
await writeFile(path.join(root, 'projects/meridius/docs/boss-concepts.md'), markdown);
// The self-contained report copy links to its sibling direction document.
await writeFile(path.join(out, 'concepts.md'), markdown.replace('(boss-encounter-direction.md)', '(direction.md)'));

const variantHTML = v => `<section class="variant" id="${v.id}"><p class="eyebrow">Alternate visual form / Arachne hybrid</p><h3>${esc(v.name)}</h3><p class="hook">${esc(v.hook)}</p>${artwork(v.id)}<p>${esc(v.silhouette)}</p><p><strong>Anatomy:</strong> ${esc(v.construction)}</p><p class="meta">${esc(v.scale)}</p><p><strong>Proposed identity:</strong> ${esc(v.lore)}</p><p><strong>Attack presentation:</strong> ${esc(v.performance)}</p><details class="prompt"><summary>Arachne image prompt · 16:9 / 2K</summary><p>One additional visual version; the original spider concept is preserved.</p><p><a href="bosses/prompts/boss_${v.id}.txt" download>Download Arachne prompt</a></p><button type="button" class="copy">Copy full prompt</button><span class="copy-status" role="status"></span><pre>${esc(imagePrompt(v))}</pre></details></section>`;
const details = ordered.map((b,i)=>`<article class="boss" id="${b.id}">
  <p class="eyebrow">${String(i+1).padStart(2,'0')} / ${esc(b.kind)}</p>
  <h2>${esc(b.name)}</h2><p class="hook">${esc(b.hook)}</p>
  ${artwork(b.id)}
  <div class="decision"><strong>The decision</strong><p>${esc(b.question)}</p></div>
  <p>${esc(b.silhouette)}</p><p class="meta">${esc(b.scale)}</p>
  <div class="columns"><div><h3>Place in the world</h3><p>${esc(b.lore)}</p><h3>The arena</h3><p>${esc(b.arena)}</p></div><div><h3>Movement</h3><p>${esc(b.movement)}</p><h3>Who takes which hit</h3><p>${esc(b.assignment)}</p></div></div>
  <details class="moves" ${i===0?'open':''}><summary>Attack set · ${b.moves.length} moves</summary><div class="table-wrap"><table><thead><tr><th>Attack</th><th>Warning</th><th>Resolution</th><th>Your response</th></tr></thead><tbody>${b.moves.map(m=>'<tr>'+m.map((c,j)=>`<${j?'td':'th'}>${esc(c)}</${j?'td':'th'}>`).join('')+'</tr>').join('')}</tbody></table></div></details>
  <details><summary>Phases and opening sequence</summary><div class="columns"><div><h3>Escalation</h3><ol>${b.phases.map(p=>`<li>${esc(p)}</li>`).join('')}</ol></div><div><h3>First four beats</h3><ol>${b.opening.map(p=>`<li>${esc(p.replace(/^Beat \d: /,''))}</li>`).join('')}</ol></div></div></details>
  <details><summary>Failure, recovery and the signature moment</summary><p><strong>Failure:</strong> ${esc(b.failure)}</p><p><strong>Recovery:</strong> ${esc(b.recovery)}</p><p><strong>The moment:</strong> ${esc(b.spectacle)}</p><p class="meta"><strong>Prototype needs:</strong> ${esc(b.production)}</p></details>
  <details class="prompt"><summary>Complete image prompt · 16:9 / 2K</summary><p>Prepared for Higgsfield. See the current production status above for submission progress.</p><p><a href="bosses/prompts/boss_${b.id}.txt" download>Download prompt</a></p><button type="button" class="copy">Copy full prompt</button><span class="copy-status" role="status"></span><pre>${esc(imagePrompt(b))}</pre></details>
${activeVariants.filter(v=>v.parentId===b.id).map(variantHTML).join('')}
</article>`).join('\n');

const newDetails = newBossConcepts.map(b=>`<article class="boss new-concept" id="${b.id}"><p class="eyebrow">NEW VISUAL CONCEPT / ${esc(b.kind)}</p><h2>${esc(b.name)}</h2><p class="hook">${esc(b.hook)}</p>${artwork(b.id)||'<p>Generation is pending.</p>'}<p>${esc(b.silhouette)}</p><p class="meta">${esc(b.scale)}</p><p><strong>Arena:</strong> ${esc(b.arena)}</p><p class="meta">Character direction only; encounter rules and modeling references come after visual selection.</p><details class="prompt"><summary>Generation prompt · 16:9 / 2K</summary><p>${esc(b.referenceNote||(b.references.length?'The aqua-eye edit uses approved take 3. The exact submitted prompt is kept beside each version.':'Original design from a written brief.'))}</p><p><a href="bosses/prompts/boss_${b.id}.txt" download>Download prompt</a></p><button type="button" class="copy">Copy full prompt</button><span class="copy-status" role="status"></span><pre>${esc(imagePrompt(b))}</pre></details></article>`).join('\n');

const html = `<!doctype html>
<html lang="en" data-mak-report="document"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Meridius — Current boss concepts</title><link rel="stylesheet" href="../_shared/report.css"><script defer src="../_shared/report.js"></script><link rel="stylesheet" href="bosses/report.css"><script defer src="bosses/report.js"></script></head>
<body><main class="container">
<header><p class="eyebrow">MERIDIUS / BOSS CONCEPTS / 24 OCTOBER 2026</p><h1>Giants against<br>a small company.</h1><p class="lead">Six boss designs, including an ancient stone troll carrying the ruined homes built on his sleeping shoulders and the black-and-dark-red colossus with glowing aqua eyes. The roster follows your marked selection.</p><p class="meta">Six active designs · four encounter drafts · two new visual concepts</p></header>
<aside class="status"><strong>${esc(production.headline)}</strong><p>${esc(production.summary)}</p><p>Nano Banana Pro / 2K / 16:9 / one image / Unlimited ON. The latest Troll revision uses the supplied central standing troll directly and the approved shoulder crop. Other game characters were checked for style consistency. It preserves the back ruins while requesting stone surfaces and no ears. The colossus eye edit uses its previous take.</p><p class="meta">${selection.retained.length} retained designs · ${production.downloadedImages} preserved original images across current and archived designs · ${production.agentReviewedImages} agent-reviewed · updated ${esc(production.updated)}</p><p><a href="bosses/concepts.md">Current design document</a> · <a href="bosses/direction.md">Combat principles</a> · <a href="bosses/generation-handoff.md">Generation handoff</a> · <a href="bosses/production.json" download>Production status</a> · <a href="bosses/prompts.json" download>Current prompts</a> · <a href="bosses/selection.json" download>Selection record</a> · <a href="bosses/catalog.mjs" download>Editable source</a></p></aside>
<section class="overview"><h2>The current roster</h2><div class="index-grid">${activeSubjects.map(b=>`<a class="index-card" href="#${b.id}"><span>${esc(b.kind)}</span><strong>${esc(b.name)}</strong><p>${esc(b.question||b.hook)}</p></a>`).join('')}</div></section>
${gallery}
<p class="meta">Originals: <code>projects/meridius/references/characters/bosses/concepts/</code> (full-size PNGs, local only; the report shows WebP copies from <code>bosses/originals/</code>). Tripo exports and Blender working files have separate folders alongside it. <a href="bosses/delivery-manifest.json">Downloaded image manifest</a> · <a href="bosses/asset-folders.md">Folder guide</a> · <a href="bosses/tripo-recovered-exports.json">19 recovered character model exports</a>.</p>
<section class="erosion"><p class="eyebrow">THE SANGUINE DELVER / A SPATIAL DAMAGE PUZZLE</p><h2>Your damage changes the battlefield</h2><p>Compare opening a wound in the central route with baiting the crawler onto expendable soil first. Advance the stages to see why the same successful attack can produce a very different position.</p>
<div class="controls"><label>Wound location <select id="scenario"><option value="edge">Bait to the outer terrace</option><option value="centre">Burst on the central route</option></select></label><fieldset><legend>Erosion stage</legend><button type="button" data-stage="0" aria-pressed="true">1 · Stain</button><button type="button" data-stage="1" aria-pressed="false">2 · Bloom</button><button type="button" data-stage="2" aria-pressed="false">3 · Undercut</button><button type="button" data-stage="3" aria-pressed="false">Cauterise instead</button></fieldset></div>
<div class="diagram-layout"><div id="erosion-board" role="img" aria-label="Explanatory top-down erosion diagram"></div><div><p id="stage-note" aria-live="polite"></p><ul class="legend"><li><b>S</b> Stable stone outer route</li><li><b>B</b> Boss footprint</li><li><b>1–6</b> Company squads</li><li><b>× / ≋ / ▾</b> Stain / bloom / undercut</li><li><b>+</b> Cauterised stable earth</li><li><b>F</b> Quarry brazier</li></ul><p class="meta">Illustrative schematic; not a playable map or a navigation simulation. Erosion stages each allow a full company turn. Squad markers show scale and formation, not a solved turn sequence.</p></div></div>
</section>
<section class="principles"><h2>Make the hard hit a decision</h2><div class="columns"><div><h3>Read, assign, move</h3><p>Warnings distinguish <strong>evacuate, intercept, share, bait and shelter</strong>. Every major move has a stated resolution turn. Boss movement, forced movement and the next escape route remain visible.</p><p>A shared hit uses separate squad stations. Defend still protects against eligible ordered attacks; it does not secretly absorb ground AoEs.</p></div><div><h3>Losses carry weight</h3><p>Soldiers who fall stay down. Major impacts can cause casualties even when handled well, but recovery beats and reserve rotations keep the fight from becoming an unavoidable drain on the roster.</p><p>One enemy and one health pool throughout. Body parts, roots, vents and conduits create tactical choices without spawning an army.</p></div></div></section>
${details}
${newDetails}
<section class="references"><h2>Ancient troll references</h2><p>Your woodland troll reference guides his species and age. The marked shoulder areas guide ruin placement. The terrain cottage supplies the timber, cream plaster and stone materials. Take 3 reduces the houses to broken remnants and removes the tall back trees. Take 4 rebuilds the standing posture and human-relative scale. Take 5 removes the ears but retains too much of the earlier face and smooth body. Take 6 improves stone material but produces an unwanted comparison sheet. Take 7 requests one faithful standing reference-species troll with no visible ears and the approved shoulder ruins.</p><div class="reference-grid"><figure><a href="bosses/references/ancient-troll-user-reference.png"><img loading="lazy" src="bosses/references/ancient-troll-user-reference.png" alt="User troll anatomy, long hooked nose, old face, long hair and beard, moss, roots and trinkets."></a><figcaption>User troll anatomy, long hooked nose, old face, long hair and beard, moss, roots and trinkets. <a href="bosses/references/ancient-troll-user-reference.png" download>Download</a></figcaption></figure><figure><a href="bosses/references/shoulder-ruins-user-markup.png"><img loading="lazy" src="bosses/references/shoulder-ruins-user-markup.png" alt="Placement of ruins across both shoulders and upper back only. Red circles are annotations; no crown, giant fortress or buried pose."></a><figcaption>Placement of ruins across both shoulders and upper back only. Red circles are annotations; no crown, giant fortress or buried pose. <a href="bosses/references/shoulder-ruins-user-markup.png" download>Download</a></figcaption></figure><figure><a href="terrain/originals/house_ruined_cottage__take-01.webp"><img loading="lazy" src="terrain/originals/house_ruined_cottage__take-01.webp" alt="Meridius terrain architecture and painted materials: small timber-and-thatch cottages, pale plaster, stone footings and chimney, broken rafters. Ignore magenta."></a><figcaption>Meridius terrain architecture and painted materials: small timber-and-thatch cottages, pale plaster, stone footings and chimney, broken rafters. Ignore magenta. <a href="terrain/originals/house_ruined_cottage__take-01.webp" download>Download</a></figcaption></figure></div><p><a href="bosses/ancient-troll-references.json" download>Reference roles and sources</a></p></section>
<section class="references"><h2>Stone troll: approved ruins and game style</h2><p>The shoulder crop is the feature you asked to preserve: abandoned homes built on a sleeping giant. The Footman sheet anchors painted shading, controlled contours and the blue-and-cream human palette. The supplied troll sheet above remains the authority for his species.</p><div class="reference-grid"><figure><a href="bosses/references/approved-troll-shoulder-ruins.png"><img loading="lazy" src="bosses/references/approved-troll-shoulder-ruins.png" alt="User-approved ruined walls and snapped timber across the troll back and shoulders."></a><figcaption>Approved shoulder and back ruins.</figcaption></figure><figure><a href="bosses/references/meridius-footmen-style.webp"><img loading="lazy" src="bosses/references/meridius-footmen-style.webp" alt="Meridius Footmen: controlled contours, painted material planes and blue-and-cream colours."></a><figcaption>Existing game character rendering reference.</figcaption></figure></div><p><a href="bosses/stone-troll-style-review.json" download>Character style review and reference roles</a></p></section>
<section class="references"><h2>Colossus construction reference</h2><p>Your supplied image controls the standing proportions, stone armour, fur and slab sword. The pale first take translated that construction into this scene. Take 2 changes the materials to black and charcoal with dark-red details. Take 3 corrects the mask and is the user-approved base. Take 4 changes only its two eyes to glowing aqua.</p><div class="reference-grid"><figure><a href="bosses/references/colossus-user-reference.png"><img loading="lazy" src="bosses/references/colossus-user-reference.png" alt="User-supplied standing stone-and-fur colossus with a slab sword"></a><figcaption>Supplied reference. <a href="bosses/references/colossus-user-reference.png" download>Download</a></figcaption></figure></div></section>
<footer><h2>Scope and next production step</h2><p>Review the Giant Troll and Pale Colossus before preparing clean modeling references. The retained encounter drafts remain proposals; these bosses have not been implemented or balanced. Anatomy and squad-staging findings appear beside each take.</p><p>Removed designs are outside this active report. Their original files and submitted prompts are preserved in the boss library.</p><p id="verification-note">${verificationHtml}</p></footer>
</main></body></html>`;
await writeFile(path.join(reportDir,'bosses.html'), html);
await copyFile(new URL('report.css',import.meta.url),path.join(out,'report.css'));
await copyFile(new URL('report.js',import.meta.url),path.join(out,'report.js'));
try { await copyFile(path.join(runtime,'verification.json'),path.join(out,'report-checks.json')); }
catch (error) { if(error.code!=='ENOENT')throw error; }

const writeOnce = async (filename, value) => { try { await access(filename); } catch (e) { if(e.code!=='ENOENT') throw e; await writeFile(filename, JSON.stringify(value,null,2)+'\n'); } };
await writeOnce(path.join(runtime,'queue.json'), {version:1,status:'prepared_waiting_for_terrain_release',provider:'Higgsfield website',browser:'Brave',model:'Nano Banana Pro',quality:'2K',aspect:'16:9',unlimitedRequired:true,automaticWorkerInstalled:false,order:prompts.map(p=>p.id),items:prompts.map(p=>({id:p.id,status:'prepared',take:1,promptFile:`workspace/2026-10-20_meridius/bosses/prompts/${p.id}.txt`,references:p.references,destination:`${canonical}/${p.file}`}))});
await writeOnce(path.join(runtime,'jobs.json'), []);
// Add authorised visual variants without resetting existing jobs, takes or statuses.
const queuePath = path.join(runtime,'queue.json');
const queue = JSON.parse((await readFile(queuePath,'utf8')).replace(/^\uFEFF/, ''));
let queueChanged = false;
for (const p of prompts) if (!queue.items.some(item=>item.id===p.id)) {
  queue.items.push({id:p.id,status:'prepared',take:1,promptFile:`workspace/2026-10-20_meridius/bosses/prompts/${p.id}.txt`,references:p.references,destination:`${canonical}/${p.file}`});
  const priorId = prompts[prompts.indexOf(p)-1]?.id;
  const insertAt = queue.order.indexOf(priorId);
  queue.order.splice(insertAt < 0 ? queue.order.length : insertAt+1,0,p.id);
  queueChanged = true;
}
if (queueChanged) { queue.updated = new Date().toISOString(); await writeFile(queuePath,JSON.stringify(queue,null,2)+'\n'); }
// Explicit destinations override remembered browser download folders.
for (const item of queue.items) {
  item.destination = `${canonical}/${item.id}__take-${String(item.take).padStart(2,'0')}.png`;
  if (!item.jobId && ['prepared','no_job_observed'].includes(item.status)) {
    const brief = prompts.find(p=>p.id===item.id);
    item.references = brief?.references || item.references || [];
    item.inputMode = brief?.inputMode || item.inputMode || 'text-only';
    item.promptFile = `${canonical}/briefs/${item.id}.txt`;
  } else if (delivered.some(image=>image.subject===item.id&&image.take===item.take)) {
    item.promptFile = `${canonical}/prompts/${item.id}__take-${String(item.take).padStart(2,'0')}.txt`;
  }
}
queue.outputRoot = canonical;
queue.activeIds = selection.active.map(id=>'boss_'+id);
queue.updated = new Date().toISOString();
await writeFile(queuePath,JSON.stringify(queue,null,2)+'\n');
console.log(JSON.stringify({activeBosses:activeSubjects.length,completePrompts:prompts.length,report:'workspace/2026-10-20_meridius/bosses.html',productionState:production.state,confirmedJobs:production.confirmedJobs}));
