// War engines in the figures' look: ballista, mangonel, the goblins' rock
// lobber and war wagon. Each engine is built once as a small 3D rig in its own
// frame (f forward, s across toward the camera's side, h up; ground centre at
// the origin), projected to the battle's 3/4 view, every face cel-shaded by
// the warm upper-left light and outlined in ink, and drawn back to front.
// Front poses (`_f`) aim down-left toward the camera, back poses up-right.
// Units match drawFigure: a standing human is about 120 tall.

import { Rng } from '../core/rng';
import { GOLD, INK, STEEL, STEEL_D, poly, shade, skull, type Pose } from './figures';

type V = [number, number, number];

const add = (a: V, b: V): V => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const sub = (a: V, b: V): V => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const mul = (a: V, k: number): V => [a[0] * k, a[1] * k, a[2] * k];
const dot = (a: V, b: V) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a: V, b: V): V => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const len = (a: V) => Math.hypot(a[0], a[1], a[2]);
const norm = (a: V): V => mul(a, 1 / (len(a) || 1));
const lerp = (a: V, b: V, t: number): V => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];

/** World axes: E (screen down-right), S (screen down-left), U (up). */
const LIGHT = norm([-0.55, -0.2, 0.8]);
const VIEW = norm([1, 1, 0.9]);

// Palette.
const TIMBER = '#8a6038';
const TIMBER_D = '#6a4628';
const PLANK = '#a07443';
const IRON = '#5a5f66';
const ROPE = '#c9b48a';
const BLUE = '#2f58b8';
const BLUE_D = '#1f3f8c';
const CRUDE = '#6e5236';
const CRUDE_D = '#55402a';
const RED = '#b3261c';
const RED_D = '#7a2a1c';
const BURLAP = '#9a8458';
const STONE = '#9d9b8c';

/** Colour of a face with outward world normal `n`. */
function lit(col: string, n: V): string {
  const l = dot(n, LIGHT);
  return shade(col, l >= 0 ? l * 0.18 : l * 0.45);
}

interface Part {
  lo: V;
  hi: V;
  x0: number;
  y0: number;
  x1: number;
  y1: number;
  d: number;
  layer: number;
  draw: () => void;
}

type Pt = [number, number];

interface BeamOpts {
  lw?: number;
  grain?: boolean;
  up?: V;
  bias?: number;
}

interface CylOpts {
  n?: number;
  cap?: string;
  bands?: number[];
  bandCol?: string;
  lw?: number;
  bias?: number;
  open?: boolean;
}

interface WheelOpts {
  spokes?: number;
  wood?: string;
  tyre?: string;
  crude?: boolean;
  seed?: number;
  /** A hub cap in this colour (company paint). */
  hub?: string;
  /** Wheel lying flat on the ground (wrecks): the axis is vertical. */
  flat?: boolean;
}

/**
 * The 3D rig: primitives are projected as they are added (through the current
 * stack of local transforms) and drawn in back-to-front order by render().
 */
class Rig {
  readonly parts: Part[] = [];
  private stack: ((p: V) => V)[] = [];
  constructor(
    readonly x: CanvasRenderingContext2D,
    readonly back: boolean,
  ) {}

  /** Run `fn` with every point first passed through `t` (local transforms nest). */
  with(t: (p: V) => V, fn: () => void) {
    this.stack.push(t);
    fn();
    this.stack.pop();
  }

  /** Local point → world (E, S, U). */
  w(p: V): V {
    let q = p;
    for (let i = this.stack.length - 1; i >= 0; i--) q = this.stack[i](q);
    return this.back ? [q[1], -q[0], q[2]] : [q[1], q[0], q[2]];
  }

  P(p: V): Pt {
    return scr(this.w(p));
  }

  /** World direction of a local direction at a point. */
  dir(at: V, d: V): V {
    return norm(sub(this.w(add(at, d)), this.w(at)));
  }

  part(world: V[], draw: () => void, layer = 0, bias = 0) {
    const lo: V = [Infinity, Infinity, Infinity];
    const hi: V = [-Infinity, -Infinity, -Infinity];
    let x0 = Infinity;
    let y0 = Infinity;
    let x1 = -Infinity;
    let y1 = -Infinity;
    let d = 0;
    for (const p of world) {
      for (let k = 0; k < 3; k++) {
        lo[k] = Math.min(lo[k], p[k]);
        hi[k] = Math.max(hi[k], p[k]);
      }
      const [sx, sy] = scr(p);
      x0 = Math.min(x0, sx);
      y0 = Math.min(y0, sy);
      x1 = Math.max(x1, sx);
      y1 = Math.max(y1, sy);
      d += p[0] + p[1] + p[2] * 0.9;
    }
    this.parts.push({ lo, hi, x0: x0 - 2, y0: y0 - 2, x1: x1 + 2, y1: y1 + 2, d: d / world.length + bias, layer, draw });
  }

  /** A convex solid from quads of local points (outward winding not needed). */
  solid(quads: V[][], col: string, lw = 2, grain: number[][] | null = null, bias = 0) {
    const wq = quads.map((q) => q.map((p) => this.w(p)));
    const all = wq.flat();
    const c = mul(all.reduce((a, b) => add(a, b), [0, 0, 0] as V), 1 / all.length);
    const faces: { pts: Pt[]; fill: string; g?: number[] }[] = [];
    wq.forEach((q, i) => {
      let n = norm(cross(sub(q[1], q[0]), sub(q[3], q[0])));
      const fc = mul(q.reduce((a, b) => add(a, b), [0, 0, 0] as V), 0.25);
      if (dot(n, sub(fc, c)) < 0) n = mul(n, -1);
      if (dot(n, VIEW) <= 0.01) return;
      faces.push({ pts: q.map(scr), fill: lit(col, n), g: grain?.[i] });
    });
    const x = this.x;
    this.part(all, () => {
      for (const f of faces) {
        path(x, f.pts);
        x.fillStyle = f.fill;
        x.fill();
        if (f.g) {
          // Grain lines along the face's long edges (planks, beams).
          x.save();
          x.clip();
          x.strokeStyle = shade(f.fill, -0.22);
          x.lineWidth = 1;
          const [a, b, cc, dd] = f.pts;
          for (const t of f.g) {
            x.beginPath();
            x.moveTo(a[0] + (dd[0] - a[0]) * t, a[1] + (dd[1] - a[1]) * t);
            x.lineTo(b[0] + (cc[0] - b[0]) * t, b[1] + (cc[1] - b[1]) * t);
            x.stroke();
          }
          x.restore();
          path(x, f.pts);
        }
        x.lineWidth = lw;
        x.strokeStyle = INK;
        x.stroke();
      }
    }, 0, bias);
  }

  /** A squared timber from a to b, `w` across and `t` thick. */
  beam(a: V, b: V, w: number, t: number, col: string, o: BeamOpts = {}) {
    const u = sub(b, a);
    let r: V = o.up ?? [0, 0, 1];
    if (len(cross(u, r)) < 1e-3 * len(u)) r = [1, 0, 0];
    const sv = mul(norm(cross(u, r)), w / 2);
    const uv = mul(norm(cross(cross(u, r), u)), t / 2);
    const C = (end: V, j: number, k: number) => add(add(end, mul(sv, j)), mul(uv, k));
    const quads: V[][] = [
      [C(a, -1, 1), C(b, -1, 1), C(b, 1, 1), C(a, 1, 1)],
      [C(a, -1, -1), C(b, -1, -1), C(b, 1, -1), C(a, 1, -1)],
      [C(a, 1, -1), C(b, 1, -1), C(b, 1, 1), C(a, 1, 1)],
      [C(a, -1, -1), C(b, -1, -1), C(b, -1, 1), C(a, -1, 1)],
      [C(a, -1, -1), C(a, 1, -1), C(a, 1, 1), C(a, -1, 1)],
      [C(b, -1, -1), C(b, 1, -1), C(b, 1, 1), C(b, -1, 1)],
    ];
    const long = len(u) > Math.max(w, t) * 2.5;
    const g = o.grain ?? long;
    const lines = (n: number) => Array.from({ length: n }, (_, i) => (i + 1) / (n + 1));
    const grain = g ? [lines(w > 14 ? 3 : 1), lines(1), lines(t > 14 ? 3 : 1), lines(t > 14 ? 3 : 1), [], []] : null;
    this.solid(quads, col, o.lw ?? 2, grain, o.bias ?? 0);
  }

