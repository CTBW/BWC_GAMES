// Formation gallery from the real battle renderer: squads at every strength
// (6..1, trolls 3..1) and all four facings, for close visual review.
// Usage: node scripts/formations.mjs <outDir>   (BASE_URL overrides the dev server)
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const out = process.argv[2] ?? 'formations';
fs.mkdirSync(out, { recursive: true });
const base = process.env.BASE_URL ?? 'http://localhost:5199';
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto(`${base}/?newgame&seed=3`);
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });

// Lay out squads on an open field: one row per facing, strength falling left to right.
const setup = async (encounter, rows) => {
  await page.evaluate(([enc, rows]) => {
    const s = window.__meridius.store;
    s.debug.testBattle(enc, { seed: 5, mapId: 'forest_clearing' });
    const sc = s.battleScene;
    const b = sc.b;
    for (const t of b.map.tiles) { t.prop = undefined; t.h = 0; }
    sc.terrain = sc.terrain; // terrain art stays; props are cleared for a clean view
    b.map.outer = b.map.outer.filter(() => true);
    // Clone template squads of each type so any number can be shown.
    const templates = b.units.slice();
    for (const u of templates) { u.status = 'fled'; u.x = -50; u.y = -50; sc.views.get(u.uid).visible = false; }
    rows.forEach((row, r) => {
      row.squads.forEach((sq, c) => {
        const tpl = templates.find((x) => x.typeId === sq.type) ?? templates[0];
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
    const mx = 3 + 5, my = 2 + rows.length;
    sc.cam.tx = sc.cam.x = (mx - my) * 64;
    sc.cam.ty = sc.cam.y = (mx + my) * 32 - 30;
    sc.cam.tzoom = sc.cam.zoom = 1.25;
    s.emit();
  }, [encounter, rows]);
  await page.waitForTimeout(900);
};

await setup('orc_overseer', [0, 1, 2, 3].map((f) => ({ facing: f, squads: [6, 5, 4, 3, 2, 1].map((a, c) => ({ type: c % 2 ? 'footman' : 'spearman', alive: a })) })));
await page.screenshot({ path: path.join(out, 'player-strengths.png') });
await setup('moss_trolls', [0, 1, 2, 3].map((f) => ({ facing: f, squads: [{ type: 'troll', alive: 3 }, { type: 'troll', alive: 2 }, { type: 'troll', alive: 1 }, { type: 'goblin_spear', alive: 6 }, { type: 'goblin_archer', alive: 5 }, { type: 'goblin_spear', alive: 3 }] })));
await page.screenshot({ path: path.join(out, 'trolls-goblins.png') });
await setup('warband_camp', [0, 1, 2, 3].map((f) => ({ facing: f, squads: [6, 5, 4, 3, 2, 1].map((a) => ({ type: 'orc_warlord', alive: a })) })));
await page.screenshot({ path: path.join(out, 'warlord-guard.png') });
console.log(errors.length ? errors.join('\n') : 'no page errors');
await browser.close();
