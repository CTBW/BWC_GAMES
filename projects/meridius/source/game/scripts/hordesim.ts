// Headless horde battles: each encounter fought N times with the AI on both
// sides. Reports win rate, turns, losses, waves met and time per battle.
// Usage: npx vite-node scripts/hordesim.ts [N] [encounter,ids]
import { Rng } from '../src/core/rng';
import { Battle } from '../src/battle/battle';
import { runEnemyAi, runPlayerAuto } from '../src/battle/ai';
import { buildBattle, rollEncounter } from '../src/battle/setup';
import { ENCOUNTERS } from '../src/data/encounters';
import { newSoldier, soldierToUnit } from '../src/meta/soldier';

const N = Number(process.argv[2] ?? 40);
const only = process.argv[3]?.split(',');
const std = ['footman', 'footman', 'spearman', 'spearman', 'crossbowman', 'crossbowman'];

function army(seed: number, level: number) {
  const rng = new Rng(seed);
  let n = 0;
  return std.map((t) => soldierToUnit(newSoldier(rng, t, level, () => `s${n++}`, 0)));
}

for (const e of ENCOUNTERS) {
  if (only && !only.includes(e.id)) continue;
  for (const level of e.kind === 'stand' ? [1, 2] : [1]) {
    let wins = 0, turns = 0, squadsLost = 0, menLost = 0, enemySquads = 0, ms = 0, routs = 0, horns = 0, broken = 0, relief = 0, overrun = 0;
    let maxMs = 0;
    for (let i = 0; i < N; i++) {
      const roll = rollEncounter(e.id, new Rng(1000 + i), 3);
      const b = new Battle(buildBattle(roll, army(5000 + i, level), { survivalBonus: 0 }));
      const t0 = performance.now();
      b.begin(runEnemyAi);
      while (!b.isOver() && b.turn <= 30) {
        runPlayerAuto(b);
        if (b.isOver()) break;
        b.endTurn(runEnemyAi);
      }
      const dt = performance.now() - t0;
      ms += dt;
      maxMs = Math.max(maxMs, dt);
      const ev = b.drain();
      if (b.result === 'victory') wins++;
      turns += b.turn;
      horns += ev.filter((x) => x.t === 'horn' && x.sounded).length;
      broken += ev.filter((x) => x.t === 'broken').length;
      relief += ev.filter((x) => x.t === 'relief').length;
      overrun += b.result === 'defeat' && b.overrun >= 2 ? 1 : 0;
      routs += ev.filter((x) => x.t === 'rout' && b.unit(x.uid).faction === 'player').length;
      enemySquads += b.units.filter((u) => u.faction === 'enemy' && u.status !== 'reserve').length;
      for (const u of b.units.filter((x) => x.faction === 'player' && x.soldierId)) {
        if (u.status === 'dead' || u.status === 'downed') squadsLost++;
        menLost += u.size - u.alive;
      }
    }
    const f = (x: number) => (x / N).toFixed(2);
    console.log(
      `${e.id.padEnd(16)} L${level} win ${((wins / N) * 100).toFixed(0).padStart(3)}%  turns ${f(turns)}  foes ${f(enemySquads)}  squadsLost ${f(squadsLost)}  men ${f(menLost)}  routs ${f(routs)}  horn ${f(horns)}  chief ${f(broken)}  relief ${f(relief)}  overrun ${f(overrun)}  ${(ms / N).toFixed(0)}ms (max ${maxMs.toFixed(0)})`,
    );
  }
}
