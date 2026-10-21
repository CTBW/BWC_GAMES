import { prefs } from '../core/prefs';
import type { Dir } from '../core/types';
import { Rng, hash2 } from '../core/rng';
import { OUTWARD } from '../battle/mapgen';
import { ABILITIES } from '../data/abilities';
import { PROPS, TERRAIN } from '../data/terrain';
import { UNIT_TYPES } from '../data/units';
import { EDGE_NAME, INWARD, type Battle, type FacingOption } from '../battle/battle';
import { squadName } from '../battle/squad';
import { runEnemyAi } from '../battle/ai';
import { DIRS, dirTo, dist, key, manhattan, tileAt, tilePassable, unitAt } from '../battle/grid';
import type { AttackPreview, BattleEvent, BattleUnit, Edge, MoraleState, Pt } from '../battle/types';
import { Atmosphere } from './atmosphere';
import { drawCastShadow, drawSprite, flashOf, opaqueAt, shadowOf, sprite, type Sprite } from './assets';
import type { PointerInfo, Scene } from './engine';
import { Fx } from './fx';
import { LH, TH, TW, clamp, easeInOutQuad, easeOutCubic, isoX, isoY, lerp, makeCamera, screenToWorld, updateCamera, worldToScreen, type Camera } from './iso';
import { buildTerrain, type TerrainLayer } from './terrain';
import { facesCamera, formationSlots } from './formation';
import { hasShieldPoses } from './figures';
import { championOf, killMembers, makeMembers, memberHeight, memberScale, reform, standing, stepMembers, type Member } from './squadView';
import { sfx } from '../audio/sfx';

/** A fallen soldier left on the field. */
interface Corpse {
  wx: number;
  wy: number;
  /** Depth: under the living on the same tile. */
  d: number;
  type: string;
  variant: number;
  flip: boolean;
  scale: number;
}

/**
 * What the screen shows of a squad: one anchor on the grid (moved, turned and
 * targeted as a single unit) and the soldiers standing around it.
 */
export interface UnitView {
  uid: string;
  /** Squad anchor on the grid (fractional while marching). */
  x: number;
  y: number;
  h: number;
  facing: Dir;
  /** Squad-wide jump (war cries). */
  hop: number;
  shake: number;
  alpha: number;
  /** The soldiers; their offsets are relative to the anchor. */
  members: Member[];
  /** Formation spacing: 1 normal, tighter behind a shield wall, ragged when fleeing. */
  tight: number;
  /** Marching: time along the march and how strongly the stride shows (0..1). */
  walkT: number;
  walking: number;
  marching: boolean;
  hp: number;
  /** Soldiers shown standing; follows playback, not the rules (which run ahead). */
  alive: number;
  morale: number;
  status: BattleUnit['status'];
  stance: BattleUnit['stance'];
  routing: boolean;
  visible: boolean;
  /** Still beyond the edge with a coming wave (drawn when the wave is near). */
  reserve: boolean;
}

export interface HoverInfo {
  tile?: Pt;
  unit?: string;
  preview?: AttackPreview & { target: string; from?: Pt; ability?: string; moveFirst: boolean };
  path?: Pt[];
  zoc?: number;
  /** Where the previewed move ends, the facing it arrives with, and the other facings that tile allows. */
  dest?: Pt;
  facing?: Dir;
  facings?: Dir[];
  /** The move only turns the squad: it steps out and back onto its own tile. */
  turn?: boolean;
}

export interface BattleUiState {
  selected?: string;
  hover: HoverInfo;
  ability?: string;
  busy: boolean;
  banner?: { text: string; sub?: string; tone: 'player' | 'enemy' | 'neutral'; id: number };
  log: { text: string; tone?: string }[];
  showGrid: boolean;
  danger: boolean;
  version: number;
  /** Turn and side as played back so far; the rules run ahead of the animation. */
  turn: number;
  side: 'player' | 'enemy';
}

interface Anim {
  t: number;
  dur: number;
  step: (f: number) => void;
  done?: () => void;
  started?: boolean;
  start?: () => void;
  /** Squads this animation shows; later events about them wait for it. */
  uids?: string[];
  /** Turn banners, waves and the end: nothing else plays alongside. */
  barrier?: boolean;
  /** Seconds to wait before starting (a host's march sets off ragged, not in lockstep). */
  delay?: number;
}

/** Events that play alone: everything before them finishes first, nothing starts beside them. */
const BARRIERS = new Set<BattleEvent['t']>(['turn', 'end', 'warn', 'wave', 'horn', 'overrun', 'broken', 'relief']);

/** Morale changes that every squad gets at once: shown by banners and the log, not as floating numbers. */
const QUIET_MORALE = new Set(['Steadied', 'Surrounded', 'The battle is turning', 'Another wave', "The warchief's host", 'The war horn', 'The horn is silenced', 'Relief is near', 'The warchief is slain']);

/** One of the Margrave's horsemen relieving a last stand: from beyond the edge to where he reins in (grid units). */
interface ReliefRider {
  x0: number;
  y0: number;
  x1: number;
  y1: number;
  delay: number;
  /** Gallop speed in tiles per second. */
  speed: number;
  facing: Dir;
  variant: number;
  dust: number;
}

/** Most animations running at once (an enemy turn plays its squads side by side). */
const MAX_ANIMS = 14;

const MORALE_COLORS: Record<MoraleState, string> = {
  confident: '#9fe0ff',
  steady: '#6fb3ff',
  shaken: '#e5c35a',
  wavering: '#f08a3c',
  broken: '#e05555',
};

export class BattleScene implements Scene {
  b: Battle;
  terrain: TerrainLayer;
  cam: Camera;
  views = new Map<string, UnitView>();
  /** Every soldier who has fallen this battle, where he fell. */
  corpses: Corpse[] = [];
  fx = new Fx();
  atmo: Atmosphere;
  ui: BattleUiState = { hover: {}, busy: false, log: [], showGrid: true, danger: false, version: 0, turn: 1, side: 'player' };
  /** Battle playback speed, remembered between battles. */
  speed = prefs().battleSpeed;
  private listeners = new Set<() => void>();
  private queue: { e: BattleEvent; uids: string[] }[] = [];
  /** The animation `play` just created (moved into `anims` by the scheduler). */
  private anim: Anim | null = null;
  private anims: Anim[] = [];
  /** Squads of the action whose consequences are being queued (morale, falls, logs follow it). */
  private cause: string[] = [];
  /** Seconds before the camera may follow another action on its own. */
  private focusHold = 0;
  private pointer = { x: 0, y: 0 };
  private keys = new Set<string>();
  private reachCache: { uid: string; reach: Map<number, { cost: number; prev: number; zoc: number }> } | null = null;
  private statesCache: { uid: string; states: Map<number, { cost: number; prev: number; zoc: number }> } | null = null;
  /** Facing picked with Q / E for one destination tile; pointing at another edge replaces it. */
  private facingPick: { at: number; facing: Dir; pointed?: Dir } | null = null;
  private dangerCache: Set<number> | null = null;
  private targetCache: { key: string; list: BattleUnit[] } | null = null;
  private w = 1;
  private h = 1;
  private bannerId = 0;
  /** World rectangle the camera centre may roam, and the furthest zoom out that still helps. */
  private bounds = { x0: 0, y0: 0, x1: 0, y1: 0 };
  minZoom = 0.45;
  /** The held ground is being overrun (shown until the company retakes it). */
  private overrunWarn = false;
  private minimap: HTMLCanvasElement | null = null;
  /** The rest of the host, massed beyond the far edge: painted once, faded out when it has all come or fled. */
  private host: { canvas: HTMLCanvasElement | ImageBitmap; x: number; y: number; d: number } | null = null;
  /** The ground layer as an immutable GPU bitmap once it is ready (drawing the canvas itself is far slower). */
  private groundImage: ImageBitmap | null = null;
  private hostAlpha = 1;
  /** Columns of smoke from burning steadings on the horizon. */
  private smoke: { x: number; y: number; t: number; rate: number }[] = [];
  /** Torches carried in the host beyond the edge (world points), lit at night. */
  private hostTorches: { x: number; y: number }[] = [];
  /** How dark it is in a battle fought through the night: 1 at midnight, 0 at sunrise. */
  nightLevel = 0;
  /** Filtering for the ground layer and for sprites (switchable for performance checks). */
  groundQuality: ImageSmoothingQuality = 'low';
  /** Cast shadows for every soldier even on large fields. */
  richShadows = false;
  spriteQuality: ImageSmoothingQuality = 'high';
  onEnd: ((result: string) => void) | null = null;
  private ended = false;
  /** The whole host is breaking (relief or warchief slain): one banner says it, not a float per squad. */
  private hordeBroken = false;
  /** The relief of a last stand: riders charging in with the sunrise (drawn only, no rules). */
  private relief: { t: number; glow: number; edge: Edge; riders: ReliefRider[] } | null = null;

  constructor(b: Battle) {
    this.b = b;
    const m = b.map;
    this.terrain = buildTerrain({
      w: m.w,
      h: m.h,
      border: m.border,
      // The open approaches beyond the edges are painted as ground too.
      tiles: [...m.tiles, ...(m.outerGround ?? []).map((g) => ({ x: g.x, y: g.y, h: 0, terrain: g.terrain }))],
      seed: m.seed,
      palette: m.biome === 'camp' ? 'camp' : 'summer',
    });
    // Open a little closer than the whole map, leaning toward the company,
    // so the squads read as soldiers rather than specks. A last stand opens
    // wider, with the company's walls below and the enemy's ground above.
    const deploy = m.playerDeploy.length ? m.playerDeploy : [{ x: (m.w - 1) / 2, y: (m.h - 1) / 2 }];
    const px = deploy.reduce((s, p) => s + p.x, 0) / deploy.length;
    const py = deploy.reduce((s, p) => s + p.y, 0) / deploy.length;
    const large = m.scale === 'large';
    const fx = lerp((m.w - 1) / 2, px, large ? 0.35 : 0.4);
    const fy = lerp((m.h - 1) / 2, py, large ? 0.35 : 0.4);
    this.cam = makeCamera(isoX(fx, fy), isoY(fx, fy) + 20, large ? 0.72 : 1.0);
    this.computeBounds();
    if (large) this.frameStand();
    this.bakeOuter();
    createImageBitmap(this.terrain.canvas).then((bmp) => (this.groundImage = bmp)).catch(() => {});
    this.buildHost();
    this.buildSmoke();
    this.atmo = new Atmosphere(m.seed);
    this.atmo.night = !!b.setup.darkness;
    if (b.objective.dawn) {
      this.nightLevel = 1;
      this.atmo.night = true;
    }
    for (const u of b.units) this.views.set(u.uid, this.makeView(u));
    window.addEventListener('keyup', this.keyUp);
    if (b.phase === 'deploy') {
      this.banner('Deploy your company', 'Click a squad, then a blue tile, to change the formation', 'neutral');
      const first = b.active('player')[0];
      if (first) this.ui.selected = first.uid;
    }
  }

  dispose() {
    window.removeEventListener('keyup', this.keyUp);
  }

  /** The field's corners (and the approaches beyond them) in world pixels, and the painted ground around it. */
  private computeBounds() {
    const m = this.b.map;
    const pad = (e: string) => ((m.approaches ?? []).includes(e as never) ? 4 : 0.5);
    const box = (pts: number[][]) => {
      const xs = pts.map(([gx, gy]) => isoX(gx, gy));
      const ys = pts.map(([gx, gy]) => isoY(gx, gy));
      return { x0: Math.min(...xs), y0: Math.min(...ys), x1: Math.max(...xs), y1: Math.max(...ys) };
    };
    const f = box([[-pad('w'), -pad('n')], [m.w - 1 + pad('e'), -pad('n')], [-pad('w'), m.h - 1 + pad('s')], [m.w - 1 + pad('e'), m.h - 1 + pad('s')]]);
    this.bounds = { x0: f.x0, y0: f.y0 - 120, x1: f.x1, y1: f.y1 };
    const B = m.border - 0.5;
    this.ground = box([[-B, -B], [m.w - 1 + B, -B], [-B, m.h - 1 + B], [m.w - 1 + B, m.h - 1 + B]]);
  }

  /**
   * Paint the decorative forest ring beyond the field into the ground layer,
   * back to front, once. It never changes, so a large field does not redraw
   * hundreds of trees every frame, and it is always drawn behind the squads,
   * so the forest at the near edges never hides a soldier.
   */
  private bakeOuter() {
    const tl = this.terrain;
    const x = tl.canvas.getContext('2d')!;
    x.save();
    x.setTransform(tl.scale, 0, 0, tl.scale, -tl.ox * tl.scale, -tl.oy * tl.scale);
    x.imageSmoothingQuality = 'high';
    const outer = this.b.map.outer.slice().sort((a, b) => a.x + a.y - (b.x + b.y));
    for (const o of outer) {
      const s = sprite(PROPS[o.prop]?.sprite ?? o.prop, o.v);
      const px = isoX(o.x, o.y) + (hash2(o.x, o.y, 5) - 0.5) * 40;
      const py = isoY(o.x, o.y, o.h) + (hash2(o.x, o.y, 6) - 0.5) * 20;
      const flip = !s.noShadow && hash2(o.x, o.y, 9) > 0.5;
      const sc = 0.9 + hash2(o.x, o.y, 3) * 0.35;
      drawCastShadow(x, s, px, py, flip, sc, o.prop.startsWith('tree') ? 0.2 : 0.16);
      drawSprite(x, s, px, py, { flip, scale: sc });
    }
    x.restore();
  }

  /**
   * Open a last stand on the whole confrontation: the company's ground and
   * the horde's, centred between them and zoomed to fit both with room for
   * the HUD (a wide view of the walls and what is coming at them).
   */
  private frameStand() {
    const m = this.b.map;
    const pts = [...m.playerDeploy, ...m.enemyDeploy, ...(m.zone ?? [])];
    if (!pts.length) return;
    const xs = pts.map((p) => isoX(p.x, p.y));
    const ys = pts.map((p) => isoY(p.x, p.y));
    const x0 = Math.min(...xs) - 90;
    const x1 = Math.max(...xs) + 90;
    const y0 = Math.min(...ys) - 140;
    const y1 = Math.max(...ys) + 50;
    const vw = Math.max(800, window.innerWidth - 560);
    const vh = Math.max(500, window.innerHeight - 260);
    const z = clamp(Math.min(vw / (x1 - x0), vh / (y1 - y0)), 0.4, 0.8);
    this.cam.x = this.cam.tx = (x0 + x1) / 2;
    this.cam.y = this.cam.ty = (y0 + y1) / 2 + 30 / z;
    this.cam.zoom = this.cam.tzoom = z;
  }

  /**
   * The host behind the band you are fighting: rank on rank of dark figures,
   * spears and standards beyond the main approach, too far off to fight yet.
   * Small battles show a glimpse of it; a last stand shows a sea of it.
   */
  private buildHost() {
    const m = this.b.map;
    const edge = m.approaches?.[0];
    const lanes = edge ? m.entries?.[edge] : undefined;
    if (!edge || !lanes?.length) return;
    const stand = this.b.setup.kind === 'stand';
    const count = stand ? 170 : m.scale === 'large' ? 90 : 46;
    const rng = new Rng((m.seed ^ 0x51ab) >>> 0);
    const along = (p: Pt) => (edge === 'n' || edge === 's' ? p.x : p.y);
    const lo = Math.min(...lanes.map(along)) - 1;
    const hi = Math.max(...lanes.map(along)) + 1;
    const out = OUTWARD[edge];
    const inward = INWARD_DIR[edge];
    const kinds: [string, number][] = [['goblin_rabble', 34], ['goblin_spear', 28], ['goblin_archer', 14], ['orc_warrior', 10], ['orc_brute', 5], ['wolf_rider', stand ? 6 : 3]];
    const total = kinds.reduce((s, k) => s + k[1], 0);
    const figs: { wx: number; wy: number; key: string; v: number; flip: boolean; banner: boolean }[] = [];
    const near = m.scale === 'large' ? 6 : 4.2;
    for (let i = 0; i < count; i++) {
      const a = rng.range(lo, hi);
      const depth = rng.range(near, m.border - 0.4);
      const gx = edge === 'n' || edge === 's' ? a + out.x * depth : (edge === 'w' ? -1 : m.w) + out.x * (depth - 1);
      const gy = edge === 'n' || edge === 's' ? (edge === 'n' ? -1 : m.h) + out.y * (depth - 1) : a + out.y * depth;
      let r = rng.range(0, total);
      let type = kinds[0][0];
      for (const [k, wgt] of kinds) {
        if ((r -= wgt) <= 0) {
          type = k;
          break;
        }
      }
      const pk = poseKey(type, 'idle', inward);
      figs.push({ wx: isoX(gx, gy) + rng.range(-12, 12), wy: isoY(gx, gy) + rng.range(-6, 6), key: pk.key, v: rng.int(0, 5), flip: pk.flip, banner: rng.chance(0.07) });
    }
    figs.sort((p, q) => p.wy - q.wy);
    const xs = figs.map((f) => f.wx);
    const ys = figs.map((f) => f.wy);
    const x0 = Math.min(...xs) - 120;
    const y0 = Math.min(...ys) - 200;
    const c = document.createElement('canvas');
    c.width = Math.ceil(Math.max(...xs) + 120 - x0);
    c.height = Math.ceil(Math.max(...ys) + 40 - y0);
    const x = c.getContext('2d')!;
    x.translate(-x0, -y0);
    for (const f of figs) {
      if (f.banner) {
        const s = sprite('war_banner', f.v);
        drawSprite(x, s, f.wx, f.wy, { scale: 0.8 });
        continue;
      }
      const s = sprite(f.key, f.v);
      const sc = f.key.startsWith('wolf') ? 0.5 : f.key.startsWith('goblin_rabble') ? 0.46 : 0.5;
      if (figs.indexOf(f) % 4 === 0) this.hostTorches.push({ x: f.wx, y: f.wy - 46 });
      drawSprite(x, s, f.wx, f.wy, { flip: f.flip, scale: sc });
      // Distance and dusk: the host reads as a dark mass, not as squads.
      drawSprite(x, s, f.wx, f.wy, { flip: f.flip, scale: sc, alpha: 0.5, img: shadowOf(s) });
    }
    // Draw order: behind the field for the far edges, in front of nothing on the field.
    const deepest = Math.min(...figs.map((f) => f.wy)) / 32;
    this.host = { canvas: c, x: x0, y: y0, d: edge === 'n' || edge === 'w' ? -1e3 : deepest };
    // Swap the painted canvas for a GPU bitmap as soon as one is made.
    const host = this.host;
    createImageBitmap(c).then((bmp) => {
      if (this.host === host) host.canvas = bmp;
    }).catch(() => {});
  }

