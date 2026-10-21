// Save/continue check: start, march, reload, continue; plus a small-window capture.
import { chromium } from 'playwright-core';
import { tmpdir } from 'node:os';

const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const ctx = await browser.newContext({ viewport: { width: 1366, height: 768 } });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto('http://localhost:5199/?newgame&seed=31');
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base');
await page.evaluate(() => { const s = window.__meridius.store; s.game.flags = { welcome: true }; s.commit(); s.debug.autoPrepare(3); });
await page.waitForTimeout(800);
const before = await page.evaluate(() => {
  const s = window.__meridius.store;
  const ex = s.game.expedition;
  const nx = ex.edges.filter((e) => e[0] === ex.current).map((e) => e[1]);
  s.clickNode(nx[0]);
  return { cycle: s.game.cycle, current: nx[0], army: ex.army.length };
});
await page.waitForTimeout(2500);
await page.screenshot({ path: process.argv[2] ?? `${tmpdir()}/small-campaign.png` });
// Reload without the newgame flag and continue.
await page.goto('http://localhost:5199/');
await page.waitForFunction(() => window.__meridius?.store?.screen === 'title');
await page.getByRole('button', { name: 'Continue' }).click();
await page.waitForTimeout(1200);
const after = await page.evaluate(() => {
  const s = window.__meridius.store;
  return { screen: s.screen, cycle: s.game.cycle, current: s.game.expedition?.current, pending: s.game.expedition?.pending?.kind ?? null, army: s.game.expedition?.army.length };
});
console.log('before', JSON.stringify(before));
console.log('after ', JSON.stringify(after));
await page.screenshot({ path: process.argv[3] ?? `${tmpdir()}/small-continue.png` });
console.log('errors', errors.length, errors.slice(0, 3).join(' | '));
await browser.close();
