import { useStore } from '../store';

export function Title() {
  const s = useStore();
  const save = s.hasSave();
  return (
    <div className="title-screen">
      <div className="logo">MERIDIUS</div>
      <div className="logo-sub">THE FRONTIER COMPANY</div>
      <div className="panel" style={{ marginTop: 34, padding: '18px 26px', width: 520, textAlign: 'center' }}>
        <p style={{ fontSize: 17, lineHeight: 1.45, margin: '0 0 6px' }}>
          A host of goblins and orcs is pouring out of the Hillsvain Woods into the borderlands of Nordmark. There is no end to them. There is only the Amberfeld Company in the way.
        </p>
        <p className="muted" style={{ fontSize: 15, margin: '0 0 14px' }}>
          Lead the Amberfeld Company: recruit, march, fight and return. Every soldier who falls stays fallen.
        </p>
        <div className="row" style={{ justifyContent: 'center', gap: 14 }}>
          {save && (
            <button className="btn big blue" onClick={() => s.continueGame()}>
              Continue
            </button>
          )}
          <button
            className={`btn big ${save ? '' : 'primary'}`}
            onClick={() => {
              if (save && !confirm('Start a new company? The current save will be replaced.')) return;
              s.newGame();
            }}
          >
            New Company
          </button>
        </div>
      </div>
      <div className="muted tiny" style={{ position: 'absolute', bottom: 12, color: '#cdb88a' }}>
        Phase one build · Tier I campaign: The Hillsvain Host
      </div>
    </div>
  );
}
