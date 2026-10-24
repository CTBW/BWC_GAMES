// Frame cost of the battle scene (update + render, CPU side) on a small field
// and on a last stand with every wave on the field. Headless, so it measures
// the work per frame rather than the display rate.
// Usage: node scripts/perf.mjs
import { chromium } from 'playwright-core';

const base = process.env.BASE_URL ?? 'http://localhost:5199';
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto(`${base}/?newgame&seed=5`);
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base');

const measure = (label, enc, mapId, allWaves, zoom) =>
  page.evaluate(
    async ([enc, mapId, allWaves, zoom]) => {
      const m = window.__meridius;
      m.store.debug.testBattle(enc, { seed: 5, mapId });
      const sc = m.store.battleScene;
      if (allWaves) {
        // Bring every wave onto the field at once: the worst case on screen.
        const b = sc.b;
        for (const w of b.waves) w.turn = 1;
        b.begin(() => {});
        b.phase = 'player';
        b.endTurn(() => {});
        sc.pump();
        m.engine.timeScale = 8;
        await new Promise((r) => {
          const t = setInterval(() => {
            if (!sc.busy) {
              clearInterval(t);
              r();
            }
          }, 100);
        });
        m.engine.timeScale = 1;
      }
      if (zoom) {
        sc.cam.tzoom = sc.cam.zoom = zoom;
      }
      await new Promise((r) => setTimeout(r, 800));
      const ctx = m.engine.ctx;
      // Warm up: every pose and prop sprite is generated on first use.
      for (let i = 0; i < 40; i++) {
        sc.update(1 / 60, i / 60);
        sc.render(ctx, m.engine.w, m.engine.h, i / 60);
      }
      const times = [];
      for (let i = 0; i < 90; i++) {
        const t0 = performance.now();
        sc.update(1 / 60, i / 60);
        sc.render(ctx, m.engine.w, m.engine.h, i / 60);
        times.push(performance.now() - t0);
      }
      times.sort((a, b) => a - b);
      const views = [...sc.views.values()].filter((v) => v.visible).length;
      return { avg: times.reduce((s, t) => s + t, 0) / times.length, p90: times[Math.floor(times.length * 0.9)], views, units: sc.b.active('enemy').length + sc.b.active('player').length };
    },
    [enc, mapId, allWaves, zoom],
  ).then((r) => console.log(label.padEnd(28), `avg ${r.avg.toFixed(1)}ms  p90 ${r.p90.toFixed(1)}ms  squads on field ${r.units}`));

await measure('small field', 'goblin_scouts', 'forest_clearing', false, 0);
await measure('last stand, start', 'last_stand', 'steading', false, 0);
await measure('last stand, every wave', 'last_stand', 'steading', true, 0);
await measure('every wave, zoomed out', 'last_stand', 'steading', true, 0.3);
await browser.close();
