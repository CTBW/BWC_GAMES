// Downloads only URLs observed in the website. No generation or account access.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {imageSubjects} from './catalog.mjs';
import {workspaceOriginals} from '../terrain-prompt-pack/webp.mjs';
const root=fileURLToPath(new URL('../../../../',import.meta.url));
const jobPath=path.join(root,'.cache/boss-art/jobs.json');
const jobs=JSON.parse((await readFile(jobPath,'utf8')).replace(/^\uFEFF/,''));
const out=path.join(root,'workspace/2026-10-20_meridius/bosses');
const concepts=path.join(root,'projects/meridius/references/characters/bosses/concepts');
// Full-size report previews stay local; build.mjs writes the WebP copies the report links.
const previews=path.join(workspaceOriginals,'2026-10-20_meridius/bosses/originals');
const allowed=new Set(imageSubjects.map(b=>'boss_'+b.id));
await mkdir(previews,{recursive:true});
await mkdir(path.join(out,'submissions'),{recursive:true});
await mkdir(concepts,{recursive:true});
await mkdir(path.join(concepts,'prompts'),{recursive:true});
const manifest=[];
for(const job of jobs.filter(j=>j.originalUrl)){
  const url=new URL(job.originalUrl);
  if(url.protocol!=='https:'||url.hostname!=='d8j0ntlcm91z4.cloudfront.net'||url.username||url.password||!/^\/user_[A-Za-z0-9]+\/hf_\d{8}_\d{6}_[a-f0-9-]+\.png$/.test(url.pathname))throw Error('Unexpected original-image source.');
  if(!allowed.has(job.subject)||!Number.isInteger(job.take)||job.take<1||job.take>99)throw Error('Invalid subject/take.');
  const stem=`${job.subject}__take-${String(job.take).padStart(2,'0')}`;
  const destination=path.join(concepts,stem+'.png');
  let bytes;
  try{bytes=await readFile(destination);}catch(e){
    if(e.code!=='ENOENT')throw e;
    const response=await fetch(url,{signal:AbortSignal.timeout(55000),redirect:'error'});
    if(!response.ok)throw Error(`Download failed: ${response.status}`);
    bytes=Buffer.from(await response.arrayBuffer());
  }
  if(bytes.length<24||bytes.subarray(0,8).toString('hex')!=='89504e470d0a1a0a')throw Error('Not a PNG original.');
  const width=bytes.readUInt32BE(16),height=bytes.readUInt32BE(20);
  if(Math.min(width,height)<1024||Math.max(width,height)<1900)throw Error('Original is smaller than 2K.');
  const sha256=createHash('sha256').update(bytes).digest('hex');
  if(job.sha256&&job.sha256!==sha256)throw Error('Existing original differs from recorded hash.');
  try{await writeFile(destination,bytes,{flag:'wx'});}catch(e){if(e.code!=='EEXIST')throw e;}
  // The report keeps a byte-identical local preview; the character library owns the original.
  const preview=path.join(previews,stem+'.png');
  try{await writeFile(preview,bytes,{flag:'wx'});}catch(e){
    if(e.code!=='EEXIST')throw e;
    if(createHash('sha256').update(await readFile(preview)).digest('hex')!==sha256)throw Error('Report preview differs from original.');
  }
  const submittedPrompt=path.join(out,'submissions',stem+'.txt');
  if(job.prompt)await writeFile(submittedPrompt,job.prompt+'\n');
  if(job.prompt)await writeFile(path.join(concepts,'prompts',stem+'.txt'),job.prompt+'\n');
  Object.assign(job,{destination:path.relative(root,destination).replaceAll('\\','/'),downloaded:true,bytes:bytes.length,width,height,sha256});
  manifest.push({subject:job.subject,take:job.take,file:'originals/'+stem+'.png',canonicalFile:job.destination,prompt:'submissions/'+stem+'.txt',inputMode:job.inputMode,bytes:bytes.length,width,height,sha256});
  console.log(JSON.stringify({subject:job.subject,take:job.take,bytes:bytes.length,width,height,sha256}));
}
await writeFile(jobPath,JSON.stringify(jobs,null,2)+'\n');
await writeFile(path.join(out,'delivery-manifest.json'),JSON.stringify({updated:new Date().toISOString(),images:manifest},null,2)+'\n');
await writeFile(path.join(concepts,'manifest.json'),JSON.stringify({updated:new Date().toISOString(),images:manifest.map(i=>({...i,file:path.basename(i.file),prompt:'prompts/'+path.basename(i.prompt)}))},null,2)+'\n');
