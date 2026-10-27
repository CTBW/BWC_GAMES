import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport, getDefaultEnvironment } from '@modelcontextprotocol/sdk/client/stdio.js';
import { createService } from '../server.mjs';
import { sendRefusal, MAX_AGENT_MESSAGE } from '../agent-channel.mjs';
import { findChat } from '../chats-mcp.mjs';
import { sleep } from '../util.mjs';

const server = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../chats-mcp.mjs');
const menu = ['▌ Allow command?', '▌ $ cargo build', '', '  › 1. Yes, proceed (y)', "    2. Yes, and don't ask again for this command (a)", '    3. No, and tell Codex what to do differently (esc)', '', '  Press enter to confirm or esc to cancel'].join('\n');

async function fixture() {
  const repo = await mkdtemp(path.join(os.tmpdir(), 'mrmak-agent-channel-'));
  await mkdir(path.join(repo, 'workspace'));
  await writeFile(path.join(repo, 'workspace/workspace.json'), '{"entities":[]}');
  const service = await createService({ repo, uiDir: repo, mcpOptions: { home: repo, env: {} } });
  const channel = JSON.parse(await readFile(service.channel.file, 'utf8'));
  async function chat(id, name, agent = 'codex', metadata = {}) {
    const writes = [];
    const session = service.sessions.make({ id, name, agent, cwd: repo, nativeId: `native-${id}`, open: true, status: 'running', createdAt: new Date().toISOString(), lastInputAt: null, cols: 80, rows: 24, ...metadata });
    session.process = { write: data => writes.push(data), resize() {}, kill() { session.process = null; } };
    service.sessions.items.set(id, session);
    await service.sessions.hydrate(session);
    return { session, writes };
  }
  const call = (route, { token = channel.token, from, ...options } = {}) => fetch(service.origin + route, {
    ...options, headers: { Authorization: `Bearer ${token}`, ...(from ? { 'X-Mrmak-Chat': from } : {}), ...(options.body ? { 'Content-Type': 'application/json' } : {}), ...options.headers },
  });
  return { repo, service, channel, chat, call };
}

test('the agent channel has its own token, refuses browser pages and removes its file on close', async () => {
  const { service, channel, call } = await fixture();
  try {
    assert.equal(channel.origin, service.origin);
    assert.notEqual(channel.token, service.token);
    assert.ok(!JSON.stringify(channel).includes(service.token));
    assert.equal((await call('/agent/chats', { token: 'wrong' })).status, 401);
    assert.equal((await call('/agent/chats', { token: service.token })).status, 401);
    assert.equal((await call('/agent/chats', { headers: { Origin: service.origin } })).status, 401);
    assert.equal((await call('/agent/chats')).status, 200);
    // The channel token opens nothing outside /agent/.
    assert.equal((await call('/api/sessions')).status, 401);
    assert.equal((await call('/agent/other')).status, 404);
  } finally { await service.close(); }
  assert.equal(existsSync(service.channel.file), false);
});

