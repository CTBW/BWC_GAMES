// Procedural placeholder art in the project's palette. Generated sprites
// replace these key by key; small ground decals remain procedural.

import { Rng } from '../core/rng';
import type { Sprite } from './assets';
import { drawEngine, engineLooks } from './engines';
import { drawFigure, type Pose } from './figures';

/** World-pixel height of a standing figure by unit type. */
const FIGURE_SCALE: Record<string, number> = {
  footman: 0.76,
  spearman: 0.76,
  crossbowman: 0.76,
  goblin_spear: 0.76,
  goblin_archer: 0.76,
  orc_warrior: 0.76,
  orc_warlord: 0.76,
  orc_brute: 0.76,
  troll: 0.76,
  collie_guard: 0.76,
  goblin_rabble: 0.76,
  goblin_horn: 0.76,
  wolf_rider: 0.76,
  margrave_rider: 0.76,
  militia: 0.76,
  battle_mage: 0.76,
  goblin_shaman: 0.76,
  engineer: 0.76,
  ballista: 0.76,
  mangonel: 0.76,
  rock_lobber: 0.76,
  war_wagon: 0.76,
};

/**
 * Where the portrait centres on the front idle figure (head position in figure
 * units) and how far it zooms. The troll's head hangs low and forward.
 */
function portraitFrame(type: string): { hx: number; hy: number; k: number } {
  if (type === 'troll') return { hx: -50, hy: -160, k: 1.75 };
  if (type === 'wolf_rider') return { hx: -30, hy: -98, k: 1.2 };
  if (type === 'goblin_rabble') return { hx: 0, hy: -(100 * 0.74 + 21) + 12, k: 2.25 };
  if (type === 'orc_brute') return { hx: -2, hy: -(100 * 1.2 + 21) - 6, k: 1.7 };
  if (type === 'collie_guard') return { hx: -6, hy: -121, k: 2.1 };
  // The shaman's antlers and feathers stand tall over his head.
  if (type === 'goblin_shaman') return { hx: 0, hy: -99, k: 1.85 };
  const h = type === 'orc_warlord' ? 1.3 : type === 'orc_warrior' ? 1.12 : type.startsWith('goblin') ? 0.8 : 1;
  const k = type === 'orc_warlord' ? 1.75 : type === 'orc_warrior' ? 1.95 : 2.25;
  return { hx: 0, hy: -(100 * h + 21) + (type.startsWith('goblin') ? 12 : 0), k };
}

/** Head-and-shoulders portrait: the front idle figure, enlarged around the head. */
function portraitSprite(type: string, v: number): Sprite {
  const S = 160;
  const { c, x } = canvas(S, S);
  const { hx, hy, k } = portraitFrame(type);
  x.translate(S / 2 + 10 - hx * k, S * 0.42 - hy * k);
  x.scale(k, k);
  x.lineJoin = 'round';
  x.lineCap = 'round';
  drawFigure(x, type, 'idle_f', v);
  return sp(c, S / 2, S, 1);
}

function figureSprite(type: string, pose: Pose, v: number): Sprite {
  const K = 1.4;
  // The troll and its raised log, and the horsemen with their lances, need a larger canvas.
  const big = type === 'troll' || type === 'margrave_rider';
  const W = pose === 'dead' ? (big ? 560 : 460) : big ? 480 : 340;
  const H = big ? 460 : 380;
  const { c, x } = canvas(W, H);
  x.translate(W / 2, H - 26);
  x.scale(K, K);
  x.lineJoin = 'round';
  x.lineCap = 'round';
  drawFigure(x, type, pose, v);
  x.setTransform(1, 0, 0, 1, 0, 0);
  if (pose !== 'dead') lightFigure(c, W / 2, H - 26);
  return trimmed(c, W / 2, H - 26, (FIGURE_SCALE[type] ?? 0.76) / K * 1.4 * 0.62);
}

/**
 * A war engine (engines.ts) on the figure scale, so it stands at the right size
 * beside its crew: same units, lighting and trim, on a larger canvas. The
 * anchor is the engine's ground centre. Null for variants that are not drawn.
 */
function engineSprite(type: string, pose: Pose, v: number): Sprite | null {
  if (v >= engineLooks(type)) return null;
  const K = 1.4;
  const W = 680;
  const H = 560;
  const ax = W / 2;
  const ay = H - 160;
  const { c, x } = canvas(W, H);
  x.translate(ax, ay);
  x.scale(K, K);
  x.lineJoin = 'round';
  x.lineCap = 'round';
  if (!drawEngine(x, type, pose, v)) return null;
  x.setTransform(1, 0, 0, 1, 0, 0);
  // Light down to the nearest wheel rather than the anchor: the footprint reaches toward the camera.
  if (pose !== 'dead') lightFigure(c, ax, lowestRow(c), 0.2);
  return trimmed(c, ax, ay, (FIGURE_SCALE[type] ?? 0.76) / K * 1.4 * 0.62);
}

/** Portrait of an engine: the front idle sprite fitted to fill the frame. */
function enginePortrait(type: string, v: number): Sprite | null {
  const e = engineSprite(type, 'idle_f', v);
  if (!e) return null;
  const S = 160;
  const { c, x } = canvas(S, S);
  // Fit the engine, zooming in a little when it is compact so it fills the frame.
  const k = Math.min((S - 4) / e.w, (S - 4) / e.h) * (e.w > e.h * 1.5 ? 1 : 1.1);
  const w = e.w * k;
  const h = e.h * k;
  x.drawImage(e.img, (S - w) / 2, (S - h) / 2 + 6, w, h);
  return sp(c, S / 2, S, 1);
}

/** The lowest canvas row with an opaque pixel. */
function lowestRow(c: HTMLCanvasElement): number {
  const d = c.getContext('2d')!.getImageData(0, 0, c.width, c.height).data;
  for (let yy = c.height - 1; yy >= 0; yy--) {
    for (let xx = 0; xx < c.width; xx += 2) if (d[(yy * c.width + xx) * 4 + 3] > 40) return yy;
  }
  return c.height - 1;
}

