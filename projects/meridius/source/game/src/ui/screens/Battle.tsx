import { useState } from 'react';
import { setPref } from '../../core/prefs';
import type { Dir, StatusId } from '../../core/types';
import { ABILITIES, isActiveAbility } from '../../data/abilities';
import { PROPS, TERRAIN } from '../../data/terrain';
import { UNIT_TYPES } from '../../data/units';
import { tileAt } from '../../battle/grid';
import type { BattleUnit } from '../../battle/types';
import { memberNoun, squadName } from '../../battle/squad';
import { rankName } from '../../meta/soldier';
import { Bar, Icon, MenPips, Portrait, SquadBar, Tip, TypeIcon, squadTypeLabel } from '../common';
import { useStore } from '../store';

const MORALE_LABEL: Record<string, string> = {
  confident: 'Confident',
  steady: 'Steady',
  shaken: 'Shaken',
  wavering: 'Wavering',
  broken: 'Broken',
};

const STATUS_INFO: Record<StatusId, { name: string; color: string; text: string }> = {
  chilled: { name: 'Chilled', color: '#bfe6ff', text: 'Half movement, −10 to hit and −10 defense until the end of its turn.' },
  bloodlust: { name: 'Bloodlust', color: '#ff8a6a', text: '+10 to hit and +3 damage per soldier in melee, morale losses halved, −8 defense.' },
  bleeding: { name: 'Bleeding', color: '#ff9a8a', text: 'Loses HP (and soldiers) at the start of each of its turns.' },
};

/** Chips for a squad's lasting conditions (chilled, frenzied, bleeding), with what each does. */
function StatusChips({ u }: { u: BattleUnit }) {
  if (!u.statuses.length) return null;
  return (
    <span className="row" style={{ gap: 4, flexWrap: 'wrap' }}>
      {u.statuses.map((s) => (
        <Tip key={s.id} text={<><b>{STATUS_INFO[s.id].name}</b>{s.id === 'bleeding' && s.power ? ` (−${s.power} a turn, ${s.turns} more)` : ''}<br />{STATUS_INFO[s.id].text}</>}>
          <span className="tag" style={{ background: 'rgba(15,10,6,0.75)', color: STATUS_INFO[s.id].color, fontSize: 10 }}>{STATUS_INFO[s.id].name}</span>
        </Tip>
      ))}
    </span>
  );
}

/** What the squad's missile weapon is called: crossbow bolts, arcane bolts, hexes, a ballista's bolt. */
function shotName(u: BattleUnit): string {
  if (u.typeId === 'battle_mage') return 'Arcane bolt';
  if (u.typeId === 'goblin_shaman') return 'Hex bolt';
  if (u.typeId === 'ballista') return 'Bolt';
  return 'Shot';
}

