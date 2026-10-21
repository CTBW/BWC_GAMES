// Hover check for base buildings: node scripts/basepick.mjs <probes.json>
// Probe points come from scripts/art/baselayout.py --samples: world points where
// each building is the visible top layer. Moves the real mouse to each one and
// checks the scene highlights that building.
import { chromium } from 'playwright-core';
import { readFileSync } from 'node:fs';

const [probeFile] = process.argv.slice(2);
const probes = JSON.parse(readFileSync(probeFile, 'utf8'));
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto('http://localhost:5199/?newgame&seed=1234');
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });
let bad = 0;
let total = 0;
for (const [tok, byBuilding] of Object.entries(probes)) {
  await page.evaluate((t) => {
    const s = window.__meridius.store;
    s.game.flags = { welcome: true };
    Object.keys(s.game.buildings).forEach((id, i) => (s.game.buildings[id] = Number(t.length > 1 ? t[i] : t)));
    s.commit();
  }, tok);
  await page.waitForTimeout(1500);
  for (const [id, pts] of Object.entries(byBuilding)) {
    let miss = 0;
    let n = 0;
    const wrong = {};
    for (const [wx, wy] of pts) {
      const scr = await page.evaluate(([x, y]) => {
        const { engine } = window.__meridius;
        const c = engine.scene.cam;
        const r = engine.canvas.getBoundingClientRect();
        const sx = (x - c.x) * c.zoom + r.width / 2 + r.left;
        const sy = (y - c.y) * c.zoom + r.height / 2 + r.top;
        return { sx, sy, onCanvas: document.elementFromPoint(sx, sy) === engine.canvas };
      }, [wx, wy]);
      if (!scr.onCanvas) continue;
      await page.mouse.move(scr.sx, scr.sy);
      const hover = await page.evaluate(() => window.__meridius.engine.scene.ui.hover);
      n++;
      if (hover !== id) {
        miss++;
        wrong[hover ?? 'none'] = (wrong[hover ?? 'none'] ?? 0) + 1;
      }
    }
    total += n;
    bad += miss;
    console.log(`levels ${tok} ${id.padEnd(14)} ${n - miss}/${n}` + (miss ? `  wrong: ${JSON.stringify(wrong)}` : ''));
  }
}
console.log(`hover correct ${total - bad}/${total}`, 'errors', errors.length, errors.slice(0, 3).join(' | '));
await browser.close();
process.exit(bad ? 1 : 0);