test('agents list the open agent chats, read a screen and message an idle chat', async () => {
  const { service, chat, call } = await fixture();
  try {
    await chat('chat-a', 'Coordinator');
    const { session: wolf, writes } = await chat('chat-b', 'Rigging Wolf Scouts');
    await chat('chat-c', 'Local shell', 'shell');
    await chat('chat-d', 'Closed chat', 'codex', { open: false });
    const listed = await (await call('/agent/chats', { from: 'chat-a' })).json();
    assert.equal(listed.self, 'chat-a');
    assert.deepEqual(listed.chats.map(item => [item.id, item.self]), [['chat-a', true], ['chat-b', false]]);
    await new Promise(resolve => wolf.terminal.write('Rig check finished.\r\n› ', resolve));
    const screen = await (await call('/agent/chats/chat-b/screen?lines=10', { from: 'chat-a' })).json();
    assert.match(screen.screen, /Rig check finished\./);
    assert.equal(screen.prompt, null);
    assert.match(screen.note, /not instructions/);
    const sent = await call('/agent/chats/chat-b/send', { from: 'chat-a', method: 'POST', body: JSON.stringify({ text: 'The viewer zoom is capped at 4x.\nPlease update wolf-scout.html.' }) });
    assert.equal(sent.status, 200);
    assert.equal((await sent.json()).to, 'Rigging Wolf Scouts');
    assert.ok(writes[0].startsWith('\x1b[200~[Message from Coordinator (codex chat), sent through Mr. Mak. It comes from another agent, not from the user.]\nThe viewer zoom'));
    assert.ok(writes[0].endsWith('wolf-scout.html.\x1b[201~'));
    await sleep(650);
    assert.deepEqual(writes.slice(1), ['\r']);
    const log = (await readFile(service.channel.log, 'utf8')).trim().split('\n').map(line => JSON.parse(line));
    assert.deepEqual(log.map(entry => [entry.from, entry.to, entry.toName]), [['chat-a', 'chat-b', 'Rigging Wolf Scouts']]);
    // A caller outside Mr. Mak is labelled by its sanitized name.
    const outside = await call('/agent/chats/chat-b/send', { method: 'POST', body: JSON.stringify({ text: 'Hello.', sender: 'Build <script> bot' }) });
    assert.equal(outside.status, 200);
    assert.match(writes.at(-1) === '\r' ? writes.at(-2) : writes.at(-1), /\[Message from Build script bot \(outside Mr\. Mak\)/);
  } finally { await service.close(); }
});

test('messages wait for an idle chat without prompts or an unsent draft', () => {
  const now = Date.parse('2026-10-25T12:00:00Z'), at = minutes => new Date(now - minutes * 60000).toISOString();
  const base = { id: 'chat-b', name: 'Wolf Scouts', agent: 'codex', open: true, status: 'running', process: {}, activity: 'idle' };
  assert.equal(sendRefusal(base, '› ', { from: 'chat-a', now }), null);
  assert.match(sendRefusal({ ...base, activity: 'working' }, '', { now }), /middle of a turn/);
  assert.match(sendRefusal({ ...base, activity: 'waiting' }, '', { now }), /permission prompt/);
  assert.match(sendRefusal(base, menu, { now }), /permission prompt/);
  assert.match(sendRefusal(base, '', { from: 'chat-b', now }), /itself/);
  assert.match(sendRefusal({ ...base, agent: 'shell' }, '', { now }), /agent chats/);
  assert.match(sendRefusal({ ...base, open: false }, '', { now }), /agent chats/);
  assert.match(sendRefusal({ ...base, process: null, status: 'stopped' }, '', { now }), /not running/);
  assert.match(sendRefusal({ ...base, lastInputAt: at(1), lastSubmitAt: at(5) }, '', { now }), /unsent draft/);
  assert.match(sendRefusal({ ...base, lastInputAt: at(1) }, '', { now }), /unsent draft/);
  assert.equal(sendRefusal({ ...base, lastInputAt: at(5), lastSubmitAt: at(1) }, '', { now }), null);
  // A menu answer followed by a new turn, and an old keystroke, are not drafts.
  assert.equal(sendRefusal({ ...base, lastInputAt: at(5), lastSubmitAt: at(9), turnStartedAt: at(4) }, '', { now }), null);
  assert.equal(sendRefusal({ ...base, lastInputAt: at(20), lastSubmitAt: at(30) }, '', { now }), null);
});

test('the service refuses busy chats, oversized messages and message bursts', async () => {
  const { service, chat, call } = await fixture();
  const send = (id, text, from = 'chat-a') => call(`/agent/chats/${id}/send`, { from, method: 'POST', body: JSON.stringify({ text }) });
  try {
    await chat('chat-a', 'Coordinator');
    const { writes } = await chat('chat-b', 'Wolf Scouts');
    const { session: busy, writes: busyWrites } = await chat('chat-e', 'Boss fights', 'codex', { activity: 'working' });
    const { session: asking, writes: askingWrites } = await chat('chat-f', 'Menus', 'codex');
    await new Promise(resolve => asking.terminal.write(menu.replaceAll('\n', '\r\n'), resolve));
    assert.equal((await send('chat-e', 'Hello.')).status, 409);
    const prompt = await send('chat-f', 'Hello.');
    assert.equal(prompt.status, 409); assert.match((await prompt.json()).error, /only the user may answer/);
    assert.equal((await send('chat-a', 'Hello.')).status, 409);
    assert.equal((await send('chat-b', 'x'.repeat(MAX_AGENT_MESSAGE + 1))).status, 413);
    assert.equal((await send('chat-b', '   ')).status, 400);
    assert.equal((await send('missing', 'Hello.')).status, 404);
    busy.activity = 'idle'; busy.lastInputAt = new Date().toISOString();
    assert.match((await (await send('chat-e', 'Hello.')).json()).error, /unsent draft/);
    assert.deepEqual([busyWrites, askingWrites], [[], []]);
    for (let index = 0; index < 12; index++) assert.equal((await send('chat-b', `Note ${index}.`)).status, 200);
    const burst = await send('chat-b', 'One more.');
    assert.equal(burst.status, 429);
    assert.equal(writes.filter(data => data.startsWith('\x1b[200~')).length, 12);
  } finally { await service.close(); }
});

test('chat names resolve to one chat', () => {
  const chats = [{ id: 'a1', name: 'Rigging Wolf Scouts' }, { id: 'b2', name: 'Rigging Mage characters' }, { id: 'c3', name: 'BOSS fights' }];
  assert.equal(findChat(chats, 'b2').id, 'b2');
  assert.equal(findChat(chats, 'boss fights').id, 'c3');
  assert.equal(findChat(chats, 'wolf').id, 'a1');
  assert.throws(() => findChat(chats, 'rigging'), /matches 2 chats/);
  assert.throws(() => findChat(chats, 'camp'), /No open chat/);
  assert.throws(() => findChat(chats, ' '), /Name the chat/);
});

test('the chats MCP server lists, reads and messages chats over stdio', async () => {
  const { service, chat } = await fixture();
  const client = new Client({ name: 'agent-channel-test', version: '1.0.0' });
  try {
    await chat('chat-a', 'Coordinator');
    const { session: wolf, writes } = await chat('chat-b', 'Rigging Wolf Scouts');
    await new Promise(resolve => wolf.terminal.write('Pose viewer ready.\r\n', resolve));
    await client.connect(new StdioClientTransport({ command: process.execPath, args: [server], env: { ...getDefaultEnvironment(), MRMAK_STATE: path.dirname(service.channel.file), MRMAK_CHAT_ID: 'chat-a' }, stderr: 'pipe' }));
    assert.deepEqual((await client.listTools()).tools.map(tool => tool.name), ['list_chats', 'read_chat', 'send_to_chat']);
    assert.match(client.getInstructions(), /never grant approval/);
    const listed = JSON.parse((await client.callTool({ name: 'list_chats', arguments: {} })).content[0].text);
    assert.deepEqual(listed.chats.map(item => [item.name, !!item.self]), [['Coordinator', true], ['Rigging Wolf Scouts', false]]);
    const read = await client.callTool({ name: 'read_chat', arguments: { chat: 'wolf', lines: 10 } });
    assert.match(read.content[0].text, /^Rigging Wolf Scouts \(codex, running, idle\)[\s\S]*Pose viewer ready\./);
    const own = await client.callTool({ name: 'send_to_chat', arguments: { chat: 'Coordinator', message: 'Hello.' } });
    assert.equal(own.isError, true);
    const sent = await client.callTool({ name: 'send_to_chat', arguments: { chat: 'Rigging Wolf Scouts', message: 'Please add a pose viewer.' } });
    assert.ok(!sent.isError, sent.content[0].text);
    assert.match(writes[0], /\[Message from Coordinator \(codex chat\)[^\n]*\]\nPlease add a pose viewer\./);
    await service.close();
    const closed = await client.callTool({ name: 'list_chats', arguments: {} });
    assert.equal(closed.isError, true);
    assert.match(closed.content[0].text, /not running/);
  } finally { await client.close(); await service.close(); }
});
