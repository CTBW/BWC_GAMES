// Drives whole expeditions through the real UI and captures each kind of screen.
// Usage: node scripts/expedition.mjs <outDir> [seed] [expeditions]
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const out = process.argv[2] ?? 'exp-out';
const seed = Number(process.argv[3] ?? 77);
const runs = Number(process.argv[4] ?? 2);
fs.mkdirSync(out, { recursive: true });
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
const logs = [];
page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}\n${e.stack}`));
const failed = [];
page.on('response', (r) => {
  if (r.status() >= 400) failed.push(`${r.status()} ${r.url()}`);
});
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
const wait = (ms) => page.waitForTimeout(ms);
const st = (fn, arg) => page.evaluate(fn, arg);
const seen = new Set();
let n = 0;
const shot = async (name, once = true) => {
  if (once && seen.has(name)) return;
  seen.add(name);
  const f = path.join(out, `${String(++n).padStart(2, '0')}-${name}.png`);
  await page.screenshot({ path: f });
  console.log('shot', f);
};

await page.goto(`http://localhost:5199/?newgame&seed=${seed}`);
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });
await st(() => (window.__meridius.engine.timeScale = 6));
await wait(800);

for (let run = 0; run < runs; run++) {
  await st(() => window.__meridius.store.goPrep());
  await wait(500);
  await shot(`prep-${run}`);
  const ok = await page.getByRole('button', { name: 'March Out' }).isEnabled();
  if (!ok) {
    console.log('cannot march: prep invalid');
    break;
  }
  await page.getByRole('button', { name: 'March Out' }).click();
  await page.waitForFunction(() => window.__meridius.store.screen === 'campaign');
  await wait(800);
  await shot(`campaign-start-${run}`);
  let guard = 0;
  while (guard++ < 80) {
    const state = await st(() => {
      const s = window.__meridius.store;
      return { screen: s.screen, kind: s.game.expedition?.pending?.kind ?? null, marching: s.campaignScene?.marching ?? false, result: s.game.expedition?.pending?.result ? true : false };
    });
    if (state.screen === 'report') {
      await wait(500);
      await shot(`report-${run}`, false);
      await page.getByRole('button', { name: 'Back to Amberfeld' }).click();
      await wait(800);
      break;
    }
    if (state.screen === 'battle') {
      await wait(1500);
      await shot('battle-deploy');
      await st(() => window.__meridius.store.debug.autoBattle());
      await page.waitForFunction(() => window.__meridius.store.screen !== 'battle', null, { timeout: 180000 });
      await wait(500);
      continue;
    }
    if (state.marching) {
      await wait(300);
      continue;
    }
    if (!state.kind) {
      // Choose the next march: prefer camps when tired, otherwise any.
      const id = await st(() => {
        const s = window.__meridius.store;
        const ex = s.game.expedition;
        const next = ex.edges.filter((e) => e[0] === ex.current).map((e) => ex.nodes.find((x) => x.id === e[1]));
        const pref = { objective: 9, camp: 3, village: 3, event: 3, scout: 2, battle: 2, ambush: 1 };
        next.sort((a, b) => (pref[b.type] ?? 0) - (pref[a.type] ?? 0) + (Math.random() - 0.5) * 2);
        return next[0]?.id;
      });
      if (!id) break;
      await st((x) => window.__meridius.store.clickNode(x), id);
      await wait(700);
      continue;
    }
    await wait(300);
    await shot(`dialog-${state.kind}${state.result ? '-result' : ''}`);
    if (state.kind === 'event' && !state.result) {
      const choices = page.locator('.choice:not([disabled])');
      if ((await choices.count()) > 0) await choices.first().click();
      await wait(300);
      await shot('dialog-event-result');
      continue;
    }
    if (state.kind === 'camp') {
      for (const label of ['Light torches', 'Mend armour', 'Eat a hot meal']) {
        const b = page.locator('.choice', { hasText: label });
        if ((await b.count()) && (await b.isEnabled())) await b.click();
        await wait(200);
      }
      await shot('dialog-camp-after');
      const brk = page.getByRole('button', { name: 'Break camp' });
      if (await brk.count()) await brk.click();
      continue;
    }
    if (state.kind === 'village') {
      const spots = page.locator('.choice:not([disabled])');
      for (let i = 0; i < 4; i++) {
        if ((await spots.count()) === 0) break;
        await spots.first().click();
        await wait(200);
        const k = await st(() => window.__meridius.store.game.expedition?.pending?.kind);
        if (k !== 'village') break;
      }
      await shot('dialog-village-after');
      const mv = page.getByRole('button', { name: 'Move on' });
      if (await mv.count()) await mv.click();
      continue;
    }
    if (state.kind === 'battle') {
      await page.getByRole('button', { name: 'To Battle' }).click();
      await wait(600);
      continue;
    }
    if (state.kind === 'complete') {
      await page.getByRole('button', { name: 'Return to Amberfeld' }).click();
      await wait(600);
      continue;
    }
    // arrive, scout, event result, battleResult
    const btn = page.locator('.dialog .btn.primary').first();
    if (await btn.count()) await btn.click();
    else await st(() => window.__meridius.store.dismiss());
    await wait(300);
  }
  // Back at base: try an upgrade and a hire, then capture.
  await st(() => window.__meridius.store.openPanel('barracks'));
  await wait(400);
  await shot(`base-barracks-${run}`);
  await st(() => window.__meridius.store.openPanel(null));
  await shot(`base-after-${run}`, false);
}

const summary = await st(() => {
  const g = window.__meridius.store.game;
  return { cycle: g.cycle, res: g.resources, roster: g.roster.map((s) => `${s.name} L${s.level} ${s.typeId} hp${s.hp} m${s.morale} inj:${s.injuries.join('/')}`), fallen: g.fallen.map((f) => f.name), completed: g.completed, chronicle: g.chronicle.slice(0, 12).map((c) => c.text) };
});
console.log(JSON.stringify(summary, null, 2));
fs.writeFileSync(path.join(out, 'console.log'), logs.join('\n'));
const errors = logs.filter((l) => /error/i.test(l));
console.log(`console lines: ${logs.length}, errors: ${errors.length}, failed requests: ${failed.length}`);
for (const f of [...new Set(failed)]) console.log('  ', f);
for (const e of errors.slice(0, 10)) console.log(e);
await browser.close();
