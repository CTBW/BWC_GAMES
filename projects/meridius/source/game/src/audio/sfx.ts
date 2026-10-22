// Synthesised sound effects (Web Audio). Each name maps to a short recipe;
// recorded or generated samples can replace a recipe by name later.

import { prefs, setPref } from '../core/prefs';

let ctx: AudioContext | null = null;
let master: GainNode | null = null;
let muted = prefs().muted;
let volume = 0.55;
const lastPlayed = new Map<string, number>();

function ac(): AudioContext | null {
  if (typeof window === 'undefined') return null;
  if (!ctx) {
    try {
      ctx = new AudioContext();
      master = ctx.createGain();
      master.gain.value = muted ? 0 : volume;
      master.connect(ctx.destination);
    } catch {
      return null;
    }
  }
  if (ctx.state === 'suspended') void ctx.resume();
  return ctx;
}

export function setMuted(m: boolean) {
  muted = m;
  setPref('muted', m);
  if (master) master.gain.value = m ? 0 : volume;
}

export function isMuted() {
  return muted;
}

function noise(c: AudioContext, dur: number) {
  const buf = c.createBuffer(1, Math.ceil(c.sampleRate * dur), c.sampleRate);
  const d = buf.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  const src = c.createBufferSource();
  src.buffer = buf;
  return src;
}

function env(c: AudioContext, g: GainNode, a: number, peak: number, dcy: number, t0 = c.currentTime) {
  g.gain.setValueAtTime(0.0001, t0);
  g.gain.exponentialRampToValueAtTime(peak, t0 + a);
  g.gain.exponentialRampToValueAtTime(0.0001, t0 + a + dcy);
}

function burst(c: AudioContext, opts: { dur: number; type: BiquadFilterType; freq: number; q?: number; gain: number; attack?: number; sweep?: number; delay?: number }) {
  const t0 = c.currentTime + (opts.delay ?? 0);
  const src = noise(c, opts.dur + 0.05);
  const f = c.createBiquadFilter();
  f.type = opts.type;
  f.frequency.setValueAtTime(opts.freq, t0);
  if (opts.sweep) f.frequency.exponentialRampToValueAtTime(opts.sweep, t0 + opts.dur);
  f.Q.value = opts.q ?? 1;
  const g = c.createGain();
  env(c, g, opts.attack ?? 0.005, opts.gain, opts.dur, t0);
  src.connect(f).connect(g).connect(master!);
  src.start(t0);
  src.stop(t0 + opts.dur + 0.05);
}

function tone(c: AudioContext, opts: { freq: number; dur: number; type?: OscillatorType; gain: number; attack?: number; slide?: number; delay?: number }) {
  const t0 = c.currentTime + (opts.delay ?? 0);
  const o = c.createOscillator();
  o.type = opts.type ?? 'sine';
  o.frequency.setValueAtTime(opts.freq, t0);
  if (opts.slide) o.frequency.exponentialRampToValueAtTime(opts.slide, t0 + opts.dur);
  const g = c.createGain();
  env(c, g, opts.attack ?? 0.01, opts.gain, opts.dur, t0);
  o.connect(g).connect(master!);
  o.start(t0);
  o.stop(t0 + opts.dur + (opts.attack ?? 0.01) + 0.05);
}