  /** A cylinder (axle, log, skein, drum) from a to b of radius r. */
  cyl(a: V, b: V, r: number, col: string, o: CylOpts = {}) {
    const N = o.n ?? 16;
    const u = norm(sub(b, a));
    const p1 = norm(Math.abs(u[2]) < 0.9 ? cross(u, [0, 0, 1]) : cross(u, [1, 0, 0]));
    const p2 = cross(u, p1);
    const ring = (c: V, rr: number) => Array.from({ length: N }, (_, i) => {
      const t = (i / N) * Math.PI * 2;
      return add(c, add(mul(p1, Math.cos(t) * rr), mul(p2, Math.sin(t) * rr)));
    });
    const ra = ring(a, r).map((p) => this.w(p));
    const rb = ring(b, r).map((p) => this.w(p));
    const wu = norm(sub(this.w(b), this.w(a)));
    const capB = dot(wu, VIEW) > 0;
    const capPts = (capB ? rb : ra).map(scr);
    const hull = convexHull([...ra, ...rb].map(scr));
    const sa = scr(this.w(a));
    const sb = scr(this.w(b));
    const bands = (o.bands ?? []).map((t) => {
      const c = lerp(a, b, t);
      const rw = ring(c, r * 1.04).map((p) => this.w(p));
      // Only the half of the band facing the camera.
      const ctr = this.w(c);
      return rw.map((p) => ({ p: scr(p), vis: dot(sub(p, ctr), VIEW) > 0 }));
    });
    const capCol = lit(o.cap ?? shade(col, 0.15), capB ? wu : mul(wu, -1));
    const x = this.x;
    const lw = o.lw ?? 2;
    this.part([...ra, ...rb], () => {
      x.save();
      path(x, hull);
      x.fillStyle = col;
      x.fill();
      x.clip();
      // Shade the side away from the light, light the other.
      let ax = sb[0] - sa[0];
      let ay = sb[1] - sa[1];
      const al = Math.hypot(ax, ay);
      if (al > 0.5) {
        ax /= al;
        ay /= al;
        let nx = -ay;
        let ny = ax;
        if (nx * -0.6 + ny * -0.8 > 0) {
          nx = -nx;
          ny = -ny;
        }
        const k = r * 0.9;
        x.strokeStyle = shade(col, -0.32);
        x.lineWidth = r * 1.1;
        x.beginPath();
        x.moveTo(sa[0] + nx * k - ax * 400, sa[1] + ny * k - ay * 400);
        x.lineTo(sa[0] + nx * k + ax * 400, sa[1] + ny * k + ay * 400);
        x.stroke();
        x.strokeStyle = shade(col, 0.25);
        x.lineWidth = r * 0.35;
        x.beginPath();
        x.moveTo(sa[0] - nx * r * 0.55 - ax * 400, sa[1] - ny * r * 0.55 - ay * 400);
        x.lineTo(sa[0] - nx * r * 0.55 + ax * 400, sa[1] - ny * r * 0.55 + ay * 400);
        x.stroke();
      } else {
        x.fillStyle = shade(col, -0.3);
        x.fillRect(sa[0] + r * 0.2, sa[1] - 400, 400, 800);
      }
      for (const band of bands) {
        x.strokeStyle = INK;
        x.lineWidth = 4.4;
        strokeVisible(x, band);
        x.strokeStyle = o.bandCol ?? IRON;
        x.lineWidth = 2.4;
        strokeVisible(x, band);
      }
      x.restore();
      path(x, hull);
      x.lineWidth = lw;
      x.strokeStyle = INK;
      x.stroke();
      path(x, capPts);
      x.fillStyle = o.open ? shade(col, -0.55) : capCol;
      x.fill();
      x.lineWidth = lw * 0.8;
      x.stroke();
    }, 0, o.bias ?? 0);
  }

  /** A cone (spike, bolt head) from its base centre `a` to the point `b`. */
  cone(a: V, b: V, r: number, col: string, lw = 1.6) {
    const N = 10;
    const u = norm(sub(b, a));
    const p1 = norm(Math.abs(u[2]) < 0.9 ? cross(u, [0, 0, 1]) : cross(u, [1, 0, 0]));
    const p2 = cross(u, p1);
    const base = Array.from({ length: N }, (_, i) => {
      const t = (i / N) * Math.PI * 2;
      return this.w(add(a, add(mul(p1, Math.cos(t) * r), mul(p2, Math.sin(t) * r))));
    });
    const tip = this.w(b);
    const hull = convexHull([...base, tip].map(scr));
    const sa = scr(this.w(a));
    const st = scr(tip);
    const x = this.x;
    this.part([...base, tip], () => {
      x.save();
      path(x, hull);
      x.fillStyle = col;
      x.fill();
      x.clip();
      // Darken the half of the cone on the far side of its axis from the light.
      const ax = st[0] - sa[0];
      const ay = st[1] - sa[1];
      let nx = -ay;
      let ny = ax;
      if (nx * -0.6 + ny * -0.8 > 0) {
        nx = -nx;
        ny = -ny;
      }
      x.fillStyle = shade(col, -0.35);
      x.beginPath();
      x.moveTo(sa[0] - ax * 2, sa[1] - ay * 2);
      x.lineTo(st[0] + ax * 2, st[1] + ay * 2);
      x.lineTo(st[0] + nx * 40, st[1] + ny * 40);
      x.lineTo(sa[0] + nx * 40, sa[1] + ny * 40);
      x.closePath();
      x.fill();
      x.restore();
      path(x, hull);
      x.lineWidth = lw;
      x.strokeStyle = INK;
      x.stroke();
    });
  }

  /** A flat panel (plate, cloth, blade) through local points; `deco` draws on it. */
  flat(pts: V[], col: string, lw = 1.8, deco?: (x: CanvasRenderingContext2D, P: (p: V) => Pt) => void, bias = 0) {
    const wp = pts.map((p) => this.w(p));
    let n = norm(cross(sub(wp[1], wp[0]), sub(wp[2], wp[0])));
    if (dot(n, VIEW) < 0) n = mul(n, -1);
    const fill = lit(col, n);
    const sp = wp.map(scr);
    const x = this.x;
    const P = (p: V) => this.P(p);
    // Capture the transform stack for the decoration's own projections.
    const stack = [...this.stack];
    const self = this;
    this.part(wp, () => {
      path(x, sp);
      x.fillStyle = fill;
      x.fill();
      if (deco) {
        x.save();
        x.clip();
        const saved = self.stack;
        self.stack = stack;
        deco(x, P);
        self.stack = saved;
        x.restore();
        path(x, sp);
      }
      if (lw > 0) {
        x.lineWidth = lw;
        x.strokeStyle = INK;
        x.stroke();
      }
    }, 0, bias);
  }

  /**
   * A bent bar along a spine (a bow's prod): `widths` across per spine point,
   * `t` thick; its top and side strips are drawn whole so it reads as one piece.
   */
  bar(spine: V[], widths: number[], t: number, col: string, lw = 2, bands: number[] = [], bandCol = GOLD) {
    const n = spine.length;
    const up: V = [0, 0, 1];
    const TL: V[] = [];
    const TR: V[] = [];
    const BL: V[] = [];
    const BR: V[] = [];
    for (let i = 0; i < n; i++) {
      const u = norm(sub(spine[Math.min(n - 1, i + 1)], spine[Math.max(0, i - 1)]));
      const sv = mul(norm(cross(u, up)), widths[i] / 2);
      const uv = mul(up, t / 2);
      TL.push(this.w(add(add(spine[i], sv), uv)));
      TR.push(this.w(add(sub(spine[i], sv), uv)));
      BL.push(this.w(sub(add(spine[i], sv), uv)));
      BR.push(this.w(sub(sub(spine[i], sv), uv)));
    }
    const m = Math.floor(n / 2);
    const strips: { pts: V[]; n: V }[] = [];
    const strip = (a: V[], b: V[]) => {
      const nn = norm(cross(sub(a[m + 1] ?? a[m], a[m - 1] ?? a[m]), sub(b[m], a[m])));
      const centre = this.w(spine[m]);
      const face = mul(add(a[m], b[m]), 0.5);
      const o = dot(nn, sub(face, centre)) < 0 ? mul(nn, -1) : nn;
      strips.push({ pts: [...a, ...[...b].reverse()], n: o });
    };
    strip(TL, TR);
    strip(BL, BR);
    strip(TL, BL);
    strip(TR, BR);
    const vis = strips.filter((s) => dot(s.n, VIEW) > 0.02).map((s) => ({ pts: s.pts.map(scr), fill: lit(col, s.n) }));
    // End caps.
    for (const i of [0, n - 1]) {
      const q = [TL[i], TR[i], BR[i], BL[i]];
      let nn = norm(cross(sub(q[1], q[0]), sub(q[3], q[0])));
      const tang = sub(this.w(spine[i]), this.w(spine[i === 0 ? 1 : n - 2]));
      if (dot(nn, tang) < 0) nn = mul(nn, -1);
      if (dot(nn, VIEW) > 0.02) vis.push({ pts: q.map(scr), fill: lit(col, nn) });
    }
    const bandLines = bands.map((f) => {
      const i = Math.max(0, Math.min(n - 1, Math.round(f * (n - 1))));
      return [TL[i], TR[i], BR[i]].map(scr);
    });
    const x = this.x;
    this.part([...TL, ...TR, ...BL, ...BR], () => {
      for (const f of vis) {
        path(x, f.pts);
        x.fillStyle = f.fill;
        x.fill();
        x.lineWidth = lw;
        x.strokeStyle = INK;
        x.stroke();
      }
      for (const b of bandLines) {
        for (const [c, w] of [[INK, 4.2], [bandCol, 2.4]] as [string, number][]) {
          x.strokeStyle = c;
          x.lineWidth = w;
          x.beginPath();
          b.forEach(([px, py], i) => (i ? x.lineTo(px, py) : x.moveTo(px, py)));
          x.stroke();
        }
      }
    });
  }

