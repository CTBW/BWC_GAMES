import { useState } from 'react';
import type { SupplyId } from '../../core/types';
import { campaignById, NODE_INFO } from '../../data/campaigns';
import { encounterById } from '../../data/encounters';
import { EVENTS } from '../../data/events';
import { INJURIES, SUPPLIES, SUPPLY_ORDER } from '../../data/items';
import { BATTLE_MAPS } from '../../data/maps';
import { UNIT_TYPES, squadSize } from '../../data/units';
import {
  armySoldiers,
  bandageHeal,
  campRepair,
  campRest,
  campWatch,
  choiceAvailable,
  chooseEvent,
  nextNodes,
  node,
  nodeView,
  rationCost,
  searchSpot,
  useBandage,
} from '../../campaign/expedition';
import { armyCommand, armyLimits } from '../../meta/game';
import { fatigueLabel, soldierStats, squadHpCap } from '../../meta/soldier';
import { squadName } from '../../battle/squad';
import { Bar, Icon, MenPips, Portrait, ResList, RosterSquadBar, Tip, TypeIcon } from '../common';
import { useStore } from '../store';
import { sfx } from '../../audio/sfx';
import { SoldierDetail } from './Roster';

export function Campaign() {
  const s = useStore();
  const g = s.game!;
  const ex = g.expedition;
  const [confirmRetreat, setConfirmRetreat] = useState(false);
  if (!ex) return null;
  const c = campaignById(ex.campaignId);
  const army = armySoldiers(g);
  const lim = armyLimits(g, c);
  const marching = s.campaignScene?.ui.marching ?? false;
  const hoverId = s.campaignScene?.ui.hover;
  const hover = hoverId ? node(ex, hoverId) : undefined;
  const next = nextNodes(ex);
  return (
    <div className="layer">
      <div className="topbar">
        <span className="brand">{c.name.toUpperCase()}</span>
        <span className="small" style={{ color: '#cdb88a' }}>
          March {ex.marches} · {node(ex, ex.current).name}
        </span>
        <span className="spacer" />
        {SUPPLY_ORDER.map((k) => (
          <Tip key={k} text={<><b>{SUPPLIES[k].name}</b><br />{SUPPLIES[k].description}{k === 'rations' && <div style={{ marginTop: 4 }}>Each march costs {rationCost(g)}.</div>}</>} wide>
            <span className="res" style={{ color: ex.supplies[k] === 0 ? '#ff9a86' : undefined }}>
              <Icon name={k} size={22} />
              {ex.supplies[k]}
            </span>
          </Tip>
        ))}
        <span className="spacer" />
        <button className="btn sm" onClick={() => s.openManual('campaign')}>?</button>
        <span className="small" style={{ color: '#cdb88a' }}>Spoils</span>
        <ResList res={ex.loot} size={18} />
      </div>

      {/* Army */}
      <div className="panel dark" style={{ position: 'absolute', left: 12, top: 66, width: 290, padding: '10px 10px', maxHeight: 'calc(100vh - 260px)', overflow: 'auto' }}>
        <div className="row" style={{ justifyContent: 'space-between', marginBottom: 6 }}>
          <span className="cinzel" style={{ fontWeight: 700 }}>The Army</span>
          <span className="tiny muted">
            {army.reduce((n, so) => n + so.men, 0)} soldiers · {army.length}/{lim.slots} slots · {armyCommand(g, ex.army)}/{lim.command} CP
          </span>
        </div>
        <div className="col" style={{ gap: 6 }}>
          {army.map((so) => {
            const st = soldierStats(so);
            const hurt = so.hp < squadHpCap(so);
            return (
              <div key={so.id} className="row" style={{ gap: 7, cursor: 'pointer' }} onClick={() => s.openSoldier(so.id)}>
                <Portrait typeId={so.typeId} variant={so.portrait} size={40} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div className="row" style={{ justifyContent: 'space-between', gap: 4 }}>
                    <span className="cinzel" style={{ fontSize: 12.5, fontWeight: 700, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }} title={`${so.name}'s ${UNIT_TYPES[so.typeId].plural.toLowerCase()}`}>{so.name}</span>
                    <span className="tiny" style={{ color: so.fatigue >= 60 ? '#ffb070' : '#b8a27c' }}>{fatigueLabel(so.fatigue)}</span>
                  </div>
                  <RosterSquadBar so={so} height={7} />
                  <div style={{ height: 2 }} />
                  <Bar value={so.morale} max={st.morale} kind="morale" height={5} label={`Morale ${so.morale}/${st.morale}`} />
                  <div className="row" style={{ gap: 4, marginTop: 3, flexWrap: 'wrap' }}>
                    <MenPips men={so.men} size={squadSize(so.typeId)} />
                    {so.injuries.map((i) => (
                      <span key={i} className="tag" style={{ fontSize: 9, color: '#ffb0a0' }}>{INJURIES[i].name}</span>
                    ))}
                    {UNIT_TYPES[so.typeId].shot?.ammo !== undefined && <span className="tiny muted">{so.ammo} bolts</span>}
                  </div>
                </div>
                {hurt && ex.supplies.bandages > 0 && !ex.pending && (
                  <Tip text={`Use a bandage on ${squadName(so)}: +10 HP per soldier (up to +${Math.min(bandageHeal(so), squadHpCap(so) - so.hp)} HP). Bandages heal the living; they cannot bring back the dead.`} wide>
                    <button
                      className="btn sm icon"
                      onClick={(e) => {
                        e.stopPropagation();
                        if (useBandage(g, so.id)) {
                          sfx('page');
                          s.commit();
                        }
                      }}
                    >
                      <Icon name="bandages" size={16} />
                    </button>
                  </Tip>
                )}
              </div>
            );
          })}
        </div>
      </div>

      {/* Hover info */}
      {hover && !ex.pending && (
        <NodeCard id={hover.id} reachable={next.some((n) => n.id === hover.id)} />
      )}
      {!ex.pending && !marching && !hover && (
        <div className="panel dark" style={{ position: 'absolute', left: '50%', top: 66, transform: 'translateX(-50%)', padding: '6px 16px', textAlign: 'center' }}>
          <span className="cinzel">Choose the next march</span>
          <span className="small muted"> · each march eats {rationCost(g)} rations and tires the army</span>
        </div>
      )}

      {/* Log */}
      <div className="panel dark scroll" style={{ position: 'absolute', left: 12, bottom: 14, width: 420, maxHeight: 150, padding: '8px 12px', fontSize: 13 }}>
        {ex.log.slice(0, 12).map((l, i) => (
          <div key={i} style={{ color: l.tone === 'bad' ? '#ffb0a0' : l.tone === 'good' ? '#c8eab0' : '#efe2c2', opacity: 1 - i * 0.06 }}>
            {l.text}
          </div>
        ))}
      </div>

      <div style={{ position: 'absolute', right: 16, bottom: 16, display: 'flex', gap: 10 }}>
        <button className="btn" onClick={() => s.campaignScene?.focusCurrent()}>
          Find army
        </button>
        <button className="btn primary" disabled={!!ex.pending || marching} onClick={() => setConfirmRetreat(true)}>
          Retreat home
        </button>
      </div>

      {confirmRetreat && (
        <div className="modal-back">
          <div className="panel dialog" style={{ width: 520 }}>
            <div className="title">Sound the retreat?</div>
            <p>The company turns for Amberfeld with the spoils gathered so far. The objective will not be met and the campaign's reward is forfeit.</p>
            <div className="row" style={{ justifyContent: 'center', gap: 12 }}>
              <button className="btn" onClick={() => setConfirmRetreat(false)}>Press on</button>
              <button className="btn primary" onClick={() => s.goHome('retreat')}>Retreat</button>
            </div>
          </div>
        </div>
      )}

      {ex.pending && !marching && <PendingDialog />}
      {s.soldier && <SoldierDetail key={s.soldier} id={s.soldier} />}
    </div>
  );
}

