import { Rng, hash2 } from '../core/rng';
import { BUILDINGS } from '../data/buildings';
import type { GameState } from '../meta/game';
import { Atmosphere } from './atmosphere';
import { drawCastShadow, drawSprite, flashOf, hasArt, opaqueAt, sprite } from './assets';
import type { PointerInfo, Scene } from './engine';
import { Fx } from './fx';
import { clamp, isoX, isoY, makeCamera, screenToWorld, updateCamera, type Camera } from './iso';
import { buildTerrain, type GroundTile, type TerrainLayer } from './terrain';

const N = 16;
const HOME_Y = isoY(8, 8) - 30;
const HOME_ZOOM = 0.62;
/** Screen px kept clear above the highest nameplate (top bar) and below the lowest building. */
const TOP_CLEAR = 78;
const BOTTOM_CLEAR = 16;

interface Walker {
  type: string;
  variant: number;
  x: number;
  y: number;
  tx: number;
  ty: number;
  wait: number;
  facing: 0 | 1 | 2 | 3;
  phase: number;
}

export interface BaseUi {
  hover?: string;
  version: number;
}

const SPOTS: [number, number][] = [
  [6, 8], [10, 8], [8, 7], [6.4, 10], [9.4, 9.6], [12.6, 8.6], [5.6, 7], [10.6, 7], [8.8, 10.6], [13.4, 8.6], [7, 9.6], [11.2, 9.6],
];

export class BaseScene implements Scene {
  getGame: () => GameState | null;
  onBuilding: (id: string) => void;
  terrain: TerrainLayer;
  cam: Camera;
  atmo: Atmosphere;
  fx = new Fx();
  ui: BaseUi = { version: 0 };
  private listeners = new Set<() => void>();
  private props: { x: number; y: number; prop: string; v: number; s: number }[] = [];
  private stakes: { x: number; y: number }[] = [];
  private walkers: Walker[] = [];
  /** Nameplate rectangles in world space from the last frame, for hit-testing. */
  private plates = new Map<string, { x: number; y: number; w: number; h: number }>();
  private w = 1;
  private h = 1;
  private rng = new Rng(7);
  dim = false;

  constructor(getGame: () => GameState | null, onBuilding: (id: string) => void) {
    this.getGame = getGame;
    this.onBuilding = onBuilding;
    const tiles: GroundTile[] = [];
    const path = new Set<number>();
    const mark = (x: number, y: number) => path.add(y * 100 + x);
    const line = (ax0: number, ay0: number, bx0: number, by0: number) => {
      // Walk whole tiles: round the endpoints so the loop always terminates.
      const [ax, ay, bx, by] = [ax0, ay0, bx0, by0].map(Math.round);
      let x = ax;
      let y = ay;
      while (x !== bx || y !== by) {
        mark(x, y);
        if (x !== bx) x += Math.sign(bx - x);
        else y += Math.sign(by - y);
      }
      mark(bx, by);
    };
    const centre = [8, 8.6] as const;
    for (const b of BUILDINGS) line(b.pos[0], b.pos[1] + 1, centre[0], centre[1]);
    line(centre[0], centre[1], 15, centre[1]);
    for (let y = 0; y < N; y++)
      for (let x = 0; x < N; x++) {
        const inside = x >= 1 && y >= 1 && x <= 14 && y <= 14;
        let terrain = inside ? 'grass' : 'grass';
        if (path.has(y * 100 + x)) terrain = 'dirt';
        if (Math.hypot(x - centre[0], y - centre[1]) < 1.8) terrain = 'dirt';
        tiles.push({ x, y, h: 0, terrain });
      }
    this.terrain = buildTerrain({ w: N, h: N, border: 8, tiles, seed: 4242, palette: 'base', res: 22, scale: 0.75 });
    // Palisade along the perimeter, with a gate on the south-east side.
    for (let i = 1; i <= 14; i++) {
      this.stakes.push({ x: i, y: 0.6 }, { x: 0.6, y: i });
      if (!(i >= 8 && i <= 10)) this.stakes.push({ x: 14.4, y: i });
      this.stakes.push({ x: i, y: 14.4 });
    }
    const rng = new Rng(99);
    // Forest outside the walls.
    for (let y = -8; y < N + 8; y++)
      for (let x = -8; x < N + 8; x++) {
        const inside = x >= -1 && y >= -1 && x <= 16 && y <= 16;
        if (inside) continue;
        const nearRoad = Math.abs(y - centre[1]) < 1.6 && x > 14;
        if (nearRoad) continue;
        if (rng.chance(0.7)) this.props.push({ x: x + rng.range(-0.3, 0.3), y: y + rng.range(-0.3, 0.3), prop: rng.chance(0.6) ? 'tree_pine' : 'tree_oak', v: rng.int(0, 9), s: rng.range(0.85, 1.2) });
      }
    // Decor inside the walls.
    const decor: [number, number, string][] = [
      [8, 8.6, 'campfire'], [9.6, 10.4, 'crates'], [2.0, 2.2, 'crates'], [10.4, 1.8, 'crates'],
      [2.2, 13.4, 'bush'], [13.4, 13.4, 'bush'], [5.8, 2.0, 'rock_small'], [2.0, 8.0, 'fence_y'],
    ];
    for (const [x, y, p] of decor) this.props.push({ x, y, prop: p, v: Math.floor(x * 3 + y), s: 1 });
    const g = getGame();
    if (g) this.spawnWalkers(g);
    this.cam = makeCamera(isoX(8, 8), HOME_Y, HOME_ZOOM);
    this.atmo = new Atmosphere(77);
    window.addEventListener('keyup', this.keyUp);
  }

