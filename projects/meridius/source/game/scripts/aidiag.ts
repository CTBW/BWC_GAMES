// Enemy AI behaviour diagnostic: `npx vite-node scripts/aidiag.ts [battlesPerEncounter]`
// Plays the sim armies against every encounter and measures what a player would
// notice: passivity, idling, archers in melee, lone attackers, attack arcs and
// the reactions (spearwall, overwatch, zone of control) the enemy walks into.
import { Rng } from '../src/core/rng';
import { Battle } from '../src/battle/battle';
import { actUnit, runPlayerAuto } from '../src/battle/ai';
import { dist, key, manhattan } from '../src/battle/grid';
import { buildBattle, rollEncounter } from '../src/battle/setup';
import type { BattleUnit } from '../src/battle/types';
import { ENCOUNTERS } from '../src/data/encounters';
import { newSoldier, soldierToUnit } from '../src/meta/soldier';

const N = Number(process.argv[2] ?? 60);
const std = ['footman', 'footman', 'spearman', 'spearman', 'crossbowman'];

function army(seed: number, types: string[], level = 1) {
  const rng = new Rng(seed);
  let n = 0;
  return types.map((t) => soldierToUnit(newSoldier(rng, t, level, () => `s${n++}`, 0)));
}

type Tally = Record<string, number>;
const add = (t: Tally, k: string, v = 1) => (t[k] = (t[k] ?? 0) + v);

/** True if the unit has a legal attack from any tile it can reach this turn. */
function couldAttack(b: Battle, u: BattleUnit): boolean {
  if (b.targets(u).length) return true;
  for (const k of b.reachable(u).keys()) {
    const p = { x: k % 1000, y: Math.floor(k / 1000) };
    if (b.targets(u, p).length) return true;
  }
  return false;
}

/** Same unit order as runEnemyAi, with each unit observed before and after it acts. */
function observedEnemyAi(t: Tally) {
  return (b: Battle) => {
    const order = b
      .active('enemy')
      .slice()
      .sort((a, c) => {
        const ra = a.shot ? 0 : a.leader ? 2 : 1;
        const rc = c.shot ? 0 : c.leader ? 2 : 1;
        if (ra !== rc) return ra - rc;
        const da = Math.min(...b.active('player').map((p) => dist(p, a)), 99);
        const dc = Math.min(...b.active('player').map((p) => dist(p, c)), 99);
        return da - dc;
      });
    for (const u of order) {
      if (b.isOver()) return;
      if (u.status !== 'active') continue;
      const could = couldAttack(b, u);
      const from = key(u.x, u.y);
      const state = b.moraleState(u);
      actUnit(b, u);
      if (u.status !== 'active') continue;
      const moved = key(u.x, u.y) !== from;
      const foes = b.active('player');
      const nearest = Math.min(...foes.map((f) => dist(f, u)), 99);
      add(t, 'unitTurns');
      if (could) {
        add(t, 'couldAttack');
        if (!u.hasActed) {
          add(t, 'passive');
          add(t, `passive:${u.typeId}:${state}`);
        }
      }
      if (!moved && !u.hasActed && nearest <= 10) add(t, 'idle');
      if (u.shot) {
        add(t, 'rangedTurns');
        if (foes.some((f) => manhattan(f, u) === 1)) add(t, 'rangedInMelee');
      }
      if (u.hasActed && !u.shot) {
        add(t, 'meleeActs');
        const friends = b.active('enemy').filter((a) => a !== u && dist(a, u) <= 2).length;
        if (friends === 0) add(t, 'loneAttack');
      }
    }
  };
}

const total: Tally = {};
for (const enc of ENCOUNTERS) {
  const t: Tally = {};
  let wins = 0;
  let turns = 0;
  for (let i = 0; i < N; i++) {
    const rng = new Rng(1000 + i);
    const roll = rollEncounter(enc.id, rng, 3);
    const b = new Battle(buildBattle(roll, army(5000 + i, std, 1), { survivalBonus: 0 }));
    const ai = observedEnemyAi(t);
    b.begin(ai);
    while (!b.isOver() && b.turn <= 30) {
      runPlayerAuto(b);
      if (b.isOver()) break;
      b.endTurn(ai);
    }
    if (b.result === 'victory') wins++;
    turns += b.turn;
    let side = 'player';
    for (const e of b.drain()) {
      if (e.t === 'turn') side = e.faction;
      if (e.t !== 'attack') continue;
      const attacker = b.unit(e.uid);
      if (attacker.faction === 'enemy' && !e.reaction) {
        add(t, e.ranged ? 'enemyShots' : 'enemyMelee');
        if (!e.ranged) add(t, `arc:${e.arc}`);
        if (b.unit(e.target).status === 'routing') add(t, 'hitRouting');
      }
      if (attacker.faction === 'player' && e.reaction && side === 'enemy') add(t, `reaction:${e.reaction}`);
    }
  }
  const pct = (a: string, bk: string) => `${(((t[a] ?? 0) / Math.max(1, t[bk] ?? 0)) * 100).toFixed(0)}%`;
  const per = (a: string) => ((t[a] ?? 0) / N).toFixed(2);
  console.log(
    `${enc.id.padEnd(15)} win ${((wins / N) * 100).toFixed(0)}% turns ${(turns / N).toFixed(1)} | passive ${pct('passive', 'couldAttack')} idle ${pct('idle', 'unitTurns')} ` +
      `rangedInMelee ${pct('rangedInMelee', 'rangedTurns')} lone ${pct('loneAttack', 'meleeActs')} | arcs F/Fl/R ${pct('arc:front', 'enemyMelee')}/${pct('arc:flank', 'enemyMelee')}/${pct('arc:rear', 'enemyMelee')} ` +
      `| per battle: spearwall ${per('reaction:spearwall')} overwatch ${per('reaction:overwatch')} zoc ${per('reaction:zoc')} firstStrike ${per('reaction:firstStrike')}`,
  );
  for (const [k, v] of Object.entries(t)) add(total, k, v);
}
const passive = Object.entries(total)
  .filter(([k]) => k.startsWith('passive:'))
  .sort((a, b) => b[1] - a[1])
  .slice(0, 8);
console.log('most passive (type:morale):', passive.map(([k, v]) => `${k.slice(8)} ${v}`).join(', '));
