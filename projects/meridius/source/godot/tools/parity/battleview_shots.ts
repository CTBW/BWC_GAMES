// Reference captures of the original battle scene for the Godot battle view:
// the same scenes as tests/visual/battle_shots.gd (staged like the original's
// review scripts), at 1920×1080 with the HUD hidden, stepped at a fixed 1/60 s
// by calling the scene's update/render directly (the engine loop is stopped).
//
//   cd projects/meridius/source/game
//   npx vite --port 5184 --strictPort &            # the dev server
//   npx vite-node ../godot/tools/parity/battleview_shots.ts [scenario…]
//
// Output: ../godot/tests/visual/out/battle_ref_<scenario>_<frame>.png
// (BASE_URL overrides http://localhost:5184; CHROME_PATH the Edge binary.)
import { mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const game = join(here, '..', '..', '..', 'game');
const require = createRequire(join(game, 'package.json'));
const { chromium } = require('playwright-core');
const out = join(here, '..', '..', 'tests', 'visual', 'out');
mkdirSync(out, { recursive: true });
const base = process.env.BASE_URL ?? 'http://localhost:5184';
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const ALL = ['deploy', 'march', 'lab', 'formations', 'facing', 'night', 'relief', 'stand', 'horde'];
const args = process.argv.slice(2).filter((a) => !a.startsWith('-'));
const list = args.length ? args : ALL;

const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
const errors: string[] = [];
page.on('pageerror', (e: Error) => errors.push(e.message));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));

type Ev = <T, A>(fn: (a: A) => T, a?: A) => Promise<T>;
const ev = page.evaluate.bind(page) as Ev;

async function newGame(seed: number) {
  await page.goto(`${base}/?newgame&seed=${seed}`);
  await page.waitForFunction(() => (window as any).__meridius?.store?.screen === 'base', null, { timeout: 60000 });
  await page.addStyleTag({ content: '#root { display: none !important; }' });
  await ev(() => {
    const M = (window as any).__meridius;
    M.engine.stop();
    const DT = 1 / 60;
    (window as any).__bv = {
      sc: () => M.store.battleScene,
      step(secs: number) {
        const e = M.engine;
        const sc = M.store.battleScene;
        const n = Math.round(secs / DT);
        for (let i = 0; i < n && M.store.battleScene; i++) {
          e.time += DT;
          sc.update(DT, e.time);
        }
      },
      render() {
        const e = M.engine;
        e.ctx.setTransform(e.dpr, 0, 0, e.dpr, 0, 0);
        M.store.battleScene.render(e.ctx, e.w, e.h, e.time);
      },
      idle(max: number) {
        const sc = M.store.battleScene;
        let t = 0;
        while (t < max) {
          (window as any).__bv.step(6 * DT);
          t += 6 * DT;
          if (!sc.busy) return true;
        }
        return false;
      },
    };
  });
}

async function testBattle(ng: number, enc: string, opts: Record<string, unknown>, night = false) {
  await newGame(ng);
  await ev(([enc, opts, night]) => {
    const M = (window as any).__meridius;
    M.store.debug.testBattle(enc, opts);
    if (night) M.store.battleScene.atmo.night = true;
    M.engine.stop();
    // The scene learns the canvas size in render(); every frame of the game renders.
    (window as any).__bv.render();
  }, [enc, opts, night] as const);
}

const step = (s: number) => ev((s) => (window as any).__bv.step(s), s);
const idle = (max = 60) => ev((m) => (window as any).__bv.idle(m), max);
async function shot(name: string, clip?: { x: number; y: number; width: number; height: number }) {
  // The battle closes (testBattle: back to the garrison) once its end has played.
  if (!(await ev(() => !!(window as any).__meridius.store.battleScene))) return;
  await ev(() => (window as any).__bv.render());
  await page.screenshot({ path: join(out, `battle_ref_${name}.png`), clip });
}
const focus = (gx: number, gy: number, zoom: number, dy = -40) =>
  ev(([gx, gy, zoom, dy]) => {
    const c = (window as any).__meridius.store.battleScene.cam;
    c.tx = c.x = (gx - gy) * 64;
    c.ty = c.y = (gx + gy) * 32 + dy;
    c.tzoom = c.zoom = zoom;
  }, [gx, gy, zoom, dy] as const);
