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
