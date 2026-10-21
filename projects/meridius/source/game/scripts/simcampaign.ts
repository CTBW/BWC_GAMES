// Multi-cycle economy run: `npx vite-node scripts/simcampaign.ts`
import { Rng } from '../src/core/rng';
import { newGame, upgradeBuilding, nextLevel, canAfford } from '../src/meta/game';
import { autoExpedition, autoPrepare } from '../src/campaign/autoplay';

const N = 60, CYCLES = 6;
const perCycle = Array.from({ length: CYCLES }, () => ({ success: 0, retreat: 0, defeat: 0, deaths: 0, silver: 0, iron: 0, timber: 0, trophies: 0, roster: 0, lvl: 0, n: 0, upgrades: 0 }));
for (let i = 0; i < N; i++) {
  const g = newGame(1000 + i * 13);
  const rng = new Rng(i);
  for (let c = 0; c < CYCLES; c++) {
    const before = g.fallen.length;
    if (!autoPrepare(g, rng)) break;
    {
      const army = g.expedition!.army.map((id) => g.roster.find((x) => x.id === id)!);
      const { soldierStats } = await import('../src/meta/soldier');
      (perCycle[c] as any).mor = ((perCycle[c] as any).mor ?? 0) + army.reduce((s2, x) => s2 + x.morale / soldierStats(x).morale, 0) / army.length;
      (perCycle[c] as any).inj = ((perCycle[c] as any).inj ?? 0) + army.reduce((s2, x) => s2 + x.injuries.length, 0);
      (perCycle[c] as any).size = ((perCycle[c] as any).size ?? 0) + army.length;
    }
    const out = autoExpedition(g, rng);
    const pc = perCycle[c];
    pc.n++;
    (pc as any)[out] = ((pc as any)[out] ?? 0) + 1;
    pc.deaths += g.fallen.length - before;
    // Spend on upgrades greedily (command, barracks, infirmary, training, armoury, qm)
    for (const b of ['command', 'infirmary', 'barracks', 'training', 'armoury', 'quartermaster']) {
      const nl = nextLevel(g, b);
      if (nl && canAfford(g, nl.cost) && g.resources.silver - (nl.cost.silver ?? 0) > 150) { upgradeBuilding(g, b); pc.upgrades++; }
    }
    pc.silver += g.resources.silver; pc.iron += g.resources.iron; pc.timber += g.resources.timber; pc.trophies += g.resources.trophies;
    pc.roster += g.roster.length; pc.lvl += g.roster.reduce((s, x) => s + x.level, 0) / Math.max(1, g.roster.length);
  }
}
for (let c = 0; c < CYCLES; c++) {
  const p = perCycle[c]; const n = p.n || 1;
  console.log(`cycle ${c + 1}: n=${p.n} success ${(p.success / n * 100).toFixed(0)}% retreat ${(p.retreat / n * 100).toFixed(0)}% defeat ${(p.defeat / n * 100).toFixed(0)}%  deaths ${(p.deaths / n).toFixed(2)}  silver ${(p.silver / n).toFixed(0)} iron ${(p.iron / n).toFixed(1)} timber ${(p.timber / n).toFixed(1)} troph ${(p.trophies / n).toFixed(2)}  roster ${(p.roster / n).toFixed(1)} avgLvl ${(p.lvl / n).toFixed(2)} upgrades ${(p.upgrades / n).toFixed(2)} | launch morale ${(((p as any).mor ?? 0) / n * 100).toFixed(0)}% injuries ${(((p as any).inj ?? 0) / n).toFixed(2)} army ${(((p as any).size ?? 0) / n).toFixed(1)}`);
}