/**
 * Crop a sprite canvas to its opaque pixels (plus a margin), keeping the
 * anchor in place: squads of many soldiers in many poses add up, and most of
 * a figure canvas is empty.
 */
function trimmed(c: HTMLCanvasElement, ax: number, ay: number, scale: number): Sprite {
  const x = c.getContext('2d')!;
  const { width: w, height: h } = c;
  const d = x.getImageData(0, 0, w, h).data;
  let x0 = w;
  let y0 = h;
  let x1 = -1;
  let y1 = -1;
  for (let yy = 0; yy < h; yy++) {
    for (let xx = 0; xx < w; xx++) {
      if (d[(yy * w + xx) * 4 + 3] > 8) {
        if (xx < x0) x0 = xx;
        if (xx > x1) x1 = xx;
        if (yy < y0) y0 = yy;
        if (yy > y1) y1 = yy;
      }
    }
  }
  if (x1 < 0) return sp(c, ax, ay, scale);
  const m = 4;
  x0 = Math.max(0, x0 - m);
  y0 = Math.max(0, y0 - m);
  x1 = Math.min(w - 1, x1 + m);
  y1 = Math.min(h - 1, y1 + m);
  const out = document.createElement('canvas');
  out.width = x1 - x0 + 1;
  out.height = y1 - y0 + 1;
  out.getContext('2d')!.drawImage(c, -x0, -y0);
  return sp(out, ax - x0, ay - y0, scale);
}

/**
 * Light the flat figure like the 3D props: warm key light from the upper left,
 * a thin rim on the lit edge, and shade gathering toward the feet.
 */
function lightFigure(c: HTMLCanvasElement, fx: number, fy: number, aoStrength = 0.32) {
  const x = c.getContext('2d')!;
  const w = c.width;
  const h = c.height;
  // Find the figure's vertical extent for the gradients.
  const data = x.getImageData(0, 0, w, h).data;
  let top = h;
  for (let yy = 0; yy < h && top === h; yy++) {
    for (let xx = 0; xx < w; xx += 2) {
      if (data[(yy * w + xx) * 4 + 3] > 40) {
        top = yy;
        break;
      }
    }
  }
  const tall = Math.max(40, fy - top);
  x.save();
  x.globalCompositeOperation = 'source-atop';
  // Key light: lighter upper left, cooler lower right.
  const g = x.createLinearGradient(fx - tall * 0.45, top, fx + tall * 0.45, fy);
  g.addColorStop(0, 'rgba(255,236,190,0.16)');
  g.addColorStop(0.5, 'rgba(255,236,190,0)');
  g.addColorStop(1, 'rgba(30,45,80,0.2)');
  x.fillStyle = g;
  x.fillRect(0, 0, w, h);
  // Ground occlusion toward the feet.
  const ao = x.createLinearGradient(0, fy - tall * 0.28, 0, fy);
  ao.addColorStop(0, 'rgba(20,24,10,0)');
  ao.addColorStop(1, `rgba(20,24,10,${aoStrength})`);
  x.fillStyle = ao;
  x.fillRect(0, 0, w, h);
  x.restore();
  // Rim light on the upper-left edge: the silhouette minus itself shifted toward the light.
  const rim = document.createElement('canvas');
  rim.width = w;
  rim.height = h;
  const r = rim.getContext('2d')!;
  r.drawImage(c, 0, 0);
  r.globalCompositeOperation = 'source-in';
  r.fillStyle = 'rgba(255,240,200,1)';
  r.fillRect(0, 0, w, h);
  r.globalCompositeOperation = 'destination-out';
  r.drawImage(c, 2.5, 2.5);
  x.save();
  x.globalCompositeOperation = 'source-atop';
  x.globalAlpha = 0.5;
  x.drawImage(rim, 0, 0);
  x.restore();
}

const OUT = '#2a1d14';

function canvas(w: number, h: number) {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  return { c, x: c.getContext('2d')! };
}

function sp(c: HTMLCanvasElement, ax: number, ay: number, scale = 1): Sprite {
  return { img: c, ax, ay, scale, w: c.width, h: c.height };
}

function blob(x: CanvasRenderingContext2D, cx: number, cy: number, r: number, rng: Rng, jag = 0.18, n = 14) {
  x.beginPath();
  for (let i = 0; i <= n; i++) {
    const a = (i / n) * Math.PI * 2;
    const rr = r * (1 - jag / 2 + rng.next() * jag);
    const px = cx + Math.cos(a) * rr;
    const py = cy + Math.sin(a) * rr * 0.92;
    if (i === 0) x.moveTo(px, py);
    else x.lineTo(px, py);
  }
  x.closePath();
}

function pine(v: number): Sprite {
  const rng = new Rng(100 + v);
  const H = 190 + v * 14;
  const { c, x } = canvas(130, H + 20);
  const cx = 65;
  // trunk
  x.fillStyle = '#5a3a22';
  x.fillRect(cx - 5, H - 34, 10, 30);
  const tiers = 5;
  for (let i = 0; i < tiers; i++) {
    const t = i / (tiers - 1);
    const top = 8 + t * (H - 70);
    const w = 22 + t * 40;
    const bottom = top + 52 + t * 8;
    x.beginPath();
    x.moveTo(cx, top);
    const steps = 6;
    for (let s = 0; s <= steps; s++) {
      const f = s / steps;
      x.lineTo(cx + w * f + rng.range(-3, 3), top + (bottom - top) * f + (s % 2 ? -5 : 0));
    }
    for (let s = steps; s >= 0; s--) {
      const f = s / steps;
      x.lineTo(cx - w * f + rng.range(-3, 3), top + (bottom - top) * f + (s % 2 ? -5 : 0));
    }
    x.closePath();
    const g = x.createLinearGradient(cx - w, 0, cx + w, 0);
    g.addColorStop(0, '#3f7a3c');
    g.addColorStop(0.45, '#2c5e33');
    g.addColorStop(1, '#173b26');
    x.fillStyle = g;
    x.fill();
    x.strokeStyle = 'rgba(20,35,20,0.9)';
    x.lineWidth = 2;
    x.stroke();
    // needle highlights
    x.strokeStyle = 'rgba(160,200,110,0.35)';
    x.lineWidth = 1.5;
    for (let k = 0; k < 6; k++) {
      const yy = top + 14 + rng.next() * (bottom - top - 18);
      const xx = cx - w * 0.6 + rng.next() * w * 0.6;
      x.beginPath();
      x.moveTo(xx, yy);
      x.lineTo(xx + 6, yy + 3);
      x.stroke();
    }
  }
  return sp(c, cx, H - 6, 0.82);
}

