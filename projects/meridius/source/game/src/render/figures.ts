// Procedural character figures in the project's look: chunky miniature
// proportions, cel shading lit from the upper left, dark-brown outlines.
// Front poses face down-left (toward the camera); back poses face up-right.

import { Rng } from '../core/rng';

export type Pose = 'idle_f' | 'atk_f' | 'idle_b' | 'atk_b' | 'dead' | 'flee_b' | 'idle_fs' | 'atk_fs' | 'idle_bs' | 'atk_bs' | 'run_f' | 'run_b';

/**
 * Shield-leading poses (`_fs`, `_bs`) are drawn for the mirrored facings. A
 * mirrored figure would carry its shield on the right arm; these poses put the
 * shield on the leading arm and the blade on the trailing one, so once mirrored
 * every soldier still holds his shield on the left (reference: "Facing when
 * moving" sheets). Only troops with shields need them.
 */
export function hasShieldPoses(type: string): boolean {
  const sh = styleFor(type, 0).shield;
  return sh === 'kite' || sh === 'round';
}

/** Border collie coat for the collie guard. */
interface DogCoat {
  coat: string; // main fur (black or brown)
  white: string; // blaze, muzzle, ruff, paws and tail tip
  tan?: string; // tricolour points above the eyes and on the cheeks
  ears: 'fold' | 'prick';
  blaze: number; // width of the white forehead blaze
}

/** Moss troll growth and face details. */
interface TrollLook {
  mantle: string; // dark stringy hair draped over the hump
  moss: string;
  mossAmt: number; // 0.5..1.3 coverage
  fungus: number[]; // shelf fungus slots along the hump (0 front shoulder .. 7 lower back)
  twigs: number[]; // twig slots along the hump
  nose: number; // nose length factor
  beard: number; // beard length factor
  tattoo: string;
}

interface Style {
  kind: 'human' | 'goblin' | 'orc' | 'troll' | 'dog' | 'wolf' | 'horse';
  height: number; // 1 = human
  bulk: number; // width multiplier
  skin: string;
  hair: string;
  beard: boolean;
  tunic: string;
  tabard: string;
  trim: string;
  trousers: string;
  boots: string;
  belt: string;
  scarf?: string;
  hood?: string;
  /** Hood worn down: a bunched cowl around the neck instead of a scarf. */
  cowl?: string;
  helmet?: 'none' | 'kettle' | 'goblin' | 'orc' | 'horned';
  hairStyle?: 'cap' | 'spiky' | 'long' | 'shaved';
  beardStyle?: 'full' | 'chin';
  plume?: string;
  /** Feather crest over a bare scalp (savage orcs); value scales its height. */
  mohawk?: number;
  rags?: string;
  pauldrons?: 'spiked' | 'leather' | 'brute' | 'plate' | 'none';
  fur?: string;
  weapon: 'sword' | 'spear' | 'crossbow' | 'gspear' | 'bow' | 'cleaver' | 'mace' | 'club' | 'log' | 'knife' | 'horn';
  /** A pitchfork rather than a spearhead (village militia). */
  fork?: boolean;
  /** The goblin riding a wolf rider's wolf, or the knight on a horse. */
  rider?: Style;
  shield: 'kite' | 'round' | 'none';
  emblem: 'eagle' | 'orc' | 'none';
  /** Emblem and trim metal for plate armour and its kite shield (default white eagle, steel rim). */
  gold?: string;
  /** Plate armour: gold-trimmed breastplate, knee cops and vambraces. */
  plate?: boolean;
  gauntlet?: string;
  quiver?: string;
  warpaint?: string;
  paint?: 'stripe' | 'claw' | 'mask';
  armPaint?: string;
  chestPaint?: string;
  skulls?: number;
  chestSkulls?: number;
  skullShoulder?: boolean;
  banner?: boolean;
  /** Bare chest with a crossed leather harness and a fur kilt. */
  bare?: boolean;
  bracers?: string;
  headRag?: string;
  hornHood?: boolean;
  nose?: number;
  ears?: number;
  tusks?: number;
  earring?: boolean;
  dog?: DogCoat;
  troll?: TrollLook;
}

const INK = '#2a1a10';
const STEEL = '#c9ced4';
const STEEL_D = '#7d858e';
const WOOD = '#7a5532';
const LEATHER = '#6b4426';
const BONE = '#e6dcc2';
const GOLD = '#d2a63c';

const HAIRS = ['#5a3a1e', '#d9b25a', '#2b211a', '#8a4a22', '#6e4b2a', '#3a2a1a'];
const SKINS = ['#e9bf98', '#dcab84', '#c9926a', '#efc7a4', '#b07a52', '#f4d2b2'];

