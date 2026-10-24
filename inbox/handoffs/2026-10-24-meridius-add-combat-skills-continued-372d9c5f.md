# Handoff

## Result
Two leftovers from the squad skills are fixed, committed, merged into `main` and verified:
- **Charge against a square:** the attack forecast no longer shows a 0 row. It lists the charge's own row (+5 footmen, +12 hounds), then "Charge broken by the square" taking it back (−5 / −12). The rows add up to the chance shown; odds, damage and morale are unchanged.
- **Lick Wounds button:** it greys out when an enemy steps beside the selected hounds and comes back when the enemy leaves, without reselecting the squad.

Nothing is pending. What's left waits on the owner or other sessions (see "Open problems").

## Where things are
- **Repo:** `E:\ProjektM\BWC_GAMES-godot`, branch `godot-migration`, tracks `origin/godot-migration`. Remote `https://github.com/CTBW/BWC_GAMES` (public).
- **Godot project:** `projects/meridius/source/godot`. Spec: `projects/meridius/docs/squad-skills.md`.
- **Log:** `MIGRATION.md`, section "Squad skills (22 Oct 2026, Godot only)", "Follow-up, 23 Oct 2026" list. The last bullet, "Two forecast and panel quirks (24 Oct 2026)", is this chat's.
- **Earlier handoffs for this work:**
  - `inbox/handoffs/2026-10-24-meridius-add-combat-skills-continued-c4f61b66.md` (this chat started from it).
  - `inbox/handoffs/2026-10-24-meridius-add-combat-skills-merged-4c8d0d1a.md`, committed in `6499291` by a parallel chat. It predates `72e345c`. Its items "the forecast row … shows 0" and "the HUD unit-panel cache can leave the Lick Wounds button stale" are done. The "another session" editing `capture_skills.gd` was this one, and that work is committed. This handoff supersedes those lines.
- **This chat's transcript:** `%USERPROFILE%\.claude\projects\E--ProjektM-BWC-GAMES-godot\372d9c5f-2327-4342-83c1-dd4f0eabbbc0.jsonl`.