function oak(v: number): Sprite {
  const rng = new Rng(200 + v);
  const { c, x } = canvas(170, 190);
  const cx = 85;
  x.fillStyle = '#5b3b22';
  x.beginPath();
  x.moveTo(cx - 8, 182);
  x.lineTo(cx - 5, 110);
  x.lineTo(cx + 6, 110);
  x.lineTo(cx + 10, 182);
  x.closePath();
  x.fill();
  const blobs: [number, number, number][] = [];
  for (let i = 0; i < 9; i++) blobs.push([cx + rng.range(-46, 46), 70 + rng.range(-40, 32), rng.range(26, 40)]);
  blobs.sort((a, b) => a[1] - b[1]);
  for (const [bx, by, r] of blobs) {
    blob(x, bx, by, r + 2, rng);
    x.fillStyle = 'rgba(25,40,18,0.9)';
    x.fill();
  }
  for (const [bx, by, r] of blobs) {
    blob(x, bx, by, r, rng);
    const g = x.createRadialGradient(bx - r * 0.45, by - r * 0.5, r * 0.1, bx, by, r * 1.1);
    g.addColorStop(0, '#9cc25a');
    g.addColorStop(0.45, '#5f9a3a');
    g.addColorStop(1, '#2e5a26');
    x.fillStyle = g;
    x.fill();
  }
  return sp(c, cx, 180, 0.8);
}

function bush(v: number): Sprite {
  const rng = new Rng(300 + v);
  const { c, x } = canvas(110, 80);
  for (let i = 0; i < 6; i++) {
    const bx = 55 + rng.range(-28, 28);
    const by = 46 + rng.range(-12, 10);
    const r = rng.range(16, 24);
    blob(x, bx, by, r, rng, 0.3);
    const g = x.createRadialGradient(bx - r * 0.4, by - r * 0.5, 2, bx, by, r);
    g.addColorStop(0, '#a5c862');
    g.addColorStop(0.6, '#4f8a34');
    g.addColorStop(1, '#2b5223');
    x.fillStyle = g;
    x.fill();
    x.strokeStyle = 'rgba(25,40,18,0.7)';
    x.stroke();
  }
  if (v % 2 === 0) {
    for (let i = 0; i < 5; i++) {
      x.fillStyle = rng.pick(['#e8d06a', '#b78bd8', '#f2efe2']);
      x.beginPath();
      x.arc(30 + rng.next() * 50, 30 + rng.next() * 30, 2.2, 0, 7);
      x.fill();
    }
  }
  return sp(c, 55, 70, 0.8);
}

function rock(v: number, big: boolean): Sprite {
  const rng = new Rng(400 + v + (big ? 50 : 0));
  const W = big ? 150 : 90;
  const H = big ? 120 : 64;
  const { c, x } = canvas(W, H);
  const n = big ? 4 : 2;
  for (let i = 0; i < n; i++) {
    const bx = W / 2 + rng.range(-W * 0.22, W * 0.22);
    const by = H * 0.62 + rng.range(-H * 0.12, H * 0.1);
    const r = (big ? 34 : 20) * rng.range(0.75, 1.15);
    x.beginPath();
    const k = 7;
    const pts: [number, number][] = [];
    for (let j = 0; j < k; j++) {
      const a = (j / k) * Math.PI * 2 + rng.next() * 0.4;
      pts.push([bx + Math.cos(a) * r * rng.range(0.8, 1.1), by + Math.sin(a) * r * 0.75 * rng.range(0.8, 1.1)]);
    }
    pts.forEach((p, j) => (j ? x.lineTo(p[0], p[1]) : x.moveTo(p[0], p[1])));
    x.closePath();
    const g = x.createLinearGradient(bx - r, by - r, bx + r, by + r);
    g.addColorStop(0, '#d4d1c2');
    g.addColorStop(0.5, '#9d9b8c');
    g.addColorStop(1, '#5d5c55');
    x.fillStyle = g;
    x.fill();
    x.strokeStyle = OUT;
    x.lineWidth = 2;
    x.stroke();
    // moss
    x.fillStyle = 'rgba(110,150,60,0.75)';
    blob(x, bx - r * 0.2, by - r * 0.45, r * 0.35, rng, 0.5, 9);
    x.fill();
  }
  return sp(c, W / 2, H * 0.82, 0.85);
}

function stump(): Sprite {
  const { c, x } = canvas(70, 60);
  x.fillStyle = '#6b4a2c';
  x.fillRect(20, 20, 30, 28);
  x.fillStyle = '#c7a06a';
  x.beginPath();
  x.ellipse(35, 20, 15, 7, 0, 0, 7);
  x.fill();
  x.strokeStyle = OUT;
  x.lineWidth = 2;
  x.stroke();
  return sp(c, 35, 50, 0.8);
}

function fence(v: number): Sprite {
  const { c, x } = canvas(130, 80);
  x.strokeStyle = OUT;
  x.lineWidth = 2;
  for (const px of [18, 64, 110]) {
    x.fillStyle = '#7a5532';
    x.fillRect(px - 4, 18 + (v ? 2 : 0), 8, 50);
    x.strokeRect(px - 4, 18, 8, 50);
  }
  x.fillStyle = '#9a7040';
  x.save();
  x.translate(0, 0);
  x.beginPath();
  x.moveTo(10, 32);
  x.lineTo(120, 26);
  x.lineTo(120, 34);
  x.lineTo(10, 40);
  x.closePath();
  x.fill();
  x.stroke();
  x.beginPath();
  x.moveTo(10, 50);
  x.lineTo(120, 44);
  x.lineTo(120, 52);
  x.lineTo(10, 58);
  x.closePath();
  x.fill();
  x.stroke();
  x.restore();
  return sp(c, 65, 66, 0.8);
}

