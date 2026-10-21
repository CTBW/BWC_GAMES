// Captures frame sequences during combat to review animation and feedback.
// Usage: node scripts/combatframes.mjs <outDir> [seed]
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const out = process.argv[2] ?? 'frames';
const seed = Number(process.argv[3] ?? 99);
fs.mkdirSync(out, { recursive: true });
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
const logs = [];
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
const wait = (ms) => page.waitForTimeout(ms);
const st = (fn, arg) => page.evaluate(fn, arg);
let n = 0;
const shot = async (name) => {
  const f = path.join(out, `${String(++n).padStart(3, '0')}-${name}.png`);
  await page.screenshot({ path: f });
};

await page.goto(`http://localhost:5199/?newgame&seed=${seed}`);
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });
// Straight into a battle via the debug flow.
await st(() => window.__meridius.store.debug.autoPrepare(1));
await wait(500);
// Force the first node to be a battle by marching until a battle is pending.
for (let i = 0; i < 6; i++) {
  const kind = await st(() => window.__meridius.store.game.expedition?.pending?.kind ?? null);
  if (kind === 'battle') break;
  if (kind) await st(() => { const s = window.__meridius.store; const p = s.game.expedition.pending; if (p.kind === 'event' && !p.result) document.querySelector('.choice:not([disabled])')?.click(); s.dismiss(); });
  else await st(() => { const s = window.__meridius.store; const ex = s.game.expedition; const nx = ex.edges.filter((e) => e[0] === ex.current).map((e) => ex.nodes.find((x) => x.id === e[1])); s.clickNode((nx.find((x) => x.type === 'battle') ?? nx[0]).id); });
  await wait(2600);
}
await st(() => window.__meridius.store.startBattle());
await wait(1200);
await st(() => window.__meridius.store.battleScene.begin());
await wait(2500);
// Advance the whole company to contact over two turns using the AI for the player.
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
  await wait(2500);
  await st(() => window.__meridius.store.battleScene.endTurn());
  // Capture the enemy turn densely.
  for (let i = 0; i < 40; i++) {
    await shot(`t${t}-enemy`);
    await wait(120);
    const busy = await st(() => window.__meridius.store.battleScene.busy);
    if (!busy && i > 8) break;
  }
}
// Player shots: crossbows fire at the nearest target.
await st(() => {
  const sc = window.__meridius.store.battleScene;
  const b = sc.b;
  for (const u of b.active('player')) {
    const ts = b.targets(u);
    if (ts.length) b.attack(u.uid, ts[0].uid);
  }
  sc.pump();
});
for (let i = 0; i < 50; i++) {
  await shot('player-attacks');
  await wait(90);
  const busy = await st(() => window.__meridius.store.battleScene.busy);
  if (!busy && i > 8) break;
}
fs.writeFileSync(path.join(out, 'errors.log'), logs.join('\n'));
console.log('frames', n, 'errors', logs.length, logs.slice(0, 5).join('\n'));
await browser.close();
