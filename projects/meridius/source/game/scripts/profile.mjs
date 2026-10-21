// CPU profile of a scene for a few seconds; prints the functions with the most self time.
// Usage: node scripts/profile.mjs [encounter] [mapId]
import { chromium } from 'playwright-core';
const [enc = 'refugee_stand', mapId = 'ford'] = process.argv.slice(2);
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));
await page.goto('http://localhost:5199/?newgame&seed=5');
await page.waitForFunction(() => window.__meridius?.store?.screen === 'base');
await page.evaluate(([enc, mapId]) => window.__meridius.store.debug.testBattle(enc, { seed: 5, mapId }), [enc, mapId]);
await page.waitForTimeout(2500);
const cdp = await page.context().newCDPSession(page);
await cdp.send('Profiler.enable');
await cdp.send('Profiler.setSamplingInterval', { interval: 200 });
await cdp.send('Profiler.start');
await page.waitForTimeout(4000);
const { profile } = await cdp.send('Profiler.stop');
const self = new Map();
const dt = profile.timeDeltas;
const byId = new Map(profile.nodes.map((n) => [n.id, n]));
const counts = new Map();
for (const s of profile.samples) counts.set(s, (counts.get(s) ?? 0) + 1);
let total = 0;
for (const [id, c] of counts) {
  const n = byId.get(id);
  const k = `${n.callFrame.functionName || '(anon)'} ${n.callFrame.url.split('/').pop()}:${n.callFrame.lineNumber + 1}`;
  self.set(k, (self.get(k) ?? 0) + c);
  total += c;
}
void dt;
const top = [...self.entries()].sort((a, b) => b[1] - a[1]).slice(0, 22);
for (const [k, c] of top) console.log(((c / total) * 100).toFixed(1).padStart(5) + '%', k);
await browser.close();
