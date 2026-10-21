// Remembered settings: node scripts/prefscheck.mjs
// Turns on 2× battle speed and mutes sound through the real buttons, reloads,
// and checks both come back while the base scene keeps normal speed.
import { chromium } from 'playwright-core';

const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
const battle = async () => {
  await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });
  await page.evaluate(() => {
    const s = window.__meridius.store;
    s.game.flags = { welcome: true };
    s.debug.testBattle('goblin_scouts', { seed: 3 });
  });
  await page.waitForTimeout(500);
};
await page.goto('http://localhost:5199/?newgame&seed=5');
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });
await page.evaluate(() => {
  const s = window.__meridius.store;
  s.game.flags = { welcome: true };
  s.commit();
});
await page.locator('button[title="Sound on"]').click();
await battle();
await page.getByRole('button', { name: '1×' }).click();
const before = await page.evaluate(() => ({ speed: window.__meridius.store.battleScene.speed, prefs: localStorage.getItem('meridius.prefs.v1') }));
await page.goto('http://localhost:5199/?newgame&seed=5');
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });
const base = await page.evaluate(() => ({ speed: window.__meridius.engine.scene.speed ?? 1, muted: !!document.querySelector('button[title="Sound off"]') }));
await battle();
const after = await page.evaluate(() => ({ speed: window.__meridius.store.battleScene.speed, label: [...document.querySelectorAll('button')].some((b) => b.textContent === '2×') }));
console.log('before reload', JSON.stringify(before));
console.log('base after reload', JSON.stringify(base));
console.log('battle after reload', JSON.stringify(after));
const ok = before.speed === 2 && base.speed === 1 && base.muted && after.speed === 2 && after.label;
console.log(ok ? 'PASS' : 'FAIL', 'errors', errors.length, errors.slice(0, 3).join(' | '));
await browser.close();
process.exit(ok ? 0 : 1);