const screenOf = (gx: number, gy: number) =>
  ev(([gx, gy]) => {
    const sc = (window as any).__meridius.store.battleScene;
    const t = sc.b.map.tiles.find((q: any) => q.x === Math.round(gx) && q.y === Math.round(gy));
    const wx = (gx - gy) * 64;
    const wy = (gx + gy) * 32 - (t?.h ?? 0) * 26;
    const c = sc.cam;
    return { x: (wx - c.x) * c.zoom + 960, y: (wy - c.y) * c.zoom + 540 };
  }, [gx, gy] as const);

// ---------------------------------------------------------------- scenarios

async function deploy() {
  await testBattle(7, 'moss_trolls', { seed: 7 });
  await step(1.5);
  await shot('deploy');
  await ev(() => {
    const sc = (window as any).__meridius.store.battleScene;
    const u = sc.b.active('player')[0];
    const v = sc.views.get(u.uid);
    sc.cam.tzoom = 1.5;
    sc.cam.tx = (v.x - v.y) * 64;
    sc.cam.ty = (v.x + v.y) * 32 - 40;
  });
  await step(1.5);
  await shot('deploy_closeup');
}

async function march() {
  await testBattle(7, 'moss_trolls', { seed: 7 });
  await step(0.5);
  await ev(() => (window as any).__meridius.store.battleScene.begin());
  await idle();
  await ev(() => ((window as any).__meridius.store.battleScene.cam.tzoom = 0.86));
  for (let t = 0; t < 2; t++) {
    await ev(() => {
      const sc = (window as any).__meridius.store.battleScene;
      const b = sc.b;
      for (const u of b.active('player')) {
        if (u.shot) continue;
        const reach = b.reachable(u);
        let best: any = null;
        for (const [k] of reach) {
          const p = { x: k % 1000, y: Math.floor(k / 1000) };
          if (!best || p.y < best.y) best = p;
        }
        if (best) b.move(u.uid, best.x, best.y);
      }
      sc.pump();
    });
    for (let i = 0; i < 6; i++) {
      await step(0.26);
      await shot(`march_t${t}_${i}`);
    }
    await idle();
    await ev(() => (window as any).__meridius.store.battleScene.endTurn());
    for (let i = 0; i < 10; i++) {
      await step(0.2);
      await shot(`march_t${t}_enemy_${i}`);
    }
    await idle();
  }
}

