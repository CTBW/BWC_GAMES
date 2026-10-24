# Higgsfield setup (CLI and Blender add-on)

Checked on 21 October 2026 on Windows 11 with Node 24.15, npm 11.12 and
Blender 5.2.2 LTS. Every result below comes from real command output.

## Status

| Part | State |
| --- | --- |
| CLI `@higgsfield/cli` 1.2.2 | Installed, latest release (npm and GitHub agree). |
| CLI sign-in | Signed in; workspace "Private" selected; Plus plan. |
| Read-only checks | All passed (models, workflows, schemas, presets, cost). |
| Paid generation from the CLI | **Blocked**: the account is on a trial (see below). |
| Paid generation through MCP | Works: one Soul 2.0 test, 0.12 credits, image verified. |
| Blender add-on "Higgsfield" 1.5.58 | Installed, enabled, signed in, bar visible. |
| Higgsfield MCP in Claude Code | Connected (local scope); read-only tools verified. |
| Official skills plugin for Claude Code | Not installed (user's choice). |

## CLI

Install (the README's Windows route):

```powershell
npm install -g @higgsfield/cli@latest
higgsfield version   # higgsfield 1.2.2 (53301ea…) built 2026-10-16
```

- Shim: `C:\Users\<user>\AppData\Roaming\npm\higgsfield.cmd`. The npm package
  downloads `vendor\hf.exe` from the GitHub release and refuses to install on a
  SHA-256 mismatch (`install.js`); `vendor\install.json` is written only after
  that check passes.
- PATH: npm's global folder (`npm prefix -g`) was already on the user PATH, so
  nothing was changed. `higgsfield version` works in a new PowerShell process.
- Aliases: `higgsfield`, `higgs`, `hf`.
- Update: `npm install -g @higgsfield/cli@latest`; compare with
  `npm view @higgsfield/cli version`.

Sign-in and workspace:

```powershell
higgsfield auth login          # browser OAuth; the user finishes it
higgsfield workspace list      # one workspace: Private
higgsfield workspace set <id>  # required before account status works
higgsfield account status      # "<email> — plus plan, <N> credits"
```

Before a workspace is selected, `account status` fails with
`Error: No workspace selected.` (exit 4). Never run `higgsfield auth token`
in shared output: it prints the access token.

Read-only commands that worked (no credits):

```powershell
higgsfield model list --json            # 110 models
higgsfield workflow list --json         # 22 workflows
higgsfield model get <job_type> --json  # parameter schema and rules
higgsfield preset list animation-action --query walk
higgsfield generate cost <job_type> --prompt "..." --json
higgsfield generate list
```

Windows PowerShell 5.1 writes a BOM when output is redirected with `>`;
strip it before `JSON.parse`, or save from Git Bash instead.

## Model types checked for Meridius

| Job type | Use for Meridius | Key parameters |
| --- | --- | --- |
| `image_to_3d` | One reference image to a mesh (props, units) | `image_references` (required), `should_texture`, `enable_pbr`, `topology` quad/triangle, `target_polycount`, `enable_rigging`, `pose_mode` a-pose/t-pose |
| `multi_image_to_3d` | Front/side/back sheet to a mesh | same parameters as `image_to_3d` |
| `3d_rigging` | Rig an existing model, optional animation | `model_url` (required), `height_meters`, `enable_animation`, `animation_action_id` |
| `nano_banana_pro` | Character and building sheets from references | `prompt`, `image_references` (up to 14), `resolution` 1k/2k/4k, `aspect_ratio` |
| `seedance_2_5` | Motion reference clips | `prompt`, `mode` t2v/omni_reference/video_edit/video_extension, `start_image`, `duration`, `resolution` 480p–1080p, `generate_audio` |
| `autosprite` | Sprite animation frames from one unit image | `image_references` (required), `kind` (includes isometric `iso_idle_*`, `iso_walk_*`, `iso_run_*`, `iso_jump_*` for up/northeast/right/southeast/down), `frame_count` 25, `frame_size` 256, `remove_bg` |

`animation_action_id` takes an ID from `higgsfield preset list animation-action`
(for example `30 Casual_Walk`, `112 Monster_Walk`, `111 Injured_Walk`).

Estimated image costs on 21 October 2026, default settings: `text2image_soul_v2` 0.12
credits, `z_image` 0.15, `gpt_image_2_5` 0.25, `seedream_5_0_flash` 0.5,
`nano_banana_pro` 2, `seedream_v5_pro` 2.5. These are estimates, not billing.

## Paid test: blocked by the trial

One test was approved (`text2image_soul_v2`, 0.12 credits) and submitted once:

```text
Error: {"error_type":"only_mcp_usage_on_trial_is_available"}
```

No job was created (`generate list` is empty) and the balance did not change.
The account's trial allows generation only through Higgsfield's MCP connector,
not the CLI. The code is not described in Higgsfield's public documentation or
help centre. Do not retry it as is. Generate through the MCP route below
until the trial ends or the plan is paid. Read-only CLI commands, including
`generate get <job_id>`, still work during the trial. Not yet tested: whether
the Blender add-on's Generate button works during the trial.

## Claude Code MCP

Higgsfield's help centre gives `https://mcp.higgsfield.ai/mcp` (OAuth through
`clerk.higgsfield.ai`, with dynamic client registration and PKCE; no API key).
Added at local scope, which is private to this folder and stored in
`~/.claude.json`, so the shared `.mcp.json` stays unchanged:

```powershell
claude mcp add --transport http --scope local higgsfield https://mcp.higgsfield.ai/mcp
claude mcp get higgsfield      # Status: ✔ Connected after sign-in
claude mcp remove higgsfield -s local
```

- Sign-in needs an interactive terminal: run `/mcp` → higgsfield →
  Authenticate in a Claude Code chat, or `claude mcp login higgsfield` in a
  PowerShell window opened in this folder. From an agent's background shell it
  fails with `stdin isn't a terminal`.
- A chat loads its MCP servers when it starts. A server added during a chat
  appears only in chats started afterwards, launched from this folder.
- About 150 tools, including `balance`, `models_explore`, `generate_image`,
  `generate_3d`, `jobs_wait`, `animation_actions`, `remove_background` and
  `cancel_trial_auto_renewal`. Read-only calls verified: `balance` (Plus, 110
  credits), `list_workspaces` (one private workspace, not selected on the MCP
  side) and `models_explore` (17 3D models and `autosprite`). The free trial's
  unlimited block reported `available: false`, so generations cost credits.
- **MCP model IDs differ from CLI job types.** Look them up with
  `models_explore` (`list`, then `get`). `text2image_soul_v2` was rejected
  with `Invalid request: unknown model "text2image_soul_v2"` (no job, no
  charge); the MCP ID is `soul_2`, which the server maps to
  `text2image_soul_v2`. `models_explore` returns no prices, so use
  `higgsfield generate cost` for estimates.
- Paid test, 21 October 2026: `generate_image` with
  `{params: {model: "soul_2", prompt, aspect_ratio: "1:1", quality: "1.5k", count: 1, use_unlim: false}}`
  returned a pending job; one `jobs_wait` returned `completed`. The 1536×1536
  PNG matched the prompt, and the balance went from 110 to 109.88 credits.
  The job record is in `workspace/2026-10-21_higgsfield-test/job.json`
  (gitignored, because the result URL contains the account's user ID).

## Blender add-on

- Source: <https://higgsfield.ai/plugins/blender>. The Download button reads
  `https://hf-adobe-updates.higgsfield.ai/blender/manifest.json`, which gives
  the zip URL, version and SHA-256. Version 1.5.58 matched its hash.
- Requires Blender 5.1 or later. It is an extension (`id = "higgsfield_blender"`)
  with bundled wheels and network and file permissions.
- Install from the command line while Blender is closed, or drag the zip onto
  a Blender window:

  ```powershell
  & "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --command extension install-file -r user_default -e <zip>
  ```

- Verified: enabled in the saved preferences; module
  `bl_ext.user_default.higgsfield_blender` loads; 18 panels and
  `bpy.ops.higgsfield` registered; the viewport bar draws with no draw errors;
  the bar shows the tabs Scene builder, 3D Model, Character animation, Image,
  Video, Camera and Assets, and the account's credit balance once signed in.
- The add-on has its own sign-in (stored under `%LOCALAPPDATA%\Higgsfield\Blender\Data`),
  separate from the CLI's.
- Coexistence with `blender_mcp.py`: the add-on's "Enable MCP control" is off
  by default. If it is turned on, it also tries port 9876 (falls back to
  9877–9879). Whichever add-on starts first gets 9876, so leave it off while
  the workspace's Blender MCP connection relies on `blender_mcp`.
- Auto-save preferences is on. A Blender session started before the install
  can save its preferences on exit without the extension enabled. If the bar
  disappears, enable "Higgsfield" in Preferences > Add-ons again.
- Blender started from a background shell may open minimized, and its
  screenshots are then black. Capture only after the window is visible.

## Example for Meridius (syntax from the schema; not run)

```powershell
higgsfield generate cost autosprite --image-references <one cut-out unit.png> --kind iso_walk_southeast --json
higgsfield generate create autosprite --image-references <one cut-out unit.png> --kind iso_walk_southeast --wait --json
```

Save the returned job ID at once. After a timeout, continue with
`higgsfield generate wait <job_id>`; never submit the same job twice.

## Footman pixel-art squads (21 October 2026, MCP, `nano_banana_pro` 2K)

Eight-direction footman squads in `projects/meridius/source/game/art/sprites/footman_squad`;
job IDs in `art/receipts/footman_squad_higgsfield.json`. 46 credits (23 jobs).
What we learned:

- `generate_image_batch` rejected most parallel items with
  `Out of credits on plus (monthly) plan` while about 100 credits remained.
  Rejected items create no job and no charge. One `generate_image` call per
  job worked, including several running at once.
- A finished image passed as a style reference also fixes the pose: six of
  seven whole-squad directions copied the reference's facing.
- One soldier per sheet in five views (S, SW, E, N, NE) came out right almost
  every time. West, south-east and north-west did not: the model draws them
  mirrored, so the sword ends up in the left hand.
- West and north-west: mirror E or NE, then a text-only edit that swaps sword
  and shield works. Attaching a painted reference to such an edit made the
  model paste in its scenery, or ignore the swap.
- South-east: converting the painted `Footmen_right.png` to pixel art (pixel
  figures as style reference) kept its correct poses, but a faded strip of the
  painted ground was left behind and had to be masked locally.
- `scripts/art/pixelize.py` snaps output to a true pixel grid and cuts out the
  flat background; `scripts/art/squad.py` normalises body height, builds the
  mirrored edit inputs and assembles the 3 x 2 squads with one shared palette.

## Footman animations (21 October 2026, keyframe edits)

Idle, walk, strike and death frames in
`projects/meridius/source/game/art/sprites/footman_anim`, rebuilt from the raw
edits by `scripts/art/footman_anim.sh`. 38 credits (19 edits, 3 of them
re-rolls); jobs under `anim_keyframes` in the receipt. What we learned:

- `autosprite` failed three times with no error text and no charge: idle,
  walk and a custom strike, from a grey 1024 px input and a transparent
  768 px one. We did not find the cause.
- An edit of a six-soldier idle grid that changes only the action, with
  facing, hands, size and positions kept, gives one keyframe for all six men
  per job. 13 of 16 worked first time. A requested pose close to the input
  comes back unchanged: a cocked thrust from an idle that already holds the
  blade forward. A pose the camera can't show comes back as something else:
  a downswing seen from behind came back as a raised sword. Both re-rolls
  worked once the prompt asked for a pose that is clearly visible from this
  camera and plainly different from the input, adding "the sword must clearly
  be above his head, not at his side as in image 1".
- Seen from behind, a soldier slumped on hands and knees would not lie down:
  the edit returned the input almost unchanged. From the front, the same
  chained collapse worked first time.
- An edit keeps every figure where it was drawn, so
  `scripts/art/anim.py cut` registers frames against the idle sprites by
  their cell offsets. Feet go back on the ground line, because drawn rows
  drift by up to 11 px, and up to 37 px for kneeling figures.
- Chained edits work: kneel edits of the idle grids, then collapse edits of
  the cut kneel frames, re-laid with room to fall. In 3 x 2 cells of
  682 px, lying bodies don't fit, and the earlier dead pose came out at half
  scale. 2K 3:2 comes back at 2528 x 1696; 4K costs 4 credits.
- Blades that touch a neighbour need `--split` lines through the gap. The
  lines cut the dilated mask, so they must clear the 2 px dilation.
- Cut with `--no-shadows`. `pixelize.cut_out` treats neutral greys next to
  the background as a contact shadow, and that removed a soldier's grey hair
  and left holes in blades and shield rims. The edits have no shadows.
- Map frames to the idle palette with `anim.py palette`, which repeats
  `assemble`'s median cut, and PIL `quantize(palette=…)`. Nearest-colour
  matching against the delivered colours alone gave 17% wrong pixels.
