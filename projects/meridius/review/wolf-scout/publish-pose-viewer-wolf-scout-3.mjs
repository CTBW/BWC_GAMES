// Puts Wolf Scout 3's four clips in the shared pose viewer, first on the Wolf scout tab, in
// place of Wolf Scout 2's, and brings the tab's text up to date: she is now the sandbox's
// only Wolf Scout, on the Amberfeld side.
//   node projects/meridius/review/wolf-scout/publish-pose-viewer-wolf-scout-3.mjs   (from the repository root)
// Render the frames first with art/wolf_scout_3d/tools/render_viewer_wolf_scout_3.py into
// wolf-scout-3/viewer-frames/; they are packed here at the sneak sheets' scale (0.8). Without
// the frames, the page is rebuilt from the sheets already published. Safe to run again.
import fs from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
const root=process.cwd(),hub=path.join(root,'workspace/2026-10-20_meridius');
const frames=path.join(root,'projects/meridius/review/wolf-scout/wolf-scout-3/viewer-frames'),dest=path.join(hub,'wolf-scout/wolf-scout-3/pose-viewer');
if(existsSync(path.join(frames,'render_info.json')))execFileSync('python',[path.join(root,'projects/meridius/source/godot/art/crossbowman_3d/tools/build_sheets.py'),frames,dest,'0.8'],{stdio:'inherit'});
const meta=JSON.parse(await fs.readFile(path.join(dest,'frames.json'),'utf8'));
const clips=[['idle','Idle'],['sneak','Sneak walk'],['attack','Attack'],['death','Death']];
for(const [id] of clips)if(!meta.clips[id])throw Error('No sheets for '+id);
const config={base:'wolf-scout/wolf-scout-3/pose-viewer/',start:'idle',key:'wolf-scout-3-pose-viewer',character:'Wolf Scout',clips,sameScale:true};
const template=await fs.readFile(path.join(hub,'spearman-3d.html'),'utf8');
const markup=template.slice(template.indexOf('<div class="viewer">'),template.indexOf('\n<div class="steps">'));
const n=id=>meta.clips[id].se.frames;
const section=`<!-- WOLF_POSE_VIEWER --><section id="pose-viewer"><h2>Pose viewer</h2><p>Wolf Scout 3's four clips: her crouched idle, sneak walk, twin-dagger attack and death. Step through each one frame by frame in four facings. Scroll up on the picture to zoom in, up to 4×.</p>${markup}<p>Native Blender frames of <code>projects/meridius/source/godot/art/wolf_scout_3d/wolf_scout_3.blend</code> (kept in the repository, not on this page), at the scale of the earlier scouts' sheets: idle ${n('idle')} frames, sneak ${n('sneak')}, attack ${n('attack')} and death ${n('death')}. The looping idle and sneak leave out their last frame, which repeats the first. The attack's two strikes land at 0.80 s and 0.83 s, frames 25 and 26. Death is shown in place: the camera follows her hips over the ground. It keeps the other clips' scale, so where her fall is wider than the column, scroll sideways or hold Shift and scroll.</p></section><!-- END_WOLF_POSE_VIEWER -->`;
let html=await fs.readFile(path.join(hub,'wolf-scout.html'),'utf8');
html=html.replace(/<!-- WOLF_POSE_VIEWER -->[\s\S]*?<!-- END_WOLF_POSE_VIEWER -->/,'').replace(/<div class="viewer">[\s\S]*?<div class="stage" id="stage"><\/div>\n<\/div>\n?/,'');
html=html.replace('</header>','</header>'+section);
html=html.replace(/<p><strong>Current stage:<\/strong>[\s\S]*?<\/p>/,'<p><strong>Current stage:</strong> Wolf Scout 3 is the only Wolf Scout in the 3D unit sandbox, a squad of three on the Amberfeld side, on the south flank of the player line. She rests in a crouch with both daggers held point back, her hooded cape draped over her back and shoulders, her ears through its hood. All four clips are in the pose viewer at the top. Wolf Scout 2 and the original Scout below are earlier versions, no longer in the sandbox.</p>');
html=html.replace('<h2>Wolf Scout 2 · imported into the 3D sandbox</h2><p>Select <strong>Wolf Scout 2</strong> in the sandbox roster. She starts beside the original Wolf Scout and has four clips: idle, sneak, twin-dagger attack and death. All four are in the pose viewer at the top.</p>','<h2>Wolf Scout 2 · earlier version</h2><p>Wolf Scout 3 has replaced her and the original Wolf Scout in the sandbox, and in the pose viewer at the top. She had four clips: idle, sneak, twin-dagger attack and death. Her files are kept below.</p>');
html=html.replace('Step through it as “Sneak walk” in the pose viewer at the top. ','');
html=html.replace(/(<script id="frames-data" type="application\/json">)[\s\S]*?(<\/script>)/,(_,a,b)=>a+JSON.stringify(meta)+b);
html=html.replace(/(<script id="viewer-config" type="application\/json">)[\s\S]*?(<\/script>)/,(_,a,b)=>a+JSON.stringify(config)+b);
if((html.match(/<div class="viewer">/g)||[]).length!==1)throw Error('Expected one pose viewer on the page');
if(/Wolf Scout 2 is imported|All four are in the pose viewer|in the pose viewer at the top\. <a/.test(html))throw Error('Stale Wolf Scout 2 text left on the page');
await fs.writeFile(path.join(hub,'wolf-scout.html'),html);
const ws2='All four clips are in the pose viewer at the top of the Wolf scout tab. Its frames are rendered from this Blender source by art/wolf_scout_3d/tools/render_viewer_wolf_scout_2.py and published by projects/meridius/review/wolf-scout/publish-pose-viewer-wolf-scout-2.mjs.';
const ws2now='Wolf Scout 3 has replaced Wolf Scout 2 in the sandbox and in the pose viewer at the top of the Wolf scout tab. Wolf Scout 2\'s frames can be rendered again from this Blender source by art/wolf_scout_3d/tools/render_viewer_wolf_scout_2.py and published by projects/meridius/review/wolf-scout/publish-pose-viewer-wolf-scout-2.mjs, which puts her back in the viewer.';
const intro='Wolf Scout 2 is a separate 3D unit in the Meridius 3D unit sandbox, beside the original Wolf Scout. Open the sandbox and select **Wolf Scout 2** in the roster. Her original counterpart remains available.';
const introNow='Wolf Scout 2 was a separate 3D unit in the Meridius 3D unit sandbox, beside the original Wolf Scout. Both have been replaced there by Wolf Scout 3; her files are kept here as an earlier version.';
for(const file of [path.join(hub,'wolf-scout/wolf-scout-2/notes.md'),path.join(root,'projects/meridius/review/wolf-scout/wolf-scout-2/integration-notes.md')])
  if(existsSync(file))await fs.writeFile(file,(await fs.readFile(file,'utf8')).replace(ws2,ws2now).replace(intro,introNow));
console.log('Wolf Scout 3 pose viewer published:',clips.map(([id])=>`${id} ${n(id)}`).join(', '));