  /** A rope or string through local points. */
  rope(pts: V[], col = ROPE, w = 1.8, layer = 0, bias = 0) {
    const wp = pts.map((p) => this.w(p));
    const sp = wp.map(scr);
    const x = this.x;
    this.part(wp, () => {
      x.lineCap = 'round';
      x.lineJoin = 'round';
      for (const [c, lw] of [[INK, w + 2], [col, w]] as [string, number][]) {
        x.strokeStyle = c;
        x.lineWidth = lw;
        x.beginPath();
        sp.forEach(([px, py], i) => (i ? x.lineTo(px, py) : x.moveTo(px, py)));
        x.stroke();
      }
    }, layer, bias);
  }

  /**
   * Pale motion streaks along an arc about `pivot` in the f-h plane, from angle
   * a0 to a1 at the given radii (the swing of a throwing arm), drawn over all.
   */
  swing(pivot: V, radii: number[], a0: number, a1: number) {
    const arcs = radii.map((rad) =>
      Array.from({ length: 9 }, (_, i) => {
        const a = a0 + ((a1 - a0) * i) / 8;
        return this.P(add(pivot, [Math.cos(a) * rad, 0, Math.sin(a) * rad]));
      }),
    );
    const x = this.x;
    this.part([this.w(pivot)], () => {
      x.lineCap = 'round';
      arcs.forEach((pts, k) => {
        x.strokeStyle = `rgba(255,248,225,${0.85 - k * 0.25})`;
        x.lineWidth = 2.6 - k * 0.6;
        x.beginPath();
        pts.forEach(([px, py], i) => (i ? x.lineTo(px, py) : x.moveTo(px, py)));
        x.stroke();
      });
    }, 1);
  }

  /** A 2D drawing at the projected point `at`, sorted as a small box of radius r. */
  bill(at: V, r: number, draw: (x: CanvasRenderingContext2D, sx: number, sy: number) => void, layer = 0, bias = 0) {
    const c = this.w(at);
    const [sx, sy] = scr(c);
    const box: V[] = [add(c, [-r, -r, -r]), add(c, [r, r, r])];
    const x = this.x;
    this.part(box, () => draw(x, sx, sy), layer, bias);
  }

  /** A wheel on an axle along s (or lying flat), spoked or a crude plank disc. */
  wheel(c: V, r: number, th: number, o: WheelOpts = {}) {
    const N = 28;
    const ax: V = o.flat ? [0, 0, 1] : [0, 1, 0];
    const e1: V = [1, 0, 0];
    const e2: V = o.flat ? [0, 1, 0] : [0, 0, 1];
    const rng = new Rng(o.seed ?? 7);
    const jag = Array.from({ length: N }, () => (o.crude ? rng.range(-1.6, 1.2) : 0));
    const ringL = (cc: V, rr: number, j = false) =>
      Array.from({ length: N }, (_, i): V => {
        const t = (i / N) * Math.PI * 2;
        const k = rr + (j ? jag[i] : 0);
        return add(cc, add(mul(e1, Math.cos(t) * k), mul(e2, Math.sin(t) * k)));
      });
    const near = add(c, mul(ax, th / 2));
    const far = add(c, mul(ax, -th / 2));
    const wn = this.dir(c, ax);
    const front = dot(wn, VIEW) >= 0 ? near : far;
    const nface = dot(wn, VIEW) >= 0 ? wn : mul(wn, -1);
    const out = [...ringL(near, r, true), ...ringL(far, r, true)].map((p) => this.w(p));
    const hull = convexHull(out.map(scr));
    const P = (p: V) => this.P(p);
    const rim = ringL(front, r, true).map(P);
    const wood = o.wood ?? TIMBER;
    const tyre = o.tyre ?? IRON;
    const faceWood = lit(wood, nface);
    const x = this.x;
    const spokes = o.spokes ?? 8;
    const felloe = ringL(front, r - 3.2).map(P);
    const inner = ringL(front, r - 7.5).map(P);
    const hubR = Math.max(3.5, r * 0.2);
    const hub = ringL(front, hubR).map(P);
    const hubOut = ringL(add(front, mul(ax, dot(wn, VIEW) >= 0 ? 3 : -3)), hubR * 0.7).map(P);
    const spokeEnds = Array.from({ length: spokes }, (_, i) => {
      const t = (i / spokes) * Math.PI * 2 + 0.3;
      return [P(add(front, add(mul(e1, Math.cos(t) * hubR), mul(e2, Math.sin(t) * hubR)))), P(add(front, add(mul(e1, Math.cos(t) * (r - 6)), mul(e2, Math.sin(t) * (r - 6)))))];
    });
    const planks = o.crude
      ? [-0.55, -0.18, 0.2, 0.56].map((k) => {
          const h = Math.sqrt(Math.max(0, 1 - k * k)) * (r - 2);
          return [P(add(front, add(mul(e1, k * r), mul(e2, -h)))), P(add(front, add(mul(e1, k * r), mul(e2, h))))];
        })
      : [];
    const studs = o.crude ? Array.from({ length: 6 }, (_, i) => P(add(front, add(mul(e1, Math.cos(i * 1.047 + 0.4) * (r - 4)), mul(e2, Math.sin(i * 1.047 + 0.4) * (r - 4)))))) : [];
    this.part(out, () => {
      // Tread between the two rims.
      path(x, hull);
      x.fillStyle = shade(tyre, -0.15);
      x.fill();
      x.lineWidth = 2;
      x.strokeStyle = INK;
      x.stroke();
      if (o.crude) {
        // A disc of planks pegged together, iron studs round the rim.
        path(x, rim);
        x.fillStyle = faceWood;
        x.fill();
        x.save();
        x.clip();
        x.strokeStyle = shade(faceWood, -0.35);
        x.lineWidth = 1.4;
        for (const [a, b] of planks) {
          x.beginPath();
          x.moveTo(a[0], a[1]);
          x.lineTo(b[0], b[1]);
          x.stroke();
        }
        x.restore();
        path(x, rim);
        x.lineWidth = 2.2;
        x.strokeStyle = INK;
        x.stroke();
        x.fillStyle = STEEL_D;
        for (const [px, py] of studs) {
          x.beginPath();
          x.arc(px, py, 1.8, 0, Math.PI * 2);
          x.fill();
        }
      } else {
        // Iron tyre, felloe, spokes and hub.
        path(x, rim);
        x.fillStyle = lit(tyre, nface);
        x.fill();
        x.lineWidth = 2;
        x.strokeStyle = INK;
        x.stroke();
        path(x, felloe);
        x.fillStyle = faceWood;
        x.fill();
        x.lineWidth = 1.4;
        x.stroke();
        path(x, inner);
        x.fillStyle = shade(wood, -0.55);
        x.fill();
        x.lineWidth = 1.6;
        x.stroke();
        x.lineCap = 'round';
        for (const [cc, lw] of [[INK, 4.6], [faceWood, 2.6]] as [string, number][]) {
          x.strokeStyle = cc;
          x.lineWidth = lw;
          x.beginPath();
          for (const [a, b] of spokeEnds) {
            x.moveTo(a[0], a[1]);
            x.lineTo(b[0], b[1]);
          }
          x.stroke();
        }
      }
      path(x, hub);
      x.fillStyle = o.hub ?? shade(wood, -0.1);
      x.fill();
      x.lineWidth = 1.6;
      x.strokeStyle = INK;
      x.stroke();
      path(x, hubOut);
      x.fillStyle = STEEL_D;
      x.fill();
      x.stroke();
    });
  }

