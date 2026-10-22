// Bakes the original game's sprites and sounds for the Godot port.
//
//   node tools/bake/bake.mjs            # everything: sprites, audio, sheets
//   node tools/bake/bake.mjs sprites    # only the sprite registry
//   node tools/bake/bake.mjs audio      # only the sound effects
//   node tools/bake/bake.mjs sheets     # only the browser contact sheets
//   node tools/bake/bake.mjs imports    # only pin the .import parameters
//
// Runs the ORIGINAL code (../game/src, unmodified) in Microsoft Edge through
// playwright-core, served by the original's vite toolchain from tools/bake
// (port 5181). See tools/bake/README.md.

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { encodePNG } from './png.mjs';
import { buildSheets } from './sheets.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const GODOT = path.resolve(HERE, '../..');
const GAME = path.resolve(GODOT, '../game');
const PORT = Number(process.env.BAKE_PORT ?? 5181);
const EDGE = process.env.CHROME_PATH ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const OUT_SPRITES = path.join(GODOT, 'assets/sprites');
const OUT_AUDIO = path.join(GODOT, 'assets/audio');
const FIXTURES = path.join(GODOT, 'tests/fixtures/assets');
const VISUAL_OUT = path.join(GODOT, 'tests/visual/out');

const steps = process.argv.slice(2);
const want = (s) => steps.length === 0 || steps.includes(s) || steps.includes('all');

const { createServer } = await import(pathToFileURL(path.join(GAME, 'node_modules/vite/dist/node/index.js')).href);
const { chromium } = await import(pathToFileURL(path.join(GAME, 'node_modules/playwright-core/index.mjs')).href);

const read = (rel) => fs.readFileSync(path.join(GAME, rel), 'utf8');
const toRes = (abs) => 'res://' + path.relative(GODOT, abs).split(path.sep).join('/');

/** Write a file only when its bytes change (keeps Godot from re-importing). */
function writeIfChanged(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const buf = Buffer.isBuffer(data) ? data : Buffer.from(data);
  if (fs.existsSync(file) && fs.readFileSync(file).equals(buf)) return false;
  fs.writeFileSync(file, buf);
  return true;
}

// ---------------------------------------------------------------- key enumeration

/**
 * Every sprite key the original can request at runtime, from its sources:
 * the figure / portrait regexes of procedural.ts, the Pose type of figures.ts,
 * literal keys in the scenes and UI, and the data tables (props, buildings,
 * campaign node types) read in the page.
 */