function shade(col: string, f: number): string {
  // Accepts '#rrggbb' or a previous result of shade() ('rgb(r,g,b)').
  let rgb: number[];
  if (col.startsWith('rgb')) rgb = col.slice(col.indexOf('(') + 1, -1).split(',').map(Number);
  else {
    const n = parseInt(col.slice(1), 16);
    rgb = [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }
  const c = rgb.map((v) => Math.max(0, Math.min(255, Math.round(f < 0 ? v * (1 + f) : v + (255 - v) * f))));
  return `rgb(${c[0]},${c[1]},${c[2]})`;
}

/**
 * Look of one soldier. Variants 0..5 of a type share its uniform, palette and
 * silhouette but differ in hair, beard, skin, headgear and small trophies, so
 * a squad of six reads as one unit made of individuals.
 */
export function styleFor(type: string, variant: number): Style {
  const r = new Rng(type.length * 97 + variant * 13 + 5);
  const v = ((variant % 6) + 6) % 6;
  // Variants 3..5 are a second set of looks on top of the original three.
  const hi = v >= 3;
  const human = (over: Partial<Style>): Style => ({
    kind: 'human',
    height: 1,
    bulk: 1,
    skin: SKINS[v % SKINS.length],
    hair: HAIRS[(v * 2 + type.length + (hi ? 1 : 0)) % HAIRS.length],
    beard: r.chance(0.45),
    hairStyle: hi ? (['spiky', 'long', 'shaved'] as const)[v - 3] : 'cap',
    tunic: '#ece2c6',
    tabard: '#2f58b8',
    trim: '#1f3f8c',
    trousers: '#2c3f86',
    boots: '#5a3820',
    belt: '#5a3a22',
    scarf: '#2f58b8',
    helmet: 'none',
    weapon: 'sword',
    shield: 'none',
    emblem: 'eagle',
    pauldrons: 'none',
    ...over,
  });
  // Beards for variants 3..5 per type, chosen to complement the first three.
  const beardHi = (list: (false | 'full' | 'chin')[]): Partial<Style> =>
    hi ? { beard: !!list[v - 3], beardStyle: list[v - 3] || 'full' } : {};
  const goblinSkin = ['#7f9a3a', '#8aa142', '#71903a', '#94a446', '#66853a', '#7e9446'][v];
  switch (type) {
    case 'footman':
      return human({ weapon: 'sword', shield: 'kite', bulk: 1.06, ...beardHi(['chin', false, 'full']) });
    case 'spearman':
      return human({ weapon: 'spear', pauldrons: 'leather', ...beardHi([false, 'chin', false]) });
    case 'crossbowman': {
      // Odd later variants wear the hood down as a cowl, showing their hair.
      const down = v === 3 || v === 5;
      return human({
        weapon: 'crossbow', hood: down ? undefined : '#2f58b8', cowl: down ? '#2f58b8' : undefined, scarf: undefined,
        quiver: '#7a5532', bulk: 0.98, ...(v === 5 ? { hairStyle: 'long' as const } : {}), ...beardHi([false, false, 'chin']),
      });
    }
    case 'collie_guard': {
      const coats: DogCoat[] = [
        { coat: '#1f1b1c', white: '#f2eee4', ears: 'fold', blaze: 1 },
        { coat: '#1f1b1c', white: '#f2eee4', tan: '#b8682e', ears: 'fold', blaze: 0.7 },
        { coat: '#6e3c1e', white: '#f2ece0', ears: 'fold', blaze: 1.15 },
        { coat: '#1f1b1c', white: '#f2eee4', ears: 'prick', blaze: 1.35 },
        { coat: '#1f1b1c', white: '#f2eee4', tan: '#b8682e', ears: 'prick', blaze: 0.8 },
        { coat: '#87512c', white: '#f4eee2', tan: '#c98a4a', ears: 'fold', blaze: 0.9 },
      ];
      return {
        kind: 'dog', height: 1, bulk: 1.08, skin: '#f2eee4', hair: coats[v].coat, beard: false,
        tunic: '#2e2c31', tabard: '#1c1a1e', trim: GOLD, trousers: '#2a292e', boots: '#2a292e', belt: '#6b4426',
        weapon: 'sword', shield: 'kite', emblem: 'eagle', gold: GOLD, plate: true, gauntlet: '#2b2522', pauldrons: 'plate',
        dog: coats[v],
      };
    }
    case 'goblin_spear':
      return {
        kind: 'goblin', height: 0.8, bulk: 0.95, skin: goblinSkin, hair: '#1c1612', beard: false,
        tunic: '#3a2f2a', tabard: '#2b231f', trim: '#a3261c', trousers: '#2d2620', boots: '#3b2a1d', belt: '#4a2f1c',
        helmet: v % 2 === 0 ? 'goblin' : 'none', hood: v % 2 === 1 ? '#25201d' : undefined, plume: '#b3261c',
        rags: '#b3261c', weapon: 'gspear', shield: 'none', emblem: 'none', warpaint: '#b3261c', pauldrons: 'none', fur: '#3a2c22',
        headRag: v === 3 ? '#b3261c' : undefined, hornHood: v === 5, skullShoulder: v === 4,
        nose: [1, 1, 1.3, 1, 0.85, 1.1][v], ears: [1, 1, 1, 0.8, 1.2, 1.1][v], paint: (['stripe', 'stripe', 'claw', 'stripe', 'mask', 'stripe'] as const)[v],
      };
    case 'goblin_archer':
      return {
        kind: 'goblin', height: 0.8, bulk: 0.92, skin: goblinSkin, hair: '#1c1612', beard: false,
        tunic: '#2a2522', tabard: '#211c1a', trim: '#a3261c', trousers: '#2d2620', boots: '#3b2a1d', belt: '#4a2f1c',
        hood: '#211d1b', rags: '#b3261c', weapon: 'bow', shield: 'none', emblem: 'none', quiver: '#5a3a22', warpaint: '#b3261c', pauldrons: 'none',
        headRag: v === 3 ? '#b3261c' : undefined, hornHood: v === 4, skullShoulder: v === 2,
        nose: [1, 1.35, 1, 0.85, 1.1, 0.8][v], ears: [1, 1, 1.3, 1.1, 0.9, 1][v], paint: (['stripe', 'claw', 'stripe', 'stripe', 'stripe', 'mask'] as const)[v],
      };
    case 'orc_warrior':
      return {
        kind: 'orc', height: 1.12, bulk: 1.35, skin: ['#7b8d3a', '#6f8436', '#839542', '#768a3c', '#8a9a48', '#667c34'][v], hair: '#1c1612',
        beard: v === 1 || v === 4 || v === 5, beardStyle: v === 1 ? 'chin' : 'full',
        tunic: '#5c3b26', tabard: '#7a2a1c', trim: '#a3261c', trousers: '#3a2f26', boots: '#3b2a1d', belt: '#4a2f1c',
        helmet: v === 2 || v === 4 ? 'none' : 'orc', plume: '#b3261c', rags: '#a3261c', pauldrons: 'spiked', fur: ['#2e241d', '#2e241d', '#2e241d', '#3b2b20', '#2e241d', '#4a3524'][v],
        weapon: 'cleaver', shield: 'round', emblem: 'orc', warpaint: '#b3261c',
        paint: v === 3 ? 'claw' : 'stripe', tusks: [1, 1, 1, 1, 1.35, 1.3][v], earring: v === 4,
      };
    case 'orc_brute':
      return {
        kind: 'orc', height: 1.2, bulk: 1.5, skin: ['#7d9140', '#6e8538', '#879a42', '#73883a', '#8c9d4a', '#647a32'][v], hair: '#161210',
        beard: v === 0 || v === 2 || v === 4, beardStyle: 'chin',
        tunic: '#7d9140', tabard: '#7a2a1c', trim: '#a3261c', trousers: '#2a2420', boots: '#3a271a', belt: '#4a2f1c',
        helmet: 'none', plume: '#b3261c', mohawk: [1.15, 0.85, 1.35, 1, 1.25, 0.8][v], rags: '#a3261c', pauldrons: 'brute', fur: ['#1c1816', '#1c1816', '#2a211b', '#1c1816', '#2a211b', '#1c1816'][v],
        weapon: 'club', shield: 'none', emblem: 'none', warpaint: v === 3 ? '#e0b830' : '#b3261c', paint: (['stripe', 'claw', 'mask', 'stripe', 'claw', 'mask'] as const)[v],
        armPaint: '#e0b830', chestPaint: [undefined, '#b3261c', undefined, '#e0b830', undefined, '#b3261c'][v], bare: true, bracers: '#5a4030', chestSkulls: [2, 1, 2, 1, 2, 1][v], skulls: 1,
        tusks: [1.15, 1, 1.35, 1.2, 1, 1.45][v], earring: v === 1 || v === 4,
      };
    case 'orc_warlord':
      return {
        kind: 'orc', height: 1.3, bulk: 1.6, skin: ['#73853a', '#6a7d34', '#7f9140', '#667a32', '#7a8a3e', '#5f7230'][v], hair: '#141010',
        beard: v !== 1 && v !== 3,
        tunic: '#4a2f20', tabard: '#8a2418', trim: '#c8a23a', trousers: '#2e261f', boots: '#33251a', belt: '#3a2614',
        helmet: v === 1 || v === 4 ? 'horned' : 'none', plume: '#b3261c', rags: '#a3261c', pauldrons: 'spiked', fur: '#241c16',
        weapon: 'mace', shield: 'none', emblem: 'orc', warpaint: '#c8a23a', skulls: 3, banner: true,
        paint: v === 2 ? 'mask' : v === 5 ? 'claw' : 'stripe', tusks: [1, 1.3, 1, 1.4, 1.1, 1.2][v], earring: v === 2 || v === 5,
      };
    case 'goblin_rabble': {
      // The host's starvelings: bald, bare-chested, ragged, with knives and hatchets.
      const sk = ['#9aa848', '#8e9e42', '#a3ab52', '#84973e', '#a0a44c', '#93a046'][v];
      return {
        kind: 'goblin', height: 0.74, bulk: 0.86, skin: sk, hair: '#1c1612', beard: false,
        tunic: sk, tabard: sk, trim: '#7a3a1c', trousers: '#3a2c20', boots: '#4a3424', belt: '#3e2a1a',
        helmet: 'none', hairStyle: 'shaved', rags: ['#6b4a2a', '#5a3a22', '#7a2a1c', '#6b4a2a', '#4e3a26', '#7a2a1c'][v],
        weapon: v % 3 === 1 ? 'cleaver' : 'knife', shield: 'none', emblem: 'none', pauldrons: 'none',
        bare: true, fur: '#4a3424', warpaint: v % 2 ? '#b3261c' : '#e0d8c0', paint: (['stripe', 'claw', 'mask', 'stripe', 'claw', 'mask'] as const)[v],
        headRag: v === 2 || v === 5 ? '#7a2a1c' : undefined,
        nose: [1.2, 1, 1.35, 0.9, 1.1, 1.25][v], ears: [1.2, 1.35, 1, 1.4, 1.15, 1.3][v],
      };
    }
    case 'goblin_horn':
      return {
        kind: 'goblin', height: 0.84, bulk: 0.98, skin: goblinSkin, hair: '#1c1612', beard: false,
        tunic: '#3a2f2a', tabard: '#2b231f', trim: '#a3261c', trousers: '#2d2620', boots: '#3b2a1d', belt: '#4a2f1c',
        hood: '#25201d', hornHood: true, rags: '#b3261c', weapon: 'horn', shield: 'none', emblem: 'none', warpaint: '#b3261c',
        pauldrons: 'none', fur: '#3a2c22', banner: true, skulls: 2, nose: 1.15, ears: 1.1, paint: 'mask',
      };
    case 'militia': {
      const coat = ['#7a6a48', '#6e6650', '#86744e', '#5e6a44', '#7c6446', '#6a5e48'][v];
      return human({
        tunic: ['#c9bc98', '#b8ad90', '#cfc29e', '#bdb394', '#c4b48e', '#b4a888'][v],
        tabard: coat, trim: shade(coat, -0.2), trousers: ['#4a4636', '#3e3a30', '#52483a', '#46483a', '#4c4234', '#3a3a32'][v],
        boots: '#4a3220', belt: '#4a3220', scarf: undefined, emblem: 'none', weapon: 'spear', fork: v % 2 === 1,
        hood: v === 1 || v === 4 ? shade(coat, -0.1) : undefined, pauldrons: 'none', bulk: 0.98,
        ...beardHi(['full', 'chin', false]),
      });
    }
    case 'wolf_rider': {
      const wolf = ['#6d6a64', '#7a746a', '#5c5a56', '#827b70', '#66625c', '#74706a'][v];
      return {
        kind: 'wolf', height: 1, bulk: 1, skin: wolf, hair: shade(wolf, -0.35), beard: false,
        tunic: '#3a2f2a', tabard: '#2b231f', trim: '#a3261c', trousers: '#2d2620', boots: '#3b2a1d', belt: '#5a3a22',
        rags: '#b3261c', weapon: 'gspear', shield: 'none', emblem: 'none', pauldrons: 'none',
        rider: {
          kind: 'goblin', height: 0.74, bulk: 0.9, skin: goblinSkin, hair: '#1c1612', beard: false,
          tunic: '#3a2f2a', tabard: '#2b231f', trim: '#a3261c', trousers: '#2d2620', boots: '#3b2a1d', belt: '#4a2f1c',
          hood: v % 2 ? '#25201d' : undefined, helmet: v % 2 ? 'none' : 'goblin', plume: '#b3261c', rags: '#b3261c',
          weapon: 'gspear', shield: 'none', emblem: 'none', warpaint: '#b3261c', pauldrons: 'none',
          nose: 1.1, ears: 1.1, paint: v % 3 === 0 ? 'claw' : 'stripe',
        },
      };
    }
    case 'margrave_rider': {
      // The Margrave's riders, who come with the dawn: bay, grey, black, chestnut, dun.
      const coat = ['#6b4128', '#b9b2a6', '#3a302c', '#8a4c26', '#a08a68', '#5a3a26'][v];
      const mane = ['#2a1c14', '#e6e0d4', '#1c1614', '#5a2e16', '#3a2c1e', '#1e1612'][v];
      return {
        kind: 'horse', height: 1, bulk: 1, skin: coat, hair: mane, beard: false,
        tunic: '#ece2c6', tabard: '#2f58b8', trim: '#1f3f8c', trousers: '#2c3f86', boots: '#5a3820', belt: '#5a3a22',
        weapon: 'spear', shield: 'none', emblem: 'none', pauldrons: 'none', gold: GOLD,
        rider: human({ helmet: 'kettle', plume: '#f2eee4', gold: GOLD, gauntlet: '#5a5f66', weapon: 'spear', scarf: undefined }),
      };
    }
    case 'troll': {
      const looks: TrollLook[] = [
        { mantle: '#4d4339', moss: '#7f9a2e', mossAmt: 1, fungus: [0, 4], twigs: [2, 4, 5], nose: 1, beard: 1, tattoo: '#3f8f8a' },
        { mantle: '#463d35', moss: '#88a032', mossAmt: 1.3, fungus: [2, 6], twigs: [3], nose: 1.15, beard: 0.8, tattoo: '#3f8f8a' },
        { mantle: '#54483b', moss: '#76922a', mossAmt: 0.7, fungus: [0, 3, 6], twigs: [2, 3, 5, 6], nose: 0.9, beard: 1.3, tattoo: '#3f8f8a' },
        { mantle: '#4a4138', moss: '#8aa634', mossAmt: 1.1, fungus: [1, 5], twigs: [4, 6], nose: 1.25, beard: 1.1, tattoo: '#3f8f8a' },
        { mantle: '#3f3832', moss: '#7c982c', mossAmt: 0.85, fungus: [0, 2, 4, 7], twigs: [1, 3, 5], nose: 1.05, beard: 0.7, tattoo: '#3f8f8a' },
        { mantle: '#51463a', moss: '#93ab3a', mossAmt: 1.2, fungus: [3], twigs: [2, 4], nose: 0.95, beard: 1.2, tattoo: '#3f8f8a' },
      ];
      return {
        kind: 'troll', height: 1.6, bulk: 1.9,
        skin: ['#b3b8ab', '#a8b29e', '#a6afb2', '#b8b0a2', '#9ea397', '#bfc1b6'][v],
        hair: ['#77706a', '#d9d4c8', '#5c5148', '#9a948a', '#bdb6a8', '#665e56'][v], beard: true,
        tunic: looks[v].mantle, tabard: looks[v].mantle, trim: looks[v].moss, trousers: '#6a4a2c', boots: '#6a4a2c', belt: '#8a6a3c',
        weapon: 'log', shield: 'none', emblem: 'none', pauldrons: 'none', troll: looks[v],
      };
    }
    default:
      return human({});
  }
}

// ---------------------------------------------------------------- primitives

function poly(x: CanvasRenderingContext2D, pts: number[][], fill: string, lw = 2.4, stroke = INK) {
  x.beginPath();
  pts.forEach(([px, py], i) => (i ? x.lineTo(px, py) : x.moveTo(px, py)));
  x.closePath();
  x.fillStyle = fill;
  x.fill();
  if (lw > 0) {
    x.lineWidth = lw;
    x.strokeStyle = stroke;
    x.stroke();
  }
}

/** Fill a path, then darken its right side for the cel shadow (light from upper left). */
function cel(x: CanvasRenderingContext2D, path: () => void, fill: string, cut: number, lw = 2.4, dark = -0.28, light = 0.18) {
  x.save();
  path();
  x.fillStyle = fill;
  x.fill();
  x.clip();
  x.fillStyle = shade(fill, dark);
  x.beginPath();
  x.rect(cut, -400, 400, 800);
  x.fill();
  x.fillStyle = shade(fill, light);
  x.globalAlpha = 0.6;
  x.beginPath();
  x.rect(-400, -400, 400 + cut - 14, 800);
  x.fill();
  x.restore();
  path();
  x.lineWidth = lw;
  x.strokeStyle = INK;
  x.stroke();
}

function limb(x: CanvasRenderingContext2D, ax: number, ay: number, bx: number, by: number, w: number, fill: string) {
  const dx = bx - ax;
  const dy = by - ay;
  const len = Math.hypot(dx, dy) || 1;
  const nx = (-dy / len) * w * 0.5;
  const ny = (dx / len) * w * 0.5;
  x.beginPath();
  x.moveTo(ax + nx, ay + ny);
  x.lineTo(bx + nx * 0.85, by + ny * 0.85);
  x.arc(bx, by, w * 0.43, Math.atan2(ny, nx), Math.atan2(ny, nx) + Math.PI);
  x.lineTo(ax - nx, ay - ny);
  x.arc(ax, ay, w * 0.5, Math.atan2(-ny, -nx), Math.atan2(-ny, -nx) + Math.PI);
  x.closePath();
  x.fillStyle = fill;
  x.fill();
  x.lineWidth = 2.2;
  x.strokeStyle = INK;
  x.stroke();
  // Cel shadow along one side.
  x.save();
  x.clip();
  x.strokeStyle = shade(fill, -0.3);
  x.lineWidth = w * 0.45;
  x.beginPath();
  x.moveTo(ax - nx * 0.9, ay - ny * 0.9);
  x.lineTo(bx - nx * 0.9, by - ny * 0.9);
  x.stroke();
  x.restore();
}

function boot(x: CanvasRenderingContext2D, hx: number, gy: number, dir: number, s: Style) {
  if (s.dog) {
    paw(x, hx, gy, dir, s.bulk, s.dog.white);
    return;
  }
  // Boot from the ankle to the ground, toe pointing in `dir` (-1 left, 1 right).
  const w = 17 * s.bulk;
  poly(
    x,
    [
      [hx - w * 0.5, gy - 20],
      [hx + w * 0.5, gy - 20],
      [hx + w * 0.55 + (dir > 0 ? 9 : 0), gy - 4],
      [hx + w * 0.5 + (dir > 0 ? 10 : 0), gy],
      [hx - w * 0.5 - (dir < 0 ? 10 : 0), gy],
      [hx - w * 0.55 - (dir < 0 ? 9 : 0), gy - 4],
    ],
    s.kind === 'human' ? s.boots : s.boots,
  );
  x.fillStyle = shade(s.boots, 0.25);
  x.fillRect(hx - w * 0.4, gy - 20, 3, 14);
  x.fillStyle = shade(s.boots, -0.45);
  x.fillRect(hx - w * 0.55 - (dir < 0 ? 8 : 0), gy - 3, w * 1.1 + 8, 3);
}

/** Furry white dog paw with feathered fetlock, toes pointing in `dir`. */
function paw(x: CanvasRenderingContext2D, hx: number, gy: number, dir: number, bulk: number, white: string) {
  const w = 17 * bulk;
  poly(
    x,
    [
      [hx - w * 0.5, gy - 23],
      [hx + w * 0.5, gy - 23],
      [hx + w * 0.66, gy - 14],
      [hx + w * 0.42, gy - 10],
      [hx + w * 0.55, gy - 6],
      [hx - w * 0.55, gy - 6],
      [hx - w * 0.42, gy - 10],
      [hx - w * 0.66, gy - 14],
    ],
    white,
    2,
  );
  const px = hx + dir * 5;
  x.beginPath();
  x.ellipse(px, gy - 4.5, w * 0.62 + 3, 5.5, 0, 0, Math.PI * 2);
  x.fillStyle = white;
  x.fill();
  x.lineWidth = 2.2;
  x.strokeStyle = INK;
  x.stroke();
  x.fillStyle = shade(white, -0.3);
  x.fillRect(px - w * 0.5, gy - 2, w + 4, 2);
  x.strokeStyle = shade(white, -0.4);
  x.lineWidth = 1.4;
  for (const k of [-1, 0, 1]) {
    x.beginPath();
    x.moveTo(px + dir * 6 + k * 4.5, gy - 9);
    x.lineTo(px + dir * 7 + k * 4.5, gy - 3);
    x.stroke();
  }
}

// ---------------------------------------------------------------- weapons

function sword(x: CanvasRenderingContext2D, hx: number, hy: number, ang: number, len = 54) {
  x.save();
  x.translate(hx, hy);
  x.rotate(ang);
  poly(x, [[-3.5, -8], [3.5, -8], [3, -len], [0, -len - 9], [-3, -len]], STEEL, 2);
  x.fillStyle = '#ffffff';
  x.globalAlpha = 0.6;
  x.fillRect(-1.6, -len + 2, 1.6, len - 12);
  x.globalAlpha = 1;
  poly(x, [[-11, -9], [11, -9], [11, -4], [-11, -4]], '#8a6a2a', 1.8);
  poly(x, [[-2.5, -4], [2.5, -4], [2.5, 10], [-2.5, 10]], LEATHER, 1.6);
  x.fillStyle = '#c8a23a';
  x.beginPath();
  x.arc(0, 12, 3.4, 0, Math.PI * 2);
  x.fill();
  x.stroke();
  x.restore();
}

function cleaver(x: CanvasRenderingContext2D, hx: number, hy: number, ang: number, big = 1) {
  x.save();
  x.translate(hx, hy);
  x.rotate(ang);
  x.scale(big, big);
  poly(x, [[-5, -8], [6, -8], [11, -48], [3, -60], [-6, -56]], '#9aa1a8', 2.2);
  x.fillStyle = '#5d646c';
  x.fillRect(-4, -54, 3, 44);
  poly(x, [[-12, -10], [12, -10], [12, -5], [-12, -5]], '#4a2f1c', 1.8);
  poly(x, [[-3, -5], [3, -5], [3, 12], [-3, 12]], '#3a2614', 1.6);
  x.restore();
}

function mace(x: CanvasRenderingContext2D, hx: number, hy: number, ang: number) {
  x.save();
  x.translate(hx, hy);
  x.rotate(ang);
  poly(x, [[-4, 16], [4, 16], [4, -50], [-4, -50]], WOOD, 2);
  x.fillStyle = '#a3261c';
  x.fillRect(-4, -6, 8, 6);
  // Spiked head.
  x.save();
  x.translate(0, -62);
  for (let i = 0; i < 8; i++) {
    const a = (i / 8) * Math.PI * 2;
    poly(x, [[Math.cos(a) * 11, Math.sin(a) * 13], [Math.cos(a + 0.2) * 22, Math.sin(a + 0.2) * 24], [Math.cos(a + 0.4) * 11, Math.sin(a + 0.4) * 13]], STEEL, 1.6);
  }
  x.beginPath();
  x.ellipse(0, 0, 14, 17, 0, 0, Math.PI * 2);
  x.fillStyle = '#5a3a22';
  x.fill();
  x.lineWidth = 2.2;
  x.strokeStyle = INK;
  x.stroke();
  x.fillStyle = STEEL_D;
  x.fillRect(-14, -3, 28, 6);
  x.restore();
  x.restore();
}

/** Two-handed savage war-club: long haft, banded wooden head studded with iron spikes. */
function club(x: CanvasRenderingContext2D, hx: number, hy: number, ang: number, size = 1) {
  x.save();
  x.translate(hx, hy);
  x.rotate(ang);
  x.scale(size, size);
  poly(x, [[-4, 36], [4, 36], [4.6, -54], [-4.6, -54]], WOOD, 2);
  x.fillStyle = shade(WOOD, 0.3);
  x.fillRect(-3, -52, 1.6, 84);
  // Red cloth wrapped round the grip.
  poly(x, [[-5, -6], [5, -9], [5, -2], [-5, 1]], '#a3261c', 1.2);
  poly(x, [[-5, 10], [5, 7], [5, 13], [-5, 16]], '#a3261c', 1.2);
  x.save();
  x.translate(0, -76);
  // Spikes first so the head covers their bases.
  for (const sy of [-14, 0, 14]) {
    for (const side of [-1, 1]) poly(x, [[side * 13, sy - 5], [side * 26, sy + side * 1.5], [side * 13, sy + 5]], STEEL, 1.6);
  }
  poly(x, [[-6, -24], [0, -38], [6, -24]], STEEL, 1.6);
  const head = () => {
    x.beginPath();
    x.moveTo(-14, -22);
    x.quadraticCurveTo(0, -30, 14, -22);
    x.lineTo(15, 20);
    x.quadraticCurveTo(0, 27, -15, 20);
    x.closePath();
  };
  x.save();
  head();
  x.fillStyle = '#5e3b22';
  x.fill();
  x.clip();
  x.fillStyle = shade('#5e3b22', -0.35);
  x.fillRect(4, -40, 20, 80);
  x.fillStyle = shade('#5e3b22', 0.2);
  x.fillRect(-15, -40, 6, 80);
  x.strokeStyle = shade('#5e3b22', -0.45);
  x.lineWidth = 1.2;
  for (const px of [-6, 1, 8]) {
    x.beginPath();
    x.moveTo(px, -26);
    x.lineTo(px, 24);
    x.stroke();
  }
  x.restore();
  head();
  x.lineWidth = 2.4;
  x.strokeStyle = INK;
  x.stroke();
  // Iron bands and front studs.
  poly(x, [[-15, -20], [15, -20], [15, -14], [-15, -14]], STEEL_D, 1.6);
  poly(x, [[-16, 12], [16, 12], [16, 18], [-16, 18]], STEEL_D, 1.6);
  poly(x, [[-4, -4], [0, -10], [4, -4], [0, 2]], STEEL, 1.4);
  poly(x, [[4, 4], [8, -1], [12, 4], [8, 9]], STEEL, 1.2);
  // Rag tied under the head.
  poly(x, [[-5, 26], [3, 26], [6, 44], [1, 38], [-3, 48]], '#a3261c', 1.2);
  x.restore();
  x.restore();
}

/**
 * The troll's uprooted log: a tapering mossy trunk from its butt end (bx, by)
 * to a splintered root ball at (ex, ey).
 */
function trollLog(x: CanvasRenderingContext2D, bx: number, by: number, ex: number, ey: number, t: TrollLook, seed: number) {
  const rng = new Rng(seed);
  const ang = Math.atan2(ey - by, ex - bx);
  const L = Math.hypot(ex - bx, ey - by);
  // Which local side faces up on screen, so the moss grows and the light falls on top.
  const up = Math.cos(ang) >= 0 ? -1 : 1;
  const BARK = '#6e4a2a';
  const w0 = 11;
  const w1 = 18;
  const rs = L - 22;
  x.save();
  x.translate(bx, by);
  x.rotate(ang);
  // Roots fanning out of the root end, behind the stump.
  for (let i = 0; i < 10; i++) {
    const a = -1.05 + i * (2.1 / 9) + rng.range(-0.1, 0.1);
    const len = rng.range(18, 34);
    const sx = rs + 4;
    const sy = Math.sin(a) * w1 * 0.9;
    const mx = sx + Math.cos(a) * len * 0.55;
    const my = sy + Math.sin(a) * len * 0.75 + rng.range(-4, 4);
    const tx = sx + Math.cos(a) * len;
    const ty = sy + Math.sin(a) * len * 1.1;
    for (const [col, lw] of [[INK, 6.4], [i % 2 ? '#5d3d22' : '#7a5532', 3.6]] as const) {
      x.strokeStyle = col;
      x.lineWidth = lw;
      x.beginPath();
      x.moveTo(sx, sy);
      x.quadraticCurveTo(mx, my, tx, ty);
      x.stroke();
    }
  }
  // Pale splinters where the trunk tore.
  for (let i = 0; i < 4; i++) {
    const sy = (i - 1.5) * 7;
    poly(x, [[rs + 6, sy - 3.5], [rs + 26 + rng.range(0, 10), sy + rng.range(-3, 3)], [rs + 6, sy + 3.5]], '#dcb97e', 1.4);
  }
  const trunk = () => {
    x.beginPath();
    x.moveTo(0, -w0);
    x.lineTo(rs, -w1);
    x.quadraticCurveTo(rs + 16, -w1 * 1.2, rs + 16, 0);
    x.quadraticCurveTo(rs + 16, w1 * 1.2, rs, w1);
    x.lineTo(0, w0);
    x.closePath();
  };
  x.save();
  trunk();
  x.fillStyle = BARK;
  x.fill();
  x.clip();
  // Light on the upper side, shade below.
  x.fillStyle = shade(BARK, -0.35);
  x.fillRect(-10, up > 0 ? -40 : 3, L + 40, 37);
  x.fillStyle = shade(BARK, 0.22);
  x.fillRect(-10, up > 0 ? 6 : -40, L + 40, 34);
  // Bark furrows and knots.
  x.strokeStyle = shade(BARK, -0.45);
  x.lineWidth = 1.4;
  for (let k = -2; k <= 2; k++) {
    x.beginPath();
    x.moveTo(6, k * 4.5);
    for (let px = 6; px < rs; px += 14) x.lineTo(px + 7, k * 4.5 * (1 + (px / rs) * 0.6) + rng.range(-1.5, 1.5));
    x.stroke();
  }
  for (const f of [0.35, 0.62]) {
    x.beginPath();
    x.ellipse(rs * f, rng.range(-4, 4), 3.5, 2.5, 0, 0, Math.PI * 2);
    x.fillStyle = shade(BARK, -0.5);
    x.fill();
  }
  x.restore();
  trunk();
  x.lineWidth = 2.4;
  x.strokeStyle = INK;
  x.stroke();
  // Cut butt end.
  x.beginPath();
  x.ellipse(0, 0, 3.5, w0, 0, 0, Math.PI * 2);
  x.fillStyle = '#c9a36a';
  x.fill();
  x.lineWidth = 1.8;
  x.stroke();
  // Vine binding near the grip.
  x.strokeStyle = '#4f6a22';
  x.lineWidth = 2.2;
  for (const f of [0.28, 0.33]) {
    x.beginPath();
    x.moveTo(rs * f - 3, -w0 - 2);
    x.lineTo(rs * f + 3, w0 + 2);
    x.stroke();
  }
  // Moss along the top of the trunk, with a few drips.
  const mossN = Math.round(4 + t.mossAmt * 3);
  const discs: number[][] = [];
  for (let i = 0; i < mossN; i++) {
    const px = rs * (0.36 + (i / mossN) * 0.66) + rng.range(-3, 3);
    const w = w0 + (w1 - w0) * (px / rs);
    discs.push([px, up * w * (0.7 + rng.range(0, 0.25)), rng.range(4.5, 7.5)]);
  }
  mossClump(x, discs, t.moss);
  x.restore();
  // Shelf fungus on the root end, drawn upright in screen space.
  const fx = bx + Math.cos(ang) * (rs - 6) - Math.sin(ang) * up * w1 * 0.9;
  const fy = by + Math.sin(ang) * (rs - 6) + Math.cos(ang) * up * w1 * 0.9;
  fungus(x, fx, fy, 0.75);
}

// ---------------------------------------------------------------- growth and trophies

/**
 * Bumpy clump of overlapping discs (moss): ink rims first, then the fills, so
 * only the outer outline of the union shows.
 */
function mossClump(x: CanvasRenderingContext2D, discs: number[][], col: string) {
  x.fillStyle = INK;
  for (const [cx, cy, r] of discs) {
    x.beginPath();
    x.arc(cx, cy, r + 1.9, 0, Math.PI * 2);
    x.fill();
  }
  x.fillStyle = shade(col, -0.22);
  for (const [cx, cy, r] of discs) {
    x.beginPath();
    x.arc(cx, cy, r, 0, Math.PI * 2);
    x.fill();
  }
  x.fillStyle = col;
  for (const [cx, cy, r] of discs) {
    x.beginPath();
    x.arc(cx - r * 0.12, cy - r * 0.14, r * 0.84, 0, Math.PI * 2);
    x.fill();
  }
  x.fillStyle = shade(col, 0.32);
  for (const [cx, cy, r] of discs) {
    x.beginPath();
    x.arc(cx - r * 0.32, cy - r * 0.36, r * 0.32, 0, Math.PI * 2);
    x.fill();
  }
}

/** Limb segment with properly rounded ends, for the big troll limbs. */
function capsule(x: CanvasRenderingContext2D, ax: number, ay: number, bx: number, by: number, w: number, fill: string) {
  const ang = Math.atan2(by - ay, bx - ax);
  const r = w / 2;
  const path = () => {
    x.beginPath();
    x.arc(ax, ay, r, ang + Math.PI / 2, ang + Math.PI * 1.5);
    x.arc(bx, by, r * 0.92, ang - Math.PI / 2, ang + Math.PI / 2);
    x.closePath();
  };
  x.save();
  path();
  x.fillStyle = fill;
  x.fill();
  x.clip();
  // Shade the side away from the upper-left light, light the other.
  const nx = -Math.sin(ang);
  const ny = Math.cos(ang);
  const sg = nx + ny >= 0 ? 1 : -1;
  x.strokeStyle = shade(fill, -0.28);
  x.lineWidth = w * 0.42;
  x.beginPath();
  x.moveTo(ax + nx * sg * r * 0.78, ay + ny * sg * r * 0.78);
  x.lineTo(bx + nx * sg * r * 0.78, by + ny * sg * r * 0.78);
  x.stroke();
  x.strokeStyle = shade(fill, 0.22);
  x.lineWidth = w * 0.16;
  x.beginPath();
  x.moveTo(ax - nx * sg * r * 0.55, ay - ny * sg * r * 0.55);
  x.lineTo(bx - nx * sg * r * 0.55, by - ny * sg * r * 0.55);
  x.stroke();
  x.restore();
  path();
  x.lineWidth = 2.4;
  x.strokeStyle = INK;
  x.stroke();
}

/** Orange shelf fungus: a small stack of half-discs with a pale underside. */
function fungus(x: CanvasRenderingContext2D, cx: number, cy: number, s: number) {
  const shelves = [
    [0, 0, 1],
    [5, -6, 0.75],
    [-6, 5, 0.7],
  ];
  for (const [ox, oy, k] of shelves) {
    const px = cx + ox * s;
    const py = cy + oy * s;
    const rw = 9 * s * k;
    x.beginPath();
    x.ellipse(px, py, rw, rw * 0.55, 0, Math.PI, 0);
    x.closePath();
    x.fillStyle = '#d27a36';
    x.fill();
    x.lineWidth = 1.4;
    x.strokeStyle = INK;
    x.stroke();
    x.fillStyle = '#efa760';
    x.beginPath();
    x.ellipse(px - rw * 0.2, py - rw * 0.32, rw * 0.5, rw * 0.14, 0, 0, Math.PI * 2);
    x.fill();
    x.beginPath();
    x.ellipse(px, py, rw, rw * 0.2, 0, 0, Math.PI);
    x.fillStyle = '#f0dcb4';
    x.fill();
    x.stroke();
  }
}

function twig(x: CanvasRenderingContext2D, x0: number, y0: number, ang: number, len: number) {
  const tx = x0 + Math.sin(ang) * len;
  const ty = y0 - Math.cos(ang) * len;
  const fx = x0 + Math.sin(ang) * len * 0.55;
  const fy = y0 - Math.cos(ang) * len * 0.55;
  const ex = fx + Math.sin(ang + 0.7) * len * 0.45;
  const ey = fy - Math.cos(ang + 0.7) * len * 0.45;
  const gx = x0 + Math.sin(ang) * len * 0.8;
  const gy = y0 - Math.cos(ang) * len * 0.8;
  const hx = gx + Math.sin(ang - 0.8) * len * 0.3;
  const hy = gy - Math.cos(ang - 0.8) * len * 0.3;
  for (const [col, lw] of [[INK, 5], ['#7a5532', 2.6]] as const) {
    x.strokeStyle = col;
    x.lineWidth = lw;
    x.beginPath();
    x.moveTo(x0, y0);
    x.lineTo(tx, ty);
    x.moveTo(fx, fy);
    x.lineTo(ex, ey);
    x.moveTo(gx, gy);
    x.lineTo(hx, hy);
    x.stroke();
  }
  // A leaf or two.
  poly(x, [[ex, ey], [ex - 4, ey - 6], [ex + 3, ey - 9], [ex + 5, ey - 3]], '#8aa634', 1.2);
}

/** Teal tattoo spiral. */
function spiral(x: CanvasRenderingContext2D, cx: number, cy: number, r: number, col: string) {
  x.strokeStyle = col;
  x.lineWidth = Math.max(1.6, r * 0.28);
  x.beginPath();
  for (let i = 0; i <= 24; i++) {
    const f = i / 24;
    const a = f * Math.PI * 3.2;
    const rr = r * (0.15 + f * 0.85);
    const px = cx + Math.cos(a) * rr;
    const py = cy + Math.sin(a) * rr * 0.85;
    if (i === 0) x.moveTo(px, py);
    else x.lineTo(px, py);
  }
  x.stroke();
}

/** Small bone skull trophy. */
function skull(x: CanvasRenderingContext2D, cx: number, cy: number, s = 1) {
  x.fillStyle = '#ece4cc';
  x.beginPath();
  x.ellipse(cx, cy, 5 * s, 6 * s, 0, 0, Math.PI * 2);
  x.fill();
  x.lineWidth = 1.4;
  x.strokeStyle = INK;
  x.stroke();
  x.fillStyle = INK;
  x.fillRect(cx - 3 * s, cy - 2 * s, 2 * s, 2 * s);
  x.fillRect(cx + 1 * s, cy - 2 * s, 2 * s, 2 * s);
  x.fillRect(cx - 0.5 * s, cy + 1.5 * s, 1 * s, 1.5 * s);
}

/**
 * A fluffy tube along a spine (dog tail): widths per spine point, jagged fur
 * edge. `tipFrom` paints the spine from that index onward in `tip`.
 */
function fluffy(x: CanvasRenderingContext2D, spine: number[][], widths: number[], fill: string, tip: string, tipFrom: number) {
  const outline = (from: number) => {
    const L: number[][] = [];
    const R: number[][] = [];
    for (let i = from; i < spine.length; i++) {
      const p = spine[i];
      const q = spine[Math.min(spine.length - 1, i + 1)];
      const o = spine[Math.max(0, i - 1)];
      const len = Math.hypot(q[0] - o[0], q[1] - o[1]) || 1;
      const tx = (q[0] - o[0]) / len;
      const ty = (q[1] - o[1]) / len;
      const nx = -ty;
      const ny = tx;
      const w = widths[i];
      L.push([p[0] + nx * w * 0.85, p[1] + ny * w * 0.85]);
      R.push([p[0] - nx * w * 0.85, p[1] - ny * w * 0.85]);
      if (i === spine.length - 1) break;
      // Two fur tufts per segment on each side, swept toward the tip.
      for (const k of [0.3, 0.75]) {
        const mx = p[0] + (q[0] - p[0]) * k;
        const my = p[1] + (q[1] - p[1]) * k;
        const mw = (w + (widths[i + 1] - w) * k) * 1.28 + 2;
        L.push([mx + nx * mw + tx * 5, my + ny * mw + ty * 5]);
        L.push([mx + nx * mw * 0.72 + tx * 7, my + ny * mw * 0.72 + ty * 7]);
        R.push([mx - nx * mw + tx * 5, my - ny * mw + ty * 5]);
        R.push([mx - nx * mw * 0.72 + tx * 7, my - ny * mw * 0.72 + ty * 7]);
      }
    }
    const last = spine[spine.length - 1];
    const prev = spine[spine.length - 2];
    const ex = last[0] + (last[0] - prev[0]) * 0.6;
    const ey = last[1] + (last[1] - prev[1]) * 0.6;
    return [...L, [ex, ey], ...R.reverse()];
  };
  poly(x, outline(0), fill, 2.2);
  if (tipFrom < spine.length - 1) poly(x, outline(tipFrom), tip, 2);
}

/** A great curved war horn: a tapering tube from the mouthpiece to a flared, banded bell. */
function warHorn(x: CanvasRenderingContext2D, mx: number, my: number, cx: number, cy: number, bx: number, by: number) {
  const N = 14;
  const pts: number[][] = [];
  for (let i = 0; i <= N; i++) {
    const t = i / N;
    const px = (1 - t) * (1 - t) * mx + 2 * (1 - t) * t * cx + t * t * bx;
    const py = (1 - t) * (1 - t) * my + 2 * (1 - t) * t * cy + t * t * by;
    pts.push([px, py, 2.5 + t * t * 9]);
  }
  const L: number[][] = [];
  const R: number[][] = [];
  pts.forEach((p, i) => {
    const q = pts[Math.min(N, i + 1)];
    const o = pts[Math.max(0, i - 1)];
    const len = Math.hypot(q[0] - o[0], q[1] - o[1]) || 1;
    const nx = -(q[1] - o[1]) / len;
    const ny = (q[0] - o[0]) / len;
    L.push([p[0] + nx * p[2], p[1] + ny * p[2]]);
    R.push([p[0] - nx * p[2], p[1] - ny * p[2]]);
  });
  poly(x, [...L, ...R.reverse()], BONE, 2.2);
  // Brass bands along the horn.
  x.strokeStyle = '#b8862e';
  x.lineWidth = 3;
  for (const i of [4, 8, 11]) {
    x.beginPath();
    x.moveTo(L[i][0], L[i][1]);
    x.lineTo(R[N - i][0], R[N - i][1]);
    x.stroke();
  }
  // The bell's dark mouth.
  const e = pts[N];
  const p = pts[N - 1];
  const ang = Math.atan2(e[1] - p[1], e[0] - p[0]);
  x.save();
  x.translate(e[0], e[1]);
  x.rotate(ang);
  x.beginPath();
  x.ellipse(0, 0, 4, 12, 0, 0, Math.PI * 2);
  x.fillStyle = '#c9b48a';
  x.fill();
  x.lineWidth = 2;
  x.strokeStyle = INK;
  x.stroke();
  x.beginPath();
  x.ellipse(1, 0, 2.2, 8, 0, 0, Math.PI * 2);
  x.fillStyle = '#2a1a10';
  x.fill();
  x.restore();
}

function spear(x: CanvasRenderingContext2D, hx: number, hy: number, ang: number, len: number, rag?: string, fork = false) {
  x.save();
  x.translate(hx, hy);
  x.rotate(ang);
  poly(x, [[-2.4, len * 0.42], [2.4, len * 0.42], [2.4, -len * 0.58], [-2.4, -len * 0.58]], WOOD, 1.8);
  x.fillStyle = shade(WOOD, 0.3);
  x.fillRect(-2, -len * 0.56, 1.4, len * 0.96);
  const t = -len * 0.58;
  if (fork) {
    // Pitchfork: a crossbar and three iron tines.
    poly(x, [[-9, t + 3], [9, t + 3], [9, t - 1], [-9, t - 1]], STEEL_D, 1.6);
    for (const tx of [-7.5, 0, 7.5]) poly(x, [[tx - 1.6, t], [tx + 1.6, t], [tx + 0.6, t - 20], [tx, t - 23], [tx - 0.6, t - 20]], STEEL, 1.2);
    x.restore();
    return;
  }
  poly(x, [[-6, t + 2], [6, t + 2], [3, t - 16], [0, t - 26], [-3, t - 16]], STEEL, 1.8);
  x.fillStyle = '#ffffff';
  x.globalAlpha = 0.55;
  x.fillRect(-1.5, t - 18, 1.4, 16);
  x.globalAlpha = 1;
  if (rag) {
    poly(x, [[-3, t + 4], [3, t + 4], [8, t + 20], [2, t + 16], [-1, t + 26], [-4, t + 14]], rag, 1.4);
  } else {
    x.fillStyle = '#2f58b8';
    x.fillRect(-3, t + 2, 6, 6);
  }
  x.restore();
}

function crossbow(x: CanvasRenderingContext2D, hx: number, hy: number, ang: number, back = false) {
  x.save();
  x.translate(hx, hy);
  x.rotate(ang);
  // Stock along -x (pointing forward/left), prod across.
  poly(x, [[14, -3], [-30, -4], [-34, 0], [-30, 4], [14, 4], [20, 8], [24, 2]], '#8a5a30', 2);
  x.fillStyle = shade('#8a5a30', 0.25);
  x.fillRect(-28, -3, 38, 2);
  x.strokeStyle = INK;
  x.lineWidth = 4.5;
  x.beginPath();
  x.moveTo(-26, -20);
  x.quadraticCurveTo(-36, 0, -26, 20);
  x.stroke();
  x.strokeStyle = '#4a2f1c';
  x.lineWidth = 2.8;
  x.beginPath();
  x.moveTo(-26, -20);
  x.quadraticCurveTo(-36, 0, -26, 20);
  x.stroke();
  x.strokeStyle = '#efe6cf';
  x.lineWidth = 1;
  x.beginPath();
  x.moveTo(-26, -20);
  x.lineTo(-8, 0);
  x.lineTo(-26, 20);
  x.stroke();
  if (!back) {
    poly(x, [[-34, -1.4], [-46, -1.4], [-50, 0], [-46, 1.4], [-34, 1.4]], STEEL, 1);
  }
  x.restore();
}

function bow(x: CanvasRenderingContext2D, hx: number, hy: number, drawn: boolean) {
  x.save();
  x.translate(hx, hy);
  x.strokeStyle = INK;
  x.lineWidth = 5;
  x.beginPath();
  x.moveTo(4, -34);
  x.quadraticCurveTo(-14, 0, 4, 34);
  x.stroke();
  x.strokeStyle = '#6b4426';
  x.lineWidth = 3;
  x.beginPath();
  x.moveTo(4, -34);
  x.quadraticCurveTo(-14, 0, 4, 34);
  x.stroke();
  x.strokeStyle = '#efe6cf';
  x.lineWidth = 1;
  x.beginPath();
  x.moveTo(4, -34);
  x.lineTo(drawn ? 22 : 6, 0);
  x.lineTo(4, 34);
  x.stroke();
  if (drawn) {
    x.strokeStyle = '#5a3a22';
    x.lineWidth = 2;
    x.beginPath();
    x.moveTo(-22, 0);
    x.lineTo(22, 0);
    x.stroke();
    poly(x, [[-22, -2], [-30, 0], [-22, 2]], STEEL, 1);
    x.fillStyle = '#b3261c';
    x.fillRect(16, -3, 7, 6);
  }
  x.restore();
}

function kiteShield(x: CanvasRenderingContext2D, cx: number, cy: number, s: number, back: boolean, st: Style) {
  x.save();
  x.translate(cx, cy);
  x.scale(s, s);
  const path = () => {
    x.beginPath();
    x.moveTo(-17, -26);
    x.quadraticCurveTo(0, -31, 17, -26);
    x.lineTo(16, 2);
    x.quadraticCurveTo(10, 22, 0, 32);
    x.quadraticCurveTo(-10, 22, -16, 2);
    x.closePath();
  };
  if (back) {
    cel(x, path, '#8a6038', 4, 2.6);
    x.strokeStyle = shade('#8a6038', -0.4);
    x.lineWidth = 1.2;
    for (let i = -10; i <= 10; i += 7) {
      x.beginPath();
      x.moveTo(i, -26);
      x.lineTo(i * 0.7, 26);
      x.stroke();
    }
    poly(x, [[-12, -6], [12, -6], [12, 0], [-12, 0]], LEATHER, 1.6);
  } else {
    cel(x, path, st.tabard, 3, 2.6, -0.3, 0.12);
    // Steel (or gilded) rim.
    path();
    x.lineWidth = 3.4;
    x.strokeStyle = st.gold ?? STEEL_D;
    x.stroke();
    path();
    x.lineWidth = 1.4;
    x.strokeStyle = INK;
    x.stroke();
    if (st.emblem === 'eagle') eagle(x, 0, -2, st.gold ? 1.05 : 0.9, st.gold);
    // Wear scratches.
    x.strokeStyle = 'rgba(255,255,255,0.35)';
    x.lineWidth = 1;
    x.beginPath();
    x.moveTo(-10, 10);
    x.lineTo(-6, 14);
    x.moveTo(8, -18);
    x.lineTo(11, -14);
    x.stroke();
  }
  x.restore();
}

function roundShield(x: CanvasRenderingContext2D, cx: number, cy: number, r: number, back: boolean) {
  x.save();
  x.translate(cx, cy);
  const path = () => {
    x.beginPath();
    x.ellipse(0, 0, r * 0.82, r, 0, 0, Math.PI * 2);
  };
  if (back) {
    cel(x, path, '#6b4426', 2, 2.6);
    poly(x, [[-r * 0.6, -4], [r * 0.6, -4], [r * 0.6, 2], [-r * 0.6, 2]], '#3a2614', 1.5);
  } else {
    cel(x, path, '#9a2a1c', 2, 2.6, -0.3, 0.1);
    x.save();
    path();
    x.clip();
    // Black war sigil.
    x.fillStyle = '#1e1310';
    x.beginPath();
    for (let i = 0; i < 4; i++) {
      const a = (i / 4) * Math.PI * 2 + 0.4;
      x.moveTo(0, 0);
      x.lineTo(Math.cos(a) * r * 0.9, Math.sin(a) * r * 0.9);
      x.lineTo(Math.cos(a + 0.35) * r * 0.3, Math.sin(a + 0.35) * r * 0.3);
    }
    x.fill();
    x.restore();
    path();
    x.lineWidth = 4;
    x.strokeStyle = STEEL_D;
    x.stroke();
    path();
    x.lineWidth = 1.6;
    x.strokeStyle = INK;
    x.stroke();
    x.fillStyle = STEEL;
    x.beginPath();
    x.ellipse(0, 0, 6, 7, 0, 0, Math.PI * 2);
    x.fill();
    x.stroke();
  }
  x.restore();
}

function eagle(x: CanvasRenderingContext2D, cx: number, cy: number, s: number, col = '#f2efe4') {
  x.save();
  x.translate(cx, cy);
  x.scale(s, s);
  x.fillStyle = col;
  x.beginPath();
  // Spread wings, body and tail.
  x.moveTo(0, -12);
  x.lineTo(3, -8);
  x.lineTo(13, -12);
  x.lineTo(11, -6);
  x.lineTo(15, -5);
  x.lineTo(9, 0);
  x.lineTo(3, 0);
  x.lineTo(4, 8);
  x.lineTo(0, 12);
  x.lineTo(-4, 8);
  x.lineTo(-3, 0);
  x.lineTo(-9, 0);
  x.lineTo(-15, -5);
  x.lineTo(-11, -6);
  x.lineTo(-13, -12);
  x.lineTo(-3, -8);
  x.closePath();
  x.fill();
  x.restore();
}

// ---------------------------------------------------------------- heads

function head(x: CanvasRenderingContext2D, cx: number, cy: number, s: Style, back: boolean, rng: Rng) {
  if (s.kind === 'dog') {
    dogHead(x, cx, cy, s, back);
    return;
  }
  const r = s.kind === 'goblin' ? 15 : s.kind === 'orc' ? 15.5 * Math.min(1.2, s.bulk * 0.85) : 15;
  // Long hair falls behind the head onto the shoulders.
  if (s.kind === 'human' && !s.hood && s.hairStyle === 'long') {
    x.beginPath();
    if (back) {
      x.moveTo(cx - r * 1.04, cy - r * 0.2);
      x.lineTo(cx - r * 1.12, cy + r * 1.2);
      x.quadraticCurveTo(cx, cy + r * 1.6, cx + r * 1.12, cy + r * 1.2);
      x.lineTo(cx + r * 1.04, cy - r * 0.2);
    } else {
      x.moveTo(cx - r * 0.85, cy);
      x.lineTo(cx - r * 0.95, cy + r * 1.1);
      x.quadraticCurveTo(cx + r * 0.3, cy + r * 1.45, cx + r * 1.3, cy + r * 1.15);
      x.lineTo(cx + r * 1.06, cy - r * 0.3);
    }
    x.closePath();
    x.fillStyle = s.hair;
    x.fill();
    x.lineWidth = 2.2;
    x.strokeStyle = INK;
    x.stroke();
  }
  // Ears behind the head for goblins and orcs.
  const earLen = (s.kind === 'goblin' ? 18 : 10) * (s.ears ?? 1);
  if (s.kind === 'goblin' || s.kind === 'orc') {
    for (const side of back ? [-1, 1] : [1]) {
      poly(x, [[cx + side * r * 0.6, cy - 4], [cx + side * (r + earLen), cy - 10], [cx + side * r * 0.7, cy + 4]], s.skin, 2);
    }
  }
  const skull = () => {
    x.beginPath();
    x.ellipse(cx, cy, r, r * 1.08, 0, 0, Math.PI * 2);
  };
  cel(x, skull, back ? (s.hood ?? (s.hairStyle === 'shaved' || s.mohawk ? s.skin : s.hair)) : s.skin, cx + r * 0.25, 2.4, -0.25, 0.12);
  if (s.earring) {
    x.strokeStyle = GOLD;
    x.lineWidth = 2;
    for (const side of back ? [-1, 1] : [1]) {
      x.beginPath();
      x.arc(cx + side * (r + earLen * 0.35), cy + 1, 3, 0, Math.PI * 2);
      x.stroke();
    }
  }
  if (!back) {
    // Face features shifted toward the facing side (left).
    const fx = cx - r * 0.32;
    if (s.warpaint && s.paint === 'mask') {
      // Painted band across the eyes, under the features.
      x.save();
      skull();
      x.clip();
      x.fillStyle = s.warpaint;
      x.fillRect(cx - r - 2, cy - 8, r * 2 + 4, 8);
      x.restore();
    }
    if (s.kind === 'goblin') {
      // Long nose, yellow eyes, fangs.
      const n = s.nose ?? 1;
      poly(x, [[fx - 2, cy - 2], [fx - 14 * n, cy + 6 + (n - 1) * 5], [fx - 1, cy + 6]], shade(s.skin, -0.1), 1.8);
      x.fillStyle = '#ffd94a';
      x.fillRect(fx - 6, cy - 5, 4, 3);
      x.fillRect(fx + 3, cy - 5, 4, 3);
      x.fillStyle = '#1a120c';
      x.fillRect(fx - 5, cy - 5, 2, 3);
      x.fillRect(fx + 4, cy - 5, 2, 3);
      x.fillStyle = '#f2ecdc';
      poly(x, [[fx - 3, cy + 9], [fx - 1, cy + 13], [fx + 1, cy + 9]], '#f2ecdc', 1);
    } else if (s.kind === 'orc') {
      x.fillStyle = '#ffcf3a';
      x.fillRect(fx - 6, cy - 4, 5, 3);
      x.fillRect(fx + 4, cy - 4, 5, 3);
      x.fillStyle = '#1a120c';
      x.fillRect(fx - 5, cy - 4, 2, 3);
      x.fillRect(fx + 5, cy - 4, 2, 3);
      // Heavy brow and tusks.
      x.strokeStyle = INK;
      x.lineWidth = 2.6;
      x.beginPath();
      x.moveTo(fx - 9, cy - 8);
      x.lineTo(fx + 10, cy - 7);
      x.stroke();
      if (s.beard && s.beardStyle === 'chin') {
        // Short braided chin beard under the tusks.
        poly(x, [[fx - 9, cy + 9], [fx + 9, cy + 10], [fx + 2, cy + 20], [fx - 1, cy + 26], [fx - 4, cy + 19]], '#1a1410', 1.6);
      } else if (s.beard) {
        poly(x, [[cx - r * 0.9, cy + 6], [cx + r * 0.6, cy + 8], [cx - 2, cy + r + 10]], '#1a1410', 1.8);
      }
      const tk = s.tusks ?? 1;
      poly(x, [[fx - 4 - 2 * tk, cy + 9], [fx - 4, cy + 9 - 8 * tk], [fx - 4 + 2 * tk, cy + 9]], '#efe6cf', 1.4);
      poly(x, [[fx + 6 - 2 * tk, cy + 9], [fx + 6, cy + 9 - 8 * tk], [fx + 6 + 2 * tk, cy + 9]], '#efe6cf', 1.4);
    } else {
      x.fillStyle = '#2a1a10';
      x.fillRect(fx - 5, cy - 3, 3, 3.5);
      x.fillRect(fx + 4, cy - 3, 3, 3.5);
      x.fillStyle = shade(s.skin, -0.18);
      x.fillRect(fx - 1, cy + 1, 3, 5);
      x.strokeStyle = shade(s.skin, -0.45);
      x.lineWidth = 1.6;
      x.beginPath();
      x.moveTo(fx - 3, cy + 8);
      x.lineTo(fx + 3, cy + 8);
      x.stroke();
      if (s.beard && s.beardStyle === 'chin') {
        // Moustache and pointed chin beard.
        poly(x, [[fx - 6, cy + 6.5], [fx + 5, cy + 6.5], [fx + 3, cy + 9], [fx - 4, cy + 9]], s.hair, 1.4);
        poly(x, [[fx - 5, cy + 10], [fx + 4, cy + 10], [fx - 1, cy + 19]], s.hair, 1.6);
      } else if (s.beard) {
        x.save();
        x.beginPath();
        x.ellipse(cx - 1, cy + 7, r * 0.95, r * 0.75, 0, 0, Math.PI);
        x.fillStyle = s.hair;
        x.fill();
        x.lineWidth = 2;
        x.strokeStyle = INK;
        x.stroke();
        x.restore();
        x.strokeStyle = shade(s.skin, -0.45);
        x.beginPath();
        x.moveTo(fx - 3, cy + 7);
        x.lineTo(fx + 3, cy + 7);
        x.stroke();
      }
    }
    if (s.warpaint && s.paint === 'claw') {
      // Three raked stripes down over the eye.
      x.strokeStyle = s.warpaint;
      x.lineWidth = 2.2;
      for (let i = 0; i < 3; i++) {
        x.beginPath();
        x.moveTo(fx - 8 + i * 5, cy - 11);
        x.lineTo(fx - 5 + i * 5, cy + 5);
        x.stroke();
      }
    } else if (s.warpaint && s.paint !== 'mask') {
      x.strokeStyle = s.warpaint;
      x.lineWidth = 2.4;
      x.beginPath();
      x.moveTo(fx + 6, cy - 9);
      x.lineTo(fx + 10, cy + 6);
      x.stroke();
    }
  }
  // Hair, hoods and helmets.
  if (s.hood) {
    x.save();
    x.beginPath();
    x.ellipse(cx + 1, cy - 2, r * 1.28, r * 1.35, 0, Math.PI * 0.95, Math.PI * 2.05);
    x.lineTo(cx + r * 1.3, cy + r * 0.9);
    x.lineTo(cx - r * 1.2, cy + r * 0.9);
    x.closePath();
    if (!back) {
      // Open face.
      x.moveTo(cx - r * 0.95, cy + r * 0.5);
      x.ellipse(cx - r * 0.3, cy + 1, r * 0.72, r * 0.82, 0, Math.PI, Math.PI * 3, false);
    }
    x.fillStyle = s.hood;
    x.fill('evenodd');
    x.lineWidth = 2.4;
    x.strokeStyle = INK;
    x.stroke();
    x.restore();
    // Hood point.
    poly(x, [[cx + r * 0.4, cy - r * 1.25], [cx + r * 1.4, cy - r * 1.6], [cx + r * 1.1, cy - r * 0.8]], s.hood, 2);
    if (s.hornHood) {
      // Bone horns lashed to the hood.
      poly(x, [[cx - r * 0.65, cy - r * 1.0], [cx - r * 0.95, cy - r * 1.6], [cx - r * 0.75, cy - r * 2.4], [cx - r * 0.45, cy - r * 1.7], [cx - r * 0.2, cy - r * 1.2]], BONE, 1.6);
      poly(x, [[cx + r * 0.15, cy - r * 1.25], [cx + r * 0.45, cy - r * 1.85], [cx + r * 0.9, cy - r * 2.45], [cx + r * 0.85, cy - r * 1.75], [cx + r * 0.65, cy - r * 1.15]], BONE, 1.6);
    }
  } else if (s.helmet === 'orc' || s.helmet === 'goblin' || s.helmet === 'horned') {
    const hr = r * 1.1;
    if (s.helmet === 'horned') {
      for (const side of [-1, 1]) {
        poly(
          x,
          [
            [cx + side * hr * 0.75, cy - hr * 0.35],
            [cx + side * hr * 1.35, cy - hr * 0.75],
            [cx + side * hr * 1.45, cy - hr * 1.65],
            [cx + side * hr * 1.1, cy - hr * 0.95],
            [cx + side * hr * 0.6, cy - hr * 0.75],
          ],
          BONE,
          1.8,
        );
      }
    }
    x.save();
    x.beginPath();
    x.ellipse(cx, cy - 3, hr, hr * 0.95, 0, Math.PI, 0);
    x.lineTo(cx + hr, cy + 2);
    x.lineTo(cx - hr, cy + 2);
    x.closePath();
    x.fillStyle = '#8f969c';
    x.fill();
    x.lineWidth = 2.4;
    x.strokeStyle = INK;
    x.stroke();
    x.fillStyle = 'rgba(255,255,255,0.4)';
    x.fillRect(cx - hr * 0.6, cy - hr * 0.7, 4, hr * 0.5);
    x.restore();
    if (!back) poly(x, [[cx - r * 0.4, cy - 2], [cx - r * 0.2, cy + 9], [cx, cy - 2]], '#8f969c', 1.6);
    if (s.plume && s.helmet !== 'horned') {
      for (let i = 0; i < 6; i++) {
        poly(x, [[cx - 2 + i, cy - hr - 2], [cx + 6 + i * 3, cy - hr - 18 - (i % 2) * 4], [cx + 4 + i * 2, cy - hr + 2]], i % 2 ? s.plume : shade(s.plume, -0.25), 1.2);
      }
    }
    if (s.kind === 'goblin') {
      poly(x, [[cx + hr * 0.4, cy - hr * 0.6], [cx + hr * 0.9, cy - hr * 1.4], [cx + hr * 0.75, cy - hr * 0.4]], '#e9dcc0', 1.4);
    }
  } else if (s.helmet === 'kettle') {
    // A steel kettle hat: a round crown over a wide brim, the plume at its crest.
    const hr = r * 1.06;
    if (s.plume) {
      for (let i = 0; i < 5; i++) {
        poly(x, [[cx - 3 + i * 1.5, cy - hr - 1], [cx + 8 + i * 3, cy - hr - 16 - (i % 2) * 4], [cx + 4 + i * 2, cy - hr + 3]], i % 2 ? s.plume : shade(s.plume, -0.2), 1.2);
      }
    }
    x.beginPath();
    x.ellipse(cx, cy - 4, hr, hr * 0.95, 0, Math.PI, 0);
    x.closePath();
    x.fillStyle = STEEL;
    x.fill();
    x.lineWidth = 2.2;
    x.strokeStyle = INK;
    x.stroke();
    x.fillStyle = 'rgba(255,255,255,0.5)';
    x.fillRect(cx - hr * 0.55, cy - hr * 0.78, 3.5, hr * 0.5);
    x.beginPath();
    x.ellipse(cx, cy - 3, hr * 1.5, hr * 0.3, 0, 0, Math.PI * 2);
    x.fillStyle = STEEL_D;
    x.fill();
    x.lineWidth = 2;
    x.stroke();
    x.strokeStyle = 'rgba(255,255,255,0.45)';
    x.lineWidth = 1.2;
    x.beginPath();
    x.ellipse(cx, cy - 3.6, hr * 1.36, hr * 0.2, 0, Math.PI * 1.05, Math.PI * 1.6);
    x.stroke();
  } else if (s.kind === 'human') {
    if (s.hairStyle === 'shaved') {
      // Close-cropped scalp: a stubble tint over the top of the skull.
      x.save();
      skull();
      x.clip();
      x.globalAlpha = 0.55;
      x.fillStyle = s.hair;
      x.beginPath();
      if (back) x.rect(cx - r - 2, cy - r - 4, r * 2 + 4, r * 1.6);
      else x.ellipse(cx + 3, cy - r * 0.55, r * 1.05, r * 0.62, 0, 0, Math.PI * 2);
      x.fill();
      x.restore();
    } else {
      if (s.hairStyle === 'spiky') {
        // Tufts sticking up from the crown; the cap covers their roots.
        for (let i = 0; i < 6; i++) {
          const a = Math.PI * (1.02 + i * 0.17);
          const bx = cx + 2 + Math.cos(a) * r * 0.95;
          const by = cy - 4 + Math.sin(a) * r * 0.82;
          const tx = cx + 2 + Math.cos(a + 0.12) * r * 1.42;
          const ty = cy - 4 + Math.sin(a + 0.12) * r * 1.25;
          poly(x, [[bx - 4, by + 2], [tx, ty], [bx + 4, by + 1]], s.hair, 1.6);
        }
      }
      // Hair: cap plus a fringe; from behind, the whole back of the head.
      x.save();
      x.beginPath();
      if (back) {
        x.ellipse(cx, cy - 1, r * 1.04, r * 1.12, 0, 0, Math.PI * 2);
      } else {
        x.ellipse(cx + 2, cy - 4, r * 1.05, r * 0.9, 0, Math.PI * 0.95, Math.PI * 2.15);
        x.lineTo(cx + r * 0.95, cy + 2);
      }
      x.fillStyle = s.hair;
      x.fill();
      x.lineWidth = 2.2;
      x.strokeStyle = INK;
      x.stroke();
      x.restore();
      x.strokeStyle = shade(s.hair, 0.35);
      x.lineWidth = 1.4;
      for (let i = 0; i < 4; i++) {
        x.beginPath();
        const hx = cx - r * 0.6 + i * r * 0.4 + rng.range(-1, 1);
        x.moveTo(hx, cy - r * 0.9);
        x.lineTo(hx - 3, cy - r * 0.4);
        x.stroke();
      }
    }
  } else if (s.kind === 'orc') {
    if (s.mohawk) {
      // Black hair tail at the back of the head, then a tall red feather crest over the scalp.
      poly(x, back ? [[cx - 5, cy - r * 0.6], [cx + 5, cy - r * 0.6], [cx + 7, cy + r * 1.3], [cx, cy + r * 1.6], [cx - 6, cy + r * 1.2]] : [[cx + r * 0.5, cy - r * 0.7], [cx + r * 0.95, cy - r * 0.3], [cx + r * 1.35, cy + r * 1.2], [cx + r * 0.9, cy + r * 1.5], [cx + r * 0.75, cy + r * 0.3]], s.hair, 1.8);
      const plume = s.plume ?? '#b3261c';
      for (let i = 0; i < 9; i++) {
        const f = i / 8;
        const a = Math.PI * (1.18 + f * 0.62);
        const bx = cx + Math.cos(a) * r * 0.9;
        const by = cy + Math.sin(a) * r * 0.98;
        const len = (14 + Math.sin(f * Math.PI) * 14) * s.mohawk;
        const ta = a + 0.3;
        poly(x, [[bx - 3.5, by + 3], [bx + Math.cos(ta) * len, by + Math.sin(ta) * len], [bx + 3.5, by + 3]], i % 2 ? plume : shade(plume, -0.25), 1.2);
      }
      // Black roots along the scalp.
      x.strokeStyle = s.hair;
      x.lineWidth = 4;
      x.beginPath();
      x.ellipse(cx, cy, r * 0.9, r * 0.98, 0, Math.PI * 1.18, Math.PI * 1.8);
      x.stroke();
    } else {
      // Top-knot.
      poly(x, [[cx - 4, cy - r], [cx + 4, cy - r], [cx + 10, cy - r - 16], [cx + 2, cy - r - 10]], s.hair, 1.8);
      if (s.plume) {
        for (let i = 0; i < 5; i++) poly(x, [[cx + 2, cy - r - 8], [cx + 12 + i * 3, cy - r - 28 + i * 2], [cx + 6 + i, cy - r - 6]], i % 2 ? s.plume : shade(s.plume, -0.25), 1.2);
      }
    }
  }
  if (s.headRag) {
    // Red rag knotted round the head, tails fluttering behind.
    const y0 = cy - r * (s.hood ? 0.62 : 0.5);
    poly(x, [[cx - r * 1.12, y0 + 1], [cx + r * 1.18, y0 - 3], [cx + r * 1.2, y0 + 5], [cx - r * 1.08, y0 + 8]], s.headRag, 1.6);
    const kx = back ? cx - 2 : cx + r * 1.1;
    poly(x, [[kx, y0], [kx + 16, y0 + 8], [kx + 10, y0 + 11], [kx + 1, y0 + 6]], s.headRag, 1.4);
    poly(x, [[kx, y0 + 4], [kx + 8, y0 + 20], [kx + 3, y0 + 19], [kx - 2, y0 + 8]], shade(s.headRag, -0.25), 1.4);
  }
}

/** Border collie head: black (or brown) skull, white blaze and muzzle, folded or pricked ears. */
function dogHead(x: CanvasRenderingContext2D, cx: number, cy: number, s: Style, back: boolean) {
  const d = s.dog!;
  const r = 15;
  const ear = (side: number) => {
    // Set on the sides of the crown and angled outward.
    const bx = cx + side * r * 0.6 + (back ? 0 : -2);
    const by = cy - r * 0.62;
    const inner = bx - side * 6;
    const outer = bx + side * 8;
    if (d.ears === 'prick') {
      poly(x, [[inner, by + 4], [bx + side * 6, by - 19], [outer, by + 5]], d.coat, 2);
      poly(x, [[inner + side * 3, by + 2], [bx + side * 5, by - 12], [outer - side * 3, by + 3]], '#6a4a44', 0);
    } else {
      // Semi-erect: the ear rises to a crease, then its tip flops forward and out.
      poly(x, [[inner, by + 5], [bx + side * 2, by - 13], [bx + side * 7, by - 15], [bx + side * 17, by - 4], [bx + side * 9, by - 5], [outer, by + 6]], d.coat, 2);
      x.strokeStyle = shade(d.coat, 0.35);
      x.lineWidth = 1.4;
      x.beginPath();
      x.moveTo(bx + side * 3, by - 11);
      x.lineTo(bx + side * 9, by - 6);
      x.stroke();
    }
  };
  // Muzzle peeking past the cheek when seen from behind (facing up-right).
  if (back) {
    x.beginPath();
    x.ellipse(cx + r * 0.95, cy + 2, 8, 6, -0.3, 0, Math.PI * 2);
    x.fillStyle = d.white;
    x.fill();
    x.lineWidth = 2;
    x.strokeStyle = INK;
    x.stroke();
    x.beginPath();
    x.ellipse(cx + r + 6, cy - 1, 3, 2.6, 0, 0, Math.PI * 2);
    x.fillStyle = '#151213';
    x.fill();
  }
  ear(-1);
  ear(1);
  const skullPath = () => {
    x.beginPath();
    x.ellipse(cx, cy, r * 1.06, r * 1.02, 0, 0, Math.PI * 2);
  };
  cel(x, skullPath, d.coat, cx + r * 0.3, 2.4, -0.3, 0.2);
  // Messy fur on the crown.
  poly(x, [[cx - r * 0.7, cy - r * 0.6], [cx - r * 0.45, cy - r * 1.22], [cx - r * 0.15, cy - r * 0.9], [cx + r * 0.15, cy - r * 1.28], [cx + r * 0.4, cy - r * 0.88], [cx + r * 0.7, cy - r * 1.1], [cx + r * 0.75, cy - r * 0.55]], d.coat, 1.6);
  if (back) {
    // White collar fur shows below the skull at the nape.
    return;
  }
  const fx = cx - r * 0.3;
  const bl = d.blaze;
  x.save();
  skullPath();
  x.clip();
  // White blaze down the forehead widening into the cheeks.
  x.fillStyle = d.white;
  x.beginPath();
  x.moveTo(fx - 2 * bl, cy - r * 1.1);
  x.lineTo(fx + 2.5 * bl, cy - r * 1.1);
  x.lineTo(fx + 4 * bl, cy - 6);
  x.quadraticCurveTo(fx + 9, cy + 2, fx + 8, cy + r);
  x.lineTo(fx - 14, cy + r);
  x.quadraticCurveTo(fx - 9, cy + 1, fx - 3.5 * bl, cy - 6);
  x.closePath();
  x.fill();
  if (d.tan) {
    x.fillStyle = d.tan;
    x.beginPath();
    x.ellipse(fx - 6.5, cy - 8, 2.6, 1.8, 0, 0, Math.PI * 2);
    x.ellipse(fx + 8, cy - 9, 2.6, 1.8, 0, 0, Math.PI * 2);
    x.fill();
    x.beginPath();
    x.ellipse(fx + 10, cy + 4, 3.5, 3, 0, 0, Math.PI * 2);
    x.fill();
  }
  x.restore();
  // Amber eyes on either side of the blaze.
  for (const [ex, ey] of [[fx - 6.5, cy - 3.5], [fx + 7.5, cy - 4.5]]) {
    x.beginPath();
    x.ellipse(ex, ey, 2.8, 2.2, 0, 0, Math.PI * 2);
    x.fillStyle = '#e2a12e';
    x.fill();
    x.lineWidth = 1.2;
    x.strokeStyle = INK;
    x.stroke();
    x.fillStyle = '#1a120c';
    x.fillRect(ex - 1, ey - 1.6, 2, 3);
  }
  // Muzzle pointing toward the facing side.
  const tipX = cx - r - 10;
  x.beginPath();
  x.moveTo(fx + 3, cy - 2);
  x.quadraticCurveTo(fx - 8, cy - 2, tipX + 2, cy + 1);
  x.quadraticCurveTo(tipX - 3, cy + 6, tipX + 2, cy + 10);
  x.quadraticCurveTo(fx - 6, cy + 14, fx + 5, cy + 11);
  x.closePath();
  x.fillStyle = d.white;
  x.fill();
  x.lineWidth = 2;
  x.strokeStyle = INK;
  x.stroke();
  x.strokeStyle = shade(d.white, -0.3);
  x.lineWidth = 1.4;
  x.beginPath();
  x.moveTo(tipX + 4, cy + 8);
  x.lineTo(fx - 1, cy + 9);
  x.stroke();
  // Nose.
  x.beginPath();
  x.ellipse(tipX + 1, cy + 2.5, 4.2, 3.4, 0, 0, Math.PI * 2);
  x.fillStyle = '#151213';
  x.fill();
  x.fillStyle = 'rgba(255,255,255,0.5)';
  x.fillRect(tipX - 1, cy + 0.5, 2, 1.4);
}

// ---------------------------------------------------------------- body

export function drawFigure(x: CanvasRenderingContext2D, type: string, pose: Pose, variant: number) {
  const s = styleFor(type, variant);
  const rng = new Rng(variant * 31 + type.length);
  if (s.kind === 'wolf') {
    drawWolfRider(x, s, pose, rng);
    return;
  }
  if (s.kind === 'horse') {
    drawHorseRider(x, s, pose, rng);
    return;
  }
  if (pose === 'dead') {
    const logSeed = rng.state + 11;
    // Lying on the ground: the idle figure rotated onto its back and flattened into the ground plane.
    x.save();
    // The troll is long enough lying down that it is shifted to stay centred.
    x.translate(s.kind === 'troll' ? 92 : 0, -6);
    x.scale(1, 0.62);
    x.rotate(-Math.PI / 2 + 0.12);
    x.translate(30 * s.height, 0);
    drawBody(x, s, 'dead', rng);
    x.restore();
    // Dropped weapon beside the body.
    x.save();
    x.translate(26, -8);
    x.scale(1, 0.5);
    if (s.weapon === 'sword') sword(x, 0, 0, 1.2, 46);
    else if (s.weapon === 'knife') sword(x, 0, 0, 1.2, 22);
    else if (s.weapon === 'horn') warHorn(x, -10, 0, 6, 16, 24, -6);
    else if (s.weapon === 'spear' || s.weapon === 'gspear') spear(x, 0, 0, 1.35, 110, s.rags, s.fork);
    else if (s.weapon === 'cleaver') cleaver(x, 0, 0, 1.2);
    else if (s.weapon === 'mace') mace(x, 0, 0, 1.3);
    else if (s.weapon === 'club') club(x, 0, 0, 1.3);
    else if (s.weapon === 'log' && s.troll) trollLog(x, -70, 34, 104, 24, s.troll, logSeed);
    x.restore();
    return;
  }
  drawBody(x, s, pose, rng);
}

function drawBody(x: CanvasRenderingContext2D, s: Style, pose: Pose, rng: Rng) {
  if (s.kind === 'troll') {
    drawTroll(x, s, pose, rng);
    return;
  }
  const H = s.height;
  const B = s.bulk;
  const back = pose === 'idle_b' || pose === 'atk_b' || pose === 'flee_b' || pose === 'idle_bs' || pose === 'atk_bs';
  const atk = pose === 'atk_f' || pose === 'atk_b' || pose === 'atk_fs' || pose === 'atk_bs';
  const flee = pose === 'flee_b';
  const lead = (pose === 'idle_fs' || pose === 'atk_fs' || pose === 'idle_bs' || pose === 'atk_bs') && (s.shield === 'kite' || s.shield === 'round');
  const hunch = s.kind === 'goblin' ? 8 : s.kind === 'orc' ? 5 : 0;
  // Key heights.
  const hip = -46 * H;
  const shoulder = -100 * H + (s.kind === 'goblin' ? 8 : 0);
  const neck = shoulder - 6;
  const headY = shoulder - 21 * (s.kind === 'goblin' ? 0.92 : 1) + (s.kind === 'goblin' ? 4 : 0);
  const sw = 28 * B; // half shoulder width
  const hw = 21 * B; // half hip width
  // Facing offset: front views lean the chest toward the left (facing side).
  const lean = back ? 3 : -3;
  const legSpread = flee ? 22 : atk ? 18 : 14;
  const dog = s.dog;
  const gold = s.gold ?? GOLD;

  // Bushy tail behind the body (front views).
  if (dog && !back) {
    fluffy(x, [[hw - 6, hip + 4], [hw + 6, hip + 4], [hw + 17, hip + 10], [hw + 24, hip + 20], [hw + 27, hip + 31], [hw + 25, hip + 41]], [4, 7, 10, 12, 11, 7], dog.coat, dog.white, 4);
  }

  // Banner pole and cloth behind the body (warlord).
  if (s.banner) {
    const bx = back ? -6 : 10;
    poly(x, [[bx - 2.5, hip], [bx + 2.5, hip], [bx + 2.5, shoulder - 70], [bx - 2.5, shoulder - 70]], WOOD, 1.8);
    poly(x, [[bx + 2, shoulder - 66], [bx + 46, shoulder - 62], [bx + 38, shoulder - 40], [bx + 48, shoulder - 20], [bx + 2, shoulder - 26]], '#9a2418', 2.2);
    x.fillStyle = '#1e1310';
    x.beginPath();
    x.arc(bx + 22, shoulder - 44, 7, 0, Math.PI * 2);
    x.fill();
  }

  // Quiver on the back (visible from behind, peeks out from the front).
  if (s.quiver) {
    const qx = back ? -4 : 14 * B;
    x.save();
    x.translate(qx, shoulder + 26);
    x.rotate(back ? -0.35 : 0.35);
    poly(x, [[-6, -30], [6, -30], [7, 14], [-7, 14]], s.quiver, 2);
    for (let i = 0; i < 4; i++) poly(x, [[-5 + i * 3.5, -30], [-3 + i * 3.5, -42], [-1 + i * 3.5, -30]], i % 2 ? '#efe6cf' : (s.kind === 'goblin' ? '#b3261c' : '#efe6cf'), 1);
    x.restore();
  }

  // Legs and boots.
  const lx = -legSpread * 0.5 * B;
  const rx = legSpread * 0.5 * B;
  const footDir = back ? 1 : -1;
  const kneeOut = flee ? 10 : 4;
  const kneeCop = (ax: number, ay: number, bx: number, by: number) => {
    // Plate knee guard halfway down the leg.
    if (!s.plate) return;
    const kx = (ax + bx) / 2;
    const ky = (ay + by) / 2 + 2;
    x.beginPath();
    x.ellipse(kx, ky, 7.5 * B, 6, 0, 0, Math.PI * 2);
    x.fillStyle = shade(s.trousers, 0.12);
    x.fill();
    x.lineWidth = 2;
    x.strokeStyle = gold;
    x.stroke();
  };
  limb(x, rx * 0.6, hip + 4, rx + kneeOut * 0.3, -18, 19 * B, s.trousers);
  kneeCop(rx * 0.6, hip + 4, rx + kneeOut * 0.3, -18);
  boot(x, rx + kneeOut * 0.3, flee ? -6 : 0, footDir, s);
  limb(x, lx * 0.6, hip + 4, lx - kneeOut * 0.4, -18, 19 * B, s.trousers);
  kneeCop(lx * 0.6, hip + 4, lx - kneeOut * 0.4, -18);
  boot(x, lx - kneeOut * 0.4, flee ? 2 : 0, footDir, s);

  // Back arm (behind the torso).
  const backArm = () => {
    if (back) {
      // From behind: the shield (or bow) arm is on the left.
      if (s.shield === 'kite' || s.shield === 'round' || s.weapon === 'club') return;
      limb(x, -sw + 4, shoulder + 6, -sw - 6, shoulder + 34, 11 * B, s.tunic);
    } else {
      // From the front, the weapon arm is on the left (toward the facing side).
    }
  };
  backArm();

  // Torso: tunic, tabard, belt.
  const torso = () => {
    x.beginPath();
    x.moveTo(-sw + lean, shoulder + hunch * 0.4);
    x.quadraticCurveTo(lean, shoulder - 6, sw + lean, shoulder + hunch * 0.4);
    x.lineTo(hw + 3, hip + 8);
    x.lineTo(hw + 6, hip + 26);
    x.lineTo(-hw - 6, hip + 26);
    x.lineTo(-hw - 3, hip + 8);
    x.closePath();
  };
  if (s.fur) {
    // Fur mantle behind the shoulders.
    x.save();
    x.beginPath();
    for (let i = 0; i <= 10; i++) {
      const a = Math.PI + (i / 10) * Math.PI;
      const rr = sw * 1.25 + (i % 2) * 5;
      x.lineTo(lean + Math.cos(a) * rr, shoulder + 6 + Math.sin(a) * 14);
    }
    x.closePath();
    x.fillStyle = s.fur;
    x.fill();
    x.lineWidth = 2;
    x.strokeStyle = INK;
    x.stroke();
    x.restore();
  }
  cel(x, torso, s.tunic, lean + sw * 0.35, 2.6, -0.25, 0.15);
  if (s.plate) {
    // Breastplate: gilded neckline, a lit ridge and the lames of the fauld below the belt.
    x.strokeStyle = gold;
    x.lineWidth = 2.4;
    x.beginPath();
    x.moveTo(-sw * 0.82 + lean, shoulder + 3);
    x.quadraticCurveTo(lean, shoulder + 9, sw * 0.82 + lean, shoulder + 3);
    x.stroke();
    x.strokeStyle = shade(s.tunic, 0.3);
    x.lineWidth = 1.6;
    for (const ly of [hip + 13, hip + 20]) {
      x.beginPath();
      x.moveTo(-hw - 4, ly);
      x.lineTo(hw + 4, ly);
      x.stroke();
    }
    x.fillStyle = 'rgba(255,255,255,0.16)';
    x.fillRect(lean - sw * 0.62, shoulder + 12, 4, (hip - shoulder) * 0.55);
  }
  if (s.bare) {
    // Bare muscled torso under a crossed leather harness.
    x.strokeStyle = shade(s.skin, -0.38);
    x.lineWidth = 1.8;
    if (!back) {
      x.beginPath();
      x.moveTo(lean - sw * 0.72, shoulder + 19);
      x.quadraticCurveTo(lean - sw * 0.32, shoulder + 29, lean - 1, shoulder + 22);
      x.quadraticCurveTo(lean + sw * 0.3, shoulder + 29, lean + sw * 0.66, shoulder + 18);
      x.moveTo(lean - 1, shoulder + 30);
      x.lineTo(lean - 1, hip - 4);
      for (const ay of [shoulder + 38, shoulder + 48]) {
        x.moveTo(lean - 9, ay);
        x.lineTo(lean + 7, ay + 1);
      }
      x.stroke();
    } else {
      x.beginPath();
      x.moveTo(lean, shoulder + 10);
      x.lineTo(lean, hip - 4);
      x.moveTo(lean - sw * 0.6, shoulder + 14);
      x.quadraticCurveTo(lean - sw * 0.3, shoulder + 30, lean - 6, shoulder + 26);
      x.moveTo(lean + sw * 0.6, shoulder + 14);
      x.quadraticCurveTo(lean + sw * 0.3, shoulder + 30, lean + 6, shoulder + 26);
      x.stroke();
    }
    if (!back && s.chestPaint) {
      // Painted slashes across the chest.
      x.strokeStyle = s.chestPaint;
      x.lineWidth = 3.2;
      x.beginPath();
      for (const o of [0, 8]) {
        x.moveTo(lean - sw * 0.62 + o, shoulder + 12);
        x.lineTo(lean - sw * 0.3 + o, shoulder + 36);
      }
      x.stroke();
    }
    const strap = (ax: number, ay: number, bx: number, by: number) => {
      const len = Math.hypot(bx - ax, by - ay) || 1;
      const nx = (-(by - ay) / len) * 4;
      const ny = ((bx - ax) / len) * 4;
      poly(x, [[ax + nx, ay + ny], [bx + nx, by + ny], [bx - nx, by - ny], [ax - nx, ay - ny]], '#4a2f1c', 1.6);
      x.fillStyle = STEEL;
      for (const f of [0.3, 0.55, 0.8]) x.fillRect(ax + (bx - ax) * f - 1.5, ay + (by - ay) * f - 1.5, 3, 3);
    };
    strap(lean - sw * 0.78, shoulder + 2, lean + hw * 0.85, hip - 1);
    strap(lean + sw * 0.78, shoulder + 2, lean - hw * 0.85, hip - 1);
    if (!back && s.chestSkulls) {
      skull(x, lean - 2, shoulder + 30, 1.5);
      if (s.chestSkulls > 1) skull(x, lean - sw * 0.52, shoulder + 18, 1.3);
    }
  }
  // Tabard panel.
  if ((s.kind === 'human' || s.kind === 'orc' || s.kind === 'dog') && !s.bare) {
    const tx = back ? lean + 2 : lean - 4;
    const tw = (s.kind === 'orc' ? 10 : 11) * B;
    const tab = () => {
      x.beginPath();
      x.moveTo(tx - tw, shoulder + 8);
      x.lineTo(tx + tw, shoulder + 8);
      x.lineTo(tx + tw + 2, hip + 30);
      x.lineTo(tx, hip + 36);
      x.lineTo(tx - tw - 2, hip + 30);
      x.closePath();
    };
    cel(x, tab, s.tabard, tx + tw * 0.4, 2, -0.3, 0.12);
    if (s.plate) {
      // Gold border inset from the tabard edge.
      x.save();
      tab();
      x.clip();
      tab();
      x.strokeStyle = gold;
      x.lineWidth = 3;
      x.stroke();
      x.restore();
      tab();
      x.lineWidth = 1.4;
      x.strokeStyle = INK;
      x.stroke();
    }
    if (s.emblem === 'eagle' && s.shield !== 'kite') eagle(x, tx, hip + 18, 0.65, s.gold);
    if (s.emblem === 'eagle' && s.shield === 'kite' && back) eagle(x, tx, shoulder + 30, 0.65, s.gold);
    if (dog && !back) eagle(x, tx - 1, shoulder + 26, 0.6, gold);
  }
  // Fur kilt under the belt (bare-chested brutes).
  if (s.bare && s.fur) {
    const kilt: number[][] = [[-hw - 6, hip + 2]];
    for (let i = 0; i <= 10; i++) kilt.push([hw + 6 - (i / 10) * (2 * hw + 12), hip + (i % 2 ? 30 : 22)]);
    kilt.splice(1, 0, [hw + 6, hip + 2]);
    poly(x, kilt, s.fur, 1.8);
  }
  // Belt with pouch.
  poly(x, [[-hw - 4, hip - 2], [hw + 4, hip - 2], [hw + 4, hip + 5], [-hw - 4, hip + 5]], s.belt, 2);
  x.fillStyle = s.plate ? gold : '#c8a23a';
  x.fillRect(lean - 3, hip - 2, 6, 7);
  poly(x, [[hw - 6, hip + 4], [hw + 6, hip + 4], [hw + 6, hip + 16], [hw - 6, hip + 16]], shade(s.belt, 0.15), 1.6);
  if (s.skulls) {
    for (const sx of s.skulls >= 3 ? [-hw + 2, lean + 2, hw - 4] : [lean + 2]) skull(x, sx, hip + 12);
  }
  // Rags hanging from the belt.
  if (s.rags) {
    for (let i = 0; i < 4; i++) {
      const rx2 = -hw + 4 + i * (hw * 0.6);
      poly(x, [[rx2 - 4, hip + 4], [rx2 + 4, hip + 4], [rx2 + 3 + rng.range(-2, 2), hip + 26 + rng.range(0, 8)], [rx2, hip + 20], [rx2 - 3, hip + 28]], i % 2 ? s.rags : shade(s.rags, -0.25), 1.4);
    }
  }
  // Bushy tail over the back of the legs (back views).
  if (dog && back) {
    fluffy(x, [[lean + 2, hip + 2], [lean - 4, hip + 14], [lean - 14, hip + 24], [lean - 26, hip + 32], [lean - 36, hip + 38], [lean - 44, hip + 40]], [5, 8, 10, 11, 10, 7], dog.coat, dog.white, 4);
  }
  // Pauldrons.
  if (s.pauldrons === 'spiked' || s.pauldrons === 'leather') {
    for (const side of [-1, 1]) {
      const px = lean + side * sw * 0.92;
      const py = shoulder + 4;
      const col = s.pauldrons === 'spiked' ? '#6a5040' : LEATHER;
      x.save();
      x.beginPath();
      x.ellipse(px, py, 11 * B * 0.85, 9, side * 0.3, 0, Math.PI * 2);
      x.fillStyle = col;
      x.fill();
      x.lineWidth = 2.2;
      x.strokeStyle = INK;
      x.stroke();
      x.restore();
      if (s.pauldrons === 'spiked') {
        for (let k = 0; k < 3; k++) {
          const ax = px + side * (k * 5 - 2);
          poly(x, [[ax - 3, py - 6], [ax + side * 4, py - 20 - k * 2], [ax + 3, py - 6]], '#ece4cc', 1.4);
        }
      }
    }
  } else if (s.pauldrons === 'brute') {
    // Huge leather-and-iron pauldrons bristling with bone spikes.
    for (const side of [-1, 1]) {
      const px = lean + side * sw * 0.9;
      const py = shoulder + 2;
      for (let k = 0; k < 3; k++) {
        const ax = px + side * (k * 7 - 6);
        poly(x, [[ax - 4.5, py - 6], [ax + side * 5, py - 25 - k * 4], [ax + 4.5, py - 6]], BONE, 1.6);
      }
      const pad = () => {
        x.beginPath();
        x.ellipse(px, py, 15 * B * 0.8, 12.5, side * 0.3, 0, Math.PI * 2);
      };
      cel(x, pad, '#5a4030', px + 3, 2.4, -0.3, 0.2);
      x.strokeStyle = STEEL_D;
      x.lineWidth = 3;
      x.beginPath();
      x.ellipse(px, py + 1, 15 * B * 0.8 - 3, 9.5, side * 0.3, 0.15, Math.PI - 0.15);
      x.stroke();
      x.fillStyle = STEEL;
      for (const k of [-1, 0, 1]) x.fillRect(px + k * 8 - 1.5, py + 6 - Math.abs(k) * 2, 3, 3);
    }
  } else if (s.pauldrons === 'plate') {
    // Rounded plate pauldrons with a gilded edge and one lame below.
    for (const side of [-1, 1]) {
      const px = lean + side * sw * 0.92;
      const py = shoulder + 4;
      const lame = () => {
        x.beginPath();
        x.ellipse(px + side * 2, py + 8, 9.5 * B, 5.5, side * 0.3, 0, Math.PI * 2);
      };
      cel(x, lame, s.tunic, px + 2, 2, -0.3, 0.25);
      const pad = () => {
        x.beginPath();
        x.ellipse(px, py, 12 * B, 9.5, side * 0.3, 0, Math.PI * 2);
      };
      cel(x, pad, s.tunic, px + 2, 2.2, -0.3, 0.3);
      x.strokeStyle = gold;
      x.lineWidth = 1.8;
      x.beginPath();
      x.ellipse(px, py, 12 * B - 2.5, 7, side * 0.3, 0, Math.PI * 2);
      x.stroke();
    }
  }
  if (s.skullShoulder) {
    const px = lean + (back ? -1 : 1) * sw * 0.85;
    poly(x, [[px - 4, shoulder - 2], [px - 9, shoulder - 13], [px - 1, shoulder - 5]], BONE, 1.2);
    poly(x, [[px + 4, shoulder - 2], [px + 9, shoulder - 13], [px + 1, shoulder - 5]], BONE, 1.2);
    skull(x, px, shoulder + 2, 1.4);
  }
  // Collar: a white fur ruff (collie), a hood worn down, or a scarf.
  if (dog) {
    const cx = lean - (back ? 0 : 2);
    const cy = neck + 9;
    const rx = sw * 0.66;
    const ry = back ? 8 : 9;
    const pts: number[][] = [];
    const n = 20;
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2;
      const k = i % 2 ? 1.22 : 1;
      const down = Math.sin(a) > 0 ? (back ? 1.15 : 2.1) : 0.85;
      pts.push([cx + Math.cos(a) * rx * k, cy + Math.sin(a) * ry * k * down]);
    }
    poly(x, pts, dog.white, 2);
    x.strokeStyle = shade(dog.white, -0.22);
    x.lineWidth = 1.2;
    for (let i = 0; i < 5; i++) {
      const px = cx - rx * 0.6 + i * rx * 0.3;
      x.beginPath();
      x.moveTo(px, cy + 2);
      x.lineTo(px - 2, cy + (back ? 7 : 14));
      x.stroke();
    }
  } else if (s.cowl) {
    if (back) {
      // The hood hangs down between the shoulder blades.
      poly(x, [[lean - 13, neck + 6], [lean + 13, neck + 6], [lean + 8, shoulder + 28], [lean, shoulder + 36], [lean - 8, shoulder + 28]], s.cowl, 2);
    } else {
      // The hood bunched up behind the head.
      x.beginPath();
      x.ellipse(lean + 10, neck - 6, 13, 10, 0.3, 0, Math.PI * 2);
      x.fillStyle = shade(s.cowl, -0.2);
      x.fill();
      x.lineWidth = 2;
      x.strokeStyle = INK;
      x.stroke();
    }
    const cw = () => {
      x.beginPath();
      x.ellipse(lean, neck + 8, sw * 0.72, 9, 0, 0, Math.PI * 2);
    };
    cel(x, cw, s.cowl, lean + 6, 2.2, -0.3, 0.15);
    x.strokeStyle = shade(s.cowl, -0.35);
    x.lineWidth = 1.4;
    x.beginPath();
    x.moveTo(lean - sw * 0.4, neck + 6);
    x.quadraticCurveTo(lean, neck + 13, lean + sw * 0.45, neck + 6);
    x.stroke();
  } else if (s.scarf) {
    const sc = () => {
      x.beginPath();
      x.ellipse(lean, neck + 8, sw * 0.62, 7, 0, 0, Math.PI * 2);
    };
    cel(x, sc, s.scarf, lean + 6, 2.2, -0.3, 0.15);
    // Tail.
    poly(x, back ? [[lean - 6, neck + 10], [lean + 6, neck + 10], [lean + 9, shoulder + 34], [lean - 2, shoulder + 30]] : [[lean + 8, neck + 8], [lean + 18, neck + 10], [lean + 24, shoulder + 22], [lean + 14, shoulder + 18]], s.scarf, 2);
  }

  // Head.
  head(x, lean - (back ? 0 : 2), headY, s, back, rng);

  // Arms, weapons and shields in front of the body.
  const shoulderL = { x: lean - sw + 2, y: shoulder + 6 };
  const shoulderR = { x: lean + sw - 2, y: shoulder + 6 };
  const armW = 14.5 * B;
  const sleeve = s.kind === 'human' || s.kind === 'dog' ? s.tunic : s.skin;
  const glove = s.gauntlet ?? (s.kind === 'human' ? LEATHER : s.skin);
  const arm = (ax: number, ay: number, bx: number, by: number) => {
    limb(x, ax, ay, bx, by, armW, sleeve);
    const len = Math.hypot(bx - ax, by - ay) || 1;
    const nx = -(by - ay) / len;
    const ny = (bx - ax) / len;
    const at = (f: number, o: number) => [ax + (bx - ax) * f + nx * o, ay + (by - ay) * f + ny * o];
    if (s.armPaint) {
      // Two painted stripes slanting across the upper arm.
      x.strokeStyle = s.armPaint;
      x.lineWidth = 2.6;
      x.beginPath();
      for (const f of [0.14, 0.3]) {
        const [p1x, p1y] = at(f, -armW * 0.36);
        const [p2x, p2y] = at(f + 0.1, armW * 0.36);
        x.moveTo(p1x, p1y);
        x.lineTo(p2x, p2y);
      }
      x.stroke();
    }
    if (s.bracers) {
      // Studded leather bracer with a single spike.
      const w = armW * 0.62;
      poly(x, [at(0.56, w), at(0.88, w * 0.9), at(0.88, -w * 0.9), at(0.56, -w)], s.bracers, 1.8);
      const sp = nx * (bx - ax) <= 0 ? 1 : -1;
      poly(x, [at(0.66, sp * w * 0.9), at(0.72, sp * (w + 8)), at(0.78, sp * w * 0.9)], STEEL, 1.2);
      x.fillStyle = STEEL;
      for (const f of [0.62, 0.82]) {
        const [px, py] = at(f, 0);
        x.fillRect(px - 1.5, py - 1.5, 3, 3);
      }
    }
    if (s.plate) {
      // Gilded edge of the vambrace.
      x.strokeStyle = gold;
      x.lineWidth = 2.2;
      const [p1x, p1y] = at(0.62, armW * 0.5);
      const [p2x, p2y] = at(0.62, -armW * 0.5);
      x.beginPath();
      x.moveTo(p1x, p1y);
      x.lineTo(p2x, p2y);
      x.stroke();
    }
  };
  const hand = (hx: number, hy: number) => {
    x.beginPath();
    x.ellipse(hx, hy, 6.8 * B, 6.8 * B, 0, 0, Math.PI * 2);
    x.fillStyle = glove;
    x.fill();
    x.lineWidth = 2;
    x.strokeStyle = INK;
    x.stroke();
  };
  const swordLen = s.plate ? 62 : 54;
  const blade = (hx: number, hy: number, ang: number) => {
    if (s.weapon === 'sword') sword(x, hx, hy, ang, swordLen);
    else if (s.weapon === 'knife') sword(x, hx, hy, ang, 24);
    else if (s.weapon === 'cleaver') cleaver(x, hx, hy, ang, s.kind === 'goblin' ? 0.8 : 1.05);
    else mace(x, hx, hy, ang);
  };
  if (!back && lead) {
    // Front view, shield leading: the shield arm reaches toward the facing
    // side (left here, right once mirrored) and the blade is held low across
    // the body on the trailing arm, point toward the enemy.
    const hx = atk ? lean - 14 : lean + 8;
    const hy = atk ? shoulder + 26 : shoulder + 42;
    arm(shoulderR.x, shoulderR.y, hx, hy);
    blade(hx, hy, atk ? -1.45 : -0.78);
    hand(hx, hy);
    const sx = shoulderL.x - 10 + (atk ? -8 : 0);
    arm(shoulderL.x, shoulderL.y, sx + 4, shoulderL.y + 24);
    if (s.shield === 'kite') kiteShield(x, sx, shoulder + 36 + (atk ? -4 : 0), 1.32 * B, false, s);
    else roundShield(x, sx + 2, shoulder + 34 + (atk ? -4 : 0), 24 * B * 0.8, false);
    return;
  }
  if (back && lead) {
    // Back view, shield leading: the shield's back is toward us on the leading
    // (right) arm, the blade raised on the trailing arm.
    const hx = atk ? shoulderL.x + 4 : shoulderL.x - 10;
    const hy = atk ? shoulderL.y - 4 : shoulderL.y + 28;
    blade(hx, hy, atk ? 1.1 : -0.3);
    arm(shoulderL.x, shoulderL.y, hx, hy);
    hand(hx, hy);
    const sx = shoulderR.x + 6 + (atk ? 6 : 0);
    if (s.shield === 'kite') kiteShield(x, sx, shoulder + 34, 1.28 * B, true, s);
    else roundShield(x, sx, shoulder + 34, 24 * B * 0.8, true);
    return;
  }
  if (!back) {
    // Front view: weapon arm on the left (facing side), off arm on the right.
    if (s.weapon === 'sword' || s.weapon === 'cleaver' || s.weapon === 'mace' || s.weapon === 'knife') {
      const hx = atk ? shoulderL.x - 26 : shoulderL.x - 10;
      const hy = atk ? shoulderL.y + 4 : shoulderL.y + 30;
      arm(shoulderL.x, shoulderL.y, hx, hy);
      blade(hx, hy, atk ? (s.weapon === 'mace' ? -1.1 : -1.25) : s.weapon === 'mace' ? -0.35 : -0.55);
      hand(hx, hy);
    } else if (s.weapon === 'horn') {
      // Idle: the horn carried at the hip. Attacking: raised and sounded.
      if (atk) {
        const mx = lean - 8;
        const my = headY + 8;
        warHorn(x, mx, my, mx - 16, my + 34, mx - 44, my - 22);
        arm(shoulderL.x, shoulderL.y, mx - 10, my + 18);
        hand(mx - 10, my + 18);
        arm(shoulderR.x, shoulderR.y, mx + 4, my + 6);
        hand(mx + 4, my + 6);
      } else {
        const hx = shoulderL.x - 8;
        const hy = shoulderL.y + 32;
        warHorn(x, hx + 4, hy - 6, hx - 14, hy + 30, hx - 30, hy + 4);
        arm(shoulderL.x, shoulderL.y, hx, hy);
        hand(hx, hy);
        arm(shoulderR.x, shoulderR.y, shoulderR.x + 4, shoulderR.y + 28);
        hand(shoulderR.x + 4, shoulderR.y + 28);
      }
    } else if (s.weapon === 'spear' || s.weapon === 'gspear') {
      const lowered = atk || s.weapon === 'gspear';
      const hx1 = lean - 4;
      const hy1 = shoulder + 30;
      arm(shoulderL.x, shoulderL.y, hx1 - 6, hy1 + 2);
      spear(x, hx1, hy1, lowered ? -1.05 : -0.08, s.weapon === 'gspear' ? 104 : 140, s.weapon === 'gspear' ? s.rags : undefined, s.fork);
      hand(hx1 - 6, hy1 + 2);
      arm(shoulderR.x, shoulderR.y, hx1 + 12, hy1 + (lowered ? 14 : 22));
      hand(hx1 + 12, hy1 + (lowered ? 14 : 22));
    } else if (s.weapon === 'club') {
      // Two-handed: carried low with the head forward, raised overhead to strike.
      const ang = atk ? -0.4 : -1.72;
      const ux = Math.sin(ang);
      const uy = -Math.cos(ang);
      const p = atk ? { x: lean - 14, y: shoulder - 4 } : { x: lean - 4, y: shoulder + 46 };
      const q = { x: p.x - ux * 24, y: p.y - uy * 24 };
      arm(shoulderR.x, shoulderR.y, q.x, q.y);
      club(x, p.x, p.y, ang, 1.05);
      hand(q.x, q.y);
      arm(shoulderL.x, shoulderL.y, p.x, p.y);
      hand(p.x, p.y);
    } else if (s.weapon === 'crossbow') {
      const hx = lean - 2;
      const hy = shoulder + (atk ? 14 : 24);
      x.save();
      x.translate(hx + 6, hy);
      x.scale(1.35, 1.35);
      crossbow(x, 0, 0, atk ? -0.08 : 0.22);
      x.restore();
      arm(shoulderL.x, shoulderL.y, hx - 12, hy + 1);
      hand(hx - 12, hy + 1);
      arm(shoulderR.x, shoulderR.y, hx + 16, hy + 4);
      hand(hx + 16, hy + 4);
    } else if (s.weapon === 'bow') {
      const hx = shoulderL.x - (atk ? 22 : 12);
      const hy = shoulder + 20;
      arm(shoulderL.x, shoulderL.y, hx, hy);
      bow(x, hx - 2, hy, atk);
      hand(hx, hy);
      arm(shoulderR.x, shoulderR.y, atk ? shoulderR.x + 2 : shoulderR.x - 4, hy + (atk ? -2 : 18));
      hand(atk ? shoulderR.x + 2 : shoulderR.x - 4, hy + (atk ? -2 : 18));
    }
    // Off arm with shield.
    if (s.shield === 'kite') {
      arm(shoulderR.x, shoulderR.y, shoulderR.x - 4, shoulderR.y + 26);
      kiteShield(x, shoulderR.x - 6 + (atk ? -6 : 0), shoulder + 36, 1.32 * B, false, s);
    } else if (s.shield === 'round') {
      arm(shoulderR.x, shoulderR.y, shoulderR.x - 2, shoulderR.y + 24);
      roundShield(x, shoulderR.x - 2 + (atk ? -6 : 0), shoulder + 34, 24 * B * 0.8, false);
    } else if (s.weapon === 'sword' || s.weapon === 'cleaver' || s.weapon === 'mace') {
      arm(shoulderR.x, shoulderR.y, shoulderR.x + 4, shoulderR.y + 28);
      hand(shoulderR.x + 4, shoulderR.y + 28);
    }
  } else {
    // Back view: shield on the left arm, weapon on the right.
    if (s.shield === 'kite') kiteShield(x, shoulderL.x - 6, shoulder + 34, 1.28 * B, true, s);
    else if (s.shield === 'round') roundShield(x, shoulderL.x - 4, shoulder + 34, 24 * B * 0.8, true);
    if (flee) {
      // Arms flung up in panic, weapon dropped.
      arm(shoulderL.x, shoulderL.y, shoulderL.x - 14, shoulderL.y - 18);
      hand(shoulderL.x - 14, shoulderL.y - 18);
      arm(shoulderR.x, shoulderR.y, shoulderR.x + 16, shoulderR.y - 12);
      hand(shoulderR.x + 16, shoulderR.y - 12);
      return;
    }
    if (s.weapon === 'sword' || s.weapon === 'cleaver' || s.weapon === 'mace' || s.weapon === 'knife') {
      const hx = atk ? shoulderR.x + 24 : shoulderR.x + 10;
      const hy = atk ? shoulderR.y - 2 : shoulderR.y + 30;
      blade(hx, hy, atk ? (s.weapon === 'mace' ? 0.9 : 1.0) : s.weapon === 'mace' ? 0.3 : 0.45);
      arm(shoulderR.x, shoulderR.y, hx, hy);
      hand(hx, hy);
    } else if (s.weapon === 'horn') {
      // From behind, the bell of the horn shows past the head.
      const mx = lean + 6;
      const my = headY + 8;
      if (atk) warHorn(x, mx, my, mx + 18, my + 30, mx + 46, my - 26);
      else warHorn(x, shoulderR.x + 6, shoulderR.y + 26, shoulderR.x + 22, shoulderR.y + 56, shoulderR.x + 34, shoulderR.y + 30);
      arm(shoulderR.x, shoulderR.y, atk ? mx + 10 : shoulderR.x + 8, atk ? my + 16 : shoulderR.y + 30);
      hand(atk ? mx + 10 : shoulderR.x + 8, atk ? my + 16 : shoulderR.y + 30);
      arm(shoulderL.x, shoulderL.y, shoulderL.x - 4, shoulderL.y + 28);
      hand(shoulderL.x - 4, shoulderL.y + 28);
    } else if (s.weapon === 'spear' || s.weapon === 'gspear') {
      const lowered = atk || s.weapon === 'gspear';
      const hx = lean + 6;
      const hy = shoulder + 30;
      spear(x, hx, hy, lowered ? 1.0 : 0.1, s.weapon === 'gspear' ? 104 : 140, s.weapon === 'gspear' ? s.rags : undefined, s.fork);
      arm(shoulderR.x, shoulderR.y, hx + 4, hy);
      hand(hx + 4, hy);
      arm(shoulderL.x, shoulderL.y, hx - 10, hy + 16);
      hand(hx - 10, hy + 16);
    } else if (s.weapon === 'club') {
      const ang = atk ? 0.4 : 1.72;
      const ux = Math.sin(ang);
      const uy = -Math.cos(ang);
      const p = atk ? { x: lean + 14, y: shoulder - 4 } : { x: lean + 4, y: shoulder + 46 };
      const q = { x: p.x - ux * 24, y: p.y - uy * 24 };
      club(x, p.x, p.y, ang, 1.05);
      arm(shoulderL.x, shoulderL.y, q.x, q.y);
      hand(q.x, q.y);
      arm(shoulderR.x, shoulderR.y, p.x, p.y);
      hand(p.x, p.y);
    } else if (s.weapon === 'crossbow') {
      const hx = lean + 4;
      const hy = shoulder + (atk ? 14 : 26);
      arm(shoulderR.x, shoulderR.y, hx + 14, hy + 2);
      arm(shoulderL.x, shoulderL.y, hx - 10, hy + 4);
      x.save();
      x.translate(hx, hy);
      x.scale(-1.35, 1.35);
      crossbow(x, 0, 0, atk ? -0.1 : 0.25, true);
      x.restore();
      hand(hx + 14, hy + 2);
      hand(hx - 10, hy + 4);
    } else if (s.weapon === 'bow') {
      const hx = shoulderR.x + (atk ? 20 : 10);
      const hy = shoulder + 20;
      arm(shoulderR.x, shoulderR.y, hx, hy);
      x.save();
      x.translate(hx, hy);
      x.scale(-1, 1);
      bow(x, 0, 0, atk);
      x.restore();
      hand(hx, hy);
      arm(shoulderL.x, shoulderL.y, shoulderL.x - 6, hy + 10);
      hand(shoulderL.x - 6, hy + 10);
    }
    if (s.weapon === 'sword' && s.shield !== 'kite') {
      arm(shoulderL.x, shoulderL.y, shoulderL.x - 4, shoulderL.y + 28);
    }
  }
}

