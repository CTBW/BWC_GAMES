# Battlefield and campaign edges

23 October 2026. Implemented in the Godot source on `godot-migration`.

The decorative army beyond the battlefield, its standards, distant smoke and
torch effects have been removed. The existing border forest frames open grass
approaches with narrow worn tracks. Entry corridors have no decorative props.
Reserve squads stay hidden until their actual arrival animation starts.

The campaign's decorative warbands, fire glow, smoke and scorched overlay have
been removed. Its ordinary terrain, trees, roads and fog remain. New expeditions
open on the company's position instead of sweeping from the former horde corner.

Enemy wave schedules, entry cells, combat rules, active enemy squads and the
last-stand relief still use the existing gameplay logic. Generated Higgsfield
art has not been integrated as part of this change.

## Native visual evidence

These are actual Godot 4.7.2 Compatibility renderer captures at 1920 × 1080,
using the production battle/campaign views with fixed fixture seeds. The review
window was separate and muted; no active game was restarted. The world view is
shown without the screen HUD.

- [Battlefield before](review/battle-before.png) and [after](review/battle-after.png): same `trolls` fixture and camera.
- [River battlefield](review/battle_edges_river.png): open approach, no background crowd.
- [Last stand at night](review/battle_edges_last_stand.png): reserve crowds absent; real squads and incoming-wave warnings remain.
- [Former campaign horde corner](review/campaign_edges_corner_0.png): ordinary forest and fog.

`tests/visual/capture_edges.gd` checks clearing, river, camp and last-stand
battlefields plus the campaign opening and former corner at march counts 0 and 5.
The final native run completed with **zero captured runtime/render errors**.
Separate day and night battle captures also completed without errors.

The first quick test run passed 364 tests with 10 slow tests skipped. Native
review then found a leftover campaign shader refresh reference; it was removed
and the native captures were repeated successfully. The final quick suite passed
**364 tests, with zero failures and 10 slow tests skipped** in 198.1 seconds.

## Source and preservation

Main changes: `scripts/render/battle_view.gd`, `battle_draw.gd`,
`battle_night.gd`, `battle_deps.gd`, new `battle_surroundings.gd`, and
`campaign_view.gd`. Obsolete visual expectations and the campaign playthrough
harness were updated. No rules or map-generation source was changed.

The repository already contained other uncommitted work. Pre-edit copies and
hashes for the renderer files are stored locally under
`.cache/terrain-edge-review/before/` and `before-hashes.json`; unrelated edits
were preserved. No commit or application restart was performed.
