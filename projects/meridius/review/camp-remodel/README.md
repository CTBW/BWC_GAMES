# Woodland camp remodel

First native implementation of the selected `camp_small_woodland` composition as
Amberfeld Garrison, the starting place for campaigns. The stage keeps the fixed
isometric artwork and connects its six service areas to the existing game.

[Workspace report](../../../../workspace/2026-10-20_meridius/camp-remodel.html)
and [provenance manifest](manifest.json).

## Implemented presentation

- Exact selected day and night paintings, blended smoothly for a local lighting
  preview. Lighting selection does not advance campaign time.
- Shader mist in the woodland, restrained canopy light and gently breathing
  warm tent light at night. Architecture is not displaced by the shader.
- Existing roster figures following authored routes on visible open ground.
- Six hit areas opening the existing Command, Barracks, Training, Quartermaster,
  Armoury and Infirmary panels, plus keyboard-focusable service buttons.
- Bounded pan and zoom, Frame camp, compact identity and lighting controls,
  latest-only Chronicle, and the existing Roster and Plan Expedition actions.

## Atmospheric detail pass — 2026-10-24

The user accepted the first camp appearance and requested rolling fog, small
birds from the treetops, and wind bending/rustling the trees. This pass adds
engine animation over the same unmodified day/night paintings.

| Layer ID | Owner / trigger | Space / scale | Lifetime and visibility |
| --- | --- | --- | --- |
| `woodland-fog` | Camp material / scene clock | Painting UV; two advected noise layers at about 10–14 source pixels per second | Continuous while camp exists; localized north, west and eastern forest bands; cooler at night |
| `woodland-wind` | Same material / shared slow gust | Nine local tree masks in painting UV; crown movement about 3–8 source pixels | Root-weighted bend and subpixel leaf flutter; hard exclusion over enclosure; same UV displacement for both light states |
| `woodland-birds` | Camp life canvas / presentation clock | Three surveyed crown tips; 16 source-pixel wingspan decreasing with distance | 3–5 staggered birds; nine-second flight every 32 seconds; fades out and settles at night |

`atmosphere_enabled` on the renderer disables fog, wind, birds, leaves and light
motion; the material takes a cheap raw-painting branch. There are no per-flight
nodes, timers or particles to accumulate. Bird state is sampled from the scene
clock without consuming campaign RNG. All draw resources belong to the camp.

Editable bird source: [camp_wildlife.gd](../../source/godot/scripts/render/camp_wildlife.gd).
Run the native review with `-- --camp-atmosphere` to capture a matched OFF/ON
pair, all three bird routes, a 12-second day clip and a six-second night clip.
Real-time frame statistics are sampled separately, without frame readback or
encoding; they cover the whole scene and are not isolated GPU effect timings.

This is subtle deformation of painted trees. Larger branch swings, independent
foreground parallax or revealing scenery behind trunks would require separated
tree artwork and a repaired background.

## Source artwork and provenance

| Use | Selected original | Engine copy | Dimensions |
| --- | --- | --- | --- |
| Day | [camp_small_woodland, take 02](../../../../workspace/2026-10-20_meridius/terrain/originals/camp_small_woodland__take-02.webp) | [woodland_day.png](../../source/godot/assets/camp/woodland_day.png) | 2752 × 1536 |
| Night | [camp_small_woodland_night, take 01](../../../../workspace/2026-10-20_meridius/terrain/originals/camp_small_woodland_night__take-01.webp) | [woodland_night.png](../../source/godot/assets/camp/woodland_night.png) | 2752 × 1536 |

Both engine PNGs are byte-for-byte copies of their selected originals. SHA-256
was checked against both original and engine copy on 2026-10-23. The links open the WebP copies in the terrain card; the full-size
originals stay local in `local/workspace-originals/`:

- Day: `C200EE9B1B3A2182DA3F1EA0CCCAAF9C3933EB1DD13C860226FBDCF527734E14`
- Night: `D90365E2BBB29576D3AE222041DBEA46AEF6F7D0FEAE77BE6BA0FCA88C56170E`

This implementation reuses existing artwork and submits no generation jobs.
Historical generation provenance remains with the
[terrain artwork workflow](../terrain-prompt-pack/README.md). Job receipts and
account details are not copied into this deliverable.

## Editable engine sources

- [woodland_camp.gd](../../source/godot/scripts/render/woodland_camp.gd): painted
  stage, service anchors and hit polygons, figure routes, camera and lighting.
- [camp_woodland.gdshader](../../source/godot/assets/shaders/camp_woodland.gdshader):
  day/night blend and forest/tent atmosphere.
- [base_screen.gd](../../source/godot/scripts/ui/screens/base_screen.gd): camp HUD,
  service controls and existing modal integration.
- [base_view.tscn](../../source/godot/scenes/base/base_view.tscn): active camp scene.
- [base_view.gd](../../source/godot/scripts/render/base_view.gd): retained original
  renderer and compatibility base. Baseline SHA-256:
  `EE2E97C7B67D6FAB3E50642E1C5ED60B9F58D37D237D76D7992FBD66CF79F825`.