// ---------------------------------------------------------------- wolf rider

/** Trace a smooth path through points (midpoint quadratic curves). */
function smoothPath(x: CanvasRenderingContext2D, pts: number[][], closed: boolean) {
  const n = pts.length;
  x.moveTo(pts[0][0], pts[0][1]);
  for (let i = 1; i < n - (closed ? 0 : 1); i++) {
    const [ax, ay] = pts[i];
    const [bx, by] = pts[(i + 1) % n];
    x.quadraticCurveTo(ax, ay, (ax + bx) / 2, (ay + by) / 2);
  }
  if (closed) x.closePath();
  else x.lineTo(pts[n - 1][0], pts[n - 1][1]);
}

/** Both sides of a tube along a spine, one width per spine point. */
function tubeSides(spine: number[][], widths: number[]) {
  const L: number[][] = [];
  const R: number[][] = [];
  spine.forEach((p, i) => {
    const q = spine[Math.min(spine.length - 1, i + 1)];
    const o = spine[Math.max(0, i - 1)];
    const len = Math.hypot(q[0] - o[0], q[1] - o[1]) || 1;
    const nx = -(q[1] - o[1]) / len;
    const ny = (q[0] - o[0]) / len;
    L.push([p[0] + (nx * widths[i]) / 2, p[1] + (ny * widths[i]) / 2]);
    R.push([p[0] - (nx * widths[i]) / 2, p[1] - (ny * widths[i]) / 2]);
  });
  return { L, R };
}

