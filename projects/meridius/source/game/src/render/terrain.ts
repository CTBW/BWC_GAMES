// Static terrain layer: a painted top-down colour field projected onto the
// isometric plane, raised plateaus with lit cliff faces, and ground decals.

import { Rng, hash2 } from '../core/rng';
import { LH, TH, TW, isoX, isoY } from './iso';
import { sprite, drawSprite, texture } from './assets';

export interface GroundTile {
  x: number;
  y: number;
  h: number;
  terrain: string;
}

export interface TerrainInput {
  w: number;
  h: number;
  border: number;
  tiles: GroundTile[];
  seed: number;
  palette: 'summer' | 'camp' | 'base' | 'map';
  /** Smoothly blended road paths in grid coordinates (campaign map). */
  roads?: { x: number; y: number }[][];
  decals?: boolean;
  /** Pixels per tile in the colour field. */
  res?: number;
  /** Output canvas pixels per world pixel (draw with 1/scale). */
  scale?: number;
}

export interface TerrainLayer {
  canvas: HTMLCanvasElement;
  scale: number;
  /** World coordinates of the canvas origin. */
  ox: number;
  oy: number;
  water: Path2D;
  waterTiles: { x: number; y: number }[];
}

// ---------------------------------------------------------------- noise

function vnoise(x: number, y: number, seed: number) {
  const xi = Math.floor(x);
  const yi = Math.floor(y);
  const xf = x - xi;
  const yf = y - yi;
  const s = (t: number) => t * t * (3 - 2 * t);
  const a = hash2(xi, yi, seed);
  const b = hash2(xi + 1, yi, seed);
  const c = hash2(xi, yi + 1, seed);
  const d = hash2(xi + 1, yi + 1, seed);
  const u = s(xf);
  const v = s(yf);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}

export function fbm(x: number, y: number, seed: number, oct = 4) {
  let sum = 0;
  let amp = 0.5;
  let f = 1;
  for (let i = 0; i < oct; i++) {
    sum += amp * vnoise(x * f, y * f, seed + i * 17);
    f *= 2.03;
    amp *= 0.5;
  }
  return sum / 0.9375;
}

type RGB = [number, number, number];
const hex = (h: string): RGB => {
  const n = parseInt(h.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
};
const mix = (a: RGB, b: RGB, t: number): RGB => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];

const PAL = {
  grassA: hex('#86a83c'),
  grassB: hex('#a3b84a'),
  grassC: hex('#6c9334'),
  grassD: hex('#bdb85a'),
  dirtA: hex('#b8975c'),
  dirtB: hex('#9a7a48'),
  brush: hex('#557d2c'),
  forest: hex('#3f6227'),
  floor: hex('#34521f'),
  stone: hex('#a8a594'),
  water: hex('#3f86a6'),
  waterDeep: hex('#2c6a8a'),
  shallow: hex('#5ea2a8'),
  mud: hex('#6f5d3c'),
  bank: hex('#6b6a3a'),
};

const CAT = ['grass', 'dirt', 'brush', 'forest', 'stone', 'water', 'shallows', 'floor', 'mud'] as const;
type Cat = (typeof CAT)[number];
function catOf(t: string): Cat {
  if (t === 'road') return 'dirt';
  if (t === 'bridge') return 'water';
  if ((CAT as readonly string[]).includes(t)) return t as Cat;
  return 'grass';
}

// ---------------------------------------------------------------- build