  /** Smoke rising from steadings burning on the horizon, beyond the far corners. */
  private buildSmoke() {
    const m = this.b.map;
    const rng = new Rng((m.seed ^ 0x2f1) >>> 0);
    const n = this.b.setup.kind === 'stand' ? 3 : this.b.setup.kind === 'raid' ? 3 : 2;
    for (let i = 0; i < n; i++) {
      const gx = rng.range(-m.border + 1, m.w * 0.7);
      const gy = gx < 0 ? rng.range(-m.border + 1, m.h * 0.5) : rng.range(-m.border + 1, -3);
      this.smoke.push({ x: isoX(gx, gy), y: isoY(gx, gy), t: rng.range(0, 1), rate: rng.range(0.18, 0.3) });
    }
  }

  /** Painted ground (map and forest ring): the view never shows past it. */
  private ground = { x0: 0, y0: 0, x1: 0, y1: 0 };

  /**
   * Keep the camera over the field: its centre stays over the field and its
   * view inside the painted ground. Zooming out stops when the field fits.
   */
  private clampCamera() {
    const b = this.bounds;
    const g = this.ground;
    const fit = Math.min(this.w / (b.x1 - b.x0 + 160), this.h / (b.y1 - b.y0 + 160));
    this.minZoom = Math.max(0.22, Math.min(0.45, fit));
    this.cam.tzoom = clamp(this.cam.tzoom, this.minZoom, 1.6);
    const hw = this.w / 2 / this.cam.tzoom;
    const hh = this.h / 2 / this.cam.tzoom;
    const lim = (v: number, lo: number, hi: number, glo: number, ghi: number, half: number) => {
      const a = Math.max(lo, glo + half);
      const z = Math.min(hi, ghi - half);
      return a <= z ? clamp(v, a, z) : clamp(v, Math.min(lo, hi), Math.max(lo, hi));
    };
    this.cam.tx = lim(this.cam.tx, b.x0, b.x1, g.x0, g.x1, hw);
    this.cam.ty = lim(this.cam.ty, b.y0, b.y1, g.y0 - 200, g.y1, hh);
  }

  /** Reserve squads of waves close enough to be seen massing beyond their edge, with turns until they march in. */
  staged(): Map<string, number> {
    const out = new Map<string, number>();
    const lead = this.b.map.scale === 'large' ? 2 : 1;
    this.b.waves.forEach((w, i) => {
      if (this.b.waveState[i] === 'cancelled') return;
      if (w.horn && this.b.horn !== 'sounded') return;
      const dueIn = w.turn - this.ui.turn;
      if (dueIn > lead) return;
      for (const uid of w.uids) if (this.views.get(uid)?.reserve) out.set(uid, Math.max(0, dueIn));
    });
    return out;
  }

  /** The next wave as the HUD shows it: label, size, edge and turns until it marches in. */
  nextWaveInfo(): { label: string; count: number; edge: string; dueIn: number; index: number; total: number } | undefined {
    const n = this.b.nextWave();
    if (!n) return undefined;
    const visible = this.b.waves.filter((w) => !w.horn || this.b.horn === 'sounded');
    return {
      label: n.wave.label,
      count: n.wave.uids.length,
      edge: EDGE_NAME[n.wave.edge],
      dueIn: Math.max(0, n.turn - this.ui.turn),
      index: visible.indexOf(n.wave) + 1,
      total: visible.length,
    };
  }

  private keyUp = (e: KeyboardEvent) => {
    this.keys.delete(e.key.toLowerCase());
    if (e.key === 'Alt') {
      this.ui.danger = false;
      this.notify();
    }
  };

  private makeView(u: BattleUnit): UnitView {
    return {
      uid: u.uid,
      x: u.x,
      y: u.y,
      h: tileAt(this.b.map, u.x, u.y)?.h ?? 0,
      facing: u.facing,
      hop: 0,
      shake: 0,
      alpha: 1,
      members: makeMembers(u),
      tight: 1,
      walkT: 0,
      walking: 0,
      marching: false,
      hp: u.hp,
      alive: u.alive,
      morale: u.morale,
      status: u.status,
      stance: u.stance,
      routing: u.status === 'routing',
      visible: u.status !== 'reserve',
      reserve: u.status === 'reserve',
    };
  }

  /** Re-form the squad's standing soldiers for its current number, facing and order. */
  private reformView(v: UnitView, opts: { dur?: number; delay?: number; stagger?: number; instant?: boolean } = {}) {
    const u = this.b.unit(v.uid);
    reform(v.members, u.size, v.facing, {
      typeId: u.typeId,
      dur: opts.dur ?? 0.38,
      delay: opts.delay,
      stagger: opts.stagger ?? 0.035,
      instant: opts.instant,
      tight: v.tight,
      champion: championOf(u),
      spread: v.routing ? 0.35 : 0,
    });
  }

  /** World position of one soldier (anchor + slot + lunge). */
  private memberPos(v: UnitView, m: Member) {
    const p = this.viewPos(v);
    return { x: p.x + m.x + m.lunge.x, y: p.y + m.y + m.lunge.y };
  }

  /** A soldier's body comes to rest: it stays on the field where he fell. */
  private addCorpse(v: UnitView, m: Member) {
    const u = this.b.unit(v.uid);
    const p = this.memberPos(v, m);
    this.corpses.push({ wx: p.x, wy: p.y, d: Math.round(v.x) + Math.round(v.y) - 0.3, type: m.type, variant: m.variant, flip: m.fallFlip, scale: memberScale(u) });
    if (this.corpses.length > 160) this.corpses.shift();
    this.fx.burst(p.x, p.y, 1, 4, { shape: 'puff', color: 'rgba(170,150,110,1)', speed: 40, vz: 18, gravity: 20, size: 5, max: 0.7 });
  }

