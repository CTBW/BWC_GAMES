// WebP copies of Workspace card media for the public repository ("Where things
// live" in AGENTS.md). Full-size PNG originals stay in the ignored
// local/workspace-originals/ folder, in the card's own folder layout. Cards link
// the WebP copy: long side at most 2048 px, quality 85, no metadata.
import { execFileSync } from 'node:child_process';
import { existsSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../../../', import.meta.url));
export const workspaceOriginals = path.join(root, 'local/workspace-originals');
export const webpName = file => file.replace(/\.png$/i, '.webp');

const encoder = `
import json, sys
from PIL import Image
job = json.load(sys.stdin)
for source, destination in job["pairs"]:
    with Image.open(source) as image:
        image.load()
        image = image.convert("RGBA" if image.mode in ("RGBA", "LA", "PA", "P") else "RGB")
        if image.mode == "RGBA" and image.getchannel("A").getextrema() == (255, 255):
            image = image.convert("RGB")
        if max(image.size) > job["maxSide"]:
            image.thumbnail((job["maxSide"], job["maxSide"]), Image.Resampling.LANCZOS)
        image.info = {}
        image.save(destination, "WEBP", quality=job["quality"], method=6)
`;

// Writes each missing or outdated WebP copy from its PNG. A pair whose PNG is not
// on this machine (a fresh clone) keeps its committed copy.
export function webpCopies(pairs, { maxSide = 2048, quality = 85 } = {}) {
  const pending = pairs.filter(([source, destination]) => existsSync(source)
    && (!existsSync(destination) || statSync(destination).mtimeMs < statSync(source).mtimeMs));
  if (pending.length) execFileSync(process.env.PYTHON || 'python', ['-c', encoder], {
    input: JSON.stringify({ pairs: pending, maxSide, quality }), stdio: ['pipe', 'inherit', 'inherit'],
  });
  return pending.length;
}

// Width and height of a PNG or WebP file.
export function imageSize(bytes) {
  if (bytes.subarray(1, 4).toString() === 'PNG') return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
  if (bytes.subarray(0, 4).toString() !== 'RIFF' || bytes.subarray(8, 12).toString() !== 'WEBP') throw new Error('Expected a PNG or WebP image');
  const chunk = bytes.subarray(12, 16).toString();
  if (chunk === 'VP8X') return { width: 1 + bytes.readUIntLE(24, 3), height: 1 + bytes.readUIntLE(27, 3) };
  if (chunk === 'VP8L') { const bits = bytes.readUInt32LE(21); return { width: 1 + (bits & 0x3fff), height: 1 + ((bits >> 14) & 0x3fff) }; }
  if (chunk === 'VP8 ') return { width: bytes.readUInt16LE(26) & 0x3fff, height: bytes.readUInt16LE(28) & 0x3fff };
  throw new Error(`Unexpected WebP chunk ${chunk}`);
}
