import { describe, expect, it } from 'vitest';
import { Rng } from '../src/core/rng';
import type { Dir } from '../src/core/types';
import { Battle, GIVE_UP_TURN } from '../src/battle/battle';
import { runEnemyAi, runPlayerAuto } from '../src/battle/ai';
import { buildBattle, rollEncounter } from '../src/battle/setup';
import { generateMap } from '../src/battle/mapgen';
import { canStep, key, neighbors, tilePassable } from '../src/battle/grid';
import { makeEnemy, newSoldier, soldierToUnit } from '../src/meta/soldier';
import type { BattleObjective, BattleSetup, BattleUnit, Edge, Wave } from '../src/battle/types';

// The horde: waves, the war horn, held ground, relief, the warchief, and the
// enemies that break lines and slip round them.

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

function enemy(type: string, uid: string, x: number, y: number, facing: Dir = 1): BattleUnit {
  const g = makeEnemy(type, 1, uid, new Rng(uid.length * 13 + x));
  g.x = x;
  g.y = y;
  g.facing = facing;
  return g;
}

/** A battle with waves held as reserves beyond their edge, as buildBattle makes them. */
function withWaves(units: BattleUnit[], waves: (Wave & { types: string[] })[], objective: BattleObjective, seed = 3): Battle {
  const map = openField(seed);
  map.entries = { n: map.tiles.filter((t) => t.y === 0).map((t) => ({ x: t.x, y: 0 })) };
  const reserve: BattleUnit[] = [];
  const setupWaves = waves.map((w, wi) => {
    const uids = w.types.map((t, i) => {
      const u = enemy(t, `w${wi}-${i}`, 5 + i, -3);
      u.status = 'reserve';
      if (t === 'orc_warlord') u.tags.push('warchief');
      reserve.push(u);
      return u.uid;
    });
    return { ...w, uids };
  });
  const setup: BattleSetup = { seed, map, units: [...units, ...reserve], survivalBonus: 0, title: 't', objective, waves: setupWaves };
  const b = new Battle(setup);
  b.phase = 'player';
  return b;
}

const edge: Edge = 'n';

describe('waves', () => {
  it('a wave marches in from its edge on its turn, facing onto the field', () => {
    const f = soldier('footman', 1, 'f');
    f.x = 6; f.y = 10;
    const g = enemy('goblin_spear', 'g', 2, 2);
    const b = withWaves([f, g], [{ turn: 2, edge, units: [], types: ['goblin_rabble', 'goblin_spear'], label: 'Second wave' }], { kind: 'rout', title: 'Rout', brief: '' });
    b.endTurn(() => {});
    expect(b.units.filter((u) => u.status === 'reserve').length).toBe(2);
    b.endTurn(() => {});
    const arrived = b.units.filter((u) => u.uid.startsWith('w0'));
    expect(arrived.every((u) => u.status === 'active' && u.y === 0 && u.facing === 1)).toBe(true);
    const ev = b.drain();
    expect(ev.some((e) => e.t === 'wave')).toBe(true);
    expect(ev.filter((e) => e.t === 'spawn')).toHaveLength(2);
    expect(ev.some((e) => e.t === 'warn')).toBe(true);
    expect(b.waveState[0]).toBe('arrived');
  });

  it('a rout battle is not won while waves are still to come; with the field empty they come at once', () => {
    const f = soldier('footman', 2, 'f');
    f.x = 6; f.y = 10;
    const g = enemy('goblin_rabble', 'g', 6, 9);
    g.hp = 1;
    g.alive = 1;
    const b = withWaves([f, g], [{ turn: 9, edge, units: [], types: ['goblin_spear'], label: 'Late' }], { kind: 'rout', title: 'Rout', brief: '' });
    f.stats.melee = 200;
    b.attack('f', 'g');
    expect(g.status === 'dead' || g.status === 'downed').toBe(true);
    expect(b.isOver()).toBe(false);
    b.endTurn(() => {});
    expect(b.unit('w0-0').status).toBe('active');
  });
});

