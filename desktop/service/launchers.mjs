import { spawn } from 'node:child_process';
import path from 'node:path';
import { realFile } from './util.mjs';

// A card can list programs of this repository that its reports start with a
// button, such as a game's test scene:
//   "launchers": [{ "id": "sandbox", "name": "3D unit sandbox", "path": "Meridius Sandbox.cmd" }]
// A report asks only for an id. The script comes from the card's registry
// entry and runs without arguments, so a report starts nothing its card does
// not list. The script should start its program and return; its last line of
// output is shown, and a non-zero exit reports its error output.
const SCRIPT = process.platform === 'win32' ? /\.(cmd|bat)$/i : /\.(sh|command)$/;
const failure = (message, status = 400) => Object.assign(new Error(message), { status });
const running = new Map();

export function launch(repo, registry, entityId, launcherId, options = {}) {
  const key = `${entityId}\n${launcherId}`;
  // A second click while the script still runs waits for the same start.
  if (!running.has(key)) running.set(key, start(repo, registry, entityId, launcherId, options).finally(() => running.delete(key)));
  return running.get(key);
}

async function start(repo, registry, entityId, launcherId, { wait = 20000 } = {}) {
  const entity = (registry.entities || []).find(item => item.id === entityId);
  const launcher = (Array.isArray(entity?.launchers) ? entity.launchers : []).find(item => item?.id === launcherId);
  if (!launcher || typeof launcher.path !== 'string' || !launcher.path) throw failure('This card has no launcher by that name.', 404);
  const { file, info } = await realFile(repo, launcher.path);
  if (!info.isFile() || !SCRIPT.test(file)) throw failure(`A launcher must be a ${process.platform === 'win32' ? '.cmd or .bat' : '.sh or .command'} script in this repository.`);
  // cmd.exe reads these even inside quotes.
  if (process.platform === 'win32' && /["%!^&|<>\r\n]/.test(file)) throw failure('Rename the launcher script: its path has characters cmd.exe would interpret.');
  const name = String(launcher.name || launcher.id);
  const options = { cwd: path.dirname(file), env: { ...process.env, MRMAK_LAUNCHER: '1' }, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true };
  const child = process.platform === 'win32'
    ? spawn(process.env.ComSpec || 'cmd.exe', ['/d', '/s', '/c', `""${file}""`], { ...options, windowsVerbatimArguments: true })
    : spawn(file, [], options);
  let out = '', err = '';
  child.stdout.on('data', chunk => { out = (out + chunk).slice(-4000); });
  child.stderr.on('data', chunk => { err = (err + chunk).slice(-4000); });
  const last = text => text.split(/\r?\n/).map(line => line.trim()).filter(Boolean).pop() || '';
  return await new Promise((resolve, reject) => {
    // A script that keeps running is left to it; the start counts as made.
    const timer = setTimeout(() => { child.unref(); resolve({ started: true, name, message: last(out) || `${name} is starting.` }); }, wait);
    child.once('error', error => { clearTimeout(timer); reject(failure(`${name} could not start: ${error.message}`, 500)); });
    child.once('exit', code => {
      clearTimeout(timer);
      if (code === 0) resolve({ started: true, name, message: last(out) || `${name} started.` });
      else reject(failure(last(err) || last(out) || `${name} stopped with exit code ${code}.`, 500));
    });
  });
}
