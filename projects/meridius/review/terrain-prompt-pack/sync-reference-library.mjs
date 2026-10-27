import {readFile,writeFile,mkdir,readdir,copyFile} from 'node:fs/promises';
import {constants} from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../../../../',import.meta.url));
const report='workspace/2026-10-20_meridius/terrain';
// PNG originals stay local; the card in the report folder links their WebP copies.
const originals='local/workspace-originals/2026-10-20_meridius/terrain/originals';
const referenceRoot='projects/meridius/references';
const pack=JSON.parse(await readFile(path.join(root,report,'prompts.json'),'utf8'));
const review=JSON.parse(await readFile(path.join(root,report,'review.json'),'utf8'));
const items=new Map(pack.items.map(item=>[item.id,item]));
const selected=new Map(review.images.map(item=>[item.id,item]));
const woodlandTrial=new Set(['tree_pine__take-01.png','tree_beech__take-01.png','tree_oak__take-02.png','bush_green__take-01.png','undergrowth_ferns__take-01.png']);
const media=[];
let copied=0;
const hash=buffer=>createHash('sha256').update(buffer).digest('hex');
const markdownText=value=>String(value).replaceAll('|','\\|').replaceAll('\n',' ');

async function preserveCopy(source,destination,metadata){
  const sourcePath=path.resolve(root,source);
  const destinationPath=path.resolve(root,destination);
  const allowedRoot=path.resolve(root,referenceRoot)+path.sep;
  if(!destinationPath.startsWith(allowedRoot))throw new Error('Destination outside project references');
  const original=await readFile(sourcePath);
  if(original.subarray(1,4).toString()!=='PNG')throw new Error(`Expected original PNG: ${source}`);
  const sha256=hash(original);
  await mkdir(path.dirname(destinationPath),{recursive:true});
  try{await copyFile(sourcePath,destinationPath,constants.COPYFILE_EXCL);copied++;}
  catch(error){if(error.code!=='EEXIST')throw error;}
  if(hash(await readFile(destinationPath))!==sha256)throw new Error(`Existing reference differs; preserved without overwrite: ${destination}`);
  media.push({...metadata,source,destination,bytes:original.length,width:original.readUInt32BE(16),height:original.readUInt32BE(20),sha256});
}

const filenames=(await readdir(path.join(root,originals))).filter(name=>name.endsWith('.png')).sort();
for(const filename of filenames){
  const match=filename.match(/^([a-z0-9_]+)__take-(\d+)\.png$/);
  if(!match)throw new Error(`Unexpected original filename: ${filename}`);
  const [,id,takeText]=match;
  const item=items.get(id);
  if(!item)throw new Error(`Unknown terrain subject: ${id}`);
  const baseId=item.baseId??id;
  const base=items.get(baseId);
  const collection=base.kind==='scene'||['orc_pit','orc_pit_fortified','dragon_lair','dragon_lair_snow'].includes(baseId)?'backgrounds':'style';
  const selectedReview=selected.get(id);
  const isSelected=selectedReview?.file===`originals/${filename}`;
  await preserveCopy(`${originals}/${filename}`,`${referenceRoot}/${collection}/terrain/${baseId}/${filename}`,{
    id,title:item.title,baseId,collection,phase:item.baseId?'night':'day',take:Number(takeText),selected:isSelected,
    reviewStatus:isSelected?selectedReview.status:'Earlier or unreviewed take; retained for comparison',
    ...(isSelected?{reviewNote:selectedReview.note}:{})
  });
}
for(const [filename,title] of [['style-lush.png','Primary style reference — lush forest and meadow'],['style-golden.png','Primary style reference — golden grass and slopes']]){
  await preserveCopy(`${report}/references/${filename}`,`${referenceRoot}/style/terrain/primary/${filename}`,{
    id:filename.slice(0,-4),title,baseId:'primary',collection:'style',phase:'style',selected:true,reviewStatus:'User-supplied primary style reference'
  });
}

