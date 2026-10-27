# Footman motion study 01

Four authored proposals, 23 October 2026. They are **isolated native Godot 3D previews**, not integrated sprite replacements. No approval is implied. The geometry is a simple editable proxy with a left shield and right sword, using the supplied footmen's cream, blue and leather palette.

## Delivery

| Clip | Duration | Main events | Outcome |
| --- | --- | --- | --- |
| Move | 5.60 s | Eight alternating steps; travel ends at 4.50 s | Walk 3 m, settle in guard |
| Sword attack | 2.40 s | Lead plant 0.65 s; contact 0.82 s; return step 1.56–1.94 s | Return to the starting guard |
| Shield bash | 2.50 s | Lead plant 0.69 s; contact 0.86 s; rear catch-up 1.26–1.57 s | Finish in a forward guard |
| Charge | 4.80 s | Run starts 0.70 s; brake 2.60 s; last plant 3.29 s; root stops 3.30 s; contact 3.40 s | Finish braced at the target |

Times are continuous seconds. Contact frames are 24.6, 25.8 and 102 at 30 fps; the report's marker buttons seek to the first captured frame at or after the event (25, 26 and 102). The 0.17 s plant-to-contact lead on the sword and bash deliberately makes the support change legible. These are studies with preparation and a resting tail, not proposed replacements for the game's action duration.

All four actions are one-shots. Replaying the travel actions resets world position; no seamless loop is claimed. A production walk cycle would retain its internal stride phase and drive it from distance travelled.

## Edit and run

The authoritative source lives in the Godot project:

- `tools/motion_study/motion.gd`: world-space foot placements, body/hand curves, action timing and two-bone IK.
- `tools/motion_study/proxy.gd`: rigid low-poly body parts, shield, sword and contact markers.
- `tests/visual/footman_motion_study.gd`: two fixed cameras, playback controls, native capture and metrics.
- `tests/unit/test_footman_motion_study.gd`: numerical motion checks.
- `tools/motion_study/render.ps1`: native capture and direct PNG-to-H.264 encoding.

From `projects/meridius/source/godot`, use the project's installed engine wrapper:

```sh
tools/godot.sh --path . --resolution 1600x900 --audio-driver Dummy -s res://tests/visual/footman_motion_study.gd
tools/test.sh test_footman_motion_study
tools/test.sh --quick
```

Interactive keys: **1–4** select a clip, **Space** pauses, **Left/Right** steps one 30 fps frame, **S** toggles 1× / ½×, **R** restarts, **Esc** closes this preview. Existing editor/game sessions are not restarted. For native captures, append `-- capture`; `-- stills` samples diagnostic frames. Add `clip=charge` after `--` to isolate one action.

The source ZIP mirrors these paths. Extract it into an existing Meridius Godot checkout. It is not a standalone game, Blender file or skinned animation export. Motion is procedural and editable; a later asset pass can bake the accepted motion onto the intended character rig or into sprite atlases.

## Movement authority and future integration

Metres; +X forward; +Y up; character left is -Z. The study owns root translation and foot placement. Never add these root positions on top of controller displacement. For in-place runtime playback, subtract the authored root and keep contact corrections in the same space as the controller.

The production game is 2D sprite based. Relevant findings:

1. `soldier_anim.gd::pose` selects wind/hit frames during attack; `battle_view.gd::_play_drilled_melee` moves the whole figure through `m.lunge`. The boots move with the image rather than staying on independent supports.
2. `_play_drilled_melee` gives the front/rear ranks fixed reach (22 / 13 times figure scale). It does not solve each attacker's reach against an opposing body or shield. In dense formations this can create overlap.
3. Walking phase is clock driven. Front facings use drawn walk poses, while back facings can use a deformed foot rig whose amplitude is capped. Translation and limited stride travel can disagree.
4. `step_drift` intentionally uses an underdamped spring. The gait defaults set damping to 0.55; a stop can overshoot.

Recommended production order after the reference/acceptance pass: distance-matched gait; supported stop; independent attack supports and contact events; per-soldier target lanes and reach limits; separate bash/charge poses; interruptions and crowd checks. Keep rules and presentation separate. Rear ranks should hold guard or use a free lane; fixed forward lunges for everyone are insufficient. Preserve current game movement speed and action cadence unless a deliberate gameplay change is requested.

## Verification and limits

Five dedicated tests check stationary stance anchors, floor contact, fixed limb reach, planted impact, body separation, stopped charge root, and walking versus running support. The manifest audits at 240 Hz and records peak distances, planted-foot speed, body spacing and flight duration. It measures the study's control geometry, not skin deformation or a full collision system.

Native captures use Godot 4.7.2 / GL Compatibility, fixed 30 fps samples, 1600 × 900, two cameras sharing the same poses. 459 original PNG frames are retained under `tests/visual/out/motion-study/` (gitignored). MP4 copies are encoded once from the original PNGs at CRF 18, H.264 yuv420p, without audio. The report's speed and frame controls operate on these videos.

The current-game baseline is the unmodified `footman_lab.gd` march and melee scenarios. It samples 20 fps with three 1/60 s simulation steps between frames. Its scenario logger reported zero errors, then shutdown emitted four leaked ObjectDB instances and one resource still in use. This does not establish a clean shutdown of that existing harness.

Visual review uses native poses and the videos; no claim of motion capture, photorealism, production crowd validation, runtime performance measurement, final rig export or completed game integration. Shield/sword contact and body clearance are studied with one opposing footman; the final game's rank spacing must be checked separately.

Final quick suite: **368 passed, 1 failed, 10 skipped in 172.9 seconds**. The failure is `test_audio::test_a_marching_squad_is_one_tread`, reporting `!actions.custom_samplers.has(function->arguments[j].tex_builtin)` in the shader compiler. That existing production/audio path was not modified. All five new motion tests pass. No commit or Windows export was made.

Browser review: Brave at 1440 × 900 (light) and 1024 × 768 (dark), without horizontal page overflow. All four H.264 videos decode at 1600 × 900 with the expected durations. Replay, half speed, contact seek, forward/back frame steps, image enlargement, image download target and closing the image viewer were checked. Local asset/source references and the Workspace registry entry were checked. Source and video hashes are in `delivery-checks.json`. Download links resolve to local artifacts; no external hosting was used. Native keyboard controls are implemented in the lab; this review exercised the report controls, not physical input to the native window.

## Revision ledger

- Initial block: world-space support anchors, start/stop trajectories, fixed cameras and a paired defender.
- Review correction: local rather than world-axis scaling of limb cylinders; tightened sword follow-through to preserve arm reach and keep it on the weapon side of the shield.
- Contact correction: shortened shield extension and adjusted target placement rather than stretching the forearm.
- Charge correction: an additional short braking placement avoids a stretched knee; the run has a brief flight phase, the braking approach returns to double support.
- Status: authored, numerically checked and captured. User selection/approval and reference matching are pending.
