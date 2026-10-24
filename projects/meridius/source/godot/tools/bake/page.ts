// Bake page: runs the ORIGINAL game's renderer and sound code (imported from
// ../../../game/src, unmodified) inside the browser and hands the results to
// tools/bake/bake.mjs through window.__bake. Nothing here draws art itself.

import { loadAssets, sprite, variantCount, hasArt, drawSprite, drawCastShadow, flashOf, shadowOf, opaqueAt, type Sprite } from '../../../game/src/render/assets';
import { PROPS } from '../../../game/src/data/terrain';
import { BUILDINGS } from '../../../game/src/data/buildings';
import { NODE_INFO } from '../../../game/src/data/campaigns';
import { UNIT_TYPES } from '../../../game/src/data/units';

type W = typeof window & { __bake: unknown };

/** Raw bytes → base64 (through a data URL, fast for megabytes). */
function b64(bytes: Uint8Array): Promise<string> {
  return new Promise((resolve) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result).slice(String(r.result).indexOf(',') + 1));
    r.readAsDataURL(new Blob([bytes]));
  });
}

async function deflate(bytes: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([bytes]).stream().pipeThrough(new CompressionStream('deflate'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

/** Keys that the data tables make the scenes request. */
function dataKeys() {
  return {
    props: Object.values(PROPS).map((p) => p.sprite),
    propIds: Object.keys(PROPS),
    buildings: BUILDINGS.map((b) => ({ id: b.id, levels: b.levels.length })),
    nodes: Object.keys(NODE_INFO),
    unitSprites: Object.values(UNIT_TYPES).map((u) => (u as { sprite: string }).sprite),
  };
}

interface Entry {
  key: string;
  v: number;
  art: boolean;
  file?: string;
  ax: number;
  ay: number;
  scale: number;
  w: number;
  h: number;
  sx: number;
  sy: number;
  noShadow: boolean;
  /** Deflated straight-alpha RGBA of a procedural canvas (getImageData), base64. */
  rgba?: string;
}

/** What the original's sprite(key, v) returns for every variant of each key. */
async function collect(keys: string[]): Promise<{ key: string; count: number; hasArt: boolean; entries: Entry[] }[]> {
  const out = [];
  for (const key of keys) {
    const count = variantCount(key);
    const entries: Entry[] = [];
    for (let v = 0; v < count; v++) {
      const s: Sprite = sprite(key, v);
      const e: Entry = {
        key,
        v,
        art: !(s.img instanceof HTMLCanvasElement),
        ax: s.ax,
        ay: s.ay,
        scale: s.scale,
        w: s.w,
        h: s.h,
        sx: s.sx ?? 0,
        sy: s.sy ?? 0,
        noShadow: !!s.noShadow,
      };
      if (s.img instanceof HTMLCanvasElement) {
        const d = s.img.getContext('2d')!.getImageData(s.sx ?? 0, s.sy ?? 0, s.w, s.h).data;
        e.rgba = await b64(await deflate(new Uint8Array(d.buffer, d.byteOffset, d.byteLength)));
      } else {
        e.file = new URL((s.img as HTMLImageElement).src).pathname.replace(/^\/assets\//, '');
      }
      entries.push(e);
    }
    out.push({ key, count, hasArt: hasArt(key), entries });
  }
  return out;
}

interface SheetItem {
  key: string;
  v: number;
  x: number;
  y: number;
  flip?: boolean;
  scale?: number;
  alpha?: number;
  rot?: number;
  sy?: number;
  /** Cast shadow alpha (drawCastShadow before the sprite); 0 or absent for none. */
  shadow?: number;
  /** 'flash' draws flashOf(s), 'silhouette' draws shadowOf(s), 'lighter' flashOf with additive blending. */
  mode?: 'normal' | 'flash' | 'silhouette' | 'lighter';
  /** Draw the sprite into a size×size box (the Portrait component's drawImage). */
  box?: number;
}

interface SheetSpec {
  name: string;
  w: number;
  h: number;
  bg: string;
  items: SheetItem[];
}

/** Draw a contact sheet with the original's drawSprite / drawCastShadow. */
function sheet(spec: SheetSpec): string {
  const c = document.createElement('canvas');
  c.width = spec.w;
  c.height = spec.h;
  const x = c.getContext('2d')!;
  x.fillStyle = spec.bg;
  x.fillRect(0, 0, spec.w, spec.h);
  // The battle scene draws sprites with high-quality smoothing.
  x.imageSmoothingQuality = 'high';
  for (const it of spec.items) {
    const s = sprite(it.key, it.v);
    if (it.box) {
      x.drawImage(s.img, s.sx ?? 0, s.sy ?? 0, s.w, s.h, it.x, it.y, it.box, it.box);
      continue;
    }
    if (it.shadow) drawCastShadow(x, s, it.x, it.y, !!it.flip, it.scale ?? 1, it.shadow);
    const opts = { flip: it.flip, scale: it.scale, alpha: it.alpha, rot: it.rot, sy: it.sy };
    if (it.mode === 'flash') drawSprite(x, s, it.x, it.y, { ...opts, img: flashOf(s) });
    else if (it.mode === 'silhouette') drawSprite(x, s, it.x, it.y, { ...opts, img: shadowOf(s) });
    else if (it.mode === 'lighter') {
      x.save();
      x.globalCompositeOperation = 'lighter';
      drawSprite(x, s, it.x, it.y, { ...opts, img: flashOf(s) });
      x.restore();
    } else drawSprite(x, s, it.x, it.y, opts);
  }
  return c.toDataURL('image/png');
}

/** The original's opaqueAt() on a grid of points (every `step` px from step/2), as '0'/'1'. */
function hitGrid(key: string, v: number, step: number): { w: number; h: number; bits: string } {
  const s = sprite(key, v);
  let bits = '';
  for (let y = step / 2; y < s.h; y += step) for (let x = step / 2; x < s.w; x += step) bits += opaqueAt(s, x, y) ? '1' : '0';
  return { w: s.w, h: s.h, bits };
}

// ---------------------------------------------------------------- audio

const SR = 44100;
const LEN = 5;
let offline: OfflineAudioContext | null = null;
// sfx.ts creates its AudioContext lazily on the first sfx() call. Each render
// imports a fresh instance of the module, whose first call then gets an
// OfflineAudioContext of its own.
(window as unknown as { AudioContext: unknown }).AudioContext = function FakeAudioContext() {
  const c = new OfflineAudioContext(1, SR * LEN, SR);
  // An offline context cannot be resumed before rendering; sfx.ts resumes a suspended context.
  Object.defineProperty(c, 'resume', { value: () => Promise.resolve() });
  offline = c;
  return c;
};

let inst = 0;

/** Render one play of sfx(name) with the original code (Math.random seeded). Returns trimmed 16-bit PCM. */
async function renderSfx(gameFs: string, name: string, seed: number) {
  offline = null;
  const mod = await import(/* @vite-ignore */ `${gameFs}/src/audio/sfx.ts?bake=${++inst}`);
  const rnd = Math.random;
  let randomCalls = 0;
  // Seeded (mulberry32) for reproducible takes; counting calls tells which recipes are random.
  let a = seed >>> 0;
  Math.random = () => {
    randomCalls++;
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  try {
    mod.sfx(name);
  } finally {
    Math.random = rnd;
  }
  if (!offline) throw new Error(`sfx(${name}) did not create an audio context`);
  const buf = await (offline as OfflineAudioContext).startRendering();
  const d = buf.getChannelData(0);
  let peak = 0;
  let last = 0;
  for (let i = 0; i < d.length; i++) {
    const a = Math.abs(d[i]);
    if (a > peak) peak = a;
    if (a > 1e-4) last = i;
  }
  const n = Math.min(d.length, last + Math.round(SR * 0.01));
  const pcm = new Int16Array(n);
  let clipped = 0;
  for (let i = 0; i < n; i++) {
    let v = d[i];
    if (v > 1) (v = 1), clipped++;
    if (v < -1) (v = -1), clipped++;
    pcm[i] = Math.round(v * 32767);
  }
  return { sampleRate: SR, samples: n, peak, clipped, randomCalls, pcm: await b64(new Uint8Array(pcm.buffer)) };
}

const ready = loadAssets();

(window as W).__bake = { ready, dataKeys, collect, sheet, hitGrid, renderSfx, variantCount, hasArt };
