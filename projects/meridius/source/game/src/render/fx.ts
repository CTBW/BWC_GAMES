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
  /** `glow`: a soft additive light (sparks of magic, embers, frost glitter). */
  shape: 'dot' | 'spark' | 'puff' | 'leaf' | 'glow';
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

export type ProjectileKind = 'bolt' | 'arrow' | 'orb' | 'fireball' | 'stone' | 'shard';

export interface Projectile {
  x0: number;
  y0: number;
  x1: number;
  y1: number;
  t: number;
  dur: number;
  arc: number;
  kind: ProjectileKind;
  onHit?: () => void;
  stick?: boolean;
  /** Size of the missile (squad soldiers shoot smaller ones). */
  scale?: number;
  /** Glow colour of magic missiles. */
  color?: string;
  /** Seconds since the last trail particle. */
  trailT?: number;
}

export interface Mark {
  x: number;
  y: number;
  angle: number;
  /** Missiles stuck in the ground, or what a spell or a stone leaves on it. */
  kind: 'bolt' | 'arrow' | 'scorch' | 'crater' | 'frost';
  life: number;
  scale: number;
}

/** A jagged bolt of lightning, or a writhing tendril of blood magic, between two points. */
export interface Arc {
  pts: { x: number; y: number }[];
  branches: { x: number; y: number }[][];
  life: number;
  max: number;
  color: string;
  core: string;
  width: number;
  /** A tendril: drawn in its own dark colours (not as light), writhing along a smooth curve. */
  tendril?: { x0: number; y0: number; x1: number; y1: number; amp: number; seed: number; dark: string };
}

export interface Ring {
  x: number;
  y: number;
  r: number;
  max: number;
  life: number;
  color: string;
}

/** A jagged line from a to b: midpoint displacement, `jag` world pixels at the coarsest level. */
function jagged(x0: number, y0: number, x1: number, y1: number, jag: number, depth = 5): { x: number; y: number }[] {
  let pts = [{ x: x0, y: y0 }, { x: x1, y: y1 }];
  let amp = jag;
  for (let d = 0; d < depth; d++) {
    const next: { x: number; y: number }[] = [pts[0]];
    for (let i = 1; i < pts.length; i++) {
      const a = pts[i - 1];
      const b = pts[i];
      const dx = b.x - a.x;
      const dy = b.y - a.y;
      const len = Math.hypot(dx, dy) || 1;
      const off = (Math.random() - 0.5) * amp;
      next.push({ x: (a.x + b.x) / 2 - (dy / len) * off, y: (a.y + b.y) / 2 + (dx / len) * off }, b);
    }
    pts = next;
    amp *= 0.55;
  }
  return pts;
}

export class Fx {
  particles: Particle[] = [];
  texts: FloatText[] = [];
  projectiles: Projectile[] = [];
  marks: Mark[] = [];
  rings: Ring[] = [];
  arcs: Arc[] = [];

  /**
   * Lightning (or a tendril) from one point to another. It flickers: each
   * frame of its short life redraws a fresh jagged path.
   */
  lightning(x0: number, y0: number, x1: number, y1: number, opts: { color?: string; core?: string; width?: number; life?: number; jag?: number; branches?: number } = {}) {
    const len = Math.hypot(x1 - x0, y1 - y0);
    const jag = opts.jag ?? Math.min(60, len * 0.22);
    const pts = jagged(x0, y0, x1, y1, jag);
    const branches: { x: number; y: number }[][] = [];
    for (let i = 0; i < (opts.branches ?? 2); i++) {
      const p = pts[Math.floor(pts.length * (0.25 + Math.random() * 0.5))];
      const ang = Math.atan2(y1 - y0, x1 - x0) + (Math.random() - 0.5) * 2.2;
      const l = len * (0.12 + Math.random() * 0.18);
      branches.push(jagged(p.x, p.y, p.x + Math.cos(ang) * l, p.y + Math.sin(ang) * l, jag * 0.5, 3));
    }
    const life = opts.life ?? 0.32;
    this.arcs.push({ pts, branches, life, max: life, color: opts.color ?? 'rgba(120,170,255,1)', core: opts.core ?? '#f4f8ff', width: opts.width ?? 3 });
  }

