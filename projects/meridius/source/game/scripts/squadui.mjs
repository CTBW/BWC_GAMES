// Squad UI review captures (roster, barracks reinforcements, prep, campaign, battle report, battle HUD).
// node scripts/squadui.mjs <outDir> [w] [h] [sections]
// sections (comma separated, default all): roster,barracks,prep,campaign,collie,battle
// Needs the dev server on :5199. A hot reload during the run resets the page; run the missing section again.
import { chromium } from 'playwright-core';

const [outDir, wArg = '1600', hArg = '900', only = ''] = process.argv.slice(2);
const W = Number(wArg), H = Number(hArg);
const tag = `${W}x${H}`;
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: W, height: H } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto('http://localhost:5199/?newgame&seed=1234');
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });
const shot = async (name) => {
  await page.waitForTimeout(700);
  const p = `${outDir}/${name}-${tag}.png`;
  await page.screenshot({ path: p });
  console.log('saved', p);
};
const want = (n) => !only || only.split(',').includes(n);

// Damage a few squads: per-soldier share = hp / men at full strength.
await page.evaluate(() => {
  const s = window.__meridius.store;
  const g = s.game;
  g.flags = { welcome: true };
  g.resources.silver = 400;
  g.buildings.barracks = 2;
  const hurt = (i, men, shares) => {
    const so = g.roster[i];
    const per = so.hp / so.men;
    so.men = men;
    so.hp = Math.round(per * shares);
  };
  hurt(0, 4, 3.4);
  hurt(2, 5, 5);
  hurt(4, 2, 1.5);
  s.commit();
});