export function sfx(name: string) {
  if (muted) return;
  const c = ac();
  if (!c || !master) return;
  const now = performance.now();
  const minGap = name === 'step' ? 70 : 25;
  if (now - (lastPlayed.get(name) ?? 0) < minGap) return;
  lastPlayed.set(name, now);
  const r = () => 0.9 + Math.random() * 0.2;
  switch (name) {
    case 'step':
      burst(c, { dur: 0.07, type: 'lowpass', freq: 500 * r(), gain: 0.12 });
      break;
    case 'swing':
      burst(c, { dur: 0.22, type: 'bandpass', freq: 900, sweep: 2600, q: 2, gain: 0.18, attack: 0.04 });
      break;
    case 'hit_metal':
      tone(c, { freq: 1900 * r(), dur: 0.25, type: 'triangle', gain: 0.12, attack: 0.002, slide: 1500, delay: 0 });
      tone(c, { freq: 2830 * r(), dur: 0.18, type: 'sine', gain: 0.07, attack: 0.002 });
      burst(c, { dur: 0.08, type: 'highpass', freq: 2000, gain: 0.25 });
      break;
    case 'hit_flesh':
      burst(c, { dur: 0.14, type: 'lowpass', freq: 700, gain: 0.45 });
      tone(c, { freq: 140, dur: 0.12, type: 'sine', gain: 0.25, slide: 70 });
      break;
    case 'block':
      tone(c, { freq: 420 * r(), dur: 0.18, type: 'square', gain: 0.05, attack: 0.002, slide: 300 });
      burst(c, { dur: 0.1, type: 'bandpass', freq: 1200, gain: 0.3 });
      break;
    case 'miss':
      burst(c, { dur: 0.25, type: 'bandpass', freq: 1400, sweep: 500, q: 1.5, gain: 0.12, attack: 0.03 });
      break;
    case 'crossbow':
      tone(c, { freq: 220, dur: 0.12, type: 'sawtooth', gain: 0.08, slide: 110 });
      burst(c, { dur: 0.09, type: 'highpass', freq: 1500, gain: 0.35 });
      break;
    case 'bow':
      tone(c, { freq: 320, dur: 0.15, type: 'triangle', gain: 0.07, slide: 180 });
      burst(c, { dur: 0.2, type: 'bandpass', freq: 2200, sweep: 900, gain: 0.08, attack: 0.02 });
      break;
    case 'bolt_hit':
      burst(c, { dur: 0.1, type: 'lowpass', freq: 900, gain: 0.45 });
      tone(c, { freq: 200, dur: 0.08, gain: 0.2, slide: 90 });
      break;
    case 'death':
      tone(c, { freq: 320, dur: 0.35, type: 'sawtooth', gain: 0.05, slide: 150 });
      burst(c, { dur: 0.3, type: 'lowpass', freq: 400, gain: 0.25, delay: 0.25 });
      break;
    case 'death_player':
      tone(c, { freq: 220, dur: 0.6, type: 'triangle', gain: 0.1, slide: 110 });
      tone(c, { freq: 165, dur: 0.9, type: 'sine', gain: 0.1, delay: 0.2, slide: 110 });
      burst(c, { dur: 0.3, type: 'lowpass', freq: 400, gain: 0.3, delay: 0.3 });
      break;
    case 'rout':
      tone(c, { freq: 600, dur: 0.25, type: 'triangle', gain: 0.06, slide: 900 });
      tone(c, { freq: 500, dur: 0.25, type: 'triangle', gain: 0.05, slide: 800, delay: 0.12 });
      break;
    case 'horn':
      for (const [f, d] of [[196, 0], [294, 0.35]] as const) {
        tone(c, { freq: f, dur: 0.6, type: 'sawtooth', gain: 0.045, attack: 0.08, delay: d });
        tone(c, { freq: f * 2, dur: 0.6, type: 'sine', gain: 0.03, attack: 0.08, delay: d });
      }
      break;
    case 'turn':
      tone(c, { freq: 392, dur: 0.35, type: 'triangle', gain: 0.07, attack: 0.02 });
      tone(c, { freq: 523, dur: 0.45, type: 'triangle', gain: 0.06, attack: 0.02, delay: 0.12 });
      break;
    case 'drum':
      for (const d of [0, 0.22, 0.44]) tone(c, { freq: 90, dur: 0.25, gain: 0.3, slide: 45, delay: d });
      break;
    case 'select':
      tone(c, { freq: 880, dur: 0.06, type: 'triangle', gain: 0.04 });
      break;
    case 'click':
      tone(c, { freq: 660, dur: 0.05, type: 'triangle', gain: 0.04 });
      break;
    case 'deny':
      tone(c, { freq: 180, dur: 0.12, type: 'square', gain: 0.03 });
      break;
    case 'stance':
      burst(c, { dur: 0.12, type: 'bandpass', freq: 900, gain: 0.25 });
      tone(c, { freq: 300, dur: 0.2, type: 'triangle', gain: 0.08, delay: 0.05 });
      break;
    case 'warcry':
      tone(c, { freq: 120, dur: 0.9, type: 'sawtooth', gain: 0.08, slide: 160, attack: 0.1 });
      burst(c, { dur: 0.8, type: 'bandpass', freq: 600, gain: 0.15, attack: 0.1 });
      break;
    case 'coin':
      tone(c, { freq: 1400, dur: 0.08, type: 'triangle', gain: 0.05 });
      tone(c, { freq: 2100, dur: 0.12, type: 'triangle', gain: 0.04, delay: 0.06 });
      break;
    case 'build':
      for (const d of [0, 0.18, 0.36]) burst(c, { dur: 0.08, type: 'lowpass', freq: 600, gain: 0.35, delay: d });
      break;
    case 'march':
      for (const d of [0, 0.25, 0.5, 0.75]) burst(c, { dur: 0.08, type: 'lowpass', freq: 380, gain: 0.18, delay: d });
      break;
    case 'victory':
      [392, 494, 587, 784].forEach((f, i) => tone(c, { freq: f, dur: 0.6, type: 'triangle', gain: 0.07, delay: i * 0.13 }));
      break;
    case 'defeat':
      [330, 294, 247, 196].forEach((f, i) => tone(c, { freq: f, dur: 0.7, type: 'triangle', gain: 0.06, delay: i * 0.2 }));
      break;
    case 'page':
      burst(c, { dur: 0.18, type: 'bandpass', freq: 3000, sweep: 1500, gain: 0.07, attack: 0.03 });
      break;
    case 'warhorn':
      // A distant orc war horn: a long low blare that bends up, over a rumble.
      for (const [f, d, len] of [[73, 0, 1.6], [98, 0.9, 1.4]] as const) {
        tone(c, { freq: f, dur: len, type: 'sawtooth', gain: 0.05, attack: 0.35, slide: f * 1.12, delay: d });
        tone(c, { freq: f * 1.5, dur: len, type: 'sine', gain: 0.025, attack: 0.4, slide: f * 1.6, delay: d });
      }
      burst(c, { dur: 1.8, type: 'lowpass', freq: 160, gain: 0.12, attack: 0.5 });
      break;
    case 'roar':
      // The horde roars: a swell of many voices.
      burst(c, { dur: 1.3, type: 'bandpass', freq: 420, q: 0.7, gain: 0.16, attack: 0.35, sweep: 300 });
      burst(c, { dur: 1.1, type: 'bandpass', freq: 900, q: 1.2, gain: 0.07, attack: 0.3, delay: 0.1 });
      tone(c, { freq: 110, dur: 1.2, type: 'sawtooth', gain: 0.03, attack: 0.3, slide: 130 });
      break;
    case 'relief':
      // The relief column's trumpets.
      [392, 523, 659, 784, 1046].forEach((f, i) => tone(c, { freq: f, dur: 0.5, type: 'sawtooth', gain: 0.035, attack: 0.03, delay: i * 0.16 }));
      [523, 784].forEach((f) => tone(c, { freq: f, dur: 1.4, type: 'triangle', gain: 0.05, attack: 0.05, delay: 0.85 }));
      break;
    case 'hooves':
      // Horsemen at the gallop, coming closer: three-beat strides swelling over three seconds.
      for (let i = 0; i < 9; i++) {
        for (const [k, o] of [[0, 0], [1, 0.07], [2, 0.13]]) {
          burst(c, { dur: 0.07, type: 'lowpass', freq: 170 + k * 30, gain: 0.08 + i * 0.03, delay: 0.2 + i * 0.33 + o + Math.random() * 0.02 });
        }
      }
      burst(c, { dur: 3.2, type: 'lowpass', freq: 120, gain: 0.1, attack: 1.4 });
      break;
    case 'smash':
      burst(c, { dur: 0.3, type: 'lowpass', freq: 220, gain: 0.5, sweep: 80 });
      tone(c, { freq: 70, dur: 0.3, gain: 0.25, slide: 40 });
      break;
    case 'cast':
      // Power gathering: a rising hum and a breath of air.
      tone(c, { freq: 220, dur: 0.45, type: 'sine', gain: 0.06, attack: 0.15, slide: 440 });
      burst(c, { dur: 0.45, type: 'bandpass', freq: 400, sweep: 1600, q: 3, gain: 0.08, attack: 0.15 });
      break;
    case 'lightning':
      // A crack and the crackle of the arc, then thunder rolling.
      burst(c, { dur: 0.06, type: 'highpass', freq: 2500, gain: 0.45 });
      for (let i = 0; i < 5; i++) burst(c, { dur: 0.04, type: 'highpass', freq: 1800 + i * 300, gain: 0.18, delay: 0.04 + i * 0.05 + Math.random() * 0.02 });
      burst(c, { dur: 1.1, type: 'lowpass', freq: 260, sweep: 70, gain: 0.35, attack: 0.05, delay: 0.08 });
      break;
    case 'frost':
      [1760, 2350, 2960].forEach((f, i) => tone(c, { freq: f * r(), dur: 0.5, type: 'sine', gain: 0.03, attack: 0.01, delay: i * 0.05 }));
      burst(c, { dur: 0.25, type: 'bandpass', freq: 3200, q: 2, gain: 0.2, delay: 0.05 });
      burst(c, { dur: 0.12, type: 'highpass', freq: 1500, gain: 0.25, delay: 0.02 });
      break;
    case 'heal':
      [659, 880, 1109, 1319].forEach((f, i) => tone(c, { freq: f, dur: 0.7, type: 'triangle', gain: 0.035, attack: 0.03, delay: i * 0.08 }));
      break;
    case 'fireball':
      burst(c, { dur: 0.5, type: 'bandpass', freq: 500, sweep: 1400, q: 1.2, gain: 0.2, attack: 0.08 });
      tone(c, { freq: 160, dur: 0.4, type: 'sawtooth', gain: 0.03, slide: 240 });
      break;
    case 'explosion':
      burst(c, { dur: 0.9, type: 'lowpass', freq: 900, sweep: 70, gain: 0.6 });
      tone(c, { freq: 64, dur: 0.6, type: 'sine', gain: 0.35, slide: 34 });
      burst(c, { dur: 0.5, type: 'bandpass', freq: 1800, sweep: 600, gain: 0.12, delay: 0.05 });
      break;
    case 'bloodlust':
      tone(c, { freq: 82, dur: 0.8, type: 'sawtooth', gain: 0.08, attack: 0.08, slide: 123 });
      tone(c, { freq: 123, dur: 0.7, type: 'sawtooth', gain: 0.04, attack: 0.1, slide: 165, delay: 0.1 });
      for (const d of [0, 0.18]) tone(c, { freq: 95, dur: 0.2, gain: 0.25, slide: 50, delay: d });
      break;
    case 'hex':
      tone(c, { freq: 233, dur: 0.8, type: 'sine', gain: 0.06, attack: 0.1, slide: 175 });
      tone(c, { freq: 247, dur: 0.8, type: 'sine', gain: 0.05, attack: 0.1, slide: 185 });
      burst(c, { dur: 0.6, type: 'bandpass', freq: 2400, sweep: 900, q: 4, gain: 0.07, attack: 0.15 });
      break;
    case 'catapult':
      // Timber groans, the arm slams the crossbar.
      tone(c, { freq: 140, dur: 0.25, type: 'square', gain: 0.03, slide: 85 });
      burst(c, { dur: 0.18, type: 'lowpass', freq: 500, gain: 0.45, delay: 0.18 });
      tone(c, { freq: 90, dur: 0.2, gain: 0.2, slide: 55, delay: 0.18 });
      break;
    case 'crash':
      burst(c, { dur: 0.55, type: 'lowpass', freq: 420, sweep: 60, gain: 0.6 });
      tone(c, { freq: 55, dur: 0.4, gain: 0.3, slide: 32 });
      for (let i = 0; i < 4; i++) burst(c, { dur: 0.05, type: 'bandpass', freq: 900 + i * 200, gain: 0.15, delay: 0.08 + i * 0.06 });
      break;
    case 'ballista':
      tone(c, { freq: 150, dur: 0.22, type: 'sawtooth', gain: 0.1, slide: 60 });
      burst(c, { dur: 0.14, type: 'highpass', freq: 900, gain: 0.4 });
      burst(c, { dur: 0.3, type: 'lowpass', freq: 300, gain: 0.3, delay: 0.02 });
      break;
  }
}