function wall(v: number, high: boolean): Sprite {
  const rng = new Rng(500 + v + (high ? 9 : 0));
  const H = high ? 170 : 90;
  const { c, x } = canvas(130, H);
  const rows = high ? 9 : 4;
  for (let r = 0; r < rows; r++) {
    const y = H - 12 - (r + 1) * 16;
    const len = high ? 60 - (r > 6 ? rng.int(0, 30) : 0) : 110 - r * rng.int(5, 18);
    const x0 = high ? 35 : 10 + rng.int(0, 10);
    for (let bx = x0; bx < x0 + len; bx += 26) {
      const w = Math.min(24, x0 + len - bx);
      const g = x.createLinearGradient(bx, y, bx, y + 15);
      g.addColorStop(0, '#c9c4b2');
      g.addColorStop(1, '#8a8678');
      x.fillStyle = g;
      x.fillRect(bx + (r % 2) * 8, y, w, 15);
      x.strokeStyle = OUT;
      x.lineWidth = 1.5;
      x.strokeRect(bx + (r % 2) * 8, y, w, 15);
    }
  }
  x.fillStyle = 'rgba(110,150,60,0.7)';
  for (let i = 0; i < 4; i++) {
    blob(x, 20 + rng.next() * 90, H - 20 - rng.next() * (H - 40), 7, rng, 0.6, 8);
    x.fill();
  }
  return sp(c, 65, H - 10, 0.85);
}

function crates(): Sprite {
  const { c, x } = canvas(110, 90);
  const box = (bx: number, by: number, s: number) => {
    x.fillStyle = '#a07443';
    x.fillRect(bx, by, s, s);
    x.strokeStyle = OUT;
    x.lineWidth = 2;
    x.strokeRect(bx, by, s, s);
    x.beginPath();
    x.moveTo(bx, by);
    x.lineTo(bx + s, by + s);
    x.stroke();
  };
  box(18, 40, 38);
  box(54, 46, 32);
  box(32, 10, 32);
  return sp(c, 55, 84, 0.8);
}

function tent(v: number): Sprite {
  const { c, x } = canvas(160, 130);
  const red = v % 2 === 0;
  x.fillStyle = red ? '#8e2f22' : '#6b5a44';
  x.beginPath();
  x.moveTo(80, 12);
  x.lineTo(150, 110);
  x.lineTo(10, 110);
  x.closePath();
  x.fill();
  x.strokeStyle = OUT;
  x.lineWidth = 3;
  x.stroke();
  x.fillStyle = 'rgba(0,0,0,0.35)';
  x.beginPath();
  x.moveTo(80, 12);
  x.lineTo(150, 110);
  x.lineTo(92, 110);
  x.closePath();
  x.fill();
  x.fillStyle = '#2a1b12';
  x.beginPath();
  x.moveTo(80, 52);
  x.lineTo(96, 110);
  x.lineTo(64, 110);
  x.closePath();
  x.fill();
  x.strokeStyle = '#5b3b22';
  x.lineWidth = 4;
  x.beginPath();
  x.moveTo(80, 12);
  x.lineTo(80, 0);
  x.stroke();
  return sp(c, 80, 112, 0.8);
}

function totem(): Sprite {
  const { c, x } = canvas(60, 160);
  x.fillStyle = '#5b3b22';
  x.fillRect(26, 30, 8, 125);
  x.fillStyle = '#e9e1c8';
  x.beginPath();
  x.ellipse(30, 30, 14, 12, 0, 0, 7);
  x.fill();
  x.strokeStyle = OUT;
  x.lineWidth = 2;
  x.stroke();
  x.fillStyle = '#20140d';
  x.fillRect(23, 27, 5, 5);
  x.fillRect(33, 27, 5, 5);
  x.fillStyle = '#a3261c';
  x.beginPath();
  x.moveTo(34, 50);
  x.lineTo(58, 60);
  x.lineTo(34, 92);
  x.closePath();
  x.fill();
  return sp(c, 30, 155, 0.8);
}

function campfire(): Sprite {
  const { c, x } = canvas(80, 60);
  x.fillStyle = '#6d6a60';
  for (let i = 0; i < 8; i++) {
    const a = (i / 8) * Math.PI * 2;
    x.beginPath();
    x.ellipse(40 + Math.cos(a) * 22, 40 + Math.sin(a) * 9, 6, 4, 0, 0, 7);
    x.fill();
  }
  x.strokeStyle = '#5b3b22';
  x.lineWidth = 5;
  x.beginPath();
  x.moveTo(28, 44);
  x.lineTo(52, 34);
  x.moveTo(28, 34);
  x.lineTo(52, 44);
  x.stroke();
  return sp(c, 40, 46, 0.8);
}

function decal(kind: string, v: number): Sprite {
  const rng = new Rng(900 + v * 7 + kind.length);
  const { c, x } = canvas(40, 30);
  if (kind === 'tuft') {
    for (let i = 0; i < 9; i++) {
      x.strokeStyle = rng.pick(['#6c9a32', '#88b046', '#4e7a28', '#a7c45a']);
      x.lineWidth = 1.6;
      x.beginPath();
      const bx = 12 + rng.next() * 16;
      x.moveTo(bx, 26);
      x.quadraticCurveTo(bx + rng.range(-4, 4), 18, bx + rng.range(-7, 7), 8 + rng.next() * 8);
      x.stroke();
    }
  } else if (kind === 'flower') {
    for (let i = 0; i < 5; i++) {
      const fx = 8 + rng.next() * 24;
      const fy = 10 + rng.next() * 14;
      x.strokeStyle = '#5a8a2c';
      x.beginPath();
      x.moveTo(fx, fy);
      x.lineTo(fx, fy + 6);
      x.stroke();
      x.fillStyle = rng.pick(['#f4f1e4', '#f2d455', '#b88be0', '#e9a0c0']);
      x.beginPath();
      x.arc(fx, fy, 2.4, 0, 7);
      x.fill();
    }
  } else {
    for (let i = 0; i < 3; i++) {
      x.fillStyle = rng.pick(['#a9a597', '#8d897b', '#c2bfb0']);
      x.beginPath();
      x.ellipse(10 + rng.next() * 20, 18 + rng.next() * 6, 3 + rng.next() * 3, 2 + rng.next() * 2, 0, 0, 7);
      x.fill();
    }
  }
  return sp(c, 20, 26, 0.9);
}


