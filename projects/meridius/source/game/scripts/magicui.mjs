// Spells and war machines through the real interface: choose a spell with its
// key, hover an enemy for the spell forecast, click to cast; a mangonel aimed
// by hovering an enemy; the enemy turn with its shamans; the Barracks' offer.
// Usage: node scripts/magicui.mjs <outDir>   (BASE_URL overrides the dev server)
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const out = process.argv[2] ?? 'magicui';
fs.mkdirSync(out, { recursive: true });
const base = process.env.BASE_URL ?? 'http://localhost:5199';
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 860 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto(`${base}/?newgame&seed=4`);
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });
const shot = (name) => page.screenshot({ path: path.join(out, `${name}.png`) });
const idle = () => page.waitForFunction(() => !window.__meridius.store.battleScene?.busy, null, { timeout: 60000 });

// The Barracks: one specialist squad answers every muster.
await page.evaluate(() => window.__meridius.store.openPanel('barracks'));
await page.waitForTimeout(500);
await shot('barracks');
await page.evaluate(() => window.__meridius.store.openPanel(null));

// A battle with mages and both machines.
await page.evaluate(() => {
  const s = window.__meridius.store;
  s.debug.testBattle('shaman_fire', { seed: 11, army: ['footman', 'spearman', 'battle_mage', 'ballista', 'mangonel', 'crossbowman'], level: 2 });
});
await page.waitForTimeout(800);
await shot('deploy');
await page.evaluate(() => window.__meridius.store.battleScene.begin());
await idle();
await page.waitForTimeout(400);

/** Screen point of a squad's body (a little above its tile centre). */
const screenOf = (uid) =>
  page.evaluate(async (uid) => {
    const { worldToScreen, isoX, isoY } = await import('/src/render/iso.ts');
    const sc = window.__meridius.store.battleScene;
    const v = sc.views.get(uid);
    const w = window.innerWidth;
    const h = window.innerHeight;
    return worldToScreen(sc.cam, isoX(v.x, v.y), isoY(v.x, v.y, v.h) - 24, w, h);
  }, uid);

/** Select a squad of the company by type and bring it into view. */
const select = (type) =>
  page.evaluate((type) => {
    const sc = window.__meridius.store.battleScene;
    const u = sc.b.active('player').find((x) => x.typeId === type);
    sc.select(u.uid);
    return u.uid;
  }, type);

/** The enemy a spell or a stone could reach from the squad, nearest first. */
const targetFor = (uid, spell) =>
  page.evaluate(([uid, spell]) => {
    const sc = window.__meridius.store.battleScene;
    const b = sc.b;
    const u = b.unit(uid);
    const list = b.living().filter((t) => t.faction === 'enemy' && b.spellPreview(u, spell, t).legal);
    list.sort((p, q) => Math.hypot(p.x - u.x, p.y - u.y) - Math.hypot(q.x - u.x, q.y - u.y));
    return list[0]?.uid;
  }, [uid, spell]);

/** Walk the squad toward the enemy until a spell can reach it (only moves, no attacks). */
const closeIn = (uid, spell) =>
  page.evaluate(([uid, spell]) => {
    const sc = window.__meridius.store.battleScene;
    const b = sc.b;
    const u = b.unit(uid);
    const foes = b.living().filter((t) => t.faction === 'enemy');
    let best = null;
    for (const [k] of b.reachable(u)) {
      const p = { x: k % 1000, y: Math.floor(k / 1000) };
      if (foes.some((t) => b.spellPreview(u, spell, t, { from: p, movedTiles: 0 }).legal)) {
        const d = Math.min(...foes.map((t) => Math.hypot(t.x - p.x, t.y - p.y)));
        if (!best || d > best.d) best = { p, d };
      }
    }
    if (best && (best.p.x !== u.x || best.p.y !== u.y)) b.move(uid, best.p.x, best.p.y);
    sc.pump();
    return !!best;
  }, [uid, spell]);

// 1. The mages: Chain Lightning chosen with its key, forecast on hover, cast with a click.
const mage = await select('battle_mage');
if (!(await targetFor(mage, 'chain_lightning'))) {
  await closeIn(mage, 'chain_lightning');
  await idle();
}
await page.evaluate((uid) => window.__meridius.store.battleScene.select(uid), mage);
await page.keyboard.press('1');
await page.waitForTimeout(200);
const t1 = await targetFor(mage, 'chain_lightning');
if (t1) {
  const p = await screenOf(t1);
  await page.mouse.move(p.x, p.y);
  await page.waitForTimeout(400);
  await shot('mage-forecast');
  await page.mouse.click(p.x, p.y);
  await page.waitForTimeout(700);
  await shot('mage-cast');
  await idle();
} else console.log('no lightning target');

// 2. The mangonel: hover an enemy to aim the stone (no key needed), click to loose.
const mg = await select('mangonel');
const t2 = await targetFor(mg, 'hurl_stone');
if (t2) {
  const p = await screenOf(t2);
  await page.mouse.move(p.x, p.y);
  await page.waitForTimeout(400);
  await shot('mangonel-forecast');
  await page.mouse.click(p.x, p.y);
  await page.waitForTimeout(900);
  await shot('mangonel-cast');
  await idle();
} else console.log('no mangonel target in range');

// 3. The rest of the company plays itself; then the enemy turn with its shamans.
await page.evaluate(() => window.__meridius.store.debug.playerTurn());
await idle();
const panelUid = await select('battle_mage');
await page.mouse.move(700, 790);
await page.waitForTimeout(300);
await shot('unit-panel');
void panelUid;
await page.evaluate(() => window.__meridius.store.battleScene.endTurn());
for (let i = 0; i < 40; i++) {
  await page.waitForTimeout(350);
  const st = await page.evaluate(() => {
    const sc = window.__meridius.store.battleScene;
    return { side: sc.ui.side, busy: sc.busy };
  });
  if (i % 4 === 0) await shot(`enemy-turn-${String(i).padStart(2, '0')}`);
  if (st.side === 'player' && !st.busy) break;
}
await shot('after-enemy-turn');
const log = await page.evaluate(() => window.__meridius.store.battleScene.ui.log.map((l) => l.text).reverse());
fs.writeFileSync(path.join(out, 'log.txt'), log.join('\n'));
console.log(log.filter((l) => /Lightning|Frost|Healing|Fireball|Bloodlust|Gutripper|Stone|bolt|blast|arcs|bleed/i.test(l)).join('\n'));
console.log(errors.length ? `PAGE ERRORS:\n${errors.join('\n')}` : 'no page errors');
await browser.close();
