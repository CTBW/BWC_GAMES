# Pose viewer

The frame viewer on the Meridius rig tabs: Footman, Crossbowman, Spearman,
Succubus, Mage, Goblin Rabble, Goblin Spearman, Goblin Shaman and Collie Royal Guard. Build every new rig or animation review on it instead of a
page-specific player, so each one keeps frame stepping, the four facings, the
copyable frame reference and the detail zoom.

## On a page

- Put the pose viewer first, directly under the page header.
- Load `../_shared/report.css` and `rig-viewer/viewer.css` in the head. Load
  `rig-viewer/viewer.js` at the end of the body, after the two JSON tags below.
- Copy the viewer markup from `spearman-3d.html`: the clip, facing and playback
  bars (`#clipChips`, `#faceChips`, `#first`, `#prev`, `#play`, `#next`,
  `#scrub`, `#speed`, `#zoom`, `#ground`), the readout (`#readout`, `#copy`,
  `#copied`) and `#stage`.
- Add two JSON script tags:
  - `#viewer-config`: `{"base": "<folder>/", "start": "<clip>", "key": "<storage key>", "clips": [["id", "Label"], ...]}`,
    with an optional `"character"` that prefixes the frame reference.
    `"sameScale": true` draws a clip wider than the first at the same scale as the others:
    the picture scrolls sideways, centred, instead of shrinking to the column. Shift and the
    wheel scroll it.
  - `#frames-data`: the sheets' `frames.json`.

## Detail zoom

`viewer.js` adds a Detail bar under the playback controls. You can zoom up to
4× at the pointer:

- Scroll up on the picture to zoom in.
- Drag to move.
- Double-click, `0` or Fit returns to the whole picture.
- `+` and `−` zoom in and out on the centre.

Scrolling down at the fitted view still scrolls the page. The page's `#zoom`
select becomes "Size", the size of the picture. Every facing shares the zoomed
region. While zoomed, each picture's stamp shows the magnification, so a
screenshot records it. Canvases draw at the screen's pixel density.

## Resolution

The zoom enlarges the sheets as they are. The frames are not rendered again
for it. Once a sheet pixel covers four or more screen pixels, it is drawn sharp
instead of smoothed, so render flaws are not blurred away.

| Rig | Frames rendered by | Sheets packed by |
|---|---|---|
| Footman | `footman_3d/tools/render_preview.py` (mode `clip`) | A pack script like the spearman's (scale 0.75, 10 px margin), not in the repo |
| Crossbowman | `crossbowman_3d/tools/render_clips.py` | `crossbowman_3d/tools/build_sheets.py` |
| Spearman | `spearman_3d/tools/render_clips.sh` | `spearman_3d/tools/pack_sheets.py` |
| Succubus | `succubus_3d/tools/render_viewer_frames.py` | `crossbowman_3d/tools/build_sheets.py` |
| Mage | `projects/meridius/review/mage-3d/tools/render_browser_frames.py` | The mage delivery tools beside it |
| Wolf Scout | `wolf_scout_3d/tools/render_viewer_wolf_scout_3.py` | `crossbowman_3d/tools/build_sheets.py` (scale 0.8), run by `projects/meridius/review/wolf-scout/publish-pose-viewer-wolf-scout-3.mjs` |
| Goblin Rabble | `projects/meridius/references/characters/blender/goblin_rabble/tools/render_clips.py` | `pack_sheets.py` beside it |
| Goblin Spearman | `projects/meridius/references/characters/blender/goblin_spear/tools/render_clips.py` | `pack_sheets.py` beside it |
| Goblin Shaman | `projects/meridius/references/characters/blender/goblin_shaman/tools/render_clips.py`, from the scratch copy that `retarget_clips.py` beside it saves with the clips | `goblin_spear/tools/pack_sheets.py` |
| Collie Royal Guard | `collie_guard_3d/tools/render_viewer_frames.py` | `crossbowman_3d/tools/build_sheets.py`, then `split_sheets.py` here for the guard idle |

Rig folders are under `projects/meridius/source/godot/art/` unless the path says
otherwise.

The viewer also reads sheets rendered larger than the canvas. Give `frames.json`
a `scale`, the number of sheet pixels per canvas pixel (default 1). `canvas`
stays in canvas pixels, and `x`, `y`, `w` and `h` are in sheet pixels.

## Long clips

A long clip on a wide canvas packs into sheets of 30 Mpx and more. Shown in all
four facings, the browser cannot keep such sheets decoded, and the viewer stalls
on every frame: stepping the Collie Royal Guard's guard idle (227 frames on the
1000 × 960 canvas, 31–37 Mpx a facing) took 1.5 s a frame. `split_sheets.py`
here re-packs such a clip from its rendered frames into bands of whole rows of
at most 4 Mpx:

```sh
python split_sheets.py <frames dir> <card folder> <clip>[,<clip>...] [max Mpx]
```

Run it after the packer, on the same frames, then copy the card's `frames.json`
into the page's `#frames-data`. The clip's entry then lists its bands in
`"files"`, with `"per"` frames in each, in place of `"file"`; the crop, cell
and grid stay as packed. The viewer fetches each band and decodes it off the
main thread, and keeps only the band shown and the next decoded, so a step
takes a few milliseconds. Opened from disk, without `fetch`, it loads the bands
as images, which decode when first drawn.
