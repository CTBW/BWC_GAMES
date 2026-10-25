# Mixar for Meridius

Verified on 23 October 2026. Mixar 4.3.5 is installed and its official MCP
connector works from this workspace. Mixar is a separate Blender fork, with the
Blender 5.2 API; `bpy.app.version_string` reports the Mixar release number.

## Start and use

- Double-click `Mixar.cmd` at the repository root, or run
  `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/mixar/launch.ps1`.
- Open a source file with `scripts/mixar/launch.ps1 -File <file.blend>`.
- Keep Mixar open and signed in. The native profile menu > Connect MCP controls
  the connection. MCP is enabled; optional interface clicking is off. The scene
  inspection, Python, rendering and export tools work with that option off.
- New Codex sessions started in this trusted repository use the `mixar` server
  in `.codex/config.toml`. `.mcp.json` has the same launcher for compatible
  workspace clients. No active chat or application was restarted.
- Existing sessions can use the tested client below until their tool list is
  refreshed. No separate Python install, API key or provider subscription was
  added for the connector.

```powershell
. ./scripts/mixar/environment.ps1
& $MixarPython -s scripts/mixar/client.py
& $MixarPython -s scripts/mixar/client.py --call mixar_ui_context
& $MixarPython -s scripts/mixar/client.py --call mixar_guide
& $MixarPython -s scripts/mixar/client.py --call scene_overview
```

The client lists current schemas, supports `--schema <tool>`, accepts arguments
from a JSON file with `--arguments`, and pins a scene using `--session <UUID>`.
It saves receipts and received images under `.cache/mixar/checks`. It never
automatically retries a mutation. After a timeout, use the returned call UUID
with Mixar's call-status tool before doing anything again.

## Installation and isolation

| Item | Location |
| --- | --- |
| Application | `.cache/mixar/app/Mixar/mixar.exe` |
| Bundled Python | `.cache/mixar/app/Mixar/5.2/python/bin/python.exe` |
| Official bridge | `.cache/mixar/app/Mixar/5.2/scripts/mixar/mcp.py` |
| Profile | `.cache/mixar/profile` |
| MCP discovery / local credentials | `.cache/mixar/runtime` |
| Download and matching source | `.cache/mixar/downloads`, `.cache/mixar/source` |
| Previous project MCP configs | `.cache/mixar/config-backup` |

This is a workspace-local extraction of the official signed MSI, not an entry in
Windows Installed Apps. Preserve `.cache/mixar`; deleting that directory removes
the installation and its workspace profile. Use `Mixar.cmd` so the application
and connector use the same profile and discovery directory. Credentials use
Mixar's own authentication storage; no credentials are in the project MCP files.
All of `.cache` is ignored by Git. Ordinary Blender 5.2 remains installed separately.

Installer: `Mixar-4.3.5-x64.msi`, 336,498,688 bytes. Its SHA-256 matched the
official GitHub asset digest:
`56e5793b6179aa70b3e5bbc0e8386997febc6d103c4739325c7571fb87b86083`.
Windows verified the Authenticode signature from MIXAR INC. Source revision:
`15f9204a3061214e33d4b8e67beafcc14ab53b16`.

## Verified behavior

- Native application opens and displays its viewport; sign-in and backend
  connection reported ready. The introductory tour was dismissed to release
  its modal input lock.
- Official stdio MCP handshake and discovery: 73 tools. A real `mixar_guide`,
  `list_rules`, `scene_overview` and `mixar_ui_context` call succeeded.
- `mixar_scene_new` created a separate verification tab. `execute_bpy_script`
  created a one-metre bevelled cube and supporting base with two materials.
- `render_viewport` produced an inspected 768 x 768 Cycles GPU image.
  `inspect_geometry` reported ground contact with zero penetration.
- The live scene was saved as `live-mcp-verification.blend`. `export_asset`
  produced a GLB package with editable source, two meshes, two materials and
  200 triangles; export verification passed without issues.
- A separate background test saved/reopened a packed texture and UVs, rendered
  a 512 x 512 transparent PNG with Cycles CPU, and exported a textured GLB.
- Stock Blender 5.2.2 LTS opened that source and retained geometry, texture
  and metre scale. It discards Mixar-specific screen regions, producing expected
  UI-region warnings; this was not a full layered-paint compatibility test.
- Godot 4.7.2 loaded the PNG and both GLB outputs in an isolated test project.
  Checks passed for transparency, texture creation, textured material, mesh
  counts, one-metre scale and the live export's Y-up orientation.

Sources, images, machine-readable check summaries and the exported package are
under `projects/meridius/review/mixar-setup`. The Workspace report carries copies
of the principal artifacts under `workspace/2026-10-20_meridius/mixar`.

## Meridius workflow

Use `mixar_guide` first, inspect the current scene and create a new tab for
separate work. Preserve named, editable `.blend` sources in Meridius's art or
review folders. Save the source before calling `export_asset` with
`destination: "project"` to keep the package beside it in this repository.

Meridius currently uses 2D sprites: transparent orthographic renders are the
direct art path. GLB is verified for future 3D assets and supporting workflows;
the setup did not change the game's renderer or install test art into gameplay.
Approved runtime assets still go through the game's `tools/import.sh` and its
existing tests. The frozen TypeScript game and retired repository were untouched.

For a repeat local check (disposable background process only):

```powershell
. ./scripts/mixar/environment.ps1
& $MixarExecutable --background --factory-startup --python-exit-code 1 --python scripts/mixar/smoke.py
```

The current account reported zero generation credits. All verification calls
reported zero credits charged. Hosted generation and the built-in Mixie chat
were not tested or configured with a paid provider. The verified external MCP
workflow uses the workspace assistant and does not require those credits.

## Recovery and updates

- `ui_busy`: finish or dismiss the open tour/dialog/transform, then retry only
  after checking that the original operation was refused.
- No tools in an existing chat: use the client above, or start a new project
  session. Do not terminate a running chat to refresh tools.
- Signed out: finish sign-in in the native app. Never copy account tokens into
  `.mcp.json` or `.codex/config.toml`.
- Use `--background --version` for version checks. `--version` alone opens the
  native startup dialog before printing anything.
- Keep the application visible for native viewport work. On this machine its
  first launch opened minimized; restoring the window resolved capture.
- Portable-install updates were not tested. Download a verified future release
  separately, request permission before closing the running Mixar, preserve the
  profile, and repeat the smoke/MCP/export checks. Do not replace a live binary.

## Sources

- [Official Mixar 4.3.5 release](https://github.com/Mixar-AI/mixar-app/releases/tag/v4.3.5)
- [Official MCP setup guide at the installed revision](https://github.com/Mixar-AI/mixar-app/blob/v4.3.5/src/scripts/mixar/modules/mcp_bridge/README.md)
- [OpenAI: project-local MCP configuration](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)
