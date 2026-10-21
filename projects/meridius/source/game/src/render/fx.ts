// Combat feedback: particles, floating text, projectiles, shockwaves and
// persistent ground marks. All positions are in world pixels.

export interface Particle {
  x: number;
  y: number;
  z: number;
  vx: number;
  vy: number;
  vz: number;
  life: number;
  max: number;
  size: number;
  color: string;
  gravity: number;
  drag: number;
  shape: 'dot' | 'spark' | 'puff' | 'leaf';
}

export interface FloatText {
  x: number;
  y: number;
  text: string;
  color: string;
  size: number;
  life: number;
  max: number;
  vy: number;
  bold: boolean;
  delay: number;
}

export interface Projectile {
  x0: number;
  y0: number;
  x1: number;
  y1: number;
  t: number;
  dur: number;
  arc: number;
  kind: 'bolt' | 'arrow';
  onHit?: () => void;
  stick?: boolean;
  /** Size of the missile (squad soldiers shoot smaller ones). */
  scale?: number;
}

export interface Mark {
  x: number;
  y: number;
  angle: number;
  kind: 'bolt' | 'arrow';
  life: number;
  scale: number;
}

export interface Ring {
  x: number;
  y: number;
  r: number;
  max: number;
  life: number;
  color: string;
}

export class Fx {
  particles: Particle[] = [];
  texts: FloatText[] = [];
  projectiles: Projectile[] = [];
  marks: Mark[] = [];
  rings: Ring[] = [];

