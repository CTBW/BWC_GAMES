# Handoff

## Goal
Continue the Meridius squad-skills work in the Godot port. The skills are done, committed, pushed and merged. What's left is waiting on other sessions or the owner (see "Open problems").

Kits:
- **Footmen:** Charge (`shield_charge`), Defend (`defend`), Shield Wall; Shield Bash on promotion.
- **Spearmen:** Spear Wall, Square (`square`).
- **Crossbowmen:** Overwatch, Aimed Shot (`aimed_shot`).
- **Border Collie Royal Guard:** Growl (`growl`), Charge (`hound_charge`), Defend, Lick Wounds (`lick_wounds`). Promotion turns Growl into Howl (`howl`).

## Where things are
- **Repo:** `E:\ProjektM\BWC_GAMES-godot`, branch `godot-migration` (local, tracks `origin/godot-migration`; local HEAD `5e91486` at the time of writing).
- **Remote:** `https://github.com/CTBW/BWC_GAMES`. GitHub reports it as **public**.
- **Godot project:** `projects/meridius/source/godot`.
- **Spec:** `projects/meridius/docs/squad-skills.md`.
- **Log:** `MIGRATION.md` in the Godot project, section "Squad skills (22 Oct 2026, Godot only)" with its "Follow-up, 23 Oct 2026" list.
- **Earlier handoffs:**
  - `inbox/handoffs/2026-10-24-meridius-add-combat-skills-committed-4c8d0d1a.md`: committed and force-added, since `inbox/*` is gitignored. Read it first.
  - Older, untracked: `inbox/handoffs/2026-10-24-meridius-add-combat-skills-continued-63018e7b.md`, `inbox/handoffs/2026-10-23-meridius-add-combat-skills-9e489a85.md`.
- **This chat's transcript:** `C:\Users\calle\.claude\projects\E--ProjektM-BWC-GAMES-godot\4c8d0d1a-70a7-4e4c-a22e-95b16220332c.jsonl` (session bwc-games-godot-8e).

## Current state
- **Commits:**
  - `3d28cfa`: the squad skills.
  - `8b191bb`: the handoff.
- **Push:** I pushed up to `8b191bb`, which created the remote branch. Other sessions then pushed `132353c`, `f6c6e32`, `1f5be46` and `5e91486`, and set the upstream.
- **Pull request #1:** https://github.com/CTBW/BWC_GAMES/pull/1, "Meridius in Godot: the port, squad skills and Workspace updates". Merged into `main` at 2026-10-24T12:46:22Z as merge commit **`998b436`**, a merge commit pinned to head `5e91486`. The branch was kept.
  - The local `main` was not updated.
- **GitHub CLI:** logged in as CTBW (keyring, scopes gist/read:org/repo). `gh` works now.
- **Tests:**
  - Full `tools/test.sh` on the committed skills tree (sparse temp worktree, HEAD plus the staged diff): **358 passed, 0 failed, 0 skipped**, including campaign, battle and meta parity.
  - Shared working tree, quick run: 394 passed, 1 failed. The failure is the known shader error from another session's `battle_sorted.gdshader`.
  - Not re-run at the branch tip. The later commits are art sources, report tabs and notes. `project.godot` has `import/blender/enabled=false`, so `art/spearman_3d/*.blend` isn't imported.
- **Uncommitted in the working tree:**
  - **Ours:** only the Howl branch in `scripts/render/battle_view.gd`'s `"shout"` case, at about line 1249: `elif e.ability == "growl" or e.ability == "howl":` with the rings scaled by `k = radius / 2`. It sits inside the animation session's roughly 750 uncommitted lines in that file.
  - **Not ours:** another session is editing `tests/visual/capture_skills.gd` (a new `charge_square` shot showing a Charge forecast against a square, +23/−5 lines). Leave it to that session.
- **No running processes.** The temporary worktree is gone.

## Decisions and reasons
- **Defend:** a bodyguard that catches one blow per turn (`guardSpent`), the owner's choice. Shield Bash stays the footmen's promotion. The Royal Guard is promoted to Howl, which replaces Growl through `"upgrades": "growl"` and `Soldier.kit()` so the bar keeps 4 keys. No balance tuning.
- **Partial staging:** `battle.gd`, `ai.gd`, `hud_battle_panels.gd`, `test_battle_hud.gd` and `MIGRATION.md` also hold fog-of-war and dark-panel HUD work from other sessions. Only the skills hunks were committed, via `git apply --cached --recount` on filtered diffs, so others' unfinished work stayed out. The staged tree was tested on its own before committing.
- **`battle_view.gd` not committed:** it is the animation session's file, and Growl's own branch there is still uncommitted.
- **Campaign golden:** the skills don't change it, as the full suite on the skills-only tree passed. The parity failures in the shared tree come from fog of war, whose re-recording the owner keeps **on hold**. MIGRATION.md was corrected to say so.
- **Removed meta parity special case:** `test_meta_parity.gd` no longer has the Royal Guard `canPromote` case; it was a no-op once Howl existed.
- **Pushing and merging:** I pushed only up to our handoff commit, so other sessions decide their own. The pull request used a merge commit, not squash or rebase, to keep the SHAs that handoffs cite. I didn't delete the branch, because other sessions still use it.
- **Handoff file force-added:** `inbox/handoffs/2026-10-24-meridius-add-combat-skills-committed-4c8d0d1a.md` is the only tracked file in `inbox/`. The owner was told and can undo it. This handoff file is not committed.