/** combatlab.mjs stage(): two squads on a cleared field, `a` attacks `b`. */
async function stage(ng: number, enc: string, opts0: Record<string, unknown>, a: any, b: any, opts: any = {}) {
  await testBattle(ng, enc, opts0);
  await ev(([a, b, opts]) => {
    const sc = (window as any).__meridius.store.battleScene;
    const bt = sc.b;
    for (const t of bt.map.tiles) {
      t.prop = undefined;
      if (t.terrain === 'forest' || t.terrain === 'brush') t.terrain = 'grass';
    }
    const tpl = bt.units.slice();
    for (const u of tpl) {
      u.status = 'fled';
      u.x = -50;
      u.y = -50;
      sc.views.get(u.uid).visible = false;
    }
    const make = (spec: any, tag: string) => {
      const t = tpl.find((x: any) => x.typeId === spec.type);
      const u = JSON.parse(JSON.stringify(t));
      u.uid = `${t.uid}-${tag}`;
      u.status = 'active';
      u.alive = spec.alive ?? u.size;
      u.hp = spec.hp ?? u.alive * u.hpPer;
      u.facing = spec.facing;
      u.x = spec.x;
      u.y = spec.y;
      if (spec.skill) {
        u.stats.melee = spec.skill;
        u.stats.ranged = spec.skill;
      }
      bt.units.push(u);
      bt.hitsTaken[u.uid] = 0;
      sc.views.set(u.uid, sc.makeView(u));
      return u;
    };
    const ua = make(a, 'a');
    const ub = make(b, 'b');
    if (opts.findShot) {
      const tiles = bt.map.tiles.slice().sort((p: any, q: any) => Math.hypot(p.x - a.x, p.y - a.y) - Math.hypot(q.x - a.x, q.y - a.y));
      for (const t of tiles) {
        if (Math.hypot(t.x - ub.x, t.y - ub.y) < 3.5) continue;
        ua.x = t.x;
        ua.y = t.y;
        if (bt.canShoot(ua, ub).ok) break;
      }
      sc.views.set(ua.uid, sc.makeView(ua));
    }
    bt.phase = ua.faction === 'player' ? 'player' : 'enemy';
    sc.ui.selected = undefined;
    sc.ui.banner = undefined;
    const mx = (ua.x + ub.x) / 2;
    const my = (ua.y + ub.y) / 2;
    sc.cam.tx = sc.cam.x = (mx - my) * 64;
    sc.cam.ty = sc.cam.y = (mx + my) * 32 - 40;
    sc.cam.tzoom = sc.cam.zoom = opts.zoom ?? 1.9;
    (window as any).__lab = { a: ua.uid, b: ub.uid, move: opts.move };
  }, [a, b, opts] as const);
  await step(0.28);
  await ev(() => {
    const sc = (window as any).__meridius.store.battleScene;
    const { a, b, move } = (window as any).__lab;
    if (move) sc.b.move(a, move.x, move.y);
    sc.b.attack(a, b);
    sc.pump();
  });
}

async function film(name: string, secs = 2.4, every = 0.1) {
  const crop = { x: 480, y: 180, width: 960, height: 720 };
  let i = 0;
  for (let t = 0; t <= secs + 1e-6; t += every) {
    await shot(`${name}_${String(i).padStart(2, '0')}`, crop);
    await step(every);
    i++;
  }
}

async function lab() {
  await stage(7, 'orc_overseer', { seed: 7 }, { type: 'footman', x: 6, y: 6, facing: 3, skill: 300 }, { type: 'goblin_spear', x: 6, y: 5, facing: 1 });
  await film('lab_melee');
  await stage(7, 'moss_trolls', { seed: 7 }, { type: 'troll', x: 6, y: 5, facing: 1, skill: 300 }, { type: 'footman', x: 6, y: 6, facing: 3 });
  await film('lab_troll');
  await stage(7, 'orc_overseer', { seed: 7 }, { type: 'crossbowman', x: 4, y: 8, facing: 3, skill: 300 }, { type: 'goblin_spear', x: 6, y: 4, facing: 1 }, { zoom: 1.35, findShot: true });
  await film('lab_volley');
  await stage(5, 'warband_camp', { mapId: 'goblin_camp', seed: 5 }, { type: 'orc_warlord', x: 6, y: 5, facing: 1, skill: 300 }, { type: 'footman', x: 6, y: 6, facing: 3, alive: 4 });
  await film('lab_warlord');
}

/** formations.mjs setup(): one row per facing, strength falling left to right. */
async function rows(ng: number, enc: string, opts0: Record<string, unknown>, rows: any[]) {
  await testBattle(ng, enc, opts0);
  await ev((rows) => {
    const sc = (window as any).__meridius.store.battleScene;
    const b = sc.b;
    for (const t of b.map.tiles) {
      t.prop = undefined;
      t.h = 0;
    }
    const templates = b.units.slice();
    for (const u of templates) {
      u.status = 'fled';
      u.x = -50;
      u.y = -50;
      sc.views.get(u.uid).visible = false;
    }
    rows.forEach((row: any, r: number) => {
      row.squads.forEach((sq: any, c: number) => {
        const tpl = templates.find((x: any) => x.typeId === sq.type) ?? templates[0];
        const u = JSON.parse(JSON.stringify(tpl));
        u.uid = `${tpl.uid}-g${r}${c}`;
        u.status = 'active';
        u.alive = sq.alive;
        u.hp = sq.alive * u.hpPer;
        u.facing = row.facing;
        u.x = 3 + c * 2;
        u.y = 2 + r * 2;
        b.units.push(u);
        sc.views.set(u.uid, sc.makeView(u));
      });
    });
    sc.ui.selected = undefined;
    sc.ui.banner = undefined;
  }, rows);
  await focus(3 + 5, 2 + rows.length, 1.25, -30);
  await step(0.9);
}

