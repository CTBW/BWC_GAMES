import { mkdir, copyFile, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { webpCopies, workspaceOriginals } from '../terrain-prompt-pack/webp.mjs';

const root = fileURLToPath(new URL('../../../../', import.meta.url));
const folder = path.join(root, 'workspace/2026-10-20_meridius');
const output = path.join(folder, 'terrain-lab');
const captures = path.join(root, 'projects/meridius/source/godot/tests/visual/out/terrain_lab');
const shots = [
  ['field_1_day', 'Mixed northern woodland in warm light', 'First woodland pass: existing pines, broadleaf trees, bushes, stumps and fallen wood. Soft grass accents and mist are in the engine.'],
  ['field_1_night', 'The same forest ford in moonlight', 'The same layout in readable, cool moonlight. The clear crossing and patrols remain visible through the haze.'],
  ['field_0_day', 'Rolling meadow with a winding track', 'Open hills and forest pockets test material blending and movement over a broad crest.'],
  ['field_2_day', 'Two opposing ridges above a worn valley', 'Long slopes and a valley test changes in elevation. This is an abstract test layout, not a reconstruction of Waterloo.'],
  ['ridge_heights', 'Height contours on the ridge test field', 'Heights mode exposes the continuous landforms. Tactical rules still use integer tile heights.'],
  ['ford_grid', 'Tactical grid following the forest ford terrain', 'The grid and picking use the surface height. Deep water blocks movement; the shallow ford connects the two banks.'],
  ['meadow_close', 'Patrols standing on the grassy slope', 'Individual feet and shadows follow the slope beneath each formation slot.'],
  ['meadow_march', 'Patrol moving uphill in the real battle renderer', 'A native frame during movement, using the existing path rules and animation playback.'],
  ['meadow_classic', 'Classic tile-height renderer for comparison', 'Switch between the textured continuous surface and the existing plateau presentation.'],
];
// Captures go to local/workspace-originals/ as PNG; the card links WebP copies.
const originals = path.join(root, 'local/workspace-originals/2026-10-20_meridius/terrain-lab');
await mkdir(output, { recursive: true });
await mkdir(originals, { recursive: true });
for (const [id] of shots) await copyFile(path.join(captures, `${id}.png`), path.join(originals, `${id}.png`));
await copyFile(path.join(captures, 'result.json'), path.join(output, 'review.json'));
await copyFile(fileURLToPath(import.meta.url), path.join(output, 'build.mjs'));
const review = JSON.parse(await readFile(path.join(output, 'review.json'), 'utf8'));
if (review.errors.length) throw new Error('Native terrain review has failures; inspect review.json before publishing.');
const figures = shots.map(([id, alt, caption]) => `<figure><img src="terrain-lab/${id}.webp" alt="${alt}" width="1920" height="1080" loading="lazy"><figcaption>${caption} <a href="terrain-lab/${id}.webp" download>Download</a></figcaption></figure>`).join('\n');

const fogCaptures = path.join(root, 'projects/meridius/source/godot/tests/visual/out/fog_of_war');
const fogShots = [
 ['scouting_start', 'Unexplored ground uses the supplied black and blue grain; the sentry is concealed.'],
 ['scouting_revealed', 'Approaching the woodland reveals the sentry and fades the canopies over visible squads.'],
 ['scouting_explored', 'After withdrawal, the sentry disappears and explored ground remains dimly visible.'],
 ['scouting_night', 'The same visibility and woodland effect under moonlight.'],
 ['battle_night_hud', 'Native battle HUD and minimap with a visible enemy at night.'],
 ['battle_hidden_hud', 'The distant enemy disappears from the battlefield, HUD count and minimap.'],
];
const fogReview = JSON.parse(await readFile(path.join(fogCaptures, 'result.json'), 'utf8'));
if (fogReview.errors.length) throw new Error('Fog review has failed checks.');
for (const [id] of fogShots) await copyFile(path.join(fogCaptures, id + '.png'), path.join(originals, id + '.png'));
await copyFile(path.join(fogCaptures, 'result.json'), path.join(output, 'fog-review.json'));
const fogFigures = fogShots.map(([id, caption]) => '<figure><img src="terrain-lab/' + id + '.webp" alt="' + caption + '" width="1920" height="1080" loading="lazy"><figcaption>' + caption + ' <a href="terrain-lab/' + id + '.webp" download>Download</a></figcaption></figure>').join('\n');
const woodlandShots = [
 ['woodland_original_close', 'Previous foliage: the same field, patrol positions and 1.45x camera.'],
 ['woodland_painted_close', 'Painted pine, beech and oak, with shrubs and ferns at the forest edge. Canopies still fade over visible squads.'],
 ['woodland_painted_overview', 'The mixed woodland at 0.57x overview. River, ford and movement ground keep their existing layout.'],
 ['woodland_painted_night', 'The same woodland in the terrain lab moonlight setting.'],
];
for (const [id] of woodlandShots) await copyFile(path.join(fogCaptures,id+'.png'),path.join(originals,id+'.png'));
webpCopies([...shots,...fogShots,...woodlandShots].map(([id])=>[path.join(originals,id+'.png'),path.join(output,id+'.webp')]));
const woodlandFigures = woodlandShots.map(([id,caption])=>`<figure><img src="terrain-lab/${id}.webp" alt="${caption}" width="1920" height="1080" loading="lazy"><figcaption>${caption} <a href="terrain-lab/${id}.webp" download>Download</a></figcaption></figure>`).join('\n');
const woodlandValidation = JSON.parse(await readFile(path.join(output,'woodland-validation.json'),'utf8'));

const refs = [
 ['road_forest_wide', 'Golden hills and a naturally worn road'],
 ['road_forest_wide_night', 'Cool moonlight with readable terrain'],
 ['road_forest_northern_fog', 'Layered northern woodland and low mist'],
 ['road_forest_northern_clear', 'Mixed canopy, undergrowth and warm light'],
].map(([id, label]) => `<figure><img src="terrain/originals/${id}__take-01.webp" alt="Reference: ${label}" loading="lazy"><figcaption>${label}. User-selected art target, separate from the engine captures.</figcaption></figure>`).join('\n');
await writeFile(path.join(folder, 'terrain-lab.html'), `<!doctype html>
<html lang="en" data-mak-report="document"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Meridius — Terrain test fields</title><link rel="stylesheet" href="../_shared/report.css"><link rel="stylesheet" href="../_shared/examples.css"><script defer src="../_shared/report.js"></script>
<style>.evidence{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}.evidence figure{margin:0;padding:12px;border:1px solid var(--mak-border);border-radius:8px}.evidence img{width:100%;display:block;border-radius:5px}figcaption,.meta{font-size:13px;color:var(--mak-muted)}figcaption{padding-top:10px}.notice{padding:18px;border:1px solid var(--mak-border);border-radius:8px;background:var(--mak-surface)}.table-wrap{overflow-x:auto}</style></head>
<body><main class="container"><p class="meta">MERIDIUS / NATIVE GODOT TERRAIN STUDY / 24 OCTOBER 2026</p>
<h1>Terrain tests and woodland scouting</h1>
<p>Open <strong>Terrain Test Fields</strong> on the title screen. Walk patrols across a rolling meadow, a northern forest ford and opposing ridges. Compare slopes, textures, elevation and grounding before investing in finished battlefield layouts.</p>
<p class="notice">The first painted woodland kit is now in <strong>Woodland scouting</strong> and <strong>Northern forest ford</strong>: five existing paintings provide pine, beech, oak, shrubs and ferns. Use <strong>Painted woodland</strong> to compare with the previous foliage. This is an engine art trial; the wider forest art direction still needs more variation and ground work.</p>
<h2>Painted woodland comparison</h2>
<p>The comparison uses the same terrain, units and camera. Tree size and root anchors follow the paintings; the existing depth order, ground shadows and canopy fading handle their overlap with troops. Small ferns are visual decoration and do not add movement or sight blockers. The exterior forest also switches with the toggle. Mist and tree sway advance slightly between the stills.</p>
<div class="evidence">${woodlandFigures}</div>
<p>The five source PNGs are unchanged, with their hashes verified. A foliage material hides their magenta background and removes color spill, while matching opacity masks preserve holes between branches for canopy fading. Filtered mip levels reduce fine-leaf shimmer. Existing rocks, stumps and logs remain; a distinct birch and painted fallen timber still need a later pass. <a href="../../projects/meridius/source/godot/assets/terrain/woodland/sources.json">Source manifest</a>.</p>
<p><strong>${fogReview.checks.length} native checks passed, with no recorded in-scene errors.</strong> The art toggle leaves the map and unit state unchanged. Final quick regression: ${woodlandValidation.passed} passed, ${woodlandValidation.failed} failed, ${woodlandValidation.skipped} skipped. ${woodlandValidation.failureSummary} <a href="terrain-lab/woodland-validation.json">Verification record</a>. Campaign playthroughs remain deferred.</p>
<h2>Fog of war and traversable woodland</h2>
<p>Choose <strong>Woodland scouting</strong> in the field selector. Fog starts enabled there; the other three art studies can toggle it on. The test sentry holds position while you move the patrol north through the trees and back south.</p>
<p>Unexplored terrain uses the supplied black-and-blue texture, sampled in overlapping rotated patches to break up repetition. Explored ground stays dim. Sight is shared by each army; woodland conceals occupants beyond two tiles, and hills and dense foliage block sight. Tree canopies fade smoothly around visible squads. Hidden squads do not cause transparent holes in the forest.</p>
<video controls preload="metadata" poster="terrain-lab/scouting_revealed.webp" style="width:100%;border-radius:8px"><source src="terrain-lab/woodland-scouting.mp4" type="video/mp4"></video>
<p class="meta">Native gameplay excerpts at normal simulation speed: approach, canopy fade and withdrawal. 91 sampled frames at 10 fps, 1920 &times; 1080. <a href="terrain-lab/woodland-scouting.mp4" download>Download MP4</a>.</p>
<div class="evidence">${fogFigures}</div>
<p>The native checks include actual woodland routes, concealment, enemy hover suppression, HUD counts, hidden combat-log suppression and the art toggle on classic terrain. <a href="terrain-lab/fog-review.json">Native check record</a>. Earlier native runs in this pass reported eight leaked objects and two resources in use during shutdown. The final run did not print those warnings; their underlying cleanup is not claimed as repaired. Campaign playthrough testing is deferred at the user's request.</p>
<h2>Earlier terrain and atmosphere studies — 23 October</h2><p>These captures preserve the previous terrain iteration and its original foliage.</p><div class="evidence">${figures}</div>
<h2>Controls</h2><div class="table-wrap"><table><thead><tr><th>Control</th><th>Use</th></tr></thead><tbody>
<tr><td>Field selector</td><td>Switch among three terrain studies and Woodland scouting.</td></tr>
<tr><td>Textured slopes / Classic tile heights</td><td>Compare continuous terrain with the current plateau renderer.</td></tr>
<tr><td>Click a patrol, then highlighted ground</td><td>Use the game's movement rules. Patrol movement refills after arrival.</td></tr>
<tr><td>Wheel / right or middle drag</td><td>Zoom and pan. Whole field and Inspect patrol restore useful framing.</td></tr>
<tr><td>Grid / Heights / Night / Fog of war</td><td>Inspect tactical cells, continuous elevation and moonlight.</td></tr>
<tr><td>Painted woodland</td><td>Compare the new foliage in Northern forest ford or Woodland scouting without resetting the patrols.</td></tr>
<tr><td>Reset patrols / Escape</td><td>Reset this field or return to the title.</td></tr></tbody></table></div>
<p>Direct launch from the Godot folder: <code>tools/godot.sh --path . -- --terrain-lab</code>. The lab has its own battle state and does not create or change a company save.</p>
<h2>Visual direction, added gradually</h2><p>The selected paintings govern the warm golden light, cool forest shade, soft atmospheric depth, natural road edges and mixed vegetation. Future passes should add more distinct tree species, ferns, shrubs, roots and mossy rocks, with a new in-engine comparison after each useful increment.</p>
<div class="evidence">${refs}</div>
<h2>How to reach the painted look</h2>
<p>The ground uses the existing continuous height surface. Five isolated paintings now supply the two woodland fields, while the other test fields keep the older foliage. The next art increment should improve ground texture scale and forest-edge composition, add a distinct birch and painted fallen timber, and reduce visible repetition of the tree silhouettes.</p>
<div class="table-wrap"><table><thead><tr><th>Part</th><th>Recommended route</th></tr></thead><tbody>
<tr><td>Trees, bushes, ferns, rocks and logs</td><td>Use clean transparent painted cutouts, with consistent scale, root anchors, depth sorting and ground shadows. Start with the isolated concepts already saved.</td></tr>
<tr><td>Grass, dirt and roads</td><td>Blend painted surface textures and irregular road-edge masks across the terrain. Add smaller grass and verge cutouts for depth.</td></tr>
<tr><td>Hills and banks</td><td>Keep real height data and a matching rendered surface so troops follow the ground. A pasted hill painting alone cannot establish elevation.</td></tr>
<tr><td>Golden forest atmosphere</td><td>Combine varied canopy layers, warm highlights, cool shade, soft ground transitions and restrained mist. Judge the result at the gameplay camera.</td></tr>
</tbody></table></div>
<p>Cutting objects from a full landscape can work when their complete shape is visible. Overlaps, baked lighting and fog make those extractions harder. We already have isolated oak, beech, pine, bush and fern concepts, so there is enough material to try this without new generation. Additional Higgsfield images should fill specific proven gaps. Tripo meshes are optional if the game later needs rotating views or full 3D.</p>
<div class="evidence"><figure><img src="terrain/originals/tree_oak__take-02.webp" alt="Original painted oak source with its preserved magenta background" loading="lazy"><figcaption>Original oak source. Its backdrop is hidden by the material in the woodland trial. <a href="terrain/originals/tree_oak__take-02.webp" download>Download</a>.</figcaption></figure><figure><img src="terrain/originals/undergrowth_ferns__take-01.webp" alt="Original painted fern source with its preserved magenta background" loading="lazy"><figcaption>Original fern source, now placed as low undergrowth in the woodland trial. <a href="terrain/originals/undergrowth_ferns__take-01.webp" download>Download</a>.</figcaption></figure></div>
<p>Godot supports <a href="https://docs.godotengine.org/en/stable/tutorials/2d/2d_meshes.html">2D image meshes</a> and <a href="https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html">2D lights and shadows</a>. The route above is a recommendation for this game's fixed camera; exact visual fidelity remains to be demonstrated in the next art pass.</p>
<h2>Layout inspiration</h2><p>Open ground, forest pockets and visible hills draw on <a href="https://www.ageofempires.com/learn-to-play/defending-your-empires-aoe2/">Age of Empires II</a>. Clear routes, woodland boundaries and river crossings draw on <a href="https://classic.battle.net/war3/maps/">Warcraft III and The Frozen Throne maps</a>. Broad deployment slopes draw on <a href="https://academy.totalwar.com/battle-deployment-and-battle-terrain/">Total War's terrain guidance</a>. The ridge study also takes inspiration from the ridge and reverse-slope positions described by the <a href="https://www.nam.ac.uk/explore/battle-waterloo">National Army Museum's Waterloo account</a>. These are design interpretations, not copied maps or imported combat mechanics.</p>
<h2>Verification and limits</h2><p>The native GL Compatibility review completed <strong>${review.checks.length} checks with ${review.errors.length} recorded runtime errors</strong>, including height/picking round trips, connected routes, actual pointer movement, menu entry, night/height toggles, field switching and unchanged save bytes. <a href="terrain-lab/review.json">Read the native review record</a>.</p>
<p>Before the fog pass, the quick headless suite recorded <strong>375 passed, 1 failed, 10 skipped</strong>. All terrain cases passed. The existing failure is <code>test_audio::test_a_marching_squad_is_one_tread</code>, triggered by the shared unit-outline shader compiler in the headless renderer; it was already recorded in the unit-playground review. The native terrain renderer does not report that error.</p>
<p>The continuous surface is opt-in for these test fields. Normal battles and the campaign retain their current ground presentation. Elevation still uses integer tactical levels for rules; the smooth surface supplies visual height. Steep cliffs, overhangs, terrain hiding soldiers behind crests, final collision authoring and final biome assets are outside this first study.</p>
<p class="meta">Editable report source: <a href="terrain-lab/build.mjs" download>build.mjs</a>. Engine source: <code>scripts/rules/terrain_test_fields.gd</code>, <code>scripts/render/relief_terrain.gd</code>, <code>scripts/render/terrain_lab.gd</code>, <code>scripts/ui/screens/terrain_lab.gd</code>. Captures: <code>tests/visual/terrain_lab_shots.gd</code>. All engine paths are inside <code>projects/meridius/source/godot</code>.</p>
</main></body></html>\n`);
console.log(`Terrain report: ${shots.length} native captures; ${review.checks.length} checks.`);
