// The relief of a last stand, frame by frame: the company is played by the AI
// to the last turn, then the dawn, the Margrave's riders and the horde's flight
// are captured as they play.
// Usage: node scripts/reliefshots.mjs <outDir> [seed] [turns]
//   turns: end the stand early (e.g. 1) for a quick check; default the real length.
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const [out = 'reliefshots', seedArg = '7', turnsArg = ''] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const base = process.env.BASE_URL ?? 'http://localhost:5199';
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto(`${base}/?newgame&seed=3`);
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });
await page.evaluate(([seed, turns]) => {
  const m = window.__meridius;
  m.store.debug.testBattle('last_stand', { seed });
  if (turns) m.store.battleScene.b.objective.turns = turns;
  m.engine.timeScale = 3;
}, [Number(seedArg), Number(turnsArg) || 0]);
await page.waitForTimeout(1500);
await page.evaluate(() => window.__meridius.store.battleScene.begin());
const idle = () => page.waitForFunction(() => !window.__meridius.store.battleScene || !window.__meridius.store.battleScene.busy, null, { timeout: 240000 });
await idle();
for (;;) {
  const st = await page.evaluate(() => {
    const sc = window.__meridius.store.battleScene;
    return sc ? { turn: sc.b.turn, turns: sc.b.objective.turns, phase: sc.b.phase } : null;
  });
  if (!st || st.phase === 'over') {
    console.log('battle ended before the relief', JSON.stringify(st));
    break;
  }
  await page.evaluate(() => window.__meridius.store.debug.playerTurn());
  await idle();
  const last = st.turn >= st.turns;
  if (last) await page.evaluate(() => (window.__meridius.engine.timeScale = 1));
  await page.evaluate(() => window.__meridius.store.battleScene.endTurn());
  if (!last) {
    await idle();
    continue;
  }
  // The last enemy turn: wait for the riders, then film them.
  await page.waitForFunction(() => !window.__meridius.store.battleScene || window.__meridius.store.battleScene.relief, null, { timeout: 120000 });
  const t0 = Date.now();
  const info = await page.evaluate(() => {
    const sc = window.__meridius.store.battleScene;
    return sc ? { riders: sc.relief?.riders.length, edge: sc.relief?.edge } : null;
  });
  for (const at of [0.2, 0.8, 1.4, 2.0, 2.6, 3.2, 4.0, 5.0, 6.0]) {
    const wait = t0 + at * 1000 - Date.now();
    if (wait > 0) await page.waitForTimeout(wait);
    // The battle closes into the report once the victory has played.
    const alive = await page.evaluate(() => !!window.__meridius.store.battleScene).catch(() => false);
    if (!alive) break;
    await page.screenshot({ path: path.join(out, `relief-${at.toFixed(1)}.png`) }).catch((e) => errors.push(`screenshot ${at}: ${e.message}`));
  }
  await page.waitForTimeout(2500);
  await page.screenshot({ path: path.join(out, 'after.png') }).catch(() => {});
  const screen = await page.evaluate(() => window.__meridius.store.screen).catch(() => '?');
  console.log(JSON.stringify({ ...info, screenAfter: screen }));
  break;
}
console.log(errors.length ? errors.join('\n') : 'no page errors');
await browser.close();
