import { describe, expect, it } from 'vitest';
import { Rng } from '../src/core/rng';
import { Battle } from '../src/battle/battle';
import { generateMap } from '../src/battle/mapgen';
import { aliveFor, damageSquad, healSquad, killsFrom } from '../src/battle/squad';
import { DEFAULT_SQUAD_SIZE, UNIT_TYPES, squadSize } from '../src/data/units';
import { makeEnemy, newSoldier, soldierToUnit } from '../src/meta/soldier';
import { formationSlots, assignSlots, pickCasualties } from '../src/render/formation';
import type { BattleEvent, BattleUnit } from '../src/battle/types';
import type { Dir } from '../src/core/types';

function openField(seed: number) {
  const map = generateMap('forest_clearing', seed);
  for (const t of map.tiles) {
    t.prop = undefined;
    t.h = 0;
    t.terrain = 'grass';
  }
  return map;
}

function footmen(seed = 1): BattleUnit {
  let n = 0;
  return soldierToUnit(newSoldier(new Rng(seed), 'footman', 1, () => `f${n++}`, 0));
}

describe('squad size', () => {
  it('squads have six soldiers unless the type says otherwise (trolls 3, wolf riders 4, rabble 9, casters and engine crews 3)', () => {
    const special: Record<string, number> = {
      troll: 3, wolf_rider: 4, goblin_horn: 4, goblin_rabble: 9,
      battle_mage: 3, goblin_shaman: 3, ballista: 3, mangonel: 3, rock_lobber: 3, war_wagon: 3,
    };
    for (const id of Object.keys(UNIT_TYPES)) {
      expect(squadSize(id)).toBe(special[id] ?? DEFAULT_SQUAD_SIZE);
    }
    expect(DEFAULT_SQUAD_SIZE).toBe(6);
  });

  it('squad HP is soldiers × HP per soldier, for the player and the enemy', () => {
    const f = footmen();
    expect(f.size).toBe(6);
    expect(f.alive).toBe(6);
    expect(f.maxHp).toBe(f.hpPer * 6);
    expect(f.hp).toBe(f.maxHp);
    const t = makeEnemy('troll', 1, 't', new Rng(1));
    expect(t.size).toBe(3);
    expect(t.alive).toBe(3);
    expect(t.maxHp).toBe(UNIT_TYPES.troll.base.hp * 3);
  });

  it('a squad starts with the soldiers its HP can carry', () => {
    let n = 0;
    const s = newSoldier(new Rng(4), 'spearman', 1, () => `s${n++}`, 0);
    const per = s.hp / s.men;
    s.hp = per * 3 + 1; // three full shares and a sliver of a fourth
    s.men = 5;
    const u = soldierToUnit(s);
    expect(u.alive).toBe(4);
    s.hp = per * 6;
    expect(soldierToUnit(s).alive).toBe(5); // the dead do not come back
  });
});

describe('shared squad health', () => {
  it('soldiers fall at each threshold (60 HP, 10 per soldier)', () => {
    const table: [number, number][] = [
      [60, 6], [51, 6], [50, 5], [41, 5], [40, 4], [31, 4], [30, 3], [21, 3], [20, 2], [11, 2], [10, 1], [1, 1], [0, 0],
    ];
    for (const [hp, alive] of table) expect(aliveFor(hp, 10, 6)).toBe(alive);
  });

  it('one heavy blow can kill several soldiers', () => {
    const s = { hp: 60, hpPer: 10, alive: 6 };
    expect(killsFrom(s, 35)).toBe(3);
    expect(damageSquad(s, 35)).toBe(3);
    expect(s).toEqual({ hp: 25, hpPer: 10, alive: 3 });
    expect(damageSquad(s, 100)).toBe(3);
    expect(s.alive).toBe(0);
    expect(s.hp).toBe(0);
  });

  it('healing restores the survivors but never raises the dead', () => {
    const s = { hp: 25, hpPer: 10, alive: 3 };
    expect(healSquad(s, 100)).toBe(5);
    expect(s).toEqual({ hp: 30, hpPer: 10, alive: 3 });
  });
});

