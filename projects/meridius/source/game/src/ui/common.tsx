import { useEffect, useRef, useState, type ReactNode } from 'react';
import type { Resources } from '../core/types';
import { UNIT_TYPES, squadSize } from '../data/units';
import { rankName, soldierStats, squadHpCap, type Soldier } from '../meta/soldier';
import { sprite } from '../render/assets';

// ---------------------------------------------------------------- icons

const ICONS: Record<string, (c: string) => ReactNode> = {
  silver: () => (
    <>
      <ellipse cx="12" cy="15" rx="8" ry="3.5" fill="#9aa0a6" stroke="#2b1d10" strokeWidth="1.2" />
      <ellipse cx="12" cy="12" rx="8" ry="3.5" fill="#c9ced2" stroke="#2b1d10" strokeWidth="1.2" />
      <ellipse cx="12" cy="9" rx="8" ry="3.5" fill="#e6e9eb" stroke="#2b1d10" strokeWidth="1.2" />
      <ellipse cx="12" cy="9" rx="4" ry="1.5" fill="none" stroke="#8a9096" strokeWidth="1" />
    </>
  ),
  timber: () => (
    <>
      <rect x="3" y="12" width="17" height="6" rx="3" fill="#9a6a3a" stroke="#2b1d10" strokeWidth="1.2" />
      <rect x="5" y="6" width="16" height="6" rx="3" fill="#b37c44" stroke="#2b1d10" strokeWidth="1.2" />
      <circle cx="18" cy="9" r="2" fill="#e0b47a" stroke="#2b1d10" />
      <circle cx="17" cy="15" r="2" fill="#e0b47a" stroke="#2b1d10" />
    </>
  ),
  iron: () => (
    <path d="M4 17 L7 9 H17 L20 17 Z" fill="#7d858c" stroke="#2b1d10" strokeWidth="1.3" strokeLinejoin="round" />
  ),
  trophies: () => (
    <>
      <rect x="6" y="3" width="1.8" height="18" fill="#5a3a22" />
      <path d="M8 4 L19 6 L15 10 L19 14 L8 13 Z" fill="#a3261c" stroke="#2b1d10" strokeWidth="1.2" strokeLinejoin="round" />
      <circle cx="12" cy="9" r="1.6" fill="#f0e2c0" />
    </>
  ),
  rations: () => (
    <path d="M3 15 C3 9 21 9 21 15 C21 17 3 17 3 15 Z M7 11 L8 13 M11 10.5 L12 12.5 M15 11 L16 13" fill="#c98e48" stroke="#2b1d10" strokeWidth="1.2" />
  ),
  bandages: () => (
    <>
      <circle cx="10" cy="12" r="6" fill="#f2ecdc" stroke="#2b1d10" strokeWidth="1.2" />
      <circle cx="10" cy="12" r="2" fill="#d9cfb3" stroke="#2b1d10" />
      <path d="M14 15 L21 18 L20 20 L13 17" fill="#f2ecdc" stroke="#2b1d10" strokeWidth="1.2" />
      <path d="M8.5 12 h3 M10 10.5 v3" stroke="#a3261c" strokeWidth="1.4" />
    </>
  ),
  bolts: () => (
    <>
      <path d="M4 19 L18 5" stroke="#5a3a22" strokeWidth="2" />
      <path d="M18 5 L20 3 L19 7 Z" fill="#cfd3d6" stroke="#2b1d10" />
      <path d="M8 21 L20 9" stroke="#5a3a22" strokeWidth="2" />
      <path d="M20 9 L22 7 L21 11 Z" fill="#cfd3d6" stroke="#2b1d10" />
      <path d="M4 19 l-1 -2 M4 19 l2 1" stroke="#efe8d4" strokeWidth="2" />
    </>
  ),
  torches: () => (
    <>
      <path d="M11 11 L13 11 L12.5 22 L11.5 22 Z" fill="#6b4426" stroke="#2b1d10" />
      <path d="M12 2 C16 6 15 10 12 11 C9 10 8 6 12 2 Z" fill="#f2a33a" stroke="#8a3a10" />
      <path d="M12 6 C13.5 8 13 10 12 10.5 C11 10 10.5 8 12 6 Z" fill="#ffe08a" />
    </>
  ),
  tools: () => (
    <>
      <path d="M5 20 L14 11" stroke="#6b4426" strokeWidth="2.6" strokeLinecap="round" />
      <path d="M12 6 L18 4 L20 10 L16 12 Z" fill="#8a9096" stroke="#2b1d10" strokeWidth="1.2" />
    </>
  ),
  hp: () => <path d="M12 20 C4 14 3 9 6 6.5 C8.5 4.5 11 6 12 8 C13 6 15.5 4.5 18 6.5 C21 9 20 14 12 20 Z" fill="#c8352a" stroke="#2b1d10" strokeWidth="1.2" />,
  morale: () => (
    <>
      <rect x="6" y="3" width="1.8" height="18" fill="#5a3a22" />
      <path d="M8 4 H19 L16.5 8 L19 12 H8 Z" fill="#2f58b8" stroke="#2b1d10" strokeWidth="1.2" />
    </>
  ),
  fatigue: () => <path d="M7 4 H12 V14 L18 15 C20 15.5 20 19 18 19 H6 Z" fill="#8a6038" stroke="#2b1d10" strokeWidth="1.2" strokeLinejoin="round" />,
  xp: () => <path d="M12 3 L14.6 9 L21 9.5 L16 13.6 L17.7 20 L12 16.4 L6.3 20 L8 13.6 L3 9.5 L9.4 9 Z" fill="#e8b84a" stroke="#2b1d10" strokeWidth="1.1" strokeLinejoin="round" />,
  cp: () => (
    <>
      <path d="M5 9 L12 4 L19 9" fill="none" stroke="#2f58b8" strokeWidth="2.4" strokeLinejoin="round" />
      <path d="M5 14 L12 9 L19 14" fill="none" stroke="#2f58b8" strokeWidth="2.4" strokeLinejoin="round" />
      <path d="M5 19 L12 14 L19 19" fill="none" stroke="#c99a3c" strokeWidth="2.4" strokeLinejoin="round" />
    </>
  ),
  slot: () => <path d="M12 3 L19 6 V12 C19 16 16 19 12 21 C8 19 5 16 5 12 V6 Z" fill="#e8dcc0" stroke="#2b1d10" strokeWidth="1.3" />,
  weight: () => (
    <>
      <path d="M5 10 H19 L17 20 H7 Z" fill="#8a6038" stroke="#2b1d10" strokeWidth="1.2" />
      <circle cx="12" cy="7" r="3" fill="none" stroke="#2b1d10" strokeWidth="1.5" />
    </>
  ),
  skull: () => (
    <>
      <path d="M12 3 C7 3 4.5 6.5 4.5 10.5 C4.5 13 6 14.5 7 15 V19 H17 V15 C18 14.5 19.5 13 19.5 10.5 C19.5 6.5 17 3 12 3 Z" fill="#efe8d4" stroke="#2b1d10" strokeWidth="1.2" />
      <circle cx="9" cy="11" r="2" fill="#2b1d10" />
      <circle cx="15" cy="11" r="2" fill="#2b1d10" />
    </>
  ),
  injury: () => <path d="M9 3 H15 V9 H21 V15 H15 V21 H9 V15 H3 V9 H9 Z" fill="#c8352a" stroke="#2b1d10" strokeWidth="1.2" />,
  sword: () => (
    <>
      <path d="M17 3 L21 3 L21 7 L9 19 L5 15 Z" fill="#d7dbe0" stroke="#2b1d10" strokeWidth="1.1" />
      <path d="M4 13 L11 20" stroke="#6b4426" strokeWidth="2.6" />
      <path d="M3 21 L6 18" stroke="#6b4426" strokeWidth="2.6" />
    </>
  ),
  shield: () => (
    <>
      <path d="M12 2.5 L20 5.5 V11 C20 16 16.5 19.5 12 21.5 C7.5 19.5 4 16 4 11 V5.5 Z" fill="#2f58b8" stroke="#2b1d10" strokeWidth="1.3" />
      <path d="M12 7 L15 11 L12 15 L9 11 Z" fill="#f2efe4" />
    </>
  ),
  spear: () => (
    <>
      <path d="M5 21 L17 7" stroke="#7a5532" strokeWidth="2.2" />
      <path d="M17 7 L21 2 L19.5 9 Z" fill="#d7dbe0" stroke="#2b1d10" strokeWidth="1.1" />
    </>
  ),
  crossbow: () => (
    <>
      <path d="M5 19 L17 7" stroke="#7a5532" strokeWidth="3" />
      <path d="M9 5 C14 6 18 10 19 15" fill="none" stroke="#4a2f1c" strokeWidth="2.2" />
      <path d="M9 5 L19 15" stroke="#ddd" strokeWidth="0.8" />
    </>
  ),
  march: () => (
    <>
      <ellipse cx="8" cy="15" rx="2.6" ry="4" fill="#6b4426" />
      <ellipse cx="15" cy="9" rx="2.6" ry="4" fill="#6b4426" />
    </>
  ),
  eye: () => (
    <>
      <path d="M2 12 C6 6 18 6 22 12 C18 18 6 18 2 12 Z" fill="#f2ecdc" stroke="#2b1d10" strokeWidth="1.2" />
      <circle cx="12" cy="12" r="3.4" fill="#c99a3c" stroke="#2b1d10" />
    </>
  ),
  bash: () => (
    <>
      <path d="M10 3 L17 5.5 V10 C17 14 14 17 10 18.5 C6 17 3 14 3 10 V5.5 Z" fill="#2f58b8" stroke="#2b1d10" strokeWidth="1.2" />
      <path d="M17 12 L22 10 M17 15 L22 15 M16 18 L21 20" stroke="#ffd76a" strokeWidth="1.6" />
    </>
  ),
  spearwall: () => (
    <>
      <path d="M4 21 L11 6 M10 21 L15 6 M16 21 L19 6" stroke="#7a5532" strokeWidth="1.8" />
      <path d="M11 6 L12 2 L9.5 5.5 Z M15 6 L16 2 L13.5 5.5 Z M19 6 L20 2 L17.5 5.5 Z" fill="#d7dbe0" stroke="#2b1d10" strokeWidth="0.8" />
    </>
  ),
  thrust: () => (
    <>
      <path d="M2 18 L16 9" stroke="#7a5532" strokeWidth="2" />
      <path d="M16 9 L22 5.5 L18.5 11 Z" fill="#d7dbe0" stroke="#2b1d10" />
      <path d="M17 15 L22 15 M18 18 L22 19" stroke="#ffd76a" strokeWidth="1.5" />
    </>
  ),
  bolt: () => (
    <>
      <path d="M3 21 L19 5" stroke="#5a3a22" strokeWidth="2.6" />
      <path d="M19 5 L22 2 L21 8 Z" fill="#cfd3d6" stroke="#2b1d10" />
      <path d="M8 6 L10 9 L7 10 L10 13" stroke="#ffd76a" strokeWidth="1.6" fill="none" />
    </>
  ),
  horn: () => <path d="M3 9 L12 7 C17 6 21 9 21 14 L17 15 C16 12 14 11 12 12 L3 13 Z" fill="#e9dcc0" stroke="#2b1d10" strokeWidth="1.2" />,
  charge: () => <path d="M3 8 H13 V4 L21 12 L13 20 V16 H3 Z" fill="#a3261c" stroke="#2b1d10" strokeWidth="1.2" />,
  rotl: () => <path d="M18 8 A7 7 0 1 0 19 15 M18 3 V8 H13" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" />,
  rotr: () => <path d="M6 8 A7 7 0 1 1 5 15 M6 3 V8 H11" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" />,
  sound: () => <path d="M4 9 H8 L13 5 V19 L8 15 H4 Z M16 9 C17.5 10.5 17.5 13.5 16 15 M18.5 7 C21 9.5 21 14.5 18.5 17" fill="none" stroke="currentColor" strokeWidth="1.8" />,
  mute: () => <path d="M4 9 H8 L13 5 V19 L8 15 H4 Z M16 9 L21 15 M21 9 L16 15" fill="none" stroke="currentColor" strokeWidth="1.8" />,
  grid: () => <path d="M12 3 L21 12 L12 21 L3 12 Z M7.5 7.5 L16.5 16.5 M16.5 7.5 L7.5 16.5" fill="none" stroke="currentColor" strokeWidth="1.6" />,
  danger: () => <path d="M12 3 L22 20 H2 Z M12 9 V14 M12 16.5 V17.5" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinejoin="round" />,
  // Spells and war machines.
  lightning: () => (
    <>
      <path d="M14 2 L5 13 H11 L8 22 L19 9 H13 L16 2 Z" fill="#9fd0ff" stroke="#1d3a6a" strokeWidth="1.3" strokeLinejoin="round" />
      <path d="M13.5 4 L8 11.5 H12" fill="none" stroke="#ffffff" strokeWidth="1" />
    </>
  ),
  frost: () => (
    <>
      <path d="M12 2 V22 M3.5 7 L20.5 17 M3.5 17 L20.5 7" stroke="#2a5a8a" strokeWidth="3.2" strokeLinecap="round" />
      <path d="M12 2 V22 M3.5 7 L20.5 17 M3.5 17 L20.5 7" stroke="#d4f0ff" strokeWidth="1.6" strokeLinecap="round" />
      <path d="M9.5 4 L12 6.5 L14.5 4 M9.5 20 L12 17.5 L14.5 20" fill="none" stroke="#d4f0ff" strokeWidth="1.3" />
    </>
  ),
  heal: () => (
    <>
      <circle cx="12" cy="12" r="9" fill="#fff0b0" stroke="#8a6a18" strokeWidth="1.2" />
      <path d="M10 6.5 H14 V10 H17.5 V14 H14 V17.5 H10 V14 H6.5 V10 H10 Z" fill="#5aa83a" stroke="#2b4a12" strokeWidth="1" />
    </>
  ),
  circle: () => (
    <>
      <ellipse cx="12" cy="14" rx="9.5" ry="5" fill="none" stroke="#c99a3c" strokeWidth="2.2" />
      <ellipse cx="12" cy="14" rx="5.5" ry="2.8" fill="#fff0b0" stroke="#8a6a18" strokeWidth="1" />
      <path d="M12 3 V9 M9 6 H15" stroke="#5aa83a" strokeWidth="2.2" />
    </>
  ),
  fire: () => (
    <>
      <path d="M12 2 C17 7 19 11 18 15 C17 19 14.5 21 12 21 C8 21 5.5 18 6 14 C6.5 11 9 10 9 6 C11 8 11.5 9 11.5 11 C13 9 13 5 12 2 Z" fill="#ff8a2a" stroke="#7a2a0a" strokeWidth="1.2" strokeLinejoin="round" />
      <path d="M12 12 C14.5 14 15 16 14 18 C13 19.5 11 19.5 10 18.2 C9 16.5 10.5 15 12 12 Z" fill="#ffe08a" />
    </>
  ),
  blood: () => (
    <>
      <path d="M12 2.5 C15.5 8 18.5 11 18.5 15 C18.5 18.6 15.6 21.5 12 21.5 C8.4 21.5 5.5 18.6 5.5 15 C5.5 11 8.5 8 12 2.5 Z" fill="#c8241a" stroke="#4a0a06" strokeWidth="1.2" />
      <path d="M8.5 13 L10.5 15 L8.5 17 M15.5 13 L13.5 15 L15.5 17" fill="none" stroke="#ffd0b0" strokeWidth="1.4" />
    </>
  ),
  gut: () => (
    <>
      <path d="M4 20 C6 14 4 9 8 6 C11 4 13 8 11 10 C9 12 12 14 15 12 C18 10 17 5 21 4" fill="none" stroke="#4a0a14" strokeWidth="3.4" strokeLinecap="round" />
      <path d="M4 20 C6 14 4 9 8 6 C11 4 13 8 11 10 C9 12 12 14 15 12 C18 10 17 5 21 4" fill="none" stroke="#d04050" strokeWidth="1.6" strokeLinecap="round" />
      <circle cx="18" cy="17" r="2.6" fill="#a6ff5a" stroke="#2b4a12" />
    </>
  ),
  stone: () => (
    <>
      <path d="M3 20 C6 12 10 8 16 6" fill="none" stroke="#c9b79a" strokeWidth="1.6" strokeDasharray="2 2.5" />
      <path d="M15 3 L20.5 4.5 L22 9.5 L18.5 13 L13.5 12 L12 7.5 Z" fill="#8a8378" stroke="#2b1d10" strokeWidth="1.3" strokeLinejoin="round" />
      <circle cx="15.5" cy="6.5" r="1.3" fill="#c9c2b4" />
    </>
  ),
  staff: () => (
    <>
      <path d="M6 21 L15 8" stroke="#6b4426" strokeWidth="2.4" strokeLinecap="round" />
      <circle cx="16.5" cy="6" r="3.6" fill="#9fd0ff" stroke="#1d3a6a" strokeWidth="1.2" />
      <path d="M16.5 1 V3 M21.5 6 H19.5 M20 2.5 L18.8 3.7" stroke="#e8f4ff" strokeWidth="1.2" />
    </>
  ),
  engine: () => (
    <>
      <path d="M3 16 H21 L19 12 H5 Z" fill="#9a6a3a" stroke="#2b1d10" strokeWidth="1.2" strokeLinejoin="round" />
      <circle cx="7" cy="18" r="2.6" fill="#6b4426" stroke="#2b1d10" />
      <circle cx="17" cy="18" r="2.6" fill="#6b4426" stroke="#2b1d10" />
      <path d="M8 12 L17 3" stroke="#7a5532" strokeWidth="2.2" strokeLinecap="round" />
      <circle cx="17.5" cy="3.5" r="2" fill="#8a8378" stroke="#2b1d10" />
    </>
  ),
};

