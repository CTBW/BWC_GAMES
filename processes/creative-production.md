# Creative production loop

Read the brief and inspect references. Before a new design or a revision, look
at the project's earlier designs for context, and check all of them when needed,
not only the closest one: concept sheets, in-game sprites, modelling masters and
isolated parts, boss concepts, lore pages and the prompts in their receipts (the
owner, 24 October 2026). For Meridius they are in
`projects/meridius/references/characters/` (unit sheets, `*_idle/`,
`wolf_scout/`, `mage_3d/`, `bosses/concepts/`), `references/text/`, `review/`
and `source/godot/art/raw/`. A contact sheet of thumbnails shows many at once.
Note which earlier designs the new one follows (faction colours, anatomy,
materials, rendering) so it fits the universe.

Decide which result the user needs now:
an exploration, a faithful edit, a modeling reference, a mesh, a material or a
motion study. Use `3d-production-routing` to select the relevant skill.

Choose the exact provider and model from the task and current capabilities.
Inspect the live input schema before submission. Save the job receipt locally,
recover that job after a timeout and download the result once it completes.
Avoid duplicate paid submissions and preserve the accepted source image.

## Downloads are part of the pipeline

The owner explicitly authorized automatic local downloads of images and files
produced by the Higgsfield -> Tripo -> Blender workflow (24 October 2026).
Download each completed original image, model and texture export before moving
to its dependent stage. Downloading is already authorized; it does not require
another confirmation. Paid generation limits and approvals still apply.

Save provider originals in the relevant project's reference/source folder, and
keep repairs or prepared Blender files separately. Prefer original-resolution
downloads over gallery thumbnails. Record local paths, byte sizes and SHA-256
hashes alongside the private job receipt. Decode images, inspect ZIP contents,
and import meshes with their textures in Blender. A completed remote job alone
is not a delivered asset.

If browser Save As prevents the download event from completing, a fully received
temporary download may be copied without changing browser settings. Identify
the exact file associated with the just-triggered download; never assume that
an unrelated newest file belongs to the task. Use the offline
[download collector](../scripts/asset-delivery/collect-download.ps1) to validate
and retain it immediately. For Tripo ZIPs, pass the expected exported FBX name.
The collector refuses a conflicting destination and reports the retained hash.
It does not operate the browser or submit jobs. Build and verify a final
[delivery manifest](../scripts/asset-delivery/README.md) for the selected outputs.

Review at full size. Keep successful execution separate from visual acceptance.
Explain a rejection with concrete evidence, such as a missing limb, a changed
face, an unwanted camera move or sliding foot contact. Make the smallest useful
revision instead of restarting the entire design without a reason.

Present selected and rejected takes in the task's Workspace card with clear
labels and usable media previews. Retain enough prompt and version information
to reproduce the work, while excluding tokens and signed provider links from
public exports. End with a precise next step or the verified final artifact.

For game work, continue into the relevant production skill: VFX, UI, animation
integration, level design or game audio. Carry the accepted concept and real
gameplay event markers into the implementation. Keep proposals, implemented
behavior, agent verification and user acceptance distinct. Use
`gameplay-visual-review` for evidence from the actual engine; a browser study or
generated clip cannot establish that an effect works in the game.
