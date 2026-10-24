// Per-player conveniences remembered in this browser: sound and battle speed.
// Storage can be missing or blocked, so every access falls back to defaults.

const KEY = 'meridius.prefs.v1';

export interface Prefs {
  muted: boolean;
  battleSpeed: number;
}

const DEFAULTS: Prefs = { muted: false, battleSpeed: 1 };

export function prefs(): Prefs {
  try {
    return { ...DEFAULTS, ...JSON.parse(localStorage.getItem(KEY) ?? '{}') };
  } catch {
    return { ...DEFAULTS };
  }
}

export function setPref<K extends keyof Prefs>(key: K, value: Prefs[K]) {
  try {
    localStorage.setItem(KEY, JSON.stringify({ ...prefs(), [key]: value }));
  } catch {
    // Not remembered; the setting still applies for this session.
  }
}
