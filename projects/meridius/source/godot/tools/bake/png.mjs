// Minimal PNG writer/reader (8-bit RGBA / RGB / grey, non-interlaced) on
// node's zlib, so the bake writes the browser's straight-alpha pixels exactly.

import zlib from 'node:zlib';

const CRC = new Int32Array(256);
for (let n = 0; n < 256; n++) {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  CRC[n] = c;
}

function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC[(c ^ buf[i]) & 255] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'latin1'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}

/** Encode straight-alpha RGBA (Uint8Array, w*h*4) as PNG. Adaptive row filters. */
export function encodePNG(w, h, rgba) {
  const bpp = 4;
  const stride = w * bpp;
  const raw = Buffer.alloc((stride + 1) * h);
  const cand = [0, 1, 2, 3, 4].map(() => Buffer.alloc(stride));
  for (let y = 0; y < h; y++) {
    const row = rgba.subarray(y * stride, (y + 1) * stride);
    const up = y > 0 ? rgba.subarray((y - 1) * stride, y * stride) : null;
    let best = 0;
    let bestSum = Infinity;
    for (let f = 0; f < 5; f++) {
      const o = cand[f];
      let sum = 0;
      for (let i = 0; i < stride; i++) {
        const a = i >= bpp ? row[i - bpp] : 0;
        const b = up ? up[i] : 0;
        const c = up && i >= bpp ? up[i - bpp] : 0;
        const x = row[i];
        const v = f === 0 ? x : f === 1 ? x - a : f === 2 ? x - b : f === 3 ? x - ((a + b) >> 1) : x - paeth(a, b, c);
        o[i] = v & 255;
        sum += o[i] < 128 ? o[i] : 256 - o[i];
      }
      if (sum < bestSum) {
        bestSum = sum;
        best = f;
      }
    }
    raw[y * (stride + 1)] = best;
    cand[best].copy(raw, y * (stride + 1) + 1);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

/** Decode an 8-bit non-interlaced PNG (grey, grey+alpha, RGB, RGBA) to RGBA. */
export function decodePNG(buf) {
  let p = 8;
  let w = 0;
  let h = 0;
  let ct = 0;
  const idat = [];
  while (p < buf.length) {
    const len = buf.readUInt32BE(p);
    const type = buf.toString('latin1', p + 4, p + 8);
    const data = buf.subarray(p + 8, p + 8 + len);
    if (type === 'IHDR') {
      w = data.readUInt32BE(0);
      h = data.readUInt32BE(4);
      if (data[8] !== 8 || data[12] !== 0) throw new Error('unsupported PNG (bit depth / interlace)');
      ct = data[9];
    } else if (type === 'IDAT') idat.push(data);
    else if (type === 'IEND') break;
    p += 12 + len;
  }
  const bpp = { 0: 1, 2: 3, 4: 2, 6: 4 }[ct];
  if (!bpp) throw new Error(`unsupported PNG colour type ${ct}`);
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = w * bpp;
  const px = Buffer.alloc(stride * h);
  for (let y = 0; y < h; y++) {
    const f = raw[y * (stride + 1)];
    const src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const row = px.subarray(y * stride, (y + 1) * stride);
    const up = y > 0 ? px.subarray((y - 1) * stride, y * stride) : null;
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? row[i - bpp] : 0;
      const b = up ? up[i] : 0;
      const c = up && i >= bpp ? up[i - bpp] : 0;
      const x = src[i];
      row[i] = (f === 0 ? x : f === 1 ? x + a : f === 2 ? x + b : f === 3 ? x + ((a + b) >> 1) : x + paeth(a, b, c)) & 255;
    }
  }
  const out = Buffer.alloc(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    if (bpp === 4) px.copy(out, i * 4, i * 4, i * 4 + 4);
    else if (bpp === 3) {
      out[i * 4] = px[i * 3];
      out[i * 4 + 1] = px[i * 3 + 1];
      out[i * 4 + 2] = px[i * 3 + 2];
      out[i * 4 + 3] = 255;
    } else if (bpp === 2) {
      out[i * 4] = out[i * 4 + 1] = out[i * 4 + 2] = px[i * 2];
      out[i * 4 + 3] = px[i * 2 + 1];
    } else {
      out[i * 4] = out[i * 4 + 1] = out[i * 4 + 2] = px[i];
      out[i * 4 + 3] = 255;
    }
  }
  return { w, h, rgba: out };
}