  /** Draw everything back to front: overlays (layer 1) last. */
  render() {
    for (const layer of [0, 1]) {
      const ps = this.parts.filter((p) => p.layer === layer);
      const n = ps.length;
      const out: number[][] = ps.map(() => []);
      const indeg = new Array<number>(n).fill(0);
      const eps = 0.6;
      const behind = (a: Part, b: Part) => a.hi[0] <= b.lo[0] + eps || a.hi[1] <= b.lo[1] + eps || a.hi[2] <= b.lo[2] + eps;
      for (let i = 0; i < n; i++) {
        for (let j = i + 1; j < n; j++) {
          const a = ps[i];
          const b = ps[j];
          if (a.x1 < b.x0 || b.x1 < a.x0 || a.y1 < b.y0 || b.y1 < a.y0) continue;
          const ab = behind(a, b);
          const ba = behind(b, a);
          const first = ab && !ba ? i : ba && !ab ? j : a.d <= b.d ? i : j;
          const second = first === i ? j : i;
          out[first].push(second);
          indeg[second]++;
        }
      }
      const done = new Array<boolean>(n).fill(false);
      for (let k = 0; k < n; k++) {
        let pick = -1;
        for (let i = 0; i < n; i++) if (!done[i] && indeg[i] === 0 && (pick < 0 || ps[i].d < ps[pick].d)) pick = i;
        // A cycle: draw the shallowest remaining part.
        if (pick < 0) for (let i = 0; i < n; i++) if (!done[i] && (pick < 0 || ps[i].d < ps[pick].d)) pick = i;
        done[pick] = true;
        for (const m of out[pick]) indeg[m]--;
        ps[pick].draw();
      }
    }
  }
}

function scr(w: V): Pt {
  return [0.9 * (w[0] - w[1]), 0.45 * (w[0] + w[1]) - w[2]];
}

function path(x: CanvasRenderingContext2D, pts: Pt[]) {
  x.beginPath();
  pts.forEach(([px, py], i) => (i ? x.lineTo(px, py) : x.moveTo(px, py)));
  x.closePath();
}

function strokeVisible(x: CanvasRenderingContext2D, band: { p: Pt; vis: boolean }[]) {
  x.beginPath();
  let on = false;
  for (let i = 0; i <= band.length; i++) {
    const b = band[i % band.length];
    if (b.vis) {
      if (on) x.lineTo(b.p[0], b.p[1]);
      else x.moveTo(b.p[0], b.p[1]);
      on = true;
    } else on = false;
  }
  x.stroke();
}

function convexHull(pts: Pt[]): Pt[] {
  const p = [...pts].sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  if (p.length < 3) return p;
  const crossZ = (o: Pt, a: Pt, b: Pt) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
  const lower: Pt[] = [];
  for (const q of p) {
    while (lower.length >= 2 && crossZ(lower[lower.length - 2], lower[lower.length - 1], q) <= 0) lower.pop();
    lower.push(q);
  }
  const upper: Pt[] = [];
  for (let i = p.length - 1; i >= 0; i--) {
    const q = p[i];
    while (upper.length >= 2 && crossZ(upper[upper.length - 2], upper[upper.length - 1], q) <= 0) upper.pop();
    upper.push(q);
  }
  upper.pop();
  lower.pop();
  return lower.concat(upper);
}

// ---------------------------------------------------------------- transforms

/** Rotate about an axis through `pivot` parallel to s (pitch: + lifts the front). */
function pitch(pivot: V, a: number) {
  const c = Math.cos(a);
  const s = Math.sin(a);
  return (p: V): V => {
    const df = p[0] - pivot[0];
    const dh = p[2] - pivot[2];
    return [pivot[0] + df * c - dh * s, p[1], pivot[2] + df * s + dh * c];
  };
}

/** Rotate about an axis through `pivot` parallel to f (roll: + lifts the near side). */
function roll(pivot: V, a: number) {
  const c = Math.cos(a);
  const s = Math.sin(a);
  return (p: V): V => {
    const ds = p[1] - pivot[1];
    const dh = p[2] - pivot[2];
    return [p[0], pivot[1] + ds * c - dh * s, pivot[2] + ds * s + dh * c];
  };
}

/** Rotate about a vertical axis through `pivot` (yaw). */
function yaw(pivot: V, a: number) {
  const c = Math.cos(a);
  const s = Math.sin(a);
  return (p: V): V => {
    const df = p[0] - pivot[0];
    const ds = p[1] - pivot[1];
    return [pivot[0] + df * c - ds * s, pivot[1] + df * s + ds * c, p[2]];
  };
}

// ---------------------------------------------------------------- 2D details

/** A rough boulder with cel shading, light from the upper left. */
function boulder(x: CanvasRenderingContext2D, cx: number, cy: number, r: number, seed: number, col = STONE, lumps = 9) {
  const rng = new Rng(seed);
  const pts: Pt[] = [];
  for (let i = 0; i < lumps; i++) {
    const a = (i / lumps) * Math.PI * 2 + rng.range(-0.2, 0.2);
    const k = r * rng.range(0.82, 1.08);
    pts.push([cx + Math.cos(a) * k, cy + Math.sin(a) * k * 0.86]);
  }
  path(x, pts);
  x.fillStyle = col;
  x.fill();
  x.save();
  x.clip();
  x.fillStyle = shade(col, -0.32);
  x.beginPath();
  x.ellipse(cx + r * 0.45, cy + r * 0.45, r * 0.95, r * 0.8, 0, 0, Math.PI * 2);
  x.fill();
  x.fillStyle = shade(col, 0.3);
  x.beginPath();
  x.ellipse(cx - r * 0.4, cy - r * 0.42, r * 0.42, r * 0.3, -0.5, 0, Math.PI * 2);
  x.fill();
  x.strokeStyle = shade(col, -0.45);
  x.lineWidth = 1.2;
  x.beginPath();
  x.moveTo(cx - r * 0.1, cy - r * 0.2);
  x.lineTo(cx + r * 0.25, cy + r * 0.1);
  x.lineTo(cx + r * 0.15, cy + r * 0.45);
  x.stroke();
  x.restore();
  path(x, pts);
  x.lineWidth = 2;
  x.strokeStyle = INK;
  x.stroke();
}

/** A ragged cloth strip hanging from (cx, cy), tails toward `dx`. */
function rag(x: CanvasRenderingContext2D, cx: number, cy: number, col: string, dx = 1, len = 18) {
  poly(x, [[cx - 3, cy], [cx + 3, cy], [cx + 4 + dx * len * 0.35, cy + len * 0.7], [cx + dx * len * 0.2, cy + len * 0.5], [cx - 1 + dx * len * 0.3, cy + len], [cx - 4 + dx * len * 0.05, cy + len * 0.45]], col, 1.4);
}

/** A soft dust cloud: overlapping puffs with a faint outline. */
function dust(x: CanvasRenderingContext2D, cx: number, cy: number, r: number, seed: number) {
  const rng = new Rng(seed);
  const puffs: number[][] = [];
  for (let i = 0; i < 6; i++) puffs.push([cx + rng.range(-r, r), cy - rng.range(0, r * 0.7), rng.range(r * 0.35, r * 0.6)]);
  x.fillStyle = 'rgba(92,70,44,0.5)';
  for (const [px, py, pr] of puffs) {
    x.beginPath();
    x.arc(px, py, pr + 1.5, 0, Math.PI * 2);
    x.fill();
  }
  x.fillStyle = 'rgba(214,196,160,0.85)';
  for (const [px, py, pr] of puffs) {
    x.beginPath();
    x.arc(px, py, pr, 0, Math.PI * 2);
    x.fill();
  }
  x.fillStyle = 'rgba(240,230,205,0.8)';
  for (const [px, py, pr] of puffs) {
    x.beginPath();
    x.arc(px - pr * 0.3, py - pr * 0.3, pr * 0.45, 0, Math.PI * 2);
    x.fill();
  }
}

/** Pale splinters flying from (cx, cy). */
function splinters(x: CanvasRenderingContext2D, cx: number, cy: number, seed: number, dir = -1) {
  const rng = new Rng(seed);
  for (let i = 0; i < 6; i++) {
    const a = rng.range(-2.4, -0.7);
    const d = rng.range(10, 26);
    const px = cx + Math.cos(a) * d * -dir;
    const py = cy + Math.sin(a) * d;
    const l = rng.range(4, 8);
    const ang = rng.range(0, Math.PI);
    poly(x, [[px - Math.cos(ang) * l, py - Math.sin(ang) * l], [px + Math.sin(ang) * 1.6, py - Math.cos(ang) * 1.6], [px + Math.cos(ang) * l, py + Math.sin(ang) * l]], i % 2 ? '#dcb97e' : '#c49a5e', 1.1);
  }
}

