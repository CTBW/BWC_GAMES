import { describe, expect, it } from 'vitest';
import { Rng } from '../src/core/rng';
import { Battle } from '../src/battle/battle';
import { runEnemyAi, runPlayerAuto } from '../src/battle/ai';
import { generateMap } from '../src/battle/mapgen';
import { buildBattle, rollEncounter } from '../src/battle/setup';
import { canStep, key, neighbors, tilePassable } from '../src/battle/grid';
import { makeEnemy, newSoldier, soldierToUnit } from '../src/meta/soldier';
import type { BattleUnit } from '../src/battle/types';

function army(seed: number, types = ['footman', 'footman', 'spearman', 'spearman', 'crossbowman']): BattleUnit[] {
  const rng = new Rng(seed);
  let n = 0;
  return types.map((t) => soldierToUnit(newSoldier(rng, t, 1, () => `s${n++}`, 0)));
}

function autoBattle(b: Battle, maxTurns = 30) {
  b.begin(runEnemyAi);
  while (!b.isOver() && b.turn <= maxTurns) {
    runPlayerAuto(b);
    if (b.isOver()) break;
    b.endTurn(runEnemyAi);
  }
  return b;
}

describe('map generation', () => {
  for (const id of ['forest_clearing', 'river_ruins', 'goblin_camp']) {
    it(`${id}: deploy zones are passable and connected`, () => {
      for (let seed = 1; seed < 30; seed++) {
        const m = generateMap(id, seed);
        expect(m.playerDeploy.length).toBeGreaterThanOrEqual(8);
        expect(m.enemyDeploy.length).toBeGreaterThanOrEqual(8);
        const start = m.playerDeploy[0];
        const seen = new Set([key(start.x, start.y)]);
        const q = [start];
        while (q.length) {
          const c = q.shift()!;
          for (const nb of neighbors(m, c)) {
            const k = key(nb.x, nb.y);
            if (seen.has(k) || !tilePassable(m, nb.x, nb.y) || !canStep(m, c, nb)) continue;
            seen.add(k);
            q.push(nb);
          }
        }
        for (const p of m.enemyDeploy) expect(seen.has(key(p.x, p.y))).toBe(true);
      }
    });
  }
});

describe('combat rules', () => {
  const setupDuel = () => {
    const map = generateMap('forest_clearing', 7);
    for (const t of map.tiles) {
      t.prop = undefined;
      t.h = 0;
      t.terrain = 'grass';
    }
    const [f] = army(1, ['footman']);
    const [s] = army(2, ['spearman']);
    const rng = new Rng(3);
    const enemies = ['goblin_spear', 'goblin_spear'].map((t, i) => {
      const u = soldierToUnit(newSoldier(rng, 'spearman', 1, () => `x${i}`, 0));
      return { ...u, uid: `e${i}` };
    });
    void enemies;
    return { map, f, s };
  };

  it('arcs: front, flank and rear relative to facing', () => {
    const { map, f } = setupDuel();
    f.x = 5;
    f.y = 5;
    f.facing = 3; // facing -y
    const b = new Battle({ seed: 1, map, units: [f], survivalBonus: 0, title: 't' });
    expect(b.arcOf(f, { x: 5, y: 4 })).toBe('front');
    expect(b.arcOf(f, { x: 6, y: 5 })).toBe('flank');
    expect(b.arcOf(f, { x: 4, y: 5 })).toBe('flank');
    expect(b.arcOf(f, { x: 5, y: 6 })).toBe('rear');
  });

  it('rear attacks hit more often than frontal ones against a shield', () => {
    const map = generateMap('forest_clearing', 9);
    for (const t of map.tiles) {
      t.prop = undefined;
      t.h = 0;
      t.terrain = 'grass';
    }
    const [f] = army(4, ['footman']);
    const rng = new Rng(1);
    const g = makeEnemy('goblin_spear', 1, 'g', rng);
    f.x = 5; f.y = 5; f.facing = 3;
    g.x = 5; g.y = 4;
    const b = new Battle({ seed: 1, map, units: [f, g], survivalBonus: 0, title: 't' });
    const front = b.preview(g, f, { from: { x: 5, y: 4 } });
    const rear = b.preview(g, f, { from: { x: 5, y: 6 } });
    expect(rear.chance).toBeGreaterThan(front.chance + 20);
    expect(rear.max).toBeGreaterThanOrEqual(front.max);
  });

  it('spearwall halts an advancing enemy on a hit', () => {
    const map = generateMap('forest_clearing', 11);
    for (const t of map.tiles) {
      t.prop = undefined;
      t.h = 0;
      t.terrain = 'grass';
    }
    const [s] = army(5, ['spearman']);
    s.stats.melee = 200; // always hit
    s.x = 5; s.y = 8; s.facing = 3;
    s.stance = 'spearwall';
    const g = makeEnemy('orc_warrior', 1, 'g', new Rng(2));
    g.x = 5; g.y = 4; g.facing = 1;
    const b = new Battle({ seed: 2, map, units: [s, g], survivalBonus: 0, title: 't' });
    b.phase = 'enemy';
    b.move('g', 5, 7);
    const halted = b.drain().some((e) => e.t === 'halt');
    expect(halted).toBe(true);
  });
});

