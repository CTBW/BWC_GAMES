// Isometric projection shared by every scene (2:1 diamonds, upper-left light).

export const TW = 128; // tile width in world pixels
export const TH = 64; // tile height
export const LH = 26; // pixels per height level

export function isoX(x: number, y: number): number {
  return (x - y) * (TW / 2);
}

export function isoY(x: number, y: number, h = 0): number {
  return (x + y) * (TH / 2) - h * LH;
}

/** Inverse projection on the ground plane (h = 0). */
export function fromIso(sx: number, sy: number): { x: number; y: number } {
  const a = sx / (TW / 2);
  const b = sy / (TH / 2);
  return { x: (a + b) / 2, y: (b - a) / 2 };
}

export interface Camera {
  x: number; // world px at screen centre
  y: number;
  zoom: number;
  /** Target values for smooth motion. */
  tx: number;
  ty: number;
  tzoom: number;
  shake: number;
}

export function makeCamera(x = 0, y = 0, zoom = 1): Camera {
  return { x, y, zoom, tx: x, ty: y, tzoom: zoom, shake: 0 };
}

export function updateCamera(c: Camera, dt: number) {
  const k = 1 - Math.pow(0.0008, dt);
  c.x += (c.tx - c.x) * k;
  c.y += (c.ty - c.y) * k;
  c.zoom += (c.tzoom - c.zoom) * k;
  c.shake = Math.max(0, c.shake - dt * 2.5);
}

export function worldToScreen(c: Camera, wx: number, wy: number, vw: number, vh: number) {
  return { x: (wx - c.x) * c.zoom + vw / 2, y: (wy - c.y) * c.zoom + vh / 2 };
}

export function screenToWorld(c: Camera, sx: number, sy: number, vw: number, vh: number) {
  return { x: (sx - vw / 2) / c.zoom + c.x, y: (sy - vh / 2) / c.zoom + c.y };
}

export function easeOutCubic(t: number) {
  return 1 - Math.pow(1 - t, 3);
}

export function easeInOutQuad(t: number) {
  return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
}

export function clamp(v: number, a: number, b: number) {
  return Math.max(a, Math.min(b, v));
}

export function lerp(a: number, b: number, t: number) {
  return a + (b - a) * t;
}
