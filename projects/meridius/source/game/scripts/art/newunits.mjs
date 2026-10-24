// Review sheets for the battle mage, goblin shaman, engineer and the war engines.
// Draws through the standalone sprite harness (scripts/art/harness.html), so it
// works even while the rest of the game is mid-edit.
// Usage: node scripts/art/newunits.mjs [outDir] [sheet ...]
//   sheets: lineup variants engines squad portraits (default: all)
import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';

const outDir = process.argv[2] ?? '../../review/new-units';
const only = process.argv.slice(3);
const want = (s) => !only.length || only.includes(s);
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const URL = process.env.HARNESS_URL ?? 'http://localhost:5199/scripts/art/harness.html';
mkdirSync(outDir, { recursive: true });

const FIGS = ['battle_mage', 'goblin_shaman', 'engineer'];
const REF = ['footman', 'crossbowman', 'goblin_archer', 'goblin_horn'];
const ENGINES = ['ballista', 'mangonel', 'rock_lobber', 'war_wagon'];
const POSES = ['idle_f', 'atk_f', 'idle_b', 'atk_b', 'flee_b', 'dead'];
const EPOSES = ['idle_f', 'atk_f', 'idle_b', 'atk_b', 'dead'];

const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 400, height: 300 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
await page.goto(URL);
await page.waitForFunction(() => window.__artReady === true, null, { timeout: 30000 });

/**
 * Render a scene: items are sprites (key, v, x, y, scale, flip, shadow) or
 * labels, drawn in order on a background, then saved as a PNG.
 */
async function scene(file, W, H, items, bg = 'grass') {
  await page.setViewportSize({ width: W, height: H });
  await page.evaluate(
    ({ W, H, items, bg }) => {
      const A = window.__art;
      document.querySelectorAll('canvas').forEach((c) => c.remove());
      const c = document.createElement('canvas');
      c.width = W;
      c.height = H;
      c.style.cssText = 'position:fixed;left:0;top:0';
      document.body.appendChild(c);
      const x = c.getContext('2d');
      if (bg === 'grass') {
        const g = x.createLinearGradient(0, 0, 0, H);
        g.addColorStop(0, '#8fae4a');
        g.addColorStop(1, '#6f913a');
        x.fillStyle = g;
      } else x.fillStyle = bg;
      x.fillRect(0, 0, W, H);
      const get = (key, v) => (A.hasArt(key) ? A.sprite(key, v) : (A.proceduralSprite(key, v) ?? A.sprite(key, v)));
      for (const it of items) {
        if (it.text !== undefined) {
          x.font = `600 ${it.size ?? 14}px Georgia, serif`;
          x.fillStyle = it.color ?? '#20140a';
          x.fillText(it.text, it.x, it.y);
          continue;
        }
        if (it.tile) {
          // An isometric tile outline centred on (x, y), at the battle's 128x64 scale times `k`.
          const k = it.k ?? 1;
          x.strokeStyle = 'rgba(30,40,10,0.35)';
          x.lineWidth = 1;
          x.beginPath();
          x.moveTo(it.x - 64 * k, it.y);
          x.lineTo(it.x, it.y - 32 * k);
          x.lineTo(it.x + 64 * k, it.y);
          x.lineTo(it.x, it.y + 32 * k);
          x.closePath();
          x.stroke();
          continue;
        }
        if (it.rect) {
          x.fillStyle = it.rect;
          x.fillRect(it.x, it.y, it.w, it.h);
          continue;
        }
        const s = get(it.key, it.v ?? 0);
        if (it.contact) {
          x.fillStyle = 'rgba(20,25,10,0.3)';
          x.beginPath();
          x.ellipse(it.x, it.y + 1, it.contact[0], it.contact[1], 0, 0, Math.PI * 2);
          x.fill();
        }
        if (it.shadow !== false) A.drawCastShadow(x, s, it.x, it.y, !!it.flip, it.scale ?? 1, it.shadowAlpha ?? 0.18);
        A.drawSprite(x, s, it.x, it.y, { scale: it.scale ?? 1, flip: !!it.flip });
        if (it.mark) {
          x.fillStyle = '#f0f';
          x.fillRect(it.x - 1.5, it.y - 1.5, 3, 3);
        }
      }
    },
    { W, H, items, bg },
  );
  await page.locator('canvas').screenshot({ path: join(outDir, file) });
  console.log('saved', file);
}

const label = (text, x, y, size) => ({ text, x, y, size });

// 1. Lineups: every pose of the new figures beside reference types, per variant.
if (want('lineup')) {
  const types = [...FIGS, ...REF];
  for (let v = 0; v < 6; v++) {
    const ROW = 190;
    const items = [label(`variant ${v}`, 10, 22, 16)];
    types.forEach((t, ti) => {
      const py = 46 + (ti + 1) * ROW;
      items.push(label(t, 10, py - 60));
      POSES.forEach((p, pi) => {
        const px = 250 + pi * 230;
        items.push({ key: `${t}_${p}`, v, x: px, y: py, scale: 1.2, contact: [30, 14], mark: true });
      });
    });
    await scene(`lineup-v${v}.png`, 1640, 60 + types.length * 190, items);
  }
}

