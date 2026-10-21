// Render fixtures and reference captures from the original game, for the
// Godot world renderer (terrain, base view, campaign view).
//
// Needs the original's vite dev server (port 5182 by default):
//   cd projects/meridius/source/game && npx vite --port 5182 --strictPort
//   npx vite-node ../godot/tools/parity/render_fixtures_browser.ts
//
// Writes:
//   godot/tests/fixtures/render/*.json   inputs: battle maps, terrain inputs, game states, scene data
//   godot/tests/visual/out/ref/*.png     reference images: terrain layers, colour fields, screens
import { chromium } from 'playwright-core';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const fixtures = join(here, '..', '..', 'tests', 'fixtures', 'render');
const refs = join(here, '..', '..', 'tests', 'visual', 'out', 'ref');
mkdirSync(fixtures, { recursive: true });
mkdirSync(refs, { recursive: true });
const BASE = process.env.BASE_URL ?? 'http://localhost:5182';
const exe = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const only = process.argv.slice(2);
const want = (k: string) => !only.length || only.includes(k);

const browser = await chromium.launch({ executablePath: exe, headless: true });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
const errors: string[] = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.addInitScript(() => localStorage.setItem('meridius.manual.seen', '1'));

const savePng = (name: string, dataUrl: string) => {
  writeFileSync(join(refs, name), Buffer.from(dataUrl.split(',')[1], 'base64'));
};
const saveJson = (name: string, v: unknown) => writeFileSync(join(fixtures, name), JSON.stringify(v) + '\n');

async function boot(seed: number) {
  await page.goto(`${BASE}/?newgame&seed=${seed}`);
  await page.waitForFunction(() => (window as any).__meridius?.store?.screen === 'base', null, { timeout: 60000 });
  await page.evaluate(() => {
    const s = (window as any).__meridius.store;
    s.game.flags = { welcome: true };
    s.commit();
  });
}

/** World-only screenshot: hide the React interface over the canvas. */
async function worldShot(name: string) {
  await page.evaluate(() => ((document.getElementById('root') as HTMLElement).style.visibility = 'hidden'));
  await page.screenshot({ path: join(refs, name) });
  await page.evaluate(() => ((document.getElementById('root') as HTMLElement).style.visibility = 'visible'));
}

/**
 * Build a terrain layer in the page with the original buildTerrain, capturing
 * the raw colour field (putImageData), the finished field (first drawImage of
 * it) and the projected layer. Returns layer metadata.
 */
async function terrainRef(name: string, input: unknown) {
  const res = await page.evaluate(async (inp: any) => {
    const T = await (0, eval)('imp' + 'ort("/src/render/terrain.ts")');
    const proto = CanvasRenderingContext2D.prototype;
    const put = proto.putImageData;
    const draw = proto.drawImage;
    let raw = '';
    let fieldFinal = '';
    proto.putImageData = function (this: CanvasRenderingContext2D, img: ImageData, ...rest: any[]) {
      if (!raw) {
        const c = document.createElement('canvas');
        c.width = img.width;
        c.height = img.height;
        put.call(c.getContext('2d')!, img, 0, 0);
        raw = c.toDataURL('image/png');
      }
      return (put as any).call(this, img, ...rest);
    } as any;
    proto.drawImage = function (this: CanvasRenderingContext2D, src: any, ...rest: any[]) {
      if (!fieldFinal && src instanceof HTMLCanvasElement && src.width === (inp.w + 2 * inp.border) * (inp.res ?? 24)) fieldFinal = src.toDataURL('image/png');
      return (draw as any).call(this, src, ...rest);
    } as any;
    const t0 = performance.now();
    const layer = T.buildTerrain(inp);
    const ms = performance.now() - t0;
    proto.putImageData = put;
    proto.drawImage = draw;
    return { raw, fieldFinal, layer: layer.canvas.toDataURL('image/png'), ox: layer.ox, oy: layer.oy, scale: layer.scale, w: layer.canvas.width, h: layer.canvas.height, waterTiles: layer.waterTiles, ms };
  }, input);
  savePng(`terrain_${name}_field_raw.png`, res.raw);
  savePng(`terrain_${name}_field.png`, res.fieldFinal);
  savePng(`terrain_${name}_layer.png`, res.layer);
  console.log(`terrain ${name}: ${res.w}x${res.h} built in ${res.ms.toFixed(0)} ms`);
  return { ox: res.ox, oy: res.oy, scale: res.scale, w: res.w, h: res.h, waterTiles: res.waterTiles, ms: res.ms };
}

// ---------------------------------------------------------------- battle grounds

const BATTLES: [string, string, Record<string, unknown>][] = [
  ['forest', 'raiding_party', { mapId: 'forest_clearing', seed: 3 }],
  ['river', 'orc_overseer', { mapId: 'river_ruins', seed: 4 }],
  ['camp', 'warband_camp', { mapId: 'goblin_camp', seed: 5 }],
  ['night_torch', 'road_ambush', { seed: 8, night: true, darkness: false }],
  ['steading', 'last_stand', { mapId: 'steading', seed: 11 }],
  ['ford', 'refugee_stand', { mapId: 'ford', seed: 12 }],
];