  subscribe(fn: () => void) {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  notify() {
    this.ui.version++;
    for (const l of this.listeners) l();
  }

  private banner(text: string, sub: string | undefined, tone: 'player' | 'enemy' | 'neutral') {
    this.ui.banner = { text, sub, tone, id: ++this.bannerId };
    this.notify();
  }

  // ---------------------------------------------------------------- commands (from UI)

  get busy() {
    return this.anims.length > 0 || this.queue.length > 0 || this.fx.busy;
  }

  select(uid?: string) {
    if (uid) {
      const u = this.b.unit(uid);
      if (u.faction !== 'player' || u.status !== 'active') return;
      const v = this.views.get(uid)!;
      this.focusOn(v.x, v.y, false);
    }
    this.ui.selected = uid;
    this.ui.ability = undefined;
    this.reachCache = null;
    this.statesCache = null;
    this.facingPick = null;
    sfx('select');
    this.notify();
  }

  setAbility(id?: string) {
    const u = this.selectedUnit();
    if (!u || this.busy) return;
    if (!id) {
      this.ui.ability = undefined;
      this.notify();
      return;
    }
    const ab = ABILITIES[id];
    if (ab.kind === 'stance') {
      if (this.b.useStance(u.uid, id)) this.pump();
    } else if (ab.kind === 'shout') {
      if (this.b.shout(u.uid, id)) this.pump();
    } else {
      this.ui.ability = this.ui.ability === id ? undefined : id;
      sfx('click');
    }
    this.notify();
  }

  /**
   * Q / E: arrive on the previewed tile from another side. A squad faces the
   * way it last stepped, so this picks another path to the same tile.
   */
  cycleFacing(dir: 1 | -1) {
    const h = this.ui.hover;
    if (!h.dest || h.facing === undefined || !h.facings || h.facings.length < 2) {
      sfx('deny');
      return;
    }
    const i = h.facings.indexOf(h.facing);
    const f = h.facings[(i + dir + h.facings.length) % h.facings.length];
    this.facingPick = { at: key(h.dest.x, h.dest.y), facing: f, pointed: h.dest && h.tile && h.dest.x === h.tile.x && h.dest.y === h.tile.y ? this.pointing(h.dest) : undefined };
    this.refreshHover();
    sfx('click');
  }

  /** Take back a soldier's move this turn (only before that soldier attacks). */
  redo(uid = this.ui.selected) {
    if (this.busy || !uid) return;
    if (this.b.redoMove(uid)) {
      this.pump();
      this.ui.selected = uid;
      this.ui.ability = undefined;
      sfx('click');
      this.notify();
    } else sfx('deny');
  }

  endUnit() {
    const u = this.selectedUnit();
    if (!u || this.busy) return;
    this.b.endUnit(u.uid);
    this.selectNext();
  }

  selectNext() {
    const list = this.b.active('player').filter((x) => !x.done);
    if (!list.length) {
      this.select(undefined);
      return;
    }
    const cur = list.findIndex((x) => x.uid === this.ui.selected);
    this.select(list[(cur + 1) % list.length].uid);
  }

  begin() {
    if (this.b.phase !== 'deploy') return;
    this.b.begin(runEnemyAi);
    this.pump();
    sfx('horn');
  }

  endTurn() {
    if (this.busy || this.b.phase !== 'player') return;
    this.ui.selected = undefined;
    this.ui.ability = undefined;
    this.b.endTurn(runEnemyAi);
    this.pump();
  }

  retreat() {
    if (this.busy || this.b.phase !== 'player') return;
    this.b.retreat();
    this.pump();
  }

  selectedUnit(): BattleUnit | undefined {
    if (!this.ui.selected) return undefined;
    const u = this.b.unit(this.ui.selected);
    return u.status === 'active' ? u : undefined;
  }

  // ---------------------------------------------------------------- event playback

  pump() {
    for (const e of this.b.drain()) this.queue.push({ e, uids: this.involved(e) });
    this.reachCache = null;
    this.statesCache = null;
    this.dangerCache = null;
    this.targetCache = null;
    this.ui.busy = this.busy;
    this.notify();
  }

  /**
   * The squads an event shows. Consequences (morale, falls, routs, log lines)
   * also wait for the action that caused them, so a comrade's fall never
   * shakes anyone before it is seen.
   */
  private involved(e: BattleEvent): string[] {
    const withCause = (uid: string) => [...new Set([uid, ...this.cause])];
    switch (e.t) {
      case 'move':
      case 'face':
      case 'stance':
      case 'halt':
      case 'spawn':
      case 'shout':
      case 'horn':
      case 'broken':
        this.cause = [e.uid];
        return [e.uid];
      case 'attack':
        this.cause = [e.uid, e.target];
        return this.cause.slice();
      case 'push':
      case 'heal':
      case 'morale':
      case 'mstate':
      case 'down':
      case 'rout':
      case 'rally':
      case 'fled':
        return withCause(e.uid);
      case 'log':
        return this.cause.slice();
      default:
        this.cause = [];
        return [];
    }
  }

  /**
   * Start queued events in order. Events about different squads may run side
   * by side, so a host of thirty marches as one surge instead of one by one;
   * events about the same squads, and barriers (turns, waves, the end), keep
   * their order.
   */
  private next() {
    if (this.anims.some((a) => a.barrier)) return;
    const busy = new Set<string>();
    for (const a of this.anims) for (const u of a.uids ?? []) busy.add(u);
    let started = 0;
    for (let i = 0; i < this.queue.length; ) {
      const { e, uids } = this.queue[i];
      if (BARRIERS.has(e.t)) {
        if (i > 0 || this.anims.length) return;
        this.queue.splice(i, 1);
        this.anim = null;
        this.play(e);
        if (this.anim) {
          const a: Anim = this.anim;
          this.anim = null;
          a.barrier = true;
          a.uids = uids;
          this.anims.push(a);
          return;
        }
        continue;
      }
      if (this.anims.length >= MAX_ANIMS) return;
      if (uids.some((u) => busy.has(u))) {
        for (const u of uids) busy.add(u);
        i++;
        continue;
      }
      this.queue.splice(i, 1);
      this.anim = null;
      this.play(e);
      if (this.anim) {
        const a: Anim = this.anim;
        this.anim = null;
        a.uids = uids;
        a.delay = (a.delay ?? 0) + Math.min(0.6, started * 0.08);
        this.anims.push(a);
        started++;
        for (const u of uids) busy.add(u);
      }
    }
  }

  private viewPos(v: UnitView) {
    return { x: isoX(v.x, v.y), y: isoY(v.x, v.y, v.h) };
  }

  /** Just above the heads of the squad's rear rank: bars and combat text sit here. */
  private headPos(v: UnitView) {
    const p = this.viewPos(v);
    const u = this.b.unit(v.uid);
    const live = standing(v.members);
    const top = live.length ? Math.min(...live.map((m) => m.y)) : 0;
    return { x: p.x, y: p.y + Math.min(0, top) - memberHeight(u.typeId) - 24 - v.hop };
  }

  /**
   * Bring a point into view. `force` always pans (selecting a squad); other
   * calls pan only when the point is near the screen edge, and at most about
   * once a second, so a turn of many squads does not throw the camera around.
   */
  private focusOn(x: number, y: number, force: boolean) {
    const wx = isoX(x, y);
    const wy = isoY(x, y);
    const s = worldToScreen(this.cam, wx, wy, this.w, this.h);
    const margin = 0.22;
    const off = s.x < this.w * margin || s.x > this.w * (1 - margin) || s.y < this.h * margin || s.y > this.h * (1 - margin);
    if (force || (off && this.focusHold <= 0)) {
      this.cam.tx = wx;
      this.cam.ty = wy;
      this.clampCamera();
      if (!force) this.focusHold = 1.1;
    }
  }

  private play(e: BattleEvent) {
    switch (e.t) {
      case 'log':
        this.ui.log.unshift({ text: e.text, tone: e.tone });
        if (this.ui.log.length > 60) this.ui.log.pop();
        this.notify();
        return;
      case 'turn': {
        const isPlayer = e.faction === 'player';
        this.ui.turn = e.turn;
        this.ui.side = e.faction;
        this.banner(isPlayer ? 'Your Turn' : 'Enemy Turn', `Turn ${e.turn}`, isPlayer ? 'player' : 'enemy');
        sfx(isPlayer ? 'turn' : 'drum');
        this.anim = { t: 0, dur: 0.9, step: () => {} };
        if (isPlayer) {
          const first = this.b.active('player').find((u) => !u.done);
          if (first) this.ui.selected = first.uid;
        }
        return;
      }
      case 'face': {
        // The whole squad turns; the ranks shift their lean toward the new front.
        const v = this.views.get(e.uid)!;
        if (v.facing !== e.facing) {
          v.facing = e.facing;
          this.reformView(v, { dur: 0.28, stagger: 0.025 });
        }
        return;
      }
      case 'move': {
        // One path for the squad: the anchor walks it and every soldier keeps
        // his place in the ranks, turning with the squad at each corner.
        const v = this.views.get(e.uid)!;
        const path = e.path;
        const steps = path.length - 1;
        const u = this.b.unit(e.uid);
        const per = v.routing ? 0.15 : u.faction === 'enemy' ? 0.24 : 0.26;
        let lastStep = -1;
        this.anim = {
          t: 0,
          dur: per * steps,
          start: () => {
            v.marching = true;
            if (u.faction === 'player') this.focusOn(path[path.length - 1].x, path[path.length - 1].y, false);
          },
          step: (f) => {
            const pos = f * steps;
            const i = Math.min(steps - 1, Math.floor(pos));
            const k = pos - i;
            const a = path[i];
            const b = path[i + 1];
            const ha = tileAt(this.b.map, a.x, a.y)?.h ?? 0;
            const hb = tileAt(this.b.map, b.x, b.y)?.h ?? 0;
            v.x = lerp(a.x, b.x, k);
            v.y = lerp(a.y, b.y, k);
            v.h = lerp(ha, hb, easeInOutQuad(k)) + Math.max(0, hb - ha) * Math.sin(k * Math.PI) * 0.4;
            const dir = dirOf(a, b);
            if (dir !== v.facing) {
              v.facing = dir;
              this.reformView(v, { dur: per * 0.8, stagger: 0.02 });
            }
            if (i !== lastStep) {
              lastStep = i;
              // Dust under every pair of boots, not one cloud for the squad.
              for (const m of standing(v.members)) {
                if (Math.random() < 0.5) continue;
                const p = this.memberPos(v, m);
                this.fx.burst(p.x, p.y, 1, 1, { shape: 'puff', color: 'rgba(190,165,120,1)', speed: 18, vz: 14, gravity: 10, size: 4, max: 0.5 });
              }
              sfx('step');
            }
          },
          done: () => {
            const end = path[path.length - 1];
            v.x = end.x;
            v.y = end.y;
            v.h = tileAt(this.b.map, end.x, end.y)?.h ?? 0;
            v.marching = false;
            // Halt and dress the ranks.
            this.reformView(v, { dur: 0.3, stagger: 0.03 });
          },
        };
        return;
      }
      case 'heal': {
        const v = this.views.get(e.uid)!;
        v.hp = e.hp;
        const hp = this.headPos(v);
        const p = this.viewPos(v);
        this.fx.text(hp.x, hp.y - 4, `+${e.amount}`, '#9ff08a', { size: 22 });
        this.fx.text(hp.x, hp.y - 30, e.reason, '#c8f0b0', { size: 14, bold: false, delay: 0.1 });
        this.fx.ring(p.x, p.y, 60, 'rgba(150,240,120,0.8)', 0.6);
        for (const m of standing(v.members)) {
          const q = this.memberPos(v, m);
          this.fx.burst(q.x, q.y - 30, 0, 3, { shape: 'puff', color: 'rgba(150,230,110,1)', speed: 20, vz: 40, gravity: -20, size: 4, max: 0.9 });
        }
        this.anim = { t: 0, dur: 0.5, step: () => {} };
        return;
      }
      case 'attack':
        this.playAttack(e);
        return;
      case 'push': {
        const v = this.views.get(e.uid)!;
        const from = { ...e.from };
        this.anim = {
          t: 0,
          dur: e.blocked ? 0.18 : 0.25,
          step: (f) => {
            if (e.blocked) {
              v.shake = 1 - f;
              return;
            }
            v.x = lerp(from.x, e.to.x, easeOutCubic(f));
            v.y = lerp(from.y, e.to.y, easeOutCubic(f));
          },
          done: () => {
            v.x = e.to.x;
            v.y = e.to.y;
            v.h = tileAt(this.b.map, e.to.x, e.to.y)!.h;
            const p = this.viewPos(v);
            this.fx.burst(p.x, p.y, 4, 6, { shape: 'puff', color: 'rgba(190,165,120,1)', speed: 60, vz: 30, gravity: 20, size: 7, max: 0.7 });
            if (e.blocked) {
              this.fx.text(p.x, this.headPos(v).y, 'Slammed!', '#ffd27a', { size: 18 });
              v.hp = e.hp;
              this.showCasualties(v, v.alive - e.alive, { x: 0, y: -1 });
            }
          },
        };
        return;
      }
      case 'morale': {
        const v = this.views.get(e.uid)!;
        v.morale = e.value;
        // Morale numbers only for the company, and only from the fighting: the
        // turn's upkeep and army-wide news (waves, horns) are told by banners.
        const quiet = QUIET_MORALE.has(e.reason);
        if (Math.abs(e.delta) >= 5 && !quiet && this.b.unit(e.uid).faction === 'player') {
          const hp = this.headPos(v);
          this.fx.text(hp.x, hp.y + 24, `${e.delta > 0 ? '+' : ''}${e.delta} morale`, e.delta > 0 ? '#9fd8ff' : '#c9a7ff', { size: 13, bold: false, delay: 0.15, life: 1.4 });
        }
        return;
      }
      case 'mstate': {
        const v = this.views.get(e.uid)!;
        const worse = rank(e.to) > rank(e.from);
        const mine = this.b.unit(e.uid).faction === 'player';
        // Only bad news floats: a squad of the company shaken or wavering, or a band of the horde about to break.
        if (e.to !== 'broken' && (mine ? worse : e.to === 'wavering')) {
          const hp = this.headPos(v);
          this.fx.text(hp.x, hp.y - 50, cap(e.to), MORALE_COLORS[e.to], { size: 16, delay: 0.35 });
        }
        return;
      }
      case 'down': {
        // The squad is destroyed: whoever is still standing falls now.
        const v = this.views.get(e.uid)!;
        const u = this.b.unit(e.uid);
        const hp = this.headPos(v);
        v.status = e.dead ? 'dead' : 'downed';
        v.stance = undefined;
        v.hp = 0;
        if (standing(v.members).length) this.showCasualties(v, standing(v.members).length, { x: 0, y: -1 });
        v.alive = 0;
        const label = u.leader ? 'Slain' : e.dead ? 'Wiped out' : 'Broken';
        this.fx.text(hp.x, hp.y - 14, label, e.dead ? '#ff8a7a' : '#ffd27a', { size: 22 });
        sfx(u.faction === 'player' ? 'death_player' : 'death');
        const p = this.viewPos(v);
        this.fx.ring(p.x, p.y, 70, u.faction === 'player' ? 'rgba(120,170,255,0.7)' : 'rgba(235,80,60,0.7)', 0.6);
        this.anim = { t: 0, dur: 0.55, step: () => {} };
        if (u.faction === 'player') this.cam.shake = 0.4;
        return;
      }
      case 'rout': {
        // Order breaks: the ranks scatter and the soldiers turn to run.
        const v = this.views.get(e.uid)!;
        v.routing = true;
        v.stance = undefined;
        v.tight = 1;
        this.reformView(v, { dur: 0.3, stagger: 0.02 });
        const hp = this.headPos(v);
        if (!this.hordeBroken) {
          this.fx.text(hp.x, hp.y - 18, 'Routed!', '#f2efe4', { size: 22 });
          sfx('rout');
        }
        this.anim = { t: 0, dur: 0.45, step: (f) => (v.shake = (1 - f) * 0.6) };
        return;
      }
      case 'rally': {
        const v = this.views.get(e.uid)!;
        v.routing = false;
        this.reformView(v, { dur: 0.5, stagger: 0.05 });
        const hp = this.headPos(v);
        this.fx.text(hp.x, hp.y - 18, 'Rallied!', '#9fe0ff', { size: 20 });
        return;
      }
      case 'fled': {
        const v = this.views.get(e.uid)!;
        v.status = 'fled';
        this.anim = {
          t: 0,
          dur: 0.4,
          step: (f) => (v.alpha = 1 - f),
          done: () => (v.visible = false),
        };
        return;
      }
      case 'stance': {
        // A shield wall closes the ranks; set spears draw them in a little.
        const v = this.views.get(e.uid)!;
        v.stance = e.stance ?? undefined;
        const tight = e.stance === 'shieldwall' ? 0.84 : e.stance === 'spearwall' ? 0.92 : 1;
        if (tight !== v.tight) {
          v.tight = tight;
          this.reformView(v, { dur: 0.3, stagger: 0.03 });
        }
        if (e.stance) {
          const hp = this.headPos(v);
          const name = e.stance === 'shieldwall' ? 'Shield Wall' : e.stance === 'spearwall' ? 'Spearwall' : 'Overwatch';
          this.fx.text(hp.x, hp.y - 10, name, '#e9d58f', { size: 18 });
          sfx('stance');
          const p = this.viewPos(v);
          this.fx.ring(p.x, p.y, 70, 'rgba(240,220,150,0.9)', 0.5);
          this.anim = { t: 0, dur: 0.35, step: () => {} };
        }
        return;
      }
      case 'shout': {
        const v = this.views.get(e.uid)!;
        const p = this.viewPos(v);
        const ab = ABILITIES[e.ability];
        this.fx.ring(p.x, p.y, 260, 'rgba(230,70,50,0.9)', 0.9);
        this.fx.ring(p.x, p.y, 180, 'rgba(255,190,120,0.8)', 0.7);
        this.fx.text(p.x, p.y - 160, `${ab.name}!`, '#ff9a7a', { size: 26 });
        this.cam.shake = 0.5;
        sfx('warcry');
        this.focusOn(v.x, v.y, true);
        this.anim = { t: 0, dur: 0.9, step: (f) => (v.hop = Math.sin(f * Math.PI) * 10) };
        return;
      }
      case 'halt': {
        const v = this.views.get(e.uid)!;
        const hp = this.headPos(v);
        this.fx.text(hp.x, hp.y - 20, 'Halted!', '#e9d58f', { size: 18, delay: 0.1 });
        return;
      }
      case 'warn': {
        this.banner('War horns!', `${e.label}: ${e.count} squads reach the field from the ${EDGE_NAME[e.edge]} edge at the end of this turn`, 'enemy');
        sfx('warhorn');
        this.anim = { t: 0, dur: 1.1, step: () => {} };
        return;
      }
      case 'wave': {
        this.banner(e.final ? 'The warchief comes!' : e.label, `${e.count} more squads march onto the field from the ${EDGE_NAME[e.edge]} edge`, 'enemy');
        sfx('warhorn');
        sfx('roar');
        this.cam.shake = Math.max(this.cam.shake, e.final ? 0.6 : 0.3);
        const ent = this.b.map.entries?.[e.edge];
        if (ent?.length) {
          const c = ent[Math.floor(ent.length / 2)];
          this.focusHold = 0;
          this.focusOn(c.x, c.y, false);
        }
        this.anim = { t: 0, dur: 1.3, step: () => {} };
        return;
      }
      case 'spawn': {
        // March in from the staging ground beyond the edge, straight onto the field.
        const v = this.views.get(e.uid)!;
        v.reserve = false;
        v.visible = true;
        v.status = 'active';
        v.alpha = 1;
        v.x = e.from.x;
        v.y = e.from.y;
        v.h = 0;
        const dx = Math.sign(e.to.x - e.from.x);
        const dy = Math.sign(e.to.y - e.from.y);
        const path: Pt[] = [{ ...e.from }];
        let cur = { ...e.from };
        for (let guard = 0; guard < 20 && (cur.x !== e.to.x || cur.y !== e.to.y); guard++) {
          cur = cur.x !== e.to.x ? { x: cur.x + dx, y: cur.y } : { x: cur.x, y: cur.y + dy };
          path.push(cur);
        }
        if (path.length < 2) path.push({ ...e.to });
        this.play({ t: 'move', uid: e.uid, path });
        return;
      }
      case 'horn': {
        const v = this.views.get(e.uid);
        const p = v ? this.viewPos(v) : null;
        if (e.sounded) {
          this.banner('The war horn sounds!', 'More of the horde will answer it next turn', 'enemy');
          sfx('warhorn');
          if (p) {
            this.fx.ring(p.x, p.y - 30, 200, 'rgba(230,70,50,0.8)', 1.0);
            this.fx.ring(p.x, p.y - 30, 120, 'rgba(255,190,120,0.7)', 0.8);
          }
        } else {
          this.banner('The horn is silenced', 'No help will come for them', 'player');
          sfx('horn');
        }
        this.anim = { t: 0, dur: 1.1, step: () => {} };
        return;
      }
      case 'overrun': {
        this.overrunWarn = true;
        this.banner('The line is breaking!', `${this.b.map.zoneName ?? 'The held ground'} is overrun. Drive them out before their next turn ends.`, 'enemy');
        sfx('drum');
        this.anim = { t: 0, dur: 1.1, step: () => {} };
        return;
      }
      case 'broken': {
        const v = this.views.get(e.uid);
        const u = this.b.unit(e.uid);
        this.hordeBroken = true;
        this.banner('The horde breaks!', `${squadName(u)} is slain`, 'player');
        sfx('relief');
        this.cam.shake = 0.7;
        if (v) {
          const p = this.viewPos(v);
          this.fx.ring(p.x, p.y, 320, 'rgba(255,215,106,0.9)', 1.2);
          this.fx.ring(p.x, p.y, 200, 'rgba(255,255,255,0.8)', 0.9);
        }
        this.anim = { t: 0, dur: 1.6, step: () => {} };
        return;
      }
      case 'relief': {
        this.hordeBroken = true;
        this.banner(this.b.objective.dawn ? 'Dawn!' : 'Held!', e.text, 'player');
        sfx('relief');
        if (this.b.objective.dawn) {
          // The riders crest the rise and charge before the horde breaks.
          this.startRelief();
          this.anim = { t: 0, dur: 3.4, step: () => {} };
        } else this.anim = { t: 0, dur: 1.8, step: () => {} };
        return;
      }
      case 'end': {
        this.anim = {
          t: 0,
          dur: 1.2,
          step: () => {},
          done: () => {
            this.ended = true;
            this.onEnd?.(e.result);
          },
        };
        this.banner(e.result === 'victory' ? 'Victory' : e.result === 'retreat' ? 'Withdrawal' : 'Defeat', undefined, e.result === 'victory' ? 'player' : 'enemy');
        sfx(e.result === 'victory' ? 'victory' : 'defeat');
        return;
      }
    }
  }

  /**
   * Soldiers of a squad fall to a blow coming from direction `from` (screen
   * space, pointing from the squad toward the attacker). The nearest go down,
   * then the survivors close up the ranks.
   */
  private showCasualties(v: UnitView, count: number, from: Pt, opts: { quiet?: boolean; reformDelay?: number } = {}): Member[] {
    if (count <= 0) return [];
    const u = this.b.unit(v.uid);
    const fallen = killMembers(v.members, count, from, championOf(u));
    for (const m of fallen) this.fallMember(v, m);
    v.alive = standing(v.members).length;
    if (!opts.quiet && fallen.length) {
      const hp = this.headPos(v);
      this.fx.text(hp.x + 52, hp.y - 6, `${fallen.length} slain`, '#ff9a86', { size: 16, delay: 0.12 });
    }
    if (v.alive) this.reformView(v, { delay: opts.reformDelay ?? 0.42 + fallen.length * 0.07, dur: 0.45, stagger: 0.05 });
    return fallen;
  }

  /** Blood and a grunt as one soldier goes down. */
  private fallMember(v: UnitView, m: Member) {
    const p = this.memberPos(v, m);
    this.fx.burst(p.x, p.y - 22, 0, 6, { shape: 'spark', colors: ['#b8291c', '#7d1a12', '#e0a080'], speed: 90, vz: 50, gravity: 220, size: 2.4, max: 0.4 });
  }

  /** Points between two squads on screen, for aiming lunges and missiles. */
  private dirBetween(a: UnitView, b: UnitView) {
    const ap = this.viewPos(a);
    const bp = this.viewPos(b);
    const dx = bp.x - ap.x;
    const dy = bp.y - ap.y;
    const len = Math.hypot(dx, dy) || 1;
    return { nx: dx / len, ny: dy / len, len };
  }

  private playAttack(e: Extract<BattleEvent, { t: 'attack' }>) {
    const av = this.views.get(e.uid)!;
    const tv = this.views.get(e.target)!;
    const attacker = this.b.unit(e.uid);
    const target = this.b.unit(e.target);
    if (target.faction === 'player' || attacker.faction === 'player') this.focusOn((av.x + tv.x) / 2, (av.y + tv.y) / 2, false);
    if (e.reaction) {
      const label = e.reaction === 'zoc' ? 'Free attack' : e.reaction === 'spearwall' ? 'Spearwall!' : e.reaction === 'overwatch' ? 'Overwatch!' : 'First strike!';
      const hp = this.headPos(av);
      this.fx.text(hp.x, hp.y - 6, label, '#e9d58f', { size: 16 });
    }
    // Squads strike from where they stand without turning: only marching turns a squad.
    const { nx, ny, len } = this.dirBetween(av, tv);
    const killed = Math.max(0, e.aliveBefore - e.aliveAfter);
    // The damage was rolled once by the rules; the animation only shows it.
    let shown = false;
    const showHit = () => {
      if (shown) return;
      shown = true;
      tv.hp = e.targetHp;
      const head = this.headPos(tv);
      const tp = this.viewPos(tv);
      if (e.hit) {
        this.fx.text(head.x, head.y - 4, `${e.damage}`, e.arc === 'rear' ? '#ffb347' : '#ffffff', { size: e.arc === 'front' ? 26 : 30 });
        if (e.arc !== 'front') this.fx.text(head.x, head.y - 34, e.arc === 'rear' ? 'Rear!' : 'Flank!', '#ffb347', { size: 15, delay: 0.05 });
        this.cam.shake = Math.max(this.cam.shake, killed >= 2 ? 0.4 : e.damage >= 30 ? 0.28 : 0.16);
        const armored = target.stats.armor >= 2;
        sfx(e.ranged ? 'bolt_hit' : armored ? 'hit_metal' : 'hit_flesh');
        // The whole squad flinches.
        for (const m of standing(tv.members)) {
          m.flash = Math.max(m.flash, 0.42);
          m.shake = 1;
          m.lunge = { x: nx * 4, y: ny * 2.5 };
        }
      } else {
        const blocked = !e.ranged && e.arc === 'front' && target.shieldFront > 0;
        this.fx.text(head.x, head.y - 4, blocked ? 'Blocked' : 'Miss', '#c8c8c8', { size: 20 });
        if (blocked) {
          this.fx.burst(tp.x - nx * 30, tp.y - 26 - ny * 16, 0, 10, { shape: 'spark', colors: ['#ffffff', '#ffe9a8'], speed: 150, vz: 40, size: 2.5, max: 0.35 });
          sfx('block');
        } else sfx('miss');
        // Sidestep.
        for (const m of standing(tv.members)) m.lunge = { x: -ny * 6 * (m.id % 2 ? 1 : -1), y: nx * 3 };
      }
    };
    const strikers = standing(av.members);
    // Front rank first: the soldiers nearest the enemy act first and reach furthest.
    const order = strikers.slice().sort((a, b) => b.x * nx + b.y * ny - (a.x * nx + a.y * ny));
    if (e.ranged) {
      this.playVolley(e, av, tv, order, killed, showHit, nx, ny, len);
      return;
    }
    // Melee: a ripple of blows from front to back. Each soldier winds up,
    // lunges and recovers on his own beat; the squad's damage lands once.
    const beat = 0.05;
    const wind = 0.14;
    const strike = 0.1;
    const recover = 0.34;
    const total = (order.length - 1) * beat + wind + strike + recover;
    const impactAt = wind + strike;
    const reach = order.map((_, i) => (i < Math.ceil(order.length / 2) ? 30 : 17));
    // Casualties fall one by one as the blows land along the line.
    const victims = killed > 0 ? this.pickVictims(tv, killed, { x: -nx, y: -ny }) : [];
    let next = 0;
    sfx('swing');
    let swung2 = false;
    this.anim = {
      t: 0,
      dur: total,
      step: (f) => {
        const t = f * total;
        order.forEach((m, i) => {
          const lt = t - i * beat;
          const L = reach[i];
          if (lt < 0) return;
          if (lt < wind) {
            m.pose = 'atk';
            const k = lt / wind;
            m.lunge = { x: -nx * 7 * k, y: -ny * 4 * k };
          } else if (lt < wind + strike) {
            const k = (lt - wind) / strike;
            m.lunge = { x: lerp(-nx * 7, nx * L, easeOutCubic(k)), y: lerp(-ny * 4, ny * L * 0.55, easeOutCubic(k)) };
          } else {
            const k = Math.min(1, (lt - wind - strike) / recover);
            m.lunge = { x: nx * L * (1 - easeOutCubic(k)), y: ny * L * 0.55 * (1 - easeOutCubic(k)) };
            if (k >= 1) m.pose = 'idle';
          }
        });
        if (t >= impactAt) {
          if (!shown) {
            showHit();
            if (e.hit) {
              const tp = this.viewPos(tv);
              const armored = target.stats.armor >= 2;
              this.fx.burst(tp.x - nx * 24, tp.y - 26 - ny * 12, 0, armored ? 16 : 10, { shape: 'spark', colors: armored ? ['#fff6c8', '#ffd27a', '#ffffff'] : ['#d64a3a', '#a3261c', '#f2c0a0'], speed: 180, vz: 60, gravity: 200, size: 3, max: 0.45 });
            }
          }
          // One victim per landing blow, front rank first.
          while (next < victims.length && t >= impactAt + next * beat * 1.4) {
            this.dropVictim(tv, victims[next], { x: -nx, y: -ny });
            next++;
          }
        }
        if (!swung2 && order.length > 3 && t >= impactAt + beat * 2) {
          swung2 = true;
          sfx('swing');
        }
        for (const m of standing(tv.members)) {
          m.lunge.x *= 0.88;
          m.lunge.y *= 0.88;
        }
      },
      done: () => {
        showHit();
        while (next < victims.length) this.dropVictim(tv, victims[next++], { x: -nx, y: -ny });
        this.afterCasualties(tv, victims.length);
        for (const m of order) {
          m.pose = 'idle';
          m.lunge = { x: 0, y: 0 };
        }
        for (const m of standing(tv.members)) m.lunge = { x: 0, y: 0 };
      },
    };
  }

  /** The soldiers a blow from `from` will kill, chosen now and dropped as the blows land. */
  private pickVictims(v: UnitView, count: number, from: Pt): Member[] {
    const u = this.b.unit(v.uid);
    const live = standing(v.members);
    const champ = championOf(u);
    const order = live.slice().sort((a, b) => {
      const pa = a.id === champ ? -1e6 : a.toX * from.x + a.toY * from.y * 2;
      const pb = b.id === champ ? -1e6 : b.toX * from.x + b.toY * from.y * 2;
      return pb - pa;
    });
    return order.slice(0, Math.min(count, live.length));
  }

  private dropVictim(v: UnitView, m: Member, from: Pt) {
    if (!m.alive) return;
    const len = Math.hypot(from.x, from.y) || 1;
    m.alive = false;
    m.dying = true;
    m.deathT = 0;
    m.deathDelay = 0;
    m.flash = 1;
    m.pose = 'idle';
    m.lunge = { x: (-from.x / len) * 6, y: (-from.y / len) * 3.5 };
    m.fallFlip = from.x > 0;
    v.alive = standing(v.members).length;
    this.fallMember(v, m);
  }

  /** After the last body drops: a casualty count, then the ranks close up. */
  private afterCasualties(v: UnitView, count: number) {
    if (count <= 0) return;
    const hp = this.headPos(v);
    if (v.alive > 0) {
      this.fx.text(hp.x + 52, hp.y - 6, `${count} slain`, '#ff9a86', { size: 16, delay: 0.05 });
      this.reformView(v, { delay: 0.45, dur: 0.45, stagger: 0.05 });
    }
  }

  /**
   * Missile troops loose together: each surviving archer or crossbowman fires
   * his own shot, a beat apart, at a soldier of the target squad. Shots that
   * miss stick in the ground around them. Casualties drop as their shots land.
   */
  private playVolley(
    e: Extract<BattleEvent, { t: 'attack' }>,
    av: UnitView,
    tv: UnitView,
    order: Member[],
    killed: number,
    showHit: () => void,
    nx: number,
    ny: number,
    len: number,
  ) {
    const attacker = this.b.unit(e.uid);
    const bolt = attacker.typeId === 'crossbowman';
    const flight = clamp(len / 1000, 0.2, 0.55);
    const aim = 0.24;
    const beat = bolt ? 0.07 : 0.05;
    const shooters = order.map((m, i) => ({ m, at: aim + i * beat + Math.random() * 0.02, fired: false }));
    const victims = killed > 0 ? this.pickVictims(tv, killed, { x: -nx, y: -ny }) : [];
    const targets = standing(tv.members);
    const total = aim + (shooters.length - 1) * beat + flight + 0.3;
    sfx(bolt ? 'crossbow' : 'bow');
    let volleySound = false;
    this.anim = {
      t: 0,
      dur: total,
      step: (f) => {
        const t = f * total;
        shooters.forEach((s, i) => {
          const m = s.m;
          if (t < s.at) {
            // Raise and draw.
            m.pose = 'atk';
            const k = Math.min(1, t / aim);
            m.lunge = { x: -nx * 3 * k, y: -ny * 2 * k };
            return;
          }
          if (!s.fired) {
            s.fired = true;
            m.lunge = { x: -nx * 5, y: -ny * 3 };
            const from = this.memberPos(av, m);
            // Hits fly at the soldiers who will fall first, then at the rest.
            let to: { x: number; y: number };
            const victim = e.hit ? victims[i] : undefined;
            if (e.hit) {
              const tm = victim ?? targets[(i * 3 + 1) % Math.max(1, targets.length)];
              const q = tm ? this.memberPos(tv, tm) : this.viewPos(tv);
              to = { x: q.x + (Math.random() - 0.5) * 6, y: q.y - 18 - Math.random() * 10 };
            } else {
              const q = this.viewPos(tv);
              to = { x: q.x + (Math.random() - 0.5) * 90, y: q.y + (Math.random() - 0.5) * 34 };
            }
            this.fx.shoot({
              x0: from.x + nx * 8,
              y0: from.y - 28,
              x1: to.x,
              y1: to.y,
              t: 0,
              dur: flight * (0.92 + Math.random() * 0.16),
              arc: bolt ? len * 0.05 : len * 0.16,
              kind: bolt ? 'bolt' : 'arrow',
              scale: 0.62,
              stick: !e.hit,
              onHit: () => {
                showHit();
                if (victim) this.dropVictim(tv, victim, { x: -nx, y: -ny });
              },
            });
            if (!volleySound && i === Math.floor(shooters.length / 2) && shooters.length > 2) {
              volleySound = true;
              sfx(bolt ? 'crossbow' : 'bow');
            }
          } else {
            m.lunge.x *= 0.86;
            m.lunge.y *= 0.86;
          }
        });
        for (const m of standing(tv.members)) {
          m.lunge.x *= 0.9;
          m.lunge.y *= 0.9;
        }
      },
      done: () => {
        showHit();
        // Any casualty whose shot was not assigned (more dead than shooters) drops now.
        for (const vm of victims) this.dropVictim(tv, vm, { x: -nx, y: -ny });
        this.afterCasualties(tv, victims.length);
        for (const s of shooters) {
          s.m.pose = 'idle';
          s.m.lunge = { x: 0, y: 0 };
        }
        for (const m of standing(tv.members)) m.lunge = { x: 0, y: 0 };
      },
    };
  }

  // ---------------------------------------------------------------- update

  update(dt: number, time: number) {
    // Keyboard panning.
    const pan = 700 * dt / this.cam.zoom;
    if (this.keys.has('w') || this.keys.has('arrowup')) this.cam.ty -= pan;
    if (this.keys.has('s') || this.keys.has('arrowdown')) this.cam.ty += pan;
    if (this.keys.has('a') || this.keys.has('arrowleft')) this.cam.tx -= pan;
    if (this.keys.has('d') || this.keys.has('arrowright')) this.cam.tx += pan;
    this.clampCamera();
    updateCamera(this.cam, dt);
    this.fx.update(dt);
    this.atmo.update(dt, this.w, this.h);
    for (const v of this.views.values()) {
      v.shake = Math.max(0, v.shake - dt * 3);
      stepMembers(v.members, dt, (m) => this.addCorpse(v, m));
      v.walking = clamp(v.walking + (v.marching ? dt * 6 : -dt * 4), 0, 1);
      if (v.walking > 0) v.walkT += dt;
    }
    this.focusHold = Math.max(0, this.focusHold - dt);
    const rush = this.ui.side === 'enemy' ? clamp(1 + this.queue.length / 45, 1, 1.9) : 1;
    const adt = dt * rush;
    const o = this.b.objective;
    if (o.dawn && o.turns) {
      // Night gives way to dawn turn by turn; the sun is up when the relief comes.
      const won = !!this.relief || this.ended || (this.b.phase === 'over' && this.b.result === 'victory' && !this.busy);
      const want = won ? 0 : clamp(1 - ((this.ui.turn - 1) / o.turns) * 0.85, 0.15, 1);
      this.nightLevel += (want - this.nightLevel) * Math.min(1, dt * (this.relief ? 1.6 : 0.6));
      this.atmo.night = this.nightLevel > 0.05;
    }
    // The host fades once it has all marched in, or when it breaks and runs.
    const finalIn = this.b.waves.some((w, i) => w.final && this.b.waveState[i] !== 'pending' && !w.uids.some((id) => this.views.get(id)?.reserve));
    const gone = this.b.phase === 'over' || finalIn;
    this.hostAlpha = clamp(this.hostAlpha + (gone ? -dt * 0.5 : dt), 0, 1);
    if (this.relief) this.stepRelief(dt);
    for (const s of this.smoke) {
      s.t += dt;
      if (s.t >= s.rate) {
        s.t = 0;
        this.fx.burst(s.x + (Math.random() - 0.5) * 20, s.y, 30, 1, { shape: 'puff', color: Math.random() < 0.3 ? 'rgba(70,60,52,1)' : 'rgba(110,100,92,1)', speed: 6, vz: 26, gravity: -4, size: 14, max: 7, drag: 0.2 });
      }
    }
    for (const a of this.anims.slice()) {
      if (a.delay && a.delay > 0) {
        a.delay -= adt;
        continue;
      }
      if (!a.started) {
        a.started = true;
        a.start?.();
      }
      a.t += adt;
      a.step(Math.min(1, a.t / a.dur));
      // Banners and the end wait for missiles still in the air.
      if (a.t >= a.dur && (!a.barrier || !this.fx.busy)) {
        a.done?.();
        this.anims.splice(this.anims.indexOf(a), 1);
      }
    }
    this.next();
    const busy = this.busy;
    if (busy !== this.ui.busy) {
      this.ui.busy = busy;
      if (!busy) this.refreshHover();
      this.notify();
    }
  }

  // ---------------------------------------------------------------- input

  private tileAtScreen(sx: number, sy: number): Pt | null {
    const wpt = screenToWorld(this.cam, sx, sy, this.w, this.h);
    // Test from the highest level down so raised tiles win.
    let best: Pt | null = null;
    for (let lvl = 3; lvl >= 0 && !best; lvl--) {
      const gx = (wpt.x / (TW / 2) + (wpt.y + lvl * LH) / (TH / 2)) / 2;
      const gy = ((wpt.y + lvl * LH) / (TH / 2) - wpt.x / (TW / 2)) / 2;
      const x = Math.round(gx);
      const y = Math.round(gy);
      const t = tileAt(this.b.map, x, y);
      if (t && t.h === lvl) best = { x, y };
    }
    return best;
  }

  pointerMove(p: PointerInfo) {
    this.pointer = { x: p.x, y: p.y };
    this.refreshHover();
  }

  /** Front-most living unit whose figure (opaque pixels) is under the cursor. */
  private unitAtScreen(sx: number, sy: number): BattleUnit | undefined {
    const wp = screenToWorld(this.cam, sx, sy, this.w, this.h);
    let best: BattleUnit | undefined;
    let bestD = -Infinity;
    for (const v of this.views.values()) {
      if (!v.visible || v.status === 'dead' || v.status === 'downed' || v.status === 'fled') continue;
      const u = this.b.unit(v.uid);
      if (!this.bodyCovers(v, u, wp.x, wp.y)) continue;
      const d = v.x + v.y;
      if (d > bestD) {
        bestD = d;
        best = u;
      }
    }
    return best;
  }

  /** Whether the selected soldier could be moved (or deployed) onto this tile now. */
  private isMoveTarget(t: Pt): boolean {
    const sel = this.selectedUnit();
    if (!sel || unitAt(this.b.units, t.x, t.y)) return false;
    if (this.b.phase === 'deploy') return this.b.map.playerDeploy.some((p) => p.x === t.x && p.y === t.y);
    if (this.b.phase !== 'player' || sel.hasMoved || this.busy) return false;
    return this.reach(sel).has(key(t.x, t.y));
  }

  /**
   * What the cursor points at. A unit's figure wins over the ground behind it,
   * except that an empty tile the selected soldier can move to beats a friendly
   * figure that merely overlaps it on screen. Enemy figures always mean the enemy.
   */
  resolvePointer(sx: number, sy: number): { tile?: Pt; unit?: BattleUnit } {
    const ground = this.tileAtScreen(sx, sy) ?? undefined;
    const standing = ground ? unitAt(this.b.units, ground.x, ground.y) : undefined;
    const body = this.unitAtScreen(sx, sy);
    if (body && body !== standing) {
      if (ground && !standing && body.faction === 'player' && this.isMoveTarget(ground)) return { tile: ground };
      return { tile: { x: body.x, y: body.y }, unit: body };
    }
    if (standing) return { tile: ground, unit: standing };
    return { tile: ground };
  }

  private refreshHover() {
    const { tile: t, unit: picked } = this.resolvePointer(this.pointer.x, this.pointer.y);
    const hover: HoverInfo = { tile: t };
    const sel = this.selectedUnit();
    if (t) {
      const u = picked;
      if (u) hover.unit = u.uid;
      if (sel && !this.busy && this.b.phase === 'player') {
        if (u && u.faction === 'enemy') {
          hover.preview = this.previewAgainst(sel, u);
          const from = hover.preview?.moveFirst ? hover.preview.from : undefined;
          if (from) {
            // Arrive facing the enemy you strike, unless that way in costs extra free attacks.
            const arr = this.arrival(sel, from, dirTo(from, u), true);
            if (arr) this.showArrival(hover, from, arr);
          }
        } else if (!u && !sel.hasMoved && sel.status === 'active') {
          if (this.reach(sel).has(key(t.x, t.y))) {
            const pt = this.pointing(t);
            // Q / E hold until the cursor points at a different edge.
            if (this.facingPick && pt !== this.facingPick.pointed) this.facingPick = null;
            const arr = this.arrival(sel, t, pt);
            if (arr) this.showArrival(hover, t, arr);
          }
        } else if (u && u.uid === sel.uid && !sel.hasMoved && sel.status === 'active') {
          // Pointing at an edge of the squad's own tile: step out and back to face that way.
          const want = this.pointing(t, 0.2, true);
          if (want !== undefined && want !== sel.facing) {
            const arr = this.arrival(sel, t, want, false, true);
            if (arr && arr.opt.facing === want) {
              this.showArrival(hover, t, arr);
              hover.turn = true;
            }
          }
        }
      }
    }
    const changed = JSON.stringify(hover) !== JSON.stringify(this.ui.hover);
    this.ui.hover = hover;
    if (changed) this.notify();
  }

  private showArrival(hover: HoverInfo, at: Pt, arr: { opt: FacingOption; all: FacingOption[] }) {
    hover.dest = { x: at.x, y: at.y };
    hover.path = arr.opt.path.length > 1 ? arr.opt.path : undefined;
    hover.zoc = arr.opt.zoc;
    hover.facing = arr.opt.facing;
    hover.facings = arr.all.map((o) => o.facing);
  }

  private states(u: BattleUnit) {
    if (!this.statesCache || this.statesCache.uid !== u.uid) this.statesCache = { uid: u.uid, states: this.b.reachStates(u) };
    return this.statesCache.states;
  }

  /**
   * How the selected squad would arrive on `at`. A squad faces the way it last
   * stepped, so each facing is its own path: the one picked with Q / E, else
   * the one asked for (`soft`: only if it provokes no extra free attacks),
   * else the default (facing the nearest enemy where possible).
   */
  private arrival(sel: BattleUnit, at: Pt, want?: Dir, soft = false, turnOnly = false): { opt: FacingOption; all: FacingOption[] } | null {
    let all = this.b.facingOptions(sel, at.x, at.y, this.states(sel));
    if (turnOnly) all = all.filter((o) => o.path.length > 1);
    if (!all.length) return null;
    const k = key(at.x, at.y);
    if (this.facingPick && this.facingPick.at !== k) this.facingPick = null;
    let opt = this.facingPick ? all.find((o) => o.facing === this.facingPick!.facing) : undefined;
    if (!opt && want !== undefined) {
      const o = all.find((q) => q.facing === want);
      const minZoc = Math.min(...all.map((q) => q.zoc));
      if (o && (!soft || o.zoc <= minZoc)) opt = o;
    }
    if (!opt) opt = this.b.defaultFacing(sel, at.x, at.y, all);
    return opt ? { opt, all } : null;
  }

  /**
   * The facing the cursor points at inside a tile: toward the edge it is
   * nearest, or none near the centre. `inside` ignores points off the tile
   * (the cursor on a squad's bodies rather than its ground).
   */
  private pointing(at: Pt, dead = 0.16, inside = false): Dir | undefined {
    const th = tileAt(this.b.map, at.x, at.y)?.h ?? 0;
    const wp = screenToWorld(this.cam, this.pointer.x, this.pointer.y, this.w, this.h);
    const dx = wp.x - isoX(at.x, at.y);
    const dy = wp.y - isoY(at.x, at.y, th);
    const gx = (dx / (TW / 2) + dy / (TH / 2)) / 2;
    const gy = (dy / (TH / 2) - dx / (TW / 2)) / 2;
    if (Math.hypot(gx, gy) < dead) return undefined;
    if (inside && Math.abs(gx) + Math.abs(gy) > 0.62) return undefined;
    return dirTo({ x: 0, y: 0 }, { x: gx, y: gy });
  }

  /** Preview an attack, including move-then-strike for melee from the side under the cursor. */
  private previewAgainst(sel: BattleUnit, target: BattleUnit): HoverInfo['preview'] | undefined {
    if (sel.hasActed) return undefined;
    const ability = this.ui.ability;
    const here = this.b.preview(sel, target, { ability });
    if (here.legal) return { ...here, target: target.uid, ability, moveFirst: false };
    if (sel.hasMoved) return { ...here, target: target.uid, ability, moveFirst: false };
    const ab = ability ? ABILITIES[ability] : undefined;
    if (sel.shot && !ab) {
      // Ranged units: suggest the reachable tile that keeps the best shot.
      const reach = this.reach(sel);
      let best: { pv: AttackPreview; from: Pt } | null = null;
      for (const [k] of reach) {
        const from = { x: k % 1000, y: Math.floor(k / 1000) };
        const pv = this.b.preview(sel, target, { from, movedTiles: 1 });
        if (pv.legal && (!best || pv.chance > best.pv.chance)) best = { pv, from };
      }
      if (best) return { ...best.pv, target: target.uid, from: best.from, moveFirst: true };
      return { ...here, target: target.uid, moveFirst: false };
    }
    // Melee: choose the adjacent tile closest to the cursor.
    const reach = this.reach(sel);
    const wpt = screenToWorld(this.cam, this.pointer.x, this.pointer.y, this.w, this.h);
    const reachOpts = ab?.reach === 2
      ? DIRS.map((d) => ({ x: target.x - d.x * 2, y: target.y - d.y * 2 }))
      : DIRS.map((d) => ({ x: target.x + d.x, y: target.y + d.y }));
    let best: { from: Pt; d: number } | null = null;
    for (const from of reachOpts) {
      const info = reach.get(key(from.x, from.y));
      if (!info) continue;
      const fx = isoX(from.x, from.y);
      const fy = isoY(from.x, from.y, tileAt(this.b.map, from.x, from.y)!.h);
      const d = Math.hypot(fx - wpt.x, fy - wpt.y);
      if (!best || d < best.d) best = { from, d };
    }
    if (!best) return { ...here, target: target.uid, ability, moveFirst: false };
    const path = this.b.pathTo(sel, best.from.x, best.from.y);
    const pv = this.b.preview(sel, target, { from: best.from, ability, movedTiles: path ? path.length - 1 : 1 });
    return { ...pv, target: target.uid, from: best.from, ability, moveFirst: true };
  }

  private reach(u: BattleUnit) {
    if (!this.reachCache || this.reachCache.uid !== u.uid) this.reachCache = { uid: u.uid, reach: this.b.reachable(u) };
    return this.reachCache.reach;
  }

  pointerDown(p: PointerInfo) {
    if (p.button === 2) {
      if (this.ui.ability) this.ui.ability = undefined;
      else this.ui.selected = undefined;
      this.notify();
      return;
    }
    if (p.button === 0 && this.b.map.scale === 'large') {
      // Clicking the minimap moves the camera there.
      const r = this.minimapRect();
      if (p.x >= r.x - 4 && p.x <= r.x + r.w + 4 && p.y >= r.y - 4 && p.y <= r.y + r.h + 4) {
        this.cam.tx = r.ox + (p.x - r.x) / r.k;
        this.cam.ty = r.oy + (p.y - r.y) / r.k;
        return;
      }
    }
    if (p.button !== 0 || this.busy || this.ended) return;
    this.pointer = { x: p.x, y: p.y };
    if (this.b.phase === 'player') this.refreshHover();
    const hv = this.ui.hover;
    const { tile: t, unit: u } = this.resolvePointer(p.x, p.y);
    if (!t) return;
    if (this.b.phase === 'deploy') {
      if (u && u.faction === 'player') {
        if (this.ui.selected && this.ui.selected !== u.uid) {
          this.b.deploySwap(this.ui.selected, t.x, t.y);
          this.syncViews();
          sfx('step');
          this.ui.selected = undefined;
        } else this.ui.selected = u.uid;
        this.notify();
      } else if (this.ui.selected && this.b.deploySwap(this.ui.selected, t.x, t.y)) {
        this.syncViews();
        sfx('step');
        this.notify();
      }
      return;
    }
    if (this.b.phase !== 'player') return;
    const sel = this.selectedUnit();
    if (u && u.faction === 'player') {
      if (sel && u.uid === sel.uid && hv.turn && hv.facing !== undefined) {
        // Step out and back to face the edge pointed at.
        this.b.move(sel.uid, sel.x, sel.y, hv.facing);
        this.pump();
        this.afterPlayerAction(sel);
        return;
      }
      this.select(u.uid);
      return;
    }
    if (!sel) return;
    if (u && u.faction === 'enemy') {
      const pv = this.ui.hover.preview && this.ui.hover.preview.target === u.uid ? this.ui.hover.preview : this.previewAgainst(sel, u);
      if (!pv || !pv.legal) {
        sfx('deny');
        return;
      }
      if (pv.moveFirst && pv.from) {
        const same = hv.dest && hv.dest.x === pv.from.x && hv.dest.y === pv.from.y;
        this.b.move(sel.uid, pv.from.x, pv.from.y, same ? hv.facing : undefined);
        if (sel.status === 'active' && !sel.hasActed && this.b.preview(sel, u, { ability: pv.ability }).legal) this.b.attack(sel.uid, u.uid, pv.ability);
      } else {
        this.b.attack(sel.uid, u.uid, pv.ability);
      }
      this.ui.ability = undefined;
      this.pump();
      this.afterPlayerAction(sel);
      return;
    }
    if (!sel.hasMoved && this.reach(sel).has(key(t.x, t.y)) && !(t.x === sel.x && t.y === sel.y)) {
      const same = hv.dest && hv.dest.x === t.x && hv.dest.y === t.y;
      this.b.move(sel.uid, t.x, t.y, same ? hv.facing : undefined);
      this.pump();
      this.afterPlayerAction(sel);
    }
  }

  private afterPlayerAction(u: BattleUnit) {
    if (u.done || u.status !== 'active') {
      // Wait for animations; selection moves on in update via ui.busy toggle.
      const check = () => {
        if (this.busy) {
          requestAnimationFrame(check);
          return;
        }
        if (this.b.phase === 'player') this.selectNext();
      };
      requestAnimationFrame(check);
    }
  }

  private syncViews() {
    for (const u of this.b.units) {
      const v = this.views.get(u.uid)!;
      v.x = u.x;
      v.y = u.y;
      v.h = tileAt(this.b.map, u.x, u.y)!.h;
      if (v.facing !== u.facing) {
        v.facing = u.facing;
        this.reformView(v, { instant: true });
      }
    }
  }

  wheel(delta: number) {
    this.cam.tzoom = clamp(this.cam.tzoom * (delta > 0 ? 0.9 : 1.1), this.minZoom, 1.6);
  }

  key(e: KeyboardEvent) {
    const k = e.key.toLowerCase();
    if (['w', 'a', 's', 'd', 'arrowup', 'arrowdown', 'arrowleft', 'arrowright'].includes(k)) this.keys.add(k);
    if (k === 'q') this.cycleFacing(-1);
    if (k === 'e') this.cycleFacing(1);
    if (k === 'tab') {
      e.preventDefault();
      this.selectNext();
    }
    if (k === ' ') {
      e.preventDefault();
      this.endUnit();
    }
    if (k === 'enter') this.endTurn();
    if (k === 'backspace' || (k === 'z' && (e.ctrlKey || e.metaKey))) {
      e.preventDefault();
      this.redo();
    }
    if (k === 'escape') {
      this.ui.ability = undefined;
      this.notify();
    }
    if (k === 'g') {
      this.ui.showGrid = !this.ui.showGrid;
      this.notify();
    }
    if (e.key === 'Alt') {
      e.preventDefault();
      this.ui.danger = true;
      this.notify();
    }
    const n = Number(e.key);
    if (n >= 1 && n <= 4) {
      const u = this.selectedUnit();
      if (u) {
        const ab = u.abilities.filter((a) => ABILITIES[a].kind !== 'attack' || ABILITIES[a].damageMult)[n - 1];
        if (ab) this.setAbility(ab);
      }
    }
  }

  // ---------------------------------------------------------------- render

  private dangerTiles(): Set<number> {
    if (this.dangerCache) return this.dangerCache;
    const out = new Set<number>();
    for (const e of this.b.active('enemy')) {
      const reach = this.b.reachableFull(e);
      for (const [k] of reach) {
        const p = { x: k % 1000, y: Math.floor(k / 1000) };
        for (const d of DIRS) out.add(key(p.x + d.x, p.y + d.y));
        if (e.shot) {
          for (const t of this.b.map.tiles) if (dist(t, p) <= e.shot.range && dist(t, p) >= e.shot.minRange) out.add(key(t.x, t.y));
        }
      }
    }
    this.dangerCache = out;
    return out;
  }

  private diamondPath(ctx: CanvasRenderingContext2D, x: number, y: number, inset = 0) {
    const h = tileAt(this.b.map, x, y)?.h ?? 0;
    const s = 0.5 - inset;
    ctx.moveTo(isoX(x - s, y - s), isoY(x - s, y - s, h));
    ctx.lineTo(isoX(x + s, y - s), isoY(x + s, y - s, h));
    ctx.lineTo(isoX(x + s, y + s), isoY(x + s, y + s, h));
    ctx.lineTo(isoX(x - s, y + s), isoY(x - s, y + s, h));
    ctx.closePath();
  }

  render(ctx: CanvasRenderingContext2D, w: number, h: number, time: number) {
    this.w = w;
    this.h = h;
    ctx.fillStyle = '#1b2812';
    ctx.fillRect(0, 0, w, h);
    const shake = this.cam.shake;
    const sx = shake ? (Math.random() - 0.5) * shake * 10 : 0;
    const sy = shake ? (Math.random() - 0.5) * shake * 10 : 0;
    ctx.save();
    ctx.translate(w / 2 + sx, h / 2 + sy);
    ctx.scale(this.cam.zoom, this.cam.zoom);
    ctx.translate(-this.cam.x, -this.cam.y);
    // The ground layer is huge: plain filtering for it (high quality would
    // rebuild its filtering every frame); sprites keep the high quality.
    ctx.imageSmoothingQuality = this.groundQuality;
    const tl = this.terrain;
    ctx.drawImage(this.groundImage ?? tl.canvas, tl.ox, tl.oy, tl.canvas.width / tl.scale, tl.canvas.height / tl.scale);
    ctx.imageSmoothingQuality = this.spriteQuality;
    this.drawWater(ctx, time);
    this.atmo.drawClouds(ctx, isoX(this.b.map.w / 2, this.b.map.h / 2), isoY(this.b.map.w / 2, this.b.map.h / 2));
    this.drawGrid(ctx);
    this.drawHighlights(ctx, time);
    this.drawFootprints(ctx, time);
    this.fx.drawGround(ctx);
    this.drawSorted(ctx, time);
    this.fx.drawAir(ctx);
    ctx.restore();
    if (this.atmo.night) this.drawNight(ctx, w, h, time);
    if (this.relief && this.relief.glow > 0) this.drawSunrise(ctx, w, h);
    this.drawOverlays(ctx, w, h, time);
    // Combat text above the health bars.
    ctx.save();
    ctx.translate(w / 2 + sx, h / 2 + sy);
    ctx.scale(this.cam.zoom, this.cam.zoom);
    ctx.translate(-this.cam.x, -this.cam.y);
    this.fx.drawTexts(ctx, this.cam.zoom);
    ctx.restore();
    this.atmo.drawGrade(ctx, w, h, time);
  }

  private nightMask: HTMLCanvasElement | null = null;
  /** Soft round light stamps, drawn once and scaled per light (gradients per light per frame are costly). */
  private stamps: Record<string, HTMLCanvasElement> = {};
  private stamp(kind: 'hole' | 'glow' | 'flame'): HTMLCanvasElement {
    if (this.stamps[kind]) return this.stamps[kind];
    const c = document.createElement('canvas');
    c.width = c.height = 128;
    const x = c.getContext('2d')!;
    const g = x.createRadialGradient(64, 64, kind === 'hole' ? 10 : 0, 64, 64, 64);
    if (kind === 'hole') {
      g.addColorStop(0, 'rgba(0,0,0,0.95)');
      g.addColorStop(1, 'rgba(0,0,0,0)');
    } else if (kind === 'glow') {
      g.addColorStop(0, 'rgba(255,170,70,1)');
      g.addColorStop(1, 'rgba(255,170,70,0)');
    } else {
      g.addColorStop(0, 'rgba(255,220,140,1)');
      g.addColorStop(0.35, 'rgba(255,140,40,0.6)');
      g.addColorStop(1, 'rgba(255,90,20,0)');
    }
    x.fillStyle = g;
    x.fillRect(0, 0, 128, 128);
    this.stamps[kind] = c;
    return c;
  }
  /** Torch-lit darkness: a blue-black mask with light pools cut out of it. */
  private drawNight(ctx: CanvasRenderingContext2D, w: number, h: number, time: number) {
    this.atmo.ownNightMask = true;
    if (!this.nightMask) this.nightMask = document.createElement('canvas');
    const m = this.nightMask;
    // The mask is soft light and dark only: a quarter of the resolution is plenty.
    const Q = 4;
    const mw = Math.ceil(w / Q);
    const mh = Math.ceil(h / Q);
    if (m.width !== mw || m.height !== mh) {
      m.width = mw;
      m.height = mh;
    }
    const x = m.getContext('2d')!;
    x.setTransform(1 / Q, 0, 0, 1 / Q, 0, 0);
    x.globalCompositeOperation = 'source-over';
    x.clearRect(0, 0, w, h);
    // A battle through the night lightens toward dawn: the dark thins and warms.
    const dawn = this.b.objective.dawn;
    const level = dawn ? this.nightLevel : 1;
    const late = 1 - level;
    x.fillStyle = `rgba(${Math.round(12 + 40 * late)},${Math.round(16 + 14 * late)},${Math.round(40 + 10 * late)},${(0.74 * level).toFixed(3)})`;
    x.fillRect(0, 0, w, h);
    x.globalCompositeOperation = 'destination-out';
    const lit = !this.b.setup.darkness;
    const lights: { x: number; y: number; r: number }[] = [];
    const staged = this.staged();
    for (const v of this.views.values()) {
      const waiting = v.reserve && staged.has(v.uid);
      if (!(v.visible || waiting) || v.status === 'dead' || v.status === 'fled') continue;
      const u = this.b.unit(v.uid);
      const p = this.viewPos(v);
      // The horde comes by torchlight: every warband carries fire.
      const r = u.faction === 'player' ? (lit ? 230 : 120) : dawn ? 125 : 70;
      lights.push({ x: p.x, y: p.y - 40, r });
    }
    if (dawn && this.hostAlpha > 0.05) for (const t of this.hostTorches) lights.push({ x: t.x, y: t.y, r: 70 });
    for (const t of this.b.map.tiles) if (t.prop === 'campfire') lights.push({ x: isoX(t.x, t.y), y: isoY(t.x, t.y, t.h) - 20, r: 320 });
    const hole = this.stamp('hole');
    for (const l of lights) {
      const s = worldToScreen(this.cam, l.x, l.y, w, h);
      const r = l.r * this.cam.zoom * (1 + Math.sin(time * 9 + l.x) * 0.03);
      if (s.x + r < 0 || s.y + r < 0 || s.x - r > w || s.y - r > h) continue;
      x.drawImage(hole, s.x - r, s.y - r, r * 2, r * 2);
    }
    ctx.drawImage(m, 0, 0, w, h);
    // Warm glow where the light falls.
    ctx.save();
    ctx.globalCompositeOperation = 'soft-light';
    const glow = this.stamp('glow');
    ctx.globalAlpha = 0.32 * level;
    for (const l of lights) {
      const s = worldToScreen(this.cam, l.x, l.y, w, h);
      const r = l.r * this.cam.zoom * 0.8;
      if (s.x + r < 0 || s.y + r < 0 || s.x - r > w || s.y - r > h) continue;
      ctx.drawImage(glow, s.x - r, s.y - r, r * 2, r * 2);
    }
    ctx.restore();
    // Torch flames over the horde's warbands, so the host reads as a river of fire.
    if (dawn && level > 0.2) {
      ctx.save();
      ctx.globalCompositeOperation = 'lighter';
      const fl = this.stamp('flame');
      ctx.globalAlpha = 0.9 * level;
      const flame = (wx: number, wy: number, k: number) => {
        const s = worldToScreen(this.cam, wx, wy, w, h);
        if (s.x < -20 || s.y < -20 || s.x > w + 20 || s.y > h + 20) return;
        const f = 1 + Math.sin(time * 13 + k) * 0.18 + Math.sin(time * 7.3 + k * 3) * 0.1;
        const r = 27 * this.cam.zoom * f;
        ctx.drawImage(fl, s.x - r, s.y - r, r * 2, r * 2);
      };
      for (const v of this.views.values()) {
        const waiting = v.reserve && staged.has(v.uid);
        if (!(v.visible || waiting) || v.status === 'dead' || v.status === 'fled' || v.routing) continue;
        const u = this.b.unit(v.uid);
        if (u.faction !== 'enemy') continue;
        const live = standing(v.members);
        for (let i = 0; i < live.length; i += 3) {
          const p = this.memberPos(v, live[i]);
          flame(p.x + 8, p.y - memberHeight(u.typeId) - 10, hash2(i, v.uid.length) * 40 + i);
        }
      }
      if (this.hostAlpha > 0.05) this.hostTorches.forEach((t, i) => flame(t.x, t.y - 8, i * 1.7));
      ctx.restore();
    }
    // Dawn breaking over the far side of the field.
    if (dawn && late > 0.25) {
      ctx.save();
      ctx.globalCompositeOperation = 'screen';
      const g = ctx.createLinearGradient(0, 0, 0, h * 0.7);
      const a = Math.min(0.45, (late - 0.25) * 0.75);
      g.addColorStop(0, `rgba(255,170,120,${a.toFixed(3)})`);
      g.addColorStop(0.5, `rgba(255,140,110,${(a * 0.35).toFixed(3)})`);
      g.addColorStop(1, 'rgba(255,140,110,0)');
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, w, h);
      ctx.restore();
    }
  }