for(const baseId of [...new Set(media.map(image=>image.baseId))]){
  const images=media.filter(image=>image.baseId===baseId);
  const title=baseId==='primary'?'Primary terrain style guides':items.get(baseId).title;
  const lines=[`# ${title}`,'','Original PNG copies. Selected means the take used in the terrain review gallery; read its limitations before using it as an asset.',''];
  for(const image of images){
    const filename=path.posix.basename(image.destination);
    lines.push(`- [${filename}](${filename}) — ${image.selected?'**Selected**':'Retained take'}; ${image.reviewStatus}.`);
    if(image.selected&&image.reviewNote)lines.push(`  ${image.reviewNote}`);
  }
  const used=images.filter(image=>woodlandTrial.has(path.posix.basename(image.destination)));
  lines.push('','Magenta is an extraction background, not transparency. '+(used.length?'The '+used.map(image=>path.posix.basename(image.destination)).join(', ')+' source is used unchanged in the Godot terrain-lab painted woodland trial, through a keyed material. See assets/terrain/woodland/sources.json in the Godot project.':'These concept sources are not integrated into Godot.'),'');
  await writeFile(path.join(root,path.posix.dirname(images[0].destination),'README.md'),lines.join('\n'));
}

for(const collection of ['backgrounds','style']){
  const images=media.filter(image=>image.collection===collection);
  const baseIds=[...new Set(images.map(image=>image.baseId))];
  const lines=[`# ${collection==='backgrounds'?'Battlefield and terrain scene':'Terrain object and style'} references`,'',`${images.length} original PNG files, including ${images.filter(image=>image.selected).length} selected images. Day and night versions share a subject folder. All earlier takes are retained alongside the selected take. No source images were moved or overwritten.`,'','| Subject | Selected images | All takes |','| --- | --- | --- |'];
  for(const baseId of baseIds){
    const members=images.filter(image=>image.baseId===baseId);
    const title=baseId==='primary'?'Primary style guides':items.get(baseId).title;
    const links=members.filter(image=>image.selected).map(image=>`[${image.phase}](${baseId}/${path.posix.basename(image.destination)})`).join(' · ')||'Awaiting review';
    lines.push(`| ${markdownText(title)} | ${links} | [${members.length} PNGs](${baseId}/README.md) |`);
  }
  lines.push('','The review gallery remains at `workspace/2026-10-20_meridius/terrain-prompts.html`. Six isolated concepts have documented isolation or water-edge issues. All images require normal asset preparation before engine use.','');
  await writeFile(path.join(root,referenceRoot,collection,'terrain/README.md'),lines.join('\n'));
}

const manifest={version:1,updated:new Date().toISOString(),generatedOriginals:filenames.length,primaryStyleReferences:2,reviewedSubjects:review.images.length,files:media.length,collections:{backgrounds:media.filter(image=>image.collection==='backgrounds').length,style:media.filter(image=>image.collection==='style').length},media};
await writeFile(path.join(root,referenceRoot,'terrain-library.json'),JSON.stringify(manifest,null,2)+'\n');
await writeFile(path.join(root,report,'reference-library.json'),JSON.stringify(manifest,null,2)+'\n');
await writeFile(path.join(root,referenceRoot,'terrain-library.md'),`# Terrain reference library\n\n${manifest.generatedOriginals} generated originals and the two supplied style guides are copied into the project reference folders. ${manifest.reviewedSubjects} subjects have a selected reviewed take. Every copied PNG is byte-for-byte verified against its downloaded original.\n\n- [Battlefields, roads, camps, corrupted lands and sites](backgrounds/terrain/README.md)\n- [Trees, rocks, terrain objects, buildings, town modules and primary style guides](style/terrain/README.md)\n- [Complete file manifest with SHA-256 hashes](terrain-library.json)\n\nEach subject folder keeps day and night versions together, plus earlier takes. Its README identifies the selected images and preserves their review notes. The original review gallery and original downloads remain unchanged. Six isolated concepts still need the documented cleanup; this collection is reference material, not an engine-ready asset pack.\n\nThe full-size PNGs are local only and not in Git; WebP copies of the generated originals are in \`workspace/2026-10-20_meridius/terrain/originals/\`.\n`);
console.log(JSON.stringify({copied,verified:media.length,generatedOriginals:filenames.length,reviewedSubjects:review.images.length,...manifest.collections,index:`${referenceRoot}/terrain-library.md`}));
const libraryFile=path.join(root,referenceRoot,'terrain-library.md');
await writeFile(libraryFile,(await readFile(libraryFile,'utf8'))+'\n## Engine trial — 24 October 2026\n\nFive originals now supply pine, beech, oak, shrubs and ferns in Terrain Test Fields: Northern forest ford and Woodland scouting. Their magenta backgrounds are keyed in the material; the source PNGs remain unchanged. This is an initial art trial, not conversion of the entire reference library.\n\n- [Source hashes and dimensions](../source/godot/assets/terrain/woodland/sources.json)\n- [Integration notes](../source/godot/assets/terrain/woodland/README.md)\n- [Terrain test field documentation](../docs/terrain-test-fields.md)\n');