function building(id: string, lvl: number): Sprite {
  const rng = new Rng(id.length * 31 + lvl);
  const W = 300;
  const H = 260;
  const { c, x } = canvas(W, H);
  const cx = W / 2;
  const base = H - 30;
  const w = 90 + lvl * 14;
  const d = 60 + lvl * 8;
  const wallH = 50 + lvl * 16;
  const roof = id === 'command' ? '#2f58b8' : id === 'infirmary' ? '#e6dfcc' : id === 'barracks' ? '#8e2f22' : id === 'quartermaster' ? '#a07443' : '#5b6b7a';
  // iso box: left face, right face, roof
  const L = { x: cx - w, y: base - d * 0.5 };
  const R = { x: cx + d, y: base - w * 0.5 };
  x.lineWidth = 3;
  x.strokeStyle = OUT;
  if (lvl === 1) {
    camp1(x, id, cx, base);
    return sp(c, cx, base, 0.9);
  }
  const wallColor = lvl >= 3 ? '#cfc8b4' : '#9a7044';
  x.fillStyle = wallColor;
  x.beginPath();
  x.moveTo(L.x, L.y);
  x.lineTo(cx, base);
  x.lineTo(cx, base - wallH);
  x.lineTo(L.x, L.y - wallH);
  x.closePath();
  x.fill();
  x.stroke();
  x.fillStyle = lvl >= 3 ? '#a8a290' : '#7a5532';
  x.beginPath();
  x.moveTo(cx, base);
  x.lineTo(R.x, R.y);
  x.lineTo(R.x, R.y - wallH);
  x.lineTo(cx, base - wallH);
  x.closePath();
  x.fill();
  x.stroke();
  // planks / stones
  x.strokeStyle = 'rgba(40,25,15,0.35)';
  x.lineWidth = 1.5;
  for (let i = 1; i < 6; i++) {
    const yy = (wallH / 6) * i;
    x.beginPath();
    x.moveTo(L.x, L.y - yy);
    x.lineTo(cx, base - yy);
    x.lineTo(R.x, R.y - yy);
    x.stroke();
  }
  // door + window
  x.fillStyle = '#3a2618';
  x.beginPath();
  x.moveTo(cx - w * 0.45, base - d * 0.5 + w * 0.22 - 2);
  x.lineTo(cx - w * 0.25, base - d * 0.5 + w * 0.33 - 2);
  x.lineTo(cx - w * 0.25, base - d * 0.5 + w * 0.33 - 38);
  x.lineTo(cx - w * 0.45, base - d * 0.5 + w * 0.22 - 38);
  x.closePath();
  x.fill();
  // roof
  const peakH = 46 + lvl * 8;
  const T1 = { x: L.x - 8, y: L.y - wallH + 4 };
  const T2 = { x: cx, y: base - wallH + 10 };
  const T3 = { x: R.x + 8, y: R.y - wallH + 4 };
  const ridgeA = { x: (L.x + cx) / 2 + (d - 0) * 0.5 - d * 0.5, y: 0 };
  void ridgeA;
  const back = { x: cx + d - w, y: base - (w + d) * 0.5 - wallH };
  x.fillStyle = roof;
  x.strokeStyle = OUT;
  x.lineWidth = 3;
  const ridge1 = { x: (T1.x + back.x) / 2 + 4, y: (T1.y + back.y) / 2 - peakH };
  const ridge2 = { x: (T2.x + T3.x) / 2 + 4, y: (T2.y + T3.y) / 2 - peakH };
  x.beginPath();
  x.moveTo(T1.x, T1.y);
  x.lineTo(T2.x, T2.y);
  x.lineTo(ridge2.x, ridge2.y);
  x.lineTo(ridge1.x, ridge1.y);
  x.closePath();
  x.fill();
  x.stroke();
  x.fillStyle = shade(roof, -0.25);
  x.beginPath();
  x.moveTo(T2.x, T2.y);
  x.lineTo(T3.x, T3.y);
  x.lineTo(ridge2.x, ridge2.y);
  x.closePath();
  x.fill();
  x.stroke();
  if (lvl >= 3) {
    x.fillStyle = '#2f58b8';
    x.fillRect(ridge1.x - 2, ridge1.y - 40, 4, 40);
    x.beginPath();
    x.moveTo(ridge1.x + 2, ridge1.y - 40);
    x.lineTo(ridge1.x + 34, ridge1.y - 32);
    x.lineTo(ridge1.x + 2, ridge1.y - 22);
    x.fill();
  }
  void rng;
  return sp(c, cx, base, 0.9);
}

// ---------------------------------------------------------------- level-1 camp structures

function ridgeTent(x: CanvasRenderingContext2D, px: number, py: number, len: number, wid: number, hgt: number, cloth: string, stripe?: string) {
  // Ridge runs along the screen's up-right axis; the gable faces down-left.
  const ax = 0.87;
  const ay = 0.5;
  const back = { x: px + len * ax, y: py - len * ay };
  const gl = { x: px - wid * 0.5, y: py - wid * 0.25 };
  const gr = { x: px + wid * 0.5, y: py + wid * 0.25 };
  const top = { x: px, y: py - hgt };
  const topB = { x: back.x, y: back.y - hgt };
  const grB = { x: gr.x + len * ax, y: gr.y - len * ay };
  x.lineWidth = 2.5;
  x.strokeStyle = OUT;
  x.fillStyle = shade(cloth, -0.22);
  x.beginPath();
  x.moveTo(top.x, top.y);
  x.lineTo(topB.x, topB.y);
  x.lineTo(grB.x, grB.y);
  x.lineTo(gr.x, gr.y);
  x.closePath();
  x.fill();
  x.stroke();
  if (stripe) {
    x.strokeStyle = stripe;
    x.lineWidth = 5;
    for (let i = 1; i < 4; i++) {
      const f = i / 4;
      x.beginPath();
      x.moveTo(top.x + (topB.x - top.x) * f, top.y + (topB.y - top.y) * f);
      x.lineTo(gr.x + (grB.x - gr.x) * f, gr.y + (grB.y - gr.y) * f);
      x.stroke();
    }
    x.strokeStyle = OUT;
    x.lineWidth = 2.5;
  }
  x.fillStyle = cloth;
  x.beginPath();
  x.moveTo(gl.x, gl.y);
  x.lineTo(top.x, top.y);
  x.lineTo(gr.x, gr.y);
  x.closePath();
  x.fill();
  x.stroke();
  x.fillStyle = 'rgba(40,25,15,0.75)';
  x.beginPath();
  x.moveTo(px - wid * 0.12, py - wid * 0.06);
  x.lineTo(px, py - hgt * 0.55);
  x.lineTo(px + wid * 0.12, py + wid * 0.06);
  x.closePath();
  x.fill();
  x.strokeStyle = '#4a2f1c';
  x.lineWidth = 3;
  x.beginPath();
  x.moveTo(top.x, top.y);
  x.lineTo(top.x, top.y - 10);
  x.moveTo(topB.x, topB.y);
  x.lineTo(topB.x, topB.y - 10);
  x.stroke();
}

