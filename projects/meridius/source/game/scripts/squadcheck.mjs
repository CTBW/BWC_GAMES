// Squad system review: formations, marching in formation, volleys, casualties
// and reorganisation, captured from the real battle scene.
// Usage: node scripts/squadcheck.mjs <outDir> [encounterId] [seed]
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const out = process.argv[2] ?? 'squadcheck';
const encounter = process.argv[3] ?? 'orc_overseer';
const seed = Number(process.argv[4] ?? 7);
fs.mkdirSync(out, { recursive: true });
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
const logs = [];
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
page.on('console', (m) => { if (m.type() === 'error') logs.push(`[console] ${m.text()}`); });
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
const wait = (ms) => page.waitForTimeout(ms);
const st = (fn, arg) => page.evaluate(fn, arg);
let n = 0;
const shot = async (name) => {
  const f = path.join(out, `${String(++n).padStart(3, '0')}-${name}.png`);
  await page.screenshot({ path: f });
  return f;
};
const idle = async (max = 15000) => {
  const t0 = Date.now();
  await wait(150);
  while (Date.now() - t0 < max) {
    if (!(await st(() => window.__meridius.store.battleScene?.busy))) return;
    await wait(100);
  }
};

await page.goto(`${process.env.BASE_URL ?? 'http://localhost:5199'}/?newgame&seed=${seed}`);
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });
await st(([e, s]) => window.__meridius.store.debug.testBattle(e, { seed: s }), [encounter, seed]);
await wait(1500);
await shot('deploy');
// Close-up of the deployed company.
await st(() => {
  const sc = window.__meridius.store.battleScene;
  const u = sc.b.active('player')[0];
  const v = sc.views.get(u.uid);
  sc.cam.tzoom = 1.5;
  sc.cam.tx = (v.x - v.y) * 64;
  sc.cam.ty = (v.x + v.y) * 32 - 40;
});
await wait(1500);
await shot('deploy-closeup');
await st(() => window.__meridius.store.battleScene.begin());
await idle();
await st(() => { const c = window.__meridius.store.battleScene.cam; c.tzoom = 0.86; });

// Two turns: melee squads march toward the enemy; captures during the march.
for (let t = 0; t < 2; t++) {
  await st(() => {
    const sc = window.__meridius.store.battleScene;
    const b = sc.b;
    for (const u of b.active('player')) {
      if (u.shot) continue;
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
  for (let i = 0; i < 6; i++) {
    await wait(260);
    await shot(`t${t}-march`);
  }
  await idle();
  await st(() => window.__meridius.store.battleScene.endTurn());
  for (let i = 0; i < 30; i++) {
    await wait(200);
    if (i % 3 === 0) await shot(`t${t}-enemy`);
    const busy = await st(() => window.__meridius.store.battleScene.busy);
    if (!busy && i > 6) break;
  }
  await idle();
}

// Everyone who can attacks; dense frames to review volleys and casualties.
await st(() => {
  const sc = window.__meridius.store.battleScene;
  const b = sc.b;
  for (const u of b.active('player')) {
    const ts = b.targets(u);
    if (ts.length) b.attack(u.uid, ts[0].uid);
  }
  sc.pump();
});
for (let i = 0; i < 40; i++) {
  await wait(110);
  await shot('player-attacks');
  const busy = await st(() => window.__meridius.store.battleScene.busy);
  if (!busy && i > 6) break;
}
const state = await st(() => {
  const b = window.__meridius.store.battleScene.b;
  return b.units.map((u) => `${u.faction} ${u.typeId} hp ${u.hp}/${u.maxHp} alive ${u.alive ?? '-'} ${u.status}`);
});
fs.writeFileSync(path.join(out, 'state.txt'), state.join('\n') + '\n\n' + logs.join('\n'));
console.log(state.join('\n'));
console.log(logs.join('\n') || 'no page errors');
await browser.close();
