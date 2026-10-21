// Which battles end expeditions: plays cycle-1 expeditions with the autoplayer
// and logs every battle (encounter, result, squads and soldiers before/after).
// Usage: npx vite-node scripts/campdiag.ts [N]
import { Rng } from '../src/core/rng';
import { Battle } from '../src/battle/battle';
import { buildBattle } from '../src/battle/setup';
import { newGame } from '../src/meta/game';
import { autoBattle, autoPrepare } from '../src/campaign/autoplay';
import { EVENTS } from '../src/data/events';
import {
  applyBattle, armySoldiers, battleArmy, campRest, campWatch, chooseEvent, choiceAvailable,
  dismissPending, march, nextNodes, prepareNight, returnHome, searchSpot, survivalBonus,
} from '../src/campaign/expedition';

const N = Number(process.argv[2] ?? 40);
const rows: Record<string, { n: number; win: number; lose: number; retreat: number; squadsIn: number; menIn: number; menLost: number }> = {};
const outcomes: Record<string, number> = {};
for (let i = 0; i < N; i++) {
  const g = newGame(1000 + i * 13);
  const rng = new Rng(i);
  if (!autoPrepare(g, rng)) continue;
  let guard = 0;
  let out = 'done';
  while (g.expedition && guard++ < 200) {
    const ex = g.expedition;
    const p = ex.pending;
    if (!p) {
      const next = nextNodes(ex);
      if (!next.length) { out = returnHome(g, ex.objectiveDone ? 'success' : 'retreat').outcome; break; }
      const pref: Record<string, number> = { camp: 3, village: 2.5, event: 2, scout: 2.2, battle: 1, ambush: 1, objective: 5 };
      march(g, next.slice().sort((a, b) => (pref[b.type] ?? 1) - (pref[a.type] ?? 1))[0].id);
      continue;
    }
    if (p.kind === 'battle') {
      const men = armySoldiers(g).reduce((n, s) => n + s.men, 0);
      const squads = armySoldiers(g).length;
      const night = prepareNight(g);
      const b = new Battle(buildBattle(p.roll, battleArmy(g), { survivalBonus: survivalBonus(g), title: p.title, darkness: night.darkness }));
      autoBattle(b);
      applyBattle(g, b, p.title, p.objective);
      const after = g.expedition ? armySoldiers(g).reduce((n, s) => n + s.men, 0) : 0;
      const r = (rows[p.roll.encounterId] ??= { n: 0, win: 0, lose: 0, retreat: 0, squadsIn: 0, menIn: 0, menLost: 0 });
      r.n++;
      r.squadsIn += squads;
      r.menIn += men;
      r.menLost += men - after;
      if (b.result === 'victory') r.win++;
      else if (b.result === 'defeat') r.lose++;
      else r.retreat++;
      continue;
    }
    if (p.kind === 'complete') { out = returnHome(g, 'success').outcome; break; }
    if (p.kind === 'event' && !p.result) {
      const ev = EVENTS.find((e) => e.id === p.eventId)!;
      chooseEvent(g, Math.max(0, ev.choices.findIndex((ch) => choiceAvailable(g, ch).ok)));
    }
    if (p.kind === 'camp') {
      if (ex.supplies.torches > 0) campWatch(g);
      campRest(g);
    }
    if (p.kind === 'village') for (let k = 0; k < p.spots.length; k++) if (g.expedition?.pending?.kind === 'village' && (!p.spots[k].locked || ex.supplies.tools > 0)) searchSpot(g, k);
    if (g.expedition?.pending) dismissPending(g);
  }
  if (!g.expedition && out === 'done') out = g.lastReport?.outcome ?? 'done';
  outcomes[out] = (outcomes[out] ?? 0) + 1;
}
console.log(outcomes);
for (const [id, r] of Object.entries(rows).sort((a, b) => b[1].n - a[1].n)) {
  console.log(`${id.padEnd(16)} n ${String(r.n).padStart(3)}  win ${((r.win / r.n) * 100).toFixed(0).padStart(3)}%  lose ${((r.lose / r.n) * 100).toFixed(0).padStart(3)}%  squads in ${(r.squadsIn / r.n).toFixed(1)}  men in ${(r.menIn / r.n).toFixed(1)}  men lost ${(r.menLost / r.n).toFixed(1)}`);
}