## Files touched this chat
Paths are relative to `projects/meridius/source/godot` unless marked.
- **Committed:**
  - `tests/visual/capture_skills.gd` (the `use_howl` shot)
  - `tests/parity/test_meta_parity.gd`
  - `MIGRATION.md` (our section only)
  - `projects/meridius/docs/squad-skills.md` (repo-relative)
  - `inbox/handoffs/2026-10-24-meridius-add-combat-skills-committed-4c8d0d1a.md` (repo-relative)
- **Uncommitted:** `scripts/render/battle_view.gd` (the Howl branch only).
- **Scratchpad:** `C:\Users\calle\AppData\Local\Temp\claude\E--ProjektM-BWC-GAMES-godot\4c8d0d1a-70a7-4e4c-a22e-95b16220332c\scratchpad\` holds:
  - `pick_hunks.py`
  - the `skills_*.diff` files
  - `wt_full_test.txt`
  - `pr_body.md`

## Open problems
1. **Howl's visual is uncommitted** until the animation session commits `battle_view.gd`. Until then `main` plays War Cry's effect and sound for Howl.
2. **Howl's sound** reuses the growl `roar`; the audio session may want a howl.
3. **Minor quirks:**
   - The forecast row "Charge broken by the square" shows 0. The other session's new `charge_square` capture may be looking at this.
   - The guard note only appears for enemies that have Defend.
   - Charge aiming only tries the side under the cursor (`battle_view._preview_against`, the animation session's file).
   - The HUD unit-panel cache can leave the Lick Wounds button stale.
4. **Skill effects** per the spec's "Visual direction" are not done.
5. **Fog-of-war baseline:** re-recording it is on hold by the owner.
6. **Shader error** (`custom_samplers`, `scenes/battle/battle_sorted.gdshader`): belongs to another session.

## Next steps
1. Wait for the owner's direction. Nothing is pending.
2. **To commit the Howl visual:** coordinate with the animation session, which owns `battle_view.gd`. Never commit that file alone or revert it.
3. **New pull request:** if more work lands on `godot-migration`, a new one is needed. Run `gh pr create --repo CTBW/BWC_GAMES --base main --head godot-migration …`. Merge with `gh pr merge <n> --repo CTBW/BWC_GAMES --merge --match-head-commit <full sha>`, never with `--delete-branch`.
4. **If the owner lifts the fog-of-war hold:** run `MERIDIUS_RECORD=1 tools/test.sh test_battle_parity test_campaign_parity` from the Godot project, after checking with the fog session, and record it in MIGRATION.md.
5. **Rules for any change:**
   - Run `tools/test.sh --quick` after the change and the full `tools/test.sh` before committing.
   - Stage by explicit path only; never `git add -A` or `git add .`. Never stage `assets/audio/bank/local/`.
   - Commit with `git -c user.name=CTBW -c user.email=135850159+CTBW@users.noreply.github.com commit …`, ending the message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
   - Pull request descriptions end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
6. **Testing a partial staging on its own:**
   - Set up a sparse worktree in the scratchpad: `git worktree add --no-checkout --detach <dir> HEAD`, then `git -C <dir> sparse-checkout set projects/meridius/source/godot` and `git -C <dir> checkout --detach HEAD`.
   - Apply `git diff --cached --binary`, run `tools/import.sh`, then `tools/test.sh`.
   - Remove the worktree with PowerShell `Remove-Item -LiteralPath "\\?\<path>" -Recurse -Force` (Windows path-length limit).

## Other notes
- Session bwc-games-godot-c6 broadcasts about the footman 3D rig. Ignore them and don't touch `art/footman_3d/` or `prototypes/footman_anim/`.
- Older scratchpads:
  - `C:\Users\calle\AppData\Local\Temp\claude\E--ProjektM-BWC-GAMES-godot\7891c9ab-6aeb-4e1f-b744-74b89d60f6b9\scratchpad\` (icon sheet, Howl drafts)
  - `C:\Users\calle\AppData\Local\Temp\claude\D--ProjektM-BWC-GAMES-godot\d379d718-21fd-4cfc-b9d9-cf230a9e35de\scratchpad\` (balance tools)

---
From the Claude Code chat continuing "Meridius - Add combat skills" in E:\ProjektM\BWC_GAMES-godot, 2026-10-24.
