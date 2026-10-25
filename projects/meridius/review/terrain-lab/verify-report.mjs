import { createServer } from 'node:http';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { chromium } from '../../source/game/node_modules/playwright-core/index.mjs';
import { reportThemeCSS } from '../../../../desktop/service/report-theme.mjs';

const root=fileURLToPath(new URL('../../../../',import.meta.url));
const out=path.join(root,'.cache/woodland-report');
await mkdir(out,{recursive:true});
const types={'.html':'text/html','.css':'text/css','.js':'text/javascript','.png':'image/png','.webp':'image/webp','.mp4':'video/mp4','.json':'application/json','.md':'text/plain','.mjs':'text/javascript'};
const server=createServer(async(req,res)=>{
  try {
    const filename=path.resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));
    assert(['workspace','projects/meridius'].some(dir=>filename.startsWith(path.join(root,dir)+path.sep)));
    const data=await readFile(filename);
    const range=req.headers.range?.match(/^bytes=(\d+)-(\d*)$/);
    if(range){
      const start=Number(range[1]),end=range[2]?Math.min(Number(range[2]),data.length-1):data.length-1;
      res.writeHead(206,{'Content-Type':types[path.extname(filename)]||'text/plain','Content-Range':`bytes ${start}-${end}/${data.length}`,'Accept-Ranges':'bytes','Content-Length':end-start+1});
      return res.end(data.subarray(start,end+1));
    }
    res.writeHead(200,{'Content-Type':types[path.extname(filename)]||'text/plain'}).end(data);
  }catch{res.writeHead(404).end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const base=`http://127.0.0.1:${server.address().port}`;
const browser=await chromium.launch({channel:'msedge',headless:true});
const page=await browser.newPage({acceptDownloads:true});
const errors=[];
page.on('pageerror',e=>errors.push(String(e)));
try {
  for(const width of [1600,1000]){
    await page.setViewportSize({width,height:1000});
    await page.goto(base+'/workspace/2026-10-20_meridius/terrain-lab.html');
    await page.addStyleTag({content:reportThemeCSS});
    const links=await page.locator('a[href]').evaluateAll(nodes=>nodes.map(n=>n.href));
    for(const href of links.filter(h=>h.startsWith(base))) assert.equal((await page.request.get(href)).status(),200,href);
    for(const img of await page.locator('figure img').all()) await img.scrollIntoViewIfNeeded();
    await page.waitForFunction(()=>[...document.querySelectorAll('figure img')].every(i=>i.complete&&i.naturalWidth>0));
    for(const theme of ['light','dark']){
      await page.evaluate(t=>document.documentElement.dataset.mrmakTheme=t,theme);
      assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
      await page.evaluate(()=>scrollTo(0,0));
      await page.screenshot({path:path.join(out,`${width}-${theme}.png`)});
      for(let i=0;i<4;i++){
        await page.locator('figure img').nth(i).click();
        const dialog=page.getByRole('dialog',{name:'Image preview'});
        await dialog.waitFor({state:'visible'});
        const download=page.waitForEvent('download');
        await dialog.getByRole('link',{name:'Download',exact:true}).click();
        assert((await download).suggestedFilename().endsWith('.webp'));
        await dialog.getByRole('button',{name:'Close',exact:true}).click();
        await dialog.waitFor({state:'hidden'});
      }
    }
    const video=page.locator('video');
    await video.scrollIntoViewIfNeeded();
    await video.evaluate(async v=>{v.muted=true;await v.play();});
    await page.waitForFunction(()=>document.querySelector('video').currentTime>.3);
    assert(await video.evaluate(v=>v.videoWidth===1920&&v.videoHeight===1080&&Math.abs(v.duration-9.1)<.05));
    await video.evaluate(v=>{v.pause();v.currentTime=4;});
    await page.waitForFunction(()=>{const v=document.querySelector('video');return !v.seeking&&v.readyState>=2;});
    await video.screenshot({path:path.join(out,`video-${width}.png`)});
  }
  assert.deepEqual(errors,[]);
  const registry=JSON.parse(await readFile(path.join(root,'workspace/workspace.json'),'utf8'));
  assert.equal(registry.entities.find(c=>c.id==='meridius').steps.filter(s=>s.path==='terrain-lab.html').length,1);
  const result={status:'passed',desktopWidths:[1600,1000],themes:['light','dark'],images:await page.locator('figure img').count(),newImagePreviewsAndDownloads:4,allLocalLinks:true,video:{duration:9.1,width:1920,height:1080,playback:true,seek:true},horizontalOverflow:false,pageErrors:errors};
  await writeFile(path.join(root,'workspace/2026-10-20_meridius/terrain-lab/woodland-report-review.json'),JSON.stringify(result,null,2)+'\n');
  console.log(JSON.stringify(result));
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
