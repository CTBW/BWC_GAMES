# Boss art library

Canonical boss deliverables live here. Workspace report images are preview copies.
The full-size PNGs are local only and not in Git; WebP copies of the concept
originals are in `workspace/2026-10-20_meridius/bosses/originals/`.

- `concepts/`: original Higgsfield PNGs, exact submitted prompts and image manifest.
- `tripo/<boss>/`: downloaded Tripo ZIP/FBX exports with original textures.
- `blender/<boss>/`: editable Blender files and local texture dependencies.

Keep every take. Record private job IDs and provider URLs under `.cache/boss-art/`.
Concept approval is separate from model generation, visual review and engine readiness.
No Tripo generation or Blender import has been performed for these bosses yet.

Use `scripts/asset-delivery/collect-tripo.ps1 -Boss` with an observed source file,
character ID and asset ID. It validates the download and selects this library;
the browser's remembered ability-icons directory must never be used as the final destination.
