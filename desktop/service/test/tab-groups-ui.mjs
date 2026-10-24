// Grouped report tabs in the real Workspace window: the rail beside the report,
// the top bar limited to one group or subgroup, a group that opens to list its
// subgroups, returning to the last tab of each, the card menu above the rail and
// the narrow layout. Isolated repository and service.
import assert from 'node:assert/strict';
import { expect } from '@playwright/test';
import { mkdtemp, mkdir, writeFile, cp } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createService } from '../server.mjs';
import { launchBrowser } from './browser.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
await mkdir(path.join(root, '.cache'), { recursive: true });
const repo = await mkdtemp(path.join(root, '.cache/tab-groups-ui-'));
await mkdir(path.join(repo, 'workspace/test'), { recursive: true });
const rigs = (name, subgroup) => ({ name, group: 'Character rigs', ...(subgroup && { subgroup }) });
// Registry order deliberately interleaves subgroups; the rail gathers them.
const steps = [
  { name: 'Main 1' }, { name: 'Main 2' }, { name: 'Main 3' }, { name: 'Main 4' },
  rigs('Footman study', 'Footman'), rigs('Mixar', 'Shared'), rigs('Footman rig', 'Footman'),
  rigs('Crossbowman rig', 'Crossbowman'), { name: 'Tools', group: 'Tools' }, rigs('Loose rig'),
].map((step, index) => ({ ...step, path: `step${index}.html` }));
// The first report asks the app for other tabs of its card, as the Meridius game guide does.
const ask = target => `parent.postMessage({ type: 'mrmak:open-step', path: '${target}' }, '*')`;
const opener = `<a href="step6.html" onclick="event.preventDefault(); ${ask('step6.html')}">Open Footman rig</a> <button onclick="${ask('nowhere.html')}">Open nothing</button>`;
for (const [index, step] of steps.entries()) await writeFile(path.join(repo, 'workspace/test', step.path), `<h1>Document ${index + 1}</h1><p>Readable content.</p>${index === 0 ? opener : ''}`);
const card = { type: 'group', category: 'test', created: '2026-10-23', updated: '2026-10-23', folder: 'test', status: 'active', description: 'Tab groups.' };
await writeFile(path.join(repo, 'workspace/workspace.json'), JSON.stringify({ entities: [
  { ...card, id: 'test', title: 'Grouped card', steps, defaultStep: 0 },
  { ...card, id: 'plain', title: 'Plain card', steps: steps.map(({ name, path }) => ({ name, path })) },
] }));
await cp(path.join(root, 'public/assets'), path.join(root, 'dist/assets'), { recursive: true });
let service, browser;
try {
  service = await createService({ repo, uiDir: path.join(root, 'dist'), mcpOptions: { home: repo, env: {} } });
  browser = await launchBrowser();
  const page = await (await browser.newContext({ viewport: { width: 1280, height: 820 } })).newPage();
  page.setDefaultTimeout(10000);
  const errors = []; page.on('pageerror', error => errors.push(error.message));
  const rail = page.getByRole('navigation', { name: 'Tab groups' });
  const groupCard = name => rail.locator('.step-group:not(.step-subgroup)', { hasText: name });
  const subCard = name => rail.locator('.step-subgroup', { hasText: name });
  const cardNames = selector => rail.locator(`${selector} .step-group-name`).allTextContents();
  const tabs = () => page.getByRole('tab').allTextContents();
  const showing = async (hash, tab, document) => {
    await expect(page.getByRole('tab', { selected: true })).toHaveText(tab);
    await page.frameLocator('iframe.report-frame').getByRole('heading', { name: document, exact: true }).waitFor();
    assert.equal(new URL(page.url()).hash, hash);
  };

  // A subgrouped tab opens its group, with the subgroups listed beneath it.
  await page.goto(service.urls.workspace + '#/test/7');
  await showing('#/test/7', 'Crossbowman rig', 'Document 8');
  assert.deepEqual(await cardNames('.step-group:not(.step-subgroup)'), ['Grouped card', '▾Character rigs', 'Tools']);
  assert.deepEqual(await cardNames('.step-subgroup'), ['Footman', 'Shared', 'Crossbowman', 'Other']);
  assert.deepEqual(await rail.locator('.step-group-count').allTextContents(), ['4 tabs', '5 tabs', '2 tabs', '1 tab', '1 tab', '1 tab', '1 tab']);
  await expect(groupCard('Character rigs')).toHaveAttribute('aria-expanded', 'true');
  await expect(subCard('Crossbowman')).toHaveAttribute('aria-pressed', 'true');
  assert.deepEqual(await tabs(), ['Crossbowman rig']);

  // The rail sits under the top bar and left of the report, clear of the menu nose.
  const [bar, side, frame, nose] = await Promise.all(['.topbar', '.step-groups', '.content', '.sidebar-reopen'].map(selector => page.locator(selector).boundingBox()));
  assert.ok(side.y >= bar.y + bar.height - 1, 'rail below the top bar');
  assert.ok(frame.x >= side.x + side.width - 1, 'report right of the rail');
  assert.ok(nose.y + nose.height <= side.y, 'menu nose above the rail');
  const [parent, child] = await Promise.all([groupCard('Character rigs').boundingBox(), subCard('Footman').boundingBox()]);
  assert.ok(child.x > parent.x && child.y > parent.y, 'subgroups indented beneath their group');

  await subCard('Footman').click();
  await showing('#/test/4', 'Footman study', 'Document 5');
  assert.deepEqual(await tabs(), ['Footman study', 'Footman rig']);
  await page.getByRole('tab', { name: 'Footman rig' }).click();
  await showing('#/test/6', 'Footman rig', 'Document 7');
  await subCard('Crossbowman').click();
  await showing('#/test/7', 'Crossbowman rig', 'Document 8');
  await subCard('Footman').click();
  await showing('#/test/6', 'Footman rig', 'Document 7');

  // The main card folds the group away; the group card returns to its last tab.
  await groupCard('Grouped card').click();
  await showing('#/test/0', 'Main 1', 'Document 1');
  assert.deepEqual(await tabs(), ['Main 1', 'Main 2', 'Main 3', 'Main 4']);
  await expect(rail.locator('.step-subgroup')).toHaveCount(0);
  await expect(groupCard('Character rigs')).toHaveAttribute('aria-expanded', 'false');
  await page.getByRole('tab', { name: 'Main 3' }).click();
  await showing('#/test/2', 'Main 3', 'Document 3');
  await groupCard('Character rigs').click();
  await showing('#/test/6', 'Footman rig', 'Document 7');
  await expect(subCard('Footman')).toHaveAttribute('aria-pressed', 'true');
  await subCard('Other').click();
  await showing('#/test/9', 'Loose rig', 'Document 10');
  await groupCard('Tools').click();
  await showing('#/test/8', 'Tools', 'Document 9');
  await expect(rail.locator('.step-subgroup')).toHaveCount(0);
  await expect(groupCard('Tools')).toHaveAttribute('aria-pressed', 'true');
  await groupCard('Grouped card').click();
  await showing('#/test/2', 'Main 3', 'Document 3');

  // The card menu in the top bar still opens where it belongs.
  const status = page.getByRole('button', { name: /^Edit Grouped card:/ });
  await status.click();
  const menu = page.getByRole('dialog', { name: 'Card settings: Grouped card' });
  await expect(menu).toBeVisible();
  const [button, dialog] = await Promise.all([status.boundingBox(), menu.boundingBox()]);
  assert.ok(Math.abs(dialog.y - (button.y + button.height)) < 40 && dialog.x >= 0 && dialog.x + dialog.width <= 1280, 'card menu under its button');
  await page.keyboard.press('Escape');
  await expect(menu).toHaveCount(0);

  // A report opens another tab of its own card by path, into that tab's group.
  // Unknown paths and messages that don't come from the report frame do nothing.
  await page.goto(service.urls.workspace + '#/test/0');
  await showing('#/test/0', 'Main 1', 'Document 1');
  const report = page.frameLocator('iframe.report-frame');
  await report.getByRole('button', { name: 'Open nothing' }).click();
  assert.equal(await page.evaluate(() => new Promise(resolve => {
    window.postMessage({ type: 'mrmak:open-step', path: 'step8.html' }, '*');
    setTimeout(() => resolve(location.hash), 100);
  })), '#/test/0');
  await report.getByRole('link', { name: 'Open Footman rig' }).click();
  await showing('#/test/6', 'Footman rig', 'Document 7');
  await expect(subCard('Footman')).toHaveAttribute('aria-pressed', 'true');
  await groupCard('Grouped card').click();
  await showing('#/test/0', 'Main 1', 'Document 1');

  // A card without groups keeps the full top bar and no rail.
  await page.goto(service.urls.workspace + '#/plain/5');
  await showing('#/plain/5', 'Mixar', 'Document 6');
  await expect(rail).toHaveCount(0);
  assert.equal((await tabs()).length, 10);

  // A card link without a step opens the default tab, in its group.
  await page.goto(service.urls.workspace + '#/test');
  await expect(page.getByRole('tab', { selected: true })).toHaveText('Main 1');
  await expect(groupCard('Grouped card')).toHaveAttribute('aria-pressed', 'true');

  // Narrow window: one strip above the report, subgroups after their group. The
  // page was reloaded, so the group opens on its first subgroup.
  await page.setViewportSize({ width: 560, height: 800 });
  await groupCard('Character rigs').click();
  await showing('#/test/4', 'Footman study', 'Document 5');
  const [strip, content, first, sub] = await Promise.all([page.locator('.step-groups'), page.locator('.content'), groupCard('Grouped card'), subCard('Footman')].map(item => item.boundingBox()));
  assert.ok(strip.y + strip.height <= content.y + 1 && strip.width > 500, 'strip above the report');
  assert.ok(Math.abs(sub.y - first.y) < 2 && sub.x > first.x, 'subgroups in the same strip');

  assert.equal(await page.locator('.desktop-error').count(), 0);
  assert.deepEqual(errors, []);
  await page.screenshot({ path: path.join(repo, 'tab-groups-narrow.png') });
  await page.setViewportSize({ width: 1280, height: 820 });
  await page.screenshot({ path: path.join(repo, 'tab-groups.png') });
  console.log(`Tab groups UI passed: rail, filtered top bar, subgroups that open and fold, last tab per group and subgroup, Other subgroup, card menu, tabs opened from a report, ungrouped card, default tab and narrow strip. Screenshots: ${repo}`);
} finally {
  await browser?.close(); await service?.close();
}
