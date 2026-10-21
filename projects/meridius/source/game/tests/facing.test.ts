import { describe, expect, it } from 'vitest';
import { Rng } from '../src/core/rng';
import type { Dir } from '../src/core/types';
import { Battle } from '../src/battle/battle';
import { runEnemyAi } from '../src/battle/ai';
import { buildBattle, rollEncounter } from '../src/battle/setup';
import { generateMap } from '../src/battle/mapgen';
import { dirTo } from '../src/battle/grid';
import { makeEnemy, newSoldier, soldierToUnit } from '../src/meta/soldier';
import type { BattleUnit } from '../src/battle/types';

// Facing comes only from movement: a squad faces the way it took its last step.

function openField(seed: number) {
  const map = generateMap('forest_clearing', seed);
  for (const t of map.tiles) {
    t.prop = undefined;
    t.h = 0;
    t.terrain = 'grass';
  }
  return map;
}

function soldier(type: string, seed: number, uid: string): BattleUnit {
  const u = soldierToUnit(newSoldier(new Rng(seed), type, 1, () => uid, 0));
  return { ...u, uid };
}

function enemy(type: string, uid: string, x: number, y: number, facing: Dir): BattleUnit {
  const g = makeEnemy(type, 1, uid, new Rng(uid.length + x * 7 + y));
  g.x = x;
  g.y = y;
  g.facing = facing;
  return g;
}

function battle(units: BattleUnit[], seed = 1, phase: Battle['phase'] = 'player') {
  const b = new Battle({ seed, map: openField(seed + 40), units, survivalBonus: 0, title: 't' });
  b.phase = phase;
  return b;
}

