// Canvas owner and main loop. One scene is active at a time; React draws the
// interface on top and lets unhandled pointer input fall through to the canvas.

export interface PointerInfo {
  x: number;
  y: number;
  button: number;
  shift: boolean;
}

export interface Scene {
  update(dt: number, time: number): void;
  render(ctx: CanvasRenderingContext2D, w: number, h: number, time: number): void;
  pointerMove?(p: PointerInfo): void;
  pointerDown?(p: PointerInfo): void;
  pointerUp?(p: PointerInfo): void;
  wheel?(delta: number, p: PointerInfo): void;
  key?(e: KeyboardEvent): void;
  dispose?(): void;
  /** Playback speed of this scene, on top of the engine's timeScale. */
  speed?: number;
}

export class Engine {
  canvas: HTMLCanvasElement;
  ctx: CanvasRenderingContext2D;
  scene: Scene | null = null;
  w = 0;
  h = 0;
  dpr = 1;
  time = 0;
  private last = 0;
  private raf = 0;
  private dragging = false;
  private dragStart = { x: 0, y: 0 };
  /** Called when the camera is dragged with the right/middle button. */
  onDrag: ((dx: number, dy: number) => void) | null = null;
  fps = 0;
  /** Simulation speed multiplier (play-test automation). */
  timeScale = 1;
  private frames = 0;
  private fpsT = 0;

  constructor(canvas: HTMLCanvasElement) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d', { alpha: false })!;
    this.resize();
    window.addEventListener('resize', () => this.resize());
    canvas.addEventListener('pointermove', (e) => {
      const p = this.info(e);
      if (this.dragging && this.onDrag) {
        this.onDrag(p.x - this.dragStart.x, p.y - this.dragStart.y);
        this.dragStart = { x: p.x, y: p.y };
      }
      this.scene?.pointerMove?.(p);
    });
    canvas.addEventListener('pointerdown', (e) => {
      const p = this.info(e);
      if (e.button === 1 || e.button === 2) {
        this.dragging = true;
        this.dragStart = { x: p.x, y: p.y };
      }
      this.scene?.pointerDown?.(p);
    });
    window.addEventListener('pointerup', (e) => {
      this.dragging = false;
      this.scene?.pointerUp?.(this.info(e));
    });
    canvas.addEventListener('contextmenu', (e) => e.preventDefault());
    canvas.addEventListener(
      'wheel',
      (e) => {
        e.preventDefault();
        this.scene?.wheel?.(e.deltaY, this.info(e));
      },
      { passive: false },
    );
    window.addEventListener('keydown', (e) => {
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA') return;
      this.scene?.key?.(e);
    });
  }

  private info(e: PointerEvent | WheelEvent | MouseEvent): PointerInfo {
    const r = this.canvas.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top, button: e.button, shift: e.shiftKey };
  }

  resize() {
    this.dpr = Math.min(2, window.devicePixelRatio || 1);
    this.w = window.innerWidth;
    this.h = window.innerHeight;
    this.canvas.width = Math.round(this.w * this.dpr);
    this.canvas.height = Math.round(this.h * this.dpr);
    this.canvas.style.width = `${this.w}px`;
    this.canvas.style.height = `${this.h}px`;
  }

  setScene(s: Scene | null) {
    this.scene?.dispose?.();
    this.scene = s;
  }

  start() {
    const loop = (t: number) => {
      const real = Math.min(0.05, (t - (this.last || t)) / 1000);
      const dt = real * this.timeScale * (this.scene?.speed ?? 1);
      this.last = t;
      this.time += dt;
      this.frames++;
      this.fpsT += real;
      if (this.fpsT >= 1) {
        this.fps = this.frames / this.fpsT;
        this.frames = 0;
        this.fpsT = 0;
      }
      const ctx = this.ctx;
      ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
      if (this.scene) {
        this.scene.update(dt, this.time);
        this.scene.render(ctx, this.w, this.h, this.time);
      } else {
        ctx.fillStyle = '#16120d';
        ctx.fillRect(0, 0, this.w, this.h);
      }
      this.raf = requestAnimationFrame(loop);
    };
    this.raf = requestAnimationFrame(loop);
  }

  stop() {
    cancelAnimationFrame(this.raf);
  }
}
