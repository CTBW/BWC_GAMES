import { describe, expect, it } from 'vitest';
import { Rng } from '../src/core/rng';
import { Battle } from '../src/battle/battle';
import { actUnit, runEnemyAi } from '../src/battle/ai';
import { autoBattle } from '../src/campaign/autoplay';
import { buildBattle, rollEncounter } from '../src/battle/setup';
import { generateMap } from '../src/battle/mapgen';
import { hasStatus, moveOf, squadName } from '../src/battle/squad';
import { ABILITIES } from '../src/data/abilities';
import { UNIT_TYPES, squadSize } from '../src/data/units';
import { rollRecruits, newGame } from '../src/meta/game';
import { makeEnemy, newSoldier, soldierToUnit } from '../src/meta/soldier';
import type { BattleEvent, BattleUnit } from '../src/battle/types';

type SpellEvent = Extract<BattleEvent, { t: 'spell' }>;

function openField(seed = 1) {
  const map = generateMap('forest_clearing', seed);
  for (const t of map.tiles) {
    t.prop = undefined;
    t.h = 0;
    t.terrain = 'grass';
  }
  return map;
}

let ids = 0;
function squad(typeId: string, x: number, y: number, facing: 0 | 1 | 2 | 3 = 3): BattleUnit {
  const u = UNIT_TYPES[typeId].faction === 'player'
    ? soldierToUnit(newSoldier(new Rng(ids + 7), typeId, 1, () => `s${ids++}`, 0))
    : makeEnemy(typeId, 1, `e${ids++}`, new Rng(ids));
  u.x = x;
  u.y = y;
  u.facing = facing;
  return u;
}

function battle(units: BattleUnit[], seed = 1, phase: Battle['phase'] = 'player') {
  const b = new Battle({ seed, map: openField(seed), units, survivalBonus: 0, title: 't' });
  b.phase = phase;
  return b;
}

const spells = (evs: BattleEvent[]) => evs.filter((e): e is SpellEvent => e.t === 'spell');

