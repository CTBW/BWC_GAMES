// Magic and war machine lab: stages spells, war-machine shots and their
// conditions on an open field with the real battle renderer and captures them
// frame by frame for review.
// Usage: node scripts/magiclab.mjs <outDir> [timeScale=0.5]   (BASE_URL overrides the dev server, ONLY filters stages)
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const out = process.argv[2] ?? 'magiclab';
const timeScale = Number(process.argv[3] ?? 0.5);
fs.mkdirSync(out, { recursive: true });
const base = process.env.BASE_URL ?? 'http://localhost:5199';
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1280, height: 760 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto(`${base}/?newgame&seed=3`);
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });

/**
 * Stage squads on a flattened field and run one action. `units`: { tag, type,
 * x, y, facing, alive?, skill?, hurt? }. `action`: { cast: [tag, spell, tag | {x, y}] }
 * or { attack: [tag, tag] } or { turn: 'player' | 'enemy' } (start of a turn: bleeding).
 */
async function stage(name, units, action, opts = {}) {
  if (process.env.ONLY && !name.includes(process.env.ONLY)) return;
  await page.evaluate(async ([units, opts, ts]) => {
    const { makeEnemy, newSoldier, soldierToUnit } = await import('/src/meta/soldier.ts');
    const { UNIT_TYPES } = await import('/src/data/units.ts');
    const { Rng } = await import('/src/core/rng.ts');
    const { BattleScene } = await import('/src/render/battleScene.ts');
    const s = window.__meridius.store;
    s.debug.testBattle('orc_overseer', { seed: 5, mapId: 'forest_clearing' });
    const bt = s.battleScene.b;
    for (const t of bt.map.tiles) {
      t.prop = undefined;
      if (['forest', 'brush', 'water'].includes(t.terrain)) t.terrain = 'grass';
      t.h = 0;
    }
    // Only the staged squads take the field.
    bt.units.length = 0;
    bt.setup.waves = [];
    bt.waveState = [];
    const tags = {};
    units.forEach((spec, i) => {
      const u = UNIT_TYPES[spec.type].faction === 'player'
        ? soldierToUnit(newSoldier(new Rng(40 + i), spec.type, spec.level ?? 1, () => `lab${i}`, 0))
        : makeEnemy(spec.type, 1, `lab-e${i}`, new Rng(60 + i));
      u.uid = `lab-${spec.tag}`;
      u.x = spec.x;
      u.y = spec.y;
      u.facing = spec.facing;
      if (spec.alive) u.alive = spec.alive;
      u.hp = u.alive * u.hpPer - (spec.hurt ?? 0);
      if (spec.skill) {
        u.stats.melee = spec.skill;
        u.stats.ranged = spec.skill;
      }
      if (spec.promoted) u.abilities.push('mending_circle');
      bt.units.push(u);
      bt.hitsTaken[u.uid] = 0;
      tags[spec.tag] = u.uid;
    });
    // A fresh scene paints the flattened ground and makes the squads' views.
    bt.phase = 'player';
    const sc = new BattleScene(bt);
    sc.subscribe(() => s.emit());
    s.battleScene = sc;
    s.engine.setScene(sc);
    const f = opts.focus ?? units[0];
    sc.ui.selected = undefined;
    sc.ui.banner = undefined;
    sc.ui.showGrid = false;
    sc.cam.tx = sc.cam.x = (f.x - f.y) * 64;
    sc.cam.ty = sc.cam.y = (f.x + f.y) * 32 - 40;
    sc.cam.tzoom = sc.cam.zoom = opts.zoom ?? 1.25;
    s.engine.timeScale = ts;
    window.__lab = { tags };
    s.emit();
  }, [units, opts, timeScale]);
  await page.waitForTimeout(600);
  const result = await page.evaluate(([action]) => {
    const sc = window.__meridius.store.battleScene;
    const bt = sc.b;
    const { tags } = window.__lab;
    let ok = true;
    // Conditions already on squads when the action starts.
    for (const [tag, id, turns, power] of action.with ?? []) {
      bt.unit(tags[tag]).statuses.push({ id, turns, power });
      sc.views.get(tags[tag]).statuses.push(id);
    }
    if (action.cast) {
      const [who, spell, at] = action.cast;
      const u = bt.unit(tags[who]);
      bt.phase = u.faction === 'player' ? 'player' : 'enemy';
      const tile = typeof at === 'string' ? bt.unit(tags[at]) : at;
      ok = bt.cast(u.uid, spell, { x: tile.x, y: tile.y });
      if (!ok) sc.ui.log.unshift({ text: `cast refused: ${bt.spellPreview(u, spell, tile).reason ?? bt.canCast(u, spell).reason}` });
    } else if (action.attack) {
      const [who, target] = action.attack;
      const u = bt.unit(tags[who]);
      bt.phase = u.faction === 'player' ? 'player' : 'enemy';
      ok = bt.attack(u.uid, tags[target]);
      if (!ok) sc.ui.log.unshift({ text: `attack refused: ${bt.preview(u, bt.unit(tags[target])).reason}` });
    } else if (action.statuses) {
      // Lay conditions directly (for a still of how they look).
      for (const [tag, id] of action.statuses) {
        const u = bt.unit(tags[tag]);
        u.statuses.push({ id, turns: 2, power: 6 });
        sc.views.get(u.uid).statuses.push(id);
      }
    } else if (action.turn) {
      bt.startTurn(action.turn);
    }
    sc.pump();
    return ok;
  }, [action]);
  const dir = path.join(out, name);
  fs.mkdirSync(dir, { recursive: true });
  const frames = opts.frames ?? 80;
  for (let i = 0; i < frames; i++) {
    await page.screenshot({ path: path.join(dir, `${String(i).padStart(3, '0')}.png`) });
    const busy = await page.evaluate(() => window.__meridius.store.battleScene.busy);
    if (!busy && i > (opts.minFrames ?? 14)) break;
  }
  const log = await page.evaluate(() => window.__meridius.store.battleScene.ui.log.map((l) => l.text).reverse());
  fs.writeFileSync(path.join(dir, 'log.txt'), `${result ? 'ok' : 'REFUSED'}\n${log.join('\n')}`);
  console.log(name, result ? 'ok' : 'REFUSED', log.slice(-3).join(' | '));
}

