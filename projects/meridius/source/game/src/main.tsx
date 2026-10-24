import { createRoot } from 'react-dom/client';
import '@fontsource/cinzel/400.css';
import '@fontsource/cinzel/700.css';
import '@fontsource/cinzel/900.css';
import '@fontsource/alegreya/400.css';
import '@fontsource/alegreya/500.css';
import '@fontsource/alegreya/700.css';
import '@fontsource/alegreya/400-italic.css';
import './ui/styles.css';
import { App } from './ui/App';
import { store } from './ui/store';
import { Engine } from './render/engine';
import { loadAssets, sprite } from './render/assets';

const canvas = document.createElement('canvas');
canvas.id = 'world';
document.body.prepend(canvas);
const engine = new Engine(canvas);
store.engine = engine;
engine.start();

createRoot(document.getElementById('root')!).render(<App />);

(async () => {
  await Promise.all([
    loadAssets((f) => {
      store.loadProgress = f;
      store.emit();
    }),
    document.fonts?.ready,
  ]);
  const params = new URLSearchParams(location.search);
  if (params.has('newgame')) store.newGame(Number(params.get('seed') ?? 1234));
  else store.goTitle();
})();

// Automation hooks for scripted play-tests.
(window as unknown as { __meridius: unknown }).__meridius = { store, engine, sprite };
