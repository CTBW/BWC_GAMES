import test from 'node:test';
import assert from 'node:assert/strict';
import { chmod, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { launch } from '../launchers.mjs';

const windows = process.platform === 'win32';
const ext = windows ? '.cmd' : '.sh';
// A script that records the launch flag, then prints a line or fails.
const script = (lines, code) => windows
  ? `@echo off\r\n(echo %MRMAK_LAUNCHER%)> launched.txt\r\n${lines.join('\r\n')}\r\nexit /b ${code}\r\n`
  : `#!/bin/sh\necho "$MRMAK_LAUNCHER" > launched.txt\n${lines.join('\n')}\nexit ${code}\n`;

async function repo() {
  const root = await mkdtemp(path.join(os.tmpdir(), 'mrmak-launch-'));
  const files = {
    [`Open game${ext}`]: script(['echo Started the game.'], 0),
    [`broken${ext}`]: script([windows ? 'echo Godot was not found. 1>&2' : 'echo "Godot was not found." >&2'], 3),
    'notes.ps1': 'Write-Output hi',
  };
  for (const [name, text] of Object.entries(files)) {
    await writeFile(path.join(root, name), text);
    if (!windows) await chmod(path.join(root, name), 0o755);
  }
  const registry = { entities: [{ id: 'game', launchers: [
    { id: 'play', name: 'The game', path: `Open game${ext}` },
    { id: 'broken', name: 'Broken', path: `broken${ext}` },
    { id: 'script', path: 'notes.ps1' },
    { id: 'outside', path: `../elsewhere${ext}` },
  ] }, { id: 'other', launchers: [] }] };
  return { root, registry };
}

test('a card starts a script it lists and hears its last line', async () => {
  const { root, registry } = await repo();
  const result = await launch(root, registry, 'game', 'play');
  assert.deepEqual(result, { started: true, name: 'The game', message: 'Started the game.' });
  // The script knows the Workspace started it, so it reports errors instead of showing dialogs.
  assert.equal((await readFile(path.join(root, 'launched.txt'), 'utf8')).trim(), '1');
});

test('a failing script reports its error output', async () => {
  const { root, registry } = await repo();
  await assert.rejects(launch(root, registry, 'game', 'broken'), { message: 'Godot was not found.', status: 500 });
});

test('only listed repository scripts of the same card can start', async () => {
  const { root, registry } = await repo();
  await assert.rejects(launch(root, registry, 'other', 'play'), { status: 404 });
  await assert.rejects(launch(root, registry, 'game', 'missing'), { status: 404 });
  await assert.rejects(launch(root, registry, 'nobody', 'play'), { status: 404 });
  await assert.rejects(launch(root, registry, 'game', 'script'), { status: 400 });
  await assert.rejects(launch(root, registry, 'game', 'outside'), { status: 403 });
});

test('a second request while a script runs shares its start', async () => {
  const { root, registry } = await repo();
  const [a, b] = await Promise.all([launch(root, registry, 'game', 'play'), launch(root, registry, 'game', 'play')]);
  assert.equal(a, b);
});