async function formations() {
  await rows(7, 'orc_overseer', { seed: 7 }, [0, 1, 2, 3].map((f) => ({ facing: f, squads: [6, 5, 4, 3, 2, 1].map((a, c) => ({ type: c % 2 ? 'footman' : 'spearman', alive: a })) })));
  await shot('formations_player');
  await rows(7, 'moss_trolls', { seed: 7 }, [0, 1, 2, 3].map((f) => ({ facing: f, squads: [{ type: 'troll', alive: 3 }, { type: 'troll', alive: 2 }, { type: 'troll', alive: 1 }, { type: 'goblin_spear', alive: 6 }, { type: 'goblin_archer', alive: 5 }, { type: 'goblin_spear', alive: 3 }] })));
  await shot('formations_trolls');
  await rows(5, 'warband_camp', { mapId: 'goblin_camp', seed: 5 }, [0, 1, 2, 3].map((f) => ({ facing: f, squads: [6, 5, 4, 3, 2, 1].map((a) => ({ type: 'orc_warlord', alive: a })) })));
  await shot('formations_warlord');
}

async function facing() {
  await testBattle(3, 'last_stand', { seed: 7 });
  await step(1.5);
  await ev(() => (window as any).__meridius.store.battleScene.begin());
  await idle();
  await step(0.8);
  const plan = await ev(() => {
    const sc = (window as any).__meridius.store.battleScene;
    const b = sc.b;
    const foes = b.active('enemy');
    const gates = b.map.tiles.filter((t: any) => t.prop?.startsWith('gate'));
    let best: any = null;
    for (const u of b.active('player')) {
      const reach = b.reachable(u);
      for (const g of gates) {
        if (!reach.has(g.y * 1000 + g.x)) continue;
        const d = Math.abs(u.x - g.x) + Math.abs(u.y - g.y);
        if (d < 2) continue;
        if (!best || d < best.d) best = { uid: u.uid, gate: [g.x, g.y], d };
      }
    }
    if (!best) return null;
    const [gx, gy] = best.gate;
    let nf: any = null;
    for (const f of foes) {
      const d = Math.abs(f.x - gx) + Math.abs(f.y - gy);
      if (!nf || d < nf.d) nf = { d, x: f.x, y: f.y };
    }
    const dx = nf.x - gx;
    const dy = nf.y - gy;
    best.out = Math.abs(dx) >= Math.abs(dy) ? [Math.sign(dx), 0] : [0, Math.sign(dy)];
    sc.select(best.uid);
    return best;
  });
  if (!plan) return console.log('  no gate in reach');
  await step(0.3);
  await shot('facing_selected');
  const p = await screenOf(plan.gate[0] + plan.out[0] * 0.33, plan.gate[1] + plan.out[1] * 0.33);
  await ev((p) => (window as any).__meridius.store.battleScene.pointerMove({ x: p.x, y: p.y, button: 0, shift: false }), p);
  await step(0.4);
  await shot('facing_gate');
  const clip = { x: Math.min(1280, Math.max(0, Math.round(p.x) - 320)), y: Math.min(660, Math.max(0, Math.round(p.y) - 210)), width: 640, height: 420 };
  await shot('facing_gate_crop', clip);
  const hv = await ev(() => {
    const h = (window as any).__meridius.store.battleScene.ui.hover;
    return { facing: h.facing, facings: h.facings };
  });
  console.log('  facing plan', JSON.stringify(plan), 'hover', JSON.stringify(hv));
  await ev((p) => (window as any).__meridius.store.battleScene.pointerDown({ x: p.x, y: p.y, button: 0, shift: false }), p);
  await idle();
  await step(0.4);
  await shot('facing_arrived', clip);
  // Turn another squad on the spot: point at the edge of its own tile behind it.
  const turn = await ev(() => {
    const sc = (window as any).__meridius.store.battleScene;
    const u = sc.b.active('player').find((q: any) => !q.hasMoved && q.typeId !== 'militia');
    sc.select(u.uid);
    const back = [[-1, 0], [0, -1], [1, 0], [0, 1]][u.facing];
    return { uid: u.uid, x: u.x, y: u.y, back };
  });
  await step(0.3);
  const own = await screenOf(turn.x + turn.back[0] * 0.36, turn.y + turn.back[1] * 0.36);
  await ev((p) => (window as any).__meridius.store.battleScene.pointerMove({ x: p.x, y: p.y, button: 0, shift: false }), own);
  await step(0.3);
  await shot('facing_turn', { x: Math.min(1280, Math.max(0, Math.round(own.x) - 320)), y: Math.min(660, Math.max(0, Math.round(own.y) - 210)), width: 640, height: 420 });
}