  private keys = new Set<string>();
  private keyUp = (e: KeyboardEvent) => this.keys.delete(e.key.toLowerCase());

  dispose() {
    window.removeEventListener('keyup', this.keyUp);
  }

  subscribe(fn: () => void) {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  private notify() {
    this.ui.version++;
    for (const l of this.listeners) l();
  }

  spawnWalkers(g: GameState) {
    this.walkers = g.roster.slice(0, 9).map((s, i) => {
      const [x, y] = SPOTS[i % SPOTS.length];
      return { type: s.typeId, variant: s.variant, x, y, tx: x, ty: y, wait: 1 + i * 0.7, facing: 1, phase: i * 1.7 };
    });
  }

  update(dt: number) {
    const pan = (600 * dt) / this.cam.zoom;
    if (this.keys.has('w') || this.keys.has('arrowup')) this.cam.ty -= pan;
    if (this.keys.has('s') || this.keys.has('arrowdown')) this.cam.ty += pan;
    if (this.keys.has('a') || this.keys.has('arrowleft')) this.cam.tx -= pan;
    if (this.keys.has('d') || this.keys.has('arrowright')) this.cam.tx += pan;
    updateCamera(this.cam, dt);
    this.atmo.update(dt, this.w, this.h);
    this.fx.update(dt);
    for (const w of this.walkers) {
      if (w.wait > 0) {
        w.wait -= dt;
        if (w.wait <= 0) {
          const [tx, ty] = this.rng.pick(SPOTS);
          w.tx = tx + this.rng.range(-0.4, 0.4);
          w.ty = ty + this.rng.range(-0.4, 0.4);
        }
        continue;
      }
      const dx = w.tx - w.x;
      const dy = w.ty - w.y;
      const d = Math.hypot(dx, dy);
      if (d < 0.05) {
        w.wait = 2 + this.rng.next() * 5;
        continue;
      }
      const sp = 0.9 * dt;
      w.x += (dx / d) * Math.min(sp, d);
      w.y += (dy / d) * Math.min(sp, d);
      w.phase += dt * 9;
      w.facing = Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? 0 : 2) : dy > 0 ? 1 : 3;
    }
    // Campfire smoke and sparks.
    if (Math.random() < dt * 6) this.fx.burst(isoX(8, 8.6), isoY(8, 8.6) - 20, 10, 1, { shape: 'puff', color: 'rgba(210,210,205,1)', speed: 6, vz: 40, gravity: -8, size: 10, max: 3, drag: 0.2 });
    if (Math.random() < dt * 4) this.fx.burst(isoX(8, 8.6), isoY(8, 8.6) - 10, 5, 1, { shape: 'dot', color: '#ffb347', speed: 10, vz: 60, gravity: -10, size: 2.5, max: 1.4, drag: 0.5 });
  }

