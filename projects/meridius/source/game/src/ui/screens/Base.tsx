import { useState } from 'react';
import { BUILDINGS, buildingById } from '../../data/buildings';
import { INJURIES, SUPPLIES, SUPPLY_ORDER } from '../../data/items';
import { ABILITIES } from '../../data/abilities';
import { UNIT_TYPES } from '../../data/units';
import { campaignById } from '../../data/campaigns';
import {
  armyLimits,
  availableCampaigns,
  buyEquip,
  canAfford,
  canBuyEquip,
  canDrill,
  canPromoteHere,
  canReinforce,
  drill,
  drillCost,
  effect,
  grantLeave,
  hire,
  leaveCost,
  level,
  missingMen,
  nextEquip,
  nextLevel,
  promote,
  promoteCost,
  recruitCost,
  reinforce,
  reinforceCost,
  repair,
  repairCost,
  rosterCap,
  supplyPrice,
  treat,
  treatCost,
  upgradeBuilding,
  wagonCapacity,
  type GameState,
} from '../../meta/game';
import { commandCost, rankName, soldierStats, type Soldier } from '../../meta/soldier';
import { squadSize } from '../../data/units';
import { Bar, Icon, MenPips, Portrait, ResList, RosterSquadBar, Tip, TypeIcon, squadTypeLabel } from '../common';
import { useStore } from '../store';
import { sfx } from '../../audio/sfx';
import { RosterPanel, SoldierDetail } from './Roster';
import { TopBar } from './TopBar';

export function Base() {
  const s = useStore();
  const g = s.game!;
  const hover = s.baseScene?.ui.hover;
  // On smaller screens the full chronicle covers the west side of the camp, so it opens with the latest entry only.
  const [chronicleOpen, setChronicleOpen] = useState(() => window.innerWidth >= 1600 && window.innerHeight >= 900);
  const entries = g.chronicle.slice(0, chronicleOpen ? 9 : 1);
  return (
    <div className="layer">
      <TopBar />
      <div className="panel dark" style={{ position: 'absolute', left: 14, top: 68, width: 300, padding: '10px 14px' }}>
        <div className="title" style={{ fontSize: 17 }}>Company Chronicle</div>
        <div className="scroll" style={{ maxHeight: 240, fontSize: 13.5, lineHeight: 1.4 }}>
          {entries.map((c, i) => (
            <div key={i} style={{ marginBottom: 6, color: c.tone === 'bad' ? '#ffb0a0' : c.tone === 'good' ? '#c8eab0' : '#efe2c2' }}>
              <span className="muted tiny">Exp. {c.cycle} · </span>
              {c.text}
            </div>
          ))}
        </div>
        {g.chronicle.length > 1 && (
          <button className="btn ghost sm" style={{ display: 'block', margin: '2px auto 0' }} onClick={() => setChronicleOpen(!chronicleOpen)}>
            {chronicleOpen ? 'Latest only' : `Earlier entries (${Math.min(9, g.chronicle.length) - 1})`}
          </button>
        )}
      </div>
      {hover && !s.panel && (
        <div className="panel dark" style={{ position: 'absolute', left: '50%', bottom: 26, transform: 'translateX(-50%)', padding: '8px 16px', textAlign: 'center', pointerEvents: 'none' }}>
          <div className="cinzel" style={{ fontWeight: 700 }}>{buildingById(hover).levels[level(g, hover) - 1].name}</div>
          <div className="small muted">{buildingById(hover).role} Click to enter.</div>
        </div>
      )}
      <div style={{ position: 'absolute', right: 18, bottom: 18, display: 'flex', gap: 12, alignItems: 'flex-end' }}>
        <button className="btn big" onClick={() => s.openPanel('roster')}>
          Roster ({g.roster.length})
        </button>
        <button className="btn big primary pulse" onClick={() => s.goPrep()}>
          Plan Expedition
        </button>
      </div>
      {s.panel && (
        <div className="modal-back" onClick={() => s.openPanel(null)}>
          <div onClick={(e) => e.stopPropagation()}>
            {s.panel === 'roster' ? <RosterPanel /> : s.panel === 'memorial' ? <Memorial /> : <BuildingPanel id={s.panel} />}
          </div>
        </div>
      )}
      {s.soldier && <SoldierDetail key={s.soldier} id={s.soldier} />}
      {!g.flags?.welcome && !s.panel && <Welcome />}
    </div>
  );
}

