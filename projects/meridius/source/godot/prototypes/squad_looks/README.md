# Squad looks

How the men of a squad (one to six footmen on one model) are told apart, on
the 3D footman of the unit sandbox (`prototypes/sandbox3d`). Nothing here
touches the game's state or production units.

```
tools/godot.sh --path . res://prototypes/squad_looks/scenes/looks_lab.tscn
... -- --capture=res://tests/visual/out/looks_lab [--shots=<prefix>] [--clean]
tools/test.sh test_squad_looks
```

The lab shows four squads (six, four, three and two men) through the game's
camera. Every part of the variety is a layer you can switch off, down to clones
(keys 1-7, C). The panel sets each squad's size, livery, kit (militia, line,
guard) and shield mark, and rerolls its men. It also gives orders to every
squad (stand, block, swing, take a hit, march) and switches the facing, the
look (toon, flat, PBR) and the zoom. The footman's export
(`prototypes/footman_anim/art3d/footman.glb`) is not in Git; without it the
lab shows a message.

## How

| Layer | What changes | How |
|---|---|---|
| Livery and shield | the squad's colour, its shield's tinctures, division and charge | per-instance uniforms (`instance uniform`) on one shared material |
| Own clothes and dye | each man's dye lot, trousers, linen, leather | the same, by colour band of the texture |
| Hair, skin, beard | hair and skin colour, stubble or a full beard | the same, the head and lower face found from skin weights |
| Helmets and plume | kettle hat, nasal helm, skullcap, padded cap; the leader's plume | meshes built once per kind, on a `BoneAttachment3D` on the Head bone |
| Build | head and chest a few percent larger or smaller | a `SkeletonModifier3D` (`body_shape.gd`) scaling bones after the clip |
| Glances | at rest he looks at a squadmate, a foe or off to one side | the same modifier turning the neck and head |
| Dirt and wear | mud up the boots, dust, chipped shield paint | per-instance uniforms |

- `scripts/squad_look.gd` decides who the men are, as data. The squad shares
  its livery and mark. Hair, skin, beards, helmets and trousers come from
  per-squad shuffle bags, so no two men match while a bag lasts. The same seed
  always gives the same men.
- `scripts/unit_look.gd` dresses a man. The Tripo texture has no masks, so
  the body is copied once per model with its regions in the vertex colour
  (R head and neck, G legs, B lower face, A rest height). The shaders recolour
  each colour band relative to its measured mean, which keeps the paint's
  strokes. A second copy pulls the hair in under a helmet: the model's hair
  is thick, and a helmet fitted over it looks like a top hat. Helmets are
  surfaces of revolution fitted to the cropped head's outline. The shield's
  eagle is found once from its texture: a light patch the painted field
  encloses.
- `scripts/dressed_footman.gd` extends the sandbox's `unit3d.gd`: set
  `look_spec` before he enters the tree.
- Every man shares three materials per look mode. The Compatibility renderer
  shows `ALBEDO` unconverted, so colours stay display (sRGB) values.

## To the sandbox's squad

In `prototypes/sandbox3d/scripts/sandbox3d.gd`, `_spawn_squad` would create
`DressedFootman` instead of `Unit3D` and set
`u.look_spec = SquadLook.squad(SQUAD_SIZE, seed, SquadLook.LIVERIES[0], "line")[i]`
before `add_child`, then call `UnitLook.link(men)`. That folder belongs to the
unit sandbox's owner; ask before changing it.

## Limits

- At the game's zoom (a soldier 49 px tall, a head 6-7 px) faces don't read.
  Silhouette (helmets, plume), large colour fields (livery, shield, trousers)
  and hair colour on bareheaded men do. Beards and skin show from about 3x.
- Colour bands are found by hue. A livery's colour can't be any colour the
  texture already paints elsewhere (cream, brown), or both would change.
- Helmets are built procedurally, as placeholders for modelled ones. Modelled
  helmets (Blender or Tripo, rigid, no rig) would go on the same Head
  attachment with the same hair crop.
