// Headless balance runs: `npm run sim` (battles) or `npm run sim -- campaign`.
import { Rng } from '../src/core/rng';
import { Battle } from '../src/battle/battle';
import { runEnemyAi, runPlayerAuto } from '../src/battle/ai';
import { buildBattle, rollEncounter } from '../src/battle/setup';
import { ENCOUNTERS } from '../src/data/encounters';
import { newSoldier, soldierToUnit } from '../src/meta/soldier';

function army(seed: number, types: string[], level = 1) {
  const rng = new Rng(seed);
  let n = 0;
  return types.map((t) => soldierToUnit(newSoldier(rng, t, level, () => `s${n++}`, 0)));
}

function battleStats(encId: string, types: string[], level: number, N = 200) {
  let wins = 0, turns = 0, dead = 0, downed = 0, routedEnemies = 0, killedEnemies = 0, playerRouts = 0, hpLeft = 0;
  for (let i = 0; i < N; i++) {
    const rng = new Rng(1000 + i);
    const roll = rollEncounter(encId, rng, 3);
    const b = new Battle(buildBattle(roll, army(5000 + i, types, level), { survivalBonus: 0 }));
    b.begin(runEnemyAi);
    while (!b.isOver() && b.turn <= 30) {
      runPlayerAuto(b);
      if (b.isOver()) break;
      b.endTurn(runEnemyAi);
    }
    if (b.result === 'victory') wins++;
    turns += b.turn;
    const ev = b.drain();
    playerRouts += ev.filter((e) => e.t === 'rout' && b.unit(e.uid).faction === 'player').length;
    for (const u of b.units) {
      if (u.faction === 'player') {
        if (u.status === 'dead') dead++;
        if (u.status === 'downed') downed++;
        if (u.status !== 'dead' && u.status !== 'downed') hpLeft += u.hp / u.maxHp;
      } else {
        if (u.status === 'dead') killedEnemies++;
        if (u.status === 'fled') routedEnemies++;
      }
    }
  }
  const f = (x: number) => (x / N).toFixed(2);
  console.log(
    `${encId.padEnd(16)} L${level} ${types.length}u  win ${(wins / N * 100).toFixed(0)}%  turns ${f(turns)}  dead ${f(dead)}  downed ${f(downed)}  pRouts ${f(playerRouts)}  eKilled ${f(killedEnemies)}  eFled ${f(routedEnemies)}  hp% ${(hpLeft / N / types.length * 100).toFixed(0)}`,
  );
}

const std = ['footman', 'footman', 'spearman', 'spearman', 'crossbowman'];
for (const e of ENCOUNTERS) battleStats(e.id, std, 1);
battleStats('warband_camp', std, 2);
battleStats('warband_camp', ['footman', 'spearman', 'spearman', 'crossbowman', 'crossbowman'], 2);
