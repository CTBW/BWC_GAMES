# Tripo Studio (web) for Meridius units

Used on 23 October 2026 for the crossbowman, through the user's signed-in
Chrome (`studio.tripo3d.ai`). Ask before every paid action and give its cost
(see `context/preferences.md`).

## Generating

- 3D Workspace → Model → **Smart Mesh** (the home page's "Clean Topology"
  option is the same mode). Topology: Quad. Polycount: one shared value,
  500 to 25,000, typed into the field. The panel remembers the last settings.
- Results land 15 to 25 % over the polycount: 2,500 gave 2,852 to 3,126 quad
  faces, 500 gave 554 to 648.
- "Number of Generation" 1, 2 or 4 showed 100 credits either way, yet a run
  that produced a single variant charged 25. Generate one variant per model
  unless the user asks for more.
- Texture (20 credits) starts at once, without a settings panel. It generates
  a 4096 px base colour only.
- Segmentation costs 40 (one free trial) and Fill Parts patches the hole of a
  removed part. Removing a part is free in Blender instead: Tripo builds props
  such as a quiver as loose pieces of the body mesh.

## Exporting

- Export is free: FBX, preset Blender, texture resolution up to 4K. Textured
  exports arrive as a zip (FBX plus a `.fbm` folder with the texture).
- The browser can reuse the last save folder, such as the ability paintings
  (`E:\Ability Icons` until 2026-10-24, now `local/ability-icons/`). Select the
  model destination explicitly; never treat that folder as the final model
  library. New exports belong in
  `projects/meridius/references/characters/tripo/<character>/`; boss exports
  belong in `projects/meridius/references/characters/bosses/tripo/<boss>/`.
- Use `scripts/asset-delivery/collect-tripo.ps1` with the exact observed source,
  character and asset IDs, plus `-Boss` for bosses. It validates the archive/FBX,
  chooses the correct destination and preserves all takes. Do not identify an
  ambiguous GUID temporary file by recency alone.
- Save editable Blender scenes under `characters/blender/<character>/` or
  `characters/bosses/blender/<boss>/`, keeping textures with their model.
  Existing character libraries remain valid; no bulk migration is implied.

## Inputs that work

- One image per model from Nano Banana Pro on Higgsfield at 4K, 3:4: the
  character in a T-pose with empty hands, and each prop on its own on white.
  2048 px copies upload fine (the browser upload limit was 10 MB).
- A prop drawn at a three-quarter angle is modelled in that perspective: the
  crossbow's far bow arm came out drooping and only one string half existed.
  Ask for a straight front or top view, or repair it in Blender
  (`projects/meridius/source/godot/art/crossbowman_3d/tools/rig_crossbowman.py`
  mirrors the clean half).

## Spearman, later the same day

- **Price change: Smart Mesh charged 100 for a single variant.** At 18:28
  (polycount 5,000) and 18:52 (polycount 500), with "Number of Generation" 1,
  each run was billed −100 in Usage History, where the crossbowman runs at
  17:35–17:48 were −25 per variant. The 100 on the Generate button was right.
  Check the label and Usage History before each run, not older receipts.
- **Edit Mesh = three free retries per model** (Edit Mesh (x3), before
  texturing). It regenerates only what lies inside a box set with face handles;
  from a side view the left and right handles set the depth. The compare view
  keeps whichever version you choose, and History restores earlier ones.
- A retry box whose boundary crosses an air gap, such as between a cape and the
  torso, can come back capped with a flat wall there. Look from the front with
  backface culling. A box taken from the belt to the hem, with its front at the
  body's back surface, came back clean.
- Texturing ends Edit Mesh, so finish retries first. Receipts:
  `projects/meridius/references/characters/spearman_idle/jobs.json`.

## Goblin rabble, 24 October 2026

- Smart Mesh still charged 100 per single-variant run; texture 20.
- The left-sidebar **Texture** panel shows settings before charging: image
  reference (the model's own input image), texture style, Remove Lighting,
  and 2K / 4K / 8K (one trial). The bottom-toolbar Texture button skips it.
  Several texture jobs can run at once; each took about one minute.
- The Assets panel mixes older models with new ones, such as a textured knife
  from 01:01. Check the task ID in the URL before charging.
- With Chrome's "Ask where to save" on, every export waits for the user to
  click Save. Find the file by its exact name, not by recency.
- Exported models are normalised to 1 unit on their longest side.
- Receipts: `projects/meridius/references/characters/goblin_rabble/jobs.json`.

## Goblin archer, 25 October 2026

- Several agent sessions share the Tripo account. A Smart Mesh run took the
  header balance from 440 to 240 because another session's run was charged in
  the same second. Usage History, which lists each charge to the second, showed
  two −100 entries. A header drop larger than the button's price needs that
  check, and a message to the other chats, before anyone assumes a double
  charge.
- After the polycount popup opens, an upload can shift the panel, so a value
  typed straight away may be lost. Zoom in on the field and confirm the number
  before clicking Generate.
- Receipts: `projects/meridius/references/characters/goblin_archer/jobs.json`.

## Blender in the background

- `blender -b --factory-startup` with the normal user profile removes the
  Python wheels of the profile's extensions (Higgsfield add-on, blender_mcp)
  from `%APPDATA%\Blender Foundation\Blender\5.2\extensions\.local`, because no
  extension is enabled. Set `BLENDER_USER_RESOURCES` to a scratch folder.
- A byte image's `pixels` take sRGB values (don't linearise them). In TEXTURE
  colour mode, Workbench shows each material's active image node.