/**
 * A wolf's leg from the shoulder or hip down to the paw: one smooth outline,
 * shaded on its far side, the top left open so it grows out of the body.
 */
function wolfLeg(x: CanvasRenderingContext2D, spine: number[][], widths: number[], col: string, paw = true) {
  const { L, R } = tubeSides(spine, widths);
  const outline = [...L, ...[...R].reverse()];
  x.save();
  x.beginPath();
  smoothPath(x, outline, true);
  x.fillStyle = col;
  x.fill();
  x.clip();
  const back = tubeSides(spine.map(([px, py], i) => [px + widths[i] * 0.34, py]), widths.map((w) => w * 0.5));
  x.beginPath();
  smoothPath(x, [...back.L, ...[...back.R].reverse()], true);
  x.fillStyle = shade(col, -0.24);
  x.fill();
  x.restore();
  x.lineWidth = 2;
  x.strokeStyle = INK;
  for (const side of [L, R]) {
    x.beginPath();
    smoothPath(x, side, false);
    x.stroke();
  }
  if (!paw) return;
  // The paw, toes forward, a hint of claws.
  const [px, py] = spine[spine.length - 1];
  x.beginPath();
  x.ellipse(px - 2.5, py - 1, 7.5, 4.4, 0, 0, Math.PI * 2);
  x.fillStyle = shade(col, -0.08);
  x.fill();
  x.lineWidth = 1.9;
  x.stroke();
  x.strokeStyle = BONE;
  x.lineWidth = 1.3;
  for (const k of [0, 3, 6]) {
    x.beginPath();
    x.moveTo(px - 9 + k, py + 1.5);
    x.lineTo(px - 11 + k, py + 3.6);
    x.stroke();
  }
}

