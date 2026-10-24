// Enemy-turn pacing in the real game: node scripts/pacing.mjs [turns] [timeScale]
// Starts a test battle per encounter, lets the player pass each turn and times
// how long the enemy turn plays before control returns.
import { chromium } from 'playwright-core';

const [turnsArg = '4', scaleArg = '1'] = process.argv.slice(2);
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto('http://localhost:5199/?newgame&seed=21');
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base', null, { timeout: 60000 });
const ready = () =>
  page.waitForFunction(() => {
    const s = window.__meridius.store.battleScene;
    return s && !s.busy && (s.b.phase === 'player' || s.b.phase === 'over');
  }, null, { timeout: 120000, polling: 50 });
for (const enc of ['goblin_scouts', 'raiding_party', 'archer_screen', 'orc_overseer', 'warband_camp']) {
  await page.evaluate(([e, sc]) => {
    const { store, engine } = window.__meridius;
    store.game.flags = { welcome: true };
    store.debug.testBattle(e, { seed: 3 });
    engine.timeScale = Number(sc);
    store.battleScene.begin();
  }, [enc, scaleArg]);
  await ready();
  const rows = [];
  for (let t = 0; t < Number(turnsArg); t++) {
    if (await page.evaluate(() => window.__meridius.store.battleScene.b.phase === 'over')) break;
    const t0 = Date.now();
    const before = await page.evaluate(() => window.__meridius.store.battleScene.b.active('enemy').length);
    await page.evaluate(() => window.__meridius.store.battleScene.endTurn());
    await ready();
    const acts = await page.evaluate(() => window.__meridius.store.battleScene.ui.log.length);
    rows.push(`${((Date.now() - t0) / 1000).toFixed(1)}s/${before}e`);
    void acts;
  }
  console.log(enc.padEnd(15), rows.join('  '));
}
console.log('errors', errors.length, errors.slice(0, 3).join(' | '));
await browser.close();