if (want('roster')) {
  await page.evaluate(() => window.__meridius.store.openPanel('roster'));
  await shot('roster');
  await page.evaluate(() => { const s = window.__meridius.store; s.openSoldier(s.game.roster[0].id); });
  await shot('soldier-detail');
  await page.evaluate(() => { const s = window.__meridius.store; s.openSoldier(s.game.roster[4].id); });
  await shot('soldier-detail-xbow');
  await page.evaluate(() => { const s = window.__meridius.store; s.openSoldier(null); s.openPanel(null); });
}
if (want('barracks')) {
  await page.evaluate(() => window.__meridius.store.openPanel('barracks'));
  await shot('barracks');
  await page.evaluate(() => {
    const el = [...document.querySelectorAll('.dialog .scroll')].pop();
    const h = [...el.querySelectorAll('h3')].find((x) => x.textContent.includes('Reinforcements'));
    if (h) el.scrollTop = h.offsetTop - el.offsetTop - 8;
  });
  await shot('barracks-reinforce');
  await page.evaluate(() => window.__meridius.store.openPanel(null));
}
if (want('prep')) {
  await page.evaluate(() => window.__meridius.store.goPrep());
  await shot('prep');
  await page.evaluate(() => window.__meridius.store.goBase());
}
if (want('campaign')) {
  await page.evaluate(() => {
    const s = window.__meridius.store;
    s.game.resources.silver = 150; // keep the autoplayer from refilling everyone
    s.debug.autoPrepare(1);
    const g = s.game;
    const army = g.expedition.army.map((id) => g.roster.find((x) => x.id === id));
    const hurt = (so, men, shares) => { const per = so.hp / so.men; so.men = men; so.hp = Math.round(per * shares); };
    hurt(army[0], 4, 3.4);
    hurt(army[1], 5, 4.2);
    g.expedition.supplies.bandages = 2;
    s.commit();
  });
  await page.waitForTimeout(1500);
  await shot('campaign');
  await page.evaluate(() => {
    const s = window.__meridius.store;
    const g = s.game;
    const army = g.expedition.army.map((id) => g.roster.find((x) => x.id === id));
    g.expedition.pending = {
      kind: 'battleResult',
      report: {
        title: 'Raiding party at Elk Hollow', result: 'victory', objective: false,
        loot: { silver: 34, iron: 1 }, fallen: [{ name: army[3].name, typeId: army[3].typeId, level: 1 }],
        wounded: [{ name: army[2].name, injury: 'Cracked ribs' }], routed: [], levelUps: [`${army[0].name.split(' ')[0]}'s footmen rise to Soldier.`],
        xp: army.map((a) => ({ name: a.name, xp: 7 })), enemiesKilled: 4, enemiesFled: 1, enemySoldiersSlain: 27,
        losses: [
          { name: army[0].name, typeId: army[0].typeId, lost: 2, men: 4, size: 6, fate: 'fought' },
          { name: army[1].name, typeId: army[1].typeId, lost: 1, men: 5, size: 6, fate: 'fought' },
          { name: army[2].name, typeId: army[2].typeId, lost: 5, men: 1, size: 6, fate: 'downed' },
          { name: army[3].name, typeId: army[3].typeId, lost: 6, men: 0, size: 6, fate: 'dead' },
        ],
        bandagesUsed: 1, boltsUsed: 9,
      },
    };
    s.emit();
  });
  await shot('battle-result');
  await page.evaluate(() => { const s = window.__meridius.store; s.game.expedition.pending = null; s.game.expedition.menLost = 14; s.goHome('retreat'); });
  await shot('report');
  await page.evaluate(() => window.__meridius.store.goBase());
}
if (want('collie')) {
  await page.evaluate(() => {
    const s = window.__meridius.store;
    const g = s.game;
    // Stand-in for a level-2 barracks roll: two of the recruits are the royal guard.
    for (const r of g.recruits.slice(0, 2)) { r.typeId = 'collie_guard'; r.men = 6; r.hp = 34 * 6; r.ammo = 0; }
    s.commit();
    s.openPanel('barracks');
  });
  await shot('barracks-collie');
  await page.evaluate(() => {
    const s = window.__meridius.store;
    const g = s.game;
    const r = g.recruits[0];
    g.recruits = g.recruits.filter((x) => x !== r);
    r.men = 5; r.hp = 34 * 4 + 20;
    g.roster.unshift(r);
    s.commit();
    s.openPanel('roster');
  });
  await shot('roster-collie');
  await page.evaluate(() => { const s = window.__meridius.store; s.openPanel(null); s.openManual('squads'); });
  await shot('manual-squads');
  await page.evaluate(() => window.__meridius.store.openManual(null));
}
if (want('battle')) {
  const tb = await page.evaluate(() => {
    const s = window.__meridius.store;
    try { s.debug.testBattle('orc_overseer', { seed: 7 }); } catch (e) { return 'ERR ' + e.message + ' ' + e.stack; }
    return s.screen + ' ' + !!s.battleScene;
  });
  console.log('testBattle:', tb, errors.slice(0, 3).join(' | '));
  await page.waitForTimeout(1500);
  await page.evaluate(() => {
    const s = window.__meridius.store;
    const sc = s.battleScene;
    sc.begin();
  });
  await page.waitForTimeout(3500);
  const info = await page.evaluate(() => {
    const s = window.__meridius.store;
    const sc = s.battleScene;
    const b = sc.b;
    const me = b.units.find((u) => u.faction === 'player' && u.status === 'active');
    // Thin an enemy squad so the HUD shows fallen soldiers.
    const foe = b.units.filter((u) => u.faction === 'enemy' && u.status === 'active').sort((a, c) => Math.abs(a.x - me.x) + Math.abs(a.y - me.y) - Math.abs(c.x - me.x) - Math.abs(c.y - me.y))[0];
    foe.hp = Math.round(foe.hpPer * 3.6);
    foe.alive = 4;
    const v = sc.views.get(foe.uid);
    v.hp = foe.hp; v.alive = foe.alive;
    // Bring the foe next to Bjorn so the forecast shows a legal attack.
    const v0 = sc.views.get(foe.uid);
    for (const [dx, dy] of [[0, -1], [1, 0], [-1, 0], [0, 1]]) {
      const x = me.x + dx, y = me.y + dy;
      if (b.units.some((u) => u.x === x && u.y === y && u.status !== 'dead')) continue;
      const ox = foe.x, oy = foe.y;
      foe.x = x; foe.y = y;
      if (b.preview(me, foe).legal) { v0.x = x; v0.y = y; break; }
      foe.x = ox; foe.y = oy;
    }
    sc.select(me.uid);
    sc.ui.hover = { unit: foe.uid, preview: sc.previewAgainst(me, foe) };
    sc.notify();
    return { me: me.uid, foe: foe.uid, phase: b.phase, pv: sc.ui.hover.preview && { soldiers: sc.ui.hover.preview.soldiers, strikers: sc.ui.hover.preview.strikers } };
  });
  console.log(JSON.stringify(info));
  await shot('battle-forecast');
  await page.evaluate(({ foe }) => {
    const sc = window.__meridius.store.battleScene;
    sc.ui.hover = { unit: foe };
    sc.notify();
  }, info);
  await shot('battle-hover');
  await page.evaluate(() => {
    const s = window.__meridius.store;
    const sc = s.battleScene;
    const xb = sc.b.units.find((u) => u.faction === 'player' && u.shot);
    if (xb) { sc.select(xb.uid); xb.hasMoved = true; }
    sc.ui.hover = {};
    sc.notify();
  });
  await shot('battle-xbow');
}
console.log('errors', errors.length, errors.slice(0, 5).join(' | '));
await browser.close();