describe('squad damage', () => {
  it('scales with surviving soldiers: alive × damage per soldier', () => {
    const map = openField(3);
    const a = footmen(1);
    const g = makeEnemy('goblin_spear', 1, 'g', new Rng(2));
    a.x = 5; a.y = 5; a.facing = 3;
    g.x = 5; g.y = 4; g.facing = 1;
    const b = new Battle({ seed: 1, map, units: [a, g], survivalBonus: 0, title: 't' });
    const per = (d: number) => Math.max(1, Math.round(d - g.stats.armor));
    const full = b.preview(a, g);
    expect(full.strikers).toBe(6);
    expect(full.min).toBe(per(a.melee[0]) * 6);
    expect(full.max).toBe(per(a.melee[1]) * 6);
    for (const alive of [5, 4, 3, 2, 1]) {
      a.alive = alive;
      a.hp = alive * a.hpPer;
      const pv = b.preview(a, g);
      expect(pv.strikers).toBe(alive);
      expect(pv.min).toBe(per(a.melee[0]) * alive);
      expect(pv.max).toBe(per(a.melee[1]) * alive);
    }
  });

  it('armour is taken off every soldier\'s blow, not once per squad', () => {
    const map = openField(5);
    const a = makeEnemy('goblin_spear', 1, 'a', new Rng(1));
    const f = footmen(2);
    a.x = 5; a.y = 5; f.x = 5; f.y = 4; f.facing = 1;
    const b = new Battle({ seed: 1, map, units: [a, f], survivalBonus: 0, title: 't' });
    const pv = b.preview(a, f, { from: { x: 5, y: 5 } });
    expect(pv.min).toBe(Math.max(1, Math.round(a.melee[0] - f.stats.armor * (1 - a.meleePierce))) * 6);
  });

  it('rolls damage once per attack and applies it once, however many soldiers swing', () => {
    const map = openField(7);
    for (let seed = 1; seed < 40; seed++) {
      const a = footmen(seed);
      const g = makeEnemy('goblin_spear', 1, 'g', new Rng(seed));
      a.x = 5; a.y = 5; a.facing = 3;
      g.x = 5; g.y = 4; g.facing = 1;
      a.stats.melee = 300; // always hit
      const b = new Battle({ seed, map, units: [a, g], survivalBonus: 0, title: 't' });
      b.phase = 'player';
      const hpBefore = g.hp;
      expect(b.attack(a.uid, g.uid)).toBe(true);
      const attacks = b.drain().filter((e): e is Extract<BattleEvent, { t: 'attack' }> => e.t === 'attack' && e.uid === a.uid);
      expect(attacks.length).toBe(1);
      const e = attacks[0];
      expect(e.strikers).toBe(6);
      expect(hpBefore - g.hp).toBe(e.damage);
      expect(e.aliveBefore).toBe(6);
      expect(e.aliveAfter).toBe(g.alive);
      expect(g.alive).toBe(aliveFor(g.hp, g.hpPer, 6));
      expect(a.damageDealt).toBe(e.damage);
    }
  });

  it('enemy squads and trolls follow the same rule', () => {
    const map = openField(9);
    const t = makeEnemy('troll', 1, 't', new Rng(3));
    const f = footmen(3);
    t.x = 5; t.y = 5; f.x = 5; f.y = 4; f.facing = 1;
    const b = new Battle({ seed: 1, map, units: [t, f], survivalBonus: 0, title: 't' });
    const full = b.preview(t, f, { from: { x: 5, y: 5 } });
    expect(full.strikers).toBe(3);
    t.alive = 1;
    t.hp = t.hpPer;
    const one = b.preview(t, f, { from: { x: 5, y: 5 } });
    expect(one.min * 3).toBe(full.min);
    expect(one.max * 3).toBe(full.max);
  });

  it('troll regeneration closes wounds but a fallen troll stays down', () => {
    const map = openField(11);
    const t = makeEnemy('troll', 1, 't', new Rng(3));
    const f = footmen(4);
    t.x = 2; t.y = 2; f.x = 9; f.y = 9;
    const b = new Battle({ seed: 1, map, units: [t, f], survivalBonus: 0, title: 't' });
    t.hp = t.hpPer + 5; // two trolls standing, the second badly hurt
    t.alive = 2;
    b.phase = 'player';
    b.endTurn(() => {});
    expect(t.alive).toBe(2);
    expect(t.hp).toBeLessThanOrEqual(2 * t.hpPer);
    expect(t.hp).toBeGreaterThan(t.hpPer + 5);
    expect(b.drain().some((e) => e.t === 'heal')).toBe(true);
  });
});

