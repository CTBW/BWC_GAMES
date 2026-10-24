# Handoff

## Goal
The user wants Meridius's battle terrain to stop looking "lackluster, dull and
boring": real hills and slopes instead of "a block on top of another block", a
"real, mind-blowing and cool" look, concept images (Nano Banana) and a Seedance
video. Art targets in `projects/meridius/review/terrain/`:
- `concept_a_repaint.png` (2752×1536) is the target for raised ground: grassy
  plateaus, crumbling layered earth banks, a grass lip and golden grass.
- `concept_c_hill_study.png`: golden lit top, cool teal shaded slope.
- `concept_b_moody.png`: mood.

All requested items exist now. **No task is open.** The next chat continues
only on the user's direction (candidates under "Open problems").

## Current state
- **Relief ground: implemented, committed and pushed; lab-only; not accepted
  by the user for battles.** Commit `e481dbb` on `godot-migration` ("Meridius:
  relief ground for the terrain lab, bank polish and a Seedance clip"), pushed
  to `origin/godot-migration`. The whole branch was later pushed up to
  `150c0a9`.
- **Branch state when this was written (2026-10-24 14:11 UTC):** local HEAD
  `bc5a80f`, two commits ahead of origin (`453549e`, `bc5a80f`, both by other
  chats, not pushed). Other chats keep committing to this branch.
- **Committed `e481dbb` cannot show the relief on its own.** The lab screen,
  terrain textures and app hookups it needs are still uncommitted and belong to
  Codex or are shared (list below).
- **What the user sees in Terrain Test Fields** (title screen, or
  `--terrain-lab`), field 4 "Bluff and hollow":
  - a three-level plateau with a stratified face of sandy soil and pale stone;
  - turf hanging over the crest in ragged tongues;
  - faceted fallen blocks at the foot.
  The meadow hill shows golden lit slopes and teal shaded flanks.
- **Seedance clip of concept A: done.** Seedance 2.5 via Higgsfield MCP:
  - job `daa9f45a-c2a3-4e1d-96b1-bc8ecfea67e8`, start image media
    `5bd409a0-c07c-4c1e-b9cf-1dfa971cecfa`;
  - 8 s, 1080p, 16:9, no sound, 128 credits; balance 751.57 → 623.57.
  - Original HEVC: `projects/meridius/review/terrain/concept_a_seedance.mp4`.
    H.264 copy: `workspace/2026-10-20_meridius/terrain-relief/concept_a_seedance.mp4`.
  - Watched with the video-watch helper: one continuous scene, no cuts, no new
    objects or text. Frame 0 matches concept A. Trolls turn their heads,
    banners stir, the push-in holds the style.
- **Workspace:** the Meridius card, tab "Terrain relief ground"
  (`workspace/2026-10-20_meridius/terrain-relief.html`).
  - Contents: the video section with controls and download, the bank
    before/after, hills and targets.
  - Browser check on a temporary static server: 16 images and 17 download
    links OK, the video plays, preview works. Reports are desktop-only.
- **Receipts are local only.** I committed the two receipts in `e481dbb`.
  Another chat then untracked them (`bc5a80f`, "Keep generation receipts out
  of Git", AGENTS.md line 29) and ignored `**/receipts/`. They stay on disk at
  `projects/meridius/review/terrain/receipts/`. The Higgsfield CDN URL with the
  account ID was removed from the Seedance receipt before it was committed.

## Verification (agent, 24 October 2026)
- **Clean worktree, HEAD `5c0b3b3` plus only the relief files:** full
  `tools/test.sh` **362 passed, 0 failed**, including `test_relief` 4/4,
  campaign parity and `test_audio`. The commits after `5c0b3b3` up to `e481dbb`
  touched no Godot code.
- **Shared working tree (everyone's uncommitted changes):** full suite 406
  passed, 3 failed:
  - `test_audio::test_a_marching_squad_is_one_tread`
    (`shader_compiler.cpp:1329` custom_samplers);
  - `test_campaign_parity::test_driven_runs_with_ai_battles_match` (loot
    silver 53 vs golden 63);
  - `test_campaign_parity::test_autoplay_campaigns_match` (success vs golden
    retreat).
  All three pass on clean HEAD, so they come from other chats' uncommitted
  changes, not the relief.
  - The likely campaign-parity cause is the rule changes in the tree, e.g.
    `scripts/rules/grid.gd` `woodland_prop` makes trees and bushes passable.
  - Whoever owns those rule changes must re-record with
    `MERIDIUS_RECORD=1 tools/test.sh test_battle_parity test_campaign_parity`
    and add a note to MIGRATION.md. Not this lane.
- **Captures:** native GL Compatibility 1920×1080, 0 errors; build_ms
  {0: 49.9, 1: 47.2, 2: 76.2, 4: 48.0}. Stored in
  `projects/meridius/review/terrain/relief-2026-10-24/`, including
  `*_before_polish.png`.
- **Owner acceptance:** none yet. Relief stays lab-only until the user accepts
  it.

## Ownership (lane split with a parallel Codex chat, still active)
- **Relief lane (this chat's):** all committed in `e481dbb`. Paths under
  `projects/meridius/source/godot/`:
  - `scripts/render/relief.gd`: Catmull-Rom bicubic `surface()`;
  - `assets/shaders/terrain_relief.gdshader`;
  - the ground part of `scripts/render/relief_terrain.gd`;
  - field 4 in `scripts/rules/terrain_test_fields.gd`;
  - `tests/unit/test_relief.gd`;
  - `tests/visual/terrain_relief_shots.gd`.
- **Codex (do not edit), all uncommitted:**
  - `scripts/render/woodland_kit.gd`, `woodland_camp.gd`, `terrain_lab.gd`,
    `terrain_lab_draw.gd`;
  - `scripts/ui/screens/terrain_lab.gd`;
  - `assets/shaders/camp_woodland.gdshader`, `terrain_woodland_mist.gdshader`;
  - `tests/unit/test_woodland_camp.gd`.
- **Shared or other chats, uncommitted:**
  - `assets/terrain/` (the textures `relief_terrain.gd` loads as
    `res://assets/terrain/%s.webp`);
  - the lab hookups in `scripts/app/app.gd`, `main.gd`, the title screen and
    `README.md`;
  - `scripts/render/battle_deps.gd` (loads `relief_terrain.gd` at line 95);
  - the rule changes (`grid.gd`, `ai.gd`, `battle.gd`, `setup.gd`,
    `mapgen.gd`).
- **Partly committed shared files:**
  - `workspace/workspace.json`: only the "Terrain relief ground" tab is in HEAD
    (after "Loop 1"). The other tabs in the working copy are other chats'.
  - `knowledge/higgsfield-setup.md`: the local-scope note and "Seedance
    image-to-video through MCP" are in HEAD. "All squads (22 October 2026)"
    is another chat's and uncommitted.
  - `projects/meridius/docs/terrain-test-fields.md`: committed whole,
    including Codex's lab sections.
- Re-read shared files before editing, and never overwrite another chat's
  hunks.

## Decisions and reasons
- **Bank face painted in screen space**, not along contour lines. Two
  contour-based attempts looked like wood grain.
- **Second bank pass (24 October afternoon)** removed the masonry look:
  - long blocks, 45% of joints open, each cracking only partway;
  - no stone checkerboard;
  - strata only on steep faces (`smoothstep(1.2, 2.0, slope)`);
  - turf overhang depth from `-lap / slope`, independent of the bank's height;
  - fallen blocks placed only at the concave foot of camera-facing banks and
    lit after the ground's light.
- **Slope contrast comes from texture and hue, not light.** The light was
  already right. Textures keep about 70% of their detail contrast. The lit
  flank measures about 1.6× flat ground, the shaded flank about 0.7× (0.57×
  zoom, mist off).
- **Higgsfield:**
  - use the MCP route only; no paid CLI/API fallback;
  - `balance` before and after each job; Unlimited only for Nano Banana Pro;
  - never accept the website's "Media upload agreement" or buy upsells without
    the user's explicit yes;
  - the MCP route asked for no agreement;
  - the upload PUT needs `If-None-Match: *` as well as `Content-Type`.
- **fal is admin-locked** (HTTP 403). Don't retry.
- **Commits:**
  - commit and push only when asked;
  - stage explicit paths only; the tree has about 350 other changes;
  - check `git diff --cached --name-only` is empty first, because the index is
    shared with other chats;
  - test what you commit: a clean `git worktree` at HEAD plus your files. A
    worktree under the scratchpad needs `-c core.longpaths=true` to remove.
- **No Git identity on this machine.** Recent commits use
  `CTBW <135850159+CTBW@users.noreply.github.com>`. Pass it per command with
  `GIT_AUTHOR_*` / `GIT_COMMITTER_*` env vars; don't change git config.

## Open problems (candidates, none requested yet)
1. **Strata show as faint arcs on the bluff's curved west end.**
   - Cause: the beds follow height (`bv = hC * 1.5 + …`, shader around lines
     280–313), so on a curved bank they trace contour arcs.
   - The goal is level-looking beds, as in concept A. The method is not
     decided.
2. **Fallen blocks are small next to concept A.** Screen-space cells are
   `cs = vec2(1.1, 0.8)` (around line 350), the block mask `bA` at line 387,
   compositing at line 437.
3. **The lab mist flattens gentle slopes.** It lifts shaded slopes by about
   10–15 levels (0–255); strength 0.7 is set in Codex's `terrain_lab.gd`,
   shader `terrain_woodland_mist.gdshader`. Codex's lane: report or coordinate,
   don't edit.
4. **Relief acceptance and integration into battles.** Production battles keep
   the current renderer until the user accepts the new terrain and explicitly
   scopes combat and visibility work. Terrain occlusion behind steep crests is
   not implemented.
5. **The three working-tree test failures** (see Verification) belong to the
   owners of the uncommitted rule and audio changes.

## Commands
From `projects/meridius/source/godot`:
```bash
tools/test.sh --quick                 # after every change
tools/test.sh test_relief             # relief tests (4)
tools/test.sh                         # full suite before any commit (~25 min in the shared tree)
RELIEF_FIELDS=0,4 tools/godot.sh --path . --resolution 1920x1080 --audio-driver Dummy -s res://tests/visual/terrain_relief_shots.gd
# writes tests/visual/out/terrain_relief/*.png and result.json (look at them)
```
The capture script loads Codex's uncommitted `scripts/ui/screens/terrain_lab.gd`,
so it runs only in the shared tree, not in a clean HEAD worktree.

## Exact next steps
1. Read this handoff and `projects/meridius/docs/terrain-test-fields.md`
   ("Relief ground pass - 24 October 2026").
2. Run `git status` and `git log --oneline -5`, and re-read any shared file
   before touching it. Check for a newer Codex terrain handoff in
   `inbox/handoffs/`.
3. Ask the user, or follow their message: accept the relief, polish (open
   problems 1–2), or move on.
4. For a shader change:
   - edit only the relief lane;
   - run `tools/test.sh --quick` and recapture with the command above;
   - compare with `concept_a_repaint.png` at 0.57× and 1.45×;
   - update the docs section and the Workspace page with the new captures
     (keep before/after) and check the page in a desktop browser.
5. Commit or push only on request, following the commit rules above.

## References
- Previous handoff (before the Seedance clip and the commit):
  `inbox/handoffs/2026-10-24-meridius-terrain-battlefield-continued-bef98963.md`
- Codex's lab handoff:
  `inbox/handoffs/2026-10-24-gpt-terrain-battlefield-continued-a4d26c11.md`
- Notes: `projects/meridius/docs/terrain-test-fields.md`;
  `knowledge/higgsfield-setup.md`
- Skills: `.claude/skills/workspace-authoring/`, `.claude/skills/video-watch/`,
  `.claude/skills/feature-handoff/`
- Shader backups (temporary, outside the repo):
  - before the second bank pass:
    `%USERPROFILE%\AppData\Local\Temp\claude\E--ProjektM-BWC-GAMES-godot\6fc77634-a4d1-4581-af8b-7a88f6010dea\scratchpad\terrain_relief.v3.keep`
  - older ones, listed in the previous handoff.
- Full transcript of this chat:
  `%USERPROFILE%\.claude\projects\E--ProjektM-BWC-GAMES-godot\6fc77634-a4d1-4581-af8b-7a88f6010dea.jsonl`

---
From the Claude Code chat continuing "Meridius - Terrain & Battlefield · continued"
in E:\ProjektM\BWC_GAMES-godot, 2026-10-24T14:11:13Z.