async function night() {
  await testBattle(5, 'road_ambush', { seed: 8, night: true, darkness: false }, true);
  await step(1.8);
  await shot('night_torch');
  await testBattle(5, 'road_ambush', { seed: 9, night: true, darkness: true }, true);
  await step(1.8);
  await shot('night_dark');
}

async function relief() {
  await testBattle(3, 'last_stand', { seed: 7 });
  await ev(() => ((window as any).__meridius.store.battleScene.b.objective.turns = 2));
  await step(1.5);
  await shot('relief_start');
  await ev(() => (window as any).__meridius.store.battleScene.begin());
  await idle(120);
  for (let guard = 0; guard < 10; guard++) {
    const st = await ev(() => {
      const sc = (window as any).__meridius.store.battleScene;
      return { phase: sc.b.phase, turn: sc.b.turn, turns: sc.b.objective.turns };
    });
    if (st.phase !== 'player') break;
    await ev(() => {
      const M = (window as any).__meridius;
      M.store.debug.playerTurn();
    });
    await idle(120);
    const last = st.turn >= st.turns;
    await ev(() => (window as any).__meridius.store.battleScene.endTurn());
    if (!last) {
      await idle(240);
      continue;
    }
    for (let t = 0; t < 240; t += 0.1) {
      const r = await ev(() => !!(window as any).__meridius.store.battleScene.relief);
      if (r) break;
      await step(0.1);
    }
    let t0 = 0;
    for (const at of [0.2, 0.8, 1.4, 2.0, 2.6, 3.2, 4.0, 5.0]) {
      await step(at - t0);
      t0 = at;
      await shot(`relief_${at.toFixed(1)}`);
    }
    return;
  }
}

async function stand() {
  await testBattle(3, 'last_stand', { seed: 7 });
  await step(1.5);
  await shot('stand_deploy');
  await ev(() => (window as any).__meridius.store.battleScene.begin());
  await idle(120);
  await step(0.5);
  await shot('stand_turn1');
  await testBattle(3, 'last_stand', { seed: 7, night: true }, true);
  await step(1.5);
  await shot('stand_night');
}

async function horde() {
  await testBattle(3, 'last_stand', { seed: 7 });
  await step(1.0);
  await ev(() => (window as any).__meridius.store.battleScene.begin());
  await idle(120);
  for (let t = 0; t < 4; t++) {
    const phase = await ev(() => (window as any).__meridius.store.battleScene.b.phase);
    if (phase !== 'player') break;
    await ev(() => (window as any).__meridius.store.debug.playerTurn());
    await idle(240);
    await ev(() => (window as any).__meridius.store.battleScene.endTurn());
    await step(2.2);
    await shot(`horde_t${t}_enemy`);
    await idle(240);
    await shot(`horde_t${t + 1}_start`);
  }
}

const SC: Record<string, () => Promise<unknown>> = { deploy, march, lab, formations, facing, night, relief, stand, horde };
for (const s of list) {
  console.log('scenario', s);
  await SC[s]();
}
console.log(errors.length ? errors.join('\n') : 'no page errors');
await browser.close();