  private framed = '';

  /**
   * Frames the camp for the viewport and building levels. The home view is
   * kept whenever it shows every building and nameplate; on short viewports
   * the camera rises until the tallest nameplate clears the top bar, and zooms
   * out only if the camp then no longer fits.
   */
  private frame(g: GameState, w: number, h: number) {
    const key = `${w}x${h}:${BUILDINGS.map((b) => g.buildings[b.id] ?? 1).join('')}`;
    if (key === this.framed) return;
    const first = !this.framed;
    this.framed = key;
    let top = Infinity;
    let bottom = -Infinity;
    for (const b of BUILDINGS) {
      const s = sprite(`b_${b.id}_${g.buildings[b.id] ?? 1}`);
      const y = isoY(b.pos[0], b.pos[1]);
      top = Math.min(top, y - s.ay * s.scale);
      bottom = Math.max(bottom, y + (s.h - s.ay) * s.scale);
    }
    let zoom = HOME_ZOOM;
    let cy = HOME_Y;
    if ((top - cy) * zoom + h / 2 < TOP_CLEAR) cy = top + (h / 2 - TOP_CLEAR) / zoom;
    if ((bottom - cy) * zoom + h / 2 > h - BOTTOM_CLEAR) {
      zoom = Math.max(0.4, (h - TOP_CLEAR - BOTTOM_CLEAR) / (bottom - top));
      cy = top + (h / 2 - TOP_CLEAR) / zoom;
    }
    this.cam.tx = isoX(8, 8);
    this.cam.ty = cy;
    this.cam.tzoom = zoom;
    if (first) {
      this.cam.x = this.cam.tx;
      this.cam.y = cy;
      this.cam.zoom = zoom;
    }
  }

  private buildingAt(sx: number, sy: number): string | undefined {
    const g = this.getGame();
    if (!g) return undefined;
    const wp = screenToWorld(this.cam, sx, sy, this.w, this.h);
    const placed = BUILDINGS.map((b) => {
      const s = sprite(`b_${b.id}_${g.buildings[b.id] ?? 1}`);
      return { b, s, x: isoX(b.pos[0], b.pos[1]), y: isoY(b.pos[0], b.pos[1]) };
    }).sort((p, q) => q.b.pos[0] + q.b.pos[1] - (p.b.pos[0] + p.b.pos[1]));
    // Nameplates are drawn on top, then sprites front to back: the first
    // opaque hit is the building the player sees under the cursor.
    for (const [id, r] of this.plates) if (wp.x >= r.x && wp.x <= r.x + r.w && wp.y >= r.y && wp.y <= r.y + r.h) return id;
    for (const p of placed) if (opaqueAt(p.s, (wp.x - p.x) / p.s.scale + p.s.ax, (wp.y - p.y) / p.s.scale + p.s.ay)) return p.b.id;
    // Open ground inside a building's plot (the drill field between dummies).
    let best: string | undefined;
    let bd = Infinity;
    for (const { b, s, x, y } of placed) {
      const top = y - s.ay * s.scale;
      const half = (s.w * s.scale) / 2;
      if (wp.x > x - half * 0.8 && wp.x < x + half * 0.8 && wp.y > top + 10 && wp.y < y + 30) {
        const d = Math.abs(wp.x - x) + Math.abs(wp.y - (y - 60));
        if (d < bd) {
          bd = d;
          best = b.id;
        }
      }
    }
    return best;
  }