function NodeCard({ id, reachable }: { id: string; reachable: boolean }) {
  const s = useStore();
  const ex = s.game!.expedition!;
  const n = node(ex, id);
  const v = nodeView(n);
  const roll = n.encounter;
  return (
    <div className="panel" style={{ position: 'absolute', right: 16, top: 70, width: 300, padding: '12px 14px' }}>
      <div className="cinzel" style={{ fontWeight: 700, fontSize: 18 }}>{v.title}</div>
      <div className="small muted">{v.type === 'unknown' ? 'Unknown' : NODE_INFO[v.type].name}{n.visited ? ' · visited' : ''}</div>
      <div className="flourish" />
      <div className="small">{v.detail}</div>
      {roll && (n.scouted || n.type === 'objective') && (
        <div className="small" style={{ marginTop: 6 }}>
          <b>Ground:</b> {BATTLE_MAPS[roll.mapId].name}
        </div>
      )}
      {v.type === 'event' && n.revealed && n.type === 'event' && n.eventId && n.scouted && (
        <div className="small" style={{ marginTop: 6 }}>Scouts report: {EVENTS.find((e) => e.id === n.eventId)?.title}</div>
      )}
      {reachable ? <div className="small" style={{ marginTop: 8, color: '#6b4a10' }}>Click to march here.</div> : !n.visited && <div className="small muted" style={{ marginTop: 8 }}>Not reachable from here.</div>}
    </div>
  );
}

