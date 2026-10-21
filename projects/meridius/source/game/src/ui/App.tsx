import { useStore } from './store';
import { Base } from './screens/Base';
import { BattleHud } from './screens/Battle';
import { Campaign } from './screens/Campaign';
import { Prep } from './screens/Prep';
import { Report } from './screens/Report';
import { Title } from './screens/Title';
import { Manual } from './screens/Manual';

export function App() {
  const s = useStore();
  return (
    <>
      <Screen />
      {s.manual && (
        <div className="layer">
          <Manual start={s.manual} onClose={() => s.openManual(null)} />
        </div>
      )}
    </>
  );
}

function Screen() {
  const s = useStore();
  switch (s.screen) {
    case 'loading':
      return (
        <div className="layer" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div className="cinzel" style={{ color: '#f0e2c0', fontSize: 22 }}>
            Loading… {Math.round(s.loadProgress * 100)}%
          </div>
        </div>
      );
    case 'title':
      return (
        <div className="layer">
          <Title />
        </div>
      );
    case 'base':
      return <Base />;
    case 'prep':
      return <Prep />;
    case 'campaign':
      return <Campaign />;
    case 'battle':
      return <BattleHud />;
    case 'report':
      return <Report />;
  }
}
