// Facing sheet: every unit type in all four facings, idle and attacking, drawn
// with the sprites and mirroring the battle renderer uses. Compare with the
// reference sheets "Facing when moving" (shield on the left arm in every view).
// Usage: node scripts/facingsheet.mjs <out.png> [types,comma,separated]
import { chromium } from 'playwright-core';

const out = process.argv[2] ?? 'facing-sheet.png';
const zoom = Number(process.env.ZOOM ?? 1);
const types = (process.argv[3] ?? 'footman,collie_guard,spearman,crossbowman,goblin_spear,goblin_archer,orc_warrior,orc_brute,orc_warlord,troll').split(',');
const base = process.env.BASE_URL ?? 'http://localhost:5199';
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: Math.round(1800 * zoom), height: Math.round(140 + types.length * 150 * zoom) } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto(`${base}/?newgame&seed=3`);
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });
await page.evaluate(([types, zoom]) => {
  const { sprite } = window.__meridius;
  const c = document.createElement('canvas');
  c.width = Math.round(1800 * zoom);
  c.height = Math.round(140 + types.length * 150 * zoom);
  c.style.cssText = 'position:fixed;left:0;top:0;z-index:99999;background:#e9e4d6';
  document.body.appendChild(c);
  const x = c.getContext('2d');
  x.fillStyle = '#e9e4d6';
  x.fillRect(0, 0, c.width, c.height);
  // facing: 0 +x (down-right), 1 +y (down-left), 2 -x (up-left), 3 -y (up-right)
  const cols = [1, 0, 3, 2];
  const names = { 0: '↘ +x', 1: '↙ +y', 2: '↖ −x', 3: '↗ −y' };
  x.font = '600 16px Georgia';
  x.fillStyle = '#3a2a1a';
  cols.forEach((f, i) => {
    x.fillText(`${names[f]} idle`, (170 + i * 400) * zoom, 30);
    x.fillText('attack', (170 + i * 400 + 190) * zoom, 30);
  });
  const key = (type, pose, f) => {
    const front = f === 0 || f === 1;
    const lead = f === 0 || f === 2;
    const shield = ['footman', 'collie_guard', 'orc_warrior'].includes(type);
    return { k: `${type}_${pose}_${front ? 'f' : 'b'}${lead && shield ? 's' : ''}`, flip: lead };
  };
  types.forEach((type, r) => {
    const y = 60 + (100 + r * 150) * zoom;
    x.fillStyle = '#3a2a1a';
    x.fillText(type, 10, y - 60);
    cols.forEach((f, i) => {
      ['idle', 'atk'].forEach((pose, j) => {
        const { k, flip } = key(type, pose, f);
        const s = sprite(k, 0);
        const sc = s.scale * 0.95 * zoom;
        x.save();
        x.translate((200 + i * 400 + j * 190) * zoom, y);
        x.scale(flip ? -sc : sc, sc);
        x.drawImage(s.img, s.sx ?? 0, s.sy ?? 0, s.w, s.h, -s.ax, -s.ay, s.w, s.h);
        x.restore();
        // Facing arrow on the ground.
        const d = [[1, 0], [0, 1], [-1, 0], [0, -1]][f];
        const ax = (d[0] - d[1]) * 26;
        const ay = (d[0] + d[1]) * 13;
        x.strokeStyle = '#c0392b';
        x.lineWidth = 3;
        x.beginPath();
        x.moveTo((200 + i * 400 + j * 190) * zoom, y + 6);
        x.lineTo((200 + i * 400 + j * 190) * zoom + ax, y + 6 + ay);
        x.stroke();
      });
    });
  });
}, [types, zoom]);
await page.waitForTimeout(300);
await page.screenshot({ path: out });
console.log(errors.length ? errors.join('\n') : 'no page errors');
await browser.close();
