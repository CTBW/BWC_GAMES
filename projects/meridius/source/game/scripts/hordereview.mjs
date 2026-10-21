// Review captures of a last stand: close-ups of the fighting at the gates by
// night, the facing preview on the large field, and the ending at dawn.
// Usage: node scripts/hordereview.mjs <outDir> [seed]
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const [out = 'hordereview', seedArg = '5'] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const base = process.env.BASE_URL ?? 'http://localhost:5199';
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto(`${base}/?newgame&seed=3`);
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });
await page.evaluate((seed) => {
  const m = window.__meridius;
  m.store.debug.testBattle('last_stand', { seed, mapId: 'steading' });
  m.engine.timeScale = 3;
}, Number(seedArg));
await page.waitForTimeout(1200);
const scene = (fn, arg) => page.evaluate(fn, arg);
const idle = () => page.waitForFunction(() => !window.__meridius.store.battleScene || !window.__meridius.store.battleScene.busy, null, { timeout: 180000 });
const live = () => scene(() => !!window.__meridius.store.battleScene);
await scene(() => window.__meridius.store.battleScene.begin());
await idle();

// Facing preview: select the first footman and hover a tile two steps toward the enemy, pointing at each edge.
const prev = await scene(() => {
  const sc = window.__meridius.store.battleScene;
  const u = sc.b.active('player').find((x) => x.typeId === 'footman');
  sc.select(u.uid);
  sc.cam.tzoom = sc.cam.zoom = 1.1;
  sc.cam.tx = sc.cam.x = (u.x - u.y) * 64;
  sc.cam.ty = sc.cam.y = (u.x + u.y) * 32 - 30;
  const reach = [...sc.b.reachable(u).keys()].map((k) => ({ x: k % 1000, y: Math.floor(k / 1000) })).filter((p) => !(p.x === u.x && p.y === u.y));
  reach.sort((a, b) => Math.abs(a.x - u.x) + Math.abs(a.y - u.y) - (Math.abs(b.x - u.x) + Math.abs(b.y - u.y)));
  return reach[Math.min(2, reach.length - 1)];
});
await page.waitForTimeout(400);
const screenOf = (gx, gy) => scene(([gx, gy]) => {
  const sc = window.__meridius.store.battleScene;
  const t = sc.b.map.tiles.find((q) => q.x === Math.round(gx) && q.y === Math.round(gy));
  const wx = (gx - gy) * 64;
  const wy = (gx + gy) * 32 - (t?.h ?? 0) * 26;
  return { x: (wx - sc.cam.x) * sc.cam.zoom + innerWidth / 2, y: (wy - sc.cam.y) * sc.cam.zoom + innerHeight / 2 };
}, [gx, gy]);
if (prev) {
  const p = await screenOf(prev.x - 0.32, prev.y);
  await page.mouse.move(p.x, p.y);
  await page.waitForTimeout(300);
  await page.screenshot({ path: path.join(out, '01-facing-preview-night.png') });
}

// Play turns with the AI for the company; close-ups of the busiest fight each enemy turn.
let n = 2;
for (let t = 1; t <= 9; t++) {
  if (!(await live())) break;
  if (await scene(() => window.__meridius.store.battleScene.b.phase === 'over')) break;
  await scene(() => window.__meridius.store.debug.playerTurn());
  await idle();
  if (!(await live())) break;
  await scene(() => window.__meridius.store.battleScene.endTurn());
  await page.waitForTimeout(2600);
  if (!(await live())) break;
  // Zoom in on the player squad with the most enemies around it.
  await scene(() => {
    const sc = window.__meridius.store.battleScene;
    const b = sc.b;
    let best = null;
    let most = -1;
    for (const u of b.active('player')) {
      const k = b.active('enemy').filter((e) => Math.abs(e.x - u.x) + Math.abs(e.y - u.y) <= 2).length;
      if (k > most) {
        most = k;
        best = u;
      }
    }
    if (!best) return;
    sc.cam.tzoom = sc.cam.zoom = 1.25;
    sc.cam.tx = sc.cam.x = (best.x - best.y) * 64;
    sc.cam.ty = sc.cam.y = (best.x + best.y) * 32 - 40;
  });
  await page.waitForTimeout(500);
  await page.screenshot({ path: path.join(out, `${String(n++).padStart(2, '0')}-turn${t}-closeup.png`) });
  await idle();
  if (!(await live())) break;
  await page.waitForTimeout(200);
  await scene(() => {
    const sc = window.__meridius.store.battleScene;
    sc.cam.tzoom = sc.cam.zoom = 0.62;
  });
  await page.waitForTimeout(700);
  await page.screenshot({ path: path.join(out, `${String(n++).padStart(2, '0')}-turn${t + 1}-wide.png`) });
}
// The ending: hold the final frames.
const res = await scene(() => {
  const sc = window.__meridius.store.battleScene;
  return sc ? { phase: sc.b.phase, result: sc.b.result, turn: sc.b.turn } : { ended: true };
});
console.log(JSON.stringify(res));
console.log(errors.length ? errors.slice(0, 5).join('\n') : 'no page errors');
await browser.close();