function Welcome() {
  const s = useStore();
  const g = s.game!;
  const close = () => {
    g.flags = { ...(g.flags ?? {}), welcome: true };
    s.commit();
  };
  return (
    <div className="modal-back">
      <div className="panel dialog" style={{ width: 640 }}>
        <div className="title">To the Captain of the Amberfeld Company</div>
        <p style={{ fontStyle: 'italic' }}>
          A host of goblins and orcs is coming out of the Hillsvain Woods, more than anyone has ever counted, and it is burning every steading west of the Vattern. The Margrave's riders are days away. The council has given you six squads of six, a camp of tents and a little silver. You are what stands between the host and the river. Slow it, and hold Brannsted until the riders come.
        </p>
        <div className="flourish" />
        <div className="col" style={{ gap: 4, fontSize: 15.5 }}>
          <div><b>1. Prepare.</b> Hire new squads and refill thinned ones at the Barracks. Then plan an expedition: choose which squads march within the army limit, and pack supplies.</div>
          <div><b>2. March.</b> Pick a path across the map. Fight, scout, loot, rest. Wounds, fallen soldiers, morale and supplies carry from one fight to the next.</div>
          <div><b>3. Return.</b> Come home with the spoils, win or lose. Spend them on buildings, gear and training, then go again.</div>
        </div>
        <p className="small muted">The Field Manual (top bar) explains facing, flanks, morale and supplies whenever you need it.</p>
        <div className="row" style={{ justifyContent: 'center', gap: 10 }}>
          <button className="btn" onClick={() => { close(); s.openManual('battle'); }}>Read the Field Manual</button>
          <button className="btn primary" onClick={close}>To work</button>
        </div>
      </div>
    </div>
  );
}

function Memorial() {
  const s = useStore();
  const g = s.game!;
  return (
    <div className="panel dialog" style={{ width: 640 }}>
      <div className="title">The Fallen</div>
      <p className="muted" style={{ textAlign: 'center', marginTop: -4 }}>Their names are cut into the gatepost of Amberfeld.</p>
      <div className="scroll col" style={{ maxHeight: '60vh' }}>
        {!g.fallen.length && <p style={{ textAlign: 'center' }}>No squad of the company has been lost. Yet.</p>}
        {g.fallen.map((f, i) => (
          <div key={i} className="card row">
            <Portrait typeId={f.typeId} size={44} dead />
            <div style={{ flex: 1 }}>
              <div className="cinzel" style={{ fontWeight: 700 }}>{f.name}</div>
              <div className="small muted">
                {squadTypeLabel(f.typeId, f.level)} · {f.battles} battles · {f.kills} enemy squads slain
              </div>
            </div>
            <div className="small" style={{ textAlign: 'right' }}>
              {f.cause}
              <div className="tiny muted">Expedition {f.cycle}</div>
            </div>
          </div>
        ))}
      </div>
      <div className="row" style={{ justifyContent: 'center', marginTop: 12 }}>
        <button className="btn" onClick={() => s.openPanel(null)}>Close</button>
      </div>
    </div>
  );
}

function Pips({ n, max }: { n: number; max: number }) {
  return (
    <span style={{ letterSpacing: 3, color: '#a37a2a' }}>
      {Array.from({ length: max }, (_, i) => (i < n ? '◆' : '◇')).join('')}
    </span>
  );
}