  pointerMove(p: PointerInfo) {
    const id = this.dim ? undefined : this.buildingAt(p.x, p.y);
    if (id !== this.ui.hover) {
      this.ui.hover = id;
      this.notify();
    }
  }

  pointerDown(p: PointerInfo) {
    if (p.button !== 0 || this.dim) return;
    const id = this.buildingAt(p.x, p.y);
    if (id) this.onBuilding(id);
  }

  wheel(delta: number) {
    this.cam.tzoom = clamp(this.cam.tzoom * (delta > 0 ? 0.9 : 1.1), 0.4, 1.3);
  }

  key(e: KeyboardEvent) {
    const k = e.key.toLowerCase();
    if (['w', 'a', 's', 'd', 'arrowup', 'arrowdown', 'arrowleft', 'arrowright'].includes(k)) this.keys.add(k);
  }

  render(ctx: CanvasRenderingContext2D, w: number, h: number, time: number) {
    this.w = w;
    this.h = h;
    const g = this.getGame();
    if (g) this.frame(g, w, h);
    ctx.fillStyle = '#1b2812';
    ctx.fillRect(0, 0, w, h);
    ctx.save();
    ctx.translate(w / 2, h / 2);
    ctx.scale(this.cam.zoom, this.cam.zoom);
    ctx.translate(-this.cam.x, -this.cam.y);
    const tl = this.terrain;
    ctx.drawImage(tl.canvas, tl.ox, tl.oy, tl.canvas.width / tl.scale, tl.canvas.height / tl.scale);
    this.atmo.drawClouds(ctx, isoX(8, 8), isoY(8, 8));
    type Item = { d: number; draw: () => void };
    const items: Item[] = [];
    for (const p of this.props) {
      const s = sprite(p.prop, p.v);
      const x = isoX(p.x, p.y);
      const y = isoY(p.x, p.y);
      const flip = !s.noShadow && hash2(p.x * 9, p.y * 9) > 0.5;
      items.push({
        d: p.x + p.y,
        draw: () => {
          drawCastShadow(ctx, s, x, y, flip, p.s, 0.16);
          drawSprite(ctx, s, x, y, { flip, scale: p.s, rot: p.prop.startsWith('tree') ? Math.sin(time * 0.9 + p.x) * 0.01 : 0 });
        },
      });
    }
    const palisadeArt = hasArt('palisade_x') && hasArt('palisade_y');
    for (const st of this.stakes) {
      if (palisadeArt) {
        const alongX = st.y === 0.6 || st.y === 14.4;
        const ps = sprite(alongX ? 'palisade_x' : 'palisade_y', Math.floor(st.x * 3 + st.y * 7));
        items.push({ d: st.x + st.y, draw: () => drawSprite(ctx, ps, isoX(st.x, st.y), isoY(st.x, st.y)) });
      } else {
        items.push({ d: st.x + st.y, draw: () => this.drawStakes(ctx, st.x, st.y) });
      }
    }
    if (hasArt('gate_tower')) {
      for (const [gx, gy] of [[14.5, 7.4], [14.5, 10.6]] as const) {
        const gs = sprite('gate_tower');
        items.push({ d: gx + gy + 0.2, draw: () => drawSprite(ctx, gs, isoX(gx, gy), isoY(gx, gy)) });
      }
    }
    if (g) {
      for (const b of BUILDINGS) {
        const lvl = g.buildings[b.id] ?? 1;
        const s = sprite(`b_${b.id}_${lvl}`);
        const x = isoX(b.pos[0], b.pos[1]);
        const y = isoY(b.pos[0], b.pos[1]);
        const hov = this.ui.hover === b.id;
        items.push({
          d: b.pos[0] + b.pos[1] + 0.6,
          draw: () => {
            drawCastShadow(ctx, s, x, y, false, 1, 0.2);
            drawSprite(ctx, s, x, y);
            if (hov) {
              ctx.save();
              ctx.globalCompositeOperation = 'lighter';
              drawSprite(ctx, s, x, y, { alpha: 0.18 + 0.06 * Math.sin(time * 5), img: flashOf(s) });
              ctx.restore();
            }
          },
        });
      }
    }
    for (const wk of this.walkers) {
      const front = wk.facing === 0 || wk.facing === 1;
      const flip = wk.facing === 0 || wk.facing === 2;
      const s = sprite(`${wk.type}_idle_${front ? 'f' : 'b'}`, wk.variant);
      const x = isoX(wk.x, wk.y);
      const walking = wk.wait <= 0;
      const y = isoY(wk.x, wk.y) - (walking ? Math.abs(Math.sin(wk.phase)) * 4 : 0);
      items.push({
        d: wk.x + wk.y + 0.1,
        draw: () => {
          ctx.fillStyle = 'rgba(20,25,10,0.3)';
          ctx.beginPath();
          ctx.ellipse(x, isoY(wk.x, wk.y) + 2, 22, 10, 0, 0, Math.PI * 2);
          ctx.fill();
          drawSprite(ctx, s, x, y, { flip, scale: 0.8, sy: 1 + Math.sin(time * 2 + wk.phase) * 0.012 });
        },
      });
    }
    items.sort((a, b) => a.d - b.d);
    for (const it of items) it.draw();
    this.fx.drawAir(ctx);
    // Nameplates.
    if (g && !this.dim) {
      for (const b of BUILDINGS) {
        const lvl = g.buildings[b.id] ?? 1;
        const s = sprite(`b_${b.id}_${lvl}`);
        const x = isoX(b.pos[0], b.pos[1]);
        const y = isoY(b.pos[0], b.pos[1]) - s.ay * s.scale + 6;
        const name = b.levels[lvl - 1].name;
        const hov = this.ui.hover === b.id;
        const z = this.cam.zoom;
        const size = (hov ? 17 : 15) / Math.max(0.5, z);
        ctx.save();
        ctx.font = `700 ${size}px Cinzel, Georgia, serif`;
        ctx.textAlign = 'center';
        const tw = ctx.measureText(name).width + 22 / z;
        this.plates.set(b.id, { x: x - tw / 2, y: y - size * 1.1, w: tw, h: size * 1.5 });
        ctx.fillStyle = hov ? 'rgba(70,45,20,0.92)' : 'rgba(40,28,16,0.8)';
        ctx.fillRect(x - tw / 2, y - size * 1.1, tw, size * 1.5);
        ctx.strokeStyle = hov ? '#ffd76a' : 'rgba(200,170,110,0.6)';
        ctx.lineWidth = 1.5 / z;
        ctx.strokeRect(x - tw / 2, y - size * 1.1, tw, size * 1.5);
        ctx.fillStyle = hov ? '#ffe9a8' : '#efe3c4';
        ctx.fillText(name, x, y);
        ctx.restore();
      }
    }
    ctx.restore();
    this.atmo.drawGrade(ctx, w, h, time);
    if (this.dim) {
      ctx.fillStyle = 'rgba(15,10,5,0.45)';
      ctx.fillRect(0, 0, w, h);
    }
  }

  private drawStakes(ctx: CanvasRenderingContext2D, gx: number, gy: number) {
    const x = isoX(gx, gy);
    const y = isoY(gx, gy);
    for (let i = -1; i <= 1; i++) {
      const sx = x + i * 20 * (gx === 14.4 || gx === 0.6 ? -1 : 1);
      const sy = y + i * 10;
      const hgt = 56 + hash2(gx * 13 + i, gy * 7) * 14;
      ctx.fillStyle = '#7a5532';
      ctx.strokeStyle = '#2a1d14';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(sx - 7, sy);
      ctx.lineTo(sx - 7, sy - hgt);
      ctx.lineTo(sx, sy - hgt - 12);
      ctx.lineTo(sx + 7, sy - hgt);
      ctx.lineTo(sx + 7, sy);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = 'rgba(255,230,180,0.25)';
      ctx.fillRect(sx - 6, sy - hgt, 4, hgt);
    }
  }
}
