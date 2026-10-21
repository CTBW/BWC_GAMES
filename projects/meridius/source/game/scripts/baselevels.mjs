// Captures the base with every building at levels 1, 2 and 3:
// node scripts/baselevels.mjs <outDir> [w] [h] [chronicleEntries]
// chronicleEntries fills the Company Chronicle to check it against the camp on small screens.
import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';

const [outDir = 'shots/baselevels', wArg = '1920', hArg = '1080', chronArg = '0'] = process.argv.slice(2);
mkdirSync(outDir, { recursive: true });
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: Number(wArg), height: Number(hArg) } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto('http://localhost:5199/?newgame&seed=1234');
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });
for (const level of [1, 2, 3]) {
  await page.evaluate(([lv, n]) => {
    const s = window.__meridius.store;
    s.game.flags = { welcome: true };
    for (const id of Object.keys(s.game.buildings)) s.game.buildings[id] = lv;
    for (let i = s.game.chronicle.length; i < n; i++)
      s.game.chronicle.unshift({ cycle: i, text: 'The company returns from the Hillsvain Raids with two wounded and a cart of salvaged iron.', tone: i % 3 ? 'good' : 'bad' });
    s.commit();
  }, [level, Number(chronArg)]);
  await page.waitForTimeout(1800);
  const out = `${outDir}/base_l${level}_${wArg}x${hArg}${Number(chronArg) ? `_c${chronArg}` : ''}.png`;
  await page.screenshot({ path: out });
  console.log('saved', out);
}
console.log('errors', errors.length, errors.slice(0, 3).join(' | '));
await browser.close();