await stage('lightning', [
  { tag: 'm', type: 'battle_mage', x: 5, y: 9, facing: 3, skill: 400 },
  { tag: 'f', type: 'footman', x: 5, y: 7, facing: 3 },
  { tag: 'g1', type: 'goblin_spear', x: 5, y: 4, facing: 1 },
  { tag: 'g2', type: 'goblin_rabble', x: 6, y: 4, facing: 1 },
  { tag: 'g3', type: 'goblin_spear', x: 7, y: 5, facing: 1 },
], { cast: ['m', 'chain_lightning', 'g1'] }, { focus: { x: 6, y: 6 } });

await stage('frost', [
  { tag: 'm', type: 'battle_mage', x: 5, y: 9, facing: 3, skill: 400 },
  { tag: 'f', type: 'spearman', x: 4, y: 7, facing: 3 },
  { tag: 'o', type: 'orc_warrior', x: 5, y: 5, facing: 1 },
  { tag: 'g', type: 'goblin_spear', x: 6, y: 5, facing: 1 },
], { cast: ['m', 'frost_blast', 'o'] }, { focus: { x: 5, y: 7 } });

await stage('heal', [
  { tag: 'm', type: 'battle_mage', x: 5, y: 9, facing: 3, promoted: true },
  { tag: 'f', type: 'footman', x: 5, y: 7, facing: 3, alive: 4, hurt: 20 },
  { tag: 'g', type: 'goblin_spear', x: 5, y: 6, facing: 1 },
], { cast: ['m', 'healing_light', 'f'] }, { focus: { x: 5, y: 8 }, zoom: 1.5 });

await stage('fireball', [
  { tag: 's', type: 'goblin_shaman', x: 5, y: 2, facing: 1, skill: 400 },
  { tag: 'g', type: 'goblin_spear', x: 5, y: 5, facing: 1 },
  { tag: 'f1', type: 'footman', x: 5, y: 6, facing: 3 },
  { tag: 'f2', type: 'crossbowman', x: 6, y: 6, facing: 3 },
], { cast: ['s', 'fireball', 'f1'] }, { focus: { x: 5, y: 4 } });

await stage('bloodlust', [
  { tag: 's', type: 'goblin_shaman', x: 5, y: 2, facing: 1 },
  { tag: 'b', type: 'orc_brute', x: 5, y: 5, facing: 1 },
  { tag: 'f', type: 'footman', x: 5, y: 7, facing: 3 },
], { cast: ['s', 'bloodlust', 'b'] }, { focus: { x: 5, y: 4 }, zoom: 1.5 });

