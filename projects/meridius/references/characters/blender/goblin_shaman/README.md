# Goblin shaman Blender files

`goblin_shaman_mask_plate.blend` holds the shaman's horned skull mask, trimmed from
Tripo's skull shell to a face plate, as the user asked on 26 October 2026. Its base
colour is in `textures/` (4096², linked by relative path). It is built in background
Blender from the Tripo export in `../../tripo/goblin_shaman/` (`mask__take-01.zip`); see
`../../goblin_shaman/prompts.md` and its `jobs.json` for where it came from.

```sh
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
S=projects/meridius/references/characters/blender/goblin_shaman
"$B" -b --factory-startup --python $S/tools/trim_mask.py -- \
  projects/meridius/references/characters/tripo/goblin_shaman $S/goblin_shaman_mask_plate.blend
```

Set `BLENDER_USER_RESOURCES` to an empty folder for these runs (see
`knowledge/tripo-studio.md`).

## Face plate

- **Cut:** Tripo modelled the mask as a whole skull, open underneath, with a strap
  band round it and a back painted dark brown. The user asked for the cut just behind
  the horns. Their bases end 0.30–0.32 of the depth from the front, so a vertical cut
  keeps the front 33% (0.288 of 0.874 in Tripo's units, where the mask is 1 high),
  0.013 behind the nearer horn base. It deletes the cranium, the painted back and the
  strap band with its pegs, which begins at 35%. The face, the brow, both horns and
  the cheekbones stay whole. A first cut at 43%, which kept the strap pegs, was
  replaced the same day.
- **Caps:** the shell is thick, so the cut leaves one horseshoe-shaped section, capped
  facing back, so the plate is watertight: 1,176 faces (1,756 before, 87 of them caps),
  with no open or non-manifold edges. Each loop is capped on its own, since a part that
  pierces the shell (as the pegs did at 43%) leaves a small section that overlaps the
  shell's. Each cap triangle takes one flat colour from the nearest outside face on the
  cut, so the rim is bone.
- **Frame:** the plate stays where Tripo put it, front toward -Y and Z up, 1 high.
  Scaling it to the goblin's head and fitting it round his ears belong to the
  character's base build, which is not made yet.
- **Known limits:** the inside of the plate is dark brown, as Tripo painted the
  inside of the shell; it lies against his face. Nothing holds the plate on yet: the
  strap went with the cut.