- [camp_remodel_review.gd](../../source/godot/tests/visual/camp_remodel_review.gd):
  native capture and interaction review source.

## Coordinates and service assignment

`ANCHORS`, `ZONES` and `ROUTES` in `woodland_camp.gd` are the authoritative
presentation geometry. They use normalized image coordinates with origin at
the top-left, x increasing to the right and y increasing downward. Multiplying
by `ART_SIZE = Vector2(2752, 1536)` produces the engine stage coordinates in
source-image pixels. Camera transforms then map them to the viewport.

The manifest links to the code rather than duplicating editable polygons.
Figure routes are presentation-only paths; they are not battle navigation,
collision meshes or changes to campaign rules.

| Service ID | Painted placement | Assignment |
| --- | --- | --- |
| `command` | Central command tent | Command area |
| `barracks` | Western tent lines | Recruitment area |
| `training` | Eastern training ground | Training area |
| `quartermaster` | Rear-left supply area | Supplies area |
| `armoury` | Rear-right service area | Interpretation of unlabeled concept |
| `infirmary` | Front tent group | Interpretation of unlabeled concept |

## Native evidence

The report uses WebP copies of these native captures under
`workspace/2026-10-20_meridius/camp-remodel/`; the full-size PNGs stay local:

| File | Purpose |
| --- | --- |
| `before.webp` | Original camp baseline |
| `day.webp` | New daylight scene and HUD |
| `night.webp` | Matching night preview |
| `hover.webp` | Live service hover and information |
| `wide.webp` | Wide desktop framing |
| `barracks.webp` | Existing building panel over the new scene |

## Verification

Native review: **90 checks passed, zero runtime errors and clean shutdown**.
The actual mouse/keyboard flow verifies all six painted facilities and service
buttons, hover, modal blocking, day/night, camera reset/zoom, roster, expedition
preparation and return, and 2560 x 1080 framing. The player's save was unchanged;
preferences were restored. See the report's `camp-remodel/review.txt` and JSON.

Focused camp/interface tests: **35 passed**. Final `tools/test.sh --quick`:
**388 passed, 1 failed, 10 skipped**. The remaining failure is
`test_audio::test_a_marching_squad_is_one_tread`, a `custom_samplers` compiler error
from the existing battlefield shader under headless rendering. No battlefield
shader/audio source was changed in this task. The report includes the summary.

The original silent day/night MP4s used 288/144 native frames at 1920 x 1080.
They are now replaced by the audio recordings below. The earlier five-second
night clip is retained. These are normal-speed motion studies, not rendering
performance measurements. Original frame sequences remain in ignored native output.
The final report's desktop browser checks are recorded in the manifest. No mobile
checks are part of this task. The user accepted the first camp appearance; atmospheric additions await user visual review.

## Audio correction — 2026-10-24

The previous MP4s had no audio stream and the report's video elements were muted.
The current game already defaults to sound ON (`Prefs.DEFAULTS.muted = false`),
and the owner's saved mix also has mute OFF with nonzero Master and Ambience.
No startup override was added: deliberate player mute and volume settings remain
persistent. The replacement videos start unmuted when the user presses Play.

`tests/visual/camp_audio_review.gd` boots the production game, dismisses the
welcome letter through its button, and records the actual scene and Master bus
with Godot Movie Maker. It uses a separate review save and never writes player
preferences. Both default and saved sound, live ambience beds, unchanged campaign
state, save and preference hashes are checked. Shutdown waits for audio playback
resources to release. The day clip lasts 12 seconds; night lasts six seconds.
The movie writer outputs native 1600 x 900 at 24 fps from the 1920 x 1080 viewport;
delivery uses H.264 and stereo AAC at 48 kHz without added sound or gain changes.

Reproduce from the Godot project:

```powershell
& 'C:/Program Files/Git/bin/bash.exe' tools/godot.sh --path . --resolution 1920x1080 --disable-vsync --fixed-fps 24 --write-movie tests/visual/out/camp_audio/camp.avi -s res://tests/visual/camp_audio_review.gd
```

Create `tests/visual/out/camp_audio/` first. The capture JSON records clip frame
ranges for trimming the AVI. The full source capture stays in ignored native
output. Delivered audio measurements and file hashes are in
`workspace/2026-10-20_meridius/camp-remodel/audio-review.json`.

The quick suite rerun for this correction reports **408 passed, 0 failed,
11 skipped**. This supersedes the older suite result above. Audio checks cover
decoded output, volume and clipping; they do not claim a subjective listening
assessment or verification of the user's physical speakers.

## Limits

- Painted buildings do not change appearance when upgraded. Authoritative levels,
  costs and benefits remain in the existing game and are shown in panels/tooltips.
- Armoury and Infirmary assignments interpret the unlabeled source artwork.
- A fixed painted stage supports the camp camera, not rotating 3D geometry or
  battlefield terrain/navigation.
- Existing roster, building and campaign rules remain authoritative and unchanged.
- This is the first native implementation; implementation, automated verification
  and user visual acceptance are separate states.
