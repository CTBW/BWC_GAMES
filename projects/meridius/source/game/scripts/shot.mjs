// One-off capture of a screen state: node scripts/shot.mjs <out.png> <screen> [seed] [w] [h]
// screen: base | title | prep | campaign | roster
import { chromium } from 'playwright-core';

const [out = 'shot.png', screen = 'base', seedArg = '1234', wArg = '1920', hArg = '1080'] = process.argv.slice(2);
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: Number(wArg), height: Number(hArg) } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto(`http://localhost:5199/?newgame&seed=${seedArg}`);
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });
await page.evaluate(() => {
  const s = window.__meridius.store;
  s.game.flags = { welcome: true };
  s.commit();
});
await page.evaluate((scr) => {
  const s = window.__meridius.store;
  if (scr === 'title') s.goTitle();
  if (scr === 'prep') s.goPrep();
  if (scr === 'roster') s.openPanel('roster');
  if (scr === 'campaign') s.debug.autoPrepare(1);
}, screen);
await page.waitForTimeout(1800);
await page.screenshot({ path: out });
console.log('saved', out, 'errors', errors.length, errors.slice(0, 3).join(' | '));
await browser.close();
