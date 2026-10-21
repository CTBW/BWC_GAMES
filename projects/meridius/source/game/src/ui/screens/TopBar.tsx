import { useState } from 'react';
import { isMuted, setMuted } from '../../audio/sfx';
import { Icon, RES_NAMES } from '../common';
import { useStore } from '../store';
import type { Resources } from '../../core/types';

export function TopBar() {
  const s = useStore();
  const g = s.game!;
  const [muted, setM] = useState(isMuted());
  return (
    <div className="topbar">
      <span className="brand">MERIDIUS</span>
      <span className="muted small" style={{ color: '#cdb88a' }}>
        Amberfeld Garrison · Expeditions: {g.cycle}
      </span>
      <span className="spacer" />
      {(Object.keys(g.resources) as (keyof Resources)[]).map((k) => (
        <span key={k} className="res" title={RES_NAMES[k]}>
          <Icon name={k} size={22} />
          {g.resources[k]}
          <span className="lbl">{RES_NAMES[k]}</span>
        </span>
      ))}
      <span className="spacer" />
      <button className="btn sm" onClick={() => s.openManual('base')}>
        Field Manual
      </button>
      <button className="btn sm" onClick={() => s.openPanel('memorial')}>
        The Fallen ({g.fallen.length})
      </button>
      <button
        className="btn sm icon"
        title={muted ? 'Sound off' : 'Sound on'}
        onClick={() => {
          setMuted(!muted);
          setM(!muted);
        }}
      >
        <span style={{ color: '#f0e2c0', display: 'inline-flex' }}>
          <Icon name={muted ? 'mute' : 'sound'} />
        </span>
      </button>
      <button className="btn sm" onClick={() => s.goTitle()}>
        Menu
      </button>
    </div>
  );
}
