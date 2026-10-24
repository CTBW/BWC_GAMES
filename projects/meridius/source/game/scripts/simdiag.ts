import { Rng } from '../src/core/rng';
import { newGame } from '../src/meta/game';
import { autoPrepare } from '../src/campaign/autoplay';
import * as X from '../src/campaign/expedition';
import { Battle } from '../src/battle/battle';
import { buildBattle } from '../src/battle/setup';
import { autoBattle } from '../src/campaign/autoplay';
import { soldierStats, squadMaxHp } from '../src/meta/soldier';

const stats: Record<string, { n: number; win: number; hp: number; morale: number; units: number; fat: number }> = {};
for (let i = 0; i < 80; i++) {
  const g = newGame(3000 + i);
  const rng = new Rng(i);
  autoPrepare(g, rng);
  let guard = 0;
  while (g.expedition && guard++ < 100) {
    const ex = g.expedition; const p = ex.pending;
    if (!p) { const nx = X.nextNodes(ex); if (!nx.length) break; X.march(g, rng.pick(nx).id); continue; }
    if (p.kind === 'battle') {
      const army = X.armySoldiers(g);
      const key = p.objective ? 'objective' : p.surprise ? 'ambush' : `battle@${X.node(ex, ex.current).stage}`;
      const s = (stats[key] ??= { n: 0, win: 0, hp: 0, morale: 0, units: 0, fat: 0 });
      s.n++;
      s.units += army.length;
      // Share of full squad strength (HP of every soldier, fallen ones included).
      s.hp += army.reduce((a, x) => a + x.hp / squadMaxHp(x), 0) / army.length;
      s.morale += army.reduce((a, x) => a + x.morale / soldierStats(x).morale, 0) / army.length;
      s.fat += army.reduce((a, x) => a + x.fatigue, 0) / army.length;
      const b = new Battle(buildBattle(p.roll, X.battleArmy(g), { survivalBonus: X.survivalBonus(g), title: p.title }));
      autoBattle(b);
      if (b.result === 'victory') s.win++;
      X.applyBattle(g, b, p.title, p.objective);
      continue;
    }
    if (p.kind === 'event' && !p.result) X.chooseEvent(g, 0);
    if (p.kind === 'camp') { X.campWatch(g); X.campRest(g); if (g.expedition?.pending?.kind !== 'camp') continue; }
    if (p.kind === 'complete') { X.returnHome(g, 'success'); break; }
    X.dismissPending(g);
  }
}
for (const [k, s] of Object.entries(stats).sort()) console.log(`${k.padEnd(10)} n=${s.n} win ${(s.win / s.n * 100).toFixed(0)}% units ${(s.units / s.n).toFixed(1)} hp ${(s.hp / s.n * 100).toFixed(0)}% morale ${(s.morale / s.n * 100).toFixed(0)}% fatigue ${(s.fat / s.n).toFixed(0)}`);
