// Contact-sheet layouts shared by the browser (original drawSprite /
// drawCastShadow, tools/bake/page.ts) and Godot (tests/visual/capture_assets.gd):
// both draw the same items at the same places, so the images can be diffed.

const BG = '#a3ad78';

function flow(entries, maxW, pad = 14) {
  const items = [];
  let x = pad;
  let y = pad;
  let rowH = 0;
  let w = 0;
  for (const e of entries) {
    const sc = e.spr.scale * (e.scale ?? 1);
    const ew = Math.ceil(e.spr.w * sc);
    const eh = Math.ceil(e.spr.h * sc);
    if (x + ew > maxW && x > pad) {
      x = pad;
      y += rowH + pad;
      rowH = 0;
    }
    // Mirror about the anchor: keep the flipped sprite inside its slot.
    const ax = e.flip ? (e.spr.w - e.spr.ax) * sc : e.spr.ax * sc;
    items.push({ key: e.key, v: e.v, x: Math.round(x + ax), y: Math.round(y + e.spr.ay * sc), flip: !!e.flip, scale: e.scale ?? 1, shadow: e.shadow ?? 0 });
    x += ew + pad;
    w = Math.max(w, x);
    rowH = Math.max(rowH, eh);
  }
  return { items, w: Math.ceil(w), h: Math.ceil(y + rowH + pad) };
}

export function buildSheets(manifest, groups) {
  const sheets = [];
  const poses = [...new Set(groups.figures.map((k) => k.replace(/^.*?_(idle_fs|idle_bs|atk_fs|atk_bs|idle_f|idle_b|atk_f|atk_b|run_f|run_b|dead|flee_b)$/, '$1')))];
  const types = [...new Set(groups.figures.map((k) => k.slice(0, k.length - poses.find((p) => k.endsWith('_' + p)).length - 1)))];

  // Figures: one sheet per unit type, poses across, the six looks down.
  // Looks 3–5 are mirrored; cast shadows as the battle draws them (not for the dead).
  for (const t of types) {
    let half = 0;
    let up = 0;
    let down = 0;
    for (const p of poses) {
      for (const e of manifest[`${t}_${p}`]) {
        half = Math.max(half, e.ax * e.scale, (e.w - e.ax) * e.scale);
        up = Math.max(up, e.ay * e.scale);
        down = Math.max(down, (e.h - e.ay) * e.scale);
      }
    }
    const cw = Math.ceil(half * 2) + 6;
    const ch = Math.ceil(up + down) + 8;
    const items = [];
    poses.forEach((p, c) => {
      const list = manifest[`${t}_${p}`];
      for (let r = 0; r < list.length; r++) {
        items.push({ key: `${t}_${p}`, v: r, x: 16 + c * cw + Math.round(half), y: 16 + r * ch + Math.round(up), flip: r >= 3, scale: 1, shadow: p === 'dead' ? 0 : 0.16 });
      }
    });
    sheets.push({ name: `fig_${t}`, w: 32 + poses.length * cw, h: 32 + 6 * ch, bg: BG, items });
  }

  // Props, decals and the 'missing' sprite (procedural ones mirrored on odd variants).
  const propEntries = [];
  for (const k of [...groups.props, ...groups.literal, ...groups.decals, ...groups.missing]) {
    manifest[k].forEach((spr, v) => propEntries.push({ key: k, v, spr, flip: !spr.noShadow && v % 2 === 1, shadow: k.startsWith('tree') ? 0.2 : 0.16 }));
  }
  const props = flow(propEntries, 2200);
  sheets.push({ name: 'props', w: props.w, h: props.h, bg: BG, items: props.items });

  // Buildings and campaign node icons.
  const bEntries = [];
  for (const k of [...groups.buildings, ...groups.nodes]) manifest[k].forEach((spr, v) => bEntries.push({ key: k, v, spr, shadow: 0.2 }));
  const bld = flow(bEntries, 2400);
  sheets.push({ name: 'buildings_nodes', w: bld.w, h: bld.h, bg: BG, items: bld.items });

  // Portraits: each variant at its own 160 px and at the HUD's 56 px.
  const pItems = [];
  groups.portraits.forEach((k, i) => {
    const col = i % 2;
    const row = Math.floor(i / 2);
    const x0 = 16 + col * 760;
    const y0 = 16 + row * 176;
    manifest[k].forEach((spr, v) => {
      pItems.push({ key: k, v, x: x0 + v * 168, y: y0, box: 160 });
      pItems.push({ key: k, v, x: x0 + 3 * 168 + v * 64, y: y0 + 52, box: 56 });
    });
  });
  sheets.push({ name: 'portraits', w: 16 + 2 * 760, h: 16 + Math.ceil(groups.portraits.length / 2) * 176, bg: BG, items: pItems });

  // Drawing options: alpha, rotation, vertical squash, flash, silhouette,
  // additive flash (garrison hover), scales and cast shadows.
  const fx = [];
  const rows = [
    ['footman_idle_f', 0],
    ['troll_atk_b', 2],
    ['orc_warlord_atk_fs', 1],
    ['b_barracks_2', 0],
    ['tree_pine', 1],
    ['node_unknown', 0],
  ];
  const opts = [
    { scale: 1 },
    { scale: 1, flip: true, shadow: 0.22 },
    { scale: 1, alpha: 0.5 },
    { scale: 1, rot: 0.25 },
    { scale: 1, sy: 1.15 },
    { scale: 1, mode: 'flash', alpha: 0.8 },
    { scale: 1, mode: 'silhouette', alpha: 0.5 },
    { scale: 1, mode: 'lighter', alpha: 0.24 },
    { scale: 0.56, flip: true, shadow: 0.16 },
    { scale: 1.35 },
  ];
  let y = 16;
  let fw = 0;
  for (const [k, v] of rows) {
    const spr = manifest[k][v];
    let rowH = 0;
    let x = 16;
    for (const o of opts) {
      const sc = spr.scale * o.scale;
      const half = Math.max(spr.ax, spr.w - spr.ax) * sc;
      rowH = Math.max(rowH, spr.h * sc);
      fx.push({ key: k, v, x: Math.round(x + half), y: Math.round(y + spr.ay * sc), flip: !!o.flip, scale: o.scale, alpha: o.alpha, rot: o.rot, sy: o.sy, shadow: o.shadow ?? 0, mode: o.mode ?? 'normal' });
      x += Math.ceil(half * 2) + 12;
    }
    fw = Math.max(fw, x);
    y += Math.ceil(rowH * 1.16) + 16;
  }
  sheets.push({ name: 'fx', w: fw + 4, h: y, bg: BG, items: fx });
  return sheets;
}