## Current state
- **Commit `72e345c`:** "Meridius Godot: a square's broken charge in the forecast, a live Lick Wounds button". 6 files, +51/−12.
- **Pull request #2:** https://github.com/CTBW/BWC_GAMES/pull/2. Merged at 2026-10-24T13:23:16Z as merge commit **`ced94b0`**, pinned to head `72e345c`. The branch was kept. `main` = `ced94b0`.
- **The branch since then:** other chats pushed `6499291` (the parallel squad-skills handoff) and `aa697b4` (spearman helper scripts). `origin/godot-migration` = `aa697b4`, and the local branch matches it. Neither commit is on `main`.
- **Local `main`:** not updated. It is still behind `origin/main`.
- **Tests:**
  - Full `tools/test.sh` on `72e345c`'s changes alone (sparse worktree, `HEAD` 5e91486 plus the staged diff): **358 passed, 0 failed, 0 skipped** (381 s). That includes `test_battle_parity`, `test_campaign_parity` and `test_meta_parity`.
  - Shared working tree, `tools/test.sh --quick`: 398 passed, 1 failed, 10 skipped. The failure is the known `custom_samplers` shader error from `scenes/battle/battle_sorted.gdshader` (another session's). It lands on whichever test compiles that shader first: `test_audio` in the full quick run, `test_battle_hud::test_deployment` when run alone.
  - One combined run of `test_squad_skills test_battle_hud` failed `test_battle_hud::test_spell_buttons_and_unit_panel` once. It passed in three reruns and in the full quick run. It was treated as a one-off and not investigated.
- **Visual check:**
  - Ran `tools/godot.sh --path . --resolution 1920x1080 -s res://tests/visual/capture_skills.gd -- charge_forecast charge_square` and looked at both PNGs.
  - Plain Charge: Flank, 93%, 60–78, "Charge +12".
  - Against a square: Frontal, 65%, 48–66, morale −18, rows 76 −16 +5 +12 −12.
  - Output is in `tests/visual/out/skills_charge_*.png` (gitignored).
- **Uncommitted, ours:** none from this chat. The Howl branch in `scripts/render/battle_view.gd` (line ~1258, `elif e.ability == "growl" or e.ability == "howl":`) is from the earlier chat and still sits in the animation session's uncommitted file.
- **Running processes:** none. The temporary worktree is removed and pruned.

## What changed (all under `projects/meridius/source/godot`)
- `scripts/rules/battle.gd`, `preview()`: the charge's `hitMod` row is always added. When `_charge_broken(ab, d)`, a second row `["Charge broken by the square", -hitMod]` takes it back. The previous code skipped the bonus and added a 0 row; the chance is the same.
- `scripts/ui/battle_hud.gd`, `_refresh_unit()`: the panel signature also carries `b.can_shout(sel, a).reason` for every shout in the kit. `can_cast` needed nothing, since everything it reads is already in the signature.
- `tests/unit/test_squad_skills.gd`: checks rows `Charge = 5` and `Charge broken by the square = -5`.
- `tests/unit/test_battle_hud.gd`, `test_squad_skill_buttons`: no longer reselects another squad to force a rebuild. It moves the foe beside the hounds, then back, and checks the button both ways.
- `tests/visual/capture_skills.gd`:
  - The Charge shot now places the nearest enemy 3 tiles from the hounds along a clear straight line. It had stood 7 tiles off, beyond the hounds' move of 5, and showed "Not adjacent".
  - New `charge_square` shot: the same target with `stance = "square"`.
- `MIGRATION.md`: the follow-up bullet.

## Decisions and reasons
- **Two rows, not one negative row:** forecast rows are meant to add up to the chance. A lone −12 row with no +12 row would not.
- **Guard note left alone:** it appears only when attacking an enemy guarded by Defend, and no enemy kit has Defend. Adding it is a design call for the owner, not a bug fix.
- **Staging by index blobs:** `battle.gd`, `battle_hud.gd`, `test_battle_hud.gd` and `MIGRATION.md` also hold other sessions' unfinished work (fog of war, dark HUD panels, audio and interface notes). In `MIGRATION.md` our bullet sat inside the same insertion as theirs, so hunk-picking was fragile.
  - `%USERPROFILE%\AppData\Local\Temp\claude\E--ProjektM-BWC-GAMES-godot\372d9c5f-2327-4342-83c1-dd4f0eabbbc0\scratchpad\stage_mine.py` builds each file as `HEAD`'s blob plus our replacements (anchors must match once). It writes the blobs with `git hash-object -w`, then `git update-index --cacheinfo`.
  - The working tree is never touched. After the commit, the working diff of those files holds only the other sessions' work.
- **Merge:** a merge commit pinned with `--match-head-commit`, no branch deletion, the same as #1. The unpushed `6499291` existed at merge time and was left for its chat; it has since been pushed by others.

## Open problems
1. **Howl's visual** is uncommitted until the animation session commits `battle_view.gd`. Until then `main` plays War Cry's effect and sound for Howl.
2. **Howl's sound** reuses the growl's `roar`.
3. **Guard note** never appears in play, because no enemy has Defend (owner's call).
4. **Charge aiming** only tries the side under the cursor (`battle_view._preview_against`, the animation session's file).
5. **Skill effects** from the spec's "Visual direction" are not done.
6. **Fog-of-war baseline:** re-recording it is on hold by the owner.
7. **Shader error** in `battle_sorted.gdshader`: another session's.
8. **Branch ahead of `main`:** `6499291` and `aa697b4` belong to other chats. A new pull request from `godot-migration` will include them, so check with those chats first, or pin it to their pushed head knowingly.

## Next steps
1. Wait for the owner's direction.
2. **If the owner gives an enemy type Defend:** the guard note appears through `pv.guard` in `hud_battle_panels.gd` (`ward` / "stand guard"). Add a capture shot for it.
3. **Committing the Howl visual:** coordinate with the animation session, which owns `battle_view.gd`. Never commit that file alone or revert it.
4. **New pull request:**
   - Create it with `gh pr create --repo CTBW/BWC_GAMES --base main --head godot-migration …`.
   - Merge with `gh pr merge <n> --repo CTBW/BWC_GAMES --merge --match-head-commit <full sha>`, never `--delete-branch`.
   - Fetch first: other chats push to this branch.
5. **Rules for any change:**
   - Run `tools/test.sh --quick` after the change and the full `tools/test.sh` on the staged tree before committing.
   - Stage by explicit path, or with `stage_mine.py` for mixed files. Never `git add -A` or `git add .`. Never stage `assets/audio/bank/local/`.
   - Commit with `git -c user.name=CTBW -c user.email=135850159+CTBW@users.noreply.github.com commit …`, ending the message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
   - Pull request descriptions end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
6. **Testing a staged tree on its own:**
   - Set up the worktree: `git worktree add --no-checkout --detach <dir> HEAD`, then `git -C <dir> sparse-checkout set projects/meridius/source/godot` and `git -C <dir> checkout --detach HEAD`.
   - Apply `git diff --cached --binary`, run `tools/import.sh`, then `tools/test.sh` (about 6.5 min; run it in the background).
   - Clean up with `git worktree remove --force <dir>`. It deregisters the worktree but fails to delete the folder ("Filename too long"). Then run PowerShell `Remove-Item -LiteralPath "\\?\<full path written out>" -Recurse -Force`. A variable inside the `\\?\` path is blocked by the permission check.

## Scratchpad
`%USERPROFILE%\AppData\Local\Temp\claude\E--ProjektM-BWC-GAMES-godot\372d9c5f-2327-4342-83c1-dd4f0eabbbc0\scratchpad\` holds:
- `stage_mine.py`
- `staged.diff`, `staged.bin.diff`
- `wt_full_test.txt`, `wt_import.txt`
- `pr_body.md`
- `charge_plain_crop.png`
- `hud.txt`, `combo1.txt`, `combo2.txt`

## Other notes
- Ignore broadcasts from the footman 3D rig session. Don't touch `art/footman_3d/`, `prototypes/footman_anim/` or the spearman art.
- `inbox/*` is gitignored. This handoff is untracked.

---
From the Claude Code chat continuing "Meridius - Add combat skills · continued" in E:\ProjektM\BWC_GAMES-godot, 2026-10-24T13:25:20Z.
