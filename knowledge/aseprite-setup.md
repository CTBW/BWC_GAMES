# Aseprite setup (source build, CLI and MCP)

Set up on 22 October 2026 on Windows 11. Every result below comes from real
command output.

## Status

| Part | State |
| --- | --- |
| Aseprite 1.3.18.6 | Built from source: `E:\Tools\aseprite\build\bin\aseprite.exe` reports `Aseprite 1.3.18.6-dev`. |
| Batch mode and Lua | Works: `tools/anim/build_footman.py --aseprite` writes the footman's `.aseprite` masters through `--script`, and `--list-tags`, `--data`, `--sheet`, `--tag … --save-as x.gif` read them back. |
| MCP server `diivi/aseprite-mcp` | Cloned to `E:\Tools\aseprite-mcp` (commit `a89b205`, MIT), registered as `aseprite` in `.mcp.json` and `.codex/config.toml`. Not started yet: its dependencies install (`uv`) on first launch, which needs the user's approval. |

## Licence

Aseprite's source is public, but its EULA allows a self-compiled copy for
personal use only; it may not be redistributed. Keep the binary out of Git and
out of shipped builds. Prebuilt copies are sold (Steam, itch.io, aseprite.org).

## Build (what was installed)

- Visual Studio 2022 Build Tools 17.14 with the C++ workload (MSVC 14.44) and
  the Windows 11 SDK 10.0.26100, through winget (one UAC prompt):

  ```powershell
  winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --override "--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.26100"
  ```

- CMake 4.4.4 and Ninja 1.13.2 (`winget install Kitware.CMake`, `Ninja-build.Ninja`),
  portable installs under `%LOCALAPPDATA%\Microsoft\WinGet\Packages`, no admin.
- Source: `git clone --recursive --depth 1 --branch v1.3.18.6 --shallow-submodules https://github.com/aseprite/aseprite.git E:\Tools\aseprite`.
- Skia: Aseprite's prebuilt `m124-08a5439a6b` `Skia-Windows-Release-x64.zip`
  from <https://github.com/aseprite/skia/releases>, extracted to `E:\Tools\deps\skia`
  (INSTALL.md of v1.3.18.6 asks for the `aseprite-m124` branch).
- `E:\Tools\build_aseprite.cmd` runs `VsDevCmd.bat -arch=x64`, CMake
  (`-G Ninja -DLAF_BACKEND=skia -DSKIA_DIR=… -DCMAKE_BUILD_TYPE=RelWithDebInfo`)
  and `ninja aseprite`: 1575 steps, a few minutes. Log in `E:\Tools\build_aseprite.log`.

To update, check out a newer tag in `E:\Tools\aseprite`, run
`git submodule update --init --recursive`, confirm the Skia branch in its
INSTALL.md and run the script again.

## MCP

`diivi/aseprite-mcp` (123 tools: canvas, drawing, layers, animation, palettes,
exports, previews and a raw Lua tool) runs Aseprite in batch mode for each
call. Configuration:

```json
"aseprite": {
  "command": "uv",
  "args": ["--directory", "E:\\Tools\\aseprite-mcp", "run", "-m", "aseprite_mcp"],
  "env": { "ASEPRITE_PATH": "E:\\Tools\\aseprite\\build\\bin\\aseprite.exe" }
}
```

- A chat loads its MCP servers when it starts; the server appears in chats
  started after this change, once approved.
- The first start runs `uv` to create the server's environment (Python 3.13+,
  `mcp`, `httpx`, `pillow`). An agent's attempt to run `uv sync` for it was
  refused by Claude Code's auto-mode check ("Code from External"), so the user
  approves that first run.
- `run_lua_script` and the preview server run code on this machine; only pass
  scripts you trust.

## Use for Meridius

The footman masters live in `projects/meridius/source/godot/art/footman/`
(see that project's README). Useful CLI calls:

```powershell
$A = "E:\Tools\aseprite\build\bin\aseprite.exe"
& $A -b footman_f.aseprite --list-tags --data tags.json --format json-array
& $A -b footman_f.aseprite --tag walk --scale 0.5 --save-as walk_f.gif
& $A -b footman_f.aseprite --split-layers --save-as "{layer}_{frame}.png"   # 90 PNGs: "soldier 1_0.png" …
```