function flagPole(x: CanvasRenderingContext2D, px: number, py: number, h: number, color: string, eagle = false) {
  x.strokeStyle = '#4a2f1c';
  x.lineWidth = 3;
  x.beginPath();
  x.moveTo(px, py);
  x.lineTo(px, py - h);
  x.stroke();
  x.fillStyle = color;
  x.strokeStyle = OUT;
  x.lineWidth = 1.5;
  x.beginPath();
  x.moveTo(px + 1, py - h + 2);
  x.lineTo(px + 30, py - h + 6);
  x.lineTo(px + 26, py - h + 22);
  x.lineTo(px + 1, py - h + 26);
  x.closePath();
  x.fill();
  x.stroke();
  if (eagle) {
    x.fillStyle = '#f2efe4';
    x.beginPath();
    x.moveTo(px + 14, py - h + 8);
    x.lineTo(px + 19, py - h + 14);
    x.lineTo(px + 14, py - h + 20);
    x.lineTo(px + 9, py - h + 14);
    x.closePath();
    x.fill();
  }
}

function crate(x: CanvasRenderingContext2D, px: number, py: number, s: number) {
  x.lineWidth = 1.8;
  x.strokeStyle = OUT;
  x.fillStyle = '#a07443';
  x.beginPath();
  x.moveTo(px - s, py - s * 0.5);
  x.lineTo(px, py);
  x.lineTo(px, py - s);
  x.lineTo(px - s, py - s * 1.5);
  x.closePath();
  x.fill();
  x.stroke();
  x.fillStyle = '#7d5631';
  x.beginPath();
  x.moveTo(px, py);
  x.lineTo(px + s, py - s * 0.5);
  x.lineTo(px + s, py - s * 1.5);
  x.lineTo(px, py - s);
  x.closePath();
  x.fill();
  x.stroke();
  x.fillStyle = '#c4945a';
  x.beginPath();
  x.moveTo(px - s, py - s * 1.5);
  x.lineTo(px, py - s);
  x.lineTo(px + s, py - s * 1.5);
  x.lineTo(px, py - s * 2);
  x.closePath();
  x.fill();
  x.stroke();
}

function barrel(x: CanvasRenderingContext2D, px: number, py: number, r: number) {
  x.lineWidth = 1.8;
  x.strokeStyle = OUT;
  x.fillStyle = '#8a5a30';
  x.beginPath();
  x.moveTo(px - r, py - r * 2.2);
  x.lineTo(px - r, py);
  x.ellipse(px, py, r, r * 0.45, 0, Math.PI, 0, true);
  x.lineTo(px + r, py - r * 2.2);
  x.closePath();
  x.fill();
  x.stroke();
  x.fillStyle = '#b07c48';
  x.beginPath();
  x.ellipse(px, py - r * 2.2, r, r * 0.45, 0, 0, Math.PI * 2);
  x.fill();
  x.stroke();
  x.strokeStyle = '#3a2a1a';
  x.beginPath();
  x.ellipse(px, py - r * 0.8, r, r * 0.45, 0, 0, Math.PI);
  x.stroke();
}

function dummy(x: CanvasRenderingContext2D, px: number, py: number) {
  x.strokeStyle = '#5a3a22';
  x.lineWidth = 4;
  x.beginPath();
  x.moveTo(px, py);
  x.lineTo(px, py - 70);
  x.moveTo(px - 22, py - 50);
  x.lineTo(px + 22, py - 50);
  x.stroke();
  x.fillStyle = '#d8bf72';
  x.strokeStyle = OUT;
  x.lineWidth = 2;
  x.beginPath();
  x.ellipse(px, py - 42, 12, 20, 0, 0, Math.PI * 2);
  x.fill();
  x.stroke();
  x.beginPath();
  x.arc(px, py - 72, 9, 0, Math.PI * 2);
  x.fill();
  x.stroke();
  x.strokeStyle = '#a3261c';
  x.lineWidth = 2;
  x.beginPath();
  x.arc(px, py - 42, 5, 0, Math.PI * 2);
  x.stroke();
}

