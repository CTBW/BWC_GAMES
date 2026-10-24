# Handoff

## Result
The squad skills are **committed** as `3d28cfa` ("Meridius Godot: squad
skills for the company's squads") on branch `godot-migration`. Howl now plays
Growl's purple shout with wider rings, but that one change is **not**
committed: it lives in `battle_view.gd`, which belongs to the animation session.

The kits, as before:
- **Footmen:** Charge (`shield_charge`), Defend (`defend`), Shield Wall; Shield Bash on promotion.
- **Spearmen:** Spear Wall, Square (`square`).
- **Crossbowmen:** Overwatch, Aimed Shot (`aimed_shot`).
- **Border Collie Royal Guard:** Growl (`growl`), Charge (`hound_charge`), Defend, Lick Wounds (`lick_wounds`). Promotion turns Growl into Howl (`howl`).

Animation and effects for the skills come later (spec, "Visual direction (not implemented)").

## Where things are
- **Repo:** `E:\ProjektM\BWC_GAMES-godot`, branch `godot-migration`. Expected base: `3d28cfa` or later.
- **Godot project:** `projects/meridius/source/godot` (paths below are relative to it unless marked).
- **Spec:** `projects/meridius/docs/squad-skills.md` (repo-relative). Keep it current.
- **Log:** `MIGRATION.md`, section "Squad skills (22 Oct 2026, Godot only)" with its "Follow-up, 23 Oct 2026" list.
- **Earlier handoffs:** `inbox/handoffs/2026-10-23-meridius-add-combat-skills-9e489a85.md`, `inbox/handoffs/2026-10-24-meridius-add-combat-skills-continued-63018e7b.md`.
- **This chat's transcript:** `C:\Users\calle\.claude\projects\E--ProjektM-BWC-GAMES-godot\4c8d0d1a-70a7-4e4c-a22e-95b16220332c.jsonl` (session bwc-games-godot-8e).
- **Project rules:** `CLAUDE.md` and `ARCHITECTURE.md` in the Godot project. Read both before changing code.

## What this session did
1. **Howl visual** (owner approved): in `scripts/render/battle_view.gd`, the `"shout"` case, Growl's branch became `elif e.ability == "growl" or e.ability == "howl":`, with both rings scaled by `k = radius / 2` (Howl 3 tiles, Growl 2). Rest of the branch unchanged (text, shake, `roar` sound, focus, hop).
2. **Capture:** `tests/visual/capture_skills.gd` gained a `use_howl` shot (frees the hounds with `hasActed = false`, presses Howl, captures 20 frames in).
3. **Meta parity cleanup:** `tests/parity/test_meta_parity.gd` no longer has the Royal Guard `canPromote` special case. It compares `c.canPromote` as recorded, as MIGRATION.md already claimed.
4. **Docs:** the spec's "Events" section and MIGRATION.md's follow-up list now record the Howl view change. The campaign-golden note was corrected (see "Verification").
5. **Commit with partial staging.** Five files also held other sessions' uncommitted work: `scripts/rules/battle.gd`, `scripts/rules/ai.gd`, `scripts/ui/hud_battle_panels.gd`, `tests/unit/test_battle_hud.gd`, `MIGRATION.md`. Only the skills hunks went into the index (`git apply --cached --recount` on filtered diffs; MIGRATION.md as HEAD plus the "Squad skills" section, inserted before "## Resume here"). The working tree was not touched. After the commit, those five files' remaining diffs contain no skills lines.

## Verification
- **Committed tree** (temporary sparse worktree of HEAD + the staged diff, fresh `tools/import.sh`, then full `tools/test.sh`): **358 passed, 0 failed, 0 skipped (271 s)**. That includes all 17 `test_squad_skills` tests, `test_battle_hud::test_squad_skill_buttons`, battle parity (77 traces), campaign parity and meta parity. No shader error.
  - So the campaign golden matches the skills, including Defend's one blow per turn and Howl. The campaign parity failures in the shared tree come only from fog of war.
- **Shared working tree** (`tools/test.sh --quick`, after the Howl change, before the commit): 394 passed, 1 failed, 10 skipped. The failure is the known shader error, `custom_samplers` from `scenes/battle/battle_sorted.gdshader`, reported in `test_audio::test_a_marching_squad_is_one_tread`. Not ours.
  - The full suite was not re-run in the shared tree. The last full run (previous session) had 398 passed, 3 failed: the two fog-of-war campaign parity failures and the shader error.
- **Visual check** (agent only, not owner-reviewed): `tools/godot.sh --path . --resolution 1920x1080 -s res://tests/visual/capture_skills.gd -- use_growl tip_howl use_howl`. In `tests/visual/out/skills_use_howl.png` the purple ring reaches the cowed goblins; `skills_use_growl.png` shows the smaller Growl ring.
  - The log line in the corner of the Howl shot still reads "Growl!". That is timing, not a bug: the rules emit the log after the `shout` event, and it plays back after the 0.8 s shout animation.
- **No running processes.** The temporary worktree was removed.

## Ownership and files not to overwrite
- **`scripts/render/battle_view.gd`:** the animation session's file, with about 750 uncommitted lines. These include Growl's and Lick Wounds' shout branches, the "Guarded!" effect, and now the Howl change at about line 1249. Commit it only with that session, or with the owner's say-so. Never revert it.
- **Fog of war** (another session): uncommitted hunks in `battle.gd`, `ai.gd`, `hud_battle_panels.gd` (tile info), `test_battle_hud.gd` ("Enemies in sight"), plus `scripts/rules/visibility.gd`, `setup.gd`, `grid.gd`, `mapgen.gd`, `terrain_test_fields.gd`, `test_setup_parity.gd`. Don't stage them.
- **Dark-panel HUD restyle** (another session): `hud_battle_panels.gd` (`DarkPanel`, corner radii, facing rose).
- **`MIGRATION.md`:** shared by many sessions. Edit only our section and stage partially as above.
- **Never** use `git add -A` or `git add .` (about 1,080 untracked files are undecided). Never stage `assets/audio/bank/local/`.
- Session bwc-games-godot-c6 broadcasts about the footman 3D rig (`art/footman_3d/`, `prototypes/footman_anim/`). Ignore them and don't touch those files.

## Decisions carried forward (owner's)
- **Defend:** a bodyguard that catches one blow per turn (`guardSpent`, cleared at the start of its faction's turn and when the stance is used again).
- **Shield Bash:** stays the footmen's promotion.
- **Royal Guard promotion:** Howl, which replaces Growl through `"upgrades": "growl"` and `Soldier.kit(type_id, promoted)`. Radius 3, morale −16, Cowed 2 turns, cooldown 3. Howl's icon is `assets/icons/howl.svg`, uid `uid://dt2tbxa3rrldt`.
- **Balance:** no measuring or tuning.
- **Campaign baseline with fog of war:** **on hold** (owner, 24 Oct 2026). The re-recording belongs with the fog-of-war work; the skills don't need it.
- **Commit:** the owner accepted committing with the 3 known failures. They turned out not to affect the committed tree.

## Open items
1. **Howl's view change is uncommitted** until the animation session commits `battle_view.gd`. Until then the committed game plays War Cry's effect and sound for Howl.
2. **Howl sound:** it reuses the growl's `roar`. The audio session may want a howl.
3. **Minor quirks:**
   - The forecast row "Charge broken by the square" shows 0.
   - The guard note only appears for enemies that have Defend.
   - Charge aiming only tries the side under the cursor (`battle_view._preview_against`, the animation session's file).
   - The HUD unit-panel cache doesn't include "enemy adjacent", so the Lick Wounds button can be stale.
4. **Effects per the spec** ("Visual direction") are still to do, after the squads' frames.

## Next steps
1. Wait for the owner's direction. Nothing is pending.
2. If asked to commit the Howl view change: coordinate with the animation session, which owns `battle_view.gd`. Don't commit that file alone.
3. If the owner lifts the hold on the fog-of-war baseline: run `MERIDIUS_RECORD=1 tools/test.sh test_battle_parity test_campaign_parity` in the shared tree, then explain it in MIGRATION.md (fog of war's entry). That is the fog session's change, so check with it first.
4. After any change, run `tools/test.sh --quick`; before committing, the full `tools/test.sh`.
   - Commit as `git -c user.name=CTBW -c user.email=135850159+CTBW@users.noreply.github.com commit …`, ending the message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
   - To test a partial staging on its own, use a sparse worktree in the scratchpad: `git worktree add --no-checkout --detach <dir> HEAD`, `sparse-checkout set projects/meridius/source/godot`, apply `git diff --cached --binary`, then `tools/import.sh`.
   - Windows path limits: delete the worktree folder with PowerShell `Remove-Item -LiteralPath "\\?\<path>" -Recurse -Force`.

## Other notes
- **Scratchpad:** `C:\Users\calle\AppData\Local\Temp\claude\E--ProjektM-BWC-GAMES-godot\4c8d0d1a-70a7-4e4c-a22e-95b16220332c\scratchpad\` holds:
  - `pick_hunks.py` (keeps chosen hunks of a diff by old start line)
  - the filtered `skills_*.diff` files
  - `wt_full_test.txt` (the committed tree's full run)
- **Previous scratchpads:**
  - `C:\Users\calle\AppData\Local\Temp\claude\E--ProjektM-BWC-GAMES-godot\7891c9ab-6aeb-4e1f-b744-74b89d60f6b9\scratchpad\` (icon contact sheet `render_icons.gd`, Howl drafts, earlier test logs)
  - `C:\Users\calle\AppData\Local\Temp\claude\D--ProjektM-BWC-GAMES-godot\d379d718-21fd-4cfc-b9d9-cf230a9e35de\scratchpad\` (balance tools such as `sim_skills.gd`)

---
From the Claude Code chat continuing "Meridius - Add combat skills" in E:\ProjektM\BWC_GAMES-godot, 2026-10-24.
