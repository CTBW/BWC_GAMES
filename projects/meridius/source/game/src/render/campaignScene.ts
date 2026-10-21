import { Rng, hash2 } from '../core/rng';
import type { Expedition, CNode } from '../campaign/expedition';
import { nodeView, nextNodes } from '../campaign/expedition';
import { Atmosphere } from './atmosphere';
import { drawCastShadow, drawSprite, shadowOf, sprite } from './assets';
import type { PointerInfo, Scene } from './engine';
import { Fx } from './fx';
import { TH, TW, clamp, isoX, isoY, makeCamera, screenToWorld, updateCamera, worldToScreen, type Camera } from './iso';
import { buildTerrain, fbm, type GroundTile, type TerrainLayer } from './terrain';
import { sfx } from '../audio/sfx';

const SIZE = 38;

let puffCanvas: HTMLCanvasElement | null = null;
function puff(): HTMLCanvasElement {
  if (puffCanvas) return puffCanvas;
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const x = c.getContext('2d')!;
  const g = x.createRadialGradient(64, 64, 8, 64, 64, 64);
  // A soft grey-green mist: unexplored land stays readable instead of washing out to white.
  g.addColorStop(0, 'rgba(200,208,200,1)');
  g.addColorStop(0.5, 'rgba(196,205,198,0.55)');
  g.addColorStop(1, 'rgba(190,200,194,0)');
  x.fillStyle = g;
  x.fillRect(0, 0, 128, 128);
  puffCanvas = c;
  return c;
}

interface WorldProp {
  x: number;
  y: number;
  prop: string;
  v: number;
  s: number;
}

export interface CampaignUi {
  hover?: string;
  marching: boolean;
  version: number;
}

export class CampaignScene implements Scene {
  getEx: () => Expedition | null;
  onNodeClick: (id: string) => void;
  terrain: TerrainLayer;
  cam: Camera;
  atmo: Atmosphere;
  fx = new Fx();
  props: WorldProp[] = [];
  roads = new Map<string, { x: number; y: number }[]>();
  fog: { x: number; y: number; a: number; r: number }[] = [];
  ui: CampaignUi = { marching: false, version: 0 };
  private listeners = new Set<() => void>();
  private shownNode: string;
  private march: { path: { x: number; y: number }[]; t: number; dur: number } | null = null;
  private token = { x: 0, y: 0 };
  private w = 1;
  private h = 1;
  private keys = new Set<string>();
  /** The host's march across the map: the line from its far corner to Brannsted, its warbands and the farms it burns. */
  private horde: {
    ox: number;
    oy: number;
    ux: number;
    uy: number;
    len: number;
    bands: { t: number; s: number; figs: { a: number; b: number; key: string; v: number; flip: boolean; banner: boolean }[] }[];
    fires: { t: number; s: number; k: number }[];
    front: number;
  } | null = null;
  private hordeFx = new Fx();
  /** First look at a new expedition: the camera starts on the host, holds, then sweeps back to the muster point. */
  private intro: { t: number; from: { x: number; y: number; z: number }; to: { x: number; y: number; z: number } } | null = null;

