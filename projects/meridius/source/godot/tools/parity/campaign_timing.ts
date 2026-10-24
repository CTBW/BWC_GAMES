// Wall time of the original's automated expeditions, for comparison with the
// Godot port (tests/unit/test_campaign.gd prints the same runs).
//   cd projects/meridius/source/game && npx vite-node ../godot/tools/parity/campaign_timing.ts
import { Rng } from '../../../game/src/core/rng';
import { newGame } from '../../../game/src/meta/game';
import { autoExpedition, autoPrepare } from '../../../game/src/campaign/autoplay';

{
  const g = newGame(1000);
  const rng = new Rng(0);
  for (let c = 0; c < 3; c++) {
    if (!autoPrepare(g, rng)) break;
    const t0 = performance.now();
    const out = autoExpedition(g, rng);
    console.log(`autoExpedition ${c + 1}: ${out}, ${g.lastReport!.battles} battles, ${(performance.now() - t0).toFixed(0)} ms`);
  }
}
{
  const t0 = performance.now();
  let n = 0;
  for (let seed = 1; seed <= 6; seed++) {
    const g = newGame(seed * 77);
    const rng = new Rng(seed);
    for (let c = 0; c < 4; c++) {
      if (!autoPrepare(g, rng)) break;
      autoExpedition(g, rng);
      n++;
    }
  }
  const ms = performance.now() - t0;
  console.log(`auto loop: ${n} expeditions in ${ms.toFixed(0)} ms (${(ms / n).toFixed(0)} ms each)`);
}