/** A blue swallowtail pennant with a gold edge, or a ragged horde banner, on a pole. */
function pennant(r: Rig, base: V, h: number, col: string, edge: string | null, len: number, tattered = false, sigil = false) {
  const top = add(base, [0, 0, h]);
  r.cyl(base, top, 1.8, '#5a3a22', { n: 8, lw: 1.6 });
  r.bill(top, 2, (x, sx, sy) => {
    x.fillStyle = edge ?? STEEL_D;
    x.beginPath();
    x.arc(sx, sy - 1, 2.6, 0, Math.PI * 2);
    x.fill();
    x.lineWidth = 1.2;
    x.strokeStyle = INK;
    x.stroke();
  });
  // The cloth streams back from the pole (toward -f).
  const t = (df: number, dh: number): V => add(top, [-df, 0, -dh]);
  const pts: V[] = tattered
    ? [t(0, 2), t(len * 0.55, 0), t(len, 4), t(len * 0.78, 10), t(len * 0.95, 16), t(len * 0.6, 18), t(len * 0.7, 26), t(len * 0.3, 24), t(0, 28)]
    : [t(0, 2), t(len, 6), t(len * 0.72, 13), t(len, 21), t(0, 24)];
  r.flat(pts, col, 1.6, (x, P) => {
    if (edge) {
      x.strokeStyle = edge;
      x.lineWidth = 3;
      x.beginPath();
      pts.forEach((p, i) => {
        const [px, py] = P(p);
        if (i) x.lineTo(px, py);
        else x.moveTo(px, py);
      });
      x.closePath();
      x.stroke();
    }
    if (sigil) {
      // The horde's black war sigil.
      const [cx, cy] = P(t(len * 0.42, 13));
      x.fillStyle = '#1e1310';
      x.beginPath();
      for (let i = 0; i < 4; i++) {
        const a = (i / 4) * Math.PI * 2 + 0.4;
        x.moveTo(cx, cy);
        x.lineTo(cx + Math.cos(a) * 8, cy + Math.sin(a) * 8);
        x.lineTo(cx + Math.cos(a + 0.4) * 3, cy + Math.sin(a + 0.4) * 3);
      }
      x.fill();
    } else if (!tattered) {
      // A small white eagle.
      const [cx, cy] = P(t(len * 0.4, 12));
      x.fillStyle = '#f2efe4';
      x.beginPath();
      x.moveTo(cx, cy - 4);
      x.lineTo(cx + 5, cy - 3);
      x.lineTo(cx + 1.5, cy);
      x.lineTo(cx, cy + 4);
      x.lineTo(cx - 1.5, cy);
      x.lineTo(cx - 5, cy - 3);
      x.closePath();
      x.fill();
    }
  });
}

/** Rope lashing round a joint: a few turns across the timber. */
function lashing(r: Rig, at: V, along: V, rad: number) {
  const u = norm(along);
  const p = norm(Math.abs(u[2]) < 0.9 ? cross(u, [0, 0, 1]) : cross(u, [1, 0, 0]));
  for (const k of [-2.6, 0, 2.6]) {
    const c = add(at, mul(u, k));
    r.rope([add(c, mul(p, -rad)), add(add(c, mul(u, 1.2)), mul(p, rad))], ROPE, 1.6);
  }
}

// ---------------------------------------------------------------- engines

interface Build {
  r: Rig;
  atk: boolean;
  dead: boolean;
  v: number;
}

/**
 * Human ballista: a giant crossbow on a two-wheeled carriage with a trail.
 * The prod is a heavy bow bound in iron (blue for the company); idle: spanned
 * and loaded with a heavy bolt; attack: just loosed, the prod flexed forward,
 * the string slack, the carriage kicked back a little.
 */
function ballista({ r, atk, dead, v }: Build) {
  const axle: V = [-8, 0, 31];
  const painted = v !== 1;
  const prodCol = painted ? BLUE : '#4e3420';
  const carriage = () => {
    for (const s of [-42, 42]) {
      if (dead && s > 0) continue;
      r.wheel([axle[0], s, axle[2]], 31, 8, { spokes: 8, hub: painted ? BLUE : undefined, seed: s });
    }
    r.cyl([axle[0], -48, axle[2]], [axle[0], dead ? 28 : 48, axle[2]], 4, IRON, { n: 10 });
    // Cheeks: two heavy timbers sloping from the trail on the ground up to the front.
    for (const s of [-17, 17]) r.beam([-96, s, 9], [44, s, 48], 8, 15, v === 1 ? BLUE_D : TIMBER);
    for (const [f, h] of [[-66, 26], [-8, 42.5], [34, 54]] as const) r.beam([f, -21.5, h], [f, 21.5, h], 9, 7, TIMBER_D);
    // The trail spade, and the pivot post carrying the bow.
    r.beam([-98, -13, 5], [-98, 13, 5], 7, 9, IRON);
    r.cyl([-8, 0, 46], [-8, 0, 64], 7, TIMBER_D, { bands: [0.2, 0.8] });
  };
  const thrower = () => {
    // Stock, winch with its cranks at the back, and the claw.
    r.beam([-58, 0, 69], [80, 0, 75], 14, 11, TIMBER);
    r.cyl([-50, -16, 70], [-50, 16, 70], 6.5, TIMBER_D, { bands: [0.1, 0.9] });
    for (const s of [-18, 18]) {
      r.beam([-50, s, 70], [-50, s, 86], 3.4, 3.4, IRON, { grain: false });
      r.cyl([-50, s, 86], [-50, s + (s > 0 ? 8 : -8), 86], 2.2, TIMBER_D, { n: 8 });
    }
    r.beam([-35, 0, 77.5], [-25, 0, 77.5], 8, 4.4, IRON, { grain: false });
    // The prod across the front: drawn back when spanned, flexed forward once loosed.
    const bend = atk ? -9 : 32;
    const N = 11;
    const spine: V[] = [];
    const widths: number[] = [];
    for (let i = 0; i < N; i++) {
      const k = -1 + (2 * i) / (N - 1);
      spine.push([71 - bend * k * k, k * 70, 77]);
      widths.push(13 - 6.5 * Math.abs(k));
    }
    const prod = dead ? spine.slice(0, 7) : spine;
    r.bar(prod, widths.slice(0, prod.length), 9, prodCol, 2.2, dead ? [0.02, 0.62] : [0.02, 0.3, 0.7, 0.98], painted ? GOLD : STEEL_D);
    // The riser block that binds the prod to the stock, strapped in iron.
    r.beam([60, 0, 77], [82, 0, 77], 22, 13, TIMBER_D);
    for (const f of [64, 78]) r.beam([f, -11.6, 83.9], [f, 11.6, 83.9], 2.6, 0.8, IRON, { grain: false });
    if (dead) return;
    const tipL = spine[0];
    const tipR = spine[N - 1];
    for (const t of [tipL, tipR]) r.cyl(add(t, [-3.5, 0, 0]), add(t, [3.5, 0, 0]), 4.4, IRON, { n: 8 });
    if (atk) r.rope([tipL, [66, 0, 77.5], tipR], '#efe6cf', 2, 0, 6);
    else r.rope([tipL, [-30, 0, 81], tipR], '#efe6cf', 2, 0, 6);
    if (!atk) {
      // A heavy bolt in the groove: iron head, blue and white flights.
      r.beam([-30, 0, 84.5], [100, 0, 86.5], 5, 5, '#c9a06a', { grain: false });
      r.cone([100, 0, 86.5], [124, 0, 87], 6.5, STEEL);
      r.flat([[-28, 0, 86], [-8, 0, 86.5], [-28, 0, 98]], v === 2 ? '#f2efe4' : BLUE, 1.4);
      r.flat([[-28, -7, 85.5], [-8, 0, 86.5], [-28, 7, 85.5]], '#f2efe4', 1.4);
    }
    if (v !== 2) pennant(r, [72, 0, 84], 42, BLUE, GOLD, 32);
    if (v === 2) {
      // A sheaf of spare bolts strapped along the near cheek.
      for (const k of [0, 3, 6]) r.beam([-72, 25 + k * 0.4, 24 + k], [12, 25 + k * 0.4, 47 + k], 3.2, 3.2, '#c9a06a', { grain: false });
      for (const k of [0, 3, 6]) r.cone([12, 25 + k * 0.4, 47 + k], [22, 25 + k * 0.4, 50 + k], 2.8, STEEL, 1.2);
      r.beam([-40, 23, 30], [-40, 29, 40], 3.4, 3.4, '#4a2f1c', { grain: false });
    }
  };
  if (dead) {
    // Wrecked: the near wheel off, the carriage dropped onto its axle end,
    // the prod snapped, the bow knocked askew.
    r.wheel([20, 68, 2], 31, 8, { spokes: 8, flat: true, hub: painted ? BLUE : undefined });
    r.with(roll([0, -42, 0], -0.36), () => {
      carriage();
      r.with(yaw([-8, 0, 64], 0.22), () => r.with(pitch([-8, 0, 64], -0.1), thrower));
    });
    // The broken half of the prod and a spilled bolt.
    r.bar([[80, 30, 4], [72, 46, 4], [60, 61, 4], [45, 74, 4]], [7.5, 6.6, 5.6, 5], 7, prodCol, 2, [0.98], painted ? GOLD : STEEL_D);
    r.beam([-58, 46, 2.5], [12, 54, 3], 4.4, 4.4, '#c9a06a', { grain: false });
    r.beam([42, -48, 2.5], [68, -62, 3], 6, 7, TIMBER);
    return;
  }
  const recoil = atk ? pitch([axle[0], 0, axle[2]], 0.07) : (p: V) => p;
  r.with(recoil, () => {
    carriage();
    thrower();
  });
  if (atk) {
    // The shot's wake in front, and a kick of dust at the trail.
    r.bill([-104, 0, 2], 8, (x, sx, sy) => dust(x, sx, sy, 13, 3), 0, 30);
    r.bill([112, 0, 88], 6, (x, sx, sy) => {
      x.strokeStyle = 'rgba(255,248,225,0.9)';
      x.lineWidth = 2.4;
      x.lineCap = 'round';
      const [dx, dy] = r.back ? [0.9, -0.45] : [-0.9, 0.45];
      for (const [o, l] of [[-6, 28], [0, 42], [6, 24]]) {
        x.beginPath();
        x.moveTo(sx + dy * o, sy - dx * o);
        x.lineTo(sx + dy * o + dx * l, sy - dx * o + dy * l);
        x.stroke();
      }
    }, 1);
  }
}