/**
 * A muscle mass (shoulder, haunch) over the body: shaded like the rest, but
 * outlined only along its lower edge so it swells out of the body.
 */
function muscle(x: CanvasRenderingContext2D, cx: number, cy: number, rx: number, ry: number, rot: number, fill: string, from: number, to: number) {
  x.save();
  x.beginPath();
  x.ellipse(cx, cy, rx, ry, rot, 0, Math.PI * 2);
  x.fillStyle = fill;
  x.fill();
  x.clip();
  x.fillStyle = shade(fill, -0.24);
  x.beginPath();
  x.ellipse(cx + rx * 0.45, cy + ry * 0.35, rx * 0.8, ry * 0.8, rot, 0, Math.PI * 2);
  x.fill();
  x.restore();
  x.beginPath();
  x.ellipse(cx, cy, rx, ry, rot, from, to);
  x.lineWidth = 2;
  x.strokeStyle = INK;
  x.stroke();
}

/** Tufts of fur along a base line, swept by (dx, dy): throat, nape and ruff. */
function tufts(x: CanvasRenderingContext2D, base: number[][], dx: number, dy: number, fill: string) {
  const pts: number[][] = [base[0]];
  for (let i = 1; i < base.length; i++) {
    const [ax, ay] = base[i - 1];
    const [bx, by] = base[i];
    pts.push([(ax + bx) / 2 + dx, (ay + by) / 2 + dy]);
    pts.push([bx, by]);
  }
  poly(x, pts, fill, 1.8);
}