describe('facing from movement', () => {
  it('a squad ends facing the direction of its last step', () => {
    const f = soldier('footman', 1, 'f');
    f.x = 5; f.y = 9; f.facing = 3;
    const far = enemy('goblin_archer', 'g', 12, 1, 1);
    const b = battle([f, far]);
    // Default path to (7, 9): two steps along +x.
    expect(b.move('f', 7, 9, 0)).toBe(true);
    expect(f.facing).toBe(0);
    const moves = b.drain().filter((e) => e.t === 'move');
    const path = moves.flatMap((e) => (e.t === 'move' ? e.path : []));
    const last = path[path.length - 1];
    const prev = path[path.length - 2];
    expect(dirTo(prev, last)).toBe(0);
  });

  it('every reachable facing has a path whose last step points that way', () => {
    const f = soldier('footman', 2, 'f');
    f.x = 6; f.y = 6; f.facing = 3;
    const b = battle([f, enemy('goblin_archer', 'g', 13, 0, 1)]);
    const opts = b.facingOptions(f, 6, 4);
    expect(opts.map((o) => o.facing).sort()).toEqual([0, 1, 2, 3]);
    for (const o of opts) {
      const p = o.path;
      expect(p[0]).toEqual({ x: 6, y: 6 });
      expect(p[p.length - 1]).toEqual({ x: 6, y: 4 });
      expect(dirTo(p[p.length - 2], p[p.length - 1])).toBe(o.facing);
      expect(o.cost).toBeLessThanOrEqual(f.stats.move);
    }
    // Arriving straight ahead is cheapest; arriving from the far side costs a detour.
    const straight = opts.find((o) => o.facing === 3)!;
    const back = opts.find((o) => o.facing === 1)!;
    expect(straight.cost).toBe(2);
    expect(back.cost).toBe(4);
  });

  it('a long march leaves no choice: the squad faces the way it marched', () => {
    const f = soldier('footman', 3, 'f');
    f.x = 6; f.y = 10; f.facing = 3;
    const b = battle([f, enemy('goblin_archer', 'g', 13, 0, 1)]);
    const opts = b.facingOptions(f, 6, 6);
    expect(opts.map((o) => o.facing)).toEqual([3]);
  });

  it('turning on the spot means stepping out and back, and uses the move', () => {
    const f = soldier('footman', 4, 'f');
    f.x = 6; f.y = 6; f.facing = 3;
    const b = battle([f, enemy('goblin_archer', 'g', 13, 0, 1)]);
    const home = b.facingOptions(f, 6, 6);
    const stay = home.find((o) => o.facing === 3)!;
    expect(stay.path).toHaveLength(1);
    const about = home.find((o) => o.facing === 1)!;
    expect(about.cost).toBe(2);
    expect(b.move('f', 6, 6, 1)).toBe(true);
    expect([f.x, f.y, f.facing, f.hasMoved]).toEqual([6, 6, 1, true]);
    // Moving onto the start tile with the facing it already has is no move at all.
    const g = soldier('spearman', 5, 's');
    g.x = 9; g.y = 9; g.facing = 3;
    const b2 = battle([g, enemy('goblin_archer', 'e', 13, 0, 1)]);
    expect(b2.move('s', 9, 9, 3)).toBe(false);
    expect(b2.move('s', 9, 9)).toBe(false);
  });

  it('attacking does not turn the attacker; the target keeps its facing too', () => {
    const f = soldier('footman', 6, 'f');
    f.x = 5; f.y = 5; f.facing = 3; // facing -y
    const g = enemy('goblin_spear', 'g', 6, 5, 1); // on f's +x flank
    const b = battle([f, g]);
    expect(b.attack('f', 'g')).toBe(true);
    expect(f.facing).toBe(3);
    expect(g.facing).toBe(1);
    expect(b.drain().some((e) => e.t === 'face')).toBe(false);
  });

  it('flank and rear follow the target\'s last step', () => {
    const f = soldier('footman', 7, 'f');
    f.x = 5; f.y = 9; f.facing = 3;
    const g = enemy('goblin_spear', 'g', 9, 5, 2);
    const b = battle([f, g]);
    // March straight up: the squad faces -y, so the goblin at +x is on its flank.
    expect(b.move('f', 5, 6, 3)).toBe(true);
    expect(b.arcOf(f, { x: 6, y: 6 })).toBe('flank');
    expect(b.arcOf(f, { x: 5, y: 7 })).toBe('rear');
    expect(b.arcOf(f, { x: 5, y: 5 })).toBe('front');
    const rear = b.preview(g, f, { from: { x: 5, y: 7 } });
    const front = b.preview(g, f, { from: { x: 5, y: 5 } });
    expect(rear.arc).toBe('rear');
    expect(rear.chance).toBeGreaterThan(front.chance);
  });
});