  private drawWater(ctx: CanvasRenderingContext2D, time: number) {
    if (!this.terrain.waterTiles.length) return;
    ctx.save();
    ctx.clip(this.terrain.water);
    ctx.strokeStyle = 'rgba(220,245,255,0.35)';
    ctx.lineWidth = 1.6;
    const hw = this.w / this.cam.zoom / 2 + 80;
    const hh = this.h / this.cam.zoom / 2 + 80;
    for (const t of this.terrain.waterTiles) {
      if (Math.abs(isoX(t.x, t.y) - this.cam.x) > hw || Math.abs(isoY(t.x, t.y) - this.cam.y) > hh) continue;
      for (let i = 0; i < 2; i++) {
        const ph = time * 0.8 + hash2(t.x, t.y, i) * 6;
        const cx = isoX(t.x, t.y) + Math.sin(ph) * 20 + (hash2(t.x, t.y, i + 7) - 0.5) * 60;
        const cy = isoY(t.x, t.y) + (hash2(t.x, t.y, i + 3) - 0.5) * 30;
        const a = 0.5 + 0.5 * Math.sin(ph * 1.3);
        ctx.globalAlpha = a;
        ctx.beginPath();
        ctx.moveTo(cx - 10, cy);
        ctx.quadraticCurveTo(cx, cy - 3, cx + 10, cy);
        ctx.stroke();
      }
    }
    ctx.restore();
  }

