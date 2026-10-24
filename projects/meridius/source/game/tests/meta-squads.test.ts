import { describe, expect, it } from 'vitest';
import { Rng } from '../src/core/rng';
import { squadSize } from '../src/data/units';
import { canReinforce, migrateSave, newGame, reinforce, reinforceCost, rollRecruits, type GameState } from '../src/meta/game';
import { soldierStats, squadHpCap, squadMaxHp } from '../src/meta/soldier';
import { applyBattle, bandageHeal, generateExpedition, hurtSquad, startExpedition, useBandage, campRest } from '../src/campaign/expedition';
import { Battle } from '../src/battle/battle';
import { buildBattle, rollEncounter } from '../src/battle/setup';
import { battleArmy } from '../src/campaign/expedition';
import { autoBattle } from '../src/campaign/autoplay';

function onExpedition(seed = 5): GameState {
  const g = newGame(seed);
  const army = g.roster.slice(0, 5).map((s) => s.id);
  startExpedition(g, 'hillsvain_raids', army, { rations: 30, bandages: 3, bolts: 2, torches: 2, tools: 1 }, 0);
  return g;
}

describe('squads in the meta game', () => {
  it('new squads start at full strength', () => {
    const g = newGame(3);
    for (const s of g.roster) {
      expect(s.men).toBe(squadSize(s.typeId));
      expect(s.hp).toBe(squadMaxHp(s));
    }
  });

  it('healing never raises the dead', () => {
    const g = onExpedition();
    const s = g.roster[0];
    const per = soldierStats(s).hp;
    s.men = 4;
    s.hp = per * 3 + 2;
    for (let i = 0; i < 5; i++) useBandage(g, s.id);
    expect(s.hp).toBeLessThanOrEqual(per * 4);
    expect(s.men).toBe(4);
    expect(bandageHeal(s)).toBe(40);
  });

  it('damage outside battle kills soldiers at each share, never the last one', () => {
    const g = onExpedition();
    const s = g.roster[0];
    const per = soldierStats(s).hp;
    const lost = hurtSquad(g, s, per * 2 + 1, (who, verb) => `Fever: ${who} ${verb}.`);
    expect(lost).toBe(2);
    expect(s.men).toBe(squadSize(s.typeId) - 2);
    expect(g.expedition!.log[0].text).toMatch(/Fever: two of .+ die\./);
    hurtSquad(g, s, 10_000, () => 'x');
    expect(s.men).toBe(1);
    expect(s.hp).toBe(1);
  });

  it('camp rest heals only the survivors', () => {
    const g = onExpedition();
    const ex = g.expedition!;
    ex.pending = { kind: 'camp', nodeId: ex.current, done: ['watch'], messages: [] };
    const s = g.roster[0];
    const per = soldierStats(s).hp;
    s.men = 3;
    s.hp = Math.round(per * 2.5);
    campRest(g);
    expect(s.hp).toBeLessThanOrEqual(squadHpCap(s));
    expect(s.men).toBe(3);
  });

  it('battle results copy squad strength back to the roster', () => {
    const g = onExpedition(11);
    const roll = rollEncounter('raiding_party', new Rng(4), 1);
    const b = new Battle(buildBattle(roll, battleArmy(g), { survivalBonus: 0 }));
    autoBattle(b);
    const before = new Map(g.roster.map((s) => [s.id, s.men]));
    const report = applyBattle(g, b, 'Test', false);
    for (const u of b.units.filter((x) => x.faction === 'player')) {
      const s = g.roster.find((r) => r.id === u.soldierId);
      if (u.status === 'dead') {
        expect(s).toBeUndefined();
        continue;
      }
      expect(s).toBeDefined();
      // Field triage may carry some of the fallen back; nobody else returns.
      const saved = report.losses?.find((l) => l.name === s!.name)?.saved ?? 0;
      if (u.status === 'downed') expect(s!.men).toBe(1 + saved);
      else expect(s!.men).toBe(Math.max(1, u.alive) + saved);
      expect(s!.hp).toBeLessThanOrEqual(squadHpCap(s!));
      expect(s!.men).toBeLessThanOrEqual(before.get(s!.id)!);
    }
    const lost = (report.losses ?? []).reduce((n, l) => n + l.lost, 0);
    expect(lost).toBe(g.expedition!.menLost);
  });

  it('field triage returns only soldiers who fell in this battle, never more than fell', () => {
    for (let seed = 1; seed < 25; seed++) {
      const g = onExpedition(seed);
      const roll = rollEncounter('orc_overseer', new Rng(seed), 2);
      const b = new Battle(buildBattle(roll, battleArmy(g), { survivalBonus: 0.1 }));
      autoBattle(b);
      const report = applyBattle(g, b, 'Test', false);
      for (const l of report.losses ?? []) {
        const u = b.units.find((x) => x.faction === 'player' && x.name === l.name)!;
        // Squads march out at full strength here, so the fallen are size minus the standing.
        const fell = u.status === 'downed' ? u.size - 1 : u.size - u.alive;
        expect(l.saved ?? 0).toBeGreaterThanOrEqual(0);
        expect((l.saved ?? 0) + l.lost).toBe(fell);
        if (l.fate === 'dead') expect(l.saved ?? 0).toBe(0);
      }
    }
  });

  it('only the barracks raises men, at a price, and not on campaign', () => {
    const g = newGame(9);
    const s = g.roster[0];
    const per = soldierStats(s).hp;
    s.men = 3;
    s.hp = per * 3;
    g.resources.silver = 100;
    const cost = reinforceCost(g, s);
    expect(reinforce(g, s.id)).toBe(true);
    expect(s.men).toBe(4);
    expect(s.hp).toBe(per * 4);
    expect(g.resources.silver).toBe(100 - cost);
    expect(reinforce(g, s.id, 9)).toBe(true);
    expect(s.men).toBe(squadSize(s.typeId));
    expect(canReinforce(g, s).ok).toBe(false);
    s.men = 5;
    g.expedition = generateExpedition(g, 'hillsvain_raids', [s.id], { rations: 1, bandages: 0, bolts: 0, torches: 0, tools: 0 });
    expect(reinforce(g, s.id)).toBe(false);
  });

  it('migrates saves from before squads', () => {
    const g = newGame(21);
    const old = JSON.parse(JSON.stringify(g));
    const per = soldierStats(g.roster[0]).hp;
    for (const s of [...old.roster, ...old.recruits]) {
      delete s.men;
      s.hp = soldierStats(s).hp;
    }
    old.roster[0].hp = per - 7;
    old.roster[1].hp = undefined;
    const m = migrateSave(old);
    expect(m.roster[0].men).toBe(squadSize(m.roster[0].typeId));
    expect(m.roster[0].hp).toBe((per - 7) * m.roster[0].men);
    expect(m.roster[1].hp).toBe(squadHpCap(m.roster[1]));
    for (const s of [...m.roster, ...m.recruits]) {
      expect(s.men).toBe(squadSize(s.typeId));
      expect(s.hp).toBeGreaterThan(0);
      expect(s.hp).toBeLessThanOrEqual(squadHpCap(s));
    }
    // A current save passes through unchanged.
    const again = migrateSave(JSON.parse(JSON.stringify(m)));
    expect(again.roster).toEqual(m.roster);
  });

  it('the royal guard answers only a proper barracks', () => {
    const g = newGame(31);
    let seen = 0;
    for (let i = 0; i < 40; i++) {
      rollRecruits(g);
      seen += g.recruits.filter((r) => r.typeId === 'collie_guard').length;
    }
    expect(seen).toBe(0);
    g.buildings.barracks = 2;
    for (let i = 0; i < 40; i++) {
      rollRecruits(g);
      seen += g.recruits.filter((r) => r.typeId === 'collie_guard').length;
    }
    expect(seen).toBeGreaterThan(10);
  });
});