export function Icon({ name, size = 18, title }: { name: string; size?: number; title?: string }) {
  const f = ICONS[name];
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" style={{ flex: 'none', verticalAlign: 'middle' }} aria-label={title ?? name}>
      {title && <title>{title}</title>}
      {f ? f('#2b1d10') : <circle cx="12" cy="12" r="8" fill="#888" />}
    </svg>
  );
}

export const RES_NAMES: Record<keyof Resources, string> = { silver: 'Silver', timber: 'Timber', iron: 'Iron', trophies: 'War trophies' };

export function ResList({ res, size = 16, className }: { res: Partial<Resources>; size?: number; className?: string }) {
  const keys = (Object.keys(res) as (keyof Resources)[]).filter((k) => (res[k] ?? 0) !== 0);
  if (!keys.length) return <span className="muted">Nothing</span>;
  return (
    <span className={`row ${className ?? ''}`} style={{ gap: 10, display: 'inline-flex' }}>
      {keys.map((k) => (
        <span key={k} className="res" style={{ fontSize: size - 2 }}>
          <Icon name={k} size={size} title={RES_NAMES[k]} />
          {res[k]}
        </span>
      ))}
    </span>
  );
}

export function Bar({ value, max, kind, label, height }: { value: number; max: number; kind: string; label?: string; height?: number }) {
  const f = Math.max(0, Math.min(1, max ? value / max : 0));
  return (
    <div className={`bar ${kind} ${kind === 'hp' && f < 0.35 ? 'low' : ''}`} style={{ height }} title={label}>
      <i style={{ width: `${f * 100}%` }} />
    </div>
  );
}

