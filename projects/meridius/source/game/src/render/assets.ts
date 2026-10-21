// Sprite registry. Generated art is listed in public/assets/manifest.json;
// anything missing falls back to a procedural placeholder of the same key.

import { proceduralSprite } from './procedural';

/** A rectangle of an image: a whole silhouette canvas, or part of a larger image. */
export interface Region {
  img: HTMLCanvasElement | HTMLImageElement;
  sx: number;
  sy: number;
}

export interface Sprite {
  img: HTMLCanvasElement | HTMLImageElement;
  /** Where the sprite sits inside `img` when it is part of a larger image (default 0, 0). */
  sx?: number;
  sy?: number;
  /** Anchor in source pixels (usually the feet / ground contact point). */
  ax: number;
  ay: number;
  /** World pixels per source pixel. */
  scale: number;
  w: number;
  h: number;
  /** Black silhouette for cast shadows (lazily built). */
  shadow?: Region;
  /** White silhouette for hit flashes (lazily built). */
  flash?: HTMLCanvasElement;
  /** The sprite carries its own baked shadow: no cast shadow, never mirrored. */
  noShadow?: boolean;
}

interface ManifestEntry {
  file: string;
  ax: number;
  ay: number;
  scale?: number;
  noShadow?: boolean;
}

const sprites = new Map<string, Sprite[]>();
const images = new Map<string, HTMLImageElement>();
let manifest: Record<string, ManifestEntry[]> = {};
let textures: Record<string, string> = {};

export async function loadAssets(onProgress?: (f: number) => void): Promise<void> {
  try {
    const res = await fetch('/assets/manifest.json', { cache: 'no-cache' });
    if (res.ok) {
      const m = await res.json();
      manifest = m.sprites ?? {};
      textures = m.textures ?? {};
    }
  } catch {
    manifest = {};
  }
  const files = new Set<string>();
  for (const list of Object.values(manifest)) for (const e of list) files.add(e.file);
  for (const f of Object.values(textures)) files.add(f);
  let done = 0;
  await Promise.all(
    [...files].map(
      (f) =>
        new Promise<void>((resolve) => {
          const img = new Image();
          img.onload = () => {
            images.set(f, img);
            onProgress?.(++done / files.size);
            resolve();
          };
          img.onerror = () => {
            onProgress?.(++done / files.size);
            resolve();
          };
          img.src = `/assets/${f}`;
        }),
    ),
  );
  for (const [key, list] of Object.entries(manifest)) {
    const out: Sprite[] = [];
    for (const e of list) {
      const img = images.get(e.file);
      if (!img) continue;
      out.push({ img, ax: e.ax, ay: e.ay, scale: e.scale ?? 1, w: img.width, h: img.height, noShadow: e.noShadow });
    }
    if (out.length) sprites.set(key, out);
  }
}

export function hasArt(key: string): boolean {
  return !!manifest[key] && sprites.has(key) && !(sprites.get(key)![0].img instanceof HTMLCanvasElement);
}

/** Get a sprite variant. Falls back to procedural art when no image exists. */
export function sprite(key: string, variant = 0): Sprite {
  let list = sprites.get(key);
  if (!list) {
    list = [];
    // Squads show six soldiers side by side, so figures come in six looks.
    const looks = /_(idle_fs?|idle_bs?|atk_fs?|atk_bs?|run_[fb]|dead|flee_b)$/.test(key) ? 6 : 3;
    for (let v = 0; v < looks; v++) {
      const p = proceduralSprite(key, v);
      if (p) list.push(p);
    }
    if (!list.length) list.push(proceduralSprite('missing', 0)!);
    sprites.set(key, list);
  }
  return list[Math.abs(variant) % list.length];
}

export function variantCount(key: string): number {
  sprite(key);
  return sprites.get(key)!.length;
}

export function texture(key: string): HTMLImageElement | undefined {
  const f = textures[key];
  return f ? images.get(f) : undefined;
}

