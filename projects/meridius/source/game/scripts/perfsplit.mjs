// Where a last-stand frame spends its time: wraps the battle scene's drawing
// methods and reports milliseconds per frame for each.
// Usage: node scripts/perfsplit.mjs [zoom]
import { chromium } from 'playwright-core';

const zoom = Number(process.argv[2] ?? 0);
const base = process.env.BASE_URL ?? 'http://localhost:5199';
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto(`${base}/?newgame&seed=5`);
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base');
const out = await page.evaluate(async ([zoom, process_env_off]) => {
  const m = window.__meridius;
  m.store.debug.testBattle('last_stand', { seed: 5, mapId: 'steading' });
  const sc = m.store.battleScene;
  if (zoom) sc.cam.tzoom = sc.cam.zoom = zoom;
  const off = (process_env_off || '').split(',');
  if (off.includes('host')) sc.host = null;
  if (off.includes('night')) { sc.b.setup.objective.dawn = false; sc.atmo.night = false; sc.nightLevel = 0; }
  if (off.includes('smoke')) sc.smoke = [];
  await new Promise((r) => setTimeout(r, 600));
  const proto = Object.getPrototypeOf(sc);
  const names = ['drawWater', 'drawGrid', 'drawHighlights', 'drawFootprints', 'drawSorted', 'drawOverlays', 'drawMinimap', 'drawWaveLabels', 'drawNight', 'update'];
  const acc = {};
  for (const n of names) {
    const f = proto[n];
    if (!f) continue;
    acc[n] = 0;
    sc[n] = function (...a) {
      const t0 = performance.now();
      const r = f.apply(this, a);
      acc[n] += performance.now() - t0;
      return r;
    };
  }
  const ctx = m.engine.ctx;
  for (let i = 0; i < 30; i++) {
    sc.update(1 / 60, i / 60);
    sc.render(ctx, m.engine.w, m.engine.h, i / 60);
  }
  for (const k of Object.keys(acc)) acc[k] = 0;
  let total = 0;
  const N = 60;
  for (let i = 0; i < N; i++) {
    const t0 = performance.now();
    sc.update(1 / 60, i / 60);
    sc.render(ctx, m.engine.w, m.engine.h, i / 60);
    total += performance.now() - t0;
  }
  const res = { total: total / N };
  for (const k of Object.keys(acc)) res[k] = +(acc[k] / N).toFixed(2);
  return res;
}, [zoom, process.env.OFF ?? '']);
console.log(JSON.stringify(out));
await browser.close();