describe('redo move', () => {
  const openField = (seed: number) => {
    const map = generateMap('forest_clearing', seed);
    for (const t of map.tiles) {
      t.prop = undefined;
      t.h = 0;
      t.terrain = 'grass';
    }
    return map;
  };

  it('walks a soldier back and lets him move again, until he attacks', () => {
    const map = openField(21);
    const [f] = army(30, ['footman']);
    f.x = 5; f.y = 9; f.facing = 3;
    const g = makeEnemy('goblin_spear', 1, 'g', new Rng(3));
    g.x = 5; g.y = 4; g.facing = 1;
    const b = new Battle({ seed: 3, map, units: [f, g], survivalBonus: 0, title: 't' });
    b.phase = 'player';
    expect(b.move(f.uid, 5, 7)).toBe(true);
    expect(b.canRedo(f.uid).ok).toBe(true);
    expect(b.redoMove(f.uid)).toBe(true);
    expect([f.x, f.y, f.hasMoved, f.facing]).toEqual([5, 9, false, 3]);
    // Move again, this time next to the goblin, then attack: the move is committed.
    expect(b.move(f.uid, 5, 5)).toBe(true);
    expect(b.canRedo(f.uid).ok).toBe(true);
    expect(b.attack(f.uid, g.uid)).toBe(true);
    expect(b.canRedo(f.uid).ok).toBe(false);
    expect(b.redoMove(f.uid)).toBe(false);
  });

  it('cannot take back a move the enemy reacted to', () => {
    const map = openField(22);
    const [f] = army(31, ['footman']);
    f.x = 5; f.y = 6; f.facing = 3;
    const g = makeEnemy('goblin_spear', 1, 'g', new Rng(4));
    g.x = 5; g.y = 5; g.facing = 1;
    const b = new Battle({ seed: 4, map, units: [f, g], survivalBonus: 0, title: 't' });
    b.phase = 'player';
    // Stepping away from an adjacent enemy provokes a free attack.
    expect(b.move(f.uid, 5, 8)).toBe(true);
    const r = b.canRedo(f.uid);
    expect(r.ok).toBe(false);
    expect(r.reason).toMatch(/reacted/);
  });

  it('redo is refused once another soldier takes the starting tile', () => {
    const map = openField(23);
    const [a, c] = army(32, ['footman', 'spearman']);
    a.x = 5; a.y = 10;
    c.x = 7; c.y = 10;
    const far = makeEnemy('goblin_archer', 1, 'g', new Rng(5));
    far.x = 12; far.y = 1;
    const b = new Battle({ seed: 5, map, units: [a, c, far], survivalBonus: 0, title: 't' });
    b.phase = 'player';
    expect(b.move(a.uid, 5, 8)).toBe(true);
    expect(b.move(c.uid, 5, 10)).toBe(true);
    expect(b.canRedo(a.uid).ok).toBe(false);
    expect(b.canRedo(c.uid).ok).toBe(true);
  });
});

describe('auto battles', () => {
  it('battles finish and the starting army usually beats goblin scouts', () => {
    let wins = 0;
    const N = 40;
    for (let i = 0; i < N; i++) {
      const rng = new Rng(100 + i);
      const roll = rollEncounter('goblin_scouts', rng, 0);
      const b = new Battle(buildBattle(roll, army(200 + i), { survivalBonus: 0 }));
      autoBattle(b);
      expect(b.isOver()).toBe(true);
      if (b.result === 'victory') wins++;
    }
    expect(wins / N).toBeGreaterThan(0.7);
  });

  it('the warband camp is a real fight for a fresh army', () => {
    let wins = 0;
    const N = 30;
    for (let i = 0; i < N; i++) {
      const rng = new Rng(500 + i);
      const roll = rollEncounter('warband_camp', rng, 4);
      const b = new Battle(buildBattle(roll, army(600 + i), { survivalBonus: 0 }));
      autoBattle(b);
      if (b.result === 'victory') wins++;
    }
    expect(wins / N).toBeLessThan(0.95);
  });
});
