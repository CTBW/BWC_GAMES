# Goblin Rabble base scene

`goblin_rabble_base.blend` holds the textured Tripo body and its five props, fixed
and scaled, ready for rigging. Each object's base colour is in `textures/` (4096²,
linked by relative path). The scene is built in background Blender from the Tripo
exports in `../../tripo/goblin_rabble/` (`<model>__take-01.zip`); see
`../../goblin_rabble/prompts.md` and its `jobs.json` for where they came from.

```sh
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
D=projects/meridius/references/characters/blender/goblin_rabble
"$B" -b --factory-startup --python $D/tools/build_rabble.py -- \
  projects/meridius/references/characters/tripo/goblin_rabble $D/goblin_rabble_base.blend
"$B" -b $D/goblin_rabble_base.blend --python $D/tools/render_check.py -- <out dir> [original body.fbx]
```

Set `BLENDER_USER_RESOURCES` to an empty folder for these runs (see
`knowledge/tripo-studio.md`).

## What the build does

- **Scale:** the goblin is 1.26 m tall, with his feet on the ground and centred,
  facing -Y like the Mixamo clips. That is the 1.82 m used for the footman,
  spearman and crossbowman, times the battle view's figure heights: 34 px for the
  rabble against 49 for a man (`member_height` in
  `projects/meridius/source/godot/scripts/render/squad_view.gd`).
- **Chain:** Tripo modelled the seven links of the broken collar chain rigid,
  sticking out forward and down at 49°. They are turned about the top link, which
  passes through the collar's ring, to hang straight down. The links below it are
  moved 16 to 19 mm forward, so they clear the collar's lower edge and the chest.
  The front view is unchanged apart from the chain reaching 6 cm lower, to the
  bottom of the sternum. The links are in the vertex group `Chain`, for weighting
  them to the chest or to a dangle bone later.
- **Props:** each is scaled to its length, with its long axis on Z and its front
  facing -Y as in the Tripo front view. They stand in the `Props` collection to
  the right of the body. Lengths are read off concept B against the goblin's
  height:

  | Object | Length | Origin |
  |---|---|---|
  | `Knife` | 0.46 m | middle of the grip, halfway between the pommel and the guard |
  | `Hatchet` | 0.50 m | middle of the leather wrap, 17% up the haft |
  | `Cleaver` | 0.44 m | middle of the handle, halfway below the blade |
  | `ShieldBarrel` | 0.50 m across | middle of the back |
  | `ShieldPlank` | 0.64 m tall | middle of the back |

## Known limits

- The back of the body and the loincloth are painted darker and flatter than the
  front, because Tripo textures from the front image.
- The barrel shield is a flat disc with its staves painted on, and it has no grip
  or strap on the back. The plank shield's nails come through at the back.