  private drawGrid(ctx: CanvasRenderingContext2D) {
    if (!this.ui.showGrid) return;
    ctx.save();
    ctx.strokeStyle = 'rgba(30,40,15,0.16)';
    ctx.lineWidth = 1.2;
    ctx.beginPath();
    for (const t of this.b.map.tiles) {
      if (TERRAIN[t.terrain].water && t.terrain === 'water') continue;
      this.diamondPath(ctx, t.x, t.y, 0.02);
    }
    ctx.stroke();
    ctx.restore();
  }

  private fillTiles(ctx: CanvasRenderingContext2D, tiles: Iterable<Pt>, fill: string, stroke?: string, inset = 0.04) {
    ctx.beginPath();
    for (const t of tiles) this.diamondPath(ctx, t.x, t.y, inset);
    ctx.fillStyle = fill;
    ctx.fill();
    if (stroke) {
      ctx.strokeStyle = stroke;
      ctx.lineWidth = 2;
      ctx.stroke();
    }
  }

  /** The ground to hold: a gold outline (red and pulsing while it is being overrun). */
  private drawZone(ctx: CanvasRenderingContext2D, time: number) {
    const zone = this.b.map.zone;
    if (!zone?.length) return;
    if (this.overrunWarn && this.b.overrun === 0) this.overrunWarn = false;
    const inZone = new Set(zone.map((p) => key(p.x, p.y)));
    const danger = this.overrunWarn;
    const pulse = 0.5 + 0.5 * Math.sin(time * 5);
    this.fillTiles(ctx, zone, danger ? `rgba(220,60,40,${0.1 + 0.08 * pulse})` : 'rgba(255,215,106,0.06)', undefined, 0);
    ctx.save();
    ctx.strokeStyle = danger ? `rgba(255,90,70,${0.6 + 0.4 * pulse})` : 'rgba(255,215,106,0.75)';
    ctx.lineWidth = 3;
    ctx.setLineDash([10, 7]);
    ctx.lineDashOffset = -time * 12;
    ctx.beginPath();
    for (const p of zone) {
      const th = tileAt(this.b.map, p.x, p.y)?.h ?? 0;
      const c = (gx: number, gy: number): [number, number] => [isoX(gx, gy), isoY(gx, gy, th)];
      // Outer edges only: those not shared with another tile of the zone.
      const edges: [number, number, [number, number], [number, number]][] = [
        [0, -1, c(p.x - 0.5, p.y - 0.5), c(p.x + 0.5, p.y - 0.5)],
        [1, 0, c(p.x + 0.5, p.y - 0.5), c(p.x + 0.5, p.y + 0.5)],
        [0, 1, c(p.x + 0.5, p.y + 0.5), c(p.x - 0.5, p.y + 0.5)],
        [-1, 0, c(p.x - 0.5, p.y + 0.5), c(p.x - 0.5, p.y - 0.5)],
      ];
      for (const [dx, dy, a, bb] of edges) {
        if (inZone.has(key(p.x + dx, p.y + dy))) continue;
        ctx.moveTo(a[0], a[1]);
        ctx.lineTo(bb[0], bb[1]);
      }
    }
    ctx.stroke();
    ctx.restore();
  }