describe('formations', () => {
  const inside = (x: number, y: number) => Math.abs(x) / 64 + Math.abs(y) / 32 < 0.95;
  it('keeps every soldier inside the tile for every strength and facing', () => {
    for (const [size, type] of [[6, undefined], [3, undefined], [9, 'goblin_rabble'], [4, 'wolf_rider'], [4, 'goblin_horn']] as [number, string | undefined][]) {
      for (let n = 1; n <= size; n++) {
        for (const f of [0, 1, 2, 3] as Dir[]) {
          for (const tight of [0.84, 1]) {
            const slots = formationSlots(n, size, f, tight, type);
            expect(slots.length).toBe(n);
            for (const s of slots) expect(inside(s.x, s.y)).toBe(true);
          }
        }
      }
    }
  });

  it('rabble stands nine to a tile in three ranks of three', () => {
    const nine = formationSlots(9, 9, 1, 1, 'goblin_rabble');
    const ys = [...new Set(nine.map((s) => Math.round(s.y)))];
    expect(ys.length).toBe(3);
    for (const y of ys) expect(nine.filter((s) => Math.round(s.y) === y).length).toBe(3);
  });

  it('six stand in two ranks of three; trolls in a triangle', () => {
    const six = formationSlots(6, 6, 1);
    const ys = [...new Set(six.map((s) => Math.round(s.y)))];
    expect(ys.length).toBe(2);
    for (const y of ys) expect(six.filter((s) => Math.round(s.y) === y).length).toBe(3);
    const tri = formationSlots(3, 3, 1);
    const front = tri.filter((s) => s.y > 0);
    const back = tri.filter((s) => s.y < 0);
    expect(front.length).toBe(2);
    expect(back.length).toBe(1);
    expect(Math.abs(back[0].x)).toBeLessThan(Math.abs(front[0].x));
  });

  it('closes up around the centre as soldiers fall', () => {
    for (let n = 1; n <= 6; n++) {
      const slots = formationSlots(n, 6, 1);
      const cx = slots.reduce((s, p) => s + p.x, 0) / n;
      expect(Math.abs(cx)).toBeLessThan(6);
      for (let i = 0; i < n; i++) for (let j = i + 1; j < n; j++) {
        expect(Math.hypot(slots[i].x - slots[j].x, (slots[i].y - slots[j].y) * 2)).toBeGreaterThan(14);
      }
    }
  });

  it('assigns slots with the least movement and keeps the champion front-centre', () => {
    const from = formationSlots(6, 6, 1);
    const to = formationSlots(5, 6, 1);
    const pick = assignSlots(from.slice(0, 5), to);
    expect(new Set(pick).size).toBe(5);
    const champ = assignSlots(from, formationSlots(6, 6, 1), 4);
    expect(champ[4]).toBe(1);
  });

  it('casualties are the soldiers nearest the blow, champion last', () => {
    const slots = formationSlots(6, 6, 1);
    const dead = pickCasualties(slots, [0, 1, 2, 3, 4, 5], 2, { x: -1, y: 0 });
    // A blow from the left takes the left file, front and rear.
    for (const d of dead) expect(slots[d].x).toBeLessThan(-20);
    expect(pickCasualties(slots, [0, 1, 2, 3, 4, 5], 5, { x: -1, y: 0 }, 2)).not.toContain(2);
  });
});

describe('squad view', () => {
  it('soldiers fall, survivors re-form into the smaller formation, and nobody is lost or doubled', async () => {
    const { makeMembers, killMembers, reform, stepMembers, standing } = await import('../src/render/squadView');
    const u = footmen(7);
    const members = makeMembers(u);
    expect(standing(members).length).toBe(6);
    const corpses: number[] = [];
    const fallen = killMembers(members, 2, { x: -1, y: 0 }, -1);
    expect(fallen.length).toBe(2);
    reform(members, u.size, u.facing, { dur: 0.3 });
    for (let i = 0; i < 60; i++) stepMembers(members, 1 / 30, (m) => corpses.push(m.id));
    expect(corpses.sort()).toEqual(fallen.map((m) => m.id).sort());
    const live = standing(members);
    expect(live.length).toBe(4);
    const want = formationSlots(4, 6, u.facing).map((s) => `${s.x.toFixed(1)},${s.y.toFixed(1)}`).sort();
    expect(live.map((m) => `${m.x.toFixed(1)},${m.y.toFixed(1)}`).sort()).toEqual(want);
  });

  it('the warlord keeps the front-centre slot and is the last of his guard to fall', async () => {
    const { makeMembers, killMembers, standing, championOf } = await import('../src/render/squadView');
    const w = makeEnemy('orc_warlord', 1, 'w', new Rng(2));
    const members = makeMembers(w);
    const champ = championOf(w);
    expect(champ).toBe(0);
    expect(members[0].type).toBe('orc_warlord');
    expect(members.slice(1).every((m) => m.type === 'orc_warrior')).toBe(true);
    const front = formationSlots(6, 6, w.facing)[1];
    expect([members[0].toX, members[0].toY]).toEqual([front.x, front.y]);
    killMembers(members, 5, { x: 1, y: 1 }, champ);
    expect(standing(members).map((m) => m.id)).toEqual([0]);
  });
});
