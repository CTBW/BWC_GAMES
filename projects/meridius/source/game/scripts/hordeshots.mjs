// Horde battle captures from the running game: deployment, then each turn
// with the company played by the AI, captured at the start of every player
// turn and during the enemy turn. Records enemy-turn playback time.
// Usage: node scripts/hordeshots.mjs <outDir> <encounter> [mapId] [seed] [turns] [timeScale]
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const [out = 'hordeshots', enc = 'last_stand', mapId = '', seedArg = '7', turnsArg = '6', tsArg = '2'] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const base = process.env.BASE_URL ?? 'http://localhost:5199';
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const W = Number(process.env.W ?? 1920);
const H = Number(process.env.H ?? 1080);
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: W, height: H } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto(`${base}/?newgame&seed=3`);
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });
await page.evaluate(([enc, mapId, seed, ts]) => {
  const m = window.__meridius;
  m.store.debug.testBattle(enc, { seed, mapId: mapId || undefined });
  m.engine.timeScale = ts;
}, [enc, mapId, Number(seedArg), Number(tsArg)]);
await page.waitForTimeout(1500);
await page.screenshot({ path: path.join(out, '00-deploy.png') });
const idle = () => page.waitForFunction(() => !window.__meridius.store.battleScene || !window.__meridius.store.battleScene.busy, null, { timeout: 180000 });
const live = () => page.evaluate(() => !!window.__meridius.store.battleScene);
await page.evaluate(() => window.__meridius.store.battleScene.begin());
await idle();
await page.waitForTimeout(400);
await page.screenshot({ path: path.join(out, '01-turn1.png') });
const timings = [];
for (let t = 1; t <= Number(turnsArg); t++) {
  if (!(await live())) break;
  const over = await page.evaluate(() => window.__meridius.store.battleScene.b.phase === 'over');
  if (over) break;
  await page.evaluate(() => window.__meridius.store.debug.playerTurn());
  await idle();
  await page.waitForTimeout(300);
  await page.screenshot({ path: path.join(out, `${String(t).padStart(2, '0')}-a-player-moved.png`) });
  const t0 = Date.now();
  await page.evaluate(() => window.__meridius.store.battleScene.endTurn());
  // A frame from the middle of the enemy turn.
  await page.waitForTimeout(2200);
  await page.screenshot({ path: path.join(out, `${String(t).padStart(2, '0')}-b-enemy.png`) });
  await idle();
  if (!(await live())) break;
  const ts = await page.evaluate(() => window.__meridius.engine.timeScale);
  timings.push(((Date.now() - t0) / 1000) * ts);
  await page.waitForTimeout(300);
  await page.screenshot({ path: path.join(out, `${String(t + 1).padStart(2, '0')}-c-start.png`) });
}
const state = await page.evaluate(() => {
  if (!window.__meridius.store.battleScene) return { ended: true, chronicle: window.__meridius.store.game?.chronicle?.slice(0, 2) };
  const b = window.__meridius.store.battleScene.b;
  return { phase: b.phase, result: b.result, turn: b.turn, waves: b.waveState, enemies: b.active('enemy').length, players: b.active('player').length, fps: window.__meridius.engine.fps };
});
console.log(JSON.stringify({ state, enemyTurnSecondsAt1x: timings.map((x) => +x.toFixed(1)) }));
console.log(errors.length ? errors.slice(0, 10).join('\n') : 'no page errors');
await browser.close();
