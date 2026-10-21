// Exports every UI icon of the original game (src/ui/common.tsx ICONS) to
// assets/icons/<name>.svg for the Godot port. The icons are rendered through the
// original React component with react-dom/server, so the SVG markup is exactly
// what the browser drew. Run from the TypeScript project:
//   cd projects/meridius/source/game && npx vite-node ../godot/tools/ui_export_icons.ts
//
// Icons drawn in `currentColor` (rotl, rotr, sound, mute, grid, danger) are
// written in white so Godot can tint them with `modulate` / `self_modulate`
// (the widget in scripts/ui/widgets/icon.gd does this). `missing.svg` is the
// grey disc the original shows for an unknown icon name.
// Each SVG gets an .import file (scale 4 = 96 px, mipmaps) so it stays crisp
// from 12 to 40 px; run tools/import.sh afterwards.

import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { Icon } from '../../game/src/ui/common';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '..', 'assets', 'icons');
mkdirSync(out, { recursive: true });

// ICONS is module-private; read its keys from the source.
const src = readFileSync(join(here, '..', '..', 'game', 'src', 'ui', 'common.tsx'), 'utf8');
const block = src.slice(src.indexOf('const ICONS'), src.indexOf('export function Icon('));
const names = [...block.matchAll(/^ {2}(\w+): \(/gm)].map((m) => m[1]);
if (names.length < 30) throw new Error(`only found ${names.length} icons`);

const IMPORT = (name: string) => `[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/icons/${name}.svg"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
svg/scale=4.0
editor/scale_with_editor_scale=false
editor/convert_colors_with_editor_theme=false
`;

function write(name: string, iconName: string) {
  let svg = renderToStaticMarkup(createElement(Icon, { name: iconName, size: 24 }));
  const tinted = svg.includes('currentColor');
  svg = svg
    .replace(/<svg [^>]*>/, '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">')
    .replaceAll('currentColor', '#ffffff');
  writeFileSync(join(out, `${name}.svg`), svg + '\n');
  const imp = join(out, `${name}.svg.import`);
  // Keep an existing import file (it holds the uid); only create missing ones.
  if (!existsSync(imp)) writeFileSync(imp, IMPORT(name));
  return tinted;
}

const tinted: string[] = [];
for (const n of names) if (write(n, n)) tinted.push(n);
write('missing', '__missing__');
console.log(`exported ${names.length} icons (+ missing) to ${out}`);
console.log(`tintable (white): ${tinted.join(', ')}`);