function BuildingPanel({ id }: { id: string }) {
  const s = useStore();
  const g = s.game!;
  const b = buildingById(id);
  const lvl = level(g, id);
  const cur = b.levels[lvl - 1];
  const nl = nextLevel(g, id);
  return (
    <div className="panel dialog" style={{ width: 760, display: 'flex', flexDirection: 'column' }}>
      <div className="row" style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <div>
          <h2 style={{ fontSize: 26 }}>{cur.name}</h2>
          <div className="muted">{b.role}</div>
        </div>
        <div style={{ textAlign: 'right' }}>
          <Pips n={lvl} max={b.levels.length} />
          <div className="small muted">Level {lvl}</div>
        </div>
      </div>
      <div className="flourish" />
      <div className="scroll" style={{ maxHeight: '54vh', paddingRight: 4 }}>
        <BuildingBody id={id} g={g} />
      </div>
      <div className="flourish" />
      <div className="row" style={{ justifyContent: 'space-between' }}>
        {nl ? (
          <div className="row" style={{ gap: 12 }}>
            <div>
              <div className="cinzel" style={{ fontWeight: 700 }}>
                Upgrade to {nl.name}
              </div>
              <div className="small">{nl.description}</div>
            </div>
            <ResList res={nl.cost} />
            <button
              className="btn gold"
              disabled={!canAfford(g, nl.cost)}
              onClick={() => {
                if (upgradeBuilding(g, id)) {
                  sfx('build');
                  s.commit();
                }
              }}
            >
              Build
            </button>
          </div>
        ) : (
          <div className="muted">Fully upgraded.</div>
        )}
        <button className="btn" onClick={() => s.openPanel(null)}>
          Close
        </button>
      </div>
    </div>
  );
}

