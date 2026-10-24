// How the automated company uses its specialists: casts, shots and moves per
// battle, and how often the specialist squad itself is lost.
// Usage: npx vite-node scripts/magicdiag.ts
import { Rng } from '../src/core/rng';
import { Battle } from '../src/battle/battle';
import { runEnemyAi, runPlayerAuto } from '../src/battle/ai';
import { buildBattle, rollEncounter } from '../src/battle/setup';
import { newSoldier, soldierToUnit } from '../src/meta/soldier';

const N = 60;
for (const spec of ['battle_mage', 'ballista', 'mangonel']) {
  const tally: Record<string, number> = {};
  let lost = 0;
  let turns = 0;
  let idle = 0;
  let wins = 0;
  for (let i = 0; i < N; i++) {
    const enc = ['raiding_party', 'orc_overseer', 'siege_train'][i % 3];
    const roll = rollEncounter(enc, new Rng(2000 + i), 3);
    let n = 0;
    const rng = new Rng(7000 + i);
    const army = ['footman', 'footman', 'spearman', 'spearman', spec].map((t) => soldierToUnit(newSoldier(rng, t, 1, () => `s${n++}`, 0)));
    const b = new Battle(buildBattle(roll, army, { survivalBonus: 0 }));
    const me = army[4].uid;
    const count = (k: string) => (tally[k] = (tally[k] ?? 0) + 1);
    b.begin(runEnemyAi);
    while (!b.isOver() && b.turn <= 30) {
      const u = b.unit(me);
      runPlayerAuto(b);
      if (u.status === 'active' && !u.hasActed) idle++;
      for (const e of b.drain()) {
        if (e.t === 'spell' && e.uid === me) count(`cast ${e.ability}${e.hit ? '' : ' (miss)'}`);
        if (e.t === 'attack' && e.uid === me && !e.reaction) count(`${e.ranged ? 'shot' : 'melee'}${e.ability === 'impale' ? ' through' : ''}`);
        if (e.t === 'move' && e.uid === me) count('move');
      }
      if (b.isOver()) break;
      b.endTurn(runEnemyAi);
      b.drain();
    }
    turns += b.turn;
    if (b.result === 'victory') wins++;
    const u = b.unit(me);
    if (u.status === 'dead' || u.status === 'downed') lost++;
  }
  console.log(`${spec}: win ${Math.round((wins / N) * 100)}%  lost ${Math.round((lost / N) * 100)}%  idle turns/battle ${(idle / N).toFixed(1)}  turns ${(turns / N).toFixed(1)}`);
  for (const [k, v] of Object.entries(tally).sort((a, c) => c[1] - a[1])) console.log(`   ${k.padEnd(28)} ${(v / N).toFixed(2)}`);
}

// The host's casters and machines: what they cast, and how often they burn their own.
for (const enc of ['shaman_fire', 'siege_train']) {
  const tally: Record<string, number> = {};
  let ms = 0;
  let turnsRun = 0;
  for (let i = 0; i < N; i++) {
    const roll = rollEncounter(enc, new Rng(3000 + i), 3);
    let n = 0;
    const rng = new Rng(9000 + i);
    const army = ['footman', 'footman', 'spearman', 'spearman', 'crossbowman'].map((t) => soldierToUnit(newSoldier(rng, t, 1, () => `s${n++}`, 0)));
    const b = new Battle(buildBattle(roll, army, { survivalBonus: 0 }));
    const count = (k: string, by = 1) => (tally[k] = (tally[k] ?? 0) + by);
    const enemyTurn = (bb: Battle) => {
      const t0 = performance.now();
      runEnemyAi(bb);
      ms = Math.max(ms, performance.now() - t0);
      turnsRun++;
    };
    b.begin(enemyTurn);
    while (!b.isOver() && b.turn <= 30) {
      runPlayerAuto(b);
      b.drain();
      if (b.isOver()) break;
      b.endTurn(enemyTurn);
      for (const e of b.drain()) {
        if (e.t !== 'spell') continue;
        const caster = b.unit(e.uid);
        count(`${e.ability}${e.hit ? '' : ' (miss)'}`);
        count('own squads struck', e.hits.filter((h) => h.damage > 0 && b.unit(h.uid).faction === caster.faction).length);
        count('foes struck', e.hits.filter((h) => h.damage > 0 && b.unit(h.uid).faction !== caster.faction).length);
      }
    }
  }
  console.log(`${enc}: enemy casts per battle (worst enemy turn ${ms.toFixed(0)} ms)`);
  for (const [k, v] of Object.entries(tally).sort((a, c) => c[1] - a[1])) console.log(`   ${k.padEnd(28)} ${(v / N).toFixed(2)}`);
}