function silhouette(s: Sprite, color: string): HTMLCanvasElement {
  const c = document.createElement('canvas');
  c.width = s.w;
  c.height = s.h;
  const x = c.getContext('2d')!;
  x.drawImage(s.img, s.sx ?? 0, s.sy ?? 0, s.w, s.h, 0, 0, s.w, s.h);
  x.globalCompositeOperation = 'source-in';
  x.fillStyle = color;
  x.fillRect(0, 0, s.w, s.h);
  return c;
}



const masks = new WeakMap<Sprite, { w: number; h: number; k: number; a: Uint8Array }>();

/** A quarter-resolution alpha mask of a sprite's pixels, for hit tests. */
function buildMask(img: CanvasImageSource, sw: number, sh: number, sx: number, sy: number) {
  const k = 4;
  const w = Math.max(1, Math.ceil(sw / k));
  const h = Math.max(1, Math.ceil(sh / k));
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  const x = c.getContext('2d', { willReadFrequently: true })!;
  x.drawImage(img, sx, sy, sw, sh, 0, 0, w, h);
  const d = x.getImageData(0, 0, w, h).data;
  const a = new Uint8Array(w * h);
  for (let i = 0; i < w * h; i++) a[i] = d[i * 4 + 3];
  return { w, h, k, a };
}

/** True if the sprite is opaque at a point given in its own pixel space. */
export function opaqueAt(s: Sprite, px: number, py: number): boolean {
  let m = masks.get(s);
  if (!m) {
    m = buildMask(s.img, s.w, s.h, s.sx ?? 0, s.sy ?? 0);
    masks.set(s, m);
  }
  const ix = Math.floor(px / m.k);
  const iy = Math.floor(py / m.k);
  if (ix < 0 || iy < 0 || ix >= m.w || iy >= m.h) return false;
  return m.a[iy * m.w + ix] > 150;
}

export function shadowOf(s: Sprite): Region {
  if (!s.shadow) s.shadow = { img: silhouette(s, '#000'), sx: 0, sy: 0 };
  return s.shadow;
}

export function flashOf(s: Sprite): HTMLCanvasElement {
  if (!s.flash) s.flash = silhouette(s, '#fff');
  return s.flash;
}

/**
 * Draw a sprite anchored at world point (x, y). `flip` mirrors horizontally.
 * `scale` multiplies the sprite's own scale.
 */
export function drawSprite(
  ctx: CanvasRenderingContext2D,
  s: Sprite,
  x: number,
  y: number,
  opts: { flip?: boolean; scale?: number; sy?: number; alpha?: number; rot?: number; img?: CanvasImageSource | Region } = {},
) {
  const sc = s.scale * (opts.scale ?? 1);
  ctx.save();
  if (opts.alpha !== undefined) ctx.globalAlpha *= opts.alpha;
  ctx.translate(x, y);
  if (opts.rot) ctx.rotate(opts.rot);
  ctx.scale(opts.flip ? -sc : sc, sc * (opts.sy ?? 1));
  const o = opts.img;
  if (o && 'sx' in o && 'img' in o) ctx.drawImage(o.img, o.sx, o.sy, s.w, s.h, -s.ax, -s.ay, s.w, s.h);
  else if (o) ctx.drawImage(o as CanvasImageSource, -s.ax, -s.ay);
  else if (s.sx !== undefined) ctx.drawImage(s.img, s.sx, s.sy ?? 0, s.w, s.h, -s.ax, -s.ay, s.w, s.h);
  else ctx.drawImage(s.img, -s.ax, -s.ay);
  ctx.restore();
}

/** Cast shadow: the silhouette flattened and skewed away from the upper-left light. */
export function drawCastShadow(ctx: CanvasRenderingContext2D, s: Sprite, x: number, y: number, flip = false, scale = 1, alpha = 0.22) {
  if (s.noShadow) return;
  const sh = shadowOf(s);
  const sc = s.scale * scale;
  ctx.save();
  ctx.globalAlpha *= alpha;
  ctx.translate(x, y);
  // Light from the upper left: shadows fall down and to the right.
  ctx.transform(1, 0, -0.75, -0.32, 0, 0);
  ctx.scale(flip ? -sc : sc, sc);
  ctx.drawImage(sh.img, sh.sx, sh.sy, s.w, s.h, -s.ax, -s.ay, s.w, s.h);
  ctx.restore();
}