if (want('battle')) {
  await boot(5);
  const maps: Record<string, unknown> = {};
  for (const [name, enc, opts] of BATTLES) {
    await page.evaluate(([e, o]) => (window as any).__meridius.store.debug.testBattle(e, o), [enc, opts] as const);
    await page.waitForTimeout(1800);
    await page.screenshot({ path: join(refs, `battle_${name}_ui.png`) });
    await worldShot(`battle_${name}.png`);
    const info = await page.evaluate(() => {
      const sc = (window as any).__meridius.store.battleScene;
      const m = sc.b.map;
      return {
        map: m,
        palette: m.biome === 'camp' ? 'camp' : 'summer',
        cam: { x: sc.cam.x, y: sc.cam.y, zoom: sc.cam.zoom },
        night: sc.atmo.night,
        dawn: !!sc.b.objective.dawn,
        darkness: !!sc.b.setup.darkness,
        kind: sc.b.setup.kind,
      };
    });
    const input = {
      w: info.map.w,
      h: info.map.h,
      border: info.map.border,
      tiles: [...info.map.tiles.map((t: any) => ({ x: t.x, y: t.y, h: t.h, terrain: t.terrain })), ...(info.map.outerGround ?? []).map((g: any) => ({ x: g.x, y: g.y, h: 0, terrain: g.terrain }))],
      seed: info.map.seed,
      palette: info.palette,
    };
    const layer = await terrainRef(name, input);
    maps[name] = { encounter: enc, opts, ...info, terrainInput: input, layer };
  }
  saveJson('battle_maps.json', maps);
}

// ---------------------------------------------------------------- garrison

if (want('base')) {
  await boot(1234);
  await page.waitForTimeout(1800);
  await page.screenshot({ path: join(refs, 'base_new_ui.png') });
  await worldShot('base_new.png');
  const base = await page.evaluate(() => {
    const s = (window as any).__meridius.store;
    const sc = s.baseScene;
    return { game: s.game, cam: { x: sc.cam.x, y: sc.cam.y, zoom: sc.cam.zoom }, props: sc.props, stakes: sc.stakes, walkers: sc.walkers, layer: { ox: sc.terrain.ox, oy: sc.terrain.oy, scale: sc.terrain.scale, w: sc.terrain.canvas.width, h: sc.terrain.canvas.height } };
  });
  savePng('terrain_base_layer.png', await page.evaluate(() => (window as any).__meridius.store.baseScene.terrain.canvas.toDataURL('image/png')));
  saveJson('base_new.json', base);
  // An upgraded garrison: every building one or two levels up.
  await page.evaluate(() => {
    const s = (window as any).__meridius.store;
    s.game.buildings = { barracks: 3, training: 2, armoury: 3, infirmary: 2, quartermaster: 3, command: 2 };
    s.commit();
  });
  await page.waitForTimeout(1500);
  await page.screenshot({ path: join(refs, 'base_upgraded_ui.png') });
  await worldShot('base_upgraded.png');
  const up = await page.evaluate(() => {
    const s = (window as any).__meridius.store;
    const sc = s.baseScene;
    return { game: s.game, cam: { x: sc.cam.x, y: sc.cam.y, zoom: sc.cam.zoom } };
  });
  saveJson('base_upgraded.json', up);
  // Dim mode (a panel open over the garrison).
  await page.evaluate(() => (window as any).__meridius.store.openPanel('barracks'));
  await page.waitForTimeout(600);
  await page.screenshot({ path: join(refs, 'base_dim_ui.png') });
  await worldShot('base_dim.png');
}

// ---------------------------------------------------------------- campaign map

if (want('campaign')) {
  await boot(1234);
  await page.evaluate(() => (window as any).__meridius.store.debug.autoPrepare(1));
  // The first look sweeps from the host back to the muster point (about 4.8 s).
  await page.waitForTimeout(800);
  await worldShot('campaign_intro.png');
  await page.waitForTimeout(5600);
  await page.screenshot({ path: join(refs, 'campaign_start_ui.png') });
  await worldShot('campaign_start.png');
  const camp = await page.evaluate(() => {
    const s = (window as any).__meridius.store;
    const sc = s.campaignScene;
    return {
      game: s.game,
      cam: { x: sc.cam.x, y: sc.cam.y, zoom: sc.cam.zoom },
      props: sc.props,
      roads: [...sc.roads.entries()],
      fog: sc.fog,
      token: sc.token,
      horde: sc.horde,
      layer: { ox: sc.terrain.ox, oy: sc.terrain.oy, scale: sc.terrain.scale, w: sc.terrain.canvas.width, h: sc.terrain.canvas.height, waterTiles: sc.terrain.waterTiles },
    };
  });
  savePng('terrain_campaign_layer.png', await page.evaluate(() => (window as any).__meridius.store.campaignScene.terrain.canvas.toDataURL('image/png')));
  saveJson('campaign_start.json', camp);
}

console.log('errors', errors.length, errors.slice(0, 3).join(' | '));
await browser.close();
