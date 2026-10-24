// Agent board: reloads live/board-data.js (written every minute by
// build_board.py) and draws one lane per state. Works inside the Workspace
// and as a plain file in its own browser window.
(() => {
  const RELOAD_MS = 20000;
  const STALE_MS = 3 * 60 * 1000;
  const LANES = [
    { id: 'working', title: 'Working', hint: 'busy right now' },
    { id: 'stopped', title: 'Stopped mid-step', hint: 'interrupted, say “continue”' },
    { id: 'waiting', title: 'Your turn', hint: 'finished, waiting for you' },
    { id: 'done', title: 'Done and quiet', hint: 'finished or quiet for 3 h' },
  ];
  const $ = id => document.getElementById(id);
  let data = null, failed = false;

  function el(tag, attrs = {}, ...children) {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs)) {
      if (value == null || value === false) continue;
      if (key === 'class') node.className = value;
      else if (key === 'style') node.setAttribute('style', value);
      else node.setAttribute(key, value);
    }
    for (const child of children.flat()) if (child != null && child !== false) node.append(child);
    return node;
  }

  const time = value => value ? new Date(value).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '';
  const minutesSince = value => value ? Math.max(0, Math.round((Date.now() - new Date(value)) / 60000)) : null;
  function duration(minutes) {
    if (minutes == null) return '';
    if (minutes < 60) return `${minutes} min`;
    const hours = Math.floor(minutes / 60), rest = minutes % 60;
    return rest ? `${hours} h ${String(rest).padStart(2, '0')} min` : `${hours} h`;
  }

  function statusLine(card) {
    const minutes = minutesSince(card.since);
    if (card.lane === 'working') return `Working ${duration(minutes)}`;
    if (card.kind === 'job') return `Background job ${card.status} at ${time(card.since)}`;
    if (card.lane === 'stopped') return `Stopped ${duration(minutes)} ago`;
    if (card.lane === 'waiting') return `Waiting ${duration(minutes)}`;
    return `Quiet ${duration(minutes)}`;
  }

  function agentCard(card) {
    const minutes = minutesSince(card.since) ?? 0;
    const width = Math.min(100, Math.max(4, minutes / 120 * 100));
    const stoppedHint = card.lane === 'stopped' && card.kind !== 'job'
      ? `Ended on a ${card.stoppedAt || 'step'}${card.pendingTool ? ` (${card.pendingTool})` : ''} without a reply. Open its chat and say “continue”.`
      : null;
    const details = [];
    if (card.reply?.text) details.push(el('dt', {}, `Last reply${card.reply.at ? ` · ${time(card.reply.at)}` : ''}`), el('dd', {}, card.reply.text));
    if (card.lane === 'done' && (card.note || card.kind === 'job')) details.length = 0;
    else if (card.prompt?.text) details.push(el('dt', {}, `${card.kind === 'job' ? 'Task' : 'Last message to it'}${card.prompt.at ? ` · ${time(card.prompt.at)}` : ''}`), el('dd', { class: 'prompt' }, card.prompt.text));
    return el('article', { class: 'agent', 'aria-label': `${card.title}, ${statusLine(card)}` },
      el('div', { class: 'agent-top' }, el('span', { class: 'tag', title: card.name }, card.short), el('h3', {}, card.title)),
      el('div', { class: 'agent-time' }, el('strong', {}, statusLine(card)), card.lane === 'done' ? null : el('span', { class: 'bar', 'aria-hidden': 'true' }, el('i', { style: `width:${width}%` }))),
      card.note ? el('p', { class: 'agent-note' }, card.note) : null,
      stoppedHint ? el('p', { class: 'agent-hint' }, stoppedHint) : null,
      details.length ? el('dl', {}, details) : null,
      el('p', { class: 'agent-id' }, [card.name, card.kind === 'job' ? `job ${card.id}` : card.id, card.folder].filter(Boolean).join(' · ')));
  }

  function render() {
    if (!data) return;
    const cards = data.cards || [];
    const count = id => cards.filter(card => card.lane === id).length;
    const git = data.git;

    const summary = $('summary');
    summary.replaceChildren(...[
      ...LANES.map(lane => el('span', { class: `chip is-${lane.id}` }, el('span', { class: 'dot' }), el('b', {}, String(count(lane.id))), lane.title)),
      git && git.ahead != null ? el('span', { class: 'chip' }, el('b', {}, String(git.ahead)), git.ahead === 1 ? 'commit not on GitHub' : 'commits not on GitHub') : null,
      git ? el('span', { class: 'chip' }, el('b', {}, String(git.uncommitted)), 'uncommitted changes') : null,
      el('span', { class: 'chip' }, 'Commit lock: ', el('b', {}, data.lock ? data.lock.split(' · ')[0] : 'not tracked'))].filter(Boolean));

    $('lanes').replaceChildren(...LANES.map(lane => {
      const items = cards.filter(card => card.lane === lane.id);
      return el('section', { class: `lane is-${lane.id}`, 'aria-label': lane.title },
        el('div', { class: 'lane-head' }, el('span', { class: `dot ${lane.id}` }),
          el('h2', {}, lane.title, el('span', { class: 'hint' }, lane.hint)), el('span', { class: 'count' }, String(items.length))),
        items.length ? items.map(agentCard) : el('p', { class: 'empty' }, 'Nobody here.'));
    }));

    const repo = [];
    if (git) {
      const synced = git.ahead === 0 && git.behind === 0;
      repo.push(el('div', { class: 'panel' }, el('h2', {}, 'Git'),
        el('p', {}, 'Branch ', el('code', {}, git.branch || '?'), ' at ', el('code', {}, git.head), ` ${git.subject}`),
        el('p', { class: synced ? 'ok' : 'warn' }, git.ahead == null ? 'No GitHub branch to compare with.'
          : synced ? 'In sync with GitHub.' : `${git.ahead} commit${git.ahead === 1 ? '' : 's'} not on GitHub${git.behind ? `, ${git.behind} on GitHub not here` : ''}.`),
        git.unpushed?.length ? el('ul', {}, git.unpushed.map(commit => el('li', {}, el('code', {}, commit.sha), ` ${commit.subject}`))) : null,
        el('p', {}, `${git.uncommitted} uncommitted change${git.uncommitted === 1 ? '' : 's'} in the shared folder.`)));
    }
    repo.push(el('div', { class: 'panel' }, el('h2', {}, 'Coordinator'),
      el('p', {}, 'Commit lock: ', el('strong', {}, data.lock || 'not tracked by a coordinator')),
      data.coordinator ? el('p', {}, data.coordinator) : null));
    $('repo').replaceChildren(...repo);

    const waiting = count('waiting') + count('stopped');
    document.title = `Agent board · ${count('working')} working · ${waiting} need you`;
    tick();
  }

  function tick() {
    const feed = $('feed'), stale = $('stale');
    if (!data) {
      if (failed) {
        feed.textContent = 'No board data yet.';
        stale.hidden = false;
        stale.textContent = 'The live data file is missing. Run “python build_board.py --install” in workspace/2026-10-24_agent-board to start the minute-by-minute feed.';
      }
      return;
    }
    const age = Date.now() - new Date(data.generatedAt);
    const seconds = Math.max(0, Math.round(age / 1000));
    feed.replaceChildren(el('b', {}, failed ? 'Offline' : age > STALE_MS ? 'Paused' : 'Live'),
      ` · data from ${new Date(data.generatedAt).toLocaleTimeString()} (${seconds < 90 ? `${seconds} s` : duration(Math.round(seconds / 60))} ago) · updates every minute, this page checks every 20 s`);
    stale.hidden = !failed && age <= STALE_MS;
    if (failed && /^https?:$/.test(location.protocol)) stale.textContent = `This page lost its connection to Mr. Mak after ${time(data.generatedAt)}. If Mr. Mak restarted, open the Agent board card again or use the desktop shortcut “Agent Board”.`;
    else if (failed) stale.textContent = 'The data file live/board-data.js cannot be read. Run “python build_board.py --install” in workspace/2026-10-24_agent-board.';
    else if (age > STALE_MS) stale.textContent = `The board stopped updating at ${time(data.generatedAt)}. The scheduled task “Mr Mak Agent Board” is not running, or the last run failed (see live/last-error.txt). Run “python build_board.py --install” in workspace/2026-10-24_agent-board.`;
  }

  function load() {
    const script = document.createElement('script');
    script.src = `live/board-data.js?t=${Date.now()}`;
    script.onload = () => { script.remove(); if (window.AGENT_BOARD) { data = window.AGENT_BOARD; failed = false; render(); } };
    script.onerror = () => { script.remove(); failed = true; tick(); };
    document.head.append(script);
  }

  const popout = $('popout');
  if (window.self !== window.top && /^https?:$/.test(location.protocol)) {
    $('popout-box').hidden = false;
    popout.addEventListener('click', () => window.open(location.href, '_blank', 'noopener'));
  }

  load();
  setInterval(load, RELOAD_MS);
  setInterval(() => { if (data) render(); else tick(); }, 15000);
})();
