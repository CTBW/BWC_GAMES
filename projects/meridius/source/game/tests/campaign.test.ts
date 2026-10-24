import { describe, expect, it } from 'vitest';
import { Rng } from '../src/core/rng';
import { newGame } from '../src/meta/game';
import { generateExpedition, nextNodes } from '../src/campaign/expedition';
import { autoExpedition, autoPrepare } from '../src/campaign/autoplay';

describe('campaign generation', () => {
  it('every node is reachable and leads to the objective', () => {
    for (let seed = 1; seed < 40; seed++) {
      const g = newGame(seed);
      const ex = generateExpedition(g, 'hillsvain_raids', g.roster.slice(0, 5).map((s) => s.id), { rations: 10, bandages: 2, bolts: 2, torches: 1, tools: 1 });
      const obj = ex.nodes.find((n) => n.type === 'objective')!;
      for (const n of ex.nodes) {
        if (n.type !== 'start') expect(ex.edges.some((e) => e[1] === n.id)).toBe(true);
        if (n.type !== 'objective') expect(ex.edges.some((e) => e[0] === n.id)).toBe(true);
      }
      // BFS from start reaches the objective.
      const seen = new Set(['n0']);
      const q = ['n0'];
      while (q.length) {
        const c = q.shift()!;
        for (const e of ex.edges.filter((x) => x[0] === c)) if (!seen.has(e[1])) { seen.add(e[1]); q.push(e[1]); }
      }
      expect(seen.has(obj.id)).toBe(true);
      expect(ex.nodes.some((n) => n.type === 'camp')).toBe(true);
      ex.current = 'n0';
      expect(nextNodes(ex).length).toBeGreaterThan(0);
    }
  });
});

describe('full loop', () => {
  it('plays several expeditions end to end without breaking state', () => {
    const outcomes: string[] = [];
    for (let seed = 1; seed <= 6; seed++) {
      const g = newGame(seed * 77);
      const rng = new Rng(seed);
      for (let cycle = 0; cycle < 4; cycle++) {
        if (!autoPrepare(g, rng)) break;
        const out = autoExpedition(g, rng);
        outcomes.push(out);
        expect(g.expedition).toBeNull();
        for (const s of g.roster) {
          expect(s.hp).toBeGreaterThan(0);
          expect(Number.isFinite(s.morale)).toBe(true);
        }
        expect(g.resources.silver).toBeGreaterThanOrEqual(0);
      }
    }
    expect(outcomes.length).toBeGreaterThan(10);
    expect(outcomes.filter((o) => o === 'success').length).toBeGreaterThan(0);
  }, 60000);
});