await stage('gutripper', [
  { tag: 's', type: 'goblin_shaman', x: 5, y: 2, facing: 1, skill: 400 },
  { tag: 'f', type: 'footman', x: 5, y: 6, facing: 3 },
], { cast: ['s', 'gutripper', 'f'] }, { focus: { x: 5, y: 4 }, zoom: 1.5 });

await stage('bleeding-tick', [
  { tag: 'f', type: 'spearman', x: 5, y: 6, facing: 3 },
  { tag: 'g', type: 'goblin_spear', x: 5, y: 2, facing: 1 },
], { turn: 'player', with: [['f', 'bleeding', 2, 30]] }, { focus: { x: 5, y: 6 }, zoom: 1.7 });

await stage('ballista', [
  { tag: 'b', type: 'ballista', x: 5, y: 10, facing: 3, skill: 400 },
  { tag: 'g1', type: 'goblin_spear', x: 5, y: 6, facing: 1 },
  { tag: 'g2', type: 'goblin_rabble', x: 5, y: 5, facing: 1 },
], { attack: ['b', 'g1'] }, { focus: { x: 5, y: 8 } });

await stage('mangonel', [
  { tag: 'm', type: 'mangonel', x: 5, y: 10, facing: 3, skill: 400 },
  { tag: 'f', type: 'footman', x: 4, y: 5, facing: 3 },
  { tag: 'g1', type: 'goblin_rabble', x: 5, y: 4, facing: 1 },
  { tag: 'g2', type: 'goblin_spear', x: 6, y: 4, facing: 1 },
], { cast: ['m', 'hurl_stone', 'g1'] }, { focus: { x: 5, y: 7 }, zoom: 1.0 });

await stage('rock-lobber', [
  { tag: 'r', type: 'rock_lobber', x: 5, y: 1, facing: 1 },
  { tag: 'f', type: 'footman', x: 5, y: 7, facing: 3 },
  { tag: 's', type: 'spearman', x: 6, y: 7, facing: 3 },
], { cast: ['r', 'lob_rock', 'f'] }, { focus: { x: 5, y: 4 }, zoom: 1.0 });

await stage('war-wagon', [
  { tag: 'w', type: 'war_wagon', x: 5, y: 5, facing: 1, skill: 400 },
  { tag: 'f', type: 'footman', x: 5, y: 6, facing: 3 },
], { attack: ['w', 'f'] }, { focus: { x: 5, y: 6 }, zoom: 1.7 });

await stage('conditions', [
  { tag: 'a', type: 'goblin_spear', x: 4, y: 5, facing: 1 },
  { tag: 'b', type: 'orc_brute', x: 6, y: 5, facing: 1 },
  { tag: 'c', type: 'footman', x: 5, y: 7, facing: 3 },
  { tag: 'm', type: 'battle_mage', x: 4, y: 8, facing: 3 },
  { tag: 'w', type: 'war_wagon', x: 7, y: 7, facing: 2 },
  { tag: 'bl', type: 'ballista', x: 6, y: 9, facing: 3 },
], { statuses: [['a', 'chilled'], ['b', 'bloodlust'], ['c', 'bleeding']] }, { focus: { x: 5, y: 7 }, zoom: 1.35, frames: 6, minFrames: 3 });

// Every war machine in all four facings, with its crew.
const parade = [];
['ballista', 'mangonel', 'rock_lobber', 'war_wagon'].forEach((type, i) => {
  [0, 1, 2, 3].forEach((facing, j) => parade.push({ tag: `${type}${facing}`, type, x: 2 + j * 3, y: 1 + i * 3, facing }));
});
await stage('engines-facings', parade, { statuses: [] }, { focus: { x: 6.5, y: 5.5 }, zoom: 0.95, frames: 3, minFrames: 1 });
for (const [name, types] of [['engines-close-company', ['ballista', 'mangonel']], ['engines-close-host', ['rock_lobber', 'war_wagon']]]) {
  const close = [];
  types.forEach((type, i) => [0, 1, 2, 3].forEach((facing, j) => close.push({ tag: `${type}${facing}`, type, x: 3 + j * 2, y: 4 + i * 2, facing })));
  await stage(name, close, { statuses: [] }, { focus: { x: 6, y: 5 }, zoom: 1.7, frames: 3, minFrames: 1 });
}

console.log(errors.length ? `PAGE ERRORS:\n${errors.join('\n')}` : 'no page errors');
await browser.close();
