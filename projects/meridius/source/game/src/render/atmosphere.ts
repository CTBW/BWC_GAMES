// Shared atmosphere: drifting cloud shadows, warm light grading, vignette and
// ambient motes. Drawn over the world in screen space.

import { hash2 } from '../core/rng';

export interface Mote {
  x: number;
  y: number;
  vx: number;
  vy: number;
  life: number;
  size: number;
  kind: 'pollen' | 'leaf' | 'firefly' | 'ember';
  phase: number;
}

export class Atmosphere {
  motes: Mote[] = [];
  clouds: { x: number; y: number; r: number; s: number }[] = [];
  night = false;
  /** The scene draws its own lit darkness mask; skip the flat night tint. */
  ownNightMask = false;
  warmth = 1;

  constructor(seed = 1) {
    for (let i = 0; i < 7; i++) {
      this.clouds.push({ x: hash2(i, 1, seed) * 3000 - 1500, y: hash2(i, 2, seed) * 2000 - 1000, r: 260 + hash2(i, 3, seed) * 380, s: 0.6 + hash2(i, 4, seed) * 0.6 });
    }
  }

  update(dt: number, w: number, h: number) {
    for (const c of this.clouds) {
      c.x += 14 * c.s * dt;
      c.y += 5 * c.s * dt;
      if (c.x > 2200) c.x = -2200;
      if (c.y > 1500) c.y = -1500;
    }
    const want = this.night ? 26 : 34;
    while (this.motes.length < want) {
      const kind: Mote['kind'] = this.night ? 'firefly' : Math.random() < 0.18 ? 'leaf' : 'pollen';
      this.motes.push({
        x: Math.random() * w,
        y: Math.random() * h,
        vx: kind === 'leaf' ? 18 + Math.random() * 20 : 6 + Math.random() * 8,
        vy: kind === 'leaf' ? 10 + Math.random() * 14 : -2 + Math.random() * 4,
        life: 6 + Math.random() * 8,
        size: kind === 'leaf' ? 3 + Math.random() * 2 : 1 + Math.random() * 1.6,
        kind,
        phase: Math.random() * 10,
      });
    }
    for (const m of this.motes) {
      m.life -= dt;
      m.phase += dt;
      m.x += (m.vx + Math.sin(m.phase * 1.3) * 8) * dt;
      m.y += (m.vy + Math.cos(m.phase * 0.9) * 5) * dt;
    }
    this.motes = this.motes.filter((m) => m.life > 0 && m.x < w + 20 && m.y < h + 20);
  }

  /** Cloud shadows in world space (call with world transform applied). */
  drawClouds(ctx: CanvasRenderingContext2D, cx: number, cy: number) {
    if (this.night) return;
    ctx.save();
    ctx.globalCompositeOperation = 'multiply';
    for (const c of this.clouds) {
      const x = cx + c.x;
      const y = cy + c.y;
      const g = ctx.createRadialGradient(x, y, c.r * 0.1, x, y, c.r);
      g.addColorStop(0, 'rgba(70,90,110,0.22)');
      g.addColorStop(1, 'rgba(70,90,110,0)');
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.ellipse(x, y, c.r, c.r * 0.55, 0.3, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  /** Light grading and vignette in screen space. */
  drawGrade(ctx: CanvasRenderingContext2D, w: number, h: number, time: number) {
    ctx.save();
    if (this.night) {
      if (!this.ownNightMask) {
        ctx.globalCompositeOperation = 'multiply';
        ctx.fillStyle = 'rgba(70,80,140,0.55)';
        ctx.fillRect(0, 0, w, h);
        ctx.globalCompositeOperation = 'source-over';
      }
    } else {
      ctx.globalCompositeOperation = 'soft-light';
      const g = ctx.createLinearGradient(0, 0, w, h);
      g.addColorStop(0, `rgba(255,214,140,${0.45 * this.warmth})`);
      g.addColorStop(0.55, 'rgba(255,240,210,0.05)');
      g.addColorStop(1, 'rgba(60,90,130,0.35)');
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, w, h);
      // Sun glow from the upper left.
      ctx.globalCompositeOperation = 'screen';
      const s = ctx.createRadialGradient(w * 0.08, -h * 0.1, 10, w * 0.08, -h * 0.1, Math.max(w, h) * 0.75);
      s.addColorStop(0, 'rgba(255,225,160,0.22)');
      s.addColorStop(1, 'rgba(255,225,160,0)');
      ctx.fillStyle = s;
      ctx.fillRect(0, 0, w, h);
    }
    ctx.globalCompositeOperation = 'source-over';
    // Motes.
    for (const m of this.motes) {
      const a = Math.min(1, m.life / 1.5);
      if (m.kind === 'firefly') {
        const glow = 0.5 + 0.5 * Math.sin(m.phase * 3 + time);
        ctx.fillStyle = `rgba(230,255,140,${0.8 * a * glow})`;
        ctx.beginPath();
        ctx.arc(m.x, m.y, 2, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = `rgba(230,255,140,${0.15 * a * glow})`;
        ctx.beginPath();
        ctx.arc(m.x, m.y, 7, 0, Math.PI * 2);
        ctx.fill();
      } else if (m.kind === 'leaf') {
        ctx.save();
        ctx.translate(m.x, m.y);
        ctx.rotate(m.phase * 2);
        ctx.fillStyle = `rgba(200,170,70,${0.8 * a})`;
        ctx.fillRect(-m.size, -m.size * 0.45, m.size * 2, m.size * 0.9);
        ctx.restore();
      } else {
        ctx.fillStyle = `rgba(255,248,220,${0.55 * a})`;
        ctx.fillRect(m.x, m.y, m.size, m.size);
      }
    }
    // Vignette.
    const v = ctx.createRadialGradient(w / 2, h / 2, Math.min(w, h) * 0.35, w / 2, h / 2, Math.max(w, h) * 0.75);
    v.addColorStop(0, 'rgba(0,0,0,0)');
    v.addColorStop(1, 'rgba(20,12,6,0.55)');
    ctx.fillStyle = v;
    ctx.fillRect(0, 0, w, h);
    ctx.restore();
  }
}