  constructor(ex: Expedition, getEx: () => Expedition | null, onNodeClick: (id: string) => void) {
    this.getEx = getEx;
    this.onNodeClick = onNodeClick;
    const rng = new Rng(ex.seed);
    // Roads along every edge, gently curved.
    for (const [a, b] of ex.edges) {
      const na = ex.nodes.find((n) => n.id === a)!;
      const nb = ex.nodes.find((n) => n.id === b)!;
      const mx = (na.tx + nb.tx) / 2 + rng.range(-1.6, 1.6);
      const my = (na.ty + nb.ty) / 2 + rng.range(-1.6, 1.6);
      const pts: { x: number; y: number }[] = [];
      for (let i = 0; i <= 16; i++) {
        const t = i / 16;
        pts.push({
          x: (1 - t) * (1 - t) * na.tx + 2 * (1 - t) * t * mx + t * t * nb.tx,
          y: (1 - t) * (1 - t) * na.ty + 2 * (1 - t) * t * my + t * t * nb.ty,
        });
      }
      this.roads.set(`${a}>${b}`, pts);
    }
    const roadPts = [...this.roads.values()].flat();
    const nearRoad = (x: number, y: number, r: number) => roadPts.some((p) => (p.x - x) ** 2 + (p.y - y) ** 2 < r * r);
    const nearNode = (x: number, y: number, r: number) => ex.nodes.some((n) => (n.tx - x) ** 2 + (n.ty - y) ** 2 < r * r);

    const tiles: GroundTile[] = [];
    // River crossing the line of march.
    const river = new Set<number>();
    let rx = rng.int(4, 8);
    for (let y = SIZE - 1; y >= 0; y--) {
      const cx = Math.round(rx + (SIZE - 1 - y) * 0.95);
      if (cx >= SIZE) break;
      river.add(y * 100 + cx);
      river.add(y * 100 + cx + 1);
      if (rng.chance(0.35)) rx += rng.pick([-1, 1]);
    }
    for (let y = 0; y < SIZE; y++) {
      for (let x = 0; x < SIZE; x++) {
        let terrain = 'grass';
        let h = 0;
        const isRiver = river.has(y * 100 + x) && !nearNode(x, y, 2);
        if (isRiver) terrain = nearRoad(x, y, 1.1) ? 'shallows' : 'water';
        else {
          const f = fbm(x * 0.13, y * 0.13, ex.seed);
          const clear = nearNode(x, y, 3.3) || nearRoad(x, y, 1.5);
          if (f > 0.5 && !clear) {
            terrain = 'forest';
            if (rng.chance(0.8)) this.props.push({ x: x + rng.range(-0.25, 0.25), y: y + rng.range(-0.25, 0.25), prop: rng.chance(0.6) ? 'tree_pine' : 'tree_oak', v: rng.int(0, 9), s: rng.range(0.85, 1.15) });
            if (rng.chance(0.35)) this.props.push({ x: x + rng.range(-0.45, 0.45), y: y + rng.range(-0.45, 0.45), prop: rng.chance(0.7) ? 'tree_pine' : 'bush', v: rng.int(0, 9), s: rng.range(0.7, 1) });
          } else if (!clear && rng.chance(0.05)) {
            this.props.push({ x, y, prop: rng.pick(['rock_small', 'bush', 'bush', 'rock_large']), v: rng.int(0, 9), s: 0.9 });
          } else if (!clear && f > 0.42 && rng.chance(0.25) && !nearNode(x, y, 3.8)) {
            this.props.push({ x: x + rng.range(-0.3, 0.3), y: y + rng.range(-0.3, 0.3), prop: rng.chance(0.5) ? 'tree_oak' : 'tree_pine', v: rng.int(0, 9), s: rng.range(0.8, 1.05) });
          }
          if (f < 0.32 && !nearRoad(x, y, 2.6) && !nearNode(x, y, 3.2) && fbm(x * 0.2, y * 0.2, ex.seed + 9) > 0.55) h = 1;
          if (fbm(x * 0.3, y * 0.3, ex.seed + 3) > 0.66 && terrain === 'grass') terrain = 'dirt';
        }
        tiles.push({ x, y, h, terrain });
      }
    }
    // Decorative ring of forest beyond the map.
    const B = 9;
    for (let y = -B; y < SIZE + B; y++)
      for (let x = -B; x < SIZE + B; x++) {
        if (x >= 0 && y >= 0 && x < SIZE && y < SIZE) continue;
        const d = Math.max(-x, -y, x - (SIZE - 1), y - (SIZE - 1));
        if (d > 6) continue;
        if (rng.chance(0.8)) this.props.push({ x: x + rng.range(-0.3, 0.3), y: y + rng.range(-0.3, 0.3), prop: rng.chance(0.6) ? 'tree_pine' : 'tree_oak', v: rng.int(0, 9), s: rng.range(0.85, 1.2) });
      }
    this.terrain = buildTerrain({
      w: SIZE,
      h: SIZE,
      border: B,
      tiles,
      seed: ex.seed,
      palette: 'map',
      roads: [...this.roads.values()],
      decals: false,
      res: 14,
      scale: 0.5,
    });
    this.props.sort((a, b) => a.x + a.y - (b.x + b.y));
    // Fog puffs on a jittered lattice.
    for (let y = -6; y < SIZE + 6; y += 1.7)
      for (let x = -6; x < SIZE + 6; x += 1.7) this.fog.push({ x: x + hash2(x * 10, y * 10) * 1.2, y: y + hash2(y * 10, x * 10) * 1.2, a: 1, r: 1 + hash2(x, y, 4) * 0.8 });
    this.shownNode = ex.current;
    const cur = ex.nodes.find((n) => n.id === ex.current)!;
    this.token = { x: cur.tx, y: cur.ty };
    // Look up the road toward the objective rather than at the map corner.
    const obj = ex.nodes.find((n) => n.type === 'objective')!;
    const fx = cur.tx + (obj.tx - cur.tx) * 0.22;
    const fy = cur.ty + (obj.ty - cur.ty) * 0.22;
    this.cam = makeCamera(isoX(fx, fy), isoY(fx, fy) - 60, 0.6);
    this.atmo = new Atmosphere(ex.seed);
    this.buildHorde(ex);
    if (ex.marches === 0 && this.horde) {
      const p = this.hordeAt(this.horde.front - 0.1, 0);
      this.intro = { t: 0, from: { x: isoX(p.x, p.y), y: isoY(p.x, p.y) - 40, z: 0.5 }, to: { x: this.cam.x, y: this.cam.y, z: this.cam.zoom } };
      this.cam.x = this.cam.tx = this.intro.from.x;
      this.cam.y = this.cam.ty = this.intro.from.y;
      this.cam.zoom = this.cam.tzoom = this.intro.from.z;
    }
    this.updateFog(1);
    window.addEventListener('keyup', this.keyUp);
  }

