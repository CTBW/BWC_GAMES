// Scripted play-test with screenshots of the real game.
// Usage: node scripts/playtest.mjs <outDir> [scenario] [seed]
// Requires the dev server on http://localhost:5199 and a local Chrome.
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const out = process.argv[2] ?? 'playtest-out';
const scenario = process.argv[3] ?? 'loop';
const seed = Number(process.argv[4] ?? 1234);
fs.mkdirSync(out, { recursive: true });

const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true, args: ['--use-angle=d3d11', '--enable-gpu-rasterization'] });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
const logs = [];
page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}\n${e.stack}`));

await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
const wait = (ms) => page.waitForTimeout(ms);
const shot = async (name) => {
  const f = path.join(out, `${name}.png`);
  await page.screenshot({ path: f });
  console.log('shot', f);
};
const st = (fn, arg) => page.evaluate(fn, arg);

await page.goto(`http://localhost:5199/?newgame&seed=${seed}`);
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });
await wait(1500);
await shot('01-base');

if (scenario === 'loop' || scenario === 'battle') {
  // Open a building panel.
  await st(() => window.__meridius.store.openPanel('barracks'));
  await wait(500);
  await shot('02-barracks');
  await st(() => window.__meridius.store.openPanel(null));
  await st(() => window.__meridius.store.goPrep());
  await wait(800);
  await shot('03-prep');
  await page.getByRole('button', { name: 'March Out' }).click();
  await page.waitForFunction(() => window.__meridius.store.screen === 'campaign');
  await wait(1500);
  await shot('04-campaign');
  // March to the first battle-like node if one is reachable, else the first node.
  const target = await st(() => {
    const s = window.__meridius.store;
    const ex = s.game.expedition;
    const next = ex.edges.filter((e) => e[0] === ex.current).map((e) => ex.nodes.find((n) => n.id === e[1]));
    return (next.find((n) => n.type === 'battle') ?? next[0]).id;
  });
  await st((id) => window.__meridius.store.clickNode(id), target);
  await wait(2600);
  await shot('05-arrive');
  // Resolve until a battle prompt appears (max a few steps).
  for (let i = 0; i < 8; i++) {
    const kind = await st(() => window.__meridius.store.game.expedition?.pending?.kind ?? null);
    if (kind === 'battle') break;
    if (kind === 'event') {
      await st(() => {
        const s = window.__meridius.store;
        const p = s.game.expedition.pending;
        if (!p.result) document.querySelector('.choice:not([disabled])')?.click();
      });
      await wait(400);
      await shot(`05-event-${i}`);
    }
    await st(() => {
      const s = window.__meridius.store;
      if (s.game.expedition?.pending) s.dismiss();
    });
    await wait(300);
    const pend = await st(() => window.__meridius.store.game.expedition?.pending?.kind ?? null);
    if (!pend) {
      const nxt = await st(() => {
        const ex = window.__meridius.store.game.expedition;
        const next = ex.edges.filter((e) => e[0] === ex.current).map((e) => ex.nodes.find((n) => n.id === e[1]));
        return (next.find((n) => n.type === 'battle') ?? next[0]).id;
      });
      await st((id) => window.__meridius.store.clickNode(id), nxt);
      await wait(2600);
    }
  }
  await shot('06-battle-prompt');
  await st(() => window.__meridius.store.startBattle());
  await wait(2000);
  await shot('07-deploy');
  await st(() => window.__meridius.store.battleScene.begin());
  await wait(3500);
  await shot('08-turn1');
  // Hover an enemy with the first unit selected to show a forecast.
  const hover = await st(() => {
    const sc = window.__meridius.store.battleScene;
    const b = sc.b;
    const me = b.active('player').find((u) => !u.shot) ?? b.active('player')[0];
    sc.select(me.uid);
    const foe = b.active('enemy').sort((a, c) => Math.hypot(a.x - me.x, a.y - me.y) - Math.hypot(c.x - me.x, c.y - me.y))[0];
    const wx = (foe.x - foe.y) * 64;
    const wy = (foe.x + foe.y) * 32 - 40;
    const cam = sc.cam;
    return { x: (wx - cam.x) * cam.zoom + 960, y: (wy - cam.y) * cam.zoom + 540 };
  });
  await page.mouse.move(hover.x, hover.y);
  await wait(600);
  await shot('09-forecast');
  // Move a unit forward toward the enemy.
  await st(() => {
    const sc = window.__meridius.store.battleScene;
    const b = sc.b;
    for (const u of b.active('player')) {
      const reach = b.reachable(u);
      let best = null;
      for (const [k] of reach) {
        const p = { x: k % 1000, y: Math.floor(k / 1000) };
        if (!best || p.y < best.y) best = p;
      }
      if (best) b.move(u.uid, best.x, best.y);
    }
    sc.pump();
  });
  await wait(4000);
  await shot('10-advance');
  await st(() => window.__meridius.store.battleScene.endTurn());
  await wait(9000);
  await shot('11-enemy-turn');
  await st(() => window.__meridius.store.debug.autoBattle());
  await wait(25000);
  await shot('12-battle-end');
  await wait(3000);
  await shot('13-after');
}

fs.writeFileSync(path.join(out, 'console.log'), logs.join('\n'));
const errors = logs.filter((l) => l.includes('error'));
console.log(`console lines: ${logs.length}, errors: ${errors.length}`);
for (const e of errors.slice(0, 10)) console.log(e);
await browser.close();