function SoldierRow({ s: so, children, onClick }: { s: Soldier; children?: React.ReactNode; onClick?: () => void }) {
  const st = soldierStats(so);
  return (
    <div className={`card row ${onClick ? 'clickable' : ''}`} onClick={onClick}>
      <Portrait typeId={so.typeId} variant={so.portrait} size={42} />
      <div style={{ width: 190 }}>
        <div className="cinzel" style={{ fontWeight: 700, fontSize: 14, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
          {so.name}
        </div>
        <div className="small muted row" style={{ gap: 4, whiteSpace: 'nowrap' }}>
          <TypeIcon typeId={so.typeId} size={14} /> {squadTypeLabel(so.typeId, so.level, true)}
        </div>
      </div>
      <div style={{ width: 104, gap: 4 }} className="col">
        <MenPips men={so.men} size={squadSize(so.typeId)} />
        <RosterSquadBar so={so} height={7} />
        <Bar value={so.morale} max={st.morale} kind="morale" height={6} label={`Morale ${so.morale}/${st.morale}`} />
      </div>
      <div className="row" style={{ flex: 1, flexWrap: 'wrap', gap: 4 }}>
        {so.recovering && <span className="tag blue">Recovering</span>}
        {so.injuries.map((i) => (
          <span key={i} className="tag red">
            {INJURIES[i].name}
          </span>
        ))}
      </div>
      {children}
    </div>
  );
}

function BuildingBody({ id, g }: { id: string; g: GameState }) {
  const s = useStore();
  const [_, force] = useState(0);
  const act = (ok: boolean, sound = 'coin') => {
    if (ok) {
      sfx(sound);
      s.commit();
      force((x) => x + 1);
    } else sfx('deny');
  };
  void _;
  if (id === 'command') {
    const camps = availableCampaigns(g);
    return (
      <div className="col">
        <p style={{ margin: 0 }}>
          The map table shows the frontier from Karstenburg to the Vattern. From here the company plans its expeditions. A larger staff lets you field more soldiers.
        </p>
        {camps.map((c) => {
          const lim = armyLimits(g, c);
          return (
            <div key={c.id} className="card">
              <div className="row" style={{ justifyContent: 'space-between' }}>
                <div className="cinzel" style={{ fontWeight: 700 }}>{c.name}</div>
                <span className="tag gold">Tier {c.tier} · {c.tierName}</span>
              </div>
              <div className="small">{c.blurb}</div>
              <div className="row small" style={{ marginTop: 6, gap: 14 }}>
                <span className="row" style={{ gap: 4 }}><Icon name="slot" /> {lim.slots} unit slots</span>
                <span className="row" style={{ gap: 4 }}><Icon name="cp" /> {lim.command} command points</span>
                <span className="muted">Completed {g.completed[c.id] ?? 0}×</span>
              </div>
            </div>
          );
        })}
        <div className="small muted">Harder campaign tiers open in later builds as the company grows.</div>
        <div>
          <button className="btn primary" onClick={() => s.goPrep()}>
            Plan an expedition
          </button>
        </div>
      </div>
    );
  }
  if (id === 'barracks') {
    const cap = rosterCap(g);
    const low = g.roster.filter((so) => so.morale < soldierStats(so).morale);
    const thin = g.roster.filter((so) => missingMen(so) > 0).sort((a, b) => missingMen(b) - missingMen(a) || b.level - a.level);
    const refillAll = thin.reduce((n, so) => n + missingMen(so) * reinforceCost(g, so), 0);
    return (
      <div className="col">
        <div className="row" style={{ justifyContent: 'space-between' }}>
          <h3 style={{ fontSize: 17 }}>Recruits at the gate</h3>
          <span className="small">
            Roster {g.roster.length}/{cap} squads · New squads arrive after each expedition
          </span>
        </div>
        {!g.recruits.length && <div className="muted">No one else answers the muster this time.</div>}
        <div className="grid2">
          {g.recruits.map((r) => {
            const cost = recruitCost(r);
            const def = UNIT_TYPES[r.typeId];
            return (
              <div key={r.id} className="card row" style={{ alignItems: 'flex-start' }}>
                <Portrait typeId={r.typeId} variant={r.portrait} size={54} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div className="cinzel" style={{ fontWeight: 700, fontSize: 14 }}>
                    {r.name}
                  </div>
                  <div className="small">
                    {squadTypeLabel(r.typeId, r.level)} <span className="muted">· {def.role}</span>
                  </div>
                  <div className="small muted row" style={{ gap: 8 }}>
                    <MenPips men={r.men} size={squadSize(r.typeId)} />
                    <span className="row" style={{ gap: 3, whiteSpace: 'nowrap' }}><Icon name="cp" size={14} /> {commandCost(r)} CP</span>
                    {r.typeId === 'collie_guard' && <span className="tag gold" style={{ fontSize: 10 }}>Elite</span>}
                    {(def.crew || def.tags?.includes('caster')) && <span className="tag blue" style={{ fontSize: 10 }}>{def.crew ? 'War machine' : 'Mages'}</span>}
                  </div>
                  {(def.crew || def.tags?.includes('caster')) && <div className="tiny muted" style={{ marginTop: 2 }}>{def.blurb}</div>}
                </div>
                <button className="btn sm gold" disabled={g.resources.silver < cost || g.roster.length >= cap} onClick={() => act(hire(g, r.id))}>
                  {cost === 0 ? 'Take on volunteer' : <>Hire <Icon name="silver" size={14} /> {cost}</>}
                </button>
              </div>
            );
          })}
        </div>
        {level(g, 'barracks') < 2 && <div className="small muted">A proper Barracks (level 2) draws the Border Collie Royal Guard to the gate now and then.</div>}
        <div className="small muted">Each muster one specialist squad also offers its service: three battle mages, or a ballista or mangonel with its crew.</div>
        <div className="flourish" />
        <div className="row" style={{ justifyContent: 'space-between' }}>
          <h3 style={{ fontSize: 17 }}>Reinforcements</h3>
          {thin.length > 1 && (
            <Tip text={g.resources.silver >= refillAll ? `Fill every empty place in the company for ${refillAll} silver.` : `Needs ${refillAll} silver.`}>
              <button
                className="btn sm gold"
                disabled={g.resources.silver < refillAll}
                onClick={() => act(thin.reduce((ok, so) => reinforce(g, so.id, missingMen(so)) || ok, false))}
              >
                Refill all <Icon name="silver" size={14} /> {refillAll}
              </button>
            </Tip>
          )}
        </div>
        <div className="small muted">
          The dead stay dead: rest and surgeons heal the survivors, and only new soldiers from the Barracks fill a squad's empty places. Each arrives fit and drilled to the squad's rank.
        </div>
        {thin.map((so) => {
          const miss = missingMen(so);
          const rc = reinforceCost(g, so);
          const one = canReinforce(g, so, 1);
          const all = canReinforce(g, so, miss);
          return (
            <SoldierRow key={so.id} s={so}>
              <div className="small" style={{ width: 92, textAlign: 'right' }}>
                {miss} short
                <div className="tiny muted">{rc} silver each</div>
              </div>
              <Tip text={one.ok ? `One new ${UNIT_TYPES[so.typeId].name.toLowerCase()} joins ${so.name}'s squad (${rc} silver).` : one.reason}>
                <button className="btn sm gold" disabled={!one.ok} onClick={() => act(reinforce(g, so.id))}>
                  +1 <Icon name="silver" size={14} /> {rc}
                </button>
              </Tip>
              {miss > 1 && (
                <Tip text={all.ok ? `Bring the squad to full strength: ${miss} soldiers for ${rc * miss} silver.` : all.reason}>
                  <button className="btn sm gold" disabled={!all.ok} onClick={() => act(reinforce(g, so.id, miss))}>
                    Refill <Icon name="silver" size={14} /> {rc * miss}
                  </button>
                </Tip>
              )}
            </SoldierRow>
          );
        })}
        {!thin.length && <div className="muted small">Every squad stands at full strength.</div>}
        <div className="flourish" />
        <h3 style={{ fontSize: 17 }}>Leave and recovery</h3>
        <div className="small muted">
          Squads who stay home recover 20 morale per expedition. Leave restores morale fully, but the squad sits out the next expedition. Cost {leaveCost(g)} silver.
        </div>
        {low.map((so) => (
          <SoldierRow key={so.id} s={so}>
            <button className="btn sm" disabled={so.recovering || g.resources.silver < leaveCost(g)} onClick={() => act(grantLeave(g, so.id))}>
              Grant leave
            </button>
          </SoldierRow>
        ))}
        {!low.length && <div className="muted small">Everyone's spirits are high.</div>}
      </div>
    );
  }
  if (id === 'training') {
    const promo = effect(g, 'training', 'promote');
    const pc = promoteCost(g);
    return (
      <div className="col">
        <div className="small muted">
          Drill grants 10 XP (once per squad per expedition) up to {rankName(effect(g, 'training', 'drillMaxLevel'))} rank.{' '}
          {promo ? `Veterans can be promoted to learn a second ability (${pc.silver} silver, ${pc.iron} iron).` : 'Upgrade the yard to promote veterans.'}
        </div>
        {g.roster.map((so) => {
          const d = canDrill(g, so);
          const p = canPromoteHere(g, so);
          const promoAb = UNIT_TYPES[so.typeId].promotion;
          return (
            <SoldierRow key={so.id} s={so}>
              <div style={{ width: 110 }}>
                <div className="tiny muted">
                  XP {so.xp}
                  {so.promoted && ' · Promoted'}
                </div>
              </div>
              <Tip text={d.ok ? `Costs ${drillCost(g, so)} silver.` : d.reason}>
                <button className="btn sm" disabled={!d.ok} onClick={() => act(drill(g, so.id))}>
                  Drill {drillCost(g, so)}
                </button>
              </Tip>
              {promoAb && !so.promoted && (
                <Tip text={<><b>{ABILITIES[promoAb].name}</b>: {ABILITIES[promoAb].description}{!p.ok && <div style={{ color: '#ffb0a0' }}>{p.reason}</div>}</>} wide>
                  <button className="btn sm gold" disabled={!p.ok} onClick={() => act(promote(g, so.id), 'build')}>
                    Promote
                  </button>
                </Tip>
              )}
            </SoldierRow>
          );
        })}
      </div>
    );
  }
  if (id === 'armoury') {
    return (
      <div className="col">
        <div className="small muted">Armour wears down with every blow taken. Worn armour protects less. The smith forges tier {effect(g, 'armoury', 'tier')} gear.</div>
        {g.roster.map((so) => {
          const wn = nextEquip(g, so, 'weapon');
          const an = nextEquip(g, so, 'armor');
          const wc = canBuyEquip(g, so, 'weapon');
          const ac = canBuyEquip(g, so, 'armor');
          const rc = repairCost(g, so);
          return (
            <SoldierRow key={so.id} s={so}>
              <div className="col" style={{ gap: 3 }}>
                <span className="tiny">Armour {Math.round(so.armorCondition * 100)}%</span>
                <button className="btn sm" disabled={rc <= 0 || g.resources.silver < rc} onClick={() => act(repair(g, so.id), 'build')}>
                  Repair {rc > 0 ? rc : ''}
                </button>
              </div>
              {wn && (
                <Tip text={<>{wn.name}: {Object.entries(wn.bonus).map(([k, v]) => `+${v} ${k}`).join(', ')}{!wc.ok && <div style={{ color: '#ffb0a0' }}>{wc.reason}</div>}</>}>
                  <button className="btn sm gold" disabled={!wc.ok} onClick={() => act(buyEquip(g, so.id, 'weapon'), 'build')}>
                    <Icon name="sword" size={14} /> T{wn.tier} <ResList res={wn.cost} size={12} />
                  </button>
                </Tip>
              )}
              {an && (
                <Tip text={<>{an.name}: {Object.entries(an.bonus).map(([k, v]) => `+${v} ${k}`).join(', ')}{!ac.ok && <div style={{ color: '#ffb0a0' }}>{ac.reason}</div>}</>}>
                  <button className="btn sm gold" disabled={!ac.ok} onClick={() => act(buyEquip(g, so.id, 'armor'), 'build')}>
                    <Icon name="shield" size={14} /> T{an.tier} <ResList res={an.cost} size={12} />
                  </button>
                </Tip>
              )}
            </SoldierRow>
          );
        })}
      </div>
    );
  }
  if (id === 'infirmary') {
    const hurt = g.roster.filter((so) => so.injuries.length);
    const surv = effect(g, 'infirmary', 'survival');
    return (
      <div className="col">
        <div className="small muted">
          A sergeant's lasting injury weakens the whole squad until treated. Treatment benches the squad for the next expedition.{' '}
          {surv ? `Field surgeons add ${Math.round(surv * 100)}% to the chance that a cut-down squad's sergeant survives.` : 'Better surgeons will save more sergeants of squads cut down in battle.'}
        </div>
        {!hurt.length && <p>The cots are empty. Long may it last.</p>}
        {hurt.map((so) => (
          <SoldierRow key={so.id} s={so}>
            <div className="col">
              {so.injuries.map((inj) => (
                <Tip key={inj} text={`${INJURIES[inj].description} ${Object.entries(INJURIES[inj].effect).map(([k, v]) => `${v} ${k}`).join(', ')}`}>
                  <button className="btn sm" disabled={g.resources.silver < treatCost(g, inj)} onClick={() => act(treat(g, so.id, inj))}>
                    Treat {INJURIES[inj].name} · {treatCost(g, inj)}
                  </button>
                </Tip>
              ))}
            </div>
          </SoldierRow>
        ))}
      </div>
    );
  }
  if (id === 'quartermaster') {
    return (
      <div className="col">
        <div className="small">
          Wagon capacity <b>{wagonCapacity(g)}</b>. Leftover supplies are bought back at {Math.round(effect(g, 'quartermaster', 'buyback') * 100)}% when the company returns.
        </div>
        {SUPPLY_ORDER.map((k) => (
          <div key={k} className="card row">
            <Icon name={k} size={28} />
            <div style={{ flex: 1 }}>
              <div className="cinzel" style={{ fontWeight: 700 }}>{SUPPLIES[k].name}</div>
              <div className="small">{SUPPLIES[k].description}</div>
            </div>
            <div className="small" style={{ textAlign: 'right', width: 90 }}>
              <div className="row" style={{ justifyContent: 'flex-end', gap: 4 }}><Icon name="silver" size={14} /> {supplyPrice(g, k)}</div>
              <div className="muted">weight {SUPPLIES[k].weight}</div>
            </div>
          </div>
        ))}
        <div className="small muted">Supplies are bought when planning an expedition.</div>
      </div>
    );
  }
  return null;
}

export { BUILDINGS, campaignById };