describe('the war horn', () => {
  const horn = (killHerald: boolean) => {
    const f = soldier('footman', 3, 'f');
    f.x = 6; f.y = 10;
    const h = enemy('goblin_horn', 'h', 8, 2);
    const g = enemy('goblin_spear', 'g', 3, 2);
    const b = withWaves([f, h, g], [{ turn: 3, edge, horn: true, units: [], types: ['goblin_rabble', 'goblin_rabble'], label: 'Answer' }], { kind: 'rout', hornTurn: 2, title: 'Horn', brief: '' });
    if (killHerald) {
      h.hp = 1;
      h.alive = 1;
      f.x = 8; f.y = 3;
      f.stats.melee = 200;
      b.attack('f', 'h');
    }
    b.endTurn(() => {});
    b.endTurn(() => {});
    b.endTurn(() => {});
    return b;
  };

  it('sounds if the horn-bearer lives to his turn, and its band arrives the turn after', () => {
    const b = horn(false);
    expect(b.horn).toBe('sounded');
    expect(b.unit('w0-0').status).toBe('active');
  });

  it('falls silent if he is killed first, and no help comes', () => {
    const b = horn(true);
    expect(b.horn).toBe('silent');
    expect(b.waveState[0]).toBe('cancelled');
    expect(b.unit('w0-0').status).toBe('reserve');
  });
});

describe('holding ground', () => {
  const holdBattle = () => {
    const f = soldier('footman', 4, 'f');
    f.x = 1; f.y = 11;
    const map = openField(5);
    map.zone = [{ x: 6, y: 6 }, { x: 7, y: 6 }, { x: 6, y: 7 }, { x: 7, y: 7 }];
    map.zoneName = 'The yard';
    const a = enemy('goblin_spear', 'a', 6, 6);
    const c = enemy('goblin_spear', 'c', 7, 7);
    const b = new Battle({ seed: 5, map, units: [f, a, c], survivalBonus: 0, title: 't', objective: { kind: 'hold', turns: 9, title: 'Hold', brief: '' } });
    b.phase = 'player';
    return b;
  };

  it('two enemy turns ending with the ground taken lose the battle; the first is a warning', () => {
    const b = holdBattle();
    b.endTurn(() => {});
    expect(b.isOver()).toBe(false);
    expect(b.overrun).toBe(1);
    expect(b.drain().some((e) => e.t === 'overrun')).toBe(true);
    b.endTurn(() => {});
    expect(b.result).toBe('defeat');
  });

  it('retaking the ground resets the count', () => {
    const b = holdBattle();
    b.endTurn(() => {});
    expect(b.overrun).toBe(1);
    // Two defenders step in: the attackers no longer outnumber them by two.
    const f2 = soldier('spearman', 6, 'f2');
    f2.x = 7; f2.y = 6;
    const f3 = soldier('spearman', 7, 'f3');
    f3.x = 6; f3.y = 7;
    b.units.push(f2, f3);
    b.endTurn(() => {});
    expect(b.overrun).toBe(0);
    expect(b.isOver()).toBe(false);
  });

  it('the relief comes when the last turn ends: victory, and the horde runs', () => {
    const f = soldier('footman', 8, 'f');
    f.x = 6; f.y = 10;
    const g = enemy('goblin_spear', 'g', 2, 2);
    const b = withWaves([f, g], [{ turn: 9, edge, units: [], types: ['goblin_rabble'], label: 'Too late' }], { kind: 'survive', turns: 2, title: 'Survive', brief: '', relief: 'Riders' });
    b.endTurn(() => {});
    expect(b.isOver()).toBe(false);
    b.endTurn(() => {});
    expect(b.result).toBe('victory');
    expect(b.drain().some((e) => e.t === 'relief')).toBe(true);
    expect(b.waveState[0]).toBe('cancelled');
  });
});

describe('the warchief', () => {
  it('his fall breaks the horde: every foe runs and no more waves come', () => {
    const f = soldier('footman', 9, 'f');
    f.stats.melee = 200;
    f.x = 6; f.y = 6;
    const chief = enemy('orc_warlord', 'chief', 6, 5);
    chief.tags.push('warchief');
    chief.hp = 1;
    chief.alive = 1;
    const g = enemy('goblin_spear', 'g', 2, 2);
    const b = withWaves([f, chief, g], [{ turn: 5, edge, units: [], types: ['goblin_rabble'], label: 'More' }], { kind: 'hold', turns: 9, warchief: true, title: 'Hold', brief: '' });
    b.attack('f', 'chief');
    expect(b.drain().some((e) => e.t === 'broken')).toBe(true);
    expect(b.result).toBe('victory');
    expect(b.waveState[0]).toBe('cancelled');
  });
});

