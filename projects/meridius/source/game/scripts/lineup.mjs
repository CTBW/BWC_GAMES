// Renders every unit type and pose side by side on a neutral ground for review.
// Usage: node scripts/lineup.mjs <out.png> [variant]
// Draws through the standalone sprite harness (scripts/art/harness.html), which
// imports only the sprite modules, so it works while the rest of the game is
// mid-edit. More sheets for the newer units: scripts/art/newunits.mjs.
import { chromium } from 'playwright-core';
const out = process.argv[2] ?? 'lineup.png';
const variant = Number(process.argv[3] ?? 0);
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const url = process.env.HARNESS_URL ?? 'http://localhost:5199/scripts/art/harness.html';
const types = [
  'footman', 'spearman', 'crossbowman', 'collie_guard', 'battle_mage', 'engineer',
  'goblin_spear', 'goblin_archer', 'goblin_shaman', 'orc_warrior', 'orc_brute', 'orc_warlord', 'troll',
  'ballista', 'mangonel', 'rock_lobber', 'war_wagon',
];
/** War engines are wider than a soldier: drawn smaller so the cells do not overlap. */
const engines = new Set(['ballista', 'mangonel', 'rock_lobber', 'war_wagon']);
const W = 1800;
const ROW = 175;
const H = 60 + types.length * ROW;
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: W, height: H } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.goto(url);
await page.waitForFunction(() => window.__artReady === true, null, { timeout: 30000 });
await page.evaluate(async ({ v, types, engines, W, H, ROW }) => {
  const { sprite, hasArt, drawSprite, drawCastShadow, proceduralSprite } = window.__art;
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
    const py = 40 + (ti + 1) * ROW;
    x.fillStyle = '#20140a';
    x.fillText(t, 10, py - 60);
    const sc = engines.includes(t) ? 0.75 : 1.2;
    poses.forEach((p, pi) => {
      const key = `${t}_${p}`;
      // Procedural figures are built directly so every variant index can be reviewed;
      // engines draw fewer looks, so a missing index falls back to the cached set.
      const s = hasArt(key) ? sprite(key, v) : (proceduralSprite(key, v) ?? sprite(key, v));
      const px = 260 + pi * 250;
      x.fillStyle = 'rgba(20,25,10,0.3)'; x.beginPath(); x.ellipse(px, py, 30, 14, 0, 0, 7); x.fill();
      drawCastShadow(x, s, px, py, false, sc, 0.2);
      drawSprite(x, s, px, py, { scale: sc });
    });
  });
}, { v: variant, types, engines: [...engines], W, H, ROW });
await page.waitForTimeout(300);
await page.screenshot({ path: out });
console.log('saved', out, 'errors', errors.length, errors.join(' | '));
await browser.close();