  /**
   * The host coming down on Brannsted from beyond the far corner. Positions
   * are given along the line from the objective (t = 0) toward the start
   * (t = 1); the host lives at negative t and edges closer with every march.
   */
  private buildHorde(ex: Expedition) {
    const obj = ex.nodes.find((n) => n.type === 'objective');
    const start = ex.nodes.find((n) => n.type === 'start');
    if (!obj || !start) return;
    const dx = start.tx - obj.tx;
    const dy = start.ty - obj.ty;
    const len = Math.hypot(dx, dy) || 1;
    const rng = new Rng((ex.seed ^ 0x6a09) >>> 0);
    const kinds = ['goblin_rabble', 'goblin_rabble', 'goblin_spear', 'goblin_spear', 'goblin_archer', 'orc_warrior', 'orc_brute', 'wolf_rider'];
    const bands = [];
    for (let i = 0; i < 20; i++) {
      // Depth behind the host's front: the whole mass follows the front forward.
      const t = rng.range(0.025, 0.24);
      const s = rng.range(-11, 11);
      const figs = [];
      const n = rng.int(9, 15);
      const kind = rng.pick(kinds);
      for (let k = 0; k < n; k++) {
        // Facing down the road toward Brannsted: front views, some mirrored.
        const flip = rng.chance(0.5);
        figs.push({ a: rng.range(-0.03, 0.03), b: rng.range(-1.3, 1.3), key: `${kind === 'wolf_rider' && k % 3 ? 'goblin_rabble' : kind}_idle_f`, v: rng.int(0, 5), flip, banner: k === 0 });
      }
      bands.push({ t, s, figs });
    }
    const fires = [];
    for (let i = 0; i < 8; i++) fires.push({ t: rng.range(0.0, 0.3), s: rng.range(-11, 11), k: rng.range(0, 1) });
    this.horde = { ox: obj.tx, oy: obj.ty, ux: dx / len, uy: dy / len, len, bands, fires, front: this.frontFor(ex) };
  }

  /** How far the host has come: closer to Brannsted with every march, at its walls by the end. */
  private frontFor(ex: Expedition): number {
    return Math.min(-0.03, -0.27 + ex.marches * 0.048);
  }

  /** Grid point at `t` along the host's line and `s` tiles across it. */
  private hordeAt(t: number, s: number) {
    const h = this.horde!;
    return { x: h.ox + h.ux * h.len * t - h.uy * s, y: h.oy + h.uy * h.len * t + h.ux * s };
  }

