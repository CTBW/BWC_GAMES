/* The "Open the sandbox" button. The page asks the Mr. Mak app to start this
   card's launcher (workspace.json lists "Meridius Sandbox.cmd" for the card)
   and shows its answer: mrmak:launch-result with state 'starting', then
   'started' or 'failed' (src/App.tsx). An app without launchers does not
   answer, so after a short wait the page explains the other ways in. */
(() => {
  const button = document.getElementById('launch');
  const status = document.getElementById('launch-status');
  const help = document.getElementById('launch-help');
  const why = document.getElementById('launch-why');
  const idle = status.textContent;
  const inApp = window.parent !== window;
  let timer = 0;

  const show = (state, text) => {
    document.documentElement.dataset.launch = state;
    status.textContent = text;
    button.disabled = state === 'asking' || state === 'starting';
  };
  const explain = (state, text, reason) => {
    clearTimeout(timer);
    show(state, text);
    why.textContent = reason;
    help.hidden = false;
  };

  window.addEventListener('message', event => {
    const data = event.data;
    if (event.source !== window.parent || data?.type !== 'mrmak:launch-result' || data.launcher !== 'sandbox') return;
    clearTimeout(timer);
    if (data.state === 'starting') {
      show('starting', 'Starting the sandbox…');
      timer = setTimeout(() => explain('failed', 'The sandbox did not report back.', 'Mr. Mak started the launcher but heard nothing from it within a minute.'), 60000);
    } else if (data.state === 'started') {
      help.hidden = true;
      const again = /already open/i.test(data.message || '');
      show('started', again
        ? 'The sandbox was already open: it is now in front.'
        : 'The sandbox is starting: its window opens in a few seconds.');
      setTimeout(() => { if (document.documentElement.dataset.launch === 'started') show('', idle); }, 12000);
    } else if (data.state === 'failed') {
      explain('failed', data.error || 'The sandbox could not start.', 'Mr. Mak tried to start the sandbox and reported the error above.');
    }
  });

  button.addEventListener('click', () => {
    if (!inApp) {
      explain('help', 'This page is open outside Mr. Mak, so it cannot start programs.', 'Open the Sandbox card in the Mr. Mak desktop app, or start the sandbox yourself:');
      return;
    }
    help.hidden = true;
    show('asking', 'Asking Mr. Mak to open the sandbox…');
    window.parent.postMessage({ type: 'mrmak:launch', launcher: 'sandbox' }, '*');
    timer = setTimeout(() => explain('help', 'Mr. Mak did not answer the button.',
      'The installed Mr. Mak predates card launch buttons: the last step below enables them. Until then, start the sandbox yourself:'), 2500);
  });
})();