/**
 * Segmented HP bar for a squad: one segment per soldier of the full squad.
 * Living soldiers' segments fill from the shared pool in order (the last one may
 * be part-filled); fallen soldiers' segments stay dark.
 */
export function SquadBar({ hp, hpPer, size, alive, height, label }: { hp: number; hpPer: number; size: number; alive: number; height?: number; label?: string }) {
  const per = Math.max(1, hpPer);
  const low = hp / (per * Math.max(1, size)) < 0.35;
  return (
    <div className={`squadbar ${low ? 'low' : ''}`} style={{ height }} title={label ?? `${Math.max(0, Math.round(hp))}/${per * size} HP · ${alive}/${size} standing`}>
      {Array.from({ length: size }, (_, i) => {
        const fallen = i >= alive;
        const f = fallen ? 0 : Math.max(0, Math.min(1, (hp - i * per) / per));
        return (
          <span key={i} className={`seg ${fallen ? 'fallen' : ''}`}>
            {f > 0 && <i style={{ width: `${f * 100}%` }} />}
          </span>
        );
      })}
    </div>
  );
}

/** SquadBar for a roster squad (between battles: `men` are the soldiers serving). */
export function RosterSquadBar({ so, height }: { so: Soldier; height?: number }) {
  const per = soldierStats(so).hp;
  const size = squadSize(so.typeId);
  return <SquadBar hp={so.hp} hpPer={per} size={size} alive={so.men} height={height} label={`HP ${so.hp}/${squadHpCap(so)} (${per} per soldier) · ${so.men}/${size} soldiers`} />;
}

