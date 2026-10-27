# Collie Royal Guard: 3D model, rig and clips

Started 26 October 2026, at the user's request to take the Collie Royal Guard through the
3D pipeline: his tail works as the succubus's does, and he plays the footmen's clips. The
concept images, prompts and Higgsfield receipts are in
`projects/meridius/references/characters/collie_guard/` (`prompts.md`; `jobs.json`,
gitignored, also holds the Tripo task IDs, settings and file hashes). The Tripo exports
(Smart Mesh in quads, 4K base colour) are in `references/characters/tripo/collie_guard/`:
body 5,159 faces, tail 1,043, sword 661, shield 894. They cost 480 Tripo credits (four
meshes at 100, four textures at 20), approved by the user.

## Files

| File | What it is |
| --- | --- |
| `collie_base.blend` | Body, tail, sword and shield from the Tripo zips, ears and shield reworked, scaled to the Mixamo height (skull top 1.82 m), textures packed. From `tools/build_collie.py`. |
| `collie_rig.blend` | The rigged character: `CollieRig`, with FootmanRig's Mixamo names, hierarchy and rolls, plus `Tail_1`..`Tail_6`, `TabardF`, `TabardB` and `Tasset.L/.R`; the sword in his right fist, the shield on his left forearm with its strap and grip. From `tools/rig_collie.py`. No actions. |
| `collie_anim.blend` | The rig with the footman's 19 clips (`tools/transfer_clips.py`) and his own tail and hanging armour on them (`tools/collie_motion.py`). Local, not in Git: the footman's clips are made from Mixamo clips. |
| `tools/export_godot.py` | Writes `prototypes/sandbox3d/art3d/collie_guard.glb` (local, as the anim scene) and its sidecar `collie_guard.json` (in Git). |
| `tools/render_viewer_frames.py` | Renders the clips for the Workspace card's pose viewer. |
| `tools/bulk_up.py`, `bulk_sword.py`, `raise_arms.py` | Image tools for the concept (`prompts.md`, sections 10 and 11); not part of the rebuild. |

## The model (`build_collie.py`)

Tripo's mesh needed three fixes, all in the build script so a rebuild repeats them:

- **Ears.** Tripo modelled the folded tips as blades running forward from the crown past the
  muzzle: goat horns from the side. They are pressed back towards the crown and bent down
  over it (`EAR_K`, `EAR_FOLD`). Folded, the flaps still hung out beside his eyes, and from
  the game's camera read as rabbit's ears (the user, 26 October); each flap is then drawn
  in towards the top of the ear (`TRIM_C`, `TRIM_G`, `TRIM_K`): the tip moved from
  (0.176, -0.070, 1.775) to (0.120, -0.024, 1.824). The ears end over his brows, short
  and folded, as in the concept.
- **Shield.** Thinned to half Tripo's depth. Its field lay 4 cm behind the rim's face, so
  the rim stood out like a frame (the user, 26 October): the field and the rim's inner
  wall are brought forward to `SHIELD_FIELD` (0.4) of that depth, 1.6 cm. Tripo left the
  back open, so the field's back showed the eagle mirrored; the opening is closed with a
  flat plate in the outer wall's brown. The rivets are untouched.
- **Scale.** Skull top at 1.82 m (the ears not counted), feet at 0, facing -Y.

## The rig (`rig_collie.py`)

As the footman's (`footman_3d/tools/rig_footman.py`), so his clips carry over bone for
bone. His own measurements for the arms (`ARM_X`), neck and head; his five-fingered
gauntlets rolled round the grip into fists (`KNUCK`, `PRESS`) with the thumb moved out of
the grip. Bone heat skinning; the pauldrons' raised collars take no neck or head weight.
The sword's guard sits just in front of his thumb. The shield is strapped to the back of
the forearm as the footman's, then moved straight out from it (along its face's normal)
until its back clears forearm, bracer and fist by `SHIELD_GAP` (1.2 cm) at the nearest
point: a move of 10 cm with the closed back (8.7 cm before it).

The shield's arm strap (`ShieldStrap`) wraps the forearm 62 % of the way from elbow to
wrist (`STRAP_AT`): 4.5 cm wide leather in his belts' brown, 4 mm off the forearm's
section, riveted to the shield's back above and below it with two brass rivets at each end.
The clips hold his left wrist at the footman's lock (`WRIST`, which `transfer_clips.py`
checks), so the forearm keeps still against the shield and the strap is fitted to it as the
clips hold it; it rides on the hand bone with the shield. In every clip it clears the
forearm and the shield. His upper arm folds over the forearm's top in the guard and the
blows (it passes through the forearm there too), and passes through the strap's far side
where it does.