function camp1(x: CanvasRenderingContext2D, id: string, cx: number, base: number) {
  if (id === 'command') {
    ridgeTent(x, cx - 30, base - 6, 92, 120, 118, '#ece0c2', '#2f58b8');
    flagPole(x, cx - 112, base - 30, 150, '#2f58b8', true);
    flagPole(x, cx + 96, base - 50, 140, '#2f58b8', true);
    crate(x, cx + 70, base + 4, 14);
  } else if (id === 'barracks') {
    ridgeTent(x, cx - 10, base - 76, 54, 70, 66, '#d6c8a6');
    ridgeTent(x, cx - 70, base - 30, 54, 70, 66, '#d6c8a6');
    ridgeTent(x, cx + 10, base - 6, 54, 70, 66, '#cdbf9c');
    flagPole(x, cx + 90, base - 30, 110, '#8e2f22');
  } else if (id === 'training') {
    x.strokeStyle = '#5a3a22';
    x.lineWidth = 4;
    x.beginPath();
    x.moveTo(cx - 110, base - 60);
    x.lineTo(cx - 110, base - 110);
    x.moveTo(cx - 60, base - 85);
    x.lineTo(cx - 60, base - 135);
    x.moveTo(cx - 112, base - 100);
    x.lineTo(cx - 58, base - 126);
    x.stroke();
    x.strokeStyle = '#c9ced2';
    x.lineWidth = 3;
    for (let i = 0; i < 4; i++) {
      x.beginPath();
      x.moveTo(cx - 104 + i * 12, base - 64 - i * 6);
      x.lineTo(cx - 98 + i * 12, base - 136 - i * 6);
      x.stroke();
    }
    x.fillStyle = '#d8bf72';
    x.strokeStyle = OUT;
    x.lineWidth = 2;
    x.beginPath();
    x.ellipse(cx + 100, base - 80, 24, 28, -0.3, 0, Math.PI * 2);
    x.fill();
    x.stroke();
    const rings: [number, string][] = [
      [18, '#f2efe4'],
      [12, '#2f58b8'],
      [6, '#a3261c'],
    ];
    for (const [r, col] of rings) {
      x.fillStyle = col;
      x.beginPath();
      x.ellipse(cx + 100, base - 80, r * 0.85, r, -0.3, 0, Math.PI * 2);
      x.fill();
    }
    dummy(x, cx + 10, base - 40);
    dummy(x, cx - 60, base - 10);
    dummy(x, cx + 70, base - 4);
  } else if (id === 'armoury') {
    x.strokeStyle = OUT;
    x.lineWidth = 2.5;
    x.fillStyle = '#7d7a6e';
    x.fillRect(cx - 4, base - 150, 22, 82);
    x.strokeRect(cx - 4, base - 150, 22, 82);
    x.fillStyle = '#8d8a7c';
    x.fillRect(cx - 40, base - 70, 60, 50);
    x.strokeRect(cx - 40, base - 70, 60, 50);
    x.fillStyle = '#ff9a3a';
    x.fillRect(cx - 28, base - 52, 26, 12);
    x.fillStyle = '#6b4426';
    x.beginPath();
    x.moveTo(cx - 90, base - 100);
    x.lineTo(cx + 70, base - 140);
    x.lineTo(cx + 96, base - 108);
    x.lineTo(cx - 64, base - 68);
    x.closePath();
    x.fill();
    x.stroke();
    x.strokeStyle = '#4a2f1c';
    x.lineWidth = 5;
    x.beginPath();
    x.moveTo(cx - 64, base - 68);
    x.lineTo(cx - 64, base);
    x.moveTo(cx + 96, base - 108);
    x.lineTo(cx + 96, base - 40);
    x.stroke();
    x.fillStyle = '#4b4f55';
    x.strokeStyle = OUT;
    x.lineWidth = 2;
    x.beginPath();
    x.moveTo(cx + 20, base - 6);
    x.lineTo(cx + 60, base - 22);
    x.lineTo(cx + 66, base - 34);
    x.lineTo(cx + 18, base - 18);
    x.closePath();
    x.fill();
    x.stroke();
    barrel(x, cx - 96, base - 14, 14);
  } else if (id === 'infirmary') {
    ridgeTent(x, cx - 26, base - 8, 84, 104, 96, '#f4efe2');
    x.strokeStyle = '#4a2f1c';
    x.lineWidth = 3;
    x.beginPath();
    x.moveTo(cx - 108, base - 20);
    x.lineTo(cx - 108, base - 112);
    x.stroke();
    x.fillStyle = '#f4efe2';
    x.strokeStyle = OUT;
    x.lineWidth = 2;
    x.fillRect(cx - 128, base - 128, 40, 30);
    x.strokeRect(cx - 128, base - 128, 40, 30);
    x.fillStyle = '#4f8a34';
    x.beginPath();
    x.ellipse(cx - 114, base - 113, 6, 10, -0.5, 0, Math.PI * 2);
    x.ellipse(cx - 102, base - 113, 6, 10, 0.5, 0, Math.PI * 2);
    x.fill();
    crate(x, cx + 70, base + 2, 12);
  } else {
    const wx = cx - 20;
    const wy = base - 20;
    x.fillStyle = '#7d5631';
    x.strokeStyle = OUT;
    x.lineWidth = 2.5;
    x.beginPath();
    x.moveTo(wx - 70, wy + 4);
    x.lineTo(wx + 40, wy - 50);
    x.lineTo(wx + 40, wy - 30);
    x.lineTo(wx - 70, wy + 24);
    x.closePath();
    x.fill();
    x.stroke();
    x.fillStyle = '#ece0c2';
    x.beginPath();
    x.moveTo(wx - 70, wy + 4);
    x.quadraticCurveTo(wx - 70, wy - 70, wx - 20, wy - 92);
    x.lineTo(wx + 90, wy - 146);
    x.quadraticCurveTo(wx + 40, wy - 120, wx + 40, wy - 50);
    x.closePath();
    x.fill();
    x.stroke();
    x.strokeStyle = 'rgba(120,90,50,0.6)';
    for (let i = 1; i < 4; i++) {
      x.beginPath();
      x.moveTo(wx - 70 + i * 27, wy + 4 - i * 13);
      x.quadraticCurveTo(wx - 70 + i * 27, wy - 70 - i * 13, wx - 20 + i * 27, wy - 92 - i * 13);
      x.stroke();
    }
    const wheels: [number, number][] = [
      [-58, 22],
      [28, -22],
    ];
    for (const [ox, oy] of wheels) {
      x.fillStyle = '#5a3a22';
      x.strokeStyle = OUT;
      x.lineWidth = 2;
      x.beginPath();
      x.ellipse(wx + ox, wy + oy, 13, 18, 0.4, 0, Math.PI * 2);
      x.fill();
      x.stroke();
    }
    barrel(x, cx - 104, base - 6, 13);
    barrel(x, cx - 84, base + 6, 13);
    crate(x, cx + 70, base - 4, 15);
    crate(x, cx + 96, base + 10, 12);
  }
}