export function BattleHud() {
  const s = useStore();
  const scene = s.battleScene;
  const [confirmRetreat, setConfirmRetreat] = useState(false);
  if (!scene) return null;
  const b = scene.b;
  const ui = scene.ui;
  const sel = ui.selected ? b.unit(ui.selected) : undefined;
  const hoverUnit = ui.hover.unit ? b.unit(ui.hover.unit) : undefined;
  const players = b.units.filter((u) => u.faction === 'player');
  const enemies = b.units.filter((u) => u.faction === 'enemy');
  // Counted from what has been shown, so the tally drops as each enemy visibly falls.
  const enemyLeft = enemies.filter((u) => {
    const v = scene.views.get(u.uid);
    return v ? !v.reserve && v.status === 'active' && !v.routing : u.status === 'active';
  }).length;
  // Squads still beyond the edges in waves that will come (a silenced horn calls nobody).
  const coming = b.waves.reduce((n, w, i) => (b.waveState[i] === 'cancelled' || (w.horn && b.horn === 'silent') ? n : n + w.uids.filter((id) => scene.views.get(id)?.reserve).length), 0);
  const myTurn = b.phase === 'player' && !ui.busy;
  const ready = b.active('player').filter((u) => !u.done && (!u.hasMoved || !u.hasActed)).length;
  const fast = (scene.speed ?? 1) > 1;
  return (
    <div className="layer">
      {/* Top strip */}
      <div className="topbar" style={{ height: 50 }}>
        <span className="brand" style={{ fontSize: 17 }}>{s.battleInfo?.title ?? b.setup.title}</span>
        <span className="small" style={{ color: '#cdb88a' }}>
          {b.phase === 'deploy' ? 'Deployment' : b.phase === 'over' && !ui.busy ? `Turn ${ui.turn} · Battle over` : `Turn ${ui.turn} · ${ui.side === 'player' ? 'Your move' : 'Enemy move'}`} · {b.map.name}
          {b.setup.darkness ? ' · Night' : ''}
        </span>
        <span className="spacer" />
        <span className="small" style={{ color: '#ffb0a0', whiteSpace: 'nowrap' }} title="Enemy squads on the field, and squads still coming in waves">
          Enemy squads: {enemyLeft} on the field{coming > 0 ? ` · ${coming} coming` : ''}
        </span>
        <Tip text="Toggle grid (G)">
          <button className={`btn sm icon ${ui.showGrid ? 'active' : ''}`} onClick={() => { ui.showGrid = !ui.showGrid; scene.notify(); }}>
            <span style={{ color: '#f0e2c0', display: 'inline-flex' }}><Icon name="grid" /></span>
          </button>
        </Tip>
        <Tip text="Show where enemies can strike next turn (hold Alt)">
          <button className={`btn sm icon ${ui.danger ? 'active' : ''}`} onClick={() => { ui.danger = !ui.danger; scene.notify(); }}>
            <span style={{ color: '#f0e2c0', display: 'inline-flex' }}><Icon name="danger" /></span>
          </button>
        </Tip>
        <Tip text="Battle speed">
          <button
            className={`btn sm ${fast ? 'active' : ''}`}
            onClick={() => {
              scene.speed = fast ? 1 : 2;
              setPref('battleSpeed', scene.speed);
              scene.notify();
            }}
          >
            {fast ? '2×' : '1×'}
          </button>
        </Tip>
        <Tip text="Field manual">
          <button className="btn sm" onClick={() => s.openManual('battle')}>?</button>
        </Tip>
        {b.phase !== 'deploy' && (
          <button className="btn sm" disabled={!myTurn} onClick={() => setConfirmRetreat(true)}>
            Retreat
          </button>
        )}
        {b.phase === 'deploy' ? (
          <button className="btn primary" onClick={() => scene.begin()}>
            Begin Battle
          </button>
        ) : (
          <button className={`btn primary ${myTurn && ready === 0 ? 'pulse' : ''}`} disabled={!myTurn} onClick={() => scene.endTurn()}>
            End Turn{ready > 0 && myTurn ? ` (${ready} ready)` : ''} <kbd>Enter</kbd>
          </button>
        )}
      </div>

      <ObjectivePanel />

      {/* Company list */}
      <div className="company">
        {players.map((u) => (
          <MiniCard key={u.uid} u={u} selected={ui.selected === u.uid} onClick={() => scene.select(u.uid)} done={b.phase === 'player' && u.done} />
        ))}
      </div>

      {/* Banner */}
      {ui.banner && (
        <div key={ui.banner.id} className={`banner ${ui.banner.tone}`}>
          <div className="rule" />
          <h1>{ui.banner.text}</h1>
          <div className="rule" />
          {ui.banner.sub && <div className="sub">{ui.banner.sub}</div>}
        </div>
      )}

      {/* Forecast / hover info */}
      {ui.hover.spell && sel ? (
        <SpellForecast />
      ) : ui.hover.preview && sel ? (
        <Forecast />
      ) : hoverUnit ? (
        <UnitInfo u={hoverUnit} />
      ) : ui.hover.tile ? (
        <TileInfo />
      ) : null}

      {/* Selected unit */}
      {sel && sel.status === 'active' && b.phase !== 'over' && <UnitPanel u={sel} />}

      {/* Log */}
      <div className="panel dark logbox scroll">
        {ui.log.slice(0, 14).map((l, i) => (
          <div key={i} className={l.tone} style={{ opacity: 1 - i * 0.05 }}>
            {l.text}
          </div>
        ))}
        {!ui.log.length && <div className="muted">Hold the line. Mind the flanks.</div>}
      </div>

      {confirmRetreat && (
        <div className="modal-back">
          <div className="panel dialog" style={{ width: 520 }}>
            <div className="title">Withdraw from the field?</div>
            <p>Soldiers locked in melee take a parting blow as they pull back. The wounded are carried off. The enemy keeps the field, and you collect no spoils from it.</p>
            <div className="row" style={{ justifyContent: 'center', gap: 12 }}>
              <button className="btn" onClick={() => setConfirmRetreat(false)}>Fight on</button>
              <button className="btn primary" onClick={() => { setConfirmRetreat(false); scene.retreat(); }}>Withdraw</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

/**
 * What wins and loses this battle, how long until relief, the next wave and
 * the war horn: the facts a player needs every turn, at the top of the screen.
 */
function ObjectivePanel() {
  const s = useStore();
  const scene = s.battleScene!;
  const b = scene.b;
  const o = b.objective;
  const ui = scene.ui;
  const lines: { text: string; tone?: 'bad' | 'good' | 'warn' }[] = [];
  if ((o.kind === 'survive' || o.kind === 'hold') && o.turns) {
    const left = o.turns - ui.turn;
    lines.push({ text: left <= 0 ? 'Hold this one last turn!' : `Turn ${ui.turn} of ${o.turns} · ${left} more ${left === 1 ? 'turn' : 'turns'} after this`, tone: left <= 1 ? 'good' : undefined });
  }
  if (o.kind === 'hold' && b.map.zoneName) lines.push({ text: `Keep the enemy out of ${b.map.zoneName.toLowerCase()} (gold line)` });
  if (o.warchief) {
    const chief = b.units.find((u) => u.tags.includes('warchief'));
    const v = chief ? scene.views.get(chief.uid) : undefined;
    if (chief && v && !v.reserve && chief.status === 'active') lines.push({ text: `The warchief is on the field: slay ${chief.name.split(',')[0]} to break the horde`, tone: 'warn' });
    else if (chief && chief.status === 'reserve') lines.push({ text: 'Slay the warchief when he comes to break the horde' });
  }
  if (o.hornTurn !== undefined && b.horn === 'waiting' && b.waves.some((w) => w.horn)) {
    const left = o.hornTurn - ui.turn;
    lines.push({ text: left <= 0 ? 'The horn-bearer sounds his horn this enemy turn unless he falls!' : `The horn-bearer sounds his horn in ${left} ${left === 1 ? 'turn' : 'turns'}: kill him first`, tone: 'bad' });
  }
  if (b.horn === 'silent' && b.waves.some((w) => w.horn)) lines.push({ text: 'The horn is silenced', tone: 'good' });
  const next = scene.nextWaveInfo();
  if (next) {
    const when = next.dueIn <= 0 ? 'at the end of this turn' : next.dueIn === 1 ? 'next turn' : `in ${next.dueIn} turns`;
    lines.push({ text: `${next.total > 1 ? `Wave ${next.index} of ${next.total}` : 'Reinforcements'}: ${next.count} squads from the ${next.edge} edge ${when}`, tone: next.dueIn <= 1 ? 'bad' : undefined });
  }
  return (
    <div className="panel dark objective">
      <div className="cinzel" style={{ fontWeight: 700, color: '#f6e7c2', fontSize: 15 }}>{o.title}</div>
      {b.phase === 'deploy' && <div className="small" style={{ color: '#e9dcc0', marginTop: 2 }}>{o.brief}</div>}
      {lines.map((l, i) => (
        <div key={i} className="tiny" style={{ color: l.tone === 'bad' ? '#ffb0a0' : l.tone === 'good' ? '#a8e89a' : l.tone === 'warn' ? '#ffd76a' : '#d8c8a4', marginTop: 2 }}>
          {l.text}
        </div>
      ))}
    </div>
  );
}

function MiniCard({ u, selected, onClick, done }: { u: BattleUnit; selected: boolean; onClick: () => void; done: boolean }) {
  const s = useStore();
  const v = s.battleScene!.views.get(u.uid)!;
  // Status as played back so far (the rules run ahead of the animation).
  const st = v.status ?? u.status;
  const gone = st === 'dead' || st === 'downed' || st === 'fled';
  return (
    <div
      className={`panel dark mini ${done ? 'done' : ''}`}
      onClick={gone ? undefined : onClick}
      style={{ outline: selected ? '2px solid #ffd76a' : undefined, opacity: gone ? 0.5 : undefined }}
      title={`${squadName(u)}: ${v.alive}/${u.size} standing, ${Math.max(0, Math.round(v.hp))}/${u.maxHp} HP`}
    >
      <Portrait typeId={u.typeId} variant={u.variant} size={36} dead={st === 'dead'} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div className="row" style={{ justifyContent: 'space-between', gap: 4 }}>
          <span className="cinzel" style={{ fontSize: 12, fontWeight: 700, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', color: '#f0e2c0' }}>{u.name.split(/[ ,]/)[0]}</span>
          <span className="tiny" style={{ color: v.routing || st === 'routing' ? '#ff9a86' : '#b8a27c', whiteSpace: 'nowrap' }}>
            {st === 'dead' ? 'Slain' : st === 'downed' ? 'Cut down' : st === 'fled' ? 'Fled' : v.routing || st === 'routing' ? 'Fleeing' : u.stance ? ABILITIES[u.stance]?.name ?? '' : v.statuses.length ? STATUS_INFO[v.statuses[0]].name : done ? 'Done' : ''}
          </span>
        </div>
        <SquadBar hp={v.hp} hpPer={u.hpPer} size={u.size} alive={v.alive} height={7} />
        <div className="row" style={{ gap: 6, marginTop: 2 }}>
          <div style={{ flex: 1 }}>
            <Bar value={v.morale} max={u.maxMorale} kind="morale" height={4} />
          </div>
          <MenPips men={v.alive} size={u.size} />
        </div>
      </div>
    </div>
  );
}

function UnitPanel({ u }: { u: BattleUnit }) {
  const s = useStore();
  const scene = s.battleScene!;
  const b = scene.b;
  const v = scene.views.get(u.uid)!;
  const ms = b.moraleState(u);
  const myTurn = b.phase === 'player' && !scene.ui.busy;
  const abilities = u.abilities.filter(isActiveAbility);
  const n = Math.max(0, v.alive);
  const def = UNIT_TYPES[u.typeId];
  const caster = u.tags.includes('caster');
  const dmg = (r: [number, number]) => (
    <>
      {r[0]}–{r[1]} × {n} = <b>{r[0] * n}–{r[1] * n}</b>
    </>
  );
  return (
    <div className="panel unitpanel">
      <Portrait typeId={u.typeId} variant={u.variant} size={92} />
      <div style={{ width: 252 }}>
        <div className="cinzel" style={{ fontWeight: 700, fontSize: 16, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{u.name}</div>
        <div className="small row" style={{ gap: 4, justifyContent: 'space-between' }}>
          <span className="row" style={{ gap: 4, whiteSpace: 'nowrap' }}>
            <TypeIcon typeId={u.typeId} size={14} /> {squadTypeLabel(u.typeId, u.level, true)}
          </span>
          <span className="row" style={{ gap: 3 }}><Icon name="morale" size={14} /> {MORALE_LABEL[ms]}</span>
        </div>
        <div className="small row" style={{ justifyContent: 'space-between', marginTop: 3 }}>
          <span className="row" style={{ gap: 5 }}>
            {def.crew ? 'Crew' : caster ? 'Casters' : 'Soldiers'} <MenPips men={n} size={u.size} />
          </span>
          <span className="row" style={{ gap: 3 }} title={`${u.hpPer} HP per soldier`}>
            <Icon name="hp" size={14} /> {Math.max(0, Math.round(v.hp))}/{u.maxHp}
          </span>
        </div>
        <SquadBar hp={v.hp} hpPer={u.hpPer} size={u.size} alive={n} />
        <div style={{ height: 3 }} />
        <Bar value={v.morale} max={u.maxMorale} kind="morale" height={6} />
        <div className="tiny" style={{ marginTop: 5 }} title="Per soldier × soldiers standing = squad damage, before armour">
          {u.shot && <div>{shotName(u)} {dmg(u.shot.damage)}{u.ammo >= 0 && ` · Bolts ${u.ammo}`}</div>}
          {def.primary && ABILITIES[def.primary].power && <div>{ABILITIES[def.primary].name} {dmg(ABILITIES[def.primary].power!)}</div>}
          <div>{u.shot || def.primary ? 'Melee' : 'Damage'} {dmg(u.melee)}</div>
        </div>
        <div className="tiny">
          Melee {u.stats.melee}{(u.shot || def.primary) && ` · ${caster ? 'Spell' : def.crew ? 'Crew' : 'Ranged'} ${u.stats.ranged}`} · Def {u.stats.defense}
          {u.shieldFront ? ` (+${u.shieldFront} shield)` : ''} · Armour {u.stats.armor.toFixed(1)} · Move {u.stats.move}
        </div>
        <StatusChips u={u} />
      </div>
      <div className="col" style={{ gap: 6, justifyContent: 'center', maxWidth: 210 }}>
        <div className="row" style={{ gap: 6, flexWrap: 'wrap' }}>
          <span className={`tag ${u.hasMoved ? '' : 'blue'}`}>{u.hasMoved ? 'Moved' : 'Can move'}</span>
          <span className={`tag ${u.hasActed ? '' : 'red'}`}>{u.hasActed ? 'Acted' : 'Can act'}</span>
          {u.hasMoved && b.phase === 'player' && <RedoButton u={u} />}
        </div>
        <div className="row" style={{ gap: 6 }}>
          {abilities.map((a, i) => {
            const ab = ABILITIES[a];
            const cd = u.cooldowns[a] ?? 0;
            const cast = ab.kind === 'spell' ? b.canCast(u, a) : undefined;
            const disabled = !myTurn || u.hasActed || cd > 0 || (cast ? !cast.ok : ms === 'wavering') || (ab.ammoCost !== undefined && u.ammo >= 0 && u.ammo < ab.ammoCost) || (a === 'overwatch' && u.ammo === 0);
            const why = cast && !cast.ok && myTurn && !u.hasActed && cd === 0 ? cast.reason : ms === 'wavering' && !cast ? 'Too shaken to use abilities.' : undefined;
            return (
              <Tip key={a} text={<><b>{ab.name}</b> <span className="muted">[{i + 1}]</span>{ab.cooldown && ab.cooldown > 1 ? <span className="muted"> · every {ab.cooldown === 2 ? 'other turn' : `${ab.cooldown} turns`}</span> : null}<br />{ab.description}{why && <div style={{ color: '#ffb0a0' }}>{why}</div>}{ab.kind === 'spell' && ab.target !== 'self' && <div className="muted" style={{ marginTop: 3 }}>Choose it, then click {ab.target === 'ally' ? 'a friendly squad' : ab.target === 'tile' ? 'a squad or a tile' : 'an enemy squad'}.</div>}</>} wide>
                <button className={`ability ${scene.ui.ability === a ? 'active' : ''}`} disabled={disabled} onClick={() => scene.setAbility(a)}>
                  <span className="key">{i + 1}</span>
                  <Icon name={ab.icon} size={26} />
                  {ab.name.split(' ')[0]}
                  {cd > 0 && <span className="cd">{cd}</span>}
                </button>
              </Tip>
            );
          })}
        </div>
      </div>
      <div className="col" style={{ gap: 6, justifyContent: 'center', alignItems: 'center' }}>
        <Tip text={<>A squad faces the way it last stepped. Choose the side it arrives from: point at an edge of the destination tile, or press <b>Q</b> / <b>E</b>. To turn on the spot, point at an edge of its own tile (it steps out and back).</>} wide>
          <div className="col" style={{ alignItems: 'center', gap: 2 }}>
            <div className="tiny muted">Facing</div>
            <FacingRose facing={v.facing} />
          </div>
        </Tip>
        <button className="btn sm" disabled={!myTurn} onClick={() => scene.endUnit()}>
          Done <kbd>Space</kbd>
        </button>
      </div>
    </div>
  );
}

function RedoButton({ u }: { u: BattleUnit }) {
  const s = useStore();
  const scene = s.battleScene!;
  const can = scene.b.canRedo(u.uid);
  const ok = can.ok && !scene.ui.busy;
  return (
    <Tip text={can.ok ? 'Walk this squad back to where it started the turn and move again. Only before attacking. (Backspace)' : can.reason} wide>
      <button className="btn sm gold" disabled={!ok} onClick={() => scene.redo(u.uid)}>
        ↶ Redo move
      </button>
    </Tip>
  );
}

/** Screen arrows for the four grid facings: +x down-right, +y down-left, -x up-left, -y up-right. */
export const FACING_ARROW: Record<Dir, string> = { 0: '↘', 1: '↙', 2: '↖', 3: '↗' };

/** Read-only compass: the squad's facing, set only by its last step. */
function FacingRose({ facing }: { facing: Dir }) {
  const cells: { d: Dir; x: number; y: number }[] = [
    { d: 2, x: 0, y: 0 },
    { d: 3, x: 1, y: 0 },
    { d: 1, x: 0, y: 1 },
    { d: 0, x: 1, y: 1 },
  ];
  return (
    <div style={{ display: 'grid', gridTemplateColumns: '22px 22px', gap: 2 }}>
      {cells.map((c) => (
        <span
          key={c.d}
          style={{
            gridColumn: c.x + 1,
            gridRow: c.y + 1,
            textAlign: 'center',
            fontSize: 15,
            lineHeight: '20px',
            borderRadius: 4,
            color: c.d === facing ? '#2a1a08' : 'rgba(240,226,192,0.28)',
            background: c.d === facing ? '#ffd76a' : 'rgba(0,0,0,0.18)',
          }}
        >
          {FACING_ARROW[c.d]}
        </span>
      ))}
    </div>
  );
}

/** Heading for a squad: "Grukk's Goblin Spearmen", "Aldric Holm's Footmen", or a leader's own name. */
function squadTitle(u: BattleUnit): string {
  if (u.leader) return u.name.split(',')[0];
  const who = u.faction === 'player' ? u.name : u.name.split(/[ ,]/)[0];
  return `${who}'s ${UNIT_TYPES[u.typeId]?.plural ?? u.typeId}`;
}

function Forecast() {
  const s = useStore();
  const scene = s.battleScene!;
  const pv = scene.ui.hover.preview!;
  const target = scene.b.unit(pv.target);
  const attacker = scene.ui.selected ? scene.b.unit(scene.ui.selected) : undefined;
  const tv = scene.views.get(target.uid);
  const thp = Math.max(0, Math.round(tv?.hp ?? target.hp));
  const talive = tv?.alive ?? target.alive;
  const arcLabel = pv.arc === 'front' ? 'Frontal' : pv.arc === 'flank' ? 'Flank' : 'Rear';
  const [s0, s1] = pv.soldiers;
  return (
    <div className="panel forecast">
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <div style={{ minWidth: 0 }}>
          <div className="cinzel" style={{ fontWeight: 700 }}>{squadTitle(target)}</div>
          <div className="tiny muted row" style={{ gap: 6 }}>
            <MenPips men={talive} size={target.size} /> · {thp}/{target.maxHp} HP · {MORALE_LABEL[scene.b.moraleState(target)]}
          </div>
        </div>
        <Portrait typeId={target.typeId} variant={target.variant} size={44} />
      </div>
      <div className="flourish" />
      {!pv.legal ? (
        <div className="neg">{pv.reason}</div>
      ) : (
        <>
          <div className="row" style={{ justifyContent: 'space-between', alignItems: 'flex-end' }}>
            <div>
              <div className="tiny muted">{pv.ability ? ABILITIES[pv.ability].name : pv.moveFirst ? 'Move & attack' : 'Attack'} · {arcLabel}</div>
              <div className="big" style={{ color: pv.chance >= 70 ? '#2d5a1a' : pv.chance >= 45 ? '#6b4a10' : '#8a1f15' }}>{pv.chance}%</div>
            </div>
            <div style={{ textAlign: 'right' }}>
              <div className="tiny muted">Squad damage</div>
              <div className="cinzel" style={{ fontSize: 26, fontWeight: 900 }}>{pv.min}–{pv.max}</div>
            </div>
          </div>
          <div className="small row" style={{ justifyContent: 'space-between', marginTop: 4 }}>
            <span>{attacker ? `${pv.strikers} ${memberNoun(attacker.typeId, pv.strikers)} ${pv.strikers === 1 ? 'strikes' : 'strike'}` : `${pv.strikers} strike`}</span>
            <span className={s1 > 0 ? 'pos' : 'muted'}>
              {s1 <= 0 ? 'Slays none' : `Slays ${s0 === s1 ? s1 : `${s0}–${s1}`} ${memberNoun(target.typeId, s1)}`}
            </span>
          </div>
          <div className="small row" style={{ justifyContent: 'space-between', marginTop: 2 }}>
            <span title="Chance this attack destroys the whole squad">Destroy squad: <b>{Math.round(pv.kill * 100)}%</b></span>
            <span>Morale shock: <b>−{pv.moraleHit}</b></span>
          </div>
          <div className="mods">
            {pv.mods.map(([k, v]) => (
              <div key={k}>
                <span>{k}</span>
                <span className={v > 0 && k !== 'Melee skill' && k !== 'Ranged skill' ? 'pos' : v < 0 ? 'neg' : ''}>{v > 0 && k !== 'Melee skill' && k !== 'Ranged skill' ? `+${v}` : v}</span>
              </div>
            ))}
          </div>
          {pv.moveFirst && <ArrivalNote />}
          {pv.moveFirst && <div className="tiny muted" style={{ marginTop: 4 }}>Move the cursor around the target to choose the side you attack from; Q / E change the way you arrive.</div>}
          {target.tags.includes('firstStrike') && pv.arc === 'front' && pv.moveFirst && <div className="tiny neg" style={{ marginTop: 4 }}>Spearmen strike first at anyone charging their front.</div>}
        </>
      )}
    </div>
  );
}

/**
 * What a spell (or a war machine's stone) would do: its chance, and every
 * squad it would touch with the damage, the dead and the healing, friends
 * caught in a blast called out in orange.
 */
function SpellForecast() {
  const s = useStore();
  const scene = s.battleScene!;
  const b = scene.b;
  const pv = scene.ui.hover.spell!;
  const ab = ABILITIES[pv.ability];
  const caster = scene.ui.selected ? b.unit(scene.ui.selected) : undefined;
  const hostile = !!ab.power;
  const roleName = { main: '', splash: 'beside', chain: 'arc', aura: '' } as const;
  const friendly = pv.hits.filter((h) => h.ally && !h.heal && h.max > 0);
  return (
    <div className="panel forecast">
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <div style={{ minWidth: 0 }}>
          <div className="cinzel" style={{ fontWeight: 700 }}>{ab.name}</div>
          <div className="tiny muted">
            {caster ? `${pv.casters} ${memberNoun(caster.typeId, pv.casters)} ${ab.engine ? 'at the engine' : pv.casters === 1 ? 'casts' : 'cast'}` : ''}
            {ab.power ? ` · ${ab.power[0]}–${ab.power[1]} each` : ab.heal ? ` · heals ${ab.heal[0]}–${ab.heal[1]} each` : ''}
          </div>
        </div>
        <Icon name={ab.icon} size={34} />
      </div>
      <div className="flourish" />
      {!pv.legal ? (
        <div className="neg">{pv.reason}</div>
      ) : (
        <>
          <div className="row" style={{ justifyContent: 'space-between', alignItems: 'flex-end' }}>
            <div>
              <div className="tiny muted">{hostile ? 'Strikes home' : 'Certain'}</div>
              <div className="big" style={{ color: pv.chance >= 70 ? '#2d5a1a' : pv.chance >= 45 ? '#6b4a10' : '#8a1f15' }}>{pv.chance}%</div>
            </div>
            {pv.scatter && <div className="tiny muted" style={{ maxWidth: 150, textAlign: 'right' }}>A miss lands one tile astray, and still strikes whoever stands there.</div>}
          </div>
          {pv.hits.length === 0 && <div className="small muted" style={{ marginTop: 4 }}>Nobody stands where it would land.</div>}
          <div style={{ marginTop: 4 }}>
            {pv.hits.map((h) => {
              const t = b.unit(h.uid);
              const tv = scene.views.get(t.uid);
              const own = h.ally && !h.heal && h.max > 0;
              const alive = tv?.alive ?? t.alive;
              return (
                <div key={h.uid} className="small row" style={{ justifyContent: 'space-between', gap: 8, color: own ? '#b4520e' : undefined }} title={`${squadName(t)}: ${alive}/${t.size} standing`}>
                  <span style={{ minWidth: 0, flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {roleName[h.role] && <span className="muted">{roleName[h.role]}: </span>}
                    {squadName(t)}
                  </span>
                  <span style={{ whiteSpace: 'nowrap', flex: 'none' }}>
                    {h.heal ? (
                      <b className="pos">+{h.min}–{h.max}</b>
                    ) : h.max > 0 ? (
                      <>
                        <b>{h.min}–{h.max}</b>
                        {h.soldiers[1] > 0 && <span className={own ? '' : 'pos'}> · slays {h.soldiers[0] === h.soldiers[1] ? h.soldiers[1] : `${h.soldiers[0]}–${h.soldiers[1]}`}</span>}
                      </>
                    ) : (
                      <span className="muted">{ab.status ? STATUS_INFO[ab.status.id].name : '—'}</span>
                    )}
                  </span>
                </div>
              );
            })}
          </div>
          {friendly.length > 0 && <div className="tiny" style={{ marginTop: 4, color: '#b4520e' }}>Your own {friendly.length === 1 ? 'squad stands' : 'squads stand'} in the blast!</div>}
          {ab.status && hostile && <div className="tiny" style={{ marginTop: 4 }}>Everyone struck is {STATUS_INFO[ab.status.id].name.toLowerCase()}: {STATUS_INFO[ab.status.id].text}</div>}
          {ab.bleed && <div className="tiny" style={{ marginTop: 4 }}>The wound bleeds for {Math.round(ab.bleed * 100)}% of the damage at the start of its next two turns.</div>}
          {pv.mods.length > 0 && (
            <div className="mods">
              {pv.mods.map(([k, v]) => (
                <div key={k}>
                  <span>{k}</span>
                  <span className={v > 0 && !k.endsWith('skill') ? 'pos' : v < 0 ? 'neg' : ''}>{v > 0 && !k.endsWith('skill') ? `+${v}` : v}</span>
                </div>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  );
}

/** Which way the squad will face after its move-and-strike, relative to its target. */
function ArrivalNote() {
  const s = useStore();
  const scene = s.battleScene!;
  const h = scene.ui.hover;
  const pv = h.preview;
  if (!pv || h.facing === undefined || !h.dest) return null;
  const t = scene.b.unit(pv.target);
  const arc = scene.b.arcOf({ ...t, x: h.dest.x, y: h.dest.y, facing: h.facing } as BattleUnit, t);
  const text = arc === 'front' ? 'facing the enemy' : arc === 'flank' ? 'side-on to the enemy: its next blows land in your flank' : 'with your back to the enemy';
  return (
    <div className={`tiny ${arc === 'front' ? '' : 'neg'}`} style={{ marginTop: 6 }}>
      Arrives {FACING_ARROW[h.facing]} {text}.
    </div>
  );
}

function UnitInfo({ u }: { u: BattleUnit }) {
  const s = useStore();
  const scene = s.battleScene!;
  const def = UNIT_TYPES[u.typeId];
  const v = scene.views.get(u.uid);
  const hp = Math.max(0, Math.round(v?.hp ?? u.hp));
  const alive = v?.alive ?? u.alive;
  const morale = v?.morale ?? u.morale;
  const per = (r: [number, number]) => `${r[0]}–${r[1]} × ${alive} = ${r[0] * alive}–${r[1] * alive}`;
  return (
    <div className="panel forecast">
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <div style={{ minWidth: 0 }}>
          <div className="cinzel" style={{ fontWeight: 700 }}>{squadTitle(u)}</div>
          <div className="tiny muted">{u.leader ? `${rankName(u.level)} ${def.name}` : squadTypeLabel(u.typeId, u.faction === 'player' ? u.level : undefined)} · {def.role}</div>
        </div>
        <Portrait typeId={u.typeId} variant={u.variant} size={44} />
      </div>
      <div className="flourish" />
      <div className="small">{def.blurb}</div>
      <div className="small row" style={{ marginTop: 6, justifyContent: 'space-between' }}>
        <span className="row" style={{ gap: 5 }}>
          {u.size === 1 ? 'Alone' : 'Soldiers'} <MenPips men={alive} size={u.size} />
        </span>
        <span className="tiny muted">{u.hpPer} HP each</span>
      </div>
      <SquadBar hp={hp} hpPer={u.hpPer} size={u.size} alive={alive} height={7} />
      <div className="small" style={{ marginTop: 4 }}>
        HP {hp}/{u.maxHp} · Morale {MORALE_LABEL[scene.b.moraleState(u)]} ({morale})
      </div>
      <div className="tiny" style={{ marginTop: 3 }} title="Per soldier × soldiers standing, before armour">
        {u.shot ? `${shotName(u)} ${per(u.shot.damage)} · ` : ''}
        {def.primary && ABILITIES[def.primary].power ? `${ABILITIES[def.primary].name} ${per(ABILITIES[def.primary].power!)} · ` : ''}
        Melee {per(u.melee)}
      </div>
      <div className="tiny" style={{ marginTop: 4 }}>
        Melee {u.stats.melee} · Def {u.stats.defense}{u.shieldFront ? ` (+${u.shieldFront})` : ''} · Armour {u.stats.armor.toFixed(1)} · Move {u.stats.move}
        {u.shot && ` · ${u.tags.includes('caster') ? 'Spells' : 'Bow'} ${u.stats.ranged}, range ${u.shot.range}`}
      </div>
      {u.abilities.length > 0 && (
        <div className="tiny" style={{ marginTop: 4 }}>
          {u.abilities.map((a) => {
            const cd = u.cooldowns[a] ?? 0;
            return `${ABILITIES[a].name}${cd > 0 ? ` (ready in ${cd})` : ''}`;
          }).join(', ')}
        </div>
      )}
      <div style={{ marginTop: 4 }}><StatusChips u={u} /></div>
      {u.leader && <div className="small" style={{ marginTop: 4, color: '#8a1f15' }}>Warband leader: if he falls, his followers lose heart.</div>}
    </div>
  );
}

function TileInfo() {
  const s = useStore();
  const scene = s.battleScene!;
  const t = scene.ui.hover.tile!;
  const tile = tileAt(scene.b.map, t.x, t.y);
  if (!tile) return null;
  const ter = TERRAIN[tile.terrain];
  const prop = tile.prop ? PROPS[tile.prop] : undefined;
  return (
    <div className="panel dark" style={{ position: 'absolute', right: 16, top: 70, width: 240, padding: '8px 12px' }}>
      <div className="cinzel" style={{ fontWeight: 700 }}>{prop ? prop.name : ter.name}</div>
      <div className="tiny">
        {prop ? (prop.blocksMove ? 'Impassable' : 'Passable') : `Move cost ${ter.moveCost >= 99 ? '–' : ter.moveCost}`}
        {tile.h > 0 && ` · High ground (+${tile.h})`}
        {ter.rangedCover ? ` · -${ter.rangedCover}% to missiles` : ''}
        {prop?.cover ? ` · Cover ${prop.cover}%` : ''}
        {prop?.los === 2 ? ' · Blocks sight' : ''}
      </div>
      {scene.ui.hover.facing !== undefined && scene.ui.hover.dest && (
        <div className="tiny" style={{ marginTop: 3, color: '#ffd76a' }}>
          {scene.ui.hover.turn ? 'Turn on the spot' : 'Arrives'} facing {FACING_ARROW[scene.ui.hover.facing]}
          {(scene.ui.hover.facings?.length ?? 0) > 1 ? <span className="muted"> · Q / E or point at an edge: other sides ({scene.ui.hover.facings!.length})</span> : <span className="muted"> · the only way in</span>}
        </div>
      )}
      {scene.ui.hover.zoc ? <div className="tiny" style={{ color: '#ffb070', marginTop: 3 }}>This path leaves enemy reach: {scene.ui.hover.zoc} free attack(s).</div> : null}
    </div>
  );
}