  /**
   * Behind the front the land is scorched and smoking; the host's warbands
   * mass there under their standards, and burning farms send up smoke. Drawn
   * over the fog: the horde is seen from afar even where scouts have not been.
   */
  private drawHorde(ctx: CanvasRenderingContext2D, time: number) {
    const h = this.horde;
    if (!h) return;
    // Scorched land: a reddish-dark wash deepening away from the front, on the land only.
    const a = this.hordeAt(h.front, -30);
    const b = this.hordeAt(h.front, 30);
    const c = this.hordeAt(h.front - 0.5, 30);
    const d = this.hordeAt(h.front - 0.5, -30);
    const p0 = this.hordeAt(h.front, 0);
    const p1 = this.hordeAt(h.front - 0.3, 0);
    ctx.save();
    const E = 8;
    ctx.beginPath();
    for (const [i, [gx, gy]] of [[-E, -E], [SIZE + E, -E], [SIZE + E, SIZE + E], [-E, SIZE + E]].entries()) (i ? ctx.lineTo(isoX(gx, gy), isoY(gx, gy)) : ctx.moveTo(isoX(gx, gy), isoY(gx, gy)));
    ctx.closePath();
    ctx.clip();
    const g = ctx.createLinearGradient(isoX(p0.x, p0.y), isoY(p0.x, p0.y), isoX(p1.x, p1.y), isoY(p1.x, p1.y));
    g.addColorStop(0, 'rgba(60,20,10,0)');
    g.addColorStop(0.18, 'rgba(70,24,12,0.38)');
    g.addColorStop(1, 'rgba(36,12,8,0.62)');
    ctx.fillStyle = g;
    ctx.beginPath();
    for (const [i, q] of [a, b, c, d].entries()) (i ? ctx.lineTo(isoX(q.x, q.y), isoY(q.x, q.y)) : ctx.moveTo(isoX(q.x, q.y), isoY(q.x, q.y)));
    ctx.closePath();
    ctx.fill();
    // Fire-glow along the front.
    ctx.globalCompositeOperation = 'lighter';
    for (const f of h.fires) {
      const p = this.hordeAt(h.front - f.t, f.s);
      const x = isoX(p.x, p.y);
      const y = isoY(p.x, p.y);
      const r = 70 + 18 * Math.sin(time * 3 + f.k * 9);
      const gl = ctx.createRadialGradient(x, y, 4, x, y, r);
      gl.addColorStop(0, 'rgba(255,140,50,0.55)');
      gl.addColorStop(1, 'rgba(255,90,30,0)');
      ctx.fillStyle = gl;
      ctx.fillRect(x - r, y - r, r * 2, r * 2);
    }
    ctx.globalCompositeOperation = 'source-over';
    // The warbands, dark against the smoke, drifting toward Brannsted.
    const bands = h.bands.slice().sort((p, q) => q.t - p.t);
    for (const bd of bands) {
      const drift = Math.sin(time * 0.4 + bd.s) * 0.004;
      const figs = bd.figs.map((f) => ({ f, p: this.hordeAt(h.front - bd.t + f.a + drift, bd.s + f.b) })).sort((p, q) => p.p.x + p.p.y - (q.p.x + q.p.y));
      for (const { f, p } of figs) {
        const x = isoX(p.x, p.y);
        const y = isoY(p.x, p.y) + Math.sin(time * 6 + f.b * 5) * 0.8;
        if (f.banner) {
          drawSprite(ctx, sprite('war_banner', f.v), x, y, { scale: 0.55, alpha: 0.95 });
          continue;
        }
        const s = sprite(f.key, f.v);
        drawSprite(ctx, s, x, y, { flip: f.flip, scale: 0.46, alpha: 0.95 });
        drawSprite(ctx, s, x, y, { flip: f.flip, scale: 0.46, alpha: 0.4, img: shadowOf(s) });
      }
    }
    ctx.restore();
    this.hordeFx.drawAir(ctx);
  }

  dispose() {
    window.removeEventListener('keyup', this.keyUp);
  }

  private keyUp = (e: KeyboardEvent) => this.keys.delete(e.key.toLowerCase());