/** Shorter squad names for tight rows (cards, lists, the battle HUD). */
const SHORT_PLURAL: Record<string, string> = { collie_guard: 'Royal Guards', war_wagon: 'War Wagons' };

/** "Footmen", with rank when given: "Veteran Footmen". `short` uses compact names for long types. */
export function squadTypeLabel(typeId: string, level?: number, short = false): string {
  const def = UNIT_TYPES[typeId];
  // One war machine and its crew: "Veteran Ballista Crew".
  const plural = def?.crew ? `${(short && SHORT_PLURAL[typeId]?.replace(/s$/, '')) || def.name} Crew` : (short && SHORT_PLURAL[typeId]) || def?.plural || typeId;
  return level ? `${rankName(level)} ${plural}` : plural;
}

/** Squad strength as pips (filled: serving, hollow: fallen), optionally with "5/6". */
export function MenPips({ men, size, count = true, title }: { men: number; size: number; count?: boolean; title?: string }) {
  return (
    <span className="menpips" title={title ?? `${men} of ${size} soldiers ${men === 1 ? 'is' : 'are'} still serving`}>
      <span className="pips">
        {Array.from({ length: size }, (_, i) => (
          <i key={i} className={i < men ? 'on' : ''} />
        ))}
      </span>
      {count && (
        <b>
          {men}/{size}
        </b>
      )}
    </span>
  );
}