// 2. Variant close-ups: each new figure's six looks, front and back, at 2x.
if (want('variants')) {
  for (const t of FIGS) {
    const items = [label(t, 10, 22, 16)];
    for (let v = 0; v < 6; v++) {
      const px = 120 + v * 210;
      items.push(label(`v${v}`, px - 10, 44));
      items.push({ key: `${t}_idle_f`, v, x: px, y: 290, scale: 2, contact: [40, 16] });
      items.push({ key: `${t}_atk_f`, v, x: px, y: 560, scale: 2, contact: [40, 16] });
      items.push({ key: `${t}_idle_b`, v, x: px, y: 830, scale: 2, contact: [40, 16] });
    }
    await scene(`variants-${t}.png`, 1320, 860, items);
  }
}

// 2b. Close-up of chosen keys at 3x: node scripts/art/newunits.mjs <dir> zoom key:v key:v ...
if (only[0] === 'zoom' || only[0] === 'ezoom') {
  // ezoom: engines, two per row at 2.4x.
  const eng = only[0] === 'ezoom';
  const keys = only.slice(1);
  const items = [];
  const cw = eng ? 700 : 330;
  const ch = eng ? 520 : 600;
  const per = eng ? 2 : keys.length;
  keys.forEach((kv, i) => {
    const [key, v] = kv.split(':');
    const cx = (i % per) * cw;
    const cy = Math.floor(i / per) * ch;
    if (eng) items.push({ tile: true, x: cx + cw / 2, y: cy + ch - 150, k: 2.4 / 0.52 });
    items.push({ key, v: Number(v ?? 0), x: cx + (eng ? cw / 2 : 180), y: cy + ch - (eng ? 150 : 40), scale: eng ? 2.4 : 3.2, shadow: eng, mark: eng });
    items.push(label(kv, cx + 20, cy + 24));
  });
  await scene(eng ? 'ezoom.png' : 'zoom.png', per * cw, Math.ceil(keys.length / per) * ch, items);
}

// 3. Engines: all poses and variants at full figure scale beside a footman.
if (want('engines')) {
  for (let v = 0; v < 3; v++) {
    const ROW = 300;
    const items = [label(`engines, variant ${v}`, 10, 22, 16)];
    ENGINES.forEach((t, ti) => {
      const py = 40 + (ti + 1) * ROW - 60;
      items.push(label(t, 10, py - 120));
      items.push({ key: ti % 2 ? 'goblin_rabble_idle_f' : 'footman_idle_f', v: 0, x: 80, y: py, scale: 1 });
      EPOSES.forEach((p, pi) => {
        const px = 300 + pi * 330;
        items.push({ tile: true, x: px, y: py, k: 1 / 0.52 });
        items.push({ key: `${t}_${p}`, v, x: px, y: py, scale: 1, mark: true });
      });
    });
    await scene(`engines-v${v}.png`, 1940, 80 + ENGINES.length * 300, items);
  }
}