function shade(hex: string, f: number) {
  const n = parseInt(hex.slice(1), 16);
  const r = Math.max(0, Math.min(255, ((n >> 16) & 255) * (1 + f)));
  const g = Math.max(0, Math.min(255, ((n >> 8) & 255) * (1 + f)));
  const b = Math.max(0, Math.min(255, (n & 255) * (1 + f)));
  return `rgb(${r | 0},${g | 0},${b | 0})`;
}

function nodeIcon(kind: string): Sprite {
  const { c, x } = canvas(120, 120);
  x.translate(60, 100);
  x.lineWidth = 3;
  x.strokeStyle = OUT;
  const flag = (color: string) => {
    x.fillStyle = '#5b3b22';
    x.fillRect(-3, -80, 6, 80);
    x.fillStyle = color;
    x.beginPath();
    x.moveTo(3, -78);
    x.lineTo(40, -66);
    x.lineTo(3, -50);
    x.closePath();
    x.fill();
    x.stroke();
  };
  if (kind === 'village') {
    for (const [dx, dy] of [[-22, -6], [18, 4]]) {
      x.fillStyle = '#9a7044';
      x.fillRect(dx - 16, dy - 24, 32, 24);
      x.strokeRect(dx - 16, dy - 24, 32, 24);
      x.fillStyle = '#6b4a2c';
      x.beginPath();
      x.moveTo(dx - 22, dy - 22);
      x.lineTo(dx, dy - 46);
      x.lineTo(dx + 22, dy - 22);
      x.closePath();
      x.fill();
      x.stroke();
    }
  } else if (kind === 'camp') {
    x.fillStyle = '#d9cfb3';
    x.beginPath();
    x.moveTo(-30, 0);
    x.lineTo(0, -46);
    x.lineTo(30, 0);
    x.closePath();
    x.fill();
    x.stroke();
    x.fillStyle = '#f3a43a';
    x.beginPath();
    x.arc(34, -4, 7, 0, 7);
    x.fill();
  } else if (kind === 'scout') {
    x.fillStyle = '#9a7044';
    x.fillRect(-12, -70, 24, 70);
    x.strokeRect(-12, -70, 24, 70);
    x.fillStyle = '#6b4a2c';
    x.fillRect(-20, -82, 40, 14);
    x.strokeRect(-20, -82, 40, 14);
  } else if (kind === 'objective') {
    flag('#a3261c');
    x.fillStyle = '#6b3a22';
    x.beginPath();
    x.moveTo(-40, 0);
    x.lineTo(-14, -40);
    x.lineTo(12, 0);
    x.closePath();
    x.fill();
    x.stroke();
  } else if (kind === 'battle' || kind === 'ambush') {
    flag(kind === 'battle' ? '#a3261c' : '#5a1f1a');
  } else if (kind === 'event') {
    x.fillStyle = '#7a5532';
    x.fillRect(-4, -56, 8, 56);
    x.fillStyle = '#c7a06a';
    x.fillRect(-26, -54, 52, 18);
    x.strokeRect(-26, -54, 52, 18);
  } else if (kind === 'start') {
    flag('#2f58b8');
  } else {
    x.fillStyle = '#ddd';
    x.font = 'bold 40px serif';
    x.fillText('?', -10, -20);
  }
  return sp(c, 60, 100, 0.8);
}

export function proceduralSprite(key: string, v: number): Sprite | null {
  if (key === 'tree_pine') return pine(v);
  if (key === 'tree_oak') return oak(v);
  if (key === 'bush') return bush(v);
  if (key === 'rock_large') return rock(v, true);
  if (key === 'rock_small') return rock(v, false);
  if (key === 'stump' || key === 'log') return v === 0 ? stump() : null;
  if (key === 'fence' || key === 'fence_x' || key === 'fence_y') return v < 2 ? fence(v) : null;
  if (key === 'wall_ruin' || key === 'wall_ruin_x' || key === 'wall_ruin_y') return wall(v, false);
  if (key === 'wall_high') return v < 2 ? wall(v, true) : null;
  if (key === 'crates') return v === 0 ? crates() : null;
  if (key === 'tent') return v < 2 ? tent(v) : null;
  if (key === 'totem') return v === 0 ? totem() : null;
  if (key === 'campfire') return v === 0 ? campfire() : null;
  if (key === 'tuft' || key === 'flower' || key === 'pebble') return decal(key, v);
  const um = key.match(/^(footman|spearman|crossbowman|collie_guard|goblin_spear|goblin_archer|orc_warrior|orc_brute|orc_warlord|troll|goblin_rabble|goblin_horn|wolf_rider|militia|margrave_rider|battle_mage|goblin_shaman|engineer)_(idle_fs|idle_bs|atk_fs|atk_bs|idle_f|idle_b|atk_f|atk_b|run_f|run_b|dead|flee_b)$/);
  if (um) return figureSprite(um[1], um[2] as Pose, v);
  const em = key.match(/^(ballista|mangonel|rock_lobber|war_wagon)_(idle_fs|idle_bs|atk_fs|atk_bs|idle_f|idle_b|atk_f|atk_b|run_f|run_b|dead|flee_b)$/);
  if (em) return engineSprite(em[1], em[2] as Pose, v);
  const pe = key.match(/^portrait_(ballista|mangonel|rock_lobber|war_wagon)$/);
  if (pe) return enginePortrait(pe[1], v);
  const pm = key.match(/^portrait_(footman|spearman|crossbowman|collie_guard|goblin_spear|goblin_archer|orc_warrior|orc_brute|orc_warlord|troll|goblin_rabble|goblin_horn|wolf_rider|militia|battle_mage|goblin_shaman)$/);
  if (pm) return portraitSprite(pm[1], v);
  const bm = key.match(/^b_(\w+)_(\d)$/);
  if (bm) return v === 0 ? building(bm[1], Number(bm[2])) : null;
  const nm = key.match(/^node_(\w+)$/);
  if (nm) return v === 0 ? nodeIcon(nm[1]) : null;
  if (key === 'missing') {
    const { c, x } = canvas(40, 40);
    x.fillStyle = '#f0f';
    x.fillRect(0, 0, 40, 40);
    return sp(c, 20, 40);
  }
  return null;
}