type WolfPose = { lunge: number; run: boolean; away: boolean; dead: boolean };

/**
 * A great grey warg in profile, head to the left: far legs, tail, body,
 * hackles, near legs, harness and head. `away` turns the head from the viewer
 * (back views draw the profile mirrored, head up and to the right).
 */
function wolfProfile(x: CanvasRenderingContext2D, s: Style, o: WolfPose, rng: Rng) {
  const fur = s.skin;
  const dark = shade(fur, -0.3);
  const deep = shade(fur, -0.5);
  const light = shade(fur, 0.28);
  const pale = shade(fur, 0.55);
  const L = o.lunge;
  type Legs = { nf: number[][]; ff: number[][]; nh: number[][]; fh: number[][] };
  const legs: Legs = o.dead
    ? {
        nf: [[-24, -44], [-36, -32], [-46, -22], [-54, -16]],
        ff: [[-14, -44], [-26, -36], [-38, -28], [-46, -24]],
        nh: [[34, -44], [44, -32], [58, -26], [66, -20]],
        fh: [[24, -46], [34, -36], [48, -30], [56, -26]],
      }
    : o.run
      ? {
          nf: [[-24, -46], [-36, -36], [-48, -26], [-56, -22]],
          ff: [[-14, -46], [-26, -40], [-36, -30], [-42, -24]],
          nh: [[34, -44], [40, -30], [56, -20], [64, -14]],
          fh: [[24, -46], [28, -32], [44, -24], [52, -18]],
        }
      : {
          nf: [[-24, -44], [-22 - L * 8, -28], [-24 - L * 14, -11], [-26 - L * 16, -2]],
          ff: [[-12, -44], [-10 - L * 6, -28], [-14 - L * 10, -11], [-16 - L * 11, -2]],
          nh: [[34, -44], [28 + L * 3, -30], [42 + L * 5, -15], [38 + L * 6, -2]],
          fh: [[24, -46], [18 + L * 3, -31], [30 + L * 5, -15], [26 + L * 6, -2]],
        };
  // Far legs in shadow.
  wolfLeg(x, legs.ff, [11, 8, 6, 6], dark);
  wolfLeg(x, legs.fh, [14, 10, 7, 6], dark);
  // The tail: hanging low, held out straight when it springs or runs.
  const tail = o.dead
    ? [[44, -52], [58, -50], [72, -46], [84, -44]]
    : L > 0 || o.run
      ? [[44, -56], [58, -60], [72, -60], [84, -56]]
      : [[44, -56], [56, -50], [62, -38], [62, -24]];
  const ts = tubeSides(tail, [7, 15, 15, 5]);
  const brush = [...ts.L, [tail[3][0] + (tail[3][0] - tail[2][0]) * 0.5, tail[3][1] + (tail[3][1] - tail[2][1]) * 0.5], ...[...ts.R].reverse()];
  x.save();
  x.beginPath();
  smoothPath(x, brush, true);
  x.fillStyle = fur;
  x.fill();
  x.clip();
  x.fillStyle = deep;
  x.beginPath();
  x.arc(tail[3][0], tail[3][1], 11, 0, Math.PI * 2);
  x.fill();
  x.fillStyle = light;
  x.globalAlpha = 0.5;
  x.beginPath();
  smoothPath(x, ts.L.slice(0, 3).concat([tail[2], tail[1]]), true);
  x.fill();
  x.restore();
  x.beginPath();
  smoothPath(x, brush, true);
  x.lineWidth = 2.2;
  x.strokeStyle = INK;
  x.stroke();
  // Body: deep chest, tucked belly, heavy haunch.
  const body = () => {
    x.beginPath();
    x.moveTo(-30, -70);
    x.quadraticCurveTo(-18, -72, -10, -66);
    x.quadraticCurveTo(12, -60, 32, -62);
    x.quadraticCurveTo(49, -62, 48, -48);
    x.quadraticCurveTo(47, -36, 34, -36);
    x.quadraticCurveTo(22, -40, 8, -37);
    x.quadraticCurveTo(-10, -30, -24, -31);
    x.quadraticCurveTo(-41, -33, -41, -50);
    x.quadraticCurveTo(-41, -64, -30, -70);
    x.closePath();
  };
  x.save();
  body();
  x.fillStyle = fur;
  x.fill();
  x.clip();
  // Pale throat and belly, a dark saddle down the back, light along the top.
  x.fillStyle = pale;
  x.globalAlpha = 0.8;
  x.beginPath();
  x.ellipse(-16, -30, 30, 10, -0.15, 0, Math.PI * 2);
  x.fill();
  x.globalAlpha = 1;
  const under = x.createLinearGradient(0, -50, 0, -30);
  under.addColorStop(0, 'rgba(20,12,8,0)');
  under.addColorStop(1, 'rgba(20,12,8,0.32)');
  x.fillStyle = under;
  x.fillRect(-60, -50, 120, 24);
  x.fillStyle = dark;
  x.globalAlpha = 0.75;
  x.beginPath();
  x.ellipse(12, -64, 34, 7, 0.02, 0, Math.PI * 2);
  x.fill();
  x.globalAlpha = 1;
  const top = x.createLinearGradient(-40, -74, -10, -52);
  top.addColorStop(0, 'rgba(255,250,235,0.3)');
  top.addColorStop(1, 'rgba(255,250,235,0)');
  x.fillStyle = top;
  x.fillRect(-60, -80, 70, 34);
  // Fur strokes along the flank.
  x.strokeStyle = deep;
  x.lineWidth = 1.4;
  for (const [fx, fy] of [[-18, -50], [-8, -46], [2, -52], [12, -47], [22, -53], [-26, -42], [6, -41]]) {
    x.beginPath();
    x.moveTo(fx, fy);
    x.quadraticCurveTo(fx + 3, fy + 3, fx + 7, fy + 2);
    x.stroke();
  }
  x.restore();
  body();
  x.lineWidth = 2.6;
  x.strokeStyle = INK;
  x.stroke();
  // A thick neck out to the head, thrust forward and down when it bites.
  const hx = -50 - L * 12;
  const hy = -66 + L * 8;
  wolfLeg(x, [[-30, -60], [hx + 4, hy + 3]], [26, 22], fur, false);
  // Hackles raised along the neck and withers.
  const crest = [[-43, -56], [-44, -68], [-38, -66], [-36, -79], [-29, -71], [-22, -82], [-17, -72], [-8, -78], [-6, -68], [3, -71], [4, -63], [-6, -63], [-22, -66], [-36, -60]];
  poly(x, crest, dark, 2);
  x.strokeStyle = deep;
  x.lineWidth = 1.2;
  for (const [ax, ay, bx, by] of [[-36, -64, -34, -73], [-24, -67, -21, -77], [-12, -66, -8, -73]]) {
    x.beginPath();
    x.moveTo(ax, ay);
    x.lineTo(bx, by);
    x.stroke();
  }
  // Near legs: haunch and shoulder over the body.
  wolfLeg(x, legs.nh, [16, 11, 7.5, 6.5], fur);
  muscle(x, 36, -48, 15, 14, -0.3, fur, 0.2, Math.PI * 1.05);
  wolfLeg(x, legs.nf, [13, 9.5, 7.5, 7], fur);
  muscle(x, -25 - L * 3, -48, 10, 14, 0.25, fur, Math.PI * 0.35, Math.PI * 0.95);
  if (!o.away) {
    // Pale throat fur from under the jaw to the chest.
    const t = (k: number) => [hx + 6 + (-36 - hx - 6) * k, hy + 10 + (-40 - hy - 10) * k];
    tufts(x, [[hx + 12, hy + 2], t(0), t(0.33), t(0.66), t(1), [-30, -46]], -6, 3, pale);
  }
  if (o.dead) {
    headOf(x, s, hx, hy, 0, o.away, true, rng);
    return;
  }
  // Harness: a breast strap and a girth.
  x.lineCap = 'round';
  for (const [w, col] of [[6.5, INK], [4, '#5a3a22']] as [number, string][]) {
    x.lineWidth = w;
    x.strokeStyle = col;
    x.beginPath();
    x.moveTo(-14, -64);
    x.quadraticCurveTo(-34, -56, -36, -40);
    x.moveTo(16, -62);
    x.quadraticCurveTo(18, -48, 12, -38);
    x.stroke();
  }
  x.fillStyle = '#b8862e';
  x.beginPath();
  x.arc(-31, -50, 2.6, 0, Math.PI * 2);
  x.fill();
  x.lineWidth = 1.4;
  x.strokeStyle = INK;
  x.stroke();
  // A trophy skull on a thong from the girth.
  x.lineWidth = 1.4;
  x.beginPath();
  x.moveTo(16, -56);
  x.lineTo(22, -44);
  x.stroke();
  x.fillStyle = BONE;
  x.beginPath();
  x.ellipse(23, -41, 4, 3.6, 0, 0, Math.PI * 2);
  x.fill();
  x.stroke();
  x.fillStyle = INK;
  x.fillRect(21, -42, 1.4, 1.4);
  x.fillRect(24, -42, 1.4, 1.4);
  headOf(x, s, hx, hy, L, o.away, false, rng);
}