// 4. Squad scale: squads at the battle's 0.52 member scale, engines with crew,
// facing the camera (left half) and away from it (right half). Rendered at the
// true 1:1 screen size and magnified 2x.
if (want('squad')) {
  for (const Z of [1, 2]) {
    const K = 0.52 * Z;
    const COL = 30 * Z;
    const ROW = 11 * Z;
    const LEAN = 4 * Z;
    const items = [];
    const W = 1500 * Z;
    const H = 820 * Z;
    const tile = (x, y) => items.push({ tile: true, x, y, k: Z });
    // A squad of six in two ranks on a tile at (cx, cy); front = faces camera.
    const squad = (type, cx, cy, front, flip, vs = [0, 1, 2, 3, 4, 5]) => {
      const fs = front ? 1 : -1;
      const ls = flip ? 1 : -1;
      const slots = [-COL, 0, COL].map((x) => ({ x: x + ls * LEAN, y: fs * ROW })).concat([-COL, 0, COL].map((x) => ({ x: x - ls * LEAN, y: -fs * ROW })));
      const pose = front ? 'idle_f' : 'idle_b';
      tile(cx, cy);
      slots
        .map((s, i) => ({ ...s, v: vs[i % vs.length] }))
        .sort((a, b) => a.y - b.y)
        .forEach((s) => items.push({ key: `${type}_${pose}`, v: s.v, x: cx + s.x, y: cy + s.y, scale: K, flip, contact: [14 * Z, 6.5 * Z] }));
    };
    // An engine on a tile with three crew: two behind it, one at its far side.
    const engine = (type, crew, cx, cy, front, flip, atk = false, v = 0) => {
      // Screen direction the engine aims (unmirrored front: down-left).
      const ax = (front ? -1 : 1) * (flip ? -1 : 1);
      const ay = front ? 1 : -1;
      // Its near side, across the aim toward the camera.
      const sx = (flip ? -1 : 1) * 1;
      tile(cx, cy);
      const pose = `${atk ? 'atk' : 'idle'}_${front ? 'f' : 'b'}`;
      const crewAt = [
        { b: 50, s: -10, v: 0 },
        { b: 42, s: 18, v: 1 },
        { b: 6, s: -30, v: 2 },
      ].map((c) => ({ x: cx + (-ax * c.b * 0.9 + sx * c.s * 0.9) * Z, y: cy + (-ay * c.b * 0.45 + c.s * 0.45) * Z, v: c.v }));
      const list = [
        ...crewAt.map((c) => ({ key: `${crew}_${pose}`, v: c.v, x: c.x, y: c.y, scale: K, flip, contact: [14 * Z, 6.5 * Z] })),
        { key: `${type}_${pose}`, v, x: cx, y: cy, scale: K, flip },
      ];
      list.sort((a, b) => a.y - b.y).forEach((it) => items.push(it));
    };
    items.push(label('squad scale 0.52 - facing the camera', 20 * Z, 26 * Z, 16 * Z));
    items.push(label('facing away', W / 2 + 20 * Z, 26 * Z, 16 * Z));
    const rows = [150, 330, 520, 710].map((r) => r * Z);
    for (const [half, front] of [[0, true], [W / 2, false]]) {
      const x0 = half + 110 * Z;
      const at = (k) => x0 + k * 150 * Z;
      squad('footman', at(0), rows[0], front, false);
      squad('battle_mage', at(1), rows[0], front, false);
      squad('crossbowman', at(2), rows[0], front, false);
      squad('engineer', at(3), rows[0], front, false);
      squad('goblin_rabble', at(0), rows[1], front, false);
      squad('goblin_shaman', at(1), rows[1], front, false);
      squad('goblin_archer', at(2), rows[1], front, false);
      squad('goblin_horn', at(3), rows[1], front, false);
      engine('ballista', 'engineer', at(0.3), rows[2], front, false);
      engine('mangonel', 'engineer', at(1.6), rows[2], front, false, true);
      engine('mangonel', 'engineer', at(2.9), rows[2], front, true);
      engine('rock_lobber', 'goblin_rabble', at(0.3), rows[3], front, false);
      engine('war_wagon', 'goblin_rabble', at(1.6), rows[3], front, false);
      engine('war_wagon', 'goblin_rabble', at(2.9), rows[3], front, true, true, 1);
    }
    await scene(Z === 1 ? 'squad-scale.png' : 'squad-scale-2x.png', W, H, items);
  }
}

// 5. Portraits as the HUD shows them.
if (want('portraits')) {
  const types = ['battle_mage', 'goblin_shaman', ...ENGINES, 'footman', 'goblin_horn'];
  const items = [];
  types.forEach((t, i) => {
    const px = 20 + i * 180;
    items.push({ rect: '#2a2420', x: px, y: 40, w: 160, h: 160 });
    items.push({ key: `portrait_${t}`, v: 0, x: px + 80, y: 200, scale: 1, shadow: false });
    items.push(label(t, px, 228, 13));
    items.push({ rect: '#2a2420', x: px, y: 250, w: 160, h: 160 });
    items.push({ key: `portrait_${t}`, v: 1, x: px + 80, y: 410, scale: 1, shadow: false });
  });
  await scene('portraits.png', 20 + types.length * 180, 430, items, '#4a4038');
}

// 6. Sizes: sprite canvas, anchor and on-screen extent at the 0.52 member scale.
if (only[0] === 'measure') {
  const res = await page.evaluate(({ ENGINES, FIGS }) => {
    const A = window.__art;
    const out = [];
    for (const t of [...ENGINES, ...FIGS, 'footman', 'goblin_rabble']) {
      for (const p of ['idle_f', 'atk_f', 'idle_b', 'atk_b', 'dead']) {
        const s = A.proceduralSprite(`${t}_${p}`, 0);
        const k = s.scale * 0.52;
        const f = (n) => (n * k).toFixed(0);
        out.push(`${t}_${p}: ${s.w}x${s.h} anchor (${s.ax.toFixed(0)},${s.ay.toFixed(0)}) scale ${s.scale.toFixed(4)} | at 0.52: ${f(s.w)}x${f(s.h)} px; left ${f(s.ax)} right ${f(s.w - s.ax)} up ${f(s.ay)} down ${f(s.h - s.ay)}`);
      }
      out.push(`  ${t}: ${A.variantCount(`${t}_idle_f`)} looks`);
    }
    return out;
  }, { ENGINES, FIGS });
  console.log(res.join('\n'));
}

console.log('errors', errors.length, errors.join(' | '));
await browser.close();