describe('enemies that break and slip round lines', () => {
  it('a brute that hits smashes the squad back and steps into the gap', () => {
    const f = soldier('footman', 10, 'f');
    f.x = 6; f.y = 6; f.facing = 3;
    const br = enemy('orc_brute', 'br', 6, 5, 1);
    br.stats.melee = 300;
    const b = new Battle({ seed: 10, map: openField(10), units: [f, br], survivalBonus: 0, title: 't' });
    b.phase = 'enemy';
    b.attack('br', 'f');
    expect([f.x, f.y]).toEqual([6, 7]);
    expect([br.x, br.y]).toEqual([6, 6]);
  });

  it('wolf riders slip away without free attacks; others pay for leaving a front', () => {
    const f = soldier('footman', 11, 'f');
    f.x = 6; f.y = 6; f.facing = 3;
    const w = enemy('wolf_rider', 'w', 6, 5, 1);
    const b = new Battle({ seed: 11, map: openField(11), units: [f, w], survivalBonus: 0, title: 't' });
    b.phase = 'enemy';
    expect(b.move('w', 3, 3)).toBe(true);
    expect(b.drain().some((e) => e.t === 'attack')).toBe(false);
  });
});

describe('long skirmishes end', () => {
  it(`a band that cannot break the company gives up at the end of turn ${GIVE_UP_TURN}`, () => {
    const f = soldier('footman', 12, 'f');
    f.x = 1; f.y = 11;
    const g = enemy('goblin_archer', 'g', 12, 0);
    const b = new Battle({ seed: 12, map: openField(12), units: [f, g], survivalBonus: 0, title: 't' });
    b.phase = 'player';
    for (let t = 0; t < GIVE_UP_TURN + 1 && !b.isOver(); t++) b.endTurn(() => {});
    expect(b.result).toBe('victory');
  });
});

describe('last-stand grounds', () => {
  for (const id of ['steading', 'ford']) {
    it(`${id}: every entry reaches the ground to hold, and both layouts (plain and transposed) are sound`, () => {
      const seen = new Set<boolean>();
      for (let seed = 1; seed < 24; seed++) {
        const m = generateMap(id, seed);
        seen.add(!!m.transposed);
        expect(m.zone?.length ?? 0).toBeGreaterThan(5);
        expect(m.playerDeploy.length).toBeGreaterThanOrEqual(12);
        const start = m.zone![0];
        const reach = new Set([key(start.x, start.y)]);
        const q = [start];
        while (q.length) {
          const c = q.shift()!;
          for (const nb of neighbors(m, c)) {
            const k = key(nb.x, nb.y);
            if (reach.has(k) || !tilePassable(m, nb.x, nb.y) || !canStep(m, c, nb)) continue;
            reach.add(k);
            q.push(nb);
          }
        }
        for (const list of Object.values(m.entries ?? {})) {
          expect(list!.length).toBeGreaterThan(3);
          for (const p of list!) expect(reach.has(key(p.x, p.y))).toBe(true);
        }
        // No entry stands on the ground to hold.
        const zone = new Set(m.zone!.map((p) => key(p.x, p.y)));
        for (const list of Object.values(m.entries ?? {})) for (const p of list!) expect(zone.has(key(p.x, p.y))).toBe(false);
      }
      expect(seen.size).toBe(2);
    });
  }

  it('a whole last stand plays to an end with the AI on both sides', () => {
    for (let i = 0; i < 4; i++) {
      const roll = rollEncounter('last_stand', new Rng(70 + i), 4);
      const army = ['footman', 'footman', 'spearman', 'spearman', 'crossbowman', 'crossbowman'].map((t, k) => soldier(t, 300 + i * 10 + k, `p${k}`));
      const b = new Battle(buildBattle(roll, army, { survivalBonus: 0 }));
      b.begin(runEnemyAi);
      while (!b.isOver() && b.turn <= 12) {
        runPlayerAuto(b);
        if (b.isOver()) break;
        b.endTurn(runEnemyAi);
      }
      expect(b.isOver()).toBe(true);
      expect(b.turn).toBeLessThanOrEqual(8);
    }
  });
});