/** The warg's head facing left: ears, skull, muzzle and jaws. */
function headOf(x: CanvasRenderingContext2D, s: Style, hx: number, hy: number, bite: number, away: boolean, dead: boolean, rng: Rng) {
  const fur = s.skin;
  const dark = shade(fur, -0.3);
  const deep = shade(fur, -0.5);
  const light = shade(fur, 0.28);
  const pale = shade(fur, 0.55);
  if (away) {
    // Seen from behind: a sliver of muzzle beyond the skull, ear backs up.
    poly(x, [[hx - 4, hy - 2], [hx - 22, hy + 1], [hx - 21, hy + 6], [hx - 4, hy + 9]], dark, 2);
    cel(x, () => {
      x.beginPath();
      x.ellipse(hx, hy, 14, 12.5, -0.1, 0, Math.PI * 2);
    }, fur, hx + 5, 2.4);
    poly(x, [[hx - 9, hy - 7], [hx - 6, hy - 26], [hx + 2, hy - 9]], fur, 2);
    poly(x, [[hx + 1, hy - 9], [hx + 7, hy - 27], [hx + 11, hy - 6]], dark, 2);
    // Fur at the nape, swept back toward the hackles.
    tufts(x, [[hx + 2, hy - 4], [hx + 10, hy - 2], [hx + 14, hy + 4], [hx + 12, hy + 10], [hx + 4, hy + 8]], 6, 1, light);
    return;
  }
  // Far ear, skull, near ear.
  poly(x, [[hx + 2, hy - 8], [hx + 10, hy - 27], [hx + 13, hy - 5]], dark, 2);
  cel(x, () => {
    x.beginPath();
    x.ellipse(hx, hy, 14, 12, -0.1, 0, Math.PI * 2);
  }, fur, hx + 6, 2.4);
  poly(x, [[hx - 7, hy - 8], [hx - 3, hy - 27], [hx + 4, hy - 9]], fur, 2);
  poly(x, [[hx - 4, hy - 10], [hx - 2.5, hy - 21], [hx + 1, hy - 10]], '#5e3e3a', 0);
  // Cheek ruff behind the jaw.
  poly(x, [[hx + 4, hy + 1], [hx + 16, hy + 4], [hx + 9, hy + 8], [hx + 16, hy + 14], [hx + 5, hy + 12], [hx + 7, hy + 19], [hx - 4, hy + 12]], light, 1.8);
  // Lower jaw: hanging open in the bite, slack in death.
  const open = dead ? 0.5 : bite;
  const jaw = [[hx - 29, hy + 6 + open * 5], [hx - 25, hy + 11 + open * 11], [hx - 8, hy + 13 + open * 4], [hx - 4, hy + 7]];
  if (open > 0) {
    poly(x, [[hx - 30, hy + 4], [hx - 27, hy + 9 + open * 9], [hx - 6, hy + 10], [hx - 6, hy + 5]], '#5a1410', 0);
  }
  poly(x, jaw, pale, 2);
  if (dead) {
    poly(x, [[hx - 24, hy + 10], [hx - 30, hy + 18], [hx - 26, hy + 20], [hx - 20, hy + 12]], '#b4525a', 1.4);
  }
  // Muzzle: a long wedge from the brow to the nose, lighter beneath.
  const muzzle = [[hx - 6, hy - 9], [hx - 13, hy - 6], [hx - 31, hy - 2], [hx - 35, hy + 1], [hx - 33, hy + 6], [hx - 10, hy + 8], [hx - 3, hy + 5]];
  x.beginPath();
  muzzle.forEach(([px, py], i) => (i ? x.lineTo(px, py) : x.moveTo(px, py)));
  x.closePath();
  x.fillStyle = light;
  x.fill();
  x.save();
  x.clip();
  x.fillStyle = pale;
  x.fillRect(hx - 40, hy + 2, 40, 10);
  x.restore();
  x.lineWidth = 2;
  x.strokeStyle = INK;
  x.stroke();
  if (open > 0) {
    // Fangs top and bottom.
    x.fillStyle = BONE;
    for (const [tx, ty, d] of [[hx - 29, hy + 5, 1], [hx - 20, hy + 7, 1], [hx - 25, hy + 10 + open * 9, -1], [hx - 14, hy + 11 + open * 4, -1]]) {
      x.beginPath();
      x.moveTo(tx - 2, ty);
      x.lineTo(tx, ty + d * 5);
      x.lineTo(tx + 2, ty);
      x.fill();
    }
    // Snarl wrinkles.
    x.strokeStyle = deep;
    x.lineWidth = 1.3;
    for (const k of [0, 5]) {
      x.beginPath();
      x.moveTo(hx - 18 - k, hy - 3);
      x.quadraticCurveTo(hx - 20 - k, hy, hx - 18 - k, hy + 2);
      x.stroke();
    }
  }
  // Nose and eye under a heavy brow.
  x.fillStyle = '#151213';
  x.beginPath();
  x.ellipse(hx - 33.5, hy + 0.5, 3.6, 3, 0, 0, Math.PI * 2);
  x.fill();
  if (dead) {
    x.strokeStyle = INK;
    x.lineWidth = 1.6;
    x.beginPath();
    x.moveTo(hx - 13, hy - 3);
    x.lineTo(hx - 7, hy - 2);
    x.stroke();
    return;
  }
  x.fillStyle = '#f0c040';
  x.beginPath();
  x.ellipse(hx - 10, hy - 3, 3.2, 2.1, -0.15, 0, Math.PI * 2);
  x.fill();
  x.fillStyle = INK;
  x.beginPath();
  x.ellipse(hx - 10.5, hy - 3, 1, 1.9, 0, 0, Math.PI * 2);
  x.fill();
  x.strokeStyle = INK;
  x.lineWidth = 2;
  x.beginPath();
  x.moveTo(hx - 15, hy - 6);
  x.lineTo(hx - 5, hy - 7.5);
  x.stroke();
}

/**
 * A goblin on a great grey warg. Front views show the warg in profile heading
 * down-left with its face to us; back views mirror it, head up and to the
 * right and turned away, the rider seen from behind.
 */
function drawWolfRider(x: CanvasRenderingContext2D, s: Style, pose: Pose, rng: Rng) {
  const r = s.rider!;
  if (pose === 'dead') {
    // The warg on its side, legs out; the rider sprawled beside it.
    x.save();
    x.translate(0, -2);
    x.scale(1, 0.62);
    x.translate(0, 26);
    wolfProfile(x, s, { lunge: 0, run: false, away: false, dead: true }, rng);
    x.restore();
    // The rider thrown clear, lying in front of the warg.
    x.save();
    x.translate(-18, 10);
    x.scale(0.8, 0.5);
    x.rotate(-1.4);
    drawBody(x, r, 'idle_f', rng);
    x.restore();
    spear(x, 30, 12, 1.45, 96, s.rags);
    return;
  }
  const back = pose === 'idle_b' || pose === 'atk_b' || pose === 'flee_b' || pose === 'idle_bs' || pose === 'atk_bs';
  const atk = pose === 'atk_f' || pose === 'atk_b' || pose === 'atk_fs' || pose === 'atk_bs';
  const run = pose === 'flee_b';
  const lunge = atk ? 1 : 0;
  // The warg leans downhill toward the viewer, uphill away from him.
  const tilt = back ? 0.08 : -0.04;
  const mirror = back ? -1 : 1;
  const place = (px: number, py: number) => [mirror * (px * Math.cos(tilt) - py * Math.sin(tilt)), px * Math.sin(tilt) + py * Math.cos(tilt)];
  x.save();
  x.scale(mirror, 1);
  x.rotate(tilt);
  wolfProfile(x, s, { lunge, run, away: back, dead: false }, rng);
  // Saddle blanket with a ragged hem, and the saddle.
  poly(x, [[-8, -64], [24, -62], [26, -46], [20, -42], [16, -47], [10, -41], [4, -47], [-2, -42], [-8, -48]], s.rags!, 1.8);
  poly(x, [[-6, -69], [20, -67], [21, -60], [-4, -61]], '#5a3a22', 1.8);
  poly(x, [[15, -74], [24, -72], [22, -63], [15, -65]], '#4a2f1c', 1.6);
  x.restore();
  const [sx, sy] = place(5, -70);
  if (!back) {
    // Rider astride, leaning over the neck, spear couched toward the enemy.
    limb(x, sx - 2, sy + 2, sx - 10, sy + 13, 10, r.trousers);
    limb(x, sx - 10, sy + 13, sx - 7, sy + 24, 8.5, r.trousers);
    poly(x, [[sx - 14, sy + 21], [sx - 3, sy + 21], [sx - 1, sy + 28], [sx - 16, sy + 28]], r.boots, 1.6);
    const lean = -0.28 - lunge * 0.15;
    x.save();
    x.translate(sx, sy);
    x.rotate(lean);
    poly(x, [[-12, 0], [12, 0], [10, -34], [-10, -34]], r.tunic, 2);
    poly(x, [[-6, -32], [6, -32], [7, -4], [-7, -4]], r.tabard, 1.6);
    head(x, -2, -46, r, false, rng);
    x.restore();
    const shx = sx + Math.sin(lean) * -30 - 6;
    const shy = sy - 28;
    const spx = shx - 4 - lunge * 16;
    const spy = shy + 12 - lunge * 2;
    spear(x, spx, spy, atk ? -1.5 : -1.22, 104, r.rags);
    limb(x, shx, shy, spx, spy, 9, r.skin);
    x.fillStyle = r.skin;
    x.beginPath();
    x.arc(spx, spy, 4.5, 0, Math.PI * 2);
    x.fill();
    x.lineWidth = 1.8;
    x.strokeStyle = INK;
    x.stroke();
    return;
  }
  // Rider from behind: legs either side of the saddle, back to us.
  limb(x, sx + 7, sy + 2, sx + 12, sy + 16, 9, r.trousers);
  limb(x, sx - 6, sy + 2, sx - 13, sy + 13, 10, r.trousers);
  limb(x, sx - 13, sy + 13, sx - 11, sy + 24, 8.5, r.trousers);
  poly(x, [[sx - 18, sy + 21], [sx - 7, sy + 21], [sx - 5, sy + 28], [sx - 20, sy + 28]], r.boots, 1.6);
  const lean = 0.2 + lunge * 0.15;
  x.save();
  x.translate(sx, sy);
  x.rotate(lean);
  poly(x, [[-12, 0], [12, 0], [10, -34], [-10, -34]], r.tunic, 2);
  head(x, 2, -46, r, true, rng);
  x.restore();
  if (run) {
    limb(x, sx - 8, sy - 26, sx - 22, sy - 44, 9, r.skin);
    return;
  }
  const shx = sx + 12;
  const shy = sy - 26;
  spear(x, shx + 8 + lunge * 12, shy + 4, atk ? 1.42 : 1.15, 104, r.rags);
  limb(x, shx, shy, shx + 8 + lunge * 12, shy + 4, 9, r.skin);
}

// ---------------------------------------------------------------- horseman

type Gait = 'stand' | 'reach' | 'gather';

/** A hoof under a leg's last spine point. */
function hoof(x: CanvasRenderingContext2D, px: number, py: number, ang = 0) {
  x.save();
  x.translate(px, py);
  x.rotate(ang);
  poly(x, [[-5, -5], [5, -5], [7, 3], [-7, 3]], '#2e2622', 1.8);
  x.restore();
}

/**
 * A warhorse in profile, head to the left: far legs, tail, barrel, near legs,
 * saddle cloth, neck and mane, head and bridle. `away` turns the head from the
 * viewer (back views draw the profile mirrored). Galloping horses are lifted
 * clear of the ground in the reaching stride.
 */
function horseProfile(x: CanvasRenderingContext2D, s: Style, gait: Gait, away: boolean) {
  const coat = s.skin;
  const dark = shade(coat, -0.32);
  const light = shade(coat, 0.22);
  const mane = s.hair;
  const cloth = s.tabard;
  const trim = s.gold ?? GOLD;
  type Legs = { nf: number[][]; ff: number[][]; nh: number[][]; fh: number[][] };
  const legs: Legs =
    gait === 'reach'
      ? {
          nf: [[-40, -58], [-58, -48], [-74, -40], [-88, -38]],
          ff: [[-32, -58], [-46, -50], [-58, -40], [-68, -34]],
          nh: [[40, -62], [56, -50], [72, -42], [88, -40]],
          fh: [[32, -60], [46, -50], [60, -42], [72, -36]],
        }
      : gait === 'gather'
        ? {
            nf: [[-40, -58], [-46, -42], [-38, -30], [-44, -20]],
            ff: [[-32, -58], [-30, -38], [-30, -20], [-34, -4]],
            nh: [[40, -62], [26, -44], [18, -26], [8, -12]],
            fh: [[32, -60], [24, -40], [30, -22], [24, -4]],
          }
        : {
            nf: [[-40, -58], [-40, -38], [-41, -20], [-43, -5]],
            ff: [[-30, -58], [-28, -38], [-28, -20], [-30, -5]],
            nh: [[40, -62], [34, -40], [44, -24], [42, -5]],
            fh: [[30, -60], [24, -40], [33, -24], [31, -5]],
          };
  const footAng = (leg: number[][]) => Math.atan2(leg[3][1] - leg[2][1], leg[3][0] - leg[2][0]) - Math.PI / 2;
  const leg = (pts: number[][], w: number[], col: string) => {
    wolfLeg(x, pts, w, col, false);
    hoof(x, pts[3][0], pts[3][1], footAng(pts));
  };
  leg(legs.ff, [13, 8, 6.5, 6.5], dark);
  leg(legs.fh, [16, 10, 7, 6.5], dark);
  // Tail: streaming behind at the gallop, hanging when it stands.
  const tail = gait === 'stand' ? [[56, -80], [64, -68], [66, -50], [64, -32]] : [[56, -80], [72, -78], [88, -72], [100, -62]];
  const ts = tubeSides(tail, [8, 13, 13, 5]);
  const brush = [...ts.L, [tail[3][0] + (tail[3][0] - tail[2][0]) * 0.5, tail[3][1] + (tail[3][1] - tail[2][1]) * 0.5], ...[...ts.R].reverse()];
  x.beginPath();
  smoothPath(x, brush, true);
  x.fillStyle = mane;
  x.fill();
  x.lineWidth = 2.2;
  x.strokeStyle = INK;
  x.stroke();
  x.strokeStyle = shade(mane, 0.3);
  x.lineWidth = 1.3;
  for (const k of [0.3, 0.6]) {
    x.beginPath();
    x.moveTo(tail[1][0], tail[1][1] - 2 + k * 4);
    x.quadraticCurveTo(tail[2][0], tail[2][1] + k * 6 - 3, tail[3][0] - 4, tail[3][1] + k * 4);
    x.stroke();
  }
  // Barrel: deep through the girth, round over the quarters.
  const body = () => {
    x.beginPath();
    x.moveTo(-30, -86);
    x.quadraticCurveTo(-10, -90, 14, -83);
    x.quadraticCurveTo(36, -80, 46, -84);
    x.quadraticCurveTo(61, -81, 59, -64);
    x.quadraticCurveTo(57, -48, 42, -47);
    x.quadraticCurveTo(20, -49, 4, -45);
    x.quadraticCurveTo(-22, -40, -38, -46);
    x.quadraticCurveTo(-55, -52, -53, -66);
    x.quadraticCurveTo(-51, -81, -30, -86);
    x.closePath();
  };
  x.save();
  body();
  x.fillStyle = coat;
  x.fill();
  x.clip();
  const under = x.createLinearGradient(0, -66, 0, -42);
  under.addColorStop(0, 'rgba(20,12,8,0)');
  under.addColorStop(1, 'rgba(20,12,8,0.34)');
  x.fillStyle = under;
  x.fillRect(-70, -66, 140, 26);
  const top = x.createLinearGradient(-40, -92, 0, -66);
  top.addColorStop(0, 'rgba(255,250,235,0.32)');
  top.addColorStop(1, 'rgba(255,250,235,0)');
  x.fillStyle = top;
  x.fillRect(-70, -96, 140, 34);
  x.restore();
  body();
  x.lineWidth = 2.6;
  x.strokeStyle = INK;
  x.stroke();
  // Near legs, with the haunch and forearm swelling out of the body.
  leg(legs.nh, [20, 12, 8, 7.5], coat);
  muscle(x, 44, -66, 17, 17, -0.3, coat, 0.2, Math.PI * 1.05);
  leg(legs.nf, [16, 10, 7.5, 7.5], coat);
  muscle(x, -38, -62, 11, 15, 0.25, coat, Math.PI * 0.35, Math.PI * 0.95);
  // Saddle cloth in the company's colours, with a gold hem, and the breast strap.
  const flap = gait === 'reach' ? 3 : gait === 'gather' ? -2 : 0;
  poly(x, [[-18, -88], [30, -84], [32 + flap, -56], [24, -52 + flap], [12, -55], [0, -52 + flap], [-12, -55], [-20, -58]], cloth, 2);
  x.strokeStyle = trim;
  x.lineWidth = 3;
  x.beginPath();
  x.moveTo(30.5 + flap, -60);
  x.lineTo(24, -55 + flap);
  x.lineTo(12, -58);
  x.lineTo(0, -55 + flap);
  x.lineTo(-12, -58);
  x.lineTo(-19, -60);
  x.stroke();
  // A white star on the cloth.
  x.fillStyle = '#f2eee4';
  x.beginPath();
  for (let i = 0; i < 10; i++) {
    const a = -Math.PI / 2 + (i * Math.PI) / 5;
    const rr = i % 2 ? 2.6 : 6.4;
    const px = 7 + Math.cos(a) * rr;
    const py = -70 + Math.sin(a) * rr;
    if (i) x.lineTo(px, py);
    else x.moveTo(px, py);
  }
  x.closePath();
  x.fill();
  // Saddle: seat, pommel and cantle.
  poly(x, [[-10, -92], [22, -90], [20, -83], [-8, -84]], '#5a3a22', 1.8);
  poly(x, [[-12, -98], [-5, -96], [-6, -88], [-12, -89]], '#4a2f1c', 1.6);
  poly(x, [[17, -99], [25, -98], [23, -89], [17, -90]], '#4a2f1c', 1.6);
  for (const [w, col] of [[6.5, INK], [4, '#4a2f1c']] as [number, string][]) {
    x.lineWidth = w;
    x.strokeStyle = col;
    x.beginPath();
    x.moveTo(-18, -82);
    x.quadraticCurveTo(-44, -76, -48, -60);
    x.stroke();
  }
  for (const bx of [-32, -42]) {
    x.fillStyle = trim;
    x.beginPath();
    x.arc(bx, bx === -32 ? -77 : -69, 2.6, 0, Math.PI * 2);
    x.fill();
    x.lineWidth = 1.2;
    x.strokeStyle = INK;
    x.stroke();
  }
  // Neck, arched, thrown forward at the gallop.
  const reach = gait === 'reach' ? 1 : 0;
  const hx = -64 - reach * 8;
  const hy = -118 + reach * 12;
  wolfLeg(x, [[-34, -76], [-46, -98], [hx + 6, hy + 2]], [36, 28, 20], coat, false);
  // Mane along the crest, blown back.
  const crest = (k: number) => [-34 + (hx + 4 + 34) * k + 0, -88 + (hy - 6 + 88) * k];
  const base = [crest(0), crest(0.25), crest(0.5), crest(0.75), crest(1)].reverse();
  tufts(x, base, 9 + reach * 4, 4, mane);
  // The head: long, angled toward the ground, ears pricked.
  const turn = away ? 0 : 1;
  poly(x, [[hx + 4, hy - 4], [hx + 8, hy - 22], [hx + 12, hy - 4]], dark, 1.8);
  if (turn) poly(x, [[hx - 2, hy - 4], [hx, hy - 21], [hx + 6, hy - 6]], coat, 1.8);
  const ang = 0.75 - reach * 0.25;
  x.save();
  x.translate(hx, hy);
  // Head drawn along +x from the poll to the muzzle, then turned down toward the lower left.
  x.rotate(-ang);
  x.scale(-1, 1);
  const headPath = () => {
    x.beginPath();
    x.moveTo(-2, -9);
    x.quadraticCurveTo(14, -10, 34, -6);
    x.quadraticCurveTo(44, -4, 44, 3);
    x.quadraticCurveTo(44, 9, 36, 9);
    x.quadraticCurveTo(24, 10, 16, 12);
    x.quadraticCurveTo(4, 16, -6, 8);
    x.quadraticCurveTo(-10, -2, -2, -9);
    x.closePath();
  };
  headPath();
  x.fillStyle = away ? dark : coat;
  x.fill();
  x.save();
  x.clip();
  x.fillStyle = light;
  x.globalAlpha = 0.6;
  x.fillRect(-12, -14, 60, 7);
  x.globalAlpha = 1;
  x.fillStyle = shade(coat, -0.2);
  x.fillRect(28, -2, 20, 14);
  x.restore();
  headPath();
  x.lineWidth = 2.2;
  x.strokeStyle = INK;
  x.stroke();
  if (turn) {
    // Jowl, eye, nostril, and the bridle.
    x.beginPath();
    x.arc(4, 3, 7, 0.2, Math.PI * 1.1);
    x.lineWidth = 1.6;
    x.stroke();
    x.fillStyle = '#1a1412';
    x.beginPath();
    x.ellipse(8, -4, 2.6, 2.2, 0, 0, Math.PI * 2);
    x.fill();
    x.fillStyle = 'rgba(255,255,255,0.7)';
    x.fillRect(7.4, -5.4, 1.2, 1.2);
    x.fillStyle = '#1a1412';
    x.beginPath();
    x.ellipse(40, 0, 2.4, 1.6, 0.3, 0, Math.PI * 2);
    x.fill();
    if (gait !== 'stand') {
      // Mouth open on the bit at the gallop.
      x.strokeStyle = INK;
      x.lineWidth = 1.6;
      x.beginPath();
      x.moveTo(43, 6);
      x.lineTo(32, 9);
      x.stroke();
    }
  }
  x.strokeStyle = '#3a2416';
  x.lineWidth = 2.6;
  x.beginPath();
  x.moveTo(30, -7);
  x.lineTo(30, 10);
  x.moveTo(2, -9);
  x.lineTo(30, 4);
  x.stroke();
  x.fillStyle = trim;
  x.beginPath();
  x.arc(31, 6, 2.2, 0, Math.PI * 2);
  x.fill();
  x.restore();
}

/**
 * One of the Margrave's riders: a knight on a warhorse with a couched lance
 * and a pennant. Front views show the horse heading down-left; back views
 * mirror it and show the rider's back and cloak. `run_*` poses are the
 * gathered stride of the gallop, `atk_*` the reaching stride.
 */