The shield's grip (`ShieldGrip`) is a flat bar of blackened iron, 2.2 by 0.6 cm, bent into a
staple. Its middle, wrapped in the strap's leather to the sword grip's radius, lies along the
left fist's axis, so the fist fits it as the right fist fits the sword. The fist stands 14 cm
off the shield's back, so the legs run that far from the back, past his hand above and below
(`GRIP_GAP`, 4 mm clear of the hand's faces), 16.4 cm apart; each foot is riveted to the back
with two brass rivets. The fist rides on the hand bone alone, as the shield does, so the grip
keeps its place in his hand in every clip; only the leather inside his fist meets the fingers,
as the sword's grip does.

The tail is mounted under his belt (`TAIL_Z` 0.90 m), its stump pressed 4 cm in, tilted
to clear his legs and back panel, on six bones along its centre line, weighted by
distance, as the succubus's. The tabard's front and back panels and the side tassets get
bones of their own on the hips (`HANG`), weighted from nothing at the belt to all at the
hem.

## Clips

`transfer_clips.py` samples each of the footman's clips on FootmanRig (appended from
`local/footman_3d/footman_rig.blend`) and writes it onto CollieRig by rest-pose difference
in world space, so his bones turn exactly as the footman's turn away from the T-pose. The
hips' motion and the stored travel (`root_vel`, `root_path`, `lane_m`) are scaled by the
ratio of the hip heights; the other properties are copied.

| Clip (game name) | Frames | Tail |
| --- | --- | --- |
| `idle` (the .blend's `stand`), `idle_guard` (its `idle`), `block` | 77, 227, 60 | Slow sway, a whole number of times per loop. |
| `walk`, `start`, `stop` | 41, 91, 76 | Once per stride, against his hips' sway; built up and let die down. |
| `run` | 22 | Root raised (`RUN_LIFT`): the tail streams out behind him. |
| `charge_hit`, `charge_stab`, `charge_thrust` | 46, 69, 59 | As the run until the blow, then sinks (`CHARGE_SETTLE`). |
| `attack`, `attack_stab`, `attack_thrust`, `hit`, `block_hit` | 46, 65, 71, 30, 30 | A little sway; dragged behind his hips' turn (`DRAG`, at most `DRAG_MAX`). |
| `lane`, `turn_90`, `turn_180` (and `turn_90_r`, exported) | 58, 29, 46 | Stepping sway and drag. |
| `death` | 118 | The sway dies out and the tail sinks as he falls; once he lies on his front it is laid on the ground to his right of his legs (`DRAPE_SIDE`, `DRAPE_DOWN`). |

A ground pass then turns up any tail bone that would go under the ground. The tabard's
front panel rides forward over whichever thigh is furthest forward (at most `PANEL_FWD`),
the back panel back with whichever is furthest back (`PANEL_BACK`), never sideways; the
tassets follow their thighs' swing (`TASSET_FOLLOW`).

## In the sandbox

`prototypes/sandbox3d/scripts/roster.gd`: the profile `collie_guard` ("Collie Royal
Guard", player, the footman's attacks and settings) and the squad "Royal Guards", six in the
footmen's drill, at home at (10.4, 21.0). Without the GLB the sandbox leaves him and his
squad out. Checked in the window on 27 October (`--capture`): unit, portrait, strike,
the squad at home and in the battle; he stands 1.70 m (`height_m`), lifted 8 mm onto the
ground (`ground_lift_m`), and his slash lands at 1.26 m. The GLB's four 2048 px textures
are extracted by Godot's import into `art3d/collie_guard_collie_*_tex_basecolor.jpg`.

## Rebuild

Background Blender 5.2, with `BLENDER_USER_RESOURCES` pointing at a scratch folder (see
`knowledge/tripo-studio.md`). From this folder:

```sh
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
T="E:/ProjektM/BWC_GAMES-godot/projects/meridius/references/characters/tripo/collie_guard"
F="E:/ProjektM/BWC_GAMES-godot/local/footman_3d/footman_rig.blend"
"$B" -b --factory-startup --python tools/build_collie.py -- "$T" "$PWD/collie_base.blend" [preview_dir]
"$B" -b collie_base.blend --factory-startup --python tools/rig_collie.py -- "$PWD/collie_rig.blend"
"$B" -b collie_rig.blend --factory-startup --python tools/transfer_clips.py -- "$F" "$PWD/collie_anim.blend"
"$B" -b collie_anim.blend --factory-startup --python tools/collie_motion.py
"$B" -b collie_anim.blend --factory-startup --python tools/export_godot.py -- "$PWD/../../prototypes/sandbox3d/art3d/collie_guard.glb"
```

Then re-import with `tools/import.sh` (from the Godot project). The pose viewer's frames:
`"$B" -b collie_anim.blend --factory-startup --python tools/render_viewer_frames.py --
<out> "" <facing>` (one facing per process), packed by
`../crossbowman_3d/tools/build_sheets.py <out> <card folder>`.

## Open points

- His coat is the painting's black tricolour only; the sprite's other coats (red, blue
  merle) could be texture variants later.
- In the thrusts the shield and his left fist pass into his belly, and as he falls the fist
  passes into his left tasset: the footman's clips swing the shield arm that far in, and
  the grip goes with the fist.
- He has the footman's game settings and attacks; nothing is his own yet.