  burst(x: number, y: number, z: number, n: number, opts: Partial<Particle> & { speed?: number; spread?: number; colors?: string[] }) {
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2;
      const sp = (opts.speed ?? 80) * (0.4 + Math.random() * 0.8);
      const life = (opts.max ?? 0.6) * (0.6 + Math.random() * 0.6);
      this.particles.push({
        x,
        y,
        z,
        vx: Math.cos(a) * sp,
        vy: Math.sin(a) * sp * 0.5,
        vz: (opts.vz ?? 90) * (0.5 + Math.random()),
        life,
        max: life,
        size: (opts.size ?? 3) * (0.6 + Math.random() * 0.8),
        color: opts.colors ? opts.colors[i % opts.colors.length] : (opts.color ?? '#fff'),
        gravity: opts.gravity ?? 300,
        drag: opts.drag ?? 1.5,
        shape: opts.shape ?? 'dot',
      });
    }
  }

  text(x: number, y: number, text: string, color: string, opts: { size?: number; bold?: boolean; delay?: number; life?: number } = {}) {
    // Stack texts that spawn at the same spot.
    const near = this.texts.filter((t) => Math.abs(t.x - x) < 30 && t.life > t.max - 0.35 && Math.abs(t.y - y) < 40).length;
    this.texts.push({
      x,
      y: y - near * 18,
      text,
      color,
      size: opts.size ?? 20,
      life: opts.life ?? 1.3,
      max: opts.life ?? 1.3,
      vy: -34,
      bold: opts.bold ?? true,
      delay: opts.delay ?? 0,
    });
  }

  shoot(p: Projectile) {
    this.projectiles.push(p);
  }

  ring(x: number, y: number, max: number, color: string, life = 0.7) {
    this.rings.push({ x, y, r: 4, max, life, color });
  }

  get busy() {
    return this.projectiles.length > 0;
  }

  update(dt: number) {
    for (const p of this.particles) {
      p.life -= dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.z += p.vz * dt;
      p.vz -= p.gravity * dt;
      const d = Math.exp(-p.drag * dt);
      p.vx *= d;
      p.vy *= d;
      if (p.z < 0) {
        p.z = 0;
        p.vz *= -0.3;
        p.vx *= 0.6;
        p.vy *= 0.6;
      }
    }
    this.particles = this.particles.filter((p) => p.life > 0);
    for (const t of this.texts) {
      if (t.delay > 0) {
        t.delay -= dt;
        continue;
      }
      t.life -= dt;
      t.y += t.vy * dt;
      t.vy *= Math.exp(-2.2 * dt);
    }
    this.texts = this.texts.filter((t) => t.life > 0);
    for (const p of this.projectiles) {
      p.t += dt;
      if (p.t >= p.dur) {
        p.onHit?.();
        if (p.stick) {
          const ang = Math.atan2(p.y1 - p.y0, p.x1 - p.x0);
          this.marks.push({ x: p.x1, y: p.y1, angle: ang, kind: p.kind, life: 40, scale: p.scale ?? 1 });
        }
      }
    }
    this.projectiles = this.projectiles.filter((p) => p.t < p.dur);
    for (const r of this.rings) {
      r.life -= dt;
      r.r += (r.max - r.r) * Math.min(1, dt * 6);
    }
    this.rings = this.rings.filter((r) => r.life > 0);
    for (const m of this.marks) m.life -= dt;
    this.marks = this.marks.filter((m) => m.life > 0);
    while (this.marks.length > 90) this.marks.shift();
  }

  drawGround(ctx: CanvasRenderingContext2D) {
    for (const m of this.marks) {
      ctx.save();
      ctx.globalAlpha = Math.min(1, m.life / 3);
      ctx.translate(m.x, m.y);
      ctx.rotate(m.angle);
      ctx.scale(m.scale, m.scale);
      ctx.strokeStyle = '#5a3a22';
      ctx.lineWidth = 2.2;
      ctx.beginPath();
      ctx.moveTo(-12, -6);
      ctx.lineTo(0, 0);
      ctx.stroke();
      ctx.fillStyle = m.kind === 'arrow' ? '#a3261c' : '#e8e2d0';
      ctx.fillRect(-14, -8, 4, 3);
      ctx.restore();
    }
    for (const r of this.rings) {
      ctx.save();
      ctx.globalAlpha = Math.max(0, r.life / 0.7) * 0.8;
      ctx.strokeStyle = r.color;
      ctx.lineWidth = 4;
      ctx.beginPath();
      ctx.ellipse(r.x, r.y, r.r, r.r * 0.5, 0, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();
    }
  }

  drawAir(ctx: CanvasRenderingContext2D) {
    for (const p of this.particles) {
      const a = Math.max(0, p.life / p.max);
      ctx.globalAlpha = a;
      ctx.fillStyle = p.color;
      const y = p.y - p.z;
      if (p.shape === 'puff') {
        const s = p.size * (1.6 - a * 0.6);
        ctx.globalAlpha = a * 0.45;
        ctx.beginPath();
        ctx.arc(p.x, y, s, 0, Math.PI * 2);
        ctx.fill();
      } else if (p.shape === 'spark') {
        ctx.strokeStyle = p.color;
        ctx.lineWidth = p.size * 0.6;
        ctx.beginPath();
        ctx.moveTo(p.x, y);
        ctx.lineTo(p.x - p.vx * 0.03, y - (p.vy - p.vz) * 0.03);
        ctx.stroke();
      } else if (p.shape === 'leaf') {
        ctx.save();
        ctx.translate(p.x, y);
        ctx.rotate(p.life * 6);
        ctx.fillRect(-p.size, -p.size * 0.4, p.size * 2, p.size * 0.8);
        ctx.restore();
      } else {
        ctx.fillRect(p.x - p.size / 2, y - p.size / 2, p.size, p.size);
      }
    }
    ctx.globalAlpha = 1;
    for (const p of this.projectiles) {
      const f = Math.min(1, p.t / p.dur);
      const x = p.x0 + (p.x1 - p.x0) * f;
      const yLin = p.y0 + (p.y1 - p.y0) * f;
      const y = yLin - Math.sin(f * Math.PI) * p.arc;
      const f2 = Math.min(1, f + 0.02);
      const x2 = p.x0 + (p.x1 - p.x0) * f2;
      const y2 = p.y0 + (p.y1 - p.y0) * f2 - Math.sin(f2 * Math.PI) * p.arc;
      const ang = Math.atan2(y2 - y, x2 - x);
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(ang);
      if (p.scale) ctx.scale(p.scale, p.scale);
      ctx.strokeStyle = 'rgba(255,250,220,0.35)';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(-34, 0);
      ctx.lineTo(-8, 0);
      ctx.stroke();
      ctx.strokeStyle = '#4a2f1c';
      ctx.lineWidth = 2.6;
      ctx.beginPath();
      ctx.moveTo(-16, 0);
      ctx.lineTo(6, 0);
      ctx.stroke();
      ctx.fillStyle = '#d8dce0';
      ctx.beginPath();
      ctx.moveTo(10, 0);
      ctx.lineTo(4, -3);
      ctx.lineTo(4, 3);
      ctx.closePath();
      ctx.fill();
      ctx.fillStyle = p.kind === 'arrow' ? '#a3261c' : '#efe8d4';
      ctx.fillRect(-18, -3, 5, 6);
      ctx.restore();
    }
  }

  drawTexts(ctx: CanvasRenderingContext2D, zoom: number) {
    for (const t of this.texts) {
      if (t.delay > 0) continue;
      const a = Math.min(1, t.life / 0.35) * Math.min(1, (t.max - t.life) / 0.08 + 0.2);
      const pop = 1 + Math.max(0, 0.25 - (t.max - t.life)) * 1.6;
      ctx.save();
      ctx.globalAlpha = a;
      ctx.translate(t.x, t.y);
      const s = (t.size * pop) / Math.max(0.6, zoom);
      ctx.font = `${t.bold ? 700 : 600} ${s}px Cinzel, Georgia, serif`;
      ctx.textAlign = 'center';
      ctx.lineJoin = 'round';
      ctx.lineWidth = s * 0.22;
      ctx.strokeStyle = 'rgba(25,16,10,0.9)';
      ctx.strokeText(t.text, 0, 0);
      ctx.fillStyle = t.color;
      ctx.fillText(t.text, 0, 0);
      ctx.restore();
    }
  }
}