/**
 * Human mangonel: a low frame on four wheels with uprights and a padded
 * crossbar, a rope skein driving the throwing arm. Idle: arm wound down to
 * the back, a stone in the cup; attack: arm thrown up against the crossbar.
 */
function mangonel({ r, atk, dead, v }: Build) {
  const painted = v === 0 || v === 2;
  const pivot: V = [-26, 0, 37];
  const L = 92;
  const base = () => {
    for (const f of [-52, 50]) {
      for (const s of [-38, 38]) {
        if (dead && f > 0 && s > 0) continue;
        r.wheel([f, s, 18], 18, 7, { spokes: 6, hub: painted ? BLUE : undefined, seed: f + s });
      }
      r.cyl([f, -44, 18], [f, dead && f > 0 ? 22 : 44, 18], 3.2, IRON, { n: 8 });
    }
    for (const s of [-28, 28]) r.beam([-80, s, 24], [72, s, 24], 9, 16, painted ? BLUE_D : TIMBER);
    for (const f of [-70, 62]) r.beam([f, -32, 35.5], [f, 32, 35.5], 10, 7, TIMBER_D);
    // The skein and its ratchet wheels with their levers.
    r.cyl([pivot[0], -23.5, pivot[2]], [pivot[0], 23.5, pivot[2]], 10.5, ROPE, { bands: [0.15, 0.5, 0.85], bandCol: '#9a8458' });
    for (const s of [-34, 34]) {
      r.wheel([pivot[0], s, pivot[2]], 12, 3.4, { spokes: 4, wood: IRON, tyre: IRON });
      r.beam([pivot[0], s + (s > 0 ? 3.4 : -3.4), pivot[2]], [pivot[0] + 13, s + (s > 0 ? 3.4 : -3.4), pivot[2] + 18], 3.4, 3.4, TIMBER_D, { grain: false });
    }
  };
  const frame = () => {
    // Uprights braced forward, and the crossbar with its cushion.
    for (const s of [-28, 28]) {
      r.beam([10, s, 32], [10, s, 104], 9, 11, painted ? BLUE_D : TIMBER);
      r.beam([54, s, 32], [16, s, 88], 7, 7, TIMBER_D);
    }
    r.beam([10, -36, 108.5], [10, 36, 108.5], 13, 11, painted ? BLUE : TIMBER);
    if (painted) for (const s of [-36, 36]) r.cyl([10, s, 114], [10, s, 117.5], 4.6, GOLD, { n: 10 });
    r.cyl([-1.5, -15, 103], [-1.5, 15, 103], 7, v === 2 ? RED_D : '#c8b48a', { bands: [0.25, 0.75], bandCol: ROPE });
  };
  // The windlass at the back.
  const windlass = () => {
    for (const s of [-22, 22]) r.beam([-72, s, 32], [-72, s, 47], 6, 6, TIMBER_D);
    r.cyl([-72, -19, 45], [-72, 19, 45], 7, TIMBER, { bands: [0.5] });
    r.beam([-72, 27, 31], [-72, 27, 59], 3.4, 3.4, TIMBER_D, { grain: false });
    r.beam([-86, 27, 45], [-58, 27, 45], 3.4, 3.4, TIMBER_D, { grain: false });
  };
  const ang = atk ? Math.atan2(80, 30) : Math.PI - 0.12;
  const dirA: V = [Math.cos(ang), 0, Math.sin(ang)];
  const tip = add(pivot, mul(dirA, L));
  const arm = () => {
    r.beam(add(pivot, mul(dirA, -7)), tip, 9.5, 8, TIMBER);
    for (const t of [0.35, 0.62]) {
      const c = add(pivot, mul(dirA, L * t));
      r.cyl(add(c, mul(dirA, -1.7)), add(c, mul(dirA, 1.7)), 5.8, IRON, { n: 10 });
    }
    // The cup: open toward the throw.
    const up: V = atk ? [Math.sin(ang), 0, -Math.cos(ang)] : [0, 0, 1];
    const cupC = add(tip, mul(dirA, -5));
    r.cyl(add(cupC, mul(up, -3)), add(cupC, mul(up, 7)), 12.5, TIMBER_D, { open: true, bands: [0.5] });
    if (!atk) {
      const st = add(cupC, mul(up, 12));
      r.bill(st, 12, (x, sx, sy) => boulder(x, sx, sy, 14, 40 + v, STONE, v === 1 ? 7 : 11));
      r.rope([[-72, 0, 52], [-100, 0, 48]], ROPE, 1.8);
    } else {
      r.rope([[-72, 0, 52], [-82, 0, 36], [-90, 0, 16], [-94, 0, 2]], ROPE, 1.8);
      // The arm's swing up from its cocked rest.
      r.swing(pivot, [L + 16, L + 4], Math.PI - 0.5, ang + 0.18);
    }
  };
  if (dead) {
    // Wrecked: a front wheel off, the near upright snapped, crossbar down,
    // the arm broken across the frame and the cup spilled.
    r.wheel([86, 54, 2], 18, 7, { spokes: 6, flat: true });
    r.with(roll([0, -38, 0], -0.12), () => {
      r.with(pitch([-52, 0, 0], -0.08), () => {
        base();
        windlass();
        r.beam([10, -28, 32], [10, -28, 104], 9, 11, painted ? BLUE_D : TIMBER);
        r.beam([54, -28, 32], [16, -28, 88], 7, 7, TIMBER_D);
        r.beam([10, 28, 32], [10, 28, 60], 9, 11, painted ? BLUE_D : TIMBER);
        r.bill([10, 28, 62], 4, (x, sx, sy) => splinters(x, sx, sy - 4, 5, 1));
        r.beam(add(pivot, mul([-0.98, 0, 0.18], -4)), add(pivot, mul([-0.98, 0, 0.18], 46)), 9.5, 8, TIMBER);
      });
    });
    r.beam([30, 32, 5], [94, -24, 5], 13, 11, painted ? BLUE : TIMBER);
    r.beam([-42, 48, 4], [8, 66, 4], 9.5, 8, TIMBER);
    r.cyl([18, 72, 7], [24, 74, 16], 12.5, TIMBER_D, { open: true });
    r.bill([38, 80, 8], 8, (x, sx, sy) => boulder(x, sx, sy, 11, 44, STONE, 9));
    return;
  }
  base();
  frame();
  windlass();
  arm();
  if (v === 1) {
    // Spare stones stacked on a plank at the front.
    r.beam([66, -17, 38.5], [66, 17, 38.5], 15, 3, PLANK, { grain: false });
    for (const [s, k] of [[-9, 0], [6, 1], [-1, 2]] as const) r.bill([66, s, 47 + (k === 2 ? 9 : 0)], 7, (x, sx, sy) => boulder(x, sx, sy, 8.5, 60 + k, STONE, 8));
  }
  if (v !== 1) pennant(r, [10, 28, 114], 32, BLUE, GOLD, 28);
}

/**
 * Goblin rock lobber: a ramshackle counterweight catapult of crooked poles
 * lashed with rope on log skids, a sack of rocks for the counterweight, skulls
 * and red rags. Idle: arm down at the back with a boulder in the basket;
 * attack: arm flung up and forward, the sack dropped.
 */