export function buildTerrain(input: TerrainInput): TerrainLayer {
  const { w, h, border: B, seed } = input;
  const R = input.res ?? 24;
  const GW = w + 2 * B;
  const GH = h + 2 * B;
  const tileAt = new Map<number, GroundTile>();
  for (const t of input.tiles) tileAt.set(t.y * 4096 + t.x, t);
  const get = (x: number, y: number): GroundTile | undefined => tileAt.get(y * 4096 + x);
  const hAt = (x: number, y: number) => get(x, y)?.h ?? 0;
  const terrAt = (x: number, y: number): Cat => {
    const t = get(x, y);
    if (!t) return input.palette === 'map' ? 'grass' : 'floor';
    return catOf(t.terrain);
  };

  // 1. Category weights per tile (padded grid), sampled bilinearly per pixel.
  const weights: Record<Cat, Float32Array> = Object.fromEntries(CAT.map((c) => [c, new Float32Array(GW * GH)])) as never;
  for (let gy = 0; gy < GH; gy++)
    for (let gx = 0; gx < GW; gx++) weights[terrAt(gx - B, gy - B)][gy * GW + gx] = 1;

  // Roads (campaign map) stamped into the dirt weight at higher resolution later.
  const field = document.createElement('canvas');
  field.width = GW * R;
  field.height = GH * R;
  const fx = field.getContext('2d')!;
  const img = fx.createImageData(field.width, field.height);
  const data = img.data;
  const sampleW = (cat: Cat, u: number, v: number) => {
    // u, v in tile units relative to padded grid, centre of tile at +0.5
    const gx = u - 0.5;
    const gy = v - 0.5;
    const x0 = Math.max(0, Math.min(GW - 1, Math.floor(gx)));
    const y0 = Math.max(0, Math.min(GH - 1, Math.floor(gy)));
    const x1 = Math.min(GW - 1, x0 + 1);
    const y1 = Math.min(GH - 1, y0 + 1);
    const tx = Math.max(0, Math.min(1, gx - x0));
    const ty = Math.max(0, Math.min(1, gy - y0));
    const W = weights[cat];
    const a = W[y0 * GW + x0];
    const b = W[y0 * GW + x1];
    const c = W[y1 * GW + x0];
    const d = W[y1 * GW + x1];
    return a + (b - a) * tx + (c - a) * ty + (a - b - c + d) * tx * ty;
  };
  const camp = input.palette === 'camp';
  for (let py = 0; py < field.height; py++) {
    for (let px = 0; px < field.width; px++) {
      const u = px / R;
      const v = py / R;
      const n1 = fbm(u * 0.35, v * 0.35, seed);
      const n2 = fbm(u * 1.4, v * 1.4, seed + 5);
      const n3 = fbm(u * 4.5, v * 4.5, seed + 9);
      // Organic edges: jitter the sample point.
      const ju = u + (n2 - 0.5) * 0.9;
      const jv = v + (fbm(u * 1.4, v * 1.4, seed + 77) - 0.5) * 0.9;
      let col: RGB = mix(mix(PAL.grassC, PAL.grassA, n1), mix(PAL.grassB, PAL.grassD, n2), Math.max(0, n1 * 1.2 - 0.25));
      const wDirt = Math.min(1, sampleW('dirt', ju, jv) * 1.15 + (camp ? 0.15 : 0) * n2);
      const wBrush = sampleW('brush', ju, jv);
      const wForest = sampleW('forest', ju, jv);
      const wFloor = sampleW('floor', ju, jv);
      const wStone = sampleW('stone', ju, jv);
      const wWater = sampleW('water', u, v);
      const wShallow = sampleW('shallows', ju, jv);
      const wMud = sampleW('mud', ju, jv);
      // Natural dirt patches even on grass.
      const patch = Math.max(0, fbm(u * 0.6, v * 0.6, seed + 31) - 0.62) * 2.2;
      const dirtCol = mix(PAL.dirtB, PAL.dirtA, n3);
      col = mix(col, dirtCol, Math.min(1, Math.max(0, wDirt * 1.2 - 0.1 + (n3 - 0.5) * 0.5) + patch * 0.6));
      col = mix(col, mix(PAL.brush, PAL.grassC, n3 * 0.6), Math.min(1, wBrush * 1.1));
      col = mix(col, mix(PAL.forest, PAL.brush, n3 * 0.5), Math.min(1, wForest));
      col = mix(col, mix(PAL.floor, PAL.forest, n2 * 0.7), Math.min(1, wFloor));
      col = mix(col, mix(PAL.mud, PAL.dirtB, n3 * 0.5), Math.min(1, wMud));
      if (wStone > 0.05) {
        // Flagstones: cell pattern.
        const cu = Math.floor(u * 3 + (Math.floor(v * 3) % 2) * 0.5);
        const cv = Math.floor(v * 3);
        const cell = hash2(cu, cv, seed + 3);
        const edge = Math.min(Math.abs(((u * 3 + (Math.floor(v * 3) % 2) * 0.5) % 1) - 0.5), Math.abs(((v * 3) % 1) - 0.5));
        let sc = mix(PAL.stone, hex('#c4c0ad'), cell * 0.8);
        if (edge > 0.42) sc = mix(sc, hex('#5e5c4e'), 0.6);
        col = mix(col, sc, Math.min(1, wStone * 1.3 * (0.7 + n3 * 0.4)));
      }
      if (wShallow > 0.05) col = mix(col, mix(PAL.shallow, PAL.water, n2), Math.min(1, wShallow * 1.2));
      if (wWater > 0.02) {
        const bank = Math.max(0, Math.min(1, (wWater - 0.15) * 3));
        col = mix(col, PAL.bank, Math.min(1, wWater * 2) * (1 - bank) * 0.8);
        col = mix(col, mix(PAL.waterDeep, PAL.water, n2), bank);
      }
      // Fine painterly grain.
      const grain = (n3 - 0.5) * 22 + (hash2(px, py, seed) - 0.5) * 8;
      const i = (py * field.width + px) * 4;
      data[i] = col[0] + grain;
      data[i + 1] = col[1] + grain;
      data[i + 2] = col[2] + grain * 0.6;
      data[i + 3] = 255;
    }
  }
  fx.putImageData(img, 0, 0);

  // Roads on the campaign map: soft dirt ribbons.
  if (input.roads) {
    fx.lineCap = 'round';
    fx.lineJoin = 'round';
    for (const road of input.roads) {
      for (const [wdt, color] of [[R * 0.75, 'rgba(120,95,55,0.55)'], [R * 0.5, 'rgba(184,152,96,0.95)'], [R * 0.12, 'rgba(210,185,130,0.6)']] as const) {
        fx.strokeStyle = color;
        fx.lineWidth = wdt;
        fx.beginPath();
        road.forEach((p, i) => {
          const X = (p.x + B + 0.5) * R;
          const Y = (p.y + B + 0.5) * R;
          if (i === 0) fx.moveTo(X, Y);
          else fx.lineTo(X, Y);
        });
        fx.stroke();
      }
    }
  }

  // Painterly dabs: light and dark strokes across the meadow.
  const rng = new Rng(seed + 1234);
  const dabs = GW * GH * 22;
  for (let i = 0; i < dabs; i++) {
    const u = rng.next() * GW;
    const v = rng.next() * GH;
    const cat = terrAt(Math.floor(u) - B, Math.floor(v) - B);
    if (cat === 'water' || cat === 'stone') continue;
    const light = rng.chance(0.5);
    fx.fillStyle =
      cat === 'dirt'
        ? light
          ? 'rgba(220,190,130,0.35)'
          : 'rgba(90,70,40,0.25)'
        : light
          ? 'rgba(200,215,110,0.28)'
          : 'rgba(40,70,25,0.22)';
    const s = rng.range(1, 2.6) * (R / 24);
    fx.fillRect(u * R, v * R, s * 2.2, s);
  }

  // Optional texture detail overlay (generated ground texture when available).
  const tex = texture('ground_detail');
  if (tex) {
    fx.globalAlpha = 0.35;
    fx.globalCompositeOperation = 'overlay';
    const pat = fx.createPattern(tex, 'repeat');
    if (pat) {
      fx.fillStyle = pat;
      fx.fillRect(0, 0, field.width, field.height);
    }
    fx.globalCompositeOperation = 'source-over';
    fx.globalAlpha = 1;
  }

  // 2. Project into the isometric layer.
  const maxH = Math.max(0, ...input.tiles.map((t) => t.h));
  const corners = [
    [-B - 0.5, -B - 0.5],
    [w + B - 0.5, -B - 0.5],
    [-B - 0.5, h + B - 0.5],
    [w + B - 0.5, h + B - 0.5],
  ];
  const xs = corners.map(([x, y]) => isoX(x, y));
  const ys = corners.map(([x, y]) => isoY(x, y));
  const ox = Math.floor(Math.min(...xs)) - 4;
  const oy = Math.floor(Math.min(...ys)) - maxH * LH - 8;
  const SC = input.scale ?? 1;
  const out = document.createElement('canvas');
  out.width = Math.ceil((Math.max(...xs) - ox + 8) * SC);
  out.height = Math.ceil((Math.max(...ys) - oy + 8) * SC);
  const ctx = out.getContext('2d')!;
  ctx.imageSmoothingQuality = 'high';
  const base = () => ctx.setTransform(SC, 0, 0, SC, 0, 0);
  base();

  const drawField = (level: number) => {
    // pixel (u, v) -> grid (u/R - B - 0.5, v/R - B - 0.5) -> iso world -> canvas
    const a = TW / 2 / R;
    const b = TH / 2 / R;
    const gx0 = -B - 0.5;
    const gy0 = -B - 0.5;
    ctx.setTransform(a * SC, b * SC, -a * SC, b * SC, (isoX(gx0, gy0) - ox) * SC, (isoY(gx0, gy0, level) - oy) * SC);
    ctx.drawImage(field, 0, 0);
    base();
  };
  const diamond = (path: Path2D, x: number, y: number, lvl: number) => {
    path.moveTo(isoX(x - 0.5, y - 0.5) - ox, isoY(x - 0.5, y - 0.5, lvl) - oy);
    path.lineTo(isoX(x + 0.5, y - 0.5) - ox, isoY(x + 0.5, y - 0.5, lvl) - oy);
    path.lineTo(isoX(x + 0.5, y + 0.5) - ox, isoY(x + 0.5, y + 0.5, lvl) - oy);
    path.lineTo(isoX(x - 0.5, y + 0.5) - ox, isoY(x - 0.5, y + 0.5, lvl) - oy);
    path.closePath();
  };

  drawField(0);
  for (let L = 1; L <= maxH; L++) {
    // Cliff faces for this band, back to front.
    const raised = input.tiles.filter((t) => t.h >= L).sort((p, q) => p.x + p.y - (q.x + q.y));
    for (const t of raised) {
      if (hAt(t.x + 1, t.y) < L) face(ctx, t.x, t.y, L, 'se', ox, oy, seed);
      if (hAt(t.x, t.y + 1) < L) face(ctx, t.x, t.y, L, 'sw', ox, oy, seed);
    }
    const clip = new Path2D();
    for (const t of raised) diamond(clip, t.x, t.y, L);
    ctx.save();
    ctx.clip(clip);
    drawField(L);
    // Slight brightening of higher ground (sunlit).
    ctx.fillStyle = `rgba(255,240,190,${0.05 * L})`;
    ctx.fillRect(0, 0, out.width / SC, out.height / SC);
    ctx.restore();
    // Rim light on back edges and grass lips on front edges.
    ctx.lineCap = 'round';
    for (const t of raised) {
      if (t.h !== L && hAt(t.x, t.y) > L) continue;
      const top = (ax: number, ay: number) => [isoX(ax, ay) - ox, isoY(ax, ay, L) - oy] as const;
      const edges: [boolean, number, number, number, number, string][] = [
        [hAt(t.x - 1, t.y) < L, t.x - 0.5, t.y - 0.5, t.x - 0.5, t.y + 0.5, 'rgba(255,245,200,0.55)'],
        [hAt(t.x, t.y - 1) < L, t.x - 0.5, t.y - 0.5, t.x + 0.5, t.y - 0.5, 'rgba(255,245,200,0.4)'],
        [hAt(t.x + 1, t.y) < L, t.x + 0.5, t.y - 0.5, t.x + 0.5, t.y + 0.5, 'rgba(70,110,35,0.95)'],
        [hAt(t.x, t.y + 1) < L, t.x - 0.5, t.y + 0.5, t.x + 0.5, t.y + 0.5, 'rgba(90,130,40,0.95)'],
      ];
      for (const [on, x1, y1, x2, y2, col] of edges) {
        if (!on) continue;
        const [sx1, sy1] = top(x1, y1);
        const [sx2, sy2] = top(x2, y2);
        ctx.strokeStyle = col;
        ctx.lineWidth = col.startsWith('rgba(255') ? 2 : 5;
        ctx.beginPath();
        ctx.moveTo(sx1, sy1);
        const steps = 6;
        for (let i = 1; i <= steps; i++) {
          const f = i / steps;
          const wob = col.startsWith('rgba(255') ? 0 : Math.sin((f + t.x * 0.37 + t.y * 0.61) * 9) * 2.2;
          ctx.lineTo(sx1 + (sx2 - sx1) * f, sy1 + (sy2 - sy1) * f + wob);
        }
        ctx.stroke();
      }
    }
  }

  // Water path for animation.
  const water = new Path2D();
  const waterTiles: { x: number; y: number }[] = [];
  for (const t of input.tiles) {
    if (t.terrain === 'water' || t.terrain === 'shallows' || t.terrain === 'bridge') {
      waterTiles.push({ x: t.x, y: t.y });
      water.moveTo(isoX(t.x - 0.5, t.y - 0.5), isoY(t.x - 0.5, t.y - 0.5, t.h));
      water.lineTo(isoX(t.x + 0.5, t.y - 0.5), isoY(t.x + 0.5, t.y - 0.5, t.h));
      water.lineTo(isoX(t.x + 0.5, t.y + 0.5), isoY(t.x + 0.5, t.y + 0.5, t.h));
      water.lineTo(isoX(t.x - 0.5, t.y + 0.5), isoY(t.x - 0.5, t.y + 0.5, t.h));
      water.closePath();
    }
  }

  // Bridges.
  for (const t of input.tiles.filter((q) => q.terrain === 'bridge')) {
    const cx = isoX(t.x, t.y) - ox;
    const cy = isoY(t.x, t.y, t.h) - oy;
    ctx.save();
    ctx.translate(cx, cy);
    const planks = 7;
    for (let i = 0; i < planks; i++) {
      const f = i / (planks - 1) - 0.5;
      ctx.fillStyle = i % 2 ? '#8a6238' : '#9c7243';
      ctx.beginPath();
      // Planks run across the river (along x).
      const ax = (f - 0.07) * TW * 0.5;
      const bx = (f + 0.07) * TW * 0.5;
      ctx.moveTo(ax - TW * 0.36, ax * 0.5 + TW * 0.18 - 6);
      ctx.lineTo(bx - TW * 0.36, bx * 0.5 + TW * 0.18 - 6);
      ctx.lineTo(bx + TW * 0.36, bx * 0.5 - TW * 0.18 - 6);
      ctx.lineTo(ax + TW * 0.36, ax * 0.5 - TW * 0.18 - 6);
      ctx.closePath();
      ctx.fill();
      ctx.strokeStyle = 'rgba(40,25,15,0.7)';
      ctx.lineWidth = 1.2;
      ctx.stroke();
    }
    ctx.restore();
  }

  // Ambient occlusion along the outer forest edge.
  if (input.palette !== 'map') {
    ctx.save();
    const ring = new Path2D();
    for (let y = -B; y < h + B; y++) {
      for (let x = -B; x < w + B; x++) {
        if (x >= 0 && y >= 0 && x < w && y < h) continue;
        const d = Math.max(-x, -y, x - (w - 1), y - (h - 1));
        if (d < 2) continue;
        diamond(ring, x, y, 0);
      }
    }
    ctx.fillStyle = 'rgba(20,35,15,0.35)';
    ctx.fill(ring);
    ctx.restore();
  }

  // 3. Decals: tufts, flowers and pebbles.
  if (input.decals !== false) {
    const drng = new Rng(seed + 99);
    const list: { x: number; y: number; k: string; v: number }[] = [];
    for (let gy = -B; gy < h + B; gy++) {
      for (let gx = -B; gx < w + B; gx++) {
        const cat = terrAt(gx, gy);
        if (cat === 'water' || cat === 'stone') continue;
        const n = cat === 'grass' ? 3 : cat === 'dirt' ? 1 : cat === 'brush' ? 4 : 1;
        for (let i = 0; i < n; i++) {
          if (!drng.chance(0.75)) continue;
          const k = cat === 'dirt' ? (drng.chance(0.7) ? 'pebble' : 'tuft') : drng.chance(0.18) ? 'flower' : 'tuft';
          list.push({ x: gx + drng.range(-0.45, 0.45), y: gy + drng.range(-0.45, 0.45), k, v: drng.int(0, 2) });
        }
      }
    }
    list.sort((p, q) => p.x + p.y - (q.x + q.y));
    for (const d of list) {
      const hh = hAt(Math.round(d.x), Math.round(d.y));
      const s = sprite(d.k, d.v);
      drawSprite(ctx, s, isoX(d.x, d.y) - ox, isoY(d.x, d.y, hh) - oy, { flip: d.v === 1, scale: 0.9 + (d.v % 2) * 0.2 });
    }
  }

  ctx.setTransform(1, 0, 0, 1, 0, 0);
  return { canvas: out, scale: SC, ox, oy, water, waterTiles };
}