describe('systems that read facing', () => {
  it('slipping away behind an enemy\'s back provokes no free attack; leaving its front does', () => {
    // The goblin faces -y; the footman stands right behind it at +y.
    const f = soldier('footman', 8, 'f');
    f.x = 5; f.y = 6; f.facing = 3;
    const g = enemy('goblin_spear', 'g', 5, 5, 3);
    const b = battle([f, g], 8);
    expect(b.zocTiles(f).has(6 * 1000 + 5)).toBe(false);
    expect(b.move('f', 5, 8)).toBe(true);
    expect(b.drain().some((e) => e.t === 'attack')).toBe(false);
    // Now the goblin faces the footman: stepping away invites a blow.
    const f2 = soldier('footman', 9, 'f2');
    f2.x = 5; f2.y = 6; f2.facing = 3;
    const g2 = enemy('goblin_spear', 'g2', 5, 5, 1);
    const b2 = battle([f2, g2], 9);
    expect(b2.move('f2', 5, 8)).toBe(true);
    expect(b2.drain().some((e) => e.t === 'attack' && e.reaction === 'zoc')).toBe(true);
  });

  it('a spearwall strikes into its front and flanks, never behind, and does not turn', () => {
    const s = soldier('spearman', 10, 's');
    s.stats.melee = 200;
    s.x = 5; s.y = 5; s.facing = 3; s.stance = 'spearwall';
    // An orc walks up behind the spearmen.
    const o = enemy('orc_warrior', 'o', 5, 9, 3);
    const b = battle([s, o], 10, 'enemy');
    expect(b.move('o', 5, 6)).toBe(true);
    expect(b.drain().some((e) => e.t === 'attack')).toBe(false);
    expect(s.facing).toBe(3);
    // Another walks into the front.
    const s2 = soldier('spearman', 11, 's2');
    s2.stats.melee = 200;
    s2.x = 5; s2.y = 7; s2.facing = 3; s2.stance = 'spearwall';
    const o2 = enemy('orc_warrior', 'o2', 5, 3, 1);
    const b2 = battle([s2, o2], 11, 'enemy');
    b2.move('o2', 5, 6);
    expect(b2.drain().some((e) => e.t === 'attack' && e.reaction === 'spearwall')).toBe(true);
    expect(s2.facing).toBe(3);
  });

  it('overwatch watches the front and flanks only', () => {
    const c = soldier('crossbowman', 12, 'c');
    c.stats.ranged = 200;
    c.x = 6; c.y = 8; c.facing = 3; c.stance = 'overwatch';
    // A goblin moves about behind the crossbowmen, in range.
    const g = enemy('goblin_spear', 'g', 2, 12, 0);
    const b = battle([c, g], 12, 'enemy');
    b.move('g', 6, 11);
    expect(b.drain().some((e) => e.t === 'attack')).toBe(false);
    // In front, the bolts fly.
    const c2 = soldier('crossbowman', 13, 'c2');
    c2.stats.ranged = 200;
    c2.x = 6; c2.y = 9; c2.facing = 3; c2.stance = 'overwatch';
    const g2 = enemy('goblin_spear', 'g2', 6, 1, 1);
    const b2 = battle([c2, g2], 13, 'enemy');
    b2.move('g2', 6, 5);
    expect(b2.drain().some((e) => e.t === 'attack' && e.reaction === 'overwatch')).toBe(true);
    expect(c2.facing).toBe(3);
  });

  it('first strike needs the attacker in the spearmen\'s front', () => {
    const s = soldier('spearman', 14, 's');
    s.x = 5; s.y = 5; s.facing = 3;
    const g = enemy('goblin_spear', 'g', 5, 8, 3);
    const b = battle([s, g], 14, 'enemy');
    // From behind: no first strike.
    b.move('g', 5, 6);
    b.attack('g', 's');
    expect(b.drain().some((e) => e.t === 'attack' && e.reaction === 'firstStrike')).toBe(false);
  });
});

describe('the enemy turns only by marching', () => {
  it('after an enemy turn every squad faces its last step, and nothing turned on the spot without moving', () => {
    for (let seed = 1; seed <= 12; seed++) {
      const roll = rollEncounter(seed % 2 ? 'raiding_party' : 'orc_overseer', new Rng(seed), 2);
      const army = ['footman', 'footman', 'spearman', 'spearman', 'crossbowman'].map((t, i) => soldier(t, seed * 10 + i, `p${i}`));
      const b = new Battle(buildBattle(roll, army, { survivalBonus: 0 }));
      b.begin(runEnemyAi);
      for (let turn = 0; turn < 4 && !b.isOver(); turn++) {
        b.drain();
        const before = new Map(b.units.map((u) => [u.uid, u.facing]));
        b.endTurn(runEnemyAi);
        const ev = b.drain();
        expect(ev.some((e) => e.t === 'face')).toBe(false);
        const lastStep = new Map<string, Dir>();
        for (const e of ev) {
          if (e.t === 'move' && e.path.length > 1) lastStep.set(e.uid, dirTo(e.path[e.path.length - 2], e.path[e.path.length - 1]));
        }
        for (const u of b.units) {
          if (u.status === 'dead' || u.status === 'fled') continue;
          const step = lastStep.get(u.uid);
          if (step !== undefined) expect(u.facing).toBe(step);
          else if (!ev.some((e) => e.t === 'push' && e.uid === u.uid)) expect(u.facing).toBe(before.get(u.uid));
        }
      }
    }
  });
});