function enumerateKeys(data) {
  const proc = read('src/render/procedural.ts');
  const um = proc.match(/const um = key\.match\(\/\^\(([^)]+)\)_\(([^)]+)\)\$\//);
  const pm = proc.match(/const pm = key\.match\(\/\^portrait_\(([^)]+)\)\$\//);
  if (!um || !pm) throw new Error('procedural.ts: figure/portrait key patterns not found');
  const figTypes = um[1].split('|');
  const regexPoses = um[2].split('|');
  const poseType = read('src/render/figures.ts').match(/export type Pose = ([^;]+);/);
  const poses = [...poseType[1].matchAll(/'(\w+)'/g)].map((m) => m[1]);
  if (poses.length !== regexPoses.length || !poses.every((p) => regexPoses.includes(p))) throw new Error('Pose type and procedural regex disagree');
  // War engines (engines.ts): their own key and portrait patterns, the same poses.
  const em = proc.match(/const em = key\.match\(\/\^\(([^)]+)\)_\(([^)]+)\)\$\//);
  const pe = proc.match(/const pe = key\.match\(\/\^portrait_\(([^)]+)\)\$\//);
  if (!em !== !pe) throw new Error('procedural.ts: engine key and engine portrait patterns must come together');
  const engineTypes = em ? em[1].split('|') : [];
  if (em) {
    const enginePoses = em[2].split('|');
    if (enginePoses.length !== poses.length || !poses.every((p) => enginePoses.includes(p))) throw new Error('Pose type and engine regex disagree');
  }
  const portraitTypes = [...pm[1].split('|'), ...(pe ? pe[1].split('|') : [])];
  for (const s of data.unitSprites) if (!figTypes.includes(s) && !engineTypes.includes(s)) throw new Error(`unit sprite ${s} has no figure or engine art`);

  const groups = {
    figures: figTypes.flatMap((t) => poses.map((p) => `${t}_${p}`)),
    engines: engineTypes.flatMap((t) => poses.map((p) => `${t}_${p}`)),
    portraits: portraitTypes.map((t) => `portrait_${t}`),
    props: [],
    buildings: data.buildings.flatMap((b) => Array.from({ length: b.levels }, (_, i) => `b_${b.id}_${i + 1}`)),
    nodes: [...data.nodes.map((n) => `node_${n}`)],
    decals: [],
    literal: [],
    missing: ['missing'],
  };
  // Campaign nodes not yet revealed are drawn as 'unknown' (expedition.ts nodeView).
  if (!read('src/campaign/expedition.ts').includes("type: 'unknown'")) throw new Error('nodeView no longer returns unknown');
  groups.nodes.push('node_unknown');
  // Props: battle maps go through PROPS[id].sprite; the garrison and campaign
  // scenes name prop ids directly (trees, bushes, rocks, decor).
  const scenes = ['src/render/baseScene.ts', 'src/render/campaignScene.ts'].map(read).join('\n');
  const props = new Set(data.props);
  for (const id of data.propIds) if (scenes.includes(`'${id}'`)) props.add(id);
  groups.props = [...props];
  // Ground decals of the terrain painter.
  const terrain = read('src/render/terrain.ts');
  for (const d of ['tuft', 'flower', 'pebble']) if (terrain.includes(`'${d}'`)) groups.decals.push(d);
  // Literal keys in the scenes and UI: sprite('war_banner'), hasArt('gate_tower')…
  const files = [
    ...fs.readdirSync(path.join(GAME, 'src/render')).map((f) => `src/render/${f}`),
    ...fs.readdirSync(path.join(GAME, 'src/ui')).filter((f) => f.endsWith('.tsx')).map((f) => `src/ui/${f}`),
    ...fs.readdirSync(path.join(GAME, 'src/ui/screens')).map((f) => `src/ui/screens/${f}`),
  ];
  const lit = new Set();
  for (const f of files) {
    if (f.endsWith('assets.ts') || f.endsWith('procedural.ts')) continue;
    for (const m of read(f).matchAll(/\b(?:sprite|hasArt|variantCount)\('([a-z0-9_]+)'/g)) lit.add(m[1]);
  }
  groups.literal = [...lit].filter((k) => !Object.values(groups).some((g) => g.includes(k)));
  const all = [];
  for (const g of Object.values(groups)) for (const k of g) if (!all.includes(k)) all.push(k);
  return { groups, all, figTypes, engineTypes, poses, portraitTypes };
}

// ---------------------------------------------------------------- atlas packing

/** Shelf-pack rects (sorted tallest first) into pages of `pageW` × ≤ `maxH`. */
function pack(items, pageW = 2048, maxH = 4096, pad = 6, align = 4) {
  const order = items.map((it, i) => i).sort((a, b) => items[b].h - items[a].h || items[b].w - items[a].w);
  const pages = [];
  let page = null;
  let x = 0;
  let y = 0;
  let rowH = 0;
  const up = (n) => Math.ceil(n / align) * align;
  for (const i of order) {
    const it = items[i];
    const cw = up(it.w + 2 * pad);
    const ch = up(it.h + 2 * pad);
    if (cw > pageW) throw new Error(`sprite ${it.key} wider than an atlas page`);
    if (!page || x + cw > pageW) {
      y += rowH;
      x = 0;
      rowH = 0;
    }
    if (!page || y + ch > maxH) {
      page = { w: pageW, h: 0, items: [] };
      pages.push(page);
      x = 0;
      y = 0;
      rowH = 0;
    }
    it.page = pages.length - 1;
    it.x = x + pad;
    it.y = y + pad;
    page.items.push(it);
    page.h = Math.max(page.h, y + ch);
    x += cw;
    rowH = Math.max(rowH, ch);
  }
  // Narrow a lone short page to what it uses.
  for (const p of pages) {
    if (pages.length === 1) p.w = Math.min(pageW, up(Math.max(...p.items.map((it) => it.x + it.w + pad))));
  }
  return pages;
}

function blit(dst, dw, src, sw, sh, dx, dy) {
  for (let r = 0; r < sh; r++) src.copy(dst, ((dy + r) * dw + dx) * 4, r * sw * 4, (r + 1) * sw * 4);
}

// ---------------------------------------------------------------- import settings

const TEXTURE_PARAMS = {
  'compress/mode': '0', // lossless
  'mipmaps/generate': 'true', // zoomed-out views stay smooth (the original draws sprites with high-quality smoothing)
  'process/fix_alpha_border': 'true', // straight alpha: no dark fringes when filtering
  'process/premult_alpha': 'false',
  'detect_3d/compress_to': '0', // never switch to VRAM compression
};
const WAV_PARAMS = { 'compress/mode': '0', 'edit/trim': 'false', 'edit/normalize': 'false', 'edit/loop_mode': '0' };

/**
 * Pin the import parameters of every sprite and sound file. An existing
 * .import file keeps its uid and other parameters; a missing one is created
 * with the importer and these parameters (Godot fills in the rest).
 */
function ensureImports() {
  const files = [];
  const walk = (d) => {
    if (!fs.existsSync(d)) return;
    for (const f of fs.readdirSync(d, { withFileTypes: true })) {
      if (f.isDirectory()) walk(path.join(d, f.name));
      else if (/\.(png|webp|wav)$/.test(f.name)) files.push(path.join(d, f.name));
    }
  };
  walk(OUT_SPRITES);
  walk(OUT_AUDIO);
  let changed = 0;
  for (const f of files) {
    const wavFile = f.endsWith('.wav');
    const params = wavFile ? WAV_PARAMS : TEXTURE_PARAMS;
    const imp = f + '.import';
    let text = fs.existsSync(imp)
      ? fs.readFileSync(imp, 'utf8')
      : wavFile
        ? '[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\n\n[params]\n'
        : '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n';
    const before = text;
    for (const [k, v] of Object.entries(params)) {
      const re = new RegExp(`^${k.replace(/[/]/g, '\/')}=.*$`, 'm');
      text = re.test(text) ? text.replace(re, `${k}=${v}`) : text.replace(/\[params\]\n/, `[params]\n\n${k}=${v}\n`);
    }
    if (text !== before) {
      fs.writeFileSync(imp, text);
      changed++;
    }
  }
  console.log(`imports: ${files.length} files, ${changed} .import files updated (run tools/import.sh)`);
}

// ---------------------------------------------------------------- server + browser

async function withPage(fn) {
  const server = await createServer({
    configFile: false,
    root: HERE,
    publicDir: path.join(GAME, 'public'),
    logLevel: 'warn',
    clearScreen: false,
    optimizeDeps: { noDiscovery: true, include: [] },
    server: { port: PORT, strictPort: true, fs: { strict: true, allow: [path.resolve(GODOT, '..')] } },
  });
  await server.listen();
  const browser = await chromium.launch({ executablePath: EDGE, headless: true });
  const errors = [];
  try {
    const page = await browser.newPage();
    page.on('pageerror', (e) => errors.push(e.message));
    page.on('console', (m) => {
      if (m.type() === 'error') errors.push(m.text());
    });
    await page.goto(`http://localhost:${PORT}/index.html`);
    await page.waitForFunction(() => window.__bake, null, { timeout: 120000 });
    await page.evaluate(() => window.__bake.ready);
    await fn(page);
  } finally {
    await browser.close();
    await server.close();
  }
  if (errors.length) {
    console.error('page errors:\n  ' + errors.join('\n  '));
    process.exitCode = 1;
  }
}

// ---------------------------------------------------------------- sprites

async function bakeSprites(page) {
  const data = await page.evaluate(() => window.__bake.dataKeys());
  const keys = enumerateKeys(data);
  console.log(`keys: ${keys.all.length} (${Object.entries(keys.groups).map(([g, l]) => `${g} ${l.length}`).join(', ')})`);

  const results = [];
  for (let i = 0; i < keys.all.length; i += 24) {
    const batch = keys.all.slice(i, i + 24);
    results.push(...(await page.evaluate((b) => window.__bake.collect(b), batch)));
    process.stdout.write(`\r  collected ${Math.min(i + 24, keys.all.length)}/${keys.all.length}`);
  }
  process.stdout.write('\n');

  // Group procedural sprites into atlases: one per figure type, one per war
  // engine, portraits, misc.
  const figType = (key) => keys.figTypes.find((t) => keys.poses.some((p) => key === `${t}_${p}`));
  const engineType = (key) => keys.engineTypes.find((t) => keys.poses.some((p) => key === `${t}_${p}`));
  const atlases = new Map();
  // Engines alias poses (run_f and the shield poses draw idle_f, flee_b idle_b…):
  // identical canvases in an engine atlas share one region.
  const shared = new Map();
  const manifest = {};
  const copied = new Set();
  let artFiles = 0;
  for (const r of results) {
    manifest[r.key] = [];
    for (const e of r.entries) {
      const out = { ax: e.ax, ay: e.ay, scale: e.scale, w: e.w, h: e.h, noShadow: e.noShadow };
      if (e.art) {
        if (e.sx || e.sy) throw new Error(`${r.key}: manifest art with an offset`);
        const src = path.join(GAME, 'public/assets', e.file);
        const dst = path.join(OUT_SPRITES, 'blender', path.basename(e.file));
        if (!copied.has(dst)) {
          writeIfChanged(dst, fs.readFileSync(src));
          copied.add(dst);
          artFiles++;
        }
        manifest[r.key].push({ file: toRes(dst), ...out, art: true });
      } else {
        const t = figType(r.key);
        const et = t ? undefined : engineType(r.key);
        const group = t ? `fig_${t}` : et ? `engine_${et}` : r.key.startsWith('portrait_') ? 'portraits' : 'misc';
        if (!atlases.has(group)) atlases.set(group, []);
        const rgba = zlib.inflateSync(Buffer.from(e.rgba, 'base64'));
        if (rgba.length !== e.w * e.h * 4) throw new Error(`${r.key}: pixel data size`);
        const item = { key: r.key, v: e.v, w: e.w, h: e.h, rgba, out };
        if (et) {
          const id = `${group}:${e.w}x${e.h}:${crypto.createHash('sha1').update(rgba).digest('hex')}`;
          const same = shared.get(id);
          if (same) {
            // Same pixels: reuse the packed region, keep this key's own anchor and scale.
            manifest[r.key].push({ ref: same, out });
            continue;
          }
          shared.set(id, item);
        }
        atlases.get(group).push(item);
        manifest[r.key].push(item); // replaced below once packed
      }
    }
  }
  let atlasFiles = 0;
  let atlasBytes = 0;
  let atlasPixels = 0;
  const written = new Set();
  for (const [group, items] of atlases) {
    const pages = pack(items, group === 'misc' ? 1024 : 2048);
    pages.forEach((p, pi) => {
      const buf = Buffer.alloc(p.w * p.h * 4);
      for (const it of p.items) blit(buf, p.w, it.rgba, it.w, it.h, it.x, it.y);
      const file = path.join(OUT_SPRITES, 'baked', `${group}${pages.length > 1 ? `_${pi}` : ''}.png`);
      const png = encodePNG(p.w, p.h, buf);
      writeIfChanged(file, png);
      written.add(path.basename(file));
      atlasFiles++;
      atlasBytes += png.length;
      atlasPixels += p.w * p.h;
      for (const it of p.items) it.file = toRes(file);
    });
  }
  // Remove atlases and art files of an earlier bake that are no longer used.
  const keep = new Set([...written, ...[...copied].map((f) => path.basename(f))]);
  for (const dir of ['baked', 'blender'].map((d) => path.join(OUT_SPRITES, d))) {
    if (!fs.existsSync(dir)) continue;
    for (const f of fs.readdirSync(dir)) {
      if (/\.(png|webp)$/.test(f) && !keep.has(f)) {
        fs.rmSync(path.join(dir, f));
        fs.rmSync(path.join(dir, f + '.import'), { force: true });
      }
    }
  }
  for (const key of Object.keys(manifest)) {
    manifest[key] = manifest[key].map((it) => {
      const p = it.ref ?? it;
      return p.rgba ? { file: p.file, region: [p.x, p.y, p.w, p.h], ...it.out } : it;
    });
  }
  writeIfChanged(path.join(GODOT, 'assets/sprites.json'), JSON.stringify(manifest, null, 1) + '\n');

  // The original's variant counts and hasArt, and the key groups, for the tests.
  const counts = Object.fromEntries(results.map((r) => [r.key, r.count]));
  const hasArt = results.filter((r) => r.hasArt).map((r) => r.key);
  writeIfChanged(path.join(FIXTURES, 'variant_counts.json'), JSON.stringify({ counts, hasArt, groups: keys.groups }, null, 1) + '\n');
  // The original's hit masks (opaqueAt) for a few sprites, for the picking test.
  const hits = [];
  for (const [key, v] of [['footman_idle_f', 0], ['troll_atk_b', 2], ['goblin_rabble_dead', 4], ['b_barracks_2', 0], ['tree_pine', 1], ['node_village', 0], ['portrait_orc_warlord', 1], ['battle_mage_atk_f', 2], ['mangonel_idle_b', 1], ['war_wagon_dead', 2]]) {
    hits.push({ key, v, step: 5, ...(await page.evaluate(([k, vv]) => window.__bake.hitGrid(k, vv, 5), [key, v])) });
  }
  writeIfChanged(path.join(FIXTURES, 'hit_masks.json'), JSON.stringify(hits) + '\n');
  const blenderBytes = [...copied].reduce((n, f) => n + fs.statSync(f).size, 0);
  console.log(`sprites: ${results.length} keys, ${results.reduce((n, r) => n + r.count, 0)} variants; ${artFiles} Blender files (${(blenderBytes / 1e6).toFixed(1)} MB), ${atlasFiles} atlases (${(atlasBytes / 1e6).toFixed(1)} MB PNG, ${(atlasPixels / 1e6).toFixed(1)} Mpx)`);
}

// ---------------------------------------------------------------- audio

function wav(sampleRate, pcm) {
  const h = Buffer.alloc(44);
  h.write('RIFF', 0, 'latin1');
  h.writeUInt32LE(36 + pcm.length, 4);
  h.write('WAVE', 8, 'latin1');
  h.write('fmt ', 12, 'latin1');
  h.writeUInt32LE(16, 16);
  h.writeUInt16LE(1, 20); // PCM
  h.writeUInt16LE(1, 22); // mono
  h.writeUInt32LE(sampleRate, 24);
  h.writeUInt32LE(sampleRate * 2, 28);
  h.writeUInt16LE(2, 32);
  h.writeUInt16LE(16, 34);
  h.write('data', 36, 'latin1');
  h.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([h, pcm]);
}

/** True when `file` holds the same 16-bit WAV as `data` up to ±1 in any sample. */
function sameWithinLsb(file, data) {
  if (!fs.existsSync(file)) return false;
  const old = fs.readFileSync(file);
  if (old.length !== data.length || !old.subarray(0, 44).equals(data.subarray(0, 44))) return false;
  for (let i = 44; i + 1 < data.length; i += 2) if (Math.abs(old.readInt16LE(i) - data.readInt16LE(i)) > 1) return false;
  return true;
}

async function bakeAudio(page) {
  const src = read('src/audio/sfx.ts');
  const names = [...src.matchAll(/case '(\w+)':/g)].map((m) => m[1]);
  const volume = Number(src.match(/let volume = ([\d.]+);/)[1]);
  const gap = src.match(/const minGap = name === '(\w+)' \? (\d+) : (\d+);/);
  const gameFs = '/@fs/' + GAME.split(path.sep).join('/');
  const VARIANTS = 4;
  const sounds = {};
  const report = [];
  const written = new Set();
  for (const name of names) {
    sounds[name] = [];
    let n = 1;
    for (let i = 0; i < n; i++) {
      // Math.random is seeded per take, so a re-bake writes the same files.
      const seed = [...name].reduce((h, ch) => (Math.imul(h, 31) + ch.charCodeAt(0)) | 0, 7) + i * 7919;
      const r = await page.evaluate(([g, nm, sd]) => window.__bake.renderSfx(g, nm, sd), [gameFs, name, seed]);
      if (i === 0 && r.randomCalls > 0) n = VARIANTS;
      const file = path.join(OUT_AUDIO, `${name}_${i}.wav`);
      const data = wav(r.sampleRate, Buffer.from(r.pcm, 'base64'));
      // The browser's offline rendering jitters by a least significant bit in a
      // few samples between runs; keep the existing take then.
      if (!sameWithinLsb(file, data)) writeIfChanged(file, data);
      written.add(path.basename(file));
      sounds[name].push(toRes(file));
      if (i === 0) report.push(`${name}: ${n} variant(s), ${(r.samples / r.sampleRate).toFixed(2)} s, peak ${r.peak.toFixed(3)}${r.clipped ? `, CLIPPED ${r.clipped}` : ''}`);
    }
  }
  for (const f of fs.readdirSync(OUT_AUDIO)) {
    if (f.endsWith('.wav') && !written.has(f)) {
      fs.rmSync(path.join(OUT_AUDIO, f));
      fs.rmSync(path.join(OUT_AUDIO, f + '.import'), { force: true });
    }
  }
  const meta = {
    // The original's master gain is rendered into the samples (sfx.ts `volume`).
    master: volume,
    masterBaked: true,
    minGapMs: { [gap[1]]: Number(gap[2]) },
    defaultGapMs: Number(gap[3]),
    sounds,
  };
  writeIfChanged(path.join(OUT_AUDIO, 'sfx.json'), JSON.stringify(meta, null, 1) + '\n');
  // The original's sound names (sfx.ts switch cases) and gaps, for the tests.
  const fixture = { names, master: volume, minGapMs: meta.minGapMs, defaultGapMs: meta.defaultGapMs, takes: Object.fromEntries(names.map((n) => [n, sounds[n].length])) };
  writeIfChanged(path.join(FIXTURES, 'sfx_names.json'), JSON.stringify(fixture, null, 1) + '\n');
  console.log(`audio: ${names.length} sounds, ${written.size} files\n  ` + report.join('\n  '));
}

// ---------------------------------------------------------------- browser contact sheets

async function bakeSheets(page) {
  const manifest = JSON.parse(fs.readFileSync(path.join(GODOT, 'assets/sprites.json'), 'utf8'));
  const fixture = JSON.parse(fs.readFileSync(path.join(FIXTURES, 'variant_counts.json'), 'utf8'));
  const sheets = buildSheets(manifest, fixture.groups);
  writeIfChanged(path.join(FIXTURES, 'sheets.json'), JSON.stringify(sheets) + '\n');
  fs.mkdirSync(VISUAL_OUT, { recursive: true });
  for (const s of sheets) {
    const url = await page.evaluate((spec) => window.__bake.sheet(spec), s);
    fs.writeFileSync(path.join(VISUAL_OUT, `assets_${s.name}_browser.png`), Buffer.from(url.slice(url.indexOf(',') + 1), 'base64'));
  }
  console.log(`sheets: ${sheets.length} browser sheets in ${path.relative(GODOT, VISUAL_OUT)}`);
}

if (want('sprites') || want('audio') || want('sheets')) {
  await withPage(async (page) => {
    if (want('sprites')) await bakeSprites(page);
    if (want('audio')) await bakeAudio(page);
    if (want('sheets')) await bakeSheets(page);
  });
}
if (want('sprites') || want('audio') || want('imports')) ensureImports();
