// Meridius game guide: the section menu (after the Mr. Mak 64 starter), unit filters,
// jumps between sections and the pose previews, which run only while Animations is open.
(() => {
  const tabs = [...document.querySelectorAll('[data-page]')];
  const pages = [...document.querySelectorAll('.hub-page')];
  let pending = null;

  const reveal = id => {
    const target = document.getElementById(id);
    if (!target) return false;
    target.scrollIntoView({ block: 'start' });
    target.classList.add('flash');
    setTimeout(() => target.classList.remove('flash'), 1600);
    return true;
  };
  const select = (id, focus = false) => {
    const target = tabs.find(tab => tab.dataset.page === id) || tabs[0];
    for (const tab of tabs) {
      const active = tab === target;
      tab.setAttribute('aria-selected', String(active));
      tab.tabIndex = active ? 0 : -1;
    }
    for (const page of pages) page.hidden = page.id !== target.dataset.page;
    if (focus) target.focus();
    const anchor = pending;
    pending = null;
    if (!anchor || !reveal(anchor)) window.scrollTo({ top: 0, behavior: 'instant' });
  };
  const open = id => {
    if (location.hash === `#${id}`) select(id);
    else location.hash = id;
  };

  tabs.forEach((tab, i) => {
    tab.addEventListener('click', () => open(tab.dataset.page));
    tab.addEventListener('keydown', event => {
      const next = { ArrowDown: (i + 1) % tabs.length, ArrowRight: (i + 1) % tabs.length,
        ArrowUp: (i + tabs.length - 1) % tabs.length, ArrowLeft: (i + tabs.length - 1) % tabs.length,
        Home: 0, End: tabs.length - 1 }[event.key];
      if (next === undefined) return;
      event.preventDefault();
      open(tabs[next].dataset.page);
      select(tabs[next].dataset.page, true);
    });
  });
  document.querySelectorAll('[data-open]').forEach(button => button.addEventListener('click', () => open(button.dataset.open)));

  // Units shown on Characters: all, or one side.
  const filters = [...document.querySelectorAll('[data-filter]')];
  const cards = [...document.querySelectorAll('.unit-card')];
  const filter = side => {
    for (const button of filters) button.setAttribute('aria-pressed', String(button.dataset.filter === side));
    for (const card of cards) card.hidden = side !== 'all' && card.dataset.faction !== side;
  };
  filters.forEach(button => button.addEventListener('click', () => filter(button.dataset.filter)));

  // data-goto="page:id" opens a section at a unit's card, its animations or an ability.
  const prefix = { characters: 'unit-', animations: 'anim-', abilities: 'ability-' };
  document.addEventListener('click', event => {
    const link = event.target.closest('[data-goto]');
    if (!link) return;
    const [page, id] = link.dataset.goto.split(':');
    if (page === 'characters') filter('all');
    pending = (prefix[page] || '') + id;
    open(page);
  });

  window.addEventListener('hashchange', () => select(location.hash.slice(1)));
  select(location.hash.slice(1));

  // Pose previews step through one strip of equal cells at the game's frame times.
  const still = matchMedia('(prefers-reduced-motion: reduce)');
  const animations = document.getElementById('animations');
  const previews = [...document.querySelectorAll('.pose-preview')].map(element => ({
    element,
    n: Number(element.dataset.n),
    seq: element.dataset.seq.split(',').map(Number),
    times: element.dataset.times.split(',').map(Number),
    at: 0,
    due: 0,
  }));
  const show = p => {
    const cell = p.seq[p.at];
    p.element.style.backgroundPosition = `${p.n > 1 ? (cell / (p.n - 1)) * 100 : 0}% 0`;
  };
  previews.forEach(show);
  const tick = now => {
    requestAnimationFrame(tick);
    if (still.matches || animations.hidden) return;
    for (const p of previews) {
      if (p.seq.length < 2 || now < p.due) continue;
      p.at = (p.at + 1) % p.seq.length;
      p.due = now + p.times[p.at] * 1000;
      show(p);
    }
  };
  requestAnimationFrame(tick);
})();
