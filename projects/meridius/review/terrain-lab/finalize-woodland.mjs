import { readFile, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root=fileURLToPath(new URL('../../../../',import.meta.url));
let log=await readFile(path.join(root,'.cache/woodland-kit-final-quick.log'));
const text=log[0]===255&&log[1]===254?log.toString('utf16le'):log.toString('utf8');
const match=text.match(/==== (\d+) passed, (\d+) failed, (\d+) skipped in ([\d.]+) s ====/);
if(!match)throw new Error('The final quick suite has not completed; do not report partial counts.');
const failures=[...text.matchAll(/^  FAILED (.*)$/gm)].map(m=>m[1].trim());
const passed=Number(match[1]),failed=Number(match[2]),skipped=Number(match[3]);
const native=JSON.parse(await readFile(path.join(root,'projects/meridius/source/godot/tests/visual/out/fog_of_war/result.json'),'utf8'));
if(native.errors.length)throw new Error('Native review has failed checks.');
const failureSummary=failed===1&&text.includes('actions.custom_samplers')?
  'The remaining failure is the previously recorded headless unit-outline shader compiler error.':
  failed?`Unresolved quick-suite failures: ${failures.join('; ')}.`:'All quick-suite checks passed.';
const validation={date:new Date().toISOString(),sourceRevision:execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim(),dirtyTree:true,command:'tools/test.sh --quick',passed,failed,skipped,seconds:Number(match[4]),failures,failureSummary,native:{checks:native.checks.length,inSceneErrors:native.errors.length,renderer:native.renderer,shutdownWarnings:{leakedObjects:8,resourcesInUse:2}},firstQuickAttempt:{completed:false,reason:'Battle-view _say() parse errors outside the woodland edit, cascading failures and a later engine crash. The current file contains _say(); the final rerun above is authoritative.'},campaignPlaythroughs:'deferred',generationJobs:0,sourceAssets:5,baselineVideoSamplesSeconds:[0,2,5,8],limits:['Repeated tree silhouettes remain visible.','Birch and painted fallen timber are not yet supplied.','The PNGs retain magenta backgrounds and rely on the keyed material.','Ground artwork and large-map performance need further work.']};
validation.native.shutdownWarningsContext='Observed in earlier runs of this pass. The final 23-check run printed no shutdown warnings; cleanup is not claimed as repaired.';
validation.focusedAfterClassicCacheFix={command:'tools/test.sh --quick fog_of_war terrain_lab',passed:6,failed:1,skipped:0,failure:'The same headless unit-outline compiler error, on the first view-instantiating test. Native equivalents passed.'};
await writeFile(path.join(root,'workspace/2026-10-20_meridius/terrain-lab/woodland-validation.json'),JSON.stringify(validation,null,2)+'\n');
const registryPath=path.join(root,'workspace/workspace.json');
const registry=JSON.parse(await readFile(registryPath,'utf8'));
registry.entities.find(card=>card.id==='meridius').updated=new Date().toISOString().slice(0,10);
await writeFile(registryPath,JSON.stringify(registry,null,2)+'\n');
console.log(JSON.stringify({passed,failed,skipped,nativeChecks:native.checks.length}));
