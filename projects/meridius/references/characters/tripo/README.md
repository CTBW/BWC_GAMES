# Tripo model downloads

New non-boss exports go in `<character>/<asset>__take-01.zip` (or `.fbx`).
Keep the original archive, embedded textures and all takes together.
Use `scripts/asset-delivery/collect-tripo.ps1` with the exact observed downloaded file.

Boss exports belong in the adjacent `../bosses/tripo/<boss>/` library instead;
pass `-Boss` to the collector. Editable scenes belong in `../blender/<character>/`
or `../bosses/blender/<boss>/`. Existing character libraries are preserved.