function rockLobber({ r, atk, dead, v }: Build) {
  const apex = 104;
  const pivot: V = [0, 0, apex];
  const skids = () => {
    for (const s of [-32, 32]) {
      r.cyl([-88, s, 7], [-6, s + 1.5, 8], 7, CRUDE, { n: 12 });
      r.cyl([-6, s + 1.5, 8], [78, s - 1, 7], 7, CRUDE, { n: 12 });
      r.bill([78, s - 1, 14], 4, (x, sx, sy) => skull(x, sx, sy - 2, 1.7));
    }
    for (const f of [-74, -6, 62]) r.cyl([f, -40, 20], [f + 3, 40, 20], 6, CRUDE_D, { n: 12 });
  };
  const aframe = (collapsed: boolean) => {
    for (const s of [-27, 27]) {
      if (collapsed && s > 0) continue;
      // Two crooked poles to the apex on each side, and a cross-brace.
      r.cyl([-40, s, 21], [-21, s + 2, 62], 5.6, CRUDE, { n: 10 });
      r.cyl([-21, s + 2, 62], [-1, s, apex], 5.6, CRUDE, { n: 10 });
      r.cyl([40, s, 21], [18, s - 2, 60], 5.6, CRUDE, { n: 10 });
      r.cyl([18, s - 2, 60], [1, s, apex], 5.6, CRUDE, { n: 10 });
      r.cyl([-30, s, 47], [30, s, 49], 4.4, CRUDE_D, { n: 10 });
      lashing(r, [0, s, apex - 2], [0, 0, 1], 7);
      lashing(r, [-26, s, 48], [1, 0, 0], 5.5);
      r.bill([-29, s + (s > 0 ? 5 : -5), 43], 3, (x, sx, sy) => rag(x, sx, sy, s > 0 ? RED : RED_D, r.back ? -1 : 1, 18));
    }
    if (!collapsed) {
      r.cyl([0, -36, apex], [0, 36, apex], 6, CRUDE_D, { n: 12 });
      for (const s of [-38, 38]) r.bill([0, s, apex + 7], 4, (x, sx, sy) => skull(x, sx, sy - 3, 1.9));
    }
  };
  const longL = 100;
  const shortL = 32;
  const ang = atk ? Math.atan2(0.8, 0.6) : Math.atan2(-0.68, -0.73);
  const d: V = [Math.cos(ang), 0, Math.sin(ang)];
  const tip = add(pivot, mul(d, longL));
  const tail = add(pivot, mul(d, -shortL));
  const arm = () => {
    // A bent log: kinked a little partway along.
    const kink = add(add(pivot, mul(d, longL * 0.45)), [0, 2, 0]);
    r.cyl(tail, pivot, 6, CRUDE, { n: 12 });
    r.cyl(pivot, kink, 5.6, CRUDE, { n: 12 });
    r.cyl(kink, tip, 5, CRUDE, { n: 12 });
    lashing(r, add(pivot, mul(d, 7)), d, 7);
    // The basket.
    const up: V = atk ? [Math.sin(ang), 0, -Math.cos(ang)] : [0, 0, 1];
    const bc = add(tip, mul(d, -2));
    r.cyl(add(bc, mul(up, -5)), add(bc, mul(up, 10)), 14.5, '#8a6a3c', { open: true, bands: [0.3, 0.7], bandCol: CRUDE_D });
    if (!atk) r.bill(add(bc, mul(up, 17)), 15, (x, sx, sy) => boulder(x, sx, sy, 17, 70 + v, '#8e8a7a', 8));
    // Counterweight: a sack (or a net of rocks) on a rope from the short end.
    const hang = add(tail, [0, 0, -10]);
    r.rope([tail, hang], ROPE, 2.2);
    const sc = add(hang, [0, 0, -19]);
    r.bill(sc, 18, (x, sx, sy) => {
      if (v === 1) {
        for (const [dx, dy, rr, k] of [[-8, 4, 9, 0], [8, 5, 9, 1], [0, -5, 9.5, 2], [-3, 12, 8, 3], [7, -11, 7, 4]]) boulder(x, sx + dx, sy + dy, rr, 90 + k, '#8e8a7a', 7);
        x.strokeStyle = ROPE;
        x.lineWidth = 1.5;
        for (let i = -2; i <= 2; i++) {
          x.beginPath();
          x.moveTo(sx + i * 7 - 7, sy - 18);
          x.lineTo(sx + i * 7 + 7, sy + 18);
          x.moveTo(sx + i * 7 + 7, sy - 18);
          x.lineTo(sx + i * 7 - 7, sy + 18);
          x.stroke();
        }
      } else {
        poly(x, [[sx - 4.5, sy - 19], [sx + 4.5, sy - 19], [sx + 7, sy - 13], [sx + 18, sy - 2], [sx + 17, sy + 13], [sx + 4.5, sy + 19], [sx - 11, sy + 18], [sx - 18, sy + 7], [sx - 16, sy - 7], [sx - 6, sy - 13]], BURLAP, 2.2);
        x.fillStyle = shade(BURLAP, -0.3);
        x.beginPath();
        x.moveTo(sx + 2, sy - 9);
        x.quadraticCurveTo(sx + 18, sy, sx + 4.5, sy + 18);
        x.lineTo(sx + 16, sy + 11);
        x.lineTo(sx + 17, sy - 2);
        x.closePath();
        x.fill();
        x.strokeStyle = ROPE;
        x.lineWidth = 1.8;
        x.beginPath();
        x.moveTo(sx - 6, sy - 14);
        x.lineTo(sx + 6, sy - 14);
        x.stroke();
        if (v === 2) {
          // A daubed red hand on the sack.
          x.fillStyle = RED;
          x.beginPath();
          x.ellipse(sx - 3, sy + 3, 5, 4.5, 0, 0, Math.PI * 2);
          x.fill();
          for (const a of [-2.2, -1.7, -1.2, -0.7]) {
            x.beginPath();
            x.ellipse(sx - 3 + Math.cos(a) * 8, sy + 3 + Math.sin(a) * 8, 1.6, 3, a + Math.PI / 2, 0, Math.PI * 2);
            x.fill();
          }
        }
      }
    });
  };
  if (dead) {
    // Collapsed: the near poles down, the arm lying across the skids, the sack burst.
    skids();
    aframe(true);
    r.cyl([-32, 28, 5], [10, 60, 6], 5.6, CRUDE, { n: 10 });
    r.cyl([36, 24, 5], [-4, 64, 6], 5.6, CRUDE, { n: 10 });
    r.cyl([-64, -10, 10], [52, 18, 25], 6, CRUDE, { n: 12 });
    r.cyl([58, 24, 13], [66, 26, 25], 14.5, '#8a6a3c', { open: true });
    for (const [f, s, k] of [[30, -42, 0], [42, -52, 1], [22, -55, 2], [88, 32, 3]] as const) r.bill([f, s, 7], 7, (x, sx, sy) => boulder(x, sx, sy, k === 3 ? 15 : 8, 120 + k, '#8e8a7a', 8));
    r.bill([10, -46, 4], 8, (x, sx, sy) => poly(x, [[sx - 16, sy + 2], [sx - 7, sy - 7], [sx + 11, sy - 5], [sx + 18, sy + 3], [sx, sy + 7]], BURLAP, 1.8));
    r.bill([-72, 36, 3], 6, (x, sx, sy) => {
      poly(x, [[sx - 11, sy], [sx + 13, sy - 4], [sx + 15, sy + 4], [sx - 9, sy + 6]], RED, 1.6);
      skull(x, sx + 19, sy, 1.8);
    });
    return;
  }
  skids();
  aframe(false);
  arm();
  // A horde banner lashed to the rear of the near skid.
  pennant(r, [-84, 32, 12], 118, v === 1 ? '#2a211c' : RED, null, 36, true, true);
  if (atk) {
    r.bill([-38, 46, 2], 10, (x, sx, sy) => dust(x, sx, sy, 17, 9), 0, 30);
    r.swing(pivot, [longL + 18, longL + 6], Math.PI - 0.15, ang + 0.15);
  }
}

/**
 * Goblin war wagon: a heavy planked box on four crude wheels with a ram, a
 * spiked iron front plate, scythes on the hubs, stakes along the top, skulls
 * and red banners; a push bar at the back for its crew. Attack: lurching
 * forward into the ram, dust and splinters flying.
 */
