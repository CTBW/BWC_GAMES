import { useState } from 'react';
import { ABILITIES } from '../../data/abilities';
import { EQUIPMENT, INJURIES } from '../../data/items';
import { UNIT_TYPES, squadSize } from '../../data/units';
import { canReinforce, dismiss, missingMen, reinforce, reinforceCost, rosterCap } from '../../meta/game';
import { abilitiesOf, commandCost, fatigueLabel, rankName, soldierDamage, soldierStats, squadHpCap, xpToNext, type Soldier } from '../../meta/soldier';
import { Bar, Icon, MenPips, Portrait, RosterSquadBar, Tip, TypeIcon, squadTypeLabel } from '../common';
import { useStore } from '../store';
import { sfx } from '../../audio/sfx';

/** Order squads are listed in: the line first, then spears, then missiles, mages and war machines. */
export const SQUAD_ORDER = ['collie_guard', 'footman', 'spearman', 'crossbowman', 'battle_mage', 'ballista', 'mangonel'];
export const squadOrder = (typeId: string) => {
  const i = SQUAD_ORDER.indexOf(typeId);
  return i < 0 ? SQUAD_ORDER.length : i;
};

export function SoldierCard({ so, onClick, selected, disabled, extra }: { so: Soldier; onClick?: () => void; selected?: boolean; disabled?: boolean; extra?: React.ReactNode }) {
  const st = soldierStats(so);
  return (
    <div className={`card ${onClick ? 'clickable' : ''} ${selected ? 'sel' : ''} ${disabled ? 'disabled' : ''}`} onClick={onClick} style={{ display: 'flex', gap: 8 }}>
      <Portrait typeId={so.typeId} variant={so.portrait} size={52} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div className="row" style={{ justifyContent: 'space-between' }}>
          <div className="cinzel" style={{ fontWeight: 700, fontSize: 13.5, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{so.name}</div>
          <span className="tag" title="Command points">
            <Icon name="cp" size={12} />
            {commandCost(so)}
          </span>
        </div>
        <div className="tiny row" style={{ gap: 4, minWidth: 0, whiteSpace: 'nowrap', overflow: 'hidden' }}>
          <TypeIcon typeId={so.typeId} size={13} />
          <span style={{ overflow: 'hidden', textOverflow: 'ellipsis' }} title={squadTypeLabel(so.typeId, so.level)}>{squadTypeLabel(so.typeId, so.level, true)}</span>
          {so.promoted && <span className="tag gold" style={{ padding: '0 3px' }}>★</span>}
        </div>
        <div className="col" style={{ gap: 3, marginTop: 3 }}>
          <div className="row" style={{ gap: 6 }}>
            <div style={{ flex: 1, minWidth: 0 }}>
              <RosterSquadBar so={so} height={7} />
            </div>
            <MenPips men={so.men} size={squadSize(so.typeId)} />
          </div>
          <Bar value={so.morale} max={st.morale} kind="morale" label={`Morale ${so.morale}/${st.morale}`} height={6} />
        </div>
        <div className="row" style={{ gap: 3, flexWrap: 'wrap', marginTop: 4 }}>
          {so.injuries.map((i) => (
            <span key={i} className="tag red" style={{ fontSize: 10 }}>
              {INJURIES[i].name}
            </span>
          ))}
          {so.recovering && <span className="tag blue" style={{ fontSize: 10 }}>Recovering</span>}
          {so.armorCondition < 0.7 && <span className="tag" style={{ fontSize: 10 }}>Worn armour</span>}
          {missingMen(so) > 0 && <span className="tag" style={{ fontSize: 10 }}>{missingMen(so)} short</span>}
          {extra}
        </div>
      </div>
    </div>
  );
}

export function RosterPanel() {
  const s = useStore();
  const g = s.game!;
  const sorted = g.roster.slice().sort((a, b) => squadOrder(a.typeId) - squadOrder(b.typeId) || b.level - a.level);
  const men = g.roster.reduce((n, so) => n + so.men, 0);
  return (
    <div className="panel dialog" style={{ width: 900 }}>
      <div className="title">
        The Amberfeld Company <span className="muted small">({g.roster.length}/{rosterCap(g)} squads · {men} soldiers)</span>
      </div>
      <div className="scroll" style={{ maxHeight: '62vh', display: 'grid', gridTemplateColumns: 'repeat(3, minmax(0, 1fr))', gap: 8 }}>
        {sorted.map((so) => (
          <SoldierCard key={so.id} so={so} onClick={() => s.openSoldier(so.id)} />
        ))}
      </div>
      <div className="row" style={{ justifyContent: 'space-between', marginTop: 12 }}>
        <span className="small muted">Click a squad for details. Veteran squads cost more command points but fight far better. Refill thinned squads at the Barracks.</span>
        <button className="btn" onClick={() => s.openPanel(null)}>
          Close
        </button>
      </div>
    </div>
  );
}

export function SoldierDetail({ id }: { id: string }) {
  const s = useStore();
  const g = s.game!;
  const so = g.roster.find((x) => x.id === id);
  const [name, setName] = useState(so?.name ?? '');
  if (!so) return null;
  const def = UNIT_TYPES[so.typeId];
  const st = soldierStats(so);
  const dmg = soldierDamage(so);
  const nx = xpToNext(so);
  const weapon = def.weaponLine ? EQUIPMENT[def.weaponLine].tiers[so.weaponTier - 1] : undefined;
  const armor = def.armorLine ? EQUIPMENT[def.armorLine].tiers[so.armorTier - 1] : undefined;
  const abil = abilitiesOf(so);
  const size = squadSize(so.typeId);
  const missing = missingMen(so);
  const rc = reinforceCost(g, so);
  const one = canReinforce(g, so, 1);
  const all = canReinforce(g, so, missing);
  const times = (r: [number, number]) => `${r[0]}–${r[1]} × ${so.men} = ${r[0] * so.men}–${r[1] * so.men}`;
  const caster = !!def.tags?.includes('caster');
  const who = def.crew ? 'crewmen' : caster ? 'mages' : 'soldiers';
  const lob = def.primary ? ABILITIES[def.primary] : undefined;
  const close = () => {
    if (name.trim() && name !== so.name) {
      so.name = name.trim().slice(0, 32);
      s.commit();
    }
    s.openSoldier(null);
  };
  return (
    <div className="modal-back" onClick={close} style={{ zIndex: 20 }}>
      <div className="panel dialog" style={{ width: 760 }} onClick={(e) => e.stopPropagation()}>
        <div className="row" style={{ alignItems: 'flex-start', gap: 16 }}>
          <Portrait typeId={so.typeId} variant={so.portrait} size={128} />
          <div style={{ flex: 1 }}>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="cinzel"
              style={{ fontSize: 24, fontWeight: 700, background: 'transparent', border: 'none', borderBottom: '1px dashed rgba(91,70,48,0.4)', color: 'var(--ink)', width: '100%', outline: 'none' }}
              title="Rename the squad's sergeant"
            />
            <div className="row" style={{ gap: 6, marginTop: 4 }}>
              <TypeIcon typeId={so.typeId} />
              <b>{rankName(so.level)}</b> {def.plural} <span className="muted">· {def.role}</span>
              <MenPips men={so.men} size={size} />
              {so.promoted && <span className="tag gold">Promoted</span>}
              <span className="tag blue">
                <Icon name="cp" size={12} /> {commandCost(so)} CP
              </span>
            </div>
            <div className="small" style={{ marginTop: 6 }}>{def.blurb}</div>
            <div className="row" style={{ gap: 10, marginTop: 8 }}>
              <div style={{ flex: 1 }}>
                <div className="tiny">Experience {nx ? `${nx.have}/${nx.need}` : '(max rank)'}</div>
                <Bar value={nx?.have ?? 1} max={nx?.need ?? 1} kind="xp" />
              </div>
              <div style={{ flex: 1.3 }}>
                <div className="tiny">
                  Squad HP {so.hp}/{squadHpCap(so)} <span className="muted">· {st.hp} per soldier</span>
                </div>
                <RosterSquadBar so={so} />
              </div>
              <div style={{ flex: 1 }}>
                <div className="tiny">Morale {so.morale}/{st.morale}</div>
                <Bar value={so.morale} max={st.morale} kind="morale" />
              </div>
            </div>
          </div>
        </div>
        <div className="flourish" />
        <div className="statgrid">
          <div>Melee <b>{st.melee}</b></div>
          <div>{caster ? 'Spell skill' : def.crew ? 'Crew skill' : 'Ranged'} <b>{st.ranged || '–'}</b></div>
          <div>Defense <b>{st.defense}</b></div>
          <div>vs. missiles <b>{st.rangedDefense}</b></div>
          <div>Armour <b>{(st.armor * so.armorCondition).toFixed(1)}</b></div>
          <div>Move <b>{st.move}</b></div>
          {def.shieldFront ? <div>Shield <b>+{def.shieldFront}</b></div> : <div>Shield <b>–</b></div>}
          <div>{def.crew ? 'Crew' : caster ? 'Mages' : 'Soldiers'} <b>{so.men}/{size}</b></div>
          <div style={{ gridColumn: 'span 2' }} title={`Each of the ${so.men} ${who} strikes for ${dmg.melee[0]}–${dmg.melee[1]} before armour.`}>
            Melee damage <b>{times(dmg.melee)}</b>
          </div>
          {lob?.power ? (
            <div style={{ gridColumn: 'span 2' }} title={`${lob.name}: ${lob.power[0]}–${lob.power[1]} per crewman at the engine, half to everyone beside the squad struck.`}>
              Stone <b>{times(lob.power)}</b>
            </div>
          ) : (
            <div style={{ gridColumn: 'span 2' }} title={dmg.shot ? `Each of the ${so.men} ${who} looses for ${dmg.shot[0]}–${dmg.shot[1]} before armour.` : 'No missile weapon.'}>
              {caster ? 'Arcane bolt' : def.crew ? 'Bolt' : 'Shot damage'} <b>{dmg.shot ? times(dmg.shot) : '–'}</b>
            </div>
          )}
          <div>Fatigue <b>{fatigueLabel(so.fatigue)}</b></div>
          <div>Battles <b>{so.battles}</b></div>
          <div title="Enemy squads destroyed">Squads slain <b>{so.kills}</b></div>
        </div>
        <div className="grid2" style={{ marginTop: 10 }}>
          <div className="card">
            <h4 style={{ fontSize: 14 }}>Equipment</h4>
            {weapon ? (
              <div className="small row" style={{ gap: 6 }}><Icon name="sword" size={15} /> {weapon.name} <span className="muted">(tier {so.weaponTier})</span></div>
            ) : (
              <div className="small row" style={{ gap: 6 }}><Icon name={def.crew ? 'engine' : caster ? 'staff' : 'sword'} size={15} /> {def.crew ? `The ${def.name.toLowerCase()} and its tackle` : caster ? 'Staves and spellbooks' : '–'} <span className="muted">(not forged at the armoury)</span></div>
            )}
            {armor ? (
              <div className="small row" style={{ gap: 6 }}><Icon name="shield" size={15} /> {armor.name} <span className="muted">(tier {so.armorTier}, {Math.round(so.armorCondition * 100)}%)</span></div>
            ) : (
              <div className="small row" style={{ gap: 6 }}><Icon name="shield" size={15} /> {caster ? 'Robes, no armour' : 'Leather aprons'}</div>
            )}
            {def.shot?.ammo !== undefined && <div className="small row" style={{ gap: 6 }}><Icon name="bolts" size={15} /> {so.ammo} bolts in the quiver</div>}
          </div>
          <div className="card">
            <h4 style={{ fontSize: 14 }}>Abilities</h4>
            {abil.map((a) => (
              <Tip key={a} text={ABILITIES[a].description} wide>
                <div className="small row" style={{ gap: 6 }}>
                  <Icon name={ABILITIES[a].icon} size={15} /> <b>{ABILITIES[a].name}</b>
                </div>
              </Tip>
            ))}
            {def.promotion && !so.promoted && (
              <div className="small muted">Promotion unlocks: {ABILITIES[def.promotion].name}</div>
            )}
            {def.tags?.includes('firstStrike') && <div className="small muted">Passive: strikes first at enemies that close in from the front.</div>}
            {def.tags?.includes('impale') && <div className="small muted">Passive: a bolt that strikes home goes on into the next foe behind, at half force.</div>}
            {def.crew && <div className="small muted">A war machine: it cannot loose in a turn it has moved.</div>}
          </div>
        </div>
        {so.injuries.length > 0 && (
          <div className="card" style={{ marginTop: 8 }}>
            <h4 style={{ fontSize: 14 }}>Lasting injuries</h4>
            {so.injuries.map((i) => (
              <div key={i} className="small">
                <b>{INJURIES[i].name}</b>: {INJURIES[i].description} ({Object.entries(INJURIES[i].effect).map(([k, v]) => `${v} ${k}`).join(', ')})
              </div>
            ))}
          </div>
        )}
        {missing > 0 && (
          <div className="card row" style={{ marginTop: 8, justifyContent: 'space-between' }}>
            <div className="small">
              <b>{missing} {missing === 1 ? 'place' : 'places'} empty in the ranks.</b>{' '}
              {g.expedition ? 'The Barracks can send replacements once the company is home.' : `The Barracks can fill them for ${rc} silver per soldier.`}
            </div>
            {!g.expedition && (
              <div className="row" style={{ gap: 6 }}>
                <Tip text={one.ok ? `One new ${def.name.toLowerCase()} joins, fit and ready (${rc} silver).` : one.reason}>
                  <button className="btn sm gold" disabled={!one.ok} onClick={() => { if (reinforce(g, so.id)) { sfx('coin'); s.commit(); } else sfx('deny'); }}>
                    +1 <Icon name="silver" size={13} /> {rc}
                  </button>
                </Tip>
                {missing > 1 && (
                  <Tip text={all.ok ? `Bring the squad to full strength: ${missing} soldiers for ${rc * missing} silver.` : all.reason}>
                    <button className="btn sm gold" disabled={!all.ok} onClick={() => { if (reinforce(g, so.id, missing)) { sfx('coin'); s.commit(); } else sfx('deny'); }}>
                      Refill {missing} <Icon name="silver" size={13} /> {rc * missing}
                    </button>
                  </Tip>
                )}
              </div>
            )}
          </div>
        )}
        <div className="row" style={{ justifyContent: 'space-between', marginTop: 12 }}>
          <span className="small muted">
            Served on {so.expeditions} expedition{so.expeditions === 1 ? '' : 's'}.
          </span>
          <div className="row">
            {!g.expedition && (
              <button
                className="btn ghost sm"
                onClick={() => {
                  if (confirm(`Discharge ${so.name} and the squad from the company?`)) {
                    dismiss(g, so.id);
                    s.openSoldier(null);
                    s.commit();
                  }
                }}
              >
                Discharge
              </button>
            )}
            <button className="btn" onClick={close}>
              Close
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
