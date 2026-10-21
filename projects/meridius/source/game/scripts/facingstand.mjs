// Facing on a large field, played like a person: the last stand at its opening
// zoom, a squad moved to a gate with the cursor pointed at the edge it should
// face, then a squad turned on the spot. Captures each preview and checks the
// squads arrive facing the way the arrow showed.
// Usage: node scripts/facingstand.mjs <outDir> [seed]   (BASE_URL overrides the dev server)
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const out = process.argv[2] ?? 'facingstand';
const seed = Number(process.argv[3] ?? 7);
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
await page.evaluate((seed) => window.__meridius.store.debug.testBattle('last_stand', { seed }), seed);
await page.waitForTimeout(1500);
// Accept the deployment as set.
await page.evaluate(() => window.__meridius.store.battleScene.begin());
await page.waitForFunction(() => window.__meridius.store.battleScene && !window.__meridius.store.battleScene.busy && window.__meridius.store.battleScene.b.phase === 'player', null, { timeout: 60000 });
await page.waitForTimeout(800);

const screenOf = (gx, gy) =>
  page.evaluate(([gx, gy]) => {
    const sc = window.__meridius.store.battleScene;
    const t = sc.b.map.tiles.find((q) => q.x === Math.round(gx) && q.y === Math.round(gy));
    const wx = (gx - gy) * 64;
    const wy = (gx + gy) * 32 - (t?.h ?? 0) * 26;
    const c = sc.cam;
    return { x: (wx - c.x) * c.zoom + innerWidth / 2, y: (wy - c.y) * c.zoom + innerHeight / 2, zoom: c.zoom };
  }, [gx, gy]);
const crop = async (name, p, w = 640, h = 420) => {
  await page.screenshot({ path: path.join(out, name), clip: { x: Math.max(0, p.x - w / 2), y: Math.max(0, p.y - h / 2), width: w, height: h } });
};
const idle = () => page.waitForFunction(() => !window.__meridius.store.battleScene.busy, null, { timeout: 30000 });

// The squad nearest a gateway, and the open gate tile it can reach that faces the enemy.
const plan = await page.evaluate(() => {
  const sc = window.__meridius.store.battleScene;
  const b = sc.b;
  const foes = b.active('enemy');
  const gates = b.map.tiles.filter((t) => t.prop?.startsWith('gate'));
  let best = null;
  for (const u of b.active('player')) {
    const reach = b.reachable(u);
    for (const g of gates) {
      // reachable() is keyed y * 1000 + x and leaves out occupied tiles.
      if (!reach.has(g.y * 1000 + g.x)) continue;
      const d = Math.abs(u.x - g.x) + Math.abs(u.y - g.y);
      if (d < 2) continue;
      if (!best || d < best.d) best = { uid: u.uid, type: u.typeId, from: [u.x, u.y], facing: u.facing, gate: [g.x, g.y], d };
    }
  }
  // Which way is out: the side of the gate with the nearest foe.
  if (best) {
    const [gx, gy] = best.gate;
    let nf = null;
    for (const f of foes) {
      const d = Math.abs(f.x - gx) + Math.abs(f.y - gy);
      if (!nf || d < nf.d) nf = { d, x: f.x, y: f.y };
    }
    const dx = nf.x - gx;
    const dy = nf.y - gy;
    best.out = Math.abs(dx) >= Math.abs(dy) ? [Math.sign(dx), 0] : [0, Math.sign(dy)];
  }
  sc.select(best.uid);
  return best;
});
console.log('plan', JSON.stringify(plan));
await page.waitForTimeout(300);
await page.screenshot({ path: path.join(out, '0-selected.png') });

// Point at each edge of the gate tile in turn.
const names = { '1,0': '+x', '0,1': '+y', '-1,0': '-x', '0,-1': '-y' };
const hovers = [];
for (const d of [[1, 0], [0, 1], [-1, 0], [0, -1]]) {
  const p = await screenOf(plan.gate[0] + d[0] * 0.33, plan.gate[1] + d[1] * 0.33);
  await page.mouse.move(p.x, p.y);
  await page.waitForTimeout(250);
  const h = await page.evaluate(() => {
    const hv = window.__meridius.store.battleScene.ui.hover;
    return { dest: hv.dest, facing: hv.facing, facings: hv.facings };
  });
  hovers.push({ point: names[d.join(',')], ...h });
}
// Aim out of the gate, capture the preview at the opening zoom, then commit.
const aim = await screenOf(plan.gate[0] + plan.out[0] * 0.33, plan.gate[1] + plan.out[1] * 0.33);
await page.mouse.move(aim.x, aim.y);
await page.waitForTimeout(300);
const want = await page.evaluate(() => window.__meridius.store.battleScene.ui.hover.facing);
await page.screenshot({ path: path.join(out, '1-preview-full.png') });
await crop('1-preview-crop.png', aim);
await page.mouse.click(aim.x, aim.y);
await idle();
await page.waitForTimeout(400);
const moved = await page.evaluate((uid) => {
  const u = window.__meridius.store.battleScene.b.unit(uid);
  return { x: u.x, y: u.y, facing: u.facing };
}, plan.uid);
await crop('2-arrived.png', await screenOf(moved.x, moved.y));

// Turn another squad on the spot: point at the edge of its own tile behind it.
const turn = await page.evaluate(() => {
  const sc = window.__meridius.store.battleScene;
  const u = sc.b.active('player').find((q) => !q.hasMoved && q.typeId !== 'militia');
  sc.select(u.uid);
  const back = [[-1, 0], [0, -1], [1, 0], [0, 1]][u.facing];
  return { uid: u.uid, x: u.x, y: u.y, facing: u.facing, back };
});
const own = await screenOf(turn.x + turn.back[0] * 0.36, turn.y + turn.back[1] * 0.36);
await page.mouse.move(own.x, own.y);
await page.waitForTimeout(300);
const turnHover = await page.evaluate(() => {
  const hv = window.__meridius.store.battleScene.ui.hover;
  return { dest: hv.dest, facing: hv.facing, turn: hv.turn };
});
await crop('3-turn-preview.png', own);
await page.mouse.click(own.x, own.y);
await idle();
await page.waitForTimeout(400);
const turned = await page.evaluate((uid) => {
  const u = window.__meridius.store.battleScene.b.unit(uid);
  return { x: u.x, y: u.y, facing: u.facing, hasMoved: u.hasMoved };
}, turn.uid);
await crop('4-turned.png', await screenOf(turned.x, turned.y));

const ok = moved.x === plan.gate[0] && moved.y === plan.gate[1] && moved.facing === want && turned.facing === turnHover.facing && turned.x === turn.x && turned.y === turn.y;
console.log(JSON.stringify({ zoom: aim.zoom, hovers, want, moved, turn, turnHover, turned, ok }, null, 1));
console.log(errors.length ? errors.join('\n') : 'no page errors');
await browser.close();
