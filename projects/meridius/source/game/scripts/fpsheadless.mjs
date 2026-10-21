// Real frame rate in the headless browser (requestAnimationFrame), idle scenes.
// Usage: node scripts/fpsheadless.mjs
import { chromium } from 'playwright-core';
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true, args: ['--disable-gpu-vsync', '--disable-frame-rate-limit'] });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto('http://localhost:5199/?newgame&seed=5');
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base');
const fps = async (label, setup) => {
  await page.evaluate(setup);
  await page.waitForTimeout(2500);
  const f = await page.evaluate(() => new Promise((r) => {
    let n = 0;
    const t0 = performance.now();
    const tick = () => { n++; if (performance.now() - t0 < 3000) requestAnimationFrame(tick); else r(n / ((performance.now() - t0) / 1000)); };
    requestAnimationFrame(tick);
  }));
  console.log(label.padEnd(26), f.toFixed(1), 'fps');
};
await fps('base', () => {});
await fps('small battle', () => window.__meridius.store.debug.testBattle('goblin_scouts', { seed: 5, mapId: 'forest_clearing' }));
await fps('last stand (night)', () => window.__meridius.store.debug.testBattle('last_stand', { seed: 5, mapId: 'steading' }));
await fps('refugee stand (day)', () => window.__meridius.store.debug.testBattle('refugee_stand', { seed: 5, mapId: 'ford' }));
await browser.close();
