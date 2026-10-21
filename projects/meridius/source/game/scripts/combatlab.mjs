// Squad combat lab: stages one exchange at a time on an open field with the
// real battle renderer and captures it frame by frame (optionally in slow
// motion) for animation review: melee waves, volleys, casualties, re-forming.
// Usage: node scripts/combatlab.mjs <outDir> [timeScale=0.4]   (BASE_URL overrides the dev server)
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const out = process.argv[2] ?? 'combatlab';
const timeScale = Number(process.argv[3] ?? 0.4);
fs.mkdirSync(out, { recursive: true });
const base = process.env.BASE_URL ?? 'http://localhost:5199';
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1280, height: 760 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto(`${base}/?newgame&seed=3`);
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });

/**
 * Stage two squads: `a` attacks `b`. Positions are grid tiles on a flattened
 * field; `hit` forces the outcome by setting the attacker's skill.
 */
async function stage(name, enc, a, b, opts = {}) {
  if (process.env.ONLY && !name.includes(process.env.ONLY)) return;
  await page.evaluate(([enc, a, b, opts, ts]) => {
    const TERRAIN_LOS = ['forest', 'brush'];
    const s = window.__meridius.store;
    s.debug.testBattle(enc, { seed: 5, mapId: 'forest_clearing' });
    const sc = s.battleScene;
    const bt = sc.b;
    for (const t of bt.map.tiles) { t.prop = undefined; if (TERRAIN_LOS.includes(t.terrain)) t.terrain = 'grass'; }
    const tpl = bt.units.slice();
    for (const u of tpl) { u.status = 'fled'; u.x = -50; u.y = -50; sc.views.get(u.uid).visible = false; }
    const make = (spec, tag) => {
      const t = tpl.find((x) => x.typeId === spec.type);
      const u = JSON.parse(JSON.stringify(t));
      u.uid = `${t.uid}-${tag}`;
      u.status = 'active';
      u.alive = spec.alive ?? u.size;
      u.hp = spec.hp ?? u.alive * u.hpPer;
      u.facing = spec.facing;
      u.x = spec.x;
      u.y = spec.y;
      if (spec.skill) { u.stats.melee = spec.skill; u.stats.ranged = spec.skill; }
      bt.units.push(u);
      sc.views.set(u.uid, sc.makeView(u));
      return u;
    };
    const ua = make(a, 'a');
    const ub = make(b, 'b');
    if (opts.findShot) {
      // Hills can block the view: walk the shooter to the nearest tile with a clear, in-range shot.
      const tiles = bt.map.tiles.slice().sort((p, q) => Math.hypot(p.x - a.x, p.y - a.y) - Math.hypot(q.x - a.x, q.y - a.y));
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
    s.engine.timeScale = ts;
    window.__lab = { a: ua.uid, b: ub.uid, move: opts.move };
    s.emit();
  }, [enc, a, b, opts, timeScale]);
  await page.waitForTimeout(700);
  await page.evaluate(() => {
    const sc = window.__meridius.store.battleScene;
    const { a, b, move } = window.__lab;
    if (move) sc.b.move(a, move.x, move.y);
    const ok = sc.b.attack(a, b);
    if (!ok) sc.ui.log.unshift({ text: `attack refused: ${sc.b.preview(sc.b.unit(a), sc.b.unit(b)).reason ?? 'not allowed now'} (shot: ${sc.b.canShoot(sc.b.unit(a), sc.b.unit(b)).reason ?? 'ok'}, ammo ${sc.b.unit(a).ammo})` });
    sc.pump();
  });
  const dir = path.join(out, name);
  fs.mkdirSync(dir, { recursive: true });
  for (let i = 0; i < 70; i++) {
    await page.screenshot({ path: path.join(dir, `${String(i).padStart(3, '0')}.png`) });
    const busy = await page.evaluate(() => window.__meridius.store.battleScene.busy);
    if (!busy && i > 12) break;
  }
  const log = await page.evaluate(() => window.__meridius.store.battleScene.ui.log.map((l) => l.text).reverse());
  fs.writeFileSync(path.join(dir, 'log.txt'), log.join('\n'));
}

await stage('melee-footmen-goblins', 'orc_overseer',
  { type: 'footman', x: 6, y: 6, facing: 3, skill: 300 },
  { type: 'goblin_spear', x: 6, y: 5, facing: 1 });
await stage('melee-orc-footmen', 'orc_overseer',
  { type: 'orc_warrior', x: 6, y: 4, facing: 1, skill: 300 },
  { type: 'footman', x: 6, y: 6, facing: 3 }, { move: { x: 6, y: 5 } });
await stage('troll-smash', 'moss_trolls',
  { type: 'troll', x: 6, y: 5, facing: 1, skill: 300 },
  { type: 'footman', x: 6, y: 6, facing: 3 });
await stage('volley-crossbows', 'orc_overseer',
  { type: 'crossbowman', x: 4, y: 8, facing: 3, skill: 300 },
  { type: 'goblin_spear', x: 6, y: 4, facing: 1 }, { zoom: 1.35, findShot: true });
await stage('warlord-guard', 'warband_camp',
  { type: 'orc_warlord', x: 6, y: 5, facing: 1, skill: 300 },
  { type: 'footman', x: 6, y: 6, facing: 3, alive: 4 });
await stage('volley-goblin-archers-miss', 'orc_overseer',
  { type: 'goblin_archer', x: 6, y: 3, facing: 1, skill: -300 },
  { type: 'spearman', x: 5, y: 7, facing: 3 }, { zoom: 1.35, findShot: true });
console.log(errors.length ? errors.join('\n') : 'no page errors');
await browser.close();
