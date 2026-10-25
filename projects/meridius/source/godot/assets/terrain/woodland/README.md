# Painted woodland trial

Five unchanged Higgsfield originals from the accepted terrain concept library.
`sources.json` records their origins, dimensions and SHA-256 hashes. No new image
generation was submitted for this integration.

The terrain lab uses `scripts/render/woodland_kit.gd` to supply root anchors,
world heights and CPU opacity masks. `terrain_lab_draw.gd` places the kit into
the existing prop depth sort and canopy fade system. The marked-foliage branch
in `scenes/battle/battle_sorted.gdshader` keys the magenta backdrop and suppresses
edge spill. These PNGs still contain magenta; they are not portable RGBA cutouts.
Keep mipmap generation enabled in their import settings.

Pine, beech and oak replace their corresponding lab tree slots; shrubs replace
the lab bushes. Small ferns are presentation-only and sample the continuous
ground surface. The paintings retain their original lighting direction. Rocks,
stumps and fallen logs use the production props from `assets/sprites.json`.

Open Terrain Test Fields > Woodland scouting or Northern forest ford. The
Painted woodland toggle changes art without resetting the map, patrols or fog.
Since e5d04e0, production battles draw keyed cutouts of the same paintings
(`assets/sprites/painted/woodland_*.webp`, made by `tools/props/woodland_cutout.py`),
so the toggle compares those cutouts with the magenta-keyed originals.

Regenerate provenance and the reviewed movie with
`node projects/meridius/review/terrain-lab/woodland-media.mjs --encode` from the
repository root, after the native `fog_of_war_shots.gd` capture completes.
The script accepts `MERIDIUS_FFMPEG_BIN` for the installed FFmpeg directory.
