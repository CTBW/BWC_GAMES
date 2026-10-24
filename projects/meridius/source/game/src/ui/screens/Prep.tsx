import { useMemo, useState } from 'react';
import type { SupplyId } from '../../core/types';
import { SUPPLIES, SUPPLY_ORDER } from '../../data/items';
import { UNIT_TYPES, squadSize } from '../../data/units';
import {
  armyCommand,
  armyLimits,
  availableCampaigns,
  eligibility,
  recommendedSupplies,
  supplyCostTotal,
  supplyPrice,
  supplyWeight,
  wagonCapacity,
} from '../../meta/game';
import { commandCost } from '../../meta/soldier';
import { Bar, Icon, ResList, Tip, TypeIcon } from '../common';
import { useStore } from '../store';
import { SoldierCard, squadOrder } from './Roster';
import { sfx } from '../../audio/sfx';

export function Prep() {
  const s = useStore();
  const g = s.game!;
  const camps = availableCampaigns(g);
  const [campId, setCampId] = useState(camps[0]?.id);
  const c = camps.find((x) => x.id === campId) ?? camps[0];
  const lim = armyLimits(g, c);
  const [army, setArmy] = useState<string[]>(() => {
    // Suggest a balanced force within the limits.
    const pick: string[] = [];
    const want: Record<string, number> = { footman: 2, spearman: 2, crossbowman: 1 };
    // The royal guard takes a footman's place in the line.
    const role = (t: string) => (t === 'collie_guard' ? 'footman' : t);
    const pool = g.roster.filter((so) => eligibility(g, so, c).ok).sort((a, b) => b.level - a.level || b.men - a.men || b.hp - a.hp);
    for (const so of pool) {
      if (pick.length >= lim.slots) break;
      if ((want[role(so.typeId)] ?? 0) <= 0) continue;
      if (armyCommand(g, [...pick, so.id]) > lim.command) continue;
      pick.push(so.id);
      want[role(so.typeId)]--;
    }
    return pick;
  });
  const xb = army.filter((id) => g.roster.find((so) => so.id === id)?.typeId === 'crossbowman').length;
  const [supplies, setSupplies] = useState<Record<SupplyId, number>>(() => {
    return recommendedSupplies(5, 1, wagonCapacity(g), c.stages + 1);
  });
  const cp = armyCommand(g, army);
  const cost = supplyCostTotal(g, supplies);
  const weight = supplyWeight(supplies);
  const cap = wagonCapacity(g);
  const marchesFood = Math.ceil(army.length / 2);
  const marchesCovered = marchesFood ? Math.floor(supplies.rations / marchesFood) : 0;
  const counts = useMemo(() => {
    const out: Record<string, number> = {};
    for (const id of army) {
      const t = g.roster.find((so) => so.id === id)!.typeId;
      out[t] = (out[t] ?? 0) + 1;
    }
    return out;
  }, [army, g.roster]);
  const men = army.reduce((n, id) => n + (g.roster.find((so) => so.id === id)?.men ?? 0), 0);

  const toggle = (id: string) => {
    const so = g.roster.find((x) => x.id === id)!;
    if (army.includes(id)) {
      setArmy(army.filter((x) => x !== id));
      sfx('click');
      return;
    }
    if (!eligibility(g, so, c).ok || army.length >= lim.slots || cp + commandCost(so) > lim.command) {
      sfx('deny');
      return;
    }
    setArmy([...army, id]);
    sfx('select');
  };
  const add = (k: SupplyId, n: number) => {
    const v = Math.max(0, supplies[k] + n);
    setSupplies({ ...supplies, [k]: v });
    sfx('click');
  };
  const problems: string[] = [];
  if (army.length === 0) problems.push('Choose at least one squad.');
  if (cost > g.resources.silver) problems.push('Not enough silver for these supplies.');
  if (weight > cap) problems.push('The wagon is overloaded.');
  const warnings: string[] = [];
  if (army.length && marchesCovered < c.stages + 1) warnings.push(`Rations cover only ${marchesCovered} marches; the road is about ${c.stages + 1}.`);
  if (xb && supplies.bolts === 0) warnings.push('No spare bolts: crossbowmen will run dry.');
  if (supplies.torches === 0) warnings.push('No torches: night camps risk raids.');
  const thin = army.filter((id) => {
    const so = g.roster.find((x) => x.id === id);
    return so && so.men < squadSize(so.typeId);
  }).length;
  if (thin) warnings.push(`${thin === 1 ? 'One squad marches' : `${thin} squads march`} below strength. The Barracks can refill them first.`);

  return (
    <div className="layer" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <div className="panel" style={{ width: 'min(1460px, 96vw)', height: 'min(860px, 92vh)', padding: '16px 20px', display: 'flex', flexDirection: 'column', animation: 'rise 0.35s ease' }}>
        <div className="row" style={{ justifyContent: 'space-between' }}>
          <h2 style={{ fontSize: 28 }}>Plan the Expedition</h2>
          <div className="row" style={{ gap: 14 }}>
            <ResList res={g.resources} size={20} />
            <button className="btn" onClick={() => s.goBase()}>
              Back to camp
            </button>
          </div>
        </div>
        <div className="flourish" />
        <div style={{ flex: 1, display: 'grid', gridTemplateColumns: '1fr 1.55fr 1fr', gap: 16, minHeight: 0 }}>
          {/* Campaign */}
          <div className="col scroll" style={{ minHeight: 0 }}>
            <h3 style={{ fontSize: 18 }}>1. Campaign</h3>
            {camps.map((cc) => (
              <div key={cc.id} className={`card clickable ${cc.id === c.id ? 'sel' : ''}`} onClick={() => setCampId(cc.id)}>
                <div className="row" style={{ justifyContent: 'space-between' }}>
                  <div className="cinzel" style={{ fontWeight: 700, fontSize: 17 }}>{cc.name}</div>
                  <span className="tag gold">Tier {cc.tier} · {cc.tierName}</span>
                </div>
                <div className="small muted">{cc.region}</div>
                <p className="small" style={{ margin: '6px 0' }}>{cc.blurb}</p>
              </div>
            ))}
            <div className="card">
              <h4 style={{ fontSize: 14, marginBottom: 4 }}>Intelligence</h4>
              <div className="small" style={{ marginBottom: 6 }}>
                <b>Expect:</b>{' '}
                {c.hints.enemies.map((t) => (
                  <span key={t} className="tag red" style={{ marginRight: 4 }}>
                    <TypeIcon typeId={t} size={12} /> {UNIT_TYPES[t].plural}
                  </span>
                ))}
              </div>
              <div className="small"><b>Terrain:</b> {c.hints.terrain}</div>
              <div className="small"><b>Length:</b> {c.hints.length}</div>
              <div className="small"><b>Threat:</b> {c.hints.threat}</div>
              <div className="small"><b>Supplies:</b> {c.hints.supplies}</div>
              <div className="small" style={{ marginTop: 6 }}><b>Objective:</b> {c.objective.description}</div>
              <div className="small row" style={{ marginTop: 6, gap: 6 }}>
                <b>Reward:</b> <ResList res={c.reward} size={15} /> <span className="muted">plus all spoils</span>
              </div>
              <div className="small muted" style={{ marginTop: 6 }}>
                Soldiers above {['Recruit', 'Soldier', 'Veteran', 'Sergeant', 'Champion'][c.reluctantAbove - 1]} rank are reluctant to chase goblins (-15 morale).
              </div>
            </div>
          </div>
          {/* Army */}
          <div className="col" style={{ minHeight: 0 }}>
            <div className="row" style={{ justifyContent: 'space-between' }}>
              <h3 style={{ fontSize: 18, whiteSpace: 'nowrap' }}>2. The Army</h3>
              <div className="row small" style={{ gap: 6, flexWrap: 'wrap', justifyContent: 'flex-end', minWidth: 0 }}>
                {army.length > 0 && <span className="tag">{men} soldiers</span>}
                {Object.entries(counts).map(([t, n]) => (
                  <span key={t} className="tag blue">
                    <TypeIcon typeId={t} size={12} /> {n} {n === 1 ? UNIT_TYPES[t].name : UNIT_TYPES[t].plural}
                  </span>
                ))}
              </div>
            </div>
            <div className="grid2">
              <div>
                <div className="small row" style={{ justifyContent: 'space-between' }}>
                  <span className="row" style={{ gap: 4 }}><Icon name="slot" size={16} /> Unit slots</span>
                  <b>{army.length} / {lim.slots}</b>
                </div>
                <div className="row" style={{ gap: 3, marginTop: 3 }}>
                  {Array.from({ length: lim.slots }, (_, i) => (
                    <div key={i} style={{ flex: 1, height: 9, borderRadius: 2, background: i < army.length ? '#2f58b8' : 'rgba(30,18,8,0.25)', boxShadow: 'inset 0 1px 2px rgba(0,0,0,0.4)' }} />
                  ))}
                </div>
              </div>
              <div>
                <div className="small row" style={{ justifyContent: 'space-between' }}>
                  <Tip text="Each squad costs command points by type and rank. Veteran squads cost more: they are worth it, but you can never bring everyone.">
                    <span className="row" style={{ gap: 4 }}><Icon name="cp" size={16} /> Command points</span>
                  </Tip>
                  <b>{cp} / {lim.command}</b>
                </div>
                <div style={{ marginTop: 3 }}>
                  <Bar value={cp} max={lim.command} kind={cp > lim.command ? 'cp over' : 'cp'} />
                </div>
              </div>
            </div>
            <div className="scroll" style={{ flex: 1, minHeight: 0, display: 'grid', gridTemplateColumns: 'minmax(0, 1fr) minmax(0, 1fr)', gap: 7, alignContent: 'start', paddingRight: 4 }}>
              {g.roster
                .slice()
                .sort((a, b) => Number(army.includes(b.id)) - Number(army.includes(a.id)) || squadOrder(a.typeId) - squadOrder(b.typeId))
                .map((so) => {
                  const el = eligibility(g, so, c);
                  const inArmy = army.includes(so.id);
                  const fits = inArmy || (army.length < lim.slots && cp + commandCost(so) <= lim.command);
                  return (
                    <SoldierCard
                      key={so.id}
                      so={so}
                      selected={inArmy}
                      disabled={!el.ok || (!inArmy && !fits)}
                      onClick={() => toggle(so.id)}
                      extra={
                        <>
                          {!el.ok && <span className="tag red" style={{ fontSize: 10 }}>{el.reason}</span>}
                          {el.ok && el.reluctant && <span className="tag gold" style={{ fontSize: 10 }}>Reluctant</span>}
                          {el.ok && !inArmy && !fits && <span className="tag" style={{ fontSize: 10 }}>Over limit</span>}
                        </>
                      }
                    />
                  );
                })}
            </div>
          </div>
          {/* Supplies */}
          <div className="col" style={{ minHeight: 0 }}>
            <div className="row" style={{ justifyContent: 'space-between' }}>
              <h3 style={{ fontSize: 18 }}>3. Supplies</h3>
              <button className="btn sm ghost" onClick={() => setSupplies(recommendedSupplies(army.length, xb, cap, c.stages + 1))}>
                Quartermaster's advice
              </button>
            </div>
            {SUPPLY_ORDER.map((k) => (
              <div key={k} className="card row" style={{ padding: '6px 8px' }}>
                <Tip text={SUPPLIES[k].description} wide>
                  <Icon name={k} size={30} />
                </Tip>
                <div style={{ flex: 1 }}>
                  <div className="cinzel" style={{ fontWeight: 700, fontSize: 14 }}>{SUPPLIES[k].name}</div>
                  <div className="tiny muted">
                    {supplyPrice(g, k)} silver · weight {SUPPLIES[k].weight}
                  </div>
                </div>
                <button className="btn sm" onClick={() => add(k, -1)} disabled={supplies[k] <= 0}>−</button>
                <b className="cinzel" style={{ width: 28, textAlign: 'center', fontSize: 18 }}>{supplies[k]}</b>
                <button className="btn sm" onClick={() => add(k, 1)}>+</button>
              </div>
            ))}
            <div className="card col" style={{ gap: 4 }}>
              <div className="small row" style={{ justifyContent: 'space-between' }}>
                <span className="row" style={{ gap: 4 }}><Icon name="silver" size={15} /> Cost</span>
                <b className={cost > g.resources.silver ? 'neg' : ''}>{cost} / {g.resources.silver}</b>
              </div>
              <div className="small row" style={{ justifyContent: 'space-between' }}>
                <span className="row" style={{ gap: 4 }}><Icon name="weight" size={15} /> Wagon</span>
                <b className={weight > cap ? 'neg' : ''}>{weight} / {cap}</b>
              </div>
              <Bar value={weight} max={cap} kind={weight > cap ? 'over' : 'fatigue'} />
              <div className="small row" style={{ justifyContent: 'space-between' }}>
                <span className="row" style={{ gap: 4 }}><Icon name="rations" size={15} /> Marches fed</span>
                <b>{marchesCovered}</b>
              </div>
              <div className="tiny muted">Silver left after buying: {g.resources.silver - cost}. Leftovers sell back cheaply on return.</div>
            </div>
            {warnings.map((w) => (
              <div key={w} className="small" style={{ color: '#8a4a10' }}>⚠ {w}</div>
            ))}
            {problems.map((w) => (
              <div key={w} className="small neg">✖ {w}</div>
            ))}
            <div style={{ flex: 1 }} />
            <button className="btn big primary" disabled={problems.length > 0} onClick={() => s.launch(c.id, army, supplies, cost)}>
              March Out
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