function warWagon({ r, atk, dead, v }: Build) {
  const wheels = (skip: boolean) => {
    for (const f of [-44, 44]) {
      for (const s of [-42, 42]) {
        if (skip && f > 0 && s > 0) continue;
        r.wheel([f, s, 29], 29, 11, { crude: true, wood: CRUDE, seed: f * 3 + s, tyre: '#4a4f55' });
      }
      r.cyl([f, -50, 29], [f, skip && f > 0 ? 32 : 50, 29], 4.6, IRON, { n: 10 });
    }
    // Spikes on the near hubs and scythes on the front hubs.
    if (!skip) r.cone([44, 49, 29], [44, 67, 29], 5, STEEL_D);
    r.cone([-44, 49, 29], [-44, 64, 29], 4.6, STEEL_D);
    if (!skip) {
      r.flat([[44, 50, 32], [38, 68, 37], [25, 86, 38], [33, 72, 33], [42, 53, 25]], STEEL, 1.6);
      r.flat([[44, -50, 32], [38, -68, 37], [25, -86, 38], [33, -72, 33], [42, -53, 25]], STEEL, 1.6);
    }
  };
  const box = () => {
    r.beam([-74, 0, 44], [66, 0, 44], 74, 9, CRUDE_D);
    for (const s of [-35, 35]) {
      r.beam([-74, s, 66], [66, s, 66], 6, 34, PLANK);
      // Sharpened stakes along the top of the side.
      for (let i = 0; i < 9; i++) {
        const f = -66 + i * 15.5;
        r.cone([f, s, 83], [f + 1, s, 97 + (i % 2 ? 3 : 0)], 3.8, '#b08a58', 1.4);
      }
    }
    r.beam([-74, -32, 60], [-74, 32, 60], 6, 24, PLANK);
    // Iron straps across the near side.
    for (const f of [-50, 0, 46]) r.beam([f, 38.2, 49], [f, 38.2, 83], 4.6, 1, IRON, { grain: false });
    // Push bar for the crew.
    for (const s of [-26, 26]) r.beam([-72, s, 52], [-102, s, 62], 6, 6, CRUDE_D);
    r.cyl([-101, -34, 62], [-101, 34, 62], 4, CRUDE, { n: 10 });
    // Spikes on the near side.
    for (const f of [-38, 16]) r.cone([f, 38.5, 67], [f, 56, 67], 4.2, STEEL_D);
    // Skulls on the stakes and the side, red rags.
    for (const [f, s] of [[-35, 35], [27, 35], [-66, -35]] as const) r.bill([f, s, 99], 4, (x, sx, sy) => skull(x, sx, sy - 2, 1.7));
    r.bill([-10, 38.5, 82], 3, (x, sx, sy) => rag(x, sx, sy, RED, -1, 22));
    r.bill([52, 38.5, 82], 3, (x, sx, sy) => rag(x, sx, sy, RED_D, -1, 18));
  };
  const front = () => {
    // The slanted front plate, iron with rivets.
    const P0: V[] = [[70, -40, 34], [70, 40, 34], [56, 40, 102], [56, -40, 102]];
    const P1: V[] = P0.map((p) => add(p, [-7, 0, 0]));
    r.solid([P0, P1, [P0[0], P0[1], P1[1], P1[0]], [P0[2], P0[3], P1[3], P1[2]], [P0[1], P0[2], P1[2], P1[1]], [P0[0], P0[3], P1[3], P1[0]]], '#5e6268', 2.2, null);
    const fAt = (h: number) => 70 - ((h - 34) / 68) * 14;
    r.flat(P0, '#6a6e74', 2.2, (x, P) => {
      x.fillStyle = '#c9ced4';
      for (const [s, h] of [[-32, 40], [32, 40], [-32, 96], [32, 96], [0, 98], [-16, 68], [16, 68]]) {
        const [px, py] = P([fAt(h), s, h]);
        x.beginPath();
        x.arc(px, py, 2, 0, Math.PI * 2);
        x.fill();
      }
      x.strokeStyle = 'rgba(30,20,12,0.5)';
      x.lineWidth = 1.3;
      for (const h of [57, 80]) {
        const [ax, ay] = P([fAt(h), -40, h]);
        const [bx, by] = P([fAt(h), 40, h]);
        x.beginPath();
        x.moveTo(ax, ay);
        x.lineTo(bx, by);
        x.stroke();
      }
    }, 0.5);
    // Big iron spikes out of the plate.
    for (const [s, h] of [[-28, 46], [28, 46], [-15, 78], [15, 78], [0, 98], [-33, 92], [33, 92]] as const) {
      const f = fAt(h);
      r.cone([f, s, h], [f + 33, s * 1.1, h - 4], 5.4, STEEL);
    }
    // The ram: a log through the plate with an iron head.
    r.cyl([32, 0, 58], [106, 0, 56], 9.5, CRUDE, { bands: [0.55, 0.85], bandCol: IRON });
    r.cone([106, 0, 56], [126, 0, 55], 10.5, STEEL_D, 2);
    if (v === 2) {
      // A horned beast skull lashed over the ram.
      r.bill([96, 0, 72], 8, (x, sx, sy) => {
        for (const k of [-1, 1]) poly(x, [[sx + k * 5, sy - 4], [sx + k * 16, sy - 11], [sx + k * 20, sy - 24], [sx + k * 13, sy - 13], [sx + k * 3, sy - 7]], '#cbb98e', 1.6);
        skull(x, sx, sy, 2.4);
      });
    } else r.bill([92, 0, 69], 6, (x, sx, sy) => skull(x, sx, sy, 2.1));
    r.bill([66, 20, 68], 4, (x, sx, sy) => skull(x, sx, sy, 1.8));
  };
  const banners = () => {
    const col = v === 1 ? '#2a211c' : RED;
    pennant(r, [-68, 32, 82], 74, col, null, 36, true, true);
    if (v !== 2) pennant(r, [-68, -32, 82], 64, v === 1 ? RED : RED_D, null, 32, true, false);
  };
  if (dead) {
    // Wrecked: a front wheel off, the nose down in the dirt, the plate
    // twisted, a banner snapped and planks scattered.
    r.wheel([100, 70, 2], 29, 11, { crude: true, wood: CRUDE, flat: true, seed: 9 });
    r.with(roll([0, -42, 0], -0.1), () => {
      r.with(pitch([-44, 0, 0], -0.24), () => {
        wheels(true);
        box();
        front();
      });
    });
    r.cyl([-68, 32, 4], [-10, 74, 4], 2.2, '#5a3a22', { n: 8 });
    r.flat([[-12, 70, 1], [-36, 84, 1], [-28, 92, 1], [-46, 100, 1], [-8, 80, 1]], RED, 1.6);
    r.beam([-84, -52, 2], [-42, -66, 2], 11, 3, PLANK);
    r.beam([62, -56, 2], [90, -42, 3], 9, 3, PLANK);
    return;
  }
  const lurch = atk ? pitch([44, 0, 0], -0.12) : (p: V) => p;
  r.with(lurch, () => {
    wheels(false);
    box();
    front();
    banners();
  });
  if (atk) {
    r.bill([126, 0, 44], 8, (x, sx, sy) => splinters(x, sx, sy, 17, r.back ? 1 : -1), 1);
    // Dust kicked up at the wheels, sorted with the wagon so the body hides what is behind it.
    r.bill([48, 58, 2], 10, (x, sx, sy) => dust(x, sx, sy, 17, 21), 0, 40);
    r.bill([44, -42, 2], 10, (x, sx, sy) => dust(x, sx, sy, 15, 23), 0);
    r.bill([-50, 54, 2], 10, (x, sx, sy) => dust(x, sx, sy, 13, 25), 0, 40);
  }
}

const ENGINES: Record<string, { looks: number; draw: (b: Build) => void }> = {
  ballista: { looks: 3, draw: ballista },
  mangonel: { looks: 3, draw: mangonel },
  rock_lobber: { looks: 3, draw: rockLobber },
  war_wagon: { looks: 3, draw: warWagon },
};

export const ENGINE_TYPES = Object.keys(ENGINES);

export function isEngine(type: string): boolean {
  return type in ENGINES;
}

/** Number of distinct looks drawn for an engine type (0 if not an engine). */
export function engineLooks(type: string): number {
  return ENGINES[type]?.looks ?? 0;
}

/**
 * Draw a war engine in figure units with its ground centre at the origin.
 * Returns false when the type is unknown or the variant is not drawn (only
 * variants below engineLooks(type) exist). `flee_b` shows `idle_b`; the shield
 * poses map to the plain ones.
 */
export function drawEngine(x: CanvasRenderingContext2D, type: string, pose: Pose, variant: number): boolean {
  const e = ENGINES[type];
  if (!e || variant < 0 || variant >= e.looks) return false;
  const p = pose === 'flee_b' || pose === 'run_b' ? 'idle_b' : pose === 'run_f' ? 'idle_f' : pose.replace(/s$/, '');
  const dead = p === 'dead';
  const back = p === 'idle_b' || p === 'atk_b';
  const atk = p === 'atk_f' || p === 'atk_b';
  x.save();
  x.lineJoin = 'round';
  x.lineCap = 'round';
  const r = new Rig(x, back);
  e.draw({ r, atk, dead, v: variant });
  r.render();
  if (dead) {
    // Scorched and dulled.
    x.globalCompositeOperation = 'source-atop';
    x.fillStyle = 'rgba(34,24,16,0.34)';
    x.fillRect(-400, -400, 800, 800);
    const rng = new Rng(type.length * 11 + variant);
    x.fillStyle = 'rgba(20,14,10,0.35)';
    for (let i = 0; i < 6; i++) {
      x.beginPath();
      x.ellipse(rng.range(-80, 80), rng.range(-40, 30), rng.range(10, 24), rng.range(6, 12), 0, 0, Math.PI * 2);
      x.fill();
    }
  }
  x.restore();
  return true;
}
