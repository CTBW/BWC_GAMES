# Handoff

## Result
The squad skills are finished and on `main`, together with the two quirk fixes from a parallel chat. `main` has been fast-forwarded locally, and every squad-skills commit and handoff is merged. Nothing is pending. What's left waits on the owner or other sessions.

Kits:
- **Footmen:** Charge, Defend, Shield Wall; Shield Bash on promotion.
- **Spearmen:** Spear Wall, Square.
- **Crossbowmen:** Overwatch, Aimed Shot.
- **Border Collie Royal Guard:** Growl, Charge, Defend, Lick Wounds. Promotion turns Growl into Howl.

## Read first
- `inbox/handoffs/2026-10-24-meridius-add-combat-skills-continued-372d9c5f.md` (parallel chat, merged in `eb60186`): the latest detail on the work itself.
  - The forecast for a Charge against a square now shows two rows: the charge bonus and "Charge broken by the square" taking it back.
  - The Lick Wounds button now updates while the hounds stay selected.
  - It also documents `stage_mine.py` for staging mixed files and the test results for `72e345c`.
- **Superseded:** `inbox/handoffs/2026-10-24-meridius-add-combat-skills-merged-4c8d0d1a.md` (this chat's earlier handoff). Its quirks "forecast row shows 0" and "Lick Wounds button stale" are fixed. The "other session editing `capture_skills.gd`" was the parallel chat, and that work is committed.
- **Spec:** `projects/meridius/docs/squad-skills.md`.
- **Log:** `projects/meridius/source/godot/MIGRATION.md`, "Squad skills (22 Oct 2026, Godot only)" and its "Follow-up, 23 Oct 2026" list.

## Where things are
- **Repo:** `E:\ProjektM\BWC_GAMES-godot`, branch `godot-migration`, which tracks `origin/godot-migration`. Many sessions share this working tree.
- **Remote:** `https://github.com/CTBW/BWC_GAMES`. GitHub reports it as **public**.
- **GitHub CLI:** logged in as CTBW (keyring, scopes gist/read:org/repo).
- **This chat's transcript:** `C:\Users\calle\.claude\projects\E--ProjektM-BWC-GAMES-godot\4c8d0d1a-70a7-4e4c-a22e-95b16220332c.jsonl` (session bwc-games-godot-8e).

## Current state
- **Pull requests into `main`:** all are merge commits pinned with `--match-head-commit`, and the branch was kept each time.

  | PR | Contents | Merge commit |
  | --- | --- | --- |
  | #1 | The Godot port, squad skills `3d28cfa`, Workspace (16 commits) | `998b436` |
  | #2 | Square forecast and Lick Wounds fixes `72e345c` (parallel chat) | `ced94b0` |
  | #3 | Our handoff `6499291`, spearman helper scripts `aa697b4` | `8c48b6e` |
  | #4 | Handoffs `0d1f8cb` (spearman rig) and `eb60186` (squad skills) | `5685313` |

- **`main`:** `origin/main` = `5685313`, and local `main` was fast-forwarded to match without switching branches.
- **Branch ahead of `main`:** `origin/godot-migration` = `5c0b3b3`, two commits from other chats that are pushed but not merged:
  - `78047b8`, the succubus 3D rig, under `art/succubus_3d/`. Its `review/godot_sandbox/` holds 14 review PNGs only, with no `.gd`, `.tscn` or `project.godot`. Godot will import them as textures.
  - `5c0b3b3`, which ignores `jobs.json` receipts in `.gitignore`.
- **Tests:**
  - Full `tools/test.sh` on our committed skills tree: 358 passed, 0 failed, 0 skipped.
  - The parallel chat's `72e345c` on its own: 358 passed, 0 failed, 0 skipped.
  - Pull requests #3 and #4 changed no game files, so the suite was not re-run for them.
  - Shared working tree, quick run: only the known `custom_samplers` shader error, from another session's `scenes/battle/battle_sorted.gdshader`.
- **Uncommitted, ours:** only the Howl branch in `projects/meridius/source/godot/scripts/render/battle_view.gd`, at about line 1258: `elif e.ability == "growl" or e.ability == "howl":` with the rings scaled by `k = radius / 2`. It sits inside the animation session's uncommitted view work in that file.
- **No running processes or temporary worktrees.**

## Decisions and reasons
- **Owner's rule calls:**
  - Defend catches one blow per turn.
  - Shield Bash stays the footmen's promotion.
  - Howl replaces Growl on promotion (`"upgrades"`), so the bar keeps 4 keys.
  - No balance tuning.
  - The fog-of-war baseline is on hold.
- **Mixed files:** commit only our hunks; other sessions' fog-of-war, dark-panel HUD and view work stays uncommitted for them. Test the staged tree on its own before committing.
- **Merge commits only, no branch deletion:** handoffs cite commit SHAs, and other sessions keep working on `godot-migration`.
- **Pushing and pull requests:** check the contents first. The repo is public, so scan new files for tokens or keys. Pin the merge to the head that was checked.
- **Handoffs in `inbox/handoffs`:** force-added when committed, since `inbox/*` is gitignored. The owner knows. This handoff is not committed.

## Open problems
1. **Howl's visual** is uncommitted until the animation session commits `battle_view.gd`. Until then `main` plays War Cry's effect and sound for Howl.
2. **Howl's sound** reuses the growl's `roar`.
3. **The guard note** never appears in play, because no enemy kit has Defend. This is the owner's call.
4. **Charge aiming** only tries the side under the cursor (`battle_view._preview_against`, the animation session's file).
5. **Skill effects** from the spec's "Visual direction" are not done.
6. **Fog-of-war baseline:** re-recording is on hold by the owner.
7. **The shader error** in `battle_sorted.gdshader` is another session's.

## Next steps
1. Wait for the owner's direction.
2. **If asked to bring `main` up to date:**
   - `git fetch origin`, then list `git log origin/main..origin/godot-migration` and the changed files. Today that is `78047b8` and `5c0b3b3`, plus anything pushed since.
   - Scan new files for secrets.
   - Open the pull request with `gh pr create --repo CTBW/BWC_GAMES --base main --head godot-migration --title … --body-file …`.
   - Merge with `gh pr merge <n> --repo CTBW/BWC_GAMES --merge --match-head-commit <full sha>`, never `--delete-branch`.
   - If anything touches game files (`.gd`, `.tscn`, `.tres`, `.gdshader`, `data/*.json`, `project.godot`), run the full `tools/test.sh` on that exact head first, in a sparse worktree (see the 372d9c5f handoff).
3. **To update local `main` without leaving the branch:** `git fetch origin main:main`. It refuses anything but a fast-forward. Never check out `main` in the shared working tree.
4. **To commit the Howl visual:** coordinate with the animation session, which owns `battle_view.gd`. Never commit that file alone or revert it.
5. **Commits:**
   - Run `git -c user.name=CTBW -c user.email=135850159+CTBW@users.noreply.github.com commit …`, ending the message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
   - Pull request descriptions end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
   - Stage by explicit path only; never `git add -A` or `git add .`. Never stage `assets/audio/bank/local/`.

## Scratchpad
`C:\Users\calle\AppData\Local\Temp\claude\E--ProjektM-BWC-GAMES-godot\4c8d0d1a-70a7-4e4c-a22e-95b16220332c\scratchpad\` holds:
- `pick_hunks.py`
- `skills_*.diff`
- `wt_full_test.txt`
- `pr_body.md`, `pr3_body.md`, `pr4_body.md`

---
From the Claude Code chat continuing "Meridius - Add combat skills" in E:\ProjektM\BWC_GAMES-godot, 2026-10-24.