  /**
   * A tendril of blood magic reaching from one point to another: a smooth,
   * writhing curve in dark flesh and blood colours with a bright vein.
   */
  tendril(x0: number, y0: number, x1: number, y1: number, opts: { color: string; core: string; dark: string; width?: number; life?: number; amp?: number }) {
    const life = opts.life ?? 0.5;
    this.arcs.push({
      pts: [],
      branches: [],
      life,
      max: life,
      color: opts.color,
      core: opts.core,
      width: opts.width ?? 3,
      tendril: { x0, y0, x1, y1, amp: opts.amp ?? 14, seed: Math.random() * 10, dark: opts.dark },
    });
  }

  /** A mark left on the ground by a spell or a stone (scorch, crater, frost). */
  mark(x: number, y: number, kind: Mark['kind'], scale = 1, life = 30) {
    this.marks.push({ x, y, angle: 0, kind, life, scale });
  }

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
      // Magic and fire leave a trail of light behind them.
      if (p.kind === 'orb' || p.kind === 'fireball' || p.kind === 'shard') {
        p.trailT = (p.trailT ?? 0) + dt;
        const every = p.kind === 'fireball' ? 0.012 : 0.022;
        while (p.trailT > every) {
          p.trailT -= every;
          const f = Math.min(1, p.t / p.dur);
          const x = p.x0 + (p.x1 - p.x0) * f;
          const y = p.y0 + (p.y1 - p.y0) * f - Math.sin(f * Math.PI) * p.arc;
          const fire = p.kind === 'fireball';
          this.particles.push({
            x: x + (Math.random() - 0.5) * 4,
            y: y + (Math.random() - 0.5) * 4,
            z: 0,
            vx: (Math.random() - 0.5) * 20,
            vy: (Math.random() - 0.5) * 20 - (fire ? 10 : 0),
            vz: 0,
            life: fire ? 0.45 : 0.3,
            max: fire ? 0.45 : 0.3,
            size: (fire ? 7 : 4) * (p.scale ?? 1) * (0.7 + Math.random() * 0.6),
            color: fire ? (Math.random() < 0.5 ? '#ffb030' : '#ff6a20') : (p.color ?? '#9fd8ff'),
            gravity: 0,
            drag: 2,
            shape: 'glow',
          });
        }
      }
      if (p.t >= p.dur) {
        p.onHit?.();
        if (p.stick && (p.kind === 'bolt' || p.kind === 'arrow')) {
          const ang = Math.atan2(p.y1 - p.y0, p.x1 - p.x0);
          this.marks.push({ x: p.x1, y: p.y1, angle: ang, kind: p.kind, life: 40, scale: p.scale ?? 1 });
        }
      }
    }
    this.projectiles = this.projectiles.filter((p) => p.t < p.dur);
    for (const a of this.arcs) a.life -= dt;
    this.arcs = this.arcs.filter((a) => a.life > 0);
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
      if (m.kind === 'scorch' || m.kind === 'crater' || m.kind === 'frost') {
        // Flat on the ground: a burnt patch, a stone's crater, a skin of frost.
        ctx.save();
        ctx.globalAlpha = Math.min(1, m.life / 4);
        ctx.translate(m.x, m.y);
        ctx.scale(m.scale, m.scale * 0.5);
        if (m.kind === 'frost') {
          const g = ctx.createRadialGradient(0, 0, 4, 0, 0, 46);
          g.addColorStop(0, 'rgba(235,248,255,0.75)');
          g.addColorStop(0.6, 'rgba(170,215,245,0.45)');
          g.addColorStop(1, 'rgba(170,215,245,0)');
          ctx.fillStyle = g;
          ctx.beginPath();
          ctx.arc(0, 0, 46, 0, Math.PI * 2);
          ctx.fill();
        } else {
          const g = ctx.createRadialGradient(0, 0, 3, 0, 0, 40);
          g.addColorStop(0, m.kind === 'scorch' ? 'rgba(25,15,8,0.8)' : 'rgba(40,30,20,0.75)');
          g.addColorStop(0.7, m.kind === 'scorch' ? 'rgba(45,28,14,0.45)' : 'rgba(80,62,40,0.4)');
          g.addColorStop(1, 'rgba(45,28,14,0)');
          ctx.fillStyle = g;
          ctx.beginPath();
          ctx.arc(0, 0, 40, 0, Math.PI * 2);
          ctx.fill();
          if (m.kind === 'crater') {
            ctx.strokeStyle = 'rgba(150,125,90,0.55)';
            ctx.lineWidth = 3;
            ctx.beginPath();
            ctx.arc(0, 0, 22, Math.PI * 0.9, Math.PI * 2.1);
            ctx.stroke();
          }
        }
        ctx.restore();
        continue;
      }
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
    let glowing = false;
    for (const p of this.particles) {
      const a = Math.max(0, p.life / p.max);
      const y = p.y - p.z;
      if (p.shape === 'glow') {
        // Additive soft light: drawn in its own pass below.
        glowing = true;
        continue;
      }
      ctx.globalAlpha = a;
      ctx.fillStyle = p.color;
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
    if (glowing) {
      ctx.save();
      ctx.globalCompositeOperation = 'lighter';
      for (const p of this.particles) {
        if (p.shape !== 'glow') continue;
        const a = Math.max(0, p.life / p.max);
        ctx.fillStyle = p.color;
        ctx.globalAlpha = a * 0.35;
        ctx.beginPath();
        ctx.arc(p.x, p.y - p.z, p.size * 1.8, 0, Math.PI * 2);
        ctx.fill();
        ctx.globalAlpha = a * 0.8;
        ctx.beginPath();
        ctx.arc(p.x, p.y - p.z, p.size * 0.7, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.restore();
    }
    for (const arc of this.arcs) this.drawArc(ctx, arc);
    for (const p of this.projectiles) {
      const f = Math.min(1, p.t / p.dur);
      const x = p.x0 + (p.x1 - p.x0) * f;
      const yLin = p.y0 + (p.y1 - p.y0) * f;
      const y = yLin - Math.sin(f * Math.PI) * p.arc;
      const f2 = Math.min(1, f + 0.02);
      const x2 = p.x0 + (p.x1 - p.x0) * f2;
      const y2 = p.y0 + (p.y1 - p.y0) * f2 - Math.sin(f2 * Math.PI) * p.arc;
      const ang = Math.atan2(y2 - y, x2 - x);
      if (p.kind !== 'bolt' && p.kind !== 'arrow') {
        this.drawMissile(ctx, p, x, y, ang, f);
        continue;
      }
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

  /** Magic missiles, fireballs, ice shards and catapult stones in flight. */
  private drawMissile(ctx: CanvasRenderingContext2D, p: Projectile, x: number, y: number, ang: number, f: number) {
    const s = p.scale ?? 1;
    ctx.save();
    ctx.translate(x, y);
    if (p.kind === 'stone') {
      // A tumbling stone, its shadow racing along the ground below it.
      ctx.save();
      ctx.globalAlpha = 0.25;
      ctx.fillStyle = '#141008';
      const gy = p.y0 + (p.y1 - p.y0) * f - y;
      ctx.beginPath();
      ctx.ellipse(0, gy, 9 * s, 4 * s, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
      ctx.rotate(p.t * 9);
      ctx.scale(s, s);
      ctx.beginPath();
      const r = 9;
      for (let i = 0; i < 7; i++) {
        const a = (i / 7) * Math.PI * 2;
        const k = r * (0.78 + ((i * 37) % 10) / 30);
        if (i) ctx.lineTo(Math.cos(a) * k, Math.sin(a) * k);
        else ctx.moveTo(Math.cos(a) * k, Math.sin(a) * k);
      }
      ctx.closePath();
      ctx.fillStyle = p.color ?? '#8a8378';
      ctx.fill();
      ctx.strokeStyle = '#2a1d14';
      ctx.lineWidth = 2;
      ctx.stroke();
      ctx.fillStyle = 'rgba(255,245,220,0.35)';
      ctx.beginPath();
      ctx.arc(-3, -3, 3, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
      return;
    }
    ctx.globalCompositeOperation = 'lighter';
    if (p.kind === 'shard') {
      ctx.rotate(ang);
      ctx.scale(s, s);
      ctx.fillStyle = 'rgba(160,215,255,0.5)';
      ctx.beginPath();
      ctx.ellipse(-4, 0, 16, 6, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalCompositeOperation = 'source-over';
      ctx.fillStyle = '#e8f6ff';
      ctx.strokeStyle = '#5a8ab8';
      ctx.lineWidth = 1.2;
      ctx.beginPath();
      ctx.moveTo(12, 0);
      ctx.lineTo(0, -4);
      ctx.lineTo(-10, 0);
      ctx.lineTo(0, 4);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
      ctx.restore();
      return;
    }
    const fire = p.kind === 'fireball';
    const r = (fire ? 11 : 6) * s;
    const col = fire ? '#ff7a1c' : (p.color ?? '#9fd8ff');
    const flick = 1 + Math.sin(p.t * 40) * 0.08;
    ctx.fillStyle = col;
    ctx.globalAlpha = 0.28;
    ctx.beginPath();
    ctx.arc(0, 0, r * 2.4 * flick, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 0.6;
    ctx.beginPath();
    ctx.arc(0, 0, r * 1.35, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;
    ctx.fillStyle = fire ? '#ffe9a0' : '#ffffff';
    ctx.beginPath();
    ctx.arc(0, 0, r * 0.65, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  /** A flickering bolt: a wide soft glow under a bright core, redrawn jagged every few frames. */
  private drawArc(ctx: CanvasRenderingContext2D, a: Arc) {
    const k = Math.max(0, a.life / a.max);
    if (a.tendril) {
      this.drawTendril(ctx, a, k);
      return;
    }
    // Re-jag now and then so the bolt crackles instead of hanging still.
    if (Math.random() < 0.35 && a.pts.length > 2) {
      const first = a.pts[0];
      const last = a.pts[a.pts.length - 1];
      const len = Math.hypot(last.x - first.x, last.y - first.y);
      a.pts = jagged(first.x, first.y, last.x, last.y, Math.min(60, len * 0.22));
    }
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    const line = (pts: { x: number; y: number }[]) => {
      ctx.beginPath();
      pts.forEach((p, i) => (i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
      ctx.stroke();
    };
    for (const [w, alpha, col] of [[a.width * 5, 0.18, a.color], [a.width * 2.2, 0.45, a.color], [a.width, 1, a.core]] as const) {
      ctx.globalAlpha = alpha * k;
      ctx.strokeStyle = col;
      ctx.lineWidth = w;
      line(a.pts);
      ctx.lineWidth = w * 0.55;
      for (const b of a.branches) line(b);
    }
    ctx.restore();
  }

  /** A tendril lashes out (grows from the caster in its first fifth), writhes, then withers. */
  private drawTendril(ctx: CanvasRenderingContext2D, a: Arc, k: number) {
    const t = a.tendril!;
    const age = a.max - a.life;
    const reach = Math.min(1, age / (a.max * 0.22));
    const dx = t.x1 - t.x0;
    const dy = t.y1 - t.y0;
    const len = Math.hypot(dx, dy) || 1;
    const nx = -dy / len;
    const ny = dx / len;
    const pts: { x: number; y: number }[] = [];
    const n = 22;
    for (let i = 0; i <= n; i++) {
      const f = (i / n) * reach;
      // Two waves travelling along the tendril, pinned at both ends.
      const w = Math.sin(f * Math.PI * 3 - age * 14 + t.seed) * 0.7 + Math.sin(f * Math.PI * 5 + age * 9 + t.seed * 2) * 0.3;
      const off = w * t.amp * Math.sin(f * Math.PI);
      pts.push({ x: t.x0 + dx * f + nx * off, y: t.y0 + dy * f + ny * off });
    }
    const line = () => {
      ctx.beginPath();
      pts.forEach((p, i) => (i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
      ctx.stroke();
    };
    ctx.save();
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    const fade = Math.min(1, k * 2.5);
    // A faint glow of its own colour around it, then the dark sinew, the flesh and a bright vein.
    ctx.globalCompositeOperation = 'lighter';
    ctx.globalAlpha = 0.22 * fade;
    ctx.strokeStyle = a.color;
    ctx.lineWidth = a.width * 4.5;
    line();
    ctx.globalCompositeOperation = 'source-over';
    for (const [w, col, alpha] of [[a.width * 2.3, t.dark, 0.95], [a.width * 1.5, a.color, 1], [a.width * 0.45, a.core, 0.9]] as const) {
      ctx.globalAlpha = alpha * fade;
      ctx.strokeStyle = col;
      ctx.lineWidth = w;
      line();
    }
    ctx.restore();
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
