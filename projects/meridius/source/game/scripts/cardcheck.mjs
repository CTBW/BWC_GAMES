// Workspace card check at wide and narrow widths: node scripts/cardcheck.mjs [outDir]
import { chromium } from 'playwright-core';
import { tmpdir } from 'node:os';
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const urls = ['horde.html', 'index.html', 'squads.html', 'loop1.html'].map((f) => `file:///D:/ProjektM/BWC_GAMES/workspace/2026-10-20_meridius/${f}`);
const out = `${process.argv[2] ?? tmpdir()}/`;
for (const url of urls) for (const [w, h, size] of [[1400, 1000, 'wide'], [768, 1024, 'tablet'], [390, 844, 'narrow']]) {
  const name = `${url.split('/').pop().replace('.html', '')}-${size}.png`;
  const page = await browser.newPage({ viewport: { width: w, height: h } });
  const errs = [];
  page.on('pageerror', (e) => errs.push(e.message));
  page.on('requestfailed', (r) => errs.push('failed ' + r.url()));
  await page.goto(url);
  await page.waitForTimeout(800);
  // Lazy images load as they scroll into view.
  await page.evaluate(async () => { for (let y = 0; y < document.body.scrollHeight; y += 600) { window.scrollTo(0, y); await new Promise((r) => setTimeout(r, 60)); } window.scrollTo(0, 0); });
  await page.waitForTimeout(600);
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
  if (overflow) errs.push('horizontal page overflow');
  await page.screenshot({ path: out + name, fullPage: name.includes('narrow') ? false : false });
  const imgs = await page.evaluate(() => `${[...document.images].filter((i) => i.naturalWidth > 0).length}/${document.images.length}`);
  console.log(url.split('/').pop(), name, 'images loaded', imgs, 'errors', errs.length, errs.slice(0, 3).join(' | '));
  // Lightbox check on wide.
  if (w > 1000) {
    await page.locator('.shots img').first().click();
    await page.waitForTimeout(400);
    const open = await page.evaluate(() => !!document.querySelector('dialog.mak-lightbox[open]'));
    const download = await page.evaluate(() => !!document.querySelector('dialog.mak-lightbox[open] a[download]'));
    console.log('lightbox open', open, 'download link', download);
  }
}
await browser.close();
