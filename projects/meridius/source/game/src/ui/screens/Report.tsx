import { campaignById } from '../../data/campaigns';
import { squadName } from '../../battle/squad';
import { missingMen } from '../../meta/game';
import { soldierStats } from '../../meta/soldier';
import { MenPips, ResList } from '../common';
import { useStore } from '../store';

export function Report() {
  const s = useStore();
  const r = s.report ?? s.game?.lastReport;
  if (!r) {
    return (
      <div className="layer">
        <button className="btn" onClick={() => s.goBase()}>Continue</button>
      </div>
    );
  }
  const c = campaignById(r.campaignId);
  const roster = s.game?.roster ?? [];
  const wounded = roster.filter((so) => so.injuries.length).length;
  const worn = roster.filter((so) => so.morale < soldierStats(so).morale * 0.5).length;
  const thin = roster.filter((so) => missingMen(so) > 0).length;
  const advice = [
    'New recruits wait at the barracks.',
    thin ? `${thin === 1 ? 'One squad is' : `${thin} squads are`} below strength; the Barracks can refill the ranks.` : '',
    wounded ? `${wounded === 1 ? 'One sergeant needs' : `${wounded} sergeants need`} the surgeon.` : '',
    worn ? `${worn === 1 ? 'One is' : `${worn} are`} worn down and may want leave.` : '',
  ].filter(Boolean).join(' ');
  const title = r.outcome === 'success' ? 'Triumph' : r.outcome === 'retreat' ? 'The Long Road Home' : 'A Broken Company';
  const line =
    r.outcome === 'success'
      ? `The company returns from ${c.name}: Brannsted held until dawn, and the host was turned.`
      : r.outcome === 'retreat'
        ? `The company turns back from ${c.name} before the objective was met.`
        : `What is left of the company limps back from ${c.name}. Half the spoils were lost in the rout.`;
  return (
    <div className="layer modal-back">
      <div className="panel dialog" style={{ width: 660 }}>
        <div className="title" style={{ fontSize: 32, color: r.outcome === 'success' ? '#2d5a1a' : '#8a1f15' }}>{title}</div>
        <p style={{ textAlign: 'center' }}>{line}</p>
        <div className="grid2">
          <div className="card">
            <div className="small row" style={{ gap: 6 }}><b>Spoils:</b> <ResList res={r.loot} size={16} /></div>
            {Object.keys(r.reward).length > 0 && (
              <div className="small row" style={{ gap: 6 }}><b>Reward:</b> <ResList res={r.reward} size={16} /></div>
            )}
            <div className="small">Leftover supplies sold: {r.buyback} silver</div>
            {r.stipend > 0 && <div className="small">Council stipend: {r.stipend} silver</div>}
            <div className="small muted">{r.marches} marches · {r.battles} battles</div>
          </div>
          <div className="card">
            {r.fallen.length ? (
              <div className="small" style={{ color: '#8a1f15' }}><b>Squads lost:</b> {r.fallen.join(', ')}</div>
            ) : (
              <div className="small">Every squad came home.</div>
            )}
            {r.menLost !== undefined && (
              <div className="small" style={{ color: r.menLost ? '#8a1f15' : undefined }}>
                {r.menLost ? `${r.menLost} ${r.menLost === 1 ? 'soldier' : 'soldiers'} died on the expedition.` : 'Not a soldier was lost.'}
              </div>
            )}
            {r.strength ? (
              <div className="col losses" style={{ gap: 2, marginTop: 4 }}>
                <div className="small"><b>Returned:</b>{!r.strength.length && <span> no one</span>}</div>
                {r.strength.map((q) => (
                  <div key={q.name} className="small">
                    <span>{squadName(q)}</span>
                    <MenPips men={q.men} size={q.size} />
                  </div>
                ))}
              </div>
            ) : (
              <div className="small" style={{ marginTop: 4 }}><b>Returned:</b> {r.survivors.join(', ') || 'no one'}</div>
            )}
          </div>
        </div>
        <p className="small muted" style={{ textAlign: 'center' }}>
          {advice}
        </p>
        <div className="row" style={{ justifyContent: 'center' }}>
          <button className="btn big primary" onClick={() => s.goBase()}>
            Back to Amberfeld
          </button>
        </div>
      </div>
    </div>
  );
}