  /**
   * Where the next waves will march in: red tiles with arrows pointing onto
   * the field, bright and pulsing for a wave due at the end of this turn,
   * faint for the one after.
   */
  private drawEntryWarnings(ctx: CanvasRenderingContext2D, time: number) {
    const b = this.b;
    b.waves.forEach((w, i) => {
      if (b.waveState[i] === 'cancelled' || (w.horn && b.horn !== 'sounded')) return;
      const waiting = w.uids.filter((uid) => this.views.get(uid)?.reserve).length;
      if (!waiting) return;
      const dueIn = w.turn - this.ui.turn;
      if (dueIn > 1) return;
      const entries = (b.map.entries?.[w.edge] ?? []).slice(0, waiting);
      const pulse = dueIn <= 0 ? 0.55 + 0.45 * Math.sin(time * 6) : 0.35;
      this.fillTiles(ctx, entries, `rgba(220,50,35,${0.2 * pulse + (dueIn <= 0 ? 0.12 : 0.04)})`, `rgba(255,90,70,${0.5 * pulse})`, 0.06);
      const inward = DIRS[INWARD_DIR[w.edge]];
      for (const p of entries) {
        const th = tileAt(b.map, p.x, p.y)?.h ?? 0;
        const P = (a: number, s: number): [number, number] => {
          const gx = p.x + inward.x * a - inward.y * s;
          const gy = p.y + inward.y * a + inward.x * s;
          return [isoX(gx, gy), isoY(gx, gy, th)];
        };
        ctx.save();
        ctx.globalAlpha = dueIn <= 0 ? 0.55 + 0.45 * pulse : 0.4;
        ctx.fillStyle = '#ff6a50';
        ctx.strokeStyle = 'rgba(40,10,5,0.8)';
        ctx.lineWidth = 1.5;
        for (const off of [-0.25, 0.1]) {
          const pts = [P(off + 0.3, 0), P(off, 0.22), P(off + 0.08, 0), P(off, -0.22)];
          ctx.beginPath();
          pts.forEach(([x, y], k) => (k ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
          ctx.closePath();
          ctx.fill();
          ctx.stroke();
        }
        ctx.restore();
      }
    });
  }

  private drawHighlights(ctx: CanvasRenderingContext2D, time: number) {
    const b = this.b;
    this.drawZone(ctx, time);
    this.drawEntryWarnings(ctx, time);
    if (b.phase === 'deploy') {
      this.fillTiles(ctx, b.map.playerDeploy, 'rgba(80,140,255,0.16)', 'rgba(140,190,255,0.35)');
    }
    if (this.ui.danger) {
      const d = [...this.dangerTiles()].map((k) => ({ x: k % 1000, y: Math.floor(k / 1000) })).filter((p) => tileAt(b.map, p.x, p.y));
      this.fillTiles(ctx, d, 'rgba(220,60,40,0.16)');
    }
    // Stance zones.
    for (const u of b.active('player').concat(b.active('enemy'))) {
      if (u.stance === 'spearwall') {
        const zone = DIRS.map((d) => ({ x: u.x + d.x, y: u.y + d.y })).filter((p) => tileAt(b.map, p.x, p.y) && b.arcOf(u, p) !== 'rear');
        this.fillTiles(ctx, zone, 'rgba(240,200,90,0.16)', 'rgba(240,200,90,0.45)', 0.1);
      }
    }
    const sel = this.selectedUnit();
    if (sel && b.phase === 'player' && !this.busy) {
      if (!sel.hasMoved) {
        const reach = this.reach(sel);
        const tiles = [...reach.keys()].map((k) => ({ x: k % 1000, y: Math.floor(k / 1000) }));
        const pulse = 0.26 + 0.05 * Math.sin(time * 3);
        this.fillTiles(ctx, tiles, `rgba(105,165,255,${pulse})`, 'rgba(200,225,255,0.6)', 0.06);
      }
      if (sel.shot && !sel.hasActed && sel.stance !== 'overwatch') {
        // Range ring hint: tiles within range (light).
        ctx.save();
        ctx.setLineDash([6, 8]);
        ctx.strokeStyle = 'rgba(255,230,160,0.35)';
        ctx.lineWidth = 2;
        const r = sel.shot.range;
        const cx = isoX(sel.x, sel.y);
        const cy = isoY(sel.x, sel.y, tileAt(b.map, sel.x, sel.y)!.h);
        ctx.beginPath();
        ctx.ellipse(cx, cy, r * TW * 0.7071, r * TH * 0.7071, 0, 0, Math.PI * 2);
        ctx.stroke();
        ctx.restore();
      }
      // Attackable enemies.
      if (!sel.hasActed) {
        const tkey = `${sel.uid}|${this.ui.ability ?? ''}|${sel.x},${sel.y}`;
        if (!this.targetCache || this.targetCache.key !== tkey) this.targetCache = { key: tkey, list: b.targets(sel, sel, this.ui.ability) };
        const targets = this.targetCache.list;
        for (const t of targets) this.fillTiles(ctx, [t], 'rgba(230,70,50,0.28)', 'rgba(255,120,90,0.8)', 0.08);
      }
    }
    // Path preview.
    const path = this.ui.hover.path;
    if (path && path.length > 1 && !this.busy) {
      ctx.save();
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      const pts = path.map((p) => ({ x: isoX(p.x, p.y), y: isoY(p.x, p.y, tileAt(b.map, p.x, p.y)!.h) }));
      ctx.strokeStyle = 'rgba(20,15,10,0.45)';
      ctx.lineWidth = 9;
      ctx.beginPath();
      pts.forEach((p, i) => (i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
      ctx.stroke();
      ctx.strokeStyle = (this.ui.hover.zoc ?? 0) > 0 ? '#ffb070' : '#f4e6b0';
      ctx.lineWidth = 4;
      ctx.setLineDash([2, 10]);
      ctx.lineDashOffset = -time * 30;
      ctx.beginPath();
      pts.forEach((p, i) => (i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.restore();
    }
    // Arrival facing: a bright arrow on the destination, faint ones for the other ways in.
    const hv = this.ui.hover;
    if (hv.dest && hv.facing !== undefined && !this.busy) {
      for (const f of hv.facings ?? []) if (f !== hv.facing) this.drawFacingArrow(ctx, hv.dest, f, 0.62, false);
      this.drawFacingArrow(ctx, hv.dest, hv.facing, 1, true);
    }
    // Hovered tile.
    const ht = this.ui.hover.tile;
    if (ht) {
      ctx.save();
      ctx.beginPath();
      this.diamondPath(ctx, ht.x, ht.y, 0.03);
      ctx.strokeStyle = 'rgba(255,245,210,0.8)';
      ctx.lineWidth = 2.5;
      ctx.stroke();
      ctx.restore();
    }
  }

  /**
   * An arrow on the ground of a tile pointing toward one of its edges: the way
   * a squad will face when it arrives. `main` is the chosen facing; the small
   * ones mark the other approaches the player can pick with Q / E.
   */
  private drawFacingArrow(ctx: CanvasRenderingContext2D, at: Pt, f: Dir, alpha: number, main: boolean, screen?: { w: number; h: number }) {
    const th = tileAt(this.b.map, at.x, at.y)?.h ?? 0;
    const d = DIRS[f];
    // A little larger zoomed out, so it still reads on a large field.
    const k = clamp(0.85 / this.cam.zoom, 1, 1.4);
    const P = (a: number, b: number): [number, number] => {
      const gx = at.x + (d.x * a - d.y * b) * k;
      const gy = at.y + (d.y * a + d.x * b) * k;
      if (!screen) return [isoX(gx, gy), isoY(gx, gy, th)];
      const s = worldToScreen(this.cam, isoX(gx, gy), isoY(gx, gy, th), screen.w, screen.h);
      return [s.x, s.y];
    };
    const pts = main
      ? [P(0.72, 0), P(0.4, 0.3), P(0.44, 0.12), P(0.1, 0.12), P(0.1, -0.12), P(0.44, -0.12), P(0.4, -0.3)]
      : [P(0.66, 0), P(0.44, 0.2), P(0.5, 0), P(0.44, -0.2)];
    ctx.save();
    ctx.globalAlpha *= alpha;
    ctx.lineJoin = 'round';
    ctx.beginPath();
    pts.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
    ctx.closePath();
    ctx.fillStyle = main ? '#ffd76a' : '#f4ead0';
    ctx.strokeStyle = 'rgba(40,25,10,0.9)';
    ctx.lineWidth = (main ? 2.6 : 1.6) * (screen ? Math.max(0.7, this.cam.zoom) : 1);
    ctx.fill();
    ctx.stroke();
    ctx.restore();
  }

  /**
   * Each squad's footprint on its tile, drawn on the ground under everyone:
   * trodden earth, corner marks in the squad's colours and a chevron at its
   * front edge. It shows at a glance which soldiers belong together.
   */
  private drawFootprints(ctx: CanvasRenderingContext2D, time: number) {
    for (const v of this.views.values()) {
      if (!v.visible || v.alive <= 0 || (v.status !== 'active' && v.status !== 'routing')) continue;
      const u = this.b.unit(v.uid);
      const sel = this.ui.selected === v.uid;
      const p = this.viewPos(v);
      const k = 0.86;
      const pts = [[0, -32 * k], [64 * k, 0], [0, 32 * k], [-64 * k, 0]];
      const col = u.faction === 'player' ? (sel ? '#ffd76a' : 'rgba(130,185,255,0.95)') : 'rgba(240,96,74,0.95)';
      ctx.save();
      ctx.globalAlpha = v.alpha;
      ctx.translate(p.x, p.y);
      ctx.beginPath();
      pts.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
      ctx.closePath();
      ctx.fillStyle = sel ? `rgba(255,215,106,${0.13 + 0.07 * Math.sin(time * 4)})` : u.faction === 'player' ? 'rgba(40,70,130,0.13)' : 'rgba(120,30,20,0.12)';
      ctx.fill();
      // Corner brackets.
      ctx.strokeStyle = col;
      ctx.lineWidth = sel ? 3 : 2;
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      ctx.globalAlpha = v.alpha * (sel ? 1 : 0.75);
      ctx.beginPath();
      for (let i = 0; i < 4; i++) {
        const [cx, cy] = pts[i];
        const [px, py] = pts[(i + 3) % 4];
        const [nx, ny] = pts[(i + 1) % 4];
        ctx.moveTo(cx + (px - cx) * 0.22, cy + (py - cy) * 0.22);
        ctx.lineTo(cx, cy);
        ctx.lineTo(cx + (nx - cx) * 0.22, cy + (ny - cy) * 0.22);
      }
      ctx.stroke();
      // Chevron on the front edge.
      const d = DIRS[v.facing];
      const fx = isoX(d.x, d.y) * 0.5 * k;
      const fy = isoY(d.x, d.y) * 0.5 * k;
      ctx.translate(fx, fy);
      ctx.rotate(Math.atan2(fy, fx));
      ctx.fillStyle = col;
      ctx.beginPath();
      ctx.moveTo(9, 0);
      ctx.lineTo(-3, -7);
      ctx.lineTo(0, 0);
      ctx.lineTo(-3, 7);
      ctx.closePath();
      ctx.fill();
      ctx.restore();
    }
  }

  private drawSorted(ctx: CanvasRenderingContext2D, time: number) {
    const b = this.b;
    type Item = { d: number; draw: () => void; shadow?: () => void };
    const items: Item[] = [];
    // Only what can be on screen is drawn: large fields hold hundreds of props.
    const hw = this.w / this.cam.zoom / 2 + 240;
    const hh = this.h / this.cam.zoom / 2;
    const inView = (x: number, y: number) => Math.abs(x - this.cam.x) < hw && y - this.cam.y > -hh - 60 && y - this.cam.y < hh + 420;
    const staged = this.staged();
    // Props on the grid.
    // `marks`: world points that must stay in sight (one is enough to fade a prop).
    const unitBoxes: { x: number; y: number; d: number; marks?: number[][] }[] = [];
    for (const v of this.views.values()) {
      if (!(v.visible || staged.has(v.uid)) || !v.members.some((m) => m.alive || m.dying)) continue;
      const p = this.viewPos(v);
      if (inView(p.x, p.y)) unitBoxes.push({ x: p.x, y: p.y, d: v.x + v.y });
    }
    // Where the selected squad is about to go: a ghost formation. Walls and
    // trees in front of it fade as they would over a squad, so the facing
    // arrow at a gateway stays in sight.
    const ghost = this.moveGhost(ctx);
    if (ghost) unitBoxes.push({ x: ghost.wx, y: ghost.wy, d: ghost.at.x + ghost.at.y, marks: ghost.marks });
    const propItem = (x: number, y: number, h: number, prop: string, vseed: number, outer: boolean) => {
      const px = isoX(x, y) + (outer ? (hash2(x, y, 5) - 0.5) * 40 : 0);
      const py = isoY(x, y, h) + (outer ? (hash2(x, y, 6) - 0.5) * 20 : 0);
      if (!inView(px, py)) return;
      const s = sprite(PROPS[prop]?.sprite ?? prop, vseed);
      const flip = !s.noShadow && hash2(x, y, 9) > 0.5;
      const sc = outer ? 0.9 + hash2(x, y, 3) * 0.35 : 1;
      const d = x + y;
      // Fade a prop only where its opaque pixels actually cover a squad standing behind it.
      let alpha = 1;
      const k = s.scale * sc;
      // The sprite's box in world pixels, for a cheap test before sampling pixels.
      const bx0 = flip ? px - (s.w - s.ax) * k : px - s.ax * k;
      const bx1 = bx0 + s.w * k;
      const by0 = py - s.ay * k;
      for (const ub of unitBoxes) {
        if (ub.d >= d) continue;
        if (ub.marks) {
          const hit = ub.marks.some(([wx, wy]) => {
            if (wx < bx0 || wx > bx1 || wy < by0 || wy > py + 4) return false;
            return opaqueAt(s, flip ? s.ax - (wx - px) / k : s.ax + (wx - px) / k, s.ay + (wy - py) / k);
          });
          if (hit) {
            alpha = 0.28;
            break;
          }
          continue;
        }
        if (ub.x + 30 < bx0 || ub.x - 30 > bx1 || ub.y < by0 || ub.y - 70 > py) continue;
        let covered = 0;
        for (const [ox, oy] of [[0, -22], [0, -44], [-26, -30], [26, -30], [0, -62]]) {
          const wx = ub.x + ox;
          const wy = ub.y + oy;
          const lx = flip ? s.ax - (wx - px) / k : s.ax + (wx - px) / k;
          const ly = s.ay + (wy - py) / k;
          if (opaqueAt(s, lx, ly)) covered++;
        }
        if (covered >= 2) {
          // Squads are small figures: let them read clearly through the foliage.
          alpha = 0.28;
          break;
        }
      }
      const sway = prop.startsWith('tree') ? Math.sin(time * 0.9 + x * 0.7 + y * 0.3) * 0.012 : 0;
      items.push({
        d,
        shadow: () => drawCastShadow(ctx, s, px, py, flip, sc, prop.startsWith('tree') ? 0.2 : 0.16),
        draw: () => drawSprite(ctx, s, px, py, { flip, scale: sc, alpha, rot: sway }),
      });
    };
    for (const t of b.map.tiles) if (t.prop) propItem(t.x, t.y, t.h, t.prop, t.v, false);
    // The forest ring beyond the field is painted into the ground layer (bakeOuter).
    if (this.host && this.hostAlpha > 0.01) {
      const hst = this.host;
      items.push({ d: hst.d, draw: () => {
        ctx.save();
        ctx.globalAlpha = this.hostAlpha;
        ctx.drawImage(hst.canvas, hst.x, hst.y);
        ctx.restore();
      } });
    }
    // The fallen lie where they dropped, under the living.
    for (const c of this.corpses) {
      if (!inView(c.wx, c.wy)) continue;
      items.push({ d: c.d, draw: () => drawSprite(ctx, sprite(`${c.type}_dead`, c.variant), c.wx, c.wy, { flip: c.flip, scale: c.scale, alpha: 0.9 }) });
    }
    // The ghost formation; squads in front of it fade.
    if (ghost) items.push({ d: ghost.at.x + ghost.at.y + 0.04, draw: ghost.draw });
    for (const v of this.views.values()) {
      // Coming waves mass beyond their edge, darkened, until they march in.
      const waiting = v.reserve && staged.has(v.uid);
      if (!(v.visible || waiting) || !v.members.some((m) => m.alive || m.dying)) continue;
      const vp = this.viewPos(v);
      if (!inView(vp.x, vp.y)) continue;
      const u = b.unit(v.uid);
      // Turning on the spot: the squad itself steps aside for its ghost.
      const self = !!ghost && ghost.turn && v.uid === this.ui.selected;
      const hides = self || (!!ghost && v.x + v.y > ghost.at.x + ghost.at.y && this.bodyCovers(v, u, ghost.wx, ghost.wy - 24, 8));
      items.push({
        d: v.x + v.y + 0.05,
        draw: () => this.drawSquad(ctx, v, u, time, hides ? 0.4 : 1, waiting ? 0.42 : 0),
        shadow: () => this.drawSquadShadow(ctx, v, u),
      });
    }
    if (this.relief) {
      for (const q of this.relief.riders) {
        const p = this.riderAt(q, this.relief.t);
        if (p.alpha <= 0) continue;
        const th = tileAt(b.map, Math.round(p.x), Math.round(p.y))?.h ?? 0;
        const wx = isoX(p.x, p.y);
        const wy = isoY(p.x, p.y, th);
        if (!inView(wx, wy)) continue;
        const s = sprite(`margrave_rider_${p.pose}_${facesCamera(q.facing) ? 'f' : 'b'}`, q.variant);
        items.push({
          d: p.x + p.y + 0.05,
          shadow: () => {
            ctx.save();
            ctx.globalAlpha = 0.3 * p.alpha;
            ctx.fillStyle = 'rgb(20,25,10)';
            ctx.beginPath();
            ctx.ellipse(wx, wy + 1, 30, 10, 0, 0, Math.PI * 2);
            ctx.fill();
            ctx.restore();
          },
          draw: () => drawSprite(ctx, s, wx, wy - p.bob, { flip: q.facing === 0 || q.facing === 2, scale: 0.56, alpha: p.alpha }),
        });
      }
    }
    items.sort((p, q) => p.d - q.d);
    for (const it of items) it.shadow?.();
    for (const it of items) it.draw();
  }

  /**
   * The relief of a last stand: the Margrave's riders come down the road the
   * horde came by and fall on its rear, a column of lances three ranks deep,
   * reining in where the field is blocked or the enemy stands.
   */
  private startRelief() {
    const b = this.b;
    const used = new Map<Edge, number>();
    for (const w of b.waves) used.set(w.edge, (used.get(w.edge) ?? 0) + 1);
    const roads = (['w', 'n', 'e', 's'] as Edge[]).filter((e) => b.map.entries?.[e]?.length);
    const edge = roads.sort((p, q) => (used.get(q) ?? 0) - (used.get(p) ?? 0))[0] ?? 's';
    const facing = INWARD[edge];
    const d = DIRS[facing];
    const { w: W, h: H } = b.map;
    const ns = edge === 'n' || edge === 's';
    const edgeTile = (a: number) => (edge === 'n' ? { x: a, y: 0 } : edge === 's' ? { x: a, y: H - 1 } : edge === 'w' ? { x: 0, y: a } : { x: W - 1, y: a });
    const road = b.map.entries?.[edge] ?? [edgeTile(Math.floor((ns ? W : H) / 2))];
    const along = road.map((p) => (ns ? p.x : p.y));
    const lo = Math.min(...along);
    const hi = Math.max(...along);
    const cols = Math.max(3, Math.round((hi - lo + 1) / 0.75));
    const rng = new Rng(b.turn * 31 + W);
    const riders: ReliefRider[] = [];
    for (let rank = 0; rank < 3; rank++) {
      for (let c = 0; c < cols - (rank % 2); c++) {
        const a = lo - 0.2 + ((hi - lo + 0.4) * (c + (rank % 2) * 0.5)) / (cols - 1);
        const e0 = edgeTile(Math.round(a));
        // Ride in until the ground is blocked or the enemy stands in the way.
        let depth = -1;
        while (depth < 4 - rank) {
          const nx = e0.x + d.x * (depth + 1);
          const ny = e0.y + d.y * (depth + 1);
          if (!tilePassable(b.map, nx, ny) || unitAt(b.units, nx, ny)) break;
          depth++;
        }
        const end = Math.max(depth, -0.6) - rank * 0.9 + rng.range(-0.15, 0.15);
        const out = 2.6 + rank * 1.15;
        const side = a - Math.round(a);
        const base = { x: e0.x + (ns ? side : 0), y: e0.y + (ns ? 0 : side) };
        riders.push({
          x0: base.x - d.x * out, y0: base.y - d.y * out,
          x1: base.x + d.x * end, y1: base.y + d.y * end,
          delay: rank * 0.32 + rng.range(0, 0.2), speed: rng.range(3.4, 4),
          facing, variant: (c * 2 + rank) % 6, dust: 0,
        });
      }
    }
    this.relief = { t: 0, glow: 0, edge, riders };
    // Look toward them as they come.
    const ex = riders.reduce((s, q) => s + isoX(q.x1, q.y1), 0) / riders.length;
    const ey = riders.reduce((s, q) => s + isoY(q.x1, q.y1, 0), 0) / riders.length;
    this.cam.tx = lerp(this.cam.x, ex, 0.65);
    this.cam.ty = lerp(this.cam.y, ey - 40, 0.65);
    sfx('hooves');
  }

  /** Where a relief rider is at time `t`, his stride and how far he has come into view. */
  private riderAt(q: ReliefRider, t: number) {
    const len = Math.hypot(q.x1 - q.x0, q.y1 - q.y0);
    const run = Math.max(0, t - q.delay);
    const dur = len / q.speed + 0.4;
    const k = clamp(run / dur, 0, 1);
    // Full gallop most of the way, reining in over the last stretch.
    const f = k < 0.75 ? (k / 0.75) * 0.88 : 0.88 + 0.12 * easeOutCubic((k - 0.75) / 0.25);
    const moving = run > 0 && k < 1;
    const phase = run * 9;
    return {
      x: lerp(q.x0, q.x1, f),
      y: lerp(q.y0, q.y1, f),
      pose: !moving ? (run > 0 ? 'idle' : 'atk') : Math.sin(phase) > 0 ? 'atk' : 'run',
      bob: moving ? Math.abs(Math.sin(phase)) * 4 : 0,
      alpha: run > 0 ? clamp((f * len) / 1.1, 0, 1) : 0,
      moving,
    };
  }

  private stepRelief(dt: number) {
    const r = this.relief!;
    r.t += dt;
    r.glow = r.t < 1.2 ? r.t / 1.2 : Math.max(0.3, 1 - (r.t - 1.2) * 0.2);
    for (const q of r.riders) {
      const p = this.riderAt(q, r.t);
      if (!p.moving) continue;
      q.dust += dt;
      if (q.dust > 0.09) {
        q.dust = 0;
        const th = tileAt(this.b.map, Math.round(p.x), Math.round(p.y))?.h ?? 0;
        this.fx.burst(isoX(p.x, p.y) + (Math.random() - 0.5) * 30, isoY(p.x, p.y, th) + 2, 2, 1, { shape: 'puff', color: 'rgba(196,172,128,1)', speed: 16, vz: 22, gravity: 6, size: 9, max: 1.1, drag: 0.8 });
      }
    }
  }

  /** The sun coming up behind the relief: a warm light from their side of the field. */
  private drawSunrise(ctx: CanvasRenderingContext2D, w: number, h: number) {
    const r = this.relief!;
    const { w: W, h: H } = this.b.map;
    const mid = { n: { x: W / 2, y: -3 }, s: { x: W / 2, y: H + 2 }, w: { x: -3, y: H / 2 }, e: { x: W + 2, y: H / 2 } }[r.edge];
    const s = worldToScreen(this.cam, isoX(mid.x, mid.y), isoY(mid.x, mid.y, 0), w, h);
    const rad = Math.max(w, h) * 1.1;
    const g = ctx.createRadialGradient(s.x, s.y, 0, s.x, s.y, rad);
    g.addColorStop(0, `rgba(255,214,150,${(0.42 * r.glow).toFixed(3)})`);
    g.addColorStop(0.5, `rgba(255,190,120,${(0.16 * r.glow).toFixed(3)})`);
    g.addColorStop(1, 'rgba(255,180,110,0)');
    ctx.save();
    ctx.globalCompositeOperation = 'screen';
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, w, h);
    ctx.restore();
  }

  /** The selected squad's formation at the end of the previewed path, if any. */
  private moveGhost(ctx: CanvasRenderingContext2D): { at: Pt; wx: number; wy: number; marks: number[][]; turn: boolean; draw: () => void } | null {
    const path = this.ui.hover.path;
    const sel = this.selectedUnit();
    if (!path || path.length < 2 || !sel || this.busy) return null;
    const v = this.views.get(sel.uid)!;
    const at = path[path.length - 1];
    const prev = path[path.length - 2];
    const facing = dirOf(prev, at);
    const turn = at.x === sel.x && at.y === sel.y;
    const live = standing(v.members);
    const slots = formationSlots(live.length, sel.size, facing, v.tight, sel.typeId);
    const h = tileAt(this.b.map, at.x, at.y)?.h ?? 0;
    const wx = isoX(at.x, at.y);
    const wy = isoY(at.x, at.y, h);
    const scale = memberScale(sel);
    // The arrow along its length and each ghost soldier's body.
    const d = DIRS[facing];
    const marks = [0.3, 0.5, 0.72].map((a) => [isoX(at.x + d.x * a, at.y + d.y * a), isoY(at.x + d.x * a, at.y + d.y * a, h)]);
    for (const s of slots.slice(0, live.length)) marks.push([wx + s.x, wy + s.y - 26]);
    const draw = () => {
      const order = live.map((m, i) => ({ m, s: slots[i] })).sort((p, q) => p.s.y - q.s.y);
      for (const { m, s } of order) {
        const pk = poseKey(m.type, 'idle', facing);
        drawSprite(ctx, sprite(pk.key, m.variant), wx + s.x, wy + s.y, { flip: pk.flip, scale, alpha: 0.42 });
      }
      // The facing arrow again over the ghost so it reads through the bodies;
      // clearly when the squad turns where it stands.
      this.drawFacingArrow(ctx, at, facing, turn ? 0.9 : 0.4, true);
    };
    return { at, wx, wy, marks, turn, draw };
  }

  /** Sprite for one soldier given the squad's facing, his pose and the squad's order. */
  private memberSprite(v: UnitView, m: Member): { s: Sprite; flip: boolean } {
    if (v.routing) return { s: sprite(`${m.type}_flee_b`, m.variant), flip: v.facing === 2 || v.facing === 0 };
    const pk = poseKey(m.type, m.pose === 'atk' ? 'atk' : 'idle', v.facing);
    return { s: sprite(pk.key, m.variant), flip: pk.flip };
  }

  /** Whether a squad's drawn soldiers cover a world point (with a little tolerance). */
  private bodyCovers(v: UnitView, u: BattleUnit, wx: number, wy: number, tol = 4): boolean {
    const k0 = memberScale(u);
    for (const m of standing(v.members)) {
      const { s, flip } = this.memberSprite(v, m);
      const p = this.memberPos(v, m);
      const k = s.scale * k0;
      for (const [ox, oy] of [[0, 0], [tol, 0], [-tol, 0], [0, tol], [0, -tol]]) {
        const lx = flip ? s.ax - (wx + ox - p.x) / k : s.ax + (wx + ox - p.x) / k;
        const ly = s.ay + (wy + oy - (p.y - v.hop)) / k;
        if (opaqueAt(s, lx, ly)) return true;
      }
    }
    return false;
  }

  /** Feet, bob and lean of one soldier this frame. */
  private memberPose(v: UnitView, m: Member, time: number) {
    const p = this.memberPos(v, m);
    const marching = v.walking;
    // Marching: one shared cadence with a little personal slack, so the
    // squad keeps step without moving like a single cut-out.
    const stride = Math.abs(Math.sin((v.walkT * 3.3 + m.phase * 0.05) * Math.PI));
    const bob = marching * stride * 3.4;
    const side = v.facing === 1 || v.facing === 2 ? -1 : 1;
    const idle = 1 - marching;
    const shiftX = idle * Math.sin(time * 0.43 + m.phase * 2.3) * 0.8;
    const shakeX = m.shake ? Math.sin(time * 60 + m.id) * m.shake * 2.5 : 0;
    const vShake = v.shake ? Math.sin(time * 55) * v.shake * 3 : 0;
    return {
      x: p.x + shiftX + shakeX + vShake,
      y: p.y - bob - v.hop,
      breathe: 1 + Math.sin(time * 2.2 + m.phase) * 0.016 * idle,
      rot: Math.sin(time * 1.1 + m.phase) * 0.014 * idle + side * 0.05 * marching,
    };
  }

  private drawSquadShadow(ctx: CanvasRenderingContext2D, v: UnitView, u: BattleUnit) {
    const k = memberScale(u);
    const big = u.size <= 3 ? 1.5 : UNIT_TYPES[u.typeId].size === 'small' ? 0.8 : 1;
    ctx.save();
    ctx.globalAlpha = v.alpha;
    ctx.fillStyle = 'rgba(20,25,10,0.3)';
    for (const m of v.members) {
      if (!m.alive && !m.dying) continue;
      const p = this.memberPos(v, m);
      ctx.beginPath();
      ctx.ellipse(p.x, p.y + 1, 14 * big, 6.5 * big, 0, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
    // Zoomed out, or on a crowded large field, the contact shadows are enough:
    // a cast shadow per soldier doubles the drawing for little to see.
    if (this.cam.zoom < 0.5 || (this.b.map.scale === 'large' && !this.richShadows)) return;
    for (const m of standing(v.members)) {
      const { s, flip } = this.memberSprite(v, m);
      const p = this.memberPos(v, m);
      drawCastShadow(ctx, s, p.x, p.y, flip, k, 0.16 * v.alpha);
    }
  }

  /** `dim` darkens the squad (a wave still massing beyond the edge). */
  private drawSquad(ctx: CanvasRenderingContext2D, v: UnitView, u: BattleUnit, time: number, fade = 1, dim = 0) {
    const fighting = v.status === 'active' || v.status === 'routing';
    const baseScale = memberScale(u);
    // Back rank first so the front rank overlaps it.
    const bodies = v.members.filter((m) => m.alive || m.dying).sort((a, b) => a.y + a.lunge.y - (b.y + b.lunge.y));
    const bearer = this.standardBearer(v, u);
    const champ = championOf(u);
    for (const m of bodies) {
      const { s, flip } = this.memberSprite(v, m);
      const q = this.memberPose(v, m, time);
      // The champion stands a head taller than his guard.
      const scale = m.id === champ ? baseScale * 1.18 : baseScale;
      const alpha = v.alpha * fade;
      if (m.dying) {
        // Falls: tips over, then settles into the body left on the field.
        const k = easeOutCubic(m.deathT);
        const settle = clamp((m.deathT - 0.55) / 0.45, 0, 1);
        const dir = m.fallFlip ? -1 : 1;
        if (settle < 1) drawSprite(ctx, s, q.x, q.y + k * 3, { flip, scale, rot: dir * k * 1.35, alpha: alpha * (1 - settle) });
        if (settle > 0) drawSprite(ctx, sprite(`${m.type}_dead`, m.variant), q.x, q.y, { flip: m.fallFlip, scale, alpha: alpha * settle * 0.9 });
        if (m.flash > 0) {
          ctx.save();
          ctx.globalCompositeOperation = 'lighter';
          drawSprite(ctx, s, q.x, q.y + k * 3, { flip, scale, rot: dir * k * 1.35, alpha: m.flash * 0.7 * (1 - settle), img: flashOf(s) });
          ctx.restore();
        }
        continue;
      }
      drawSprite(ctx, s, q.x, q.y, { flip, scale, sy: q.breathe, rot: q.rot, alpha });
      if (dim > 0) drawSprite(ctx, s, q.x, q.y, { flip, scale, sy: q.breathe, rot: q.rot, alpha: alpha * dim, img: shadowOf(s) });
      if (m.flash > 0) {
        ctx.save();
        ctx.globalCompositeOperation = 'lighter';
        drawSprite(ctx, s, q.x, q.y, { flip, scale, sy: q.breathe, rot: q.rot, alpha: m.flash * 0.8, img: flashOf(s) });
        ctx.restore();
      }
      if (m === bearer && (fighting || v.reserve)) this.drawStandard(ctx, u, q.x, q.y, flip, time, alpha);
    }
  }

  /** The soldier carrying the squad's standard: the middle of the rear rank. */
  private standardBearer(v: UnitView, u: BattleUnit): Member | undefined {
    if (u.size <= 3 || v.routing) return undefined;
    const live = standing(v.members);
    if (live.length < 2) return undefined;
    // A champion carries his own banner (the warlord's war standard).
    if (championOf(u) >= 0) return undefined;
    const rearY = facesCamera(v.facing) ? Math.min(...live.map((m) => m.toY)) : Math.max(...live.map((m) => m.toY));
    const rear = live.filter((m) => Math.abs(m.toY - rearY) < 3);
    return rear.sort((a, b) => Math.abs(a.toX) - Math.abs(b.toX))[0];
  }

  /** A small standard on a pole, waving: the squad's colours. */
  private drawStandard(ctx: CanvasRenderingContext2D, u: BattleUnit, x: number, y: number, flip: boolean, time: number, alpha: number) {
    const H = memberHeight(u.typeId);
    const px = x + (flip ? -9 : 9);
    const top = y - H - 13;
    const goblin = u.typeId.startsWith('goblin');
    const cloth = u.faction === 'player' ? (u.typeId === 'collie_guard' ? '#1e1c1a' : '#2f58b8') : goblin ? '#a3261c' : '#7a2418';
    const trim = u.faction === 'player' ? (u.typeId === 'collie_guard' ? '#d6a840' : '#ece2c6') : '#1c1612';
    const dir = flip ? -1 : 1;
    ctx.save();
    ctx.globalAlpha *= alpha;
    ctx.strokeStyle = '#3a2614';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(px, y - H * 0.35);
    ctx.lineTo(px, top);
    ctx.stroke();
    // Cloth: a short pennant whose free edge ripples.
    const w = 17;
    const hgt = 11;
    ctx.beginPath();
    ctx.moveTo(px, top + 1);
    for (let i = 1; i <= 5; i++) {
      const t = i / 5;
      ctx.lineTo(px + dir * w * t, top + 1 + Math.sin(time * 5 - t * 4) * 2.2 * t);
    }
    const tail = goblin ? 0.55 : 0.75;
    ctx.lineTo(px + dir * w * tail, top + hgt * 0.55 + Math.sin(time * 5 - 3) * 2);
    ctx.lineTo(px + dir * w, top + hgt + Math.sin(time * 5 - 4) * 2.2);
    ctx.lineTo(px, top + hgt);
    ctx.closePath();
    ctx.fillStyle = cloth;
    ctx.fill();
    ctx.strokeStyle = 'rgba(30,18,10,0.85)';
    ctx.lineWidth = 1.2;
    ctx.stroke();
    // Device: a pale eagle dot for the company, a skull for the raiders.
    ctx.fillStyle = trim;
    ctx.beginPath();
    ctx.arc(px + dir * w * 0.38, top + hgt * 0.5 + Math.sin(time * 5 - 1.5) * 0.8, 2.6, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  private drawOverlays(ctx: CanvasRenderingContext2D, w: number, h: number, time: number) {
    // One shared health bar per squad, cut into one segment per soldier, with
    // morale beneath; drawn in screen space for crispness. Status labels go on
    // after every bar, so a crowded line never hides one under its neighbour's bar.
    const labels: (() => void)[] = [];
    for (const v of this.views.values()) {
      if (!v.visible || v.reserve || v.status === 'dead' || v.status === 'downed' || v.status === 'fled' || v.alive <= 0) continue;
      const u = this.b.unit(v.uid);
      const head = this.headPos(v);
      const s = worldToScreen(this.cam, head.x, head.y, w, h);
      const n = u.size;
      const gap = 2;
      const seg = n <= 3 ? 17 : 8;
      const bw = n * seg + (n - 1) * gap;
      const x = Math.round(s.x - bw / 2);
      const y = Math.round(s.y - 8);
      ctx.fillStyle = 'rgba(15,10,6,0.78)';
      ctx.fillRect(x - 2, y - 2, bw + 4, 12);
      const color = u.faction === 'player' ? (v.alive / n <= 0.34 ? '#e0a03a' : '#58b84a') : '#d9473a';
      for (let i = 0; i < n; i++) {
        const sx = x + i * (seg + gap);
        if (i >= v.alive) {
          // A fallen soldier's share: dark, with a small cross.
          ctx.fillStyle = 'rgba(70,40,30,0.9)';
          ctx.fillRect(sx, y, seg, 5);
          ctx.strokeStyle = 'rgba(220,120,100,0.65)';
          ctx.lineWidth = 1;
          ctx.beginPath();
          ctx.moveTo(sx + seg / 2 - 2, y + 0.5);
          ctx.lineTo(sx + seg / 2 + 2, y + 4.5);
          ctx.moveTo(sx + seg / 2 + 2, y + 0.5);
          ctx.lineTo(sx + seg / 2 - 2, y + 4.5);
          ctx.stroke();
          continue;
        }
        ctx.fillStyle = 'rgba(60,50,40,0.9)';
        ctx.fillRect(sx, y, seg, 5);
        const f = clamp((v.hp - i * u.hpPer) / u.hpPer, 0, 1);
        ctx.fillStyle = color;
        ctx.fillRect(sx, y, Math.max(f > 0 ? 1 : 0, Math.round(seg * f)), 5);
      }
      const mf = clamp(v.morale / u.maxMorale, 0, 1);
      const ms = v.routing ? 'broken' : moraleOf(v.morale, u.maxMorale);
      ctx.fillStyle = MORALE_COLORS[ms];
      ctx.fillRect(x, y + 6, Math.round(bw * mf), 2);
      // Icons.
      let ix = x + bw + 6;
      const icon = (txt: string, col: string) => {
        ctx.font = '700 12px Cinzel, Georgia, serif';
        const tw = ctx.measureText(txt).width;
        const lx = ix;
        labels.push(() => {
          ctx.font = '700 12px Cinzel, Georgia, serif';
          ctx.fillStyle = 'rgba(15,10,6,0.8)';
          ctx.fillRect(lx - 2, y - 3, tw + 4, 14);
          ctx.fillStyle = col;
          ctx.fillText(txt, lx, y + 8);
        });
        ix += tw + 7;
      };
      if (v.routing) icon('FLEEING', '#f2efe4');
      else if (v.stance === 'shieldwall') icon('WALL', '#e9d58f');
      else if (v.stance === 'spearwall') icon('SPEARS', '#e9d58f');
      else if (v.stance === 'overwatch') icon('WATCH', '#e9d58f');
      if (u.leader) icon('★', '#ffcf5a');
      if (u.tags.includes('warchief')) icon('WARCHIEF', '#ffcf5a');
      if (u.tags.includes('herald') && this.b.horn === 'waiting' && this.b.objective.hornTurn !== undefined) {
        const left = this.b.objective.hornTurn - this.ui.turn;
        icon(left <= 0 ? 'HORN NOW' : `HORN IN ${left}`, '#ffb070');
      }
      if (u.faction === 'player' && this.b.phase === 'player' && u.done) {
        ctx.fillStyle = 'rgba(15,10,6,0.6)';
        ctx.fillRect(x - 2, y - 2, bw + 4, 12);
      }
    }
    for (const draw of labels) draw();
    // The chosen arrival facing once more over everything, bars included: in a
    // crowded yard it is the one thing the player must not lose.
    const hv = this.ui.hover;
    if (hv.dest && hv.facing !== undefined && !this.busy && this.selectedUnit()) this.drawFacingArrow(ctx, hv.dest, hv.facing, 0.8, true, { w, h });
    this.drawWaveLabels(ctx, w, h, time);
    if (this.b.map.scale === 'large') this.drawMinimap(ctx, time);
  }

  /**
   * Over each wave massing beyond the field: how many squads and when they
   * march in. A wave whose ground is off screen gets an arrow at the screen
   * edge pointing to it.
   */
  private drawWaveLabels(ctx: CanvasRenderingContext2D, w: number, h: number, time: number) {
    const staged = this.staged();
    if (!staged.size) return;
    const groups = new Map<number, { xs: number[]; ys: number[]; dueIn: number }>();
    this.b.waves.forEach((wave, i) => {
      for (const uid of wave.uids) {
        const dueIn = staged.get(uid);
        if (dueIn === undefined) continue;
        const v = this.views.get(uid)!;
        const p = this.headPos(v);
        const g = groups.get(i) ?? { xs: [], ys: [], dueIn };
        g.xs.push(p.x);
        g.ys.push(p.y);
        groups.set(i, g);
      }
    });
    ctx.save();
    const used: { x: number; y: number; w: number }[] = [];
    for (const [i, g] of groups) {
      const wave = this.b.waves[i];
      const wx = g.xs.reduce((s, x) => s + x, 0) / g.xs.length;
      const wy = Math.min(...g.ys) - 30;
      const s = worldToScreen(this.cam, wx, wy, w, h);
      const when = g.dueIn <= 0 ? 'marches in at the end of this turn' : g.dueIn === 1 ? 'marches in next turn' : `in ${g.dueIn} turns`;
      const text = `${wave.label} · ${wave.uids.length} squads · ${when}`;
      const pulse = g.dueIn <= 0 ? 0.75 + 0.25 * Math.sin(time * 6) : 0.85;
      const on = s.x > 40 && s.x < w - 40 && s.y > 70 && s.y < h - 40;
      ctx.font = '700 13px Cinzel, Georgia, serif';
      if (on) {
        const tw = ctx.measureText(text).width;
        // Keep clear of the company list (left), the top bar, the info panel
        // (top right), the panels at the bottom, and the other wave labels.
        const lx = clamp(s.x, 270 + tw / 2, w - 16 - tw / 2);
        let ly = clamp(s.y, lx + tw / 2 > w - 300 ? 178 : 128, h - 210);
        while (used.some((q) => Math.abs(q.x - lx) < (tw + q.w) / 2 + 6 && Math.abs(q.y - ly) < 24)) ly += 26;
        used.push({ x: lx, y: ly, w: tw });
        ctx.globalAlpha = pulse;
        ctx.fillStyle = 'rgba(40,8,4,0.82)';
        ctx.fillRect(lx - tw / 2 - 8, ly - 16, tw + 16, 22);
        ctx.strokeStyle = 'rgba(255,100,80,0.8)';
        ctx.lineWidth = 1.5;
        ctx.strokeRect(lx - tw / 2 - 8, ly - 16, tw + 16, 22);
        ctx.fillStyle = '#ffb4a0';
        ctx.textAlign = 'center';
        ctx.fillText(text, lx, ly);
        ctx.textAlign = 'left';
        continue;
      }
      // Off screen: an arrow at the border pointing toward the wave.
      const cx = w / 2;
      const cy = h / 2;
      const dx = s.x - cx;
      const dy = s.y - cy;
      const k = Math.min((w / 2 - 70) / Math.max(1, Math.abs(dx)), (h / 2 - 90) / Math.max(1, Math.abs(dy)));
      const ax = cx + dx * k;
      const ay = cy + dy * k;
      const ang = Math.atan2(dy, dx);
      ctx.globalAlpha = pulse;
      ctx.save();
      ctx.translate(ax, ay);
      ctx.rotate(ang);
      ctx.fillStyle = '#e8503a';
      ctx.strokeStyle = 'rgba(30,8,4,0.9)';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(22, 0);
      ctx.lineTo(-10, -14);
      ctx.lineTo(-4, 0);
      ctx.lineTo(-10, 14);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
      ctx.restore();
      const label = `${wave.uids.length} squads ${g.dueIn <= 0 ? 'this turn' : g.dueIn === 1 ? 'next turn' : `in ${g.dueIn} turns`}`;
      ctx.font = '700 12px Cinzel, Georgia, serif';
      const tw = ctx.measureText(label).width;
      let lx = clamp(ax - tw / 2, 8, w - tw - 8);
      let ly = clamp(ay + (dy > 0 ? -26 : 34), 64, h - 10);
      // Clear of the company list on the left, and of any label already placed.
      if (lx < 262 && ly < 620) lx = 262;
      while (used.some((q) => Math.abs(q.x - lx) < tw && Math.abs(q.y - ly) < 22)) ly += 24;
      used.push({ x: lx, y: ly, w: tw });
      ctx.fillStyle = 'rgba(40,8,4,0.8)';
      ctx.fillRect(lx - 6, ly - 14, tw + 12, 19);
      ctx.fillStyle = '#ffb4a0';
      ctx.fillText(label, lx, ly);
    }
    ctx.restore();
  }

  // ---------------------------------------------------------------- minimap

  /** Screen rectangle of the minimap (bottom left) and its scale from world pixels. */
  minimapRect() {
    const b = this.bounds;
    const ww = b.x1 - b.x0 + 200;
    const wh = b.y1 - b.y0 + 200;
    const W = Math.min(250, Math.round(this.w * 0.17));
    const k = W / ww;
    const H = Math.round(wh * k);
    return { x: 14, y: this.h - H - 14, w: W, h: H, k, ox: b.x0 - 100, oy: b.y0 - 100 };
  }

  /** The field drawn once, tile by tile, for the minimap. */
  private buildMinimap(r: ReturnType<BattleScene['minimapRect']>) {
    const c = document.createElement('canvas');
    c.width = r.w;
    c.height = r.h;
    const x = c.getContext('2d')!;
    const m = this.b.map;
    const col = (t: { terrain: string; prop?: string }) => {
      if (t.prop) {
        const p = t.prop;
        if (p.startsWith('tree')) return '#2c4a1e';
        if (p.startsWith('palisade') || p === 'wall_high') return '#5a3a20';
        if (p.startsWith('gate')) return '#c9a35a';
        if (p.startsWith('wall') || p.startsWith('rock')) return '#8a8a80';
        if (p === 'stakes') return '#7a5030';
      }
      return TERRAIN[t.terrain]?.color ?? '#7fa23a';
    };
    const dia = (gx: number, gy: number, fill: string) => {
      const px = (isoX(gx, gy) - r.ox) * r.k;
      const py = (isoY(gx, gy) - r.oy) * r.k;
      const hw = (TW / 2) * r.k + 0.4;
      const hh = (TH / 2) * r.k + 0.4;
      x.fillStyle = fill;
      x.beginPath();
      x.moveTo(px, py - hh);
      x.lineTo(px + hw, py);
      x.lineTo(px, py + hh);
      x.lineTo(px - hw, py);
      x.closePath();
      x.fill();
    };
    for (const g of m.outerGround ?? []) dia(g.x, g.y, TERRAIN[g.terrain]?.color ?? '#7fa23a');
    for (const t of m.tiles) dia(t.x, t.y, col(t));
    return c;
  }

  private drawMinimap(ctx: CanvasRenderingContext2D, time: number) {
    const r = this.minimapRect();
    if (!this.minimap || this.minimap.width !== r.w || this.minimap.height !== r.h) this.minimap = this.buildMinimap(r);
    ctx.save();
    ctx.fillStyle = 'rgba(14,10,6,0.82)';
    ctx.fillRect(r.x - 4, r.y - 4, r.w + 8, r.h + 8);
    ctx.strokeStyle = 'rgba(205,184,138,0.7)';
    ctx.lineWidth = 1.5;
    ctx.strokeRect(r.x - 4, r.y - 4, r.w + 8, r.h + 8);
    ctx.drawImage(this.minimap, r.x, r.y);
    const at = (gx: number, gy: number) => ({ x: r.x + (isoX(gx, gy) - r.ox) * r.k, y: r.y + (isoY(gx, gy) - r.oy) * r.k });
    // Ground to hold.
    for (const p of this.b.map.zone ?? []) {
      const q = at(p.x, p.y);
      ctx.fillStyle = this.overrunWarn ? 'rgba(255,80,60,0.55)' : 'rgba(255,215,106,0.45)';
      ctx.fillRect(q.x - 1.5, q.y - 1, 3, 2);
    }
    // Squads: the company blue, the horde red, coming waves dark red beyond the edge.
    const staged = this.staged();
    for (const v of this.views.values()) {
      const waiting = v.reserve && staged.has(v.uid);
      if (!(v.visible || waiting) || v.status === 'dead' || v.status === 'downed' || v.status === 'fled') continue;
      const u = this.b.unit(v.uid);
      const q = at(v.x, v.y);
      ctx.fillStyle = waiting ? `rgba(150,30,20,${0.6 + 0.3 * Math.sin(time * 4)})` : u.faction === 'player' ? (this.ui.selected === v.uid ? '#ffd76a' : '#7fb4ff') : v.routing ? '#d9b0a0' : '#ff4a36';
      const s = u.faction === 'player' ? 4 : 3.4;
      ctx.fillRect(q.x - s / 2, q.y - s / 2, s, s);
    }
    // The camera's view.
    const tl = screenToWorld(this.cam, 0, 0, this.w, this.h);
    const br = screenToWorld(this.cam, this.w, this.h, this.w, this.h);
    ctx.strokeStyle = 'rgba(255,255,255,0.85)';
    ctx.lineWidth = 1.2;
    const x0 = clamp(r.x + (tl.x - r.ox) * r.k, r.x, r.x + r.w);
    const y0 = clamp(r.y + (tl.y - r.oy) * r.k, r.y, r.y + r.h);
    const x1 = clamp(r.x + (br.x - r.ox) * r.k, r.x, r.x + r.w);
    const y1 = clamp(r.y + (br.y - r.oy) * r.k, r.y, r.y + r.h);
    ctx.strokeRect(x0, y0, x1 - x0, y1 - y0);
    ctx.restore();
  }
}

/** Grid facing of the step onto the field from beyond each edge. */
const INWARD_DIR: Record<string, Dir> = { n: 1, w: 0, e: 2, s: 3 };

const shieldPoses = new Map<string, boolean>();

/**
 * Sprite key and mirroring for a soldier's pose at a facing. +x and +y show
 * the front, -x and -y the back; +x and -x are mirrored. Troops with shields
 * use their shield-leading poses when mirrored, so the shield stays on the
 * soldier's left arm in every direction.
 */
export function poseKey(type: string, pose: 'idle' | 'atk', facing: Dir): { key: string; flip: boolean } {
  let lead = shieldPoses.get(type);
  if (lead === undefined) {
    lead = hasShieldPoses(type);
    shieldPoses.set(type, lead);
  }
  const flip = facing === 0 || facing === 2;
  return { key: `${type}_${pose}_${facesCamera(facing) ? 'f' : 'b'}${flip && lead ? 's' : ''}`, flip };
}

function dirOf(a: Pt, b: Pt): Dir {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  if (Math.abs(dx) >= Math.abs(dy)) return dx >= 0 ? 0 : 2;
  return dy >= 0 ? 1 : 3;
}

function moraleOf(m: number, max: number): MoraleState {
  if (m <= 0) return 'broken';
  const r = m / max;
  if (r >= 0.9) return 'confident';
  if (r >= 0.5) return 'steady';
  if (r >= 0.25) return 'shaken';
  return 'wavering';
}

function rank(s: MoraleState) {
  return ['confident', 'steady', 'shaken', 'wavering', 'broken'].indexOf(s);
}

function cap(s: string) {
  return s[0].toUpperCase() + s.slice(1);
}

export { manhattan };
