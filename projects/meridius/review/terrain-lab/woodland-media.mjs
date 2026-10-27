import { mkdir, readFile, writeFile, copyFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { webpCopies, workspaceOriginals } from '../terrain-prompt-pack/webp.mjs';

const root = fileURLToPath(new URL('../../../../', import.meta.url));
const folder = path.join(root, 'workspace/2026-10-20_meridius/terrain-lab');
const game = path.join(root, 'projects/meridius/source/godot');
const bin = process.env.MERIDIUS_FFMPEG_BIN || path.join(process.env.LOCALAPPDATA ?? '', 'Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-9.0.2-full_build/bin');
const ffmpeg = (...args) => execFileSync(path.join(bin, 'ffmpeg.exe'), ['-hide_banner', '-loglevel', 'error', '-y', ...args], {stdio:'inherit'});
const baseline = path.join(folder, 'baseline');
await mkdir(baseline, {recursive:true});
try { await copyFile(path.join(folder, 'woodland-scouting.mp4'), path.join(baseline, 'source.mp4'), 1); }
catch (error) { if (error.code !== 'EEXIST') throw error; }
// PNG frames stay in local/workspace-originals/; the card keeps WebP copies.
const localBaseline = path.join(workspaceOriginals, '2026-10-20_meridius/terrain-lab/baseline');
await mkdir(localBaseline, {recursive:true});
for (const second of [0,2,5,8]) ffmpeg('-ss',String(second),'-i',path.join(baseline,'source.mp4'),'-frames:v','1',path.join(localBaseline,`at-${second}s.png`));
webpCopies([0,2,5,8].map(second => [path.join(localBaseline,`at-${second}s.png`), path.join(baseline,`at-${second}s.webp`)]));
if (process.argv.includes('--encode')) {
  const captures = path.join(game, 'tests/visual/out/fog_of_war');
  const review = JSON.parse(await readFile(path.join(captures, 'result.json'), 'utf8'));
  if (review.errors.length) throw new Error('Native capture has failed checks.');
  ffmpeg('-framerate',String(review.fps),'-i',path.join(captures,'frames/%04d.png'),'-frames:v',String(review.frames),'-c:v','libx264','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',path.join(folder,'woodland-scouting.mp4'));
  const metadata = JSON.parse(execFileSync(path.join(bin,'ffprobe.exe'),['-v','error','-select_streams','v:0','-show_entries','stream=width,height,r_frame_rate,nb_frames:format=duration','-of','json',path.join(folder,'woodland-scouting.mp4')],{encoding:'utf8'}));
  if (Number(metadata.streams[0].nb_frames)!==review.frames) throw new Error('Wrong encoded frame count.');
  await writeFile(path.join(folder,'woodland-video.json'),JSON.stringify(metadata,null,2)+'\n');
}
const files = [];
for (const filename of ['tree_pine__take-01.png','tree_beech__take-01.png','tree_oak__take-02.png','bush_green__take-01.png','undergrowth_ferns__take-01.png']) {
  const original = await readFile(path.join(workspaceOriginals,'2026-10-20_meridius/terrain/originals',filename));
  const asset = await readFile(path.join(game,'assets/terrain/woodland',filename));
  if (!asset.equals(original)) throw new Error('Source copy differs: '+filename);
  files.push({file:filename,source:'local/workspace-originals/2026-10-20_meridius/terrain/originals/'+filename,bytes:asset.length,width:asset.readUInt32BE(16),height:asset.readUInt32BE(20),sha256:createHash('sha256').update(asset).digest('hex')});
}
await writeFile(path.join(game,'assets/terrain/woodland/sources.json'),JSON.stringify({version:1,route:'Unmodified source PNGs, keyed by the marked-foliage branch of battle_sorted.gdshader; root anchors and sizes in woodland_kit.gd',files},null,2)+'\n');
console.log('WOODLAND_MEDIA_OK: five exact source copies; baseline samples'+(process.argv.includes('--encode')?'; encoded and verified current native clip.':'.'));