function face(ctx: CanvasRenderingContext2D, x: number, y: number, L: number, side: 'se' | 'sw', ox: number, oy: number, seed: number) {
  const p1 = side === 'se' ? [x + 0.5, y - 0.5] : [x - 0.5, y + 0.5];
  const p2 = [x + 0.5, y + 0.5];
  const a = { x: isoX(p1[0], p1[1]) - ox, y: isoY(p1[0], p1[1], L) - oy };
  const b = { x: isoX(p2[0], p2[1]) - ox, y: isoY(p2[0], p2[1], L) - oy };
  ctx.save();
  ctx.beginPath();
  ctx.moveTo(a.x, a.y);
  ctx.lineTo(b.x, b.y);
  ctx.lineTo(b.x, b.y + LH);
  ctx.lineTo(a.x, a.y + LH);
  ctx.closePath();
  const g = ctx.createLinearGradient(0, Math.min(a.y, b.y), 0, Math.max(a.y, b.y) + LH);
  if (side === 'sw') {
    g.addColorStop(0, '#9a8466');
    g.addColorStop(1, '#6e5a42');
  } else {
    g.addColorStop(0, '#6f5c45');
    g.addColorStop(1, '#4a3c2c');
  }
  ctx.fillStyle = g;
  ctx.fill();
  ctx.clip();
  // Rock strata and stones.
  const rng = new Rng(seed + x * 31 + y * 17 + L * 7 + (side === 'se' ? 1 : 0));
  for (let i = 0; i < 7; i++) {
    const f = rng.next();
    const px = a.x + (b.x - a.x) * f;
    const py = a.y + (b.y - a.y) * f + rng.range(4, LH - 4);
    ctx.fillStyle = rng.chance(0.5) ? 'rgba(200,190,170,0.35)' : 'rgba(40,30,20,0.3)';
    ctx.beginPath();
    ctx.ellipse(px, py, rng.range(4, 9), rng.range(2.5, 5), 0, 0, 7);
    ctx.fill();
  }
  ctx.restore();
  ctx.strokeStyle = 'rgba(40,28,18,0.6)';
  ctx.lineWidth = 1.2;
  ctx.beginPath();
  ctx.moveTo(a.x, a.y + LH);
  ctx.lineTo(b.x, b.y + LH);
  ctx.stroke();
}
