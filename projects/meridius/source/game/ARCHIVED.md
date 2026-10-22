# Archived

This TypeScript/Canvas version of Meridius was archived on 21 October 2026.
Development continues in the Godot version in `../godot` (see its
`README.md` and `MIGRATION.md`).

- **Kept in place, unchanged.** The Godot tools still read these sources:
  `../godot/tools/bake/` bakes the procedural figures, engines, portraits and
  icons from this renderer. Do not move or delete the folder while that is so.
- **Not kept in step with Godot.** The two versions now differ on purpose. In
  Godot a routing enemy blocks a path, and a squad whose walk is cut short on
  an ally's tile falls back to the last tile it had to itself. Here, paths
  may cross routing enemies and two squads can end up on one tile. Do not
  change this version to match.
- **Do not regenerate Godot files from it.** `../godot/tools/export_data.ts`
  would overwrite the Godot data tables (now edited directly in
  `../godot/data/`). The battle-trace and campaign generators in
  `../godot/tools/parity/` would replace the traces Godot now records itself.
- It still runs: `npm install`, then `npm run dev`, `npm test` or
  `npm run sim`.
