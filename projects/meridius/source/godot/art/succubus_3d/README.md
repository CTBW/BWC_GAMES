# Succubus (German shepherd hybrid): 3D model, rig and clips

Started 23 October 2026. Concept, Higgsfield receipts and the Tripo task IDs are in
`projects/meridius/references/characters/succubus_idle/jobs.json`; the Tripo exports
(FBX + 4K base colour) are in `references/characters/Succubus TRIPO/`.

## Files

| File | What it is |
| --- | --- |
| `succubus_base.blend` | Body (spike removed, hips and legs adjusted, paw pads, fur tufts), wings, tail and whip, textures packed. From `tools/build_succubus.py`. |
| `succubus_rig.blend` | The rigged character: `SuccubusRig` (Mixamo names, no fingers) with tail, wing and loincloth bones, the whip's handle (`WhipGrip`) and coil (`WhipCoil`) bones, and the attack's lash (`WhipLash`, 2 m on `Lash_1`..`Lash_16`). From `tools/rig_succubus.py`. |
| `succubus_anim.blend` | The rig with the clips as actions: tail, wing and loincloth motion, the whip arm and coil kept out of her body, the attack's lash. From `tools/retarget_clips.py`, `tools/secondary_motion.py`, then `tools/whip_motion.py`. |
| `review/` | Review renders: `clip_<name>.gif` (game camera and from behind), paw pads, fur, hips and legs. |

## Clips

All 30 fps; `frames`, `fps`, `loop` and `root_vel` / `root_motion` are stored on each action.

| Action | Source (E:\Animations) | Frames | Notes |
| --- | --- | --- | --- |
| `idle` | Idle standing - Succubus-German Shepherd | 500 | Loop (16.6 s), in place, her standing idle (added by the user on 24 October). Wings half spread, swaying nine times per loop. |
| `idle_flourish` | Idle - Succubus-German Shepherd | 235 | Her bending idle, now a one-off (7.8 s) played from `idle` now and then: eased in from and out to `idle`'s first pose; wings and tail sway as in `idle`, a whole number of times, so it starts and ends in step with it. The sidecar lists it under `variants.idle` with a random wait of 9 to 22 s. |
| `walk` | Walking - Succubus-German Shepherd | 36 | Loop, in place, 1.0 m/s (`root_vel`). Wings folded. |
| `walk_start` | Start Walking - Succubus-German Shepherd | 57 | Keeps its travel in the hips (`root_motion`). |
| `walk_stop` | Stop Walking - Succubus-German Shepherd | 47 | Keeps its travel in the hips. |
| `attack` | Attack - Succubus-German Shepherd | 106 | Left-handed: the lash plays out of the collar at the top of her wind-up (frames 17-22), cracks twice like a whip, an overhand strike (crack at frame 27, 0.87 s) and a rising underhand one (frame 52, 1.70 s), both at the tile ahead, and is reeled in at 62-70; after the second her arm stops at the target and sinks (edited, see The whip), so the lash falls in front of her; the wings flare round frame 42. The sidecar's `events` give `lash_out`, `strikes` and `lash_in` in seconds. |
| `hit` | Hit - Succubus-German Shepherd | 104 | Eased in from and out to `idle`, turned 38 degrees (the source stands turned to her right). |
| `death` | Death - Succubus-German Shepherd | 106 | Eased in from `idle`; she falls back. Hips lifted up to 0.28 m to keep her above the ground (`ground`); the wings open and lie beside her; a ground pass keeps tail and wings above the floor. |

## The whip

The concept's whip is a handle with a coiled, bladed lash. Tripo modelled it coiled, so the
rig splits it: the handle (pommel to collar, 705 vertices) is skinned to `WhipGrip` in her
fist, the coil (1428) to `WhipCoil` on the collar. For the attack `rig_succubus.py` builds a
lash from scratch (no paid generation): a tapering eight-sided core, scale-like blades in
pairs pointing back to the handle (three pairs per bone, each pair turned 40 degrees further
round), a gold ferrule and a hooked blade at the tip, coloured from the coil's own texture
(steel and pink medians) in a 64 px texture, 2 m long on 16 bones. It is twice as thick
as a real lash (its root as wide as the collar, 3.2 cm): true to life it drew a one-pixel
line at the game's zoom. `whip_motion.py`:

1. turns her whip arm out from her chest wherever her left forearm or hand cuts into her
   (the standing idle's hand sank 6-7 cm into her fur hips; frame 220 of the bending idle);
2. rolls the whip about its handle in her fist, tilting it a little where needed, wherever
   the coil or the pommel cuts into her skin or tail (frame 166 of the bending idle: the
   coil through her head), chosen over the whole stretch at once so it never snaps round;
3. hides the lash outside the attack (`Lash_1` scaled to 0.001) and, in the attack, rolls
   the coil up into the collar while the lash plays out, cracks it twice as a whip and
   reels it in again;
4. edits the attack's follow-through after the second crack (run before 1, so 1 still
   keeps the arm out of her body), so the lash falls in front of her (see below).

The lash is a tapered rope simulated from her hand (gravity, drag, kept out of the ground,
her legs, body and head), steered through the phases of the user's whip reference
(`review/motion_reference.md`, 24 October):

- **Loaded** (`LOAD`, frames 15-24): laid back over her shoulder as it plays out.
- **Loop and crack** (`STRIKES`: the loop starts to run out at frames 24 and 49, the cracks
  at 27 and 52): the lash straightens out of the handle towards `TARGET`, the middle of the
  tile ahead (2.72 m forward, 1.0 m up), handle first and faster and faster (`ROLL`); the
  rest rolls over in a loop (`LOOP_R`, `LOOP_PULL`) that runs out to the tip, so it is
  straight at the crack. Strike 1 cracks 2.6 m ahead, 1.0 m up; strike 2 2.5 m ahead,
  1.1 m up.