  subscribe(fn: () => void) {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  private notify() {
    this.ui.version++;
    for (const l of this.listeners) l();
  }

  private updateFog(rate: number) {
    const ex = this.getEx();
    if (!ex) return;
    const known = ex.nodes.filter((n) => n.revealed);
    for (const f of this.fog) {
      let d = Infinity;
      for (const n of known) d = Math.min(d, Math.hypot(n.tx - f.x, n.ty - f.y) - (n.visited ? 1.5 : 0));
      const edge = Math.max(0, Math.max(-f.x, -f.y, f.x - (SIZE - 1), f.y - (SIZE - 1)) + 2) / 3;
      const unknown = clamp((d - 5) / 5, 0, 1);
      const target = clamp(Math.max(unknown * 0.4, edge), 0, 1) * (0.55 + 0.35 * hash2(f.x * 3, f.y * 3, 11));
      f.a += (target - f.a) * rate;
    }
  }

  update(dt: number) {
    const ex = this.getEx();
    const pan = (700 * dt) / this.cam.zoom;
    if (this.keys.has('w') || this.keys.has('arrowup')) this.cam.ty -= pan;
    if (this.keys.has('s') || this.keys.has('arrowdown')) this.cam.ty += pan;
    if (this.keys.has('a') || this.keys.has('arrowleft')) this.cam.tx -= pan;
    if (this.keys.has('d') || this.keys.has('arrowright')) this.cam.tx += pan;
    // Keep the view over the map.
    const cx = isoX(SIZE / 2, SIZE / 2);
    const cy = isoY(SIZE / 2, SIZE / 2);
    const rx = (SIZE * TW) / 2 - this.w / (2 * this.cam.zoom) + 200;
    const ry = (SIZE * TH) / 2 - this.h / (2 * this.cam.zoom) + 150;
    this.cam.tx = clamp(this.cam.tx, cx - Math.max(0, rx), cx + Math.max(0, rx));
    this.cam.ty = clamp(this.cam.ty, cy - Math.max(0, ry), cy + Math.max(0, ry));
    if (this.intro) {
      // Hold on the host for a moment, then sweep back to the company.
      const it = this.intro;
      it.t += dt;
      const k = clamp((it.t - 2.2) / 2.6, 0, 1);
      const e = k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
      this.cam.x = this.cam.tx = it.from.x + (it.to.x - it.from.x) * e;
      this.cam.y = this.cam.ty = it.from.y + (it.to.y - it.from.y) * e;
      this.cam.zoom = this.cam.tzoom = it.from.z + (it.to.z - it.from.z) * e;
      if (k >= 1 || this.march) this.intro = null;
    } else updateCamera(this.cam, dt);
    this.atmo.update(dt, this.w, this.h);
    this.fx.update(dt);
    // The host creeps forward as the company marches.
    if (this.horde && ex) {
      const want = this.frontFor(ex);
      this.horde.front += (want - this.horde.front) * Math.min(1, dt * 0.8);
      for (const f of this.horde.fires) {
        f.k += dt;
        if (f.k > 0.32) {
          f.k = 0;
          const p = this.hordeAt(this.horde.front - f.t, f.s);
          this.hordeFx.burst(isoX(p.x, p.y) + (Math.random() - 0.5) * 24, isoY(p.x, p.y), 30, 1, { shape: 'puff', color: Math.random() < 0.4 ? 'rgba(60,50,46,1)' : 'rgba(96,86,80,1)', speed: 8, vz: 40, gravity: -6, size: 26, max: 6, drag: 0.15 });
        }
      }
    }
    this.hordeFx.update(dt);
    this.updateFog(Math.min(1, dt * 1.5));
    if (ex && ex.current !== this.shownNode && !this.march) {
      const road = this.roads.get(`${this.shownNode}>${ex.current}`);
      const target = ex.nodes.find((n) => n.id === ex.current)!;
      this.march = { path: road ?? [this.token, { x: target.tx, y: target.ty }], t: 0, dur: 1.8 };
      this.ui.marching = true;
      sfx('march');
      this.notify();
    }
    if (this.march) {
      const m = this.march;
      m.t += dt;
      const f = Math.min(1, m.t / m.dur);
      const e = f < 0.5 ? 2 * f * f : 1 - Math.pow(-2 * f + 2, 2) / 2;
      const idx = e * (m.path.length - 1);
      const i = Math.min(m.path.length - 2, Math.floor(idx));
      const k = idx - i;
      this.token = { x: m.path[i].x + (m.path[i + 1].x - m.path[i].x) * k, y: m.path[i].y + (m.path[i + 1].y - m.path[i].y) * k };
      this.cam.tx = isoX(this.token.x, this.token.y);
      this.cam.ty = isoY(this.token.x, this.token.y) - 60;
      if (Math.random() < dt * 14) {
        this.fx.burst(isoX(this.token.x, this.token.y), isoY(this.token.x, this.token.y), 2, 2, { shape: 'puff', color: 'rgba(190,165,120,1)', speed: 20, vz: 20, gravity: 5, size: 7, max: 0.8 });
      }
      if (f >= 1) {
        this.march = null;
        this.shownNode = ex?.current ?? this.shownNode;
        this.ui.marching = false;
        this.notify();
      }
    }
  }

  get marching() {
    return !!this.march;
  }

  focusCurrent() {
    const ex = this.getEx();
    if (!ex) return;
    const n = ex.nodes.find((x) => x.id === ex.current)!;
    const obj = ex.nodes.find((x) => x.type === 'objective')!;
    const fx = n.tx + (obj.tx - n.tx) * 0.18;
    const fy = n.ty + (obj.ty - n.ty) * 0.18;
    this.cam.tx = isoX(fx, fy);
    this.cam.ty = isoY(fx, fy) - 60;
  }

  private nodeAt(sx: number, sy: number): CNode | null {
    const ex = this.getEx();
    if (!ex) return null;
    const wpt = screenToWorld(this.cam, sx, sy, this.w, this.h);
    let best: CNode | null = null;
    let bd = 70;
    for (const n of ex.nodes) {
      const d = Math.hypot(isoX(n.tx, n.ty) - wpt.x, isoY(n.tx, n.ty) - 30 - wpt.y);
      if (d < bd) {
        bd = d;
        best = n;
      }
    }
    return best;
  }

  pointerMove(p: PointerInfo) {
    const n = this.nodeAt(p.x, p.y);
    const id = n?.id;
    if (id !== this.ui.hover) {
      this.ui.hover = id;
      this.notify();
    }
  }

  pointerDown(p: PointerInfo) {
    if (p.button !== 0 || this.march) return;
    const n = this.nodeAt(p.x, p.y);
    if (n) this.onNodeClick(n.id);
  }

  wheel(delta: number) {
    this.cam.tzoom = clamp(this.cam.tzoom * (delta > 0 ? 0.9 : 1.1), 0.25, 1.2);
  }

  key(e: KeyboardEvent) {
    const k = e.key.toLowerCase();
    if (['w', 'a', 's', 'd', 'arrowup', 'arrowdown', 'arrowleft', 'arrowright'].includes(k)) this.keys.add(k);
  }

  render(ctx: CanvasRenderingContext2D, w: number, h: number, time: number) {
    this.w = w;
    this.h = h;
    const ex = this.getEx();
    ctx.fillStyle = '#1b2812';
    ctx.fillRect(0, 0, w, h);
    ctx.save();
    ctx.translate(w / 2, h / 2);
    ctx.scale(this.cam.zoom, this.cam.zoom);
    ctx.translate(-this.cam.x, -this.cam.y);
    const tl = this.terrain;
    ctx.drawImage(tl.canvas, tl.ox, tl.oy, tl.canvas.width / tl.scale, tl.canvas.height / tl.scale);
    // Water shimmer.
    ctx.save();
    ctx.clip(tl.water);
    ctx.strokeStyle = 'rgba(220,245,255,0.3)';
    ctx.lineWidth = 2;
    for (const t of tl.waterTiles) {
      const ph = time * 0.7 + hash2(t.x, t.y) * 6;
      ctx.globalAlpha = 0.5 + 0.5 * Math.sin(ph);
      const cx = isoX(t.x, t.y) + Math.sin(ph) * 16;
      const cy = isoY(t.x, t.y);
      ctx.beginPath();
      ctx.moveTo(cx - 12, cy);
      ctx.quadraticCurveTo(cx, cy - 3, cx + 12, cy);
      ctx.stroke();
    }
    ctx.restore();
    this.atmo.drawClouds(ctx, isoX(SIZE / 2, SIZE / 2), isoY(SIZE / 2, SIZE / 2));
    if (ex) this.drawRoutes(ctx, ex, time);
    // Depth-sorted props, landmarks and the army.
    type Item = { d: number; draw: () => void };
    const items: Item[] = [];
    const zoomSkip = this.cam.zoom < 0.32;
    for (const p of this.props) {
      const s = sprite(p.prop, p.v);
      const x = isoX(p.x, p.y);
      const y = isoY(p.x, p.y);
      const flip = !s.noShadow && hash2(p.x * 7, p.y * 7) > 0.5;
      items.push({
        d: p.x + p.y,
        draw: () => {
          if (!zoomSkip) drawCastShadow(ctx, s, x, y, flip, p.s, 0.16);
          drawSprite(ctx, s, x, y, { flip, scale: p.s });
        },
      });
    }
    if (ex) {
      for (const n of ex.nodes) items.push({ d: n.tx + n.ty + 0.2, draw: () => this.drawNode(ctx, ex, n, time) });
      items.push({ d: this.token.x + this.token.y + 0.4, draw: () => this.drawArmy(ctx, ex, time) });
    }
    items.sort((a, b) => a.d - b.d);
    for (const it of items) it.draw();
    this.fx.drawAir(ctx);
    // Fog of war.
    for (const f of this.fog) {
      if (f.a < 0.02) continue;
      const x = isoX(f.x, f.y) + Math.sin(time * 0.2 + f.x) * 10;
      const y = isoY(f.x, f.y) - 30;
      const r = 150 * f.r;
      ctx.globalAlpha = 0.85 * f.a;
      ctx.drawImage(puff(), x - r, y - r, r * 2, r * 2);
    }
    ctx.globalAlpha = 1;
    this.drawHorde(ctx, time);
    if (ex) this.drawLabels(ctx, ex);
    ctx.restore();
    this.atmo.drawGrade(ctx, w, h, time);
  }

  private drawRoutes(ctx: CanvasRenderingContext2D, ex: Expedition, time: number) {
    const next = new Set(this.march ? [] : nextNodes(ex).map((n) => n.id));
    ctx.save();
    ctx.lineCap = 'round';
    for (const [k, pts] of this.roads) {
      const [a, b] = k.split('>');
      const travelled = ex.path.includes(a) && ex.path.includes(b) && ex.path.indexOf(b) === ex.path.indexOf(a) + 1;
      const open = a === ex.current && next.has(b);
      if (!travelled && !open) continue;
      ctx.strokeStyle = travelled ? 'rgba(60,90,200,0.7)' : 'rgba(255,225,130,0.95)';
      ctx.lineWidth = travelled ? 6 : 5;
      ctx.setLineDash(travelled ? [] : [10, 12]);
      ctx.lineDashOffset = -time * 40;
      ctx.beginPath();
      pts.forEach((p, i) => (i ? ctx.lineTo(isoX(p.x, p.y), isoY(p.x, p.y)) : ctx.moveTo(isoX(p.x, p.y), isoY(p.x, p.y))));
      ctx.stroke();
    }
    ctx.restore();
  }

  private drawNode(ctx: CanvasRenderingContext2D, ex: Expedition, n: CNode, time: number) {
    const x = isoX(n.tx, n.ty);
    const y = isoY(n.tx, n.ty);
    const view = nodeView(n);
    const reachable = !this.march && nextNodes(ex).some((m) => m.id === n.id);
    const hover = this.ui.hover === n.id;
    // Clearing under the landmark.
    ctx.save();
    ctx.fillStyle = 'rgba(40,30,15,0.18)';
    ctx.beginPath();
    ctx.ellipse(x, y, 90, 45, 0, 0, Math.PI * 2);
    ctx.fill();
    if (reachable || hover) {
      ctx.globalAlpha = 0.55 + 0.35 * Math.sin(time * 3);
      ctx.strokeStyle = hover ? '#fff3c4' : '#ffd76a';
      ctx.lineWidth = 4;
      ctx.beginPath();
      ctx.ellipse(x, y, 80, 40, 0, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.restore();
    if (view.type === 'unknown') {
      ctx.save();
      ctx.font = '700 64px Cinzel, Georgia, serif';
      ctx.textAlign = 'center';
      ctx.fillStyle = 'rgba(60,50,40,0.7)';
      ctx.fillText('?', x, y - 20);
      ctx.restore();
      return;
    }
    const s = sprite(`node_${view.type}`);
    const base = s.noShadow ? 0.92 : 1.4;
    ctx.save();
    if (n.visited && n.id !== ex.current) ctx.globalAlpha = 0.7;
    drawCastShadow(ctx, s, x, y, false, base, 0.2);
    drawSprite(ctx, s, x, y, { scale: base + (hover ? 0.06 : 0) });
    ctx.restore();
    if (n.type === 'objective' || (n.type === 'camp' && n.visited)) {
      // Smoke from fires.
      if (Math.random() < 0.15) this.fx.burst(x + 10, y - 60, 30, 1, { shape: 'puff', color: 'rgba(200,200,200,1)', speed: 6, vz: 30, gravity: -6, size: 12, max: 2.5, drag: 0.2 });
    }
  }

  private drawArmy(ctx: CanvasRenderingContext2D, ex: Expedition, time: number) {
    const x = isoX(this.token.x, this.token.y);
    const y = isoY(this.token.x, this.token.y);
    const bob = this.march ? Math.abs(Math.sin(time * 9)) * 4 : 0;
    // Banner bearer and a few soldiers.
    const types = ['footman', 'spearman', 'crossbowman'];
    const offs = [
      [-26, 8],
      [22, 12],
      [0, -10],
    ];
    for (let i = 0; i < 3; i++) {
      const s = sprite(`${types[i]}_idle_b`);
      const [ox, oy] = offs[i];
      drawCastShadow(ctx, s, x + ox, y + oy, false, 0.85, 0.2);
      drawSprite(ctx, s, x + ox, y + oy - bob * (i % 2 ? 1 : 0.6), { scale: 0.85 });
    }
    // Standard.
    ctx.save();
    ctx.strokeStyle = '#4a2f1c';
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.moveTo(x + 6, y - 6);
    ctx.lineTo(x + 6, y - 150);
    ctx.stroke();
    const wave = Math.sin(time * 4) * 6;
    ctx.fillStyle = '#2f58b8';
    ctx.strokeStyle = '#1a1208';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(x + 8, y - 148);
    ctx.quadraticCurveTo(x + 40, y - 150 + wave, x + 70, y - 140);
    ctx.lineTo(x + 66, y - 108);
    ctx.quadraticCurveTo(x + 38, y - 116 - wave, x + 8, y - 110);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = '#f2efe4';
    ctx.beginPath();
    ctx.moveTo(x + 38, y - 138);
    ctx.lineTo(x + 46, y - 128);
    ctx.lineTo(x + 38, y - 118);
    ctx.lineTo(x + 30, y - 128);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
    void ex;
  }

  private drawLabels(ctx: CanvasRenderingContext2D, ex: Expedition) {
    const z = this.cam.zoom;
    for (const n of ex.nodes) {
      const view = nodeView(n);
      if (view.type === 'unknown') continue;
      const x = isoX(n.tx, n.ty);
      const y = isoY(n.tx, n.ty) + 34;
      ctx.save();
      const size = 15 / Math.max(0.4, z);
      ctx.font = `600 ${size}px Cinzel, Georgia, serif`;
      ctx.textAlign = 'center';
      const label = view.title;
      const wdt = ctx.measureText(label).width + 18 / z;
      ctx.fillStyle = 'rgba(40,28,16,0.78)';
      ctx.fillRect(x - wdt / 2, y - size, wdt, size * 1.45);
      ctx.fillStyle = n.id === ex.current ? '#ffd76a' : '#f2e8cc';
      ctx.fillText(label, x, y + size * 0.15);
      ctx.restore();
    }
  }
}

export { TH, TW, worldToScreen };