function drawHorseRider(x: CanvasRenderingContext2D, s: Style, pose: Pose, rng: Rng) {
  const r = s.rider!;
  const back = pose === 'idle_b' || pose === 'atk_b' || pose === 'run_b' || pose === 'flee_b';
  const gait: Gait = pose.startsWith('atk') ? 'reach' : pose.startsWith('run') || pose === 'flee_b' ? 'gather' : 'stand';
  const lift = gait === 'reach' ? -10 : gait === 'gather' ? -3 : 0;
  const mirror = back ? -1 : 1;
  const tilt = (back ? 0.06 : -0.03) + (gait === 'reach' ? -0.03 : gait === 'gather' ? 0.04 : 0);
  const place = (px: number, py: number) => [mirror * (px * Math.cos(tilt) - py * Math.sin(tilt)), px * Math.sin(tilt) + py * Math.cos(tilt) + lift];
  x.save();
  x.translate(0, lift);
  x.scale(mirror, 1);
  x.rotate(tilt);
  horseProfile(x, s, gait, back);
  x.restore();
  const [sx, sy] = place(6, -94);
  const charge = gait === 'stand' ? 0 : 1;
  // Cloak streaming behind at the gallop.
  const flutter = gait === 'reach' ? 6 : 0;
  if (!back) {
    poly(x, [[sx + 6, sy - 34], [sx + 12, sy - 32], [sx + 10 + 26 * charge, sy - 14 + flutter], [sx + 16 + 20 * charge, sy + 4], [sx + 4, sy + 2]], r.tabard, 2);
  }
  // Legs: thigh along the saddle, knee forward, foot in the stirrup.
  const fx = sx - 12 * mirror;
  limb(x, sx, sy + 2, fx, sy + 14, 12, r.trousers);
  limb(x, fx, sy + 14, fx + 2 * mirror, sy + 30, 10, r.trousers);
  poly(x, [[fx - 7, sy + 26], [fx + 7, sy + 26], [fx + 8, sy + 34], [fx - 9, sy + 34]], r.boots, 1.6);
  // Torso in plate and tabard, leaning into the charge.
  const lean = mirror * (back ? 0.12 : -0.12) * charge;
  x.save();
  x.translate(sx, sy);
  x.rotate(lean);
  poly(x, [[-14, 2], [14, 2], [12, -38], [-12, -38]], back ? r.tabard : '#b9c0c8', 2.2);
  if (!back) {
    poly(x, [[-8, -36], [8, -36], [9, 0], [-9, 0]], r.tabard, 1.8);
    x.strokeStyle = r.gold ?? GOLD;
    x.lineWidth = 2;
    x.beginPath();
    x.moveTo(-8, -18);
    x.lineTo(8, -18);
    x.stroke();
  } else {
    // Cloak over the back, swinging out behind.
    poly(x, [[-14, -36], [14, -36], [17 + flutter * 0.5, 4], [4, 8], [-16 - flutter * 0.5, 4]], r.tabard, 2);
    x.strokeStyle = shade(r.tabard, -0.25);
    x.lineWidth = 1.4;
    for (const k of [-6, 4]) {
      x.beginPath();
      x.moveTo(k, -30);
      x.lineTo(k + 2, 2);
      x.stroke();
    }
  }
  head(x, back ? 1 : -2, -50, r, back, rng);
  x.restore();
  // Lance couched under the arm, pennant snapping at the tip.
  const shx = sx + Math.sin(lean) * 30 - 2 * mirror;
  const shy = sy - 30;
  const la = back ? (charge ? -0.12 : -1.1) : charge ? Math.PI + 0.12 : Math.PI + 1.1;
  const hand = [shx - mirror * 6, shy + 14];
  const len = 150;
  const tip = [hand[0] + Math.cos(la) * len * 0.78, hand[1] + Math.sin(la) * len * 0.78];
  const butt = [hand[0] - Math.cos(la) * len * 0.22, hand[1] - Math.sin(la) * len * 0.22];
  for (const [w, col] of [[6.5, INK], [4, WOOD]] as [number, string][]) {
    x.lineWidth = w;
    x.strokeStyle = col;
    x.beginPath();
    x.moveTo(butt[0], butt[1]);
    x.lineTo(tip[0], tip[1]);
    x.stroke();
  }
  const ux = Math.cos(la);
  const uy = Math.sin(la);
  poly(x, [[tip[0] + ux * 16, tip[1] + uy * 16], [tip[0] - uy * 3.5, tip[1] + ux * 3.5], [tip[0] + uy * 3.5, tip[1] - ux * 3.5]], STEEL, 1.6);
  // Pennant: a swallowtail trailing back from just below the head.
  const p0 = [tip[0] - ux * 6, tip[1] - uy * 6];
  const p1 = [tip[0] - ux * 30, tip[1] - uy * 30];
  const wave = charge ? 4 : 1;
  poly(x, [p0, [p0[0] - ux * 8, p0[1] + 12 + wave], [p1[0] - ux * 6, p1[1] + 18 + wave], [p1[0] + ux * 2, p1[1] + 10], [p1[0], p1[1]]], '#f2eee4', 1.6);
  poly(x, [p0, [p0[0] - ux * 6, p0[1] + 6], [p1[0], p1[1] + 5], [p1[0], p1[1]]], r.tabard, 0);
  limb(x, shx, shy, hand[0], hand[1], 10, '#b9c0c8');
  x.fillStyle = r.gauntlet ?? '#5a5f66';
  x.beginPath();
  x.arc(hand[0], hand[1], 5, 0, Math.PI * 2);
  x.fill();
  x.lineWidth = 1.8;
  x.strokeStyle = INK;
  x.stroke();
}

// ---------------------------------------------------------------- troll

/** Bark-and-rope wrapping round a limb segment. */
function wrap(x: CanvasRenderingContext2D, ax: number, ay: number, bx: number, by: number, w: number, col: string) {
  const len = Math.hypot(bx - ax, by - ay) || 1;
  const nx = (-(by - ay) / len) * w * 0.5;
  const ny = ((bx - ax) / len) * w * 0.5;
  poly(x, [[ax + nx, ay + ny], [bx + nx * 0.92, by + ny * 0.92], [bx - nx * 0.92, by - ny * 0.92], [ax - nx, ay - ny]], col, 2);
  x.strokeStyle = '#b39462';
  x.lineWidth = 1.6;
  const n = Math.max(2, Math.round(len / 7));
  for (let i = 0; i < n; i++) {
    const f = (i + 0.5) / n;
    const px = ax + (bx - ax) * f;
    const py = ay + (by - ay) * f;
    x.beginPath();
    x.moveTo(px + nx * 0.9 - (bx - ax) / len * 2.5, py + ny * 0.9 - (by - ay) / len * 2.5);
    x.lineTo(px - nx * 0.9 + (bx - ax) / len * 2.5, py - ny * 0.9 + (by - ay) / len * 2.5);
    x.stroke();
  }
}

/** Big bare troll foot, toes pointing in `dir` (-1 left, 1 right). */
function bigFoot(x: CanvasRenderingContext2D, hx: number, gy: number, dir: number, skin: string) {
  const path = () => {
    x.beginPath();
    x.moveTo(hx - dir * 13, gy - 17);
    x.quadraticCurveTo(hx - dir * 23, gy - 2, hx - dir * 10, gy);
    x.lineTo(hx + dir * 22, gy);
    x.quadraticCurveTo(hx + dir * 31, gy - 6, hx + dir * 20, gy - 13);
    x.quadraticCurveTo(hx + dir * 6, gy - 20, hx - dir * 13, gy - 17);
    x.closePath();
  };
  cel(x, path, skin, hx + 6, 2.4, -0.28, 0.15);
  for (let k = 0; k < 4; k++) {
    x.beginPath();
    x.ellipse(hx + dir * (24 - k * 6.5), gy - 3.8 - k * 0.6, 4.2 - k * 0.3, 3.6, 0, 0, Math.PI * 2);
    x.fillStyle = shade(skin, 0.08);
    x.fill();
    x.lineWidth = 1.4;
    x.strokeStyle = INK;
    x.stroke();
  }
}

/**
 * Hunched moss troll carrying an uprooted log. Front views face down-left with
 * the head low and forward under a mossy hump; back views show the hump.
 * The body is a mass of dark stringy hair with moss on top; the big pale arms,
 * legs and the face stand out against it.
 */
function drawTroll(x: CanvasRenderingContext2D, s: Style, pose: Pose, rng: Rng) {
  const t = s.troll!;
  const seed = rng.state;
  const R = (k: number) => new Rng(seed + k * 7919);
  const back = pose === 'idle_b' || pose === 'atk_b' || pose === 'flee_b';
  const atk = pose === 'atk_f' || pose === 'atk_b';
  const flee = pose === 'flee_b';
  const holding = pose !== 'dead' && !flee;
  // Back views mirror the hunched mass so its head end points up-right.
  const m = back ? -1 : 1;
  const X = (v: number) => v * m;
  const skin = s.skin;
  const logSeed = seed + 11;

  // Log from its butt end to the root ball; hands grip along it. Idle: carried
  // low with the roots forward; attack: heaved up overhead to smash down.
  let log: number[] | null = null;
  if (holding) log = atk ? [X(40), -140, X(-100), -270] : back ? [-60, -84, 118, -46] : [56, -96, -118, -14];
  const along = (f: number) => (log ? [log[0] + (log[2] - log[0]) * f, log[1] + (log[3] - log[1]) * f] : [0, 0]);
  const drawLog = () => log && trollLog(x, log[0], log[1], log[2], log[3], t, logSeed);
  // Carried low in a back view, the log lies mostly hidden in front of the troll.
  if (log && back && !atk) drawLog();

  // Legs: bare thighs, bark-wrapped shins, big feet.
  const spread = flee ? 1.35 : atk ? 1.2 : 1;
  for (const L of [
    { hip: X(26), knee: X(33 * spread), foot: X(35 * spread), lift: flee ? -10 : 0 },
    { hip: X(-24), knee: X(-33 * spread), foot: X(-35 * spread), lift: 0 },
  ]) {
    capsule(x, L.hip, -90, L.knee, -46, 34, skin);
    capsule(x, L.knee, -46, L.foot, -16 + L.lift, 30, skin);
    wrap(x, L.knee, -42, L.foot, -14 + L.lift, 33, s.trousers);
    bigFoot(x, L.foot, L.lift, -m, skin);
  }

  // Mantle: the dark hair mass from the hump down to the thighs, ragged at the hem.
  const mr = R(2);
  const hem: number[][] = [];
  for (let i = 0; i <= 16; i++) {
    const f = i / 16;
    const long = i % 2 ? 10 + mr.range(0, 16) : -4 + mr.range(0, 4);
    hem.push([X(80 - f * 130), -80 + f * 8 + long]);
  }
  const mantle = () => {
    x.beginPath();
    x.moveTo(X(-44), -178);
    x.quadraticCurveTo(X(-38), -222, X(4), -232);
    x.quadraticCurveTo(X(60), -244, X(86), -192);
    x.quadraticCurveTo(X(102), -140, X(80), -80);
    for (const [px, py] of hem) x.lineTo(px, py);
    x.quadraticCurveTo(X(-76), -110, X(-62), -160);
    x.closePath();
  };
  cel(x, mantle, t.mantle, 30, 2.6, -0.3, 0.16);
  x.save();
  mantle();
  x.clip();
  for (let i = 0; i < 13; i++) {
    const f = i / 12;
    const px = X(-50 + f * 140);
    const top = -206 - Math.sin(f * Math.PI) * 26;
    x.strokeStyle = i % 3 === 0 ? shade(t.mantle, -0.32) : shade(t.mantle, 0.2);
    x.lineWidth = i % 3 === 0 ? 2 : 1.4;
    x.beginPath();
    x.moveTo(px, top);
    x.bezierCurveTo(px + X(9), top + 50, px - X(7), top + 100, px + X(mr.range(-3, 5)), -60);
    x.stroke();
  }
  x.restore();

  // Moss in a thick cap along the ridge of the hump, twigs poking out, shelf fungus on top.
  const ridge: number[][] = [[-40, -198], [-22, -219], [4, -231], [32, -237], [58, -229], [78, -209], [92, -180], [98, -150]];
  const gr = R(3);
  for (const k of t.twigs) {
    const [px, py] = ridge[Math.min(ridge.length - 1, k)];
    twig(x, X(px), py + 8, X(-0.6 + (k / 7) * 1.4) + gr.range(-0.15, 0.15), gr.range(28, 40));
  }
  const discs: number[][] = [];
  const mk = 0.75 + t.mossAmt * 0.25;
  ridge.forEach(([px, py], i) => {
    if (i === ridge.length - 1 && t.mossAmt < 1) return;
    discs.push([X(px) + gr.range(-3, 3), py + 4 + gr.range(-2, 3), gr.range(10, 14) * mk]);
    if (i < ridge.length - 1) {
      const [qx, qy] = ridge[i + 1];
      discs.push([X((px + qx) / 2) + gr.range(-3, 3), (py + qy) / 2 + 12 + gr.range(0, 6) * t.mossAmt, gr.range(8, 12) * mk]);
    }
  });
  if (t.mossAmt > 1.05) discs.push([X(94), -124, 10], [X(-10), -206, 11]);
  // Moss drips hanging into the hair (under the clump).
  for (let i = 0; i < Math.round(2 + t.mossAmt * 4); i++) {
    const [px, py] = ridge[1 + Math.floor(gr.next() * (ridge.length - 2))];
    const dx = X(px + gr.range(-6, 6));
    const len = 24 + gr.range(0, 20);
    for (const [col, lw] of [[INK, 6], [t.moss, 3.4]] as const) {
      x.strokeStyle = col;
      x.lineWidth = lw;
      x.beginPath();
      x.moveTo(dx, py + 8);
      x.lineTo(dx + gr.range(-2, 2), py + len);
      x.stroke();
    }
  }
  mossClump(x, discs, t.moss);
  for (const k of t.fungus) {
    if (k > 6) continue;
    const [px, py] = ridge[k];
    fungus(x, X(px + (k < 4 ? -6 : 6)), py + 12, 1.3);
  }

  // Arms: two-segment with the elbow bent outward; shoulders carry their own moss.
  const ik = (sx: number, sy: number, hx: number, hy: number, out: number) => {
    const dx = hx - sx;
    const dy = hy - sy;
    const d = Math.hypot(dx, dy) || 1;
    const seg = 50;
    const h = d >= seg * 2 ? 0 : Math.sqrt(seg * seg - (d / 2) * (d / 2));
    let nx = -dy / d;
    let ny = dx / d;
    if (nx * out < 0) {
      nx = -nx;
      ny = -ny;
    }
    return [(sx + hx) / 2 + nx * h, (sy + hy) / 2 + ny * h];
  };
  const drawArm = (sx: number, sy: number, hx: number, hy: number, out: number) => {
    const [ex, ey] = ik(sx, sy, hx, hy, out);
    capsule(x, sx, sy, ex, ey, 34, skin);
    spiral(x, sx + (ex - sx) * 0.55, sy + (ey - sy) * 0.55, 7.5, t.tattoo);
    capsule(x, ex, ey, hx, hy, 30, skin);
    spiral(x, ex + (hx - ex) * 0.3, ey + (hy - ey) * 0.3, 5, t.tattoo);
    wrap(x, ex + (hx - ex) * 0.6, ey + (hy - ey) * 0.6, ex + (hx - ex) * 0.84, ey + (hy - ey) * 0.84, 32, s.trousers);
    // Big rounded shoulder under a clump of moss.
    const sh = () => {
      x.beginPath();
      x.ellipse(sx, sy, 20, 18, 0, 0, Math.PI * 2);
    };
    cel(x, sh, skin, sx + 7, 2.4, -0.25, 0.18);
    const ar = R(5 + Math.round(Math.abs(sx)));
    mossClump(x, [[sx - 6, sy - 13, 9 * mk], [sx + 5, sy - 15, 10 * mk], [sx + 13, sy - 8, 6 + ar.range(0, 3)]], t.moss);
  };
  const fist = (hx: number, hy: number) => {
    const p = () => {
      x.beginPath();
      x.ellipse(hx, hy, 15, 13, 0, 0, Math.PI * 2);
    };
    cel(x, p, skin, hx + 4, 2.4, -0.3, 0.15);
    x.strokeStyle = shade(skin, -0.45);
    x.lineWidth = 1.6;
    for (let k = -1; k <= 1; k++) {
      x.beginPath();
      x.moveTo(hx + k * 5.5 - 1, hy - 11);
      x.lineTo(hx + k * 5.5 + 1, hy + 1);
      x.stroke();
    }
  };
  const sNear = [X(-60), -156];
  const sFar = [X(62), -168];
  let hNear: number[];
  let hFar: number[];
  if (flee) {
    hNear = [X(-94), -214];
    hFar = [X(92), -220];
  } else if (!log) {
    hNear = [X(-50), -66];
    hFar = [X(34), -74];
  } else if (back && !atk) {
    hNear = along(0.72);
    hFar = along(0.06);
  } else {
    hNear = along(atk ? 0.34 : 0.46);
    hFar = along(atk ? 0.14 : 0.18);
  }
  drawArm(sFar[0], sFar[1], hFar[0], hFar[1], m);
  drawArm(sNear[0], sNear[1], hNear[0], hNear[1], -m);

  // Head, low and forward under the hump (hidden behind it from the back).
  if (!back) {
    const hx = -52;
    const hy = -174;
    const hr = 20;
    const hrng = R(4);
    const streak = shade(s.hair, 0.4);
    // Curtain of long hair behind the face, falling over the chest.
    const curtain: number[][] = [[hx - 18, hy - 14], [hx + 18, hy - 16]];
    for (let i = 0; i <= 8; i++) {
      const f = i / 8;
      curtain.push([hx + 28 - f * 60, hy + 54 + (i % 2 ? 14 : 0) + hrng.range(-3, 3)]);
    }
    poly(x, curtain, s.hair, 2);
    x.lineWidth = 1.5;
    for (let i = 0; i < 7; i++) {
      x.strokeStyle = i % 2 ? streak : shade(s.hair, -0.3);
      x.beginPath();
      x.moveTo(hx - 24 + i * 8.5, hy + 4);
      x.lineTo(hx - 27 + i * 9, hy + 56);
      x.stroke();
    }
    const skullP = () => {
      x.beginPath();
      x.ellipse(hx, hy, hr, hr * 1.04, 0, 0, Math.PI * 2);
    };
    cel(x, skullP, skin, hx + 5, 2.4, -0.25, 0.15);
    const fx = hx - hr * 0.3;
    // Stringy beard hanging below the nose.
    const bl = 44 * t.beard;
    const beard: number[][] = [[fx - 13, hy + 6], [fx + 16, hy + 6]];
    for (let i = 0; i <= 6; i++) {
      const f = i / 6;
      beard.push([fx + 16 - f * 31, hy + 6 + bl * (i % 2 ? 1 : 0.8) * (1 - Math.abs(f - 0.45) * 0.5)]);
    }
    poly(x, beard, s.hair, 2);
    x.strokeStyle = streak;
    x.lineWidth = 1.4;
    for (let i = 0; i < 4; i++) {
      const px = fx - 8 + i * 7.5;
      x.beginPath();
      x.moveTo(px, hy + 12);
      x.lineTo(px - 2, hy + 6 + bl * 0.72);
      x.stroke();
    }
    // Small deep-set eyes under a heavy brow.
    for (const [ex, ey] of [[fx - 8, hy - 5], [fx + 9, hy - 6]]) {
      x.beginPath();
      x.ellipse(ex, ey, 4, 2.8, 0, 0, Math.PI * 2);
      x.fillStyle = '#f0dc6a';
      x.fill();
      x.lineWidth = 1.2;
      x.strokeStyle = INK;
      x.stroke();
      x.fillStyle = '#1a120c';
      x.fillRect(ex - 1.2, ey - 2, 2.6, 4);
    }
    x.strokeStyle = INK;
    x.lineWidth = 3.4;
    x.beginPath();
    x.moveTo(fx - 14, hy - 11);
    x.quadraticCurveTo(fx + 1, hy - 7, fx + 15, hy - 12);
    x.stroke();
    // Hair cap and side locks framing the face.
    poly(x, [[hx - hr * 1.06, hy - hr * 0.2], [hx - hr * 0.9, hy - hr * 0.85], [hx - hr * 0.2, hy - hr * 1.16], [hx + hr * 0.75, hy - hr * 1.0], [hx + hr * 1.12, hy - hr * 0.25], [hx + hr * 0.6, hy - hr * 0.62], [hx - hr * 0.2, hy - hr * 0.78], [hx - hr * 0.85, hy - hr * 0.45]], s.hair, 2);
    poly(x, [[hx - hr * 1.06, hy - hr * 0.25], [hx - hr * 0.88, hy - hr * 0.1], [hx - hr * 1.08, hy + 40], [hx - hr * 1.42, hy + 46]], s.hair, 1.8);
    poly(x, [[hx + hr * 0.78, hy - hr * 0.4], [hx + hr * 1.1, hy - hr * 0.3], [hx + hr * 1.36, hy + 42], [hx + hr * 0.92, hy + 36]], s.hair, 1.8);
    // The very long drooping nose.
    const n = t.nose;
    const tipX = fx - 14 * n;
    const tipY = hy + 32 * n;
    const nose = () => {
      x.beginPath();
      x.moveTo(fx - 1, hy - 5);
      x.quadraticCurveTo(fx - 18 * n, hy + 7, tipX - 9, tipY - 3);
      x.quadraticCurveTo(tipX - 8, tipY + 11, tipX + 7, tipY + 5);
      x.quadraticCurveTo(fx + 4, hy + 16, fx + 6, hy - 3);
      x.closePath();
    };
    cel(x, nose, shade(skin, 0.14), fx - 3, 2.4, -0.25, 0.22);
    x.fillStyle = shade(skin, -0.45);
    x.beginPath();
    x.ellipse(tipX + 1, tipY + 3.5, 2.8, 1.8, -0.4, 0, Math.PI * 2);
    x.fill();
  }

  // The log over the body (front, or raised from behind), then the gripping fists.
  if (log && (!back || atk)) drawLog();
  fist(hFar[0], hFar[1]);
  fist(hNear[0], hNear[1]);
  // Fungus on the far shoulder.
  if (t.fungus.includes(7)) fungus(x, sFar[0] + X(6), sFar[1] - 10, 1.2);
}