export function Tip({ text, children, wide }: { text: ReactNode; children: ReactNode; wide?: boolean }) {
  const [pos, setPos] = useState<{ x: number; y: number } | null>(null);
  return (
    <span
      onMouseMove={(e) => setPos({ x: e.clientX, y: e.clientY })}
      onMouseLeave={() => setPos(null)}
      style={{ display: 'inline-flex' }}
    >
      {children}
      {pos && (
        <div
          className="panel dark tooltip"
          style={{ position: 'fixed', left: Math.min(window.innerWidth - (wide ? 340 : 300), pos.x + 14), top: Math.min(window.innerHeight - 120, pos.y + 16), maxWidth: wide ? 330 : 290 }}
        >
          {text}
        </div>
      )}
    </span>
  );
}

/** Head-and-shoulders crop of the unit's front sprite. */
export function Portrait({ typeId, variant = 0, size = 56, dead = false }: { typeId: string; variant?: number; size?: number; dead?: boolean }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const c = ref.current;
    if (!c) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    c.width = size * dpr;
    c.height = size * dpr;
    const x = c.getContext('2d')!;
    x.scale(dpr, dpr);
    const enemy = UNIT_TYPES[typeId]?.faction === 'enemy';
    const g = x.createLinearGradient(0, 0, 0, size);
    g.addColorStop(0, enemy ? '#6a2a1e' : '#3c5a9a');
    g.addColorStop(1, enemy ? '#2a120c' : '#1a2440');
    x.fillStyle = g;
    x.fillRect(0, 0, size, size);
    const s = sprite(`portrait_${typeId}`, variant);
    x.drawImage(s.img, s.sx ?? 0, s.sy ?? 0, s.w, s.h, 0, 0, size, size);
    const v = x.createRadialGradient(size / 2, size / 2, size * 0.3, size / 2, size / 2, size * 0.75);
    v.addColorStop(0, 'rgba(0,0,0,0)');
    v.addColorStop(1, 'rgba(0,0,0,0.45)');
    x.fillStyle = v;
    x.fillRect(0, 0, size, size);
    if (dead) {
      x.globalCompositeOperation = 'saturation';
      x.fillStyle = '#888';
      x.fillRect(0, 0, size, size);
    }
  }, [typeId, variant, size, dead]);
  return <canvas ref={ref} className="portrait" style={{ width: size, height: size }} />;
}

export function TypeIcon({ typeId, size = 16 }: { typeId: string; size?: number }) {
  const def = UNIT_TYPES[typeId];
  const name = def?.crew
    ? 'engine'
    : def?.tags?.includes('caster')
      ? 'staff'
      : typeId === 'footman' || typeId === 'collie_guard' ? 'shield' : typeId === 'spearman' ? 'spear' : typeId === 'crossbowman' ? 'crossbow' : typeId.includes('archer') ? 'crossbow' : 'sword';
  return <Icon name={name} size={size} title={UNIT_TYPES[typeId]?.name} />;
}

export function Sign({ n }: { n: number }) {
  return <span className={n > 0 ? 'pos' : n < 0 ? 'neg' : ''}>{n > 0 ? `+${n}` : n}</span>;
}
