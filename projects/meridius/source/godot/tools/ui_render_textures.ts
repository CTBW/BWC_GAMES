// Renders the original stylesheet's procedural paper textures (the `--paper`
// and `--blotch` SVG feTurbulence images in src/ui/styles.css) through the
// browser to assets/ui/paper.png (240 px tile) and assets/ui/blotch.png (600 px
// tile), so the Godot panels use exactly the same grain. Run from the
// TypeScript project (uses playwright-core and the installed Microsoft Edge):
//   cd projects/meridius/source/game && npx vite-node ../godot/tools/ui_render_textures.ts

import { readFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright-core';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '..', 'assets', 'ui');
mkdirSync(out, { recursive: true });
const css = readFileSync(join(here, '..', '..', 'game', 'src', 'ui', 'styles.css'), 'utf8');

function cssUrl(name: string): string {
  const m = css.match(new RegExp(`--${name}: url\\("([^"]+)"\\)`));
  if (!m) throw new Error(`--${name} not found`);
  return m[1];
}

const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 800, height: 800 }, deviceScaleFactor: 1 });
for (const [name, size] of [['paper', 240], ['blotch', 600]] as const) {
  const url = cssUrl(name);
  await page.setContent(
    `<html><body style="margin:0;background:transparent"><div id="t" style="width:${size}px;height:${size}px;background-image:url(&quot;${url.replaceAll('"', '&quot;')}&quot;)"></div></body></html>`,
  );
  await page.waitForTimeout(300);
  await page.locator('#t').screenshot({ path: join(out, `${name}.png`), omitBackground: true });
  console.log(`wrote ${name}.png (${size}px)`);
}
await browser.close();