- **Recoil and fall:** held straight for `HOLD`, then kicked once into an S-wave
  (`RECOIL`), after which it falls at `FALL` times gravity (the reference's quick droop)
  and lies on the ground. The drag (`DRAG`) acts on its motion relative to her hand, which
  stopped the old rope's flailing: between strikes the tip now peaks at 19 m/s, where it
  reached 40-60 m/s and cracked a second time.

**Follow-through after strike 2** (24 October). The Mixamo clip turns her chest on about
90 degrees to her left after the crack and pulls her whip hand back over her shoulder, so
the lash fell behind her. Now her chest's turn eases to a stop at about 37 degrees
(`CHEST_HOLD`, shared over `Spine`, `Spine1` and `Spine2`), and her hand stops at the target
and sinks forward to waist height (`FOLLOW_KEYS`: directions from her shoulder and reaches,
two-bone IK on `LeftArm` and `LeftForeArm` with the elbow down and out, `FOLLOW_POLE`; the
whip along her forearm). It is eased in over frames 50-52, held to 72 and eased back onto
the clip by 92 (`FOLLOW`). The lash droops and hangs from her hand in front of her, the tip
on the ground 0.75 m ahead, until it is reeled in; the crack is also cleaner (42 m/s at
the tip, up from 28, under 8 m/s afterwards). Her legs, hips, wings and tail are unchanged;
strike 1 is untouched.

The coil and the lash appear and disappear by their bones' scale keys, which the FBX
carries. Two things only Godot showed: the lash's faces were first wound inside out
(Blender's viewport draws both sides; Godot culled them and drew it black), so
`rig_succubus.py` recalculates its normals; and the imported LODs drop its blades, ferrule
and hook (small loose pieces on a 2 m mesh), so `succubus3d.gd` keeps the lash at full
detail (`lod_bias`) and gives it a thinner outline. Godot's bone positions match
Blender's to 1 mm (checked at six attack frames).

The loincloth (the front panel) has no leg weights: it hangs on its own three bones from her
hips and swings forward as one piece over whichever thigh is furthest forward, never
sideways and hardly back, so it keeps covering her groin. The user chose it over the panel
skinned with the legs (`review/loincloth_compare/*.gif`: old left, this one right);
`LOINCLOTH=0` on `rig_succubus.py` builds the old way.

## Rebuild

Background Blender 5.2, with `BLENDER_USER_RESOURCES` pointing at a scratch folder (see
`knowledge/tripo-studio.md`):

```sh
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
T="E:/ProjektM/BWC_GAMES-godot/projects/meridius/references/characters/Succubus TRIPO"
"$B" -b --factory-startup --python tools/build_succubus.py -- "$T" "$PWD/succubus_base.blend" [preview_dir]
"$B" -b succubus_base.blend --factory-startup --python tools/rig_succubus.py -- "$PWD/succubus_rig.blend"
"$B" -b succubus_rig.blend --python tools/retarget_clips.py -- "E:/Animations" "$PWD/succubus_anim.blend"
"$B" -b succubus_anim.blend --python tools/secondary_motion.py -- "idle,idle_flourish,walk,walk_start,walk_stop,attack,hit,death"
"$B" -b succubus_anim.blend --python tools/whip_motion.py -- "idle,idle_flourish,walk,walk_start,walk_stop,attack,hit,death"
"$B" -b succubus_anim.blend --python tools/render_clips.py -- <out dir> walk,idle 1 se,back
```

`build_succubus.py` takes `HIP_WIDEN`, `BUTT_FULL`, `LEG_STRETCH` and `FUR` from the
environment. `render_rig.py` renders the skeleton and deformation tests. `whip_motion.py`
adds to the clips' keys, so it runs once on freshly retargeted clips (it refuses a clip it
has already done); `-- probe <clip> <frames>` prints the cut-in at those frames instead,
and `-- lash <out.json>` writes the attack's lash as it would simulate now, without keying
anything (for trying the whip constants).

The whip-slash schematic (1800 x 3190: how the lash extends, both strikes from the game
camera with the sandbox's effects, the effect timing) is drawn from the clip:

```sh
"$B" -b succubus_anim.blend --factory-startup --python tools/slash_schematic_blend.py -- <render dir>
python tools/slash_schematic.py <render dir> <out.svg>
```

Rasterize the SVG in a browser at its own size. It needs numpy.

## Motion reference

`review/motion_reference.md` has the numbers measured from the user's reference videos:
the wings and tail, which `secondary_motion.py` uses, and the whip, which `whip_motion.py`
follows.

## Delivery

FBX is the target format for the foreseeable future (the user, 24 October 2026); sprite
sheets are on hold as an option.

```sh
"$B" -b succubus_anim.blend --python tools/export_godot.py -- <out>/succubus.fbx 1024
"$B" -b succubus_anim.blend --python tools/verify_fbx.py -- <copy of>/succubus.fbx
```

`export_godot.py` writes `succubus.fbx` (body, wings, tail, whip and lash skinned to 59
deforming bones, the eight clips as takes, 1024 px textures embedded, Y up, facing +Z) and
`succubus.json` (per clip: length, loop, frames, ground speed, steps, the death's
settling, the attack's lash and strike times; `variants.idle`: the clips idle plays now
and then, and the range of the random wait). `verify_fbx.py` re-imports it into an empty scene and compares bones, meshes,
clip lengths, sampled bone positions and each mesh's skinned position with the source
(24 October: all identical). Godot names the clips `SuccubusRig|<clip>` and the bones
with `_` for `:`.

**Godot sandbox.** The export is in `prototypes/footman_anim/art3d/` and plays in
`footman3d_sandbox.tscn` (`scripts/succubus3d.gd`) beside the 3D footman, his game sprite
and an oak prop from the game's sprites, under the game's camera, toon look with outline.
`-- --capture=<dir>` on that scene saves screenshots (`review/godot_sandbox/`). Standing
idle, she plays `idle_flourish` after her own random wait (`succubus3d.gd`, a
RandomNumberGenerator per succubus, so a squad never moves in step).
The prop is drawn in two parts: upright above its foot point (so the depth buffer sorts
units in front of or behind it) and flat on the ground below it (its painted shadow, which
an upright quad would sink under the ground). The Blender prop renders also carry a faint
black haze over the whole frame (alpha 1–20 of 255); the sandbox takes that level off.
`scripts/whip_fx.gd` draws a look test of the whip-slash effects on her strikes (a star,
a shock ring and streaks at each crack, a short flare behind it and a trail behind the tip);
`-- --capture=<dir> --shots=fx_` captures them at held clip times, with and without.

## Not done yet

- Nothing is wired into the game; the FBX plays only in the prototype sandbox.
- The lash's strikes are stored as events but nothing in the game uses them yet.