describe('new squads', () => {
  it('mages, shamans and engine crews come three to a squad', () => {
    for (const id of ['battle_mage', 'goblin_shaman', 'ballista', 'mangonel', 'rock_lobber', 'war_wagon']) {
      expect(squadSize(id)).toBe(3);
      const u = squad(id, 1, 1);
      expect(u.size).toBe(3);
      expect(u.maxHp).toBe(u.hpPer * 3);
    }
  });

  it('engine crews are named as a crew in the log', () => {
    const u = squad('ballista', 1, 1);
    expect(squadName(u)).toMatch(/'s ballista crew$/);
  });

  it('arcane bolts and ballista bolts never run out', () => {
    expect(squad('battle_mage', 1, 1).ammo).toBe(-1);
    expect(squad('ballista', 1, 1).ammo).toBe(-1);
    expect(squad('crossbowman', 1, 1).ammo).toBeGreaterThan(0);
  });

  it('every muster offers a specialist squad', () => {
    const g = newGame(5);
    for (let i = 0; i < 6; i++) {
      rollRecruits(g);
      expect(g.recruits.some((r) => ['battle_mage', 'ballista', 'mangonel'].includes(r.typeId))).toBe(true);
    }
  });
});

describe('spells', () => {
  it('chain lightning strikes once per squad, scales with the mages standing and arcs to the nearest foes', () => {
    const m = squad('battle_mage', 5, 9);
    const a = squad('goblin_spear', 5, 4);
    const b2 = squad('goblin_spear', 6, 4);
    const c = squad('goblin_spear', 7, 4);
    const far = squad('goblin_spear', 1, 1);
    m.stats.ranged = 400; // always strikes
    const b = battle([m, a, b2, c, far]);
    const pv = b.spellPreview(m, 'chain_lightning', a);
    expect(pv.legal).toBe(true);
    expect(pv.hits.map((h) => h.role)).toEqual(['main', 'chain', 'chain']);
    expect(pv.hits.some((h) => h.uid === far.uid)).toBe(false);
    // Three mages: three times one mage's bolt, armour ignored.
    expect(pv.hits[0].min).toBe(ABILITIES.chain_lightning.power![0] * 3);
    expect(pv.hits[0].max).toBe(ABILITIES.chain_lightning.power![1] * 3);
    expect(pv.hits[1].max).toBeLessThan(pv.hits[0].max);
    const hpBefore = [a.hp, b2.hp, c.hp];
    expect(b.cast(m.uid, 'chain_lightning', a)).toBe(true);
    const evs = b.drain();
    const sp = spells(evs);
    expect(sp).toHaveLength(1);
    expect(sp[0].hits).toHaveLength(3);
    for (const [i, h] of sp[0].hits.entries()) {
      const want = pv.hits[i];
      expect(h.damage).toBeGreaterThanOrEqual(Math.min(want.min, hpBefore[i]));
      expect(h.damage).toBeLessThanOrEqual(want.max);
    }
    expect(a.hp).toBe(hpBefore[0] - sp[0].hits[0].damage);
    // One mage left: a third of the power.
    m.alive = 1;
    m.hasActed = false;
    m.cooldowns = {};
    const one = b.spellPreview(m, 'chain_lightning', b2);
    expect(one.hits[0].max).toBe(ABILITIES.chain_lightning.power![1]);
  });

  it('a spell on cooldown cannot be cast again', () => {
    const m = squad('battle_mage', 5, 9);
    const g = squad('goblin_spear', 5, 5);
    m.stats.ranged = 400;
    const b = battle([m, g]);
    expect(b.cast(m.uid, 'chain_lightning', g)).toBe(true);
    m.hasActed = false;
    m.done = false;
    expect(b.canCast(m, 'chain_lightning').ok).toBe(false);
    expect(b.cast(m.uid, 'chain_lightning', g)).toBe(false);
  });

  it('frost blast chills the squad struck and the foes beside it, not friends, until the end of their next turn', () => {
    const m = squad('battle_mage', 5, 9);
    const f = squad('footman', 6, 5);
    const g = squad('goblin_spear', 5, 5);
    const h = squad('goblin_spear', 4, 5);
    m.stats.ranged = 400;
    const b = battle([m, f, g, h]);
    const pv = b.spellPreview(m, 'frost_blast', g);
    expect(pv.hits.map((x) => x.uid).sort()).toEqual([g.uid, h.uid].sort());
    const move = moveOf(g);
    expect(b.cast(m.uid, 'frost_blast', g)).toBe(true);
    expect(hasStatus(g, 'chilled')).toBe(true);
    expect(hasStatus(h, 'chilled')).toBe(true);
    expect(hasStatus(f, 'chilled')).toBe(false);
    expect(moveOf(g)).toBe(Math.ceil(move / 2));
    // Chilled squads are easier to hit and hit worse.
    expect(b.preview(f, g).mods.some(([k]) => k === 'Target chilled')).toBe(true);
    expect(b.preview(g, f, { from: { x: 6, y: 4 } }).mods.some(([k]) => k === 'Chilled')).toBe(true);
    // Still chilled through the enemy turn, gone after it.
    let chilledDuringTheirTurn = false;
    b.endTurn((bb) => {
      chilledDuringTheirTurn = hasStatus(bb.unit(g.uid), 'chilled');
    });
    expect(chilledDuringTheirTurn).toBe(true);
    expect(hasStatus(g, 'chilled')).toBe(false);
  });

  it('healing closes wounds but never raises the dead', () => {
    const m = squad('battle_mage', 5, 9);
    const f = squad('footman', 5, 7);
    const b = battle([m, f]);
    f.alive = 4;
    f.hp = f.hpPer * 3 + 2;
    expect(b.cast(m.uid, 'healing_light', f)).toBe(true);
    expect(f.alive).toBe(4);
    expect(f.hp).toBeLessThanOrEqual(f.hpPer * 4);
    expect(f.hp).toBeGreaterThan(f.hpPer * 3 + 2);
    const sp = spells(b.drain())[0];
    expect(sp.hits[0].heal).toBe(f.hp - (f.hpPer * 3 + 2));
  });

  it('mending circle heals every friendly squad within two tiles', () => {
    const m = squad('battle_mage', 5, 9);
    m.abilities.push('mending_circle');
    const near = squad('footman', 5, 8);
    const away = squad('footman', 1, 1);
    const b = battle([m, near, away]);
    for (const u of [m, near, away]) u.hp -= 10;
    expect(b.cast(m.uid, 'mending_circle', m)).toBe(true);
    expect(near.hp).toBeGreaterThan(near.maxHp - 10);
    expect(m.hp).toBeGreaterThan(m.maxHp - 10);
    expect(away.hp).toBe(away.maxHp - 10);
  });

  it('a fireball burns friend and foe beside the tile it strikes, and a miss lands a tile astray', () => {
    let missed = 0;
    for (let seed = 1; seed <= 40; seed++) {
      const s = squad('goblin_shaman', 5, 1);
      const f = squad('footman', 5, 6);
      const g = squad('goblin_spear', 5, 5);
      const b = battle([s, f, g], seed, 'enemy');
      const pv = b.spellPreview(s, 'fireball', f);
      expect(pv.hits.find((h) => h.uid === g.uid)?.ally).toBe(true);
      expect(pv.hits.find((h) => h.uid === f.uid)?.role).toBe('main');
      s.stats.ranged = -400; // 5%: nearly always astray
      expect(b.cast(s.uid, 'fireball', f)).toBe(true);
      const sp = spells(b.drain())[0];
      if (sp.hit) continue;
      missed++;
      expect(Math.max(Math.abs(sp.impact.x - f.x), Math.abs(sp.impact.y - f.y))).toBe(1);
      // Whoever stands where it lands, or beside it, still burns.
      for (const h of sp.hits) expect(Math.abs(b.unit(h.uid).x - sp.impact.x) + Math.abs(b.unit(h.uid).y - sp.impact.y)).toBeLessThanOrEqual(1);
    }
    expect(missed).toBeGreaterThan(30);
  });

  it('bloodlust frenzies a squad: harder blows, halved morale losses, lower guard, until the end of its next turn', () => {
    const s = squad('goblin_shaman', 5, 1);
    const g = squad('goblin_spear', 5, 5);
    const f = squad('footman', 5, 6, 3);
    const b = battle([s, g, f], 1, 'enemy');
    const before = b.preview(g, f);
    expect(b.cast(s.uid, 'bloodlust', g)).toBe(true);
    const after = b.preview(g, f);
    expect(after.chance).toBe(Math.min(95, before.chance + 10));
    expect(after.min).toBe(before.min + 3 * g.alive);
    expect(b.preview(f, g).mods.some(([k]) => k === 'Target in a frenzy')).toBe(true);
    const m0 = g.morale;
    b.changeMorale(g, -20, 'test');
    expect(g.morale).toBe(m0 - 10);
    // Lasts through the player's turn and the goblins' next one.
    (b as unknown as { endOfTurn: (f: string) => void }).endOfTurn('enemy');
    expect(hasStatus(g, 'bloodlust')).toBe(true);
    (b as unknown as { endOfTurn: (f: string) => void }).endOfTurn('enemy');
    expect(hasStatus(g, 'bloodlust')).toBe(false);
  });

  it('gutripper ignores armour and the wound bleeds at the start of the next two turns, killing soldiers', () => {
    const s = squad('goblin_shaman', 5, 1);
    const f = squad('footman', 5, 5);
    s.stats.ranged = 400;
    const b = battle([s, f], 1, 'enemy');
    const pv = b.spellPreview(s, 'gutripper', f);
    expect(pv.hits[0].min).toBe(ABILITIES.gutripper.power![0] * 3);
    expect(b.cast(s.uid, 'gutripper', f)).toBe(true);
    expect(hasStatus(f, 'bleeding')).toBe(true);
    b.drain();
    const startTurn = (b as unknown as { startTurn: (f: string) => void }).startTurn.bind(b);
    const dots = () => b.drain().filter((e): e is Extract<BattleEvent, { t: 'dot' }> => e.t === 'dot');
    const hp = f.hp;
    startTurn('player');
    const first = dots();
    expect(first).toHaveLength(1);
    expect(f.hp).toBe(hp - first[0].damage);
    expect(first[0].damage).toBeGreaterThan(0);
    startTurn('player');
    expect(dots()).toHaveLength(1);
    expect(hasStatus(f, 'bleeding')).toBe(false);
    startTurn('player');
    expect(dots()).toHaveLength(0);
    // Bleeding takes soldiers like any wound: the soldiers standing follow the HP.
    expect(f.alive).toBe(Math.ceil(f.hp / f.hpPer));
  });
});

describe('war machines', () => {
  it('a ballista cannot loose in a turn it has moved', () => {
    const bl = squad('ballista', 5, 10);
    const g = squad('goblin_spear', 5, 4);
    const b = battle([bl, g]);
    expect(b.preview(bl, g).legal).toBe(true);
    expect(b.preview(bl, g, { movedTiles: 1 }).legal).toBe(false);
    expect(b.move(bl.uid, 5, 9)).toBe(true);
    expect(b.attack(bl.uid, g.uid)).toBe(false);
  });

  it('a ballista bolt goes on through into the foe behind, at half force, never into friends', () => {
    const bl = squad('ballista', 5, 10);
    const g = squad('goblin_spear', 5, 6);
    const h = squad('goblin_spear', 5, 5);
    bl.stats.ranged = 400;
    const b = battle([bl, g, h]);
    expect(b.attack(bl.uid, g.uid)).toBe(true);
    const atk = b.drain().filter((e): e is Extract<BattleEvent, { t: 'attack' }> => e.t === 'attack');
    expect(atk).toHaveLength(2);
    expect(atk[1].target).toBe(h.uid);
    expect(atk[1].via).toBe(g.uid);
    expect(atk[1].damage).toBe(Math.max(1, Math.round(atk[0].damage * 0.5)));
    // A friendly squad behind stops the bolt.
    const bl2 = squad('ballista', 5, 10);
    const g2 = squad('goblin_spear', 5, 6);
    const f2 = squad('footman', 5, 5);
    bl2.stats.ranged = 400;
    const b2 = battle([bl2, g2, f2]);
    expect(b2.impaleTarget(bl2, g2)).toBeUndefined();
  });

  it('a mangonel lobs over obstacles, not too close, and not after moving', () => {
    const mg = squad('mangonel', 5, 10);
    const g = squad('goblin_spear', 5, 4);
    const close = squad('goblin_spear', 5, 8);
    const b = battle([mg, g, close]);
    // A wall of rocks in between does not matter to a lobbed stone.
    for (let x = 0; x < b.map.w; x++) b.map.tiles[7 * b.map.w + x].prop = 'rock_large';
    expect(b.spellPreview(mg, 'hurl_stone', g).legal).toBe(true);
    expect(b.spellPreview(mg, 'hurl_stone', close).legal).toBe(false);
    expect(b.spellPreview(mg, 'hurl_stone', g, { movedTiles: 1 }).legal).toBe(false);
  });

  it('a war wagon smashes a squad out of the line and rolls into the gap', () => {
    const w = squad('war_wagon', 5, 4, 1);
    const f = squad('footman', 5, 5, 3);
    w.stats.melee = 400;
    const b = battle([w, f], 1, 'enemy');
    expect(b.attack(w.uid, f.uid)).toBe(true);
    if (f.status === 'active') {
      expect(f.y).toBe(6);
      expect(w.y).toBe(5);
    }
  });
});

describe('the AI uses magic and machines', () => {
  it('shamans and rock lobbers cast during the enemy turn', () => {
    const s = squad('goblin_shaman', 5, 2, 1);
    const r = squad('rock_lobber', 7, 1, 1);
    const g = squad('goblin_spear', 5, 4, 1);
    const f = squad('footman', 5, 7, 3);
    const c = squad('crossbowman', 6, 9, 3);
    const b = battle([s, r, g, f, c], 4, 'enemy');
    runEnemyAi(b);
    const casts = spells(b.drain()).map((e) => e.ability);
    expect(casts.length).toBeGreaterThanOrEqual(1);
    expect(casts.every((id) => ABILITIES[id].kind === 'spell')).toBe(true);
  });

  it('player mages cast spells when the company is automated', () => {
    const m = squad('battle_mage', 5, 9);
    const f = squad('footman', 5, 7);
    const g = squad('goblin_spear', 5, 4, 1);
    const h = squad('goblin_spear', 6, 4, 1);
    const b = battle([m, f, g, h], 2);
    actUnit(b, m, { useStances: true });
    expect(spells(b.drain()).length).toBe(1);
  });

  it('whole battles with the new squads run to an end on both sides', () => {
    for (const [enc, seed] of [['shaman_fire', 3], ['siege_train', 5]] as const) {
      const roll = rollEncounter(enc, new Rng(seed), 2);
      const army = ['footman', 'spearman', 'battle_mage', 'ballista', 'mangonel', 'crossbowman'].map((t, i) =>
        soldierToUnit(newSoldier(new Rng(seed + i), t, 1, () => `a${seed}-${i}`, 0)),
      );
      const b = new Battle(buildBattle(roll, army, { survivalBonus: 0 }));
      autoBattle(b);
      expect(b.isOver()).toBe(true);
      expect(b.result).toBeDefined();
    }
  });
});
