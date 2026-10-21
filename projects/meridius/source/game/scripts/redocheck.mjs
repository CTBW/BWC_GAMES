// Reproduces "click a tile hidden behind my own soldier" and checks Redo move.
// Usage: node scripts/redocheck.mjs <outDir>
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const out = process.argv[2] ?? 'redocheck';
fs.mkdirSync(out, { recursive: true });
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto('http://localhost:5199/?newgame&seed=11');
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base');
await page.evaluate(() => window.__meridius.store.debug.testBattle('goblin_scouts', { mapId: 'forest_clearing', seed: 12 }));
await page.waitForTimeout(800);
await page.evaluate(() => window.__meridius.store.battleScene.begin());
await page.waitForFunction(() => !window.__meridius.store.battleScene.busy && window.__meridius.store.battleScene.b.phase === 'player', null, { timeout: 30000 });
const wait = (ms) => page.waitForTimeout(ms);
const toScreen = (sc, wx, wy) => ({ x: (wx - sc.cam.x) * sc.cam.zoom + innerWidth / 2, y: (wy - sc.cam.y) * sc.cam.zoom + innerHeight / 2 });

// 1. Pick a soldier and an empty reachable tile that a friendly figure covers on screen.
const setup = await page.evaluate(() => {
  const sc = window.__meridius.store.battleScene;
  const b = sc.b;
  const tw = 128, th = 64;
  const isoX = (x, y) => (x - y) * tw / 2;
  const isoY = (x, y) => (x + y) * th / 2;
  for (const u of b.active('player')) {
    sc.select(u.uid);
    const reach = b.reachable(u);
    for (const p of b.active('player')) {
      for (const [dx, dy] of [[-1, -1], [-1, 0], [0, -1]]) {
        const t = { x: p.x + dx, y: p.y + dy };
        if (!reach.has(t.y * 1000 + t.x) || (t.x === u.x && t.y === u.y)) continue;
        if (b.units.some((q) => q.x === t.x && q.y === t.y && (q.status === 'active' || q.status === 'routing'))) continue;
        const v = sc.views.get(p.uid);
        const th0 = b.map.tiles[t.y * b.map.w + t.x].h;
        if (sc.bodyCovers(v, p, isoX(t.x, t.y), isoY(t.x, t.y) - th0 * 26 - 4, 0)) return { uid: u.uid, cover: p.uid, t, start: { x: u.x, y: u.y }, h: th0 };
      }
    }
  }
  return null;
});
console.log('scenario', JSON.stringify(setup));
if (!setup) throw new Error('no covered tile found for this seed');
await page.evaluate((uid) => window.__meridius.store.battleScene.select(uid), setup.uid);
await wait(1500);

// 2. Hover the covered tile: it must preview a move there, not pick the soldier.
const pt = await page.evaluate(({ t }) => {
  const sc = window.__meridius.store.battleScene;
  const th0 = sc.b.map.tiles[t.y * sc.b.map.w + t.x].h;
  const wx = (t.x - t.y) * 64;
  const wy = (t.x + t.y) * 32 - th0 * 26 - 4;
  return { x: (wx - sc.cam.x) * sc.cam.zoom + innerWidth / 2, y: (wy - sc.cam.y) * sc.cam.zoom + innerHeight / 2 };
}, setup);
await page.mouse.move(pt.x, pt.y);
await wait(400);
const hover = await page.evaluate(() => {
  const h = window.__meridius.store.battleScene.ui.hover;
  return { unit: h.unit ?? null, tile: h.tile, pathEnd: h.path ? h.path[h.path.length - 1] : null };
});
console.log('hover', JSON.stringify(hover));
await page.screenshot({ path: path.join(out, '1-hover-covered-tile.png') });
const okHover = hover.unit === null && hover.pathEnd && hover.pathEnd.x === setup.t.x && hover.pathEnd.y === setup.t.y;

// 3. Click: the soldier walks there.
await page.mouse.click(pt.x, pt.y);
await page.waitForFunction(() => !window.__meridius.store.battleScene.busy, null, { timeout: 10000 });
await wait(300);
const after = await page.evaluate((uid) => { const u = window.__meridius.store.battleScene.b.unit(uid); return { x: u.x, y: u.y, moved: u.hasMoved, selected: window.__meridius.store.battleScene.ui.selected }; }, setup.uid);
console.log('after click', JSON.stringify(after));
const okMove = after.x === setup.t.x && after.y === setup.t.y && after.moved;
await page.mouse.move(10, 10);
await wait(300);
await page.screenshot({ path: path.join(out, '2-moved-redo-button.png') });

// 4. Redo move via the panel button.
await page.getByRole('button', { name: /Redo move/ }).click();
await page.waitForFunction(() => !window.__meridius.store.battleScene.busy, null, { timeout: 10000 });
await wait(300);
const back = await page.evaluate((uid) => { const u = window.__meridius.store.battleScene.b.unit(uid); return { x: u.x, y: u.y, moved: u.hasMoved }; }, setup.uid);
console.log('after redo', JSON.stringify(back));
const okRedo = back.x === setup.start.x && back.y === setup.start.y && !back.moved;
await page.screenshot({ path: path.join(out, '3-after-redo.png') });

// 5. Move next to an enemy and attack: Redo must be refused.
const att = await page.evaluate((uid) => {
  const sc = window.__meridius.store.battleScene;
  const b = sc.b;
  const u = b.unit(uid);
  const reach = b.reachable(u);
  for (const e of b.active('enemy')) {
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const t = { x: e.x + dx, y: e.y + dy };
      if (!reach.has(t.y * 1000 + t.x)) continue;
      b.move(uid, t.x, t.y);
      const ok = b.attack(uid, e.uid);
      sc.pump();
      return { attacked: ok, redo: b.canRedo(uid) };
    }
  }
  // Nobody in reach: move toward the enemy, then shoot or wait.
  return { attacked: false, redo: b.canRedo(uid) };
}, setup.uid);
console.log('attack', JSON.stringify(att));
await page.waitForFunction(() => !window.__meridius.store.battleScene.busy, null, { timeout: 15000 });
await wait(400);
await page.screenshot({ path: path.join(out, '4-after-attack.png') });
const okLocked = !att.attacked || att.redo.ok === false;

console.log(JSON.stringify({ okHover, okMove, okRedo, okLocked, errors }));
await browser.close();
