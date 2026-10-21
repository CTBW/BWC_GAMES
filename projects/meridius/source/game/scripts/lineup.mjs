// Renders every unit type and pose side by side on a neutral ground for review.
// Usage: node scripts/lineup.mjs <out.png> [variant]
import { chromium } from 'playwright-core';
const out = process.argv[2] ?? 'lineup.png';
const variant = Number(process.argv[3] ?? 0);
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const types = ['footman', 'spearman', 'crossbowman', 'collie_guard', 'goblin_spear', 'goblin_archer', 'orc_warrior', 'orc_brute', 'orc_warlord', 'troll'];
const W = 1800;
const ROW = 175;
const H = 60 + types.length * ROW;
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: W, height: H } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto('http://localhost:5199/?newgame&seed=2');
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base');
await page.evaluate(async ({ v, types, W, H, ROW }) => {
  const { sprite, hasArt, drawSprite, drawCastShadow } = await import('/src/render/assets.ts');
  const { proceduralSprite } = await import('/src/render/procedural.ts');
  const poses = ['idle_f', 'atk_f', 'idle_b', 'atk_b', 'flee_b', 'dead'];
  const c = document.createElement('canvas');
  c.width = W; c.height = H;
  c.style.cssText = 'position:fixed;inset:0;z-index:99';
  document.body.appendChild(c);
  const x = c.getContext('2d');
  const g = x.createLinearGradient(0, 0, 0, H);
  g.addColorStop(0, '#8fae4a'); g.addColorStop(1, '#6f913a');
  x.fillStyle = g; x.fillRect(0, 0, W, H);
  x.font = '600 15px Cinzel, serif'; x.fillStyle = '#20140a';
  x.fillText(`variant ${v}`, 10, 20);
  types.forEach((t, ti) => {
    x.fillText(t, 10, 50 + ti * ROW);
    poses.forEach((p, pi) => {
      const key = `${t}_${p}`;
      // Procedural figures are built directly so every variant index can be reviewed.
      const s = hasArt(key) ? sprite(key, v) : (proceduralSprite(key, v) ?? sprite(key, v));
      const px = 260 + pi * 250;
      const py = 40 + (ti + 1) * ROW;
      x.fillStyle = 'rgba(20,25,10,0.3)'; x.beginPath(); x.ellipse(px, py, 30, 14, 0, 0, 7); x.fill();
      drawCastShadow(x, s, px, py, false, 1, 0.2);
      drawSprite(x, s, px, py, { scale: 1.2 });
    });
  });
}, { v: variant, types, W, H, ROW });
await page.waitForTimeout(300);
await page.screenshot({ path: out });
console.log('saved', out, 'errors', errors.length, errors.join(' | '));
await browser.close();