function PendingDialog() {
  const s = useStore();
  const g = s.game!;
  const ex = g.expedition!;
  const p = ex.pending!;
  if (p.kind === 'arrive' || p.kind === 'scout') {
    const n = node(ex, p.nodeId);
    return (
      <div className="modal-back">
        <div className="panel dialog" style={{ width: 560 }}>
          <div className="title">{n.name}</div>
          <p>
            {p.kind === 'scout'
              ? 'From the high ground the scouts can see for miles: the roads ahead, the bands of the host moving along them, and far to the west the smoke of the host itself. The next stretch of the march is revealed in detail.'
              : 'The company arrives.'}
          </p>
          <div className="row" style={{ justifyContent: 'center' }}>
            <button className="btn primary" onClick={() => s.dismiss()}>Continue</button>
          </div>
        </div>
      </div>
    );
  }
  if (p.kind === 'event') {
    const ev = EVENTS.find((e) => e.id === p.eventId)!;
    const subject = armySoldiers(g).find((so) => so.id === p.subject)?.name ?? armySoldiers(g)[0]?.name ?? 'A soldier';
    return (
      <div className="modal-back">
        <div className="panel dialog">
          <div className="title">{ev.title}</div>
          <p style={{ fontStyle: 'italic' }}>{ev.text.replaceAll('{name}', subject)}</p>
          <div className="flourish" />
          {!p.result &&
            ev.choices.map((ch, i) => {
              const ok = choiceAvailable(g, ch);
              return (
                <button
                  key={i}
                  className="choice"
                  disabled={!ok.ok}
                  onClick={() => {
                    chooseEvent(g, i);
                    sfx('page');
                    s.commit();
                  }}
                >
                  {ch.label}
                  {ch.hint && <span className="hint">({ch.hint})</span>}
                  {!ok.ok && <span className="hint" style={{ color: '#a3261c' }}>— {ok.reason}</span>}
                </button>
              );
            })}
          {p.result && (
            <>
              <p>{p.result.text}</p>
              <div className="row" style={{ flexWrap: 'wrap', gap: 6, justifyContent: 'center' }}>
                {p.result.changes.map((c, i) => (
                  <span key={i} className={`tag ${c.startsWith('-') ? 'red' : c.startsWith('+') ? 'green' : 'gold'}`}>{c}</span>
                ))}
              </div>
              <div className="row" style={{ justifyContent: 'center', marginTop: 12 }}>
                <button className="btn primary" onClick={() => s.dismiss()}>
                  {p.followBattle ? 'To arms!' : 'Continue'}
                </button>
              </div>
            </>
          )}
        </div>
      </div>
    );
  }
  if (p.kind === 'battle') {
    const enc = encounterById(p.roll.encounterId);
    const n = node(ex, p.nodeId);
    const counts: Record<string, number> = {};
    for (const e of p.roll.enemies) counts[e.typeId] = (counts[e.typeId] ?? 0) + 1;
    return (
      <div className="modal-back">
        <div className="panel dialog" style={{ width: 620 }}>
          <div className="title">{p.surprise ? 'Ambush!' : p.objective ? 'The Last Stand' : enc.kind === 'stand' ? 'A Stand' : 'Battle'}</div>
          <p style={{ textAlign: 'center', marginTop: -4 }} className="cinzel">
            {p.title}
          </p>
          <p>
            {p.night
              ? ex.supplies.torches > 0
                ? 'Goblins rush the camp in the dark! The sentries light torches so the crossbows can see.'
                : 'Goblins rush the camp in the dark, and there are no torches left. Crossbows will be nearly blind.'
              : p.surprise
              ? 'They strike first, from more than one side. Form up where you stand!'
              : p.objective
                ? 'Night falls over Brannsted. Torches beyond counting are coming down the western road: the whole host, and its warchief. The steading has a palisade, two gates and a breach by the old tower. Hold it until dawn.'
                : `${enc.name} hold ${n.name}. There is no going around.`}
          </p>
          <div className="card">
            <div className="small" style={{ marginBottom: 4 }}><b>Enemy</b></div>
            <div className="row" style={{ flexWrap: 'wrap', gap: 6 }}>
              {Object.entries(counts).map(([t, k]) => (
                <span key={t} className="tag red">
                  <TypeIcon typeId={t} size={13} /> {k} × {k === 1 ? UNIT_TYPES[t].name : UNIT_TYPES[t].plural}
                </span>
              ))}
            </div>
            {(p.roll.waves ?? []).length > 0 && (
              <div className="small" style={{ marginTop: 6 }}>
                <b>{(p.roll.waves ?? []).some((w) => w.horn) ? 'If the horn sounds:' : 'Then, in waves:'}</b>{' '}
                {(p.roll.waves ?? []).reduce((n, w) => n + w.units.length, 0)} more squads
                {(p.roll.waves ?? []).some((w) => w.units.some((u) => u.warchief)) ? ', and the warchief himself' : ''}.
              </div>
            )}
            {enc.goal && (
              <div className="small" style={{ marginTop: 6 }}>
                <b>{enc.goal.title}.</b> {enc.goal.brief}
              </div>
            )}
            <div className="small" style={{ marginTop: 6 }}>
              <b>Ground:</b> {BATTLE_MAPS[p.roll.mapId].name}. {BATTLE_MAPS[p.roll.mapId].description}
            </div>
          </div>
          <div className="row" style={{ justifyContent: 'center', marginTop: 14 }}>
            <button className="btn big primary" onClick={() => s.startBattle()}>
              To Battle
            </button>
          </div>
        </div>
      </div>
    );
  }
  if (p.kind === 'battleResult') {
    const r = p.report;
    const title = r.result === 'victory' ? 'Victory' : r.result === 'retreat' ? 'Withdrawal' : 'Defeat';
    const losses = r.losses;
    const lostMen = (losses ?? []).reduce((n, l) => n + l.lost, 0);
    const gone = (losses ?? []).filter((l) => l.fate === 'dead').length;
    return (
      <div className="modal-back">
        <div className="panel dialog" style={{ width: 640 }}>
          <div className="title" style={{ fontSize: 30, color: r.result === 'victory' ? '#2d5a1a' : '#8a1f15' }}>{title}</div>
          <p style={{ textAlign: 'center', marginTop: -6 }} className="cinzel">{r.title}</p>
          <div className="grid2">
            <div className="card">
              <div className="small">
                <b>Foes</b>: {r.enemiesKilled} {r.enemiesKilled === 1 ? 'squad' : 'squads'} destroyed, {r.enemiesFled} fled
                {r.enemySoldiersSlain !== undefined && <span className="muted"> · {r.enemySoldiersSlain} soldiers slain</span>}
              </div>
              <div className="small row" style={{ gap: 6 }}><b>Spoils:</b> <ResList res={r.loot} size={15} /></div>
              {r.bandagesUsed > 0 && <div className="small">{r.bandagesUsed} bandage(s) used on the wounded</div>}
              {r.boltsUsed > 0 && <div className="small">{r.boltsUsed} bolts loosed</div>}
            </div>
            <div className="card">
              {losses ? (
                <div className="small" style={{ color: lostMen ? '#8a1f15' : undefined }}>
                  {lostMen ? <><b>{lostMen}</b> {lostMen === 1 ? 'soldier' : 'soldiers'} lost{gone ? `, ${gone} ${gone === 1 ? 'squad' : 'squads'} destroyed` : ''}.</> : 'Not a soldier was lost.'}
                </div>
              ) : r.fallen.length > 0 ? (
                <div className="small" style={{ color: '#8a1f15' }}>
                  <b>Fallen:</b> {r.fallen.map((f) => f.name).join(', ')}
                </div>
              ) : (
                <div className="small">No one was lost.</div>
              )}
              {!losses && r.wounded.map((w) => (
                <div key={w.name} className="small"><b>{w.name}</b> survived: {w.injury}</div>
              ))}
              {r.routed.length > 0 && <div className="small">Fled the field: {r.routed.join(', ')}</div>}
            </div>
          </div>
          {losses && losses.length > 0 && (
            <div className="card losses col" style={{ marginTop: 8, gap: 3 }}>
              {losses.map((l) => {
                const injury = r.wounded.find((w) => w.name === l.name)?.injury;
                return (
                  <div key={l.name} className="small" style={{ color: l.fate === 'fought' ? undefined : '#8a1f15' }}>
                    <span>
                      <b>{squadName(l)}</b>:{' '}
                      {l.fate === 'dead'
                        ? `wiped out with their sergeant (${l.lost} lost).`
                        : l.fate === 'downed'
                          ? `cut down to the last man; ${l.name.split(' ')[0]} lives${injury ? ` (${injury.toLowerCase()})` : ''}. ${l.lost} lost.`
                          : l.lost
                            ? `lost ${l.lost} ${l.lost === 1 ? 'man' : 'men'}, ${l.men}/${l.size} remain.`
                            : `no one lost, ${l.men}/${l.size} remain.`}
                      {l.saved ? <span className="muted"> {l.saved} of the fallen {l.saved === 1 ? 'was' : 'were'} found alive and carried back, badly hurt.</span> : null}
                    </span>
                    <MenPips men={l.men} size={l.size} count={false} />
                  </div>
                );
              })}
            </div>
          )}
          {r.levelUps.length > 0 && (
            <div className="card" style={{ marginTop: 8 }}>
              {r.levelUps.map((l) => (
                <div key={l} className="small" style={{ color: '#6b4a10' }}>★ {l}</div>
              ))}
            </div>
          )}
          <div className="small muted" style={{ marginTop: 6 }}>
            Experience: {r.xp.map((x) => `${x.name.split(' ')[0]} +${x.xp}`).join(' · ')}
          </div>
          <div className="row" style={{ justifyContent: 'center', marginTop: 12 }}>
            <button className="btn primary" onClick={() => s.dismiss()}>
              {r.result === 'defeat' ? 'Retreat home' : 'Continue'}
            </button>
          </div>
        </div>
      </div>
    );
  }
  if (p.kind === 'camp') {
    const done = p.done;
    const army = armySoldiers(g);
    return (
      <div className="modal-back">
        <div className="panel dialog" style={{ width: 640 }}>
          <div className="title">{node(ex, p.nodeId).name}</div>
          <p>A sheltered hollow with water and dry wood. Night is falling. What will the company do?</p>
          <div className="col">
            <button className="choice" disabled={done.includes('watch') || ex.supplies.torches < 1} onClick={() => { campWatch(g); sfx('page'); s.commit(); }}>
              Light torches and set a watch <span className="hint">(-1 torch: no night raid)</span>
            </button>
            <button className="choice" disabled={done.includes('repair') || ex.supplies.tools < 1} onClick={() => { campRepair(g); sfx('build'); s.commit(); }}>
              Mend armour and kit <span className="hint">(-1 tools: +40% armour condition)</span>
            </button>
            <button className="choice" disabled={done.includes('rest')} onClick={() => { campRest(g); sfx('page'); s.commit(); }}>
              Eat a hot meal and sleep <span className="hint">(-{army.length} rations: heal the living, recover morale and fatigue)</span>
            </button>
          </div>
          {p.messages.map((m, i) => (
            <p key={i} className="small" style={{ margin: '6px 0' }}>{m}</p>
          ))}
          <div className="row" style={{ justifyContent: 'center', marginTop: 10 }}>
            <button className="btn primary" onClick={() => s.dismiss()}>Break camp</button>
          </div>
        </div>
      </div>
    );
  }
  if (p.kind === 'village') {
    return (
      <div className="modal-back">
        <div className="panel dialog" style={{ width: 620 }}>
          <div className="title">{node(ex, p.nodeId).name}</div>
          <p>The village is empty. Doors hang open; the raiders were thorough, but not everything was found.</p>
          <div className="col">
            {p.spots.map((sp, i) => (
              <button
                key={i}
                className="choice"
                disabled={sp.searched || (sp.locked && ex.supplies.tools < 1)}
                onClick={() => {
                  searchSpot(g, i);
                  sfx('page');
                  s.commit();
                }}
              >
                Search {sp.label.toLowerCase()} {sp.locked && <span className="hint">(needs 1 tools)</span>} {sp.searched && <span className="hint">(searched)</span>}
              </button>
            ))}
          </div>
          {p.messages.map((m, i) => (
            <p key={i} className="small" style={{ margin: '6px 0' }}>{m}</p>
          ))}
          <div className="row" style={{ justifyContent: 'center', marginTop: 10 }}>
            <button className="btn primary" onClick={() => s.dismiss()}>Move on</button>
          </div>
        </div>
      </div>
    );
  }
  if (p.kind === 'complete') {
    return (
      <div className="modal-back">
        <div className="panel dialog" style={{ width: 560, textAlign: 'center' }}>
          <div className="title" style={{ fontSize: 30, color: '#2d5a1a' }}>Objective Complete</div>
          <p>Brannsted held. When the sun came up the Margrave's riders came over the hill, and the host broke against them and ran for the woods. The country west of the Vattern is saved, for now, by the Amberfeld Company.</p>
          <p className="small">Spoils: <ResList res={ex.loot} /></p>
          <button className="btn big primary" onClick={() => s.goHome('success')}>
            Return to Amberfeld
          </button>
        </div>
      </div>
    );
  }
  return null;
}

export type { SupplyId };
