# Pose viewer

The frame viewer on the Meridius rig tabs: Footman, Crossbowman, Spearman,
Succubus, Mage and Goblin Rabble. Build every new rig or animation review on it instead of a
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
| Goblin Rabble | `projects/meridius/references/characters/blender/goblin_rabble/tools/render_clips.py` | `pack_sheets.py` beside it |

Rig folders are under `projects/meridius/source/godot/art/` unless the path says
otherwise.

The viewer also reads sheets rendered larger than the canvas. Give `frames.json`
a `scale`, the number of sheet pixels per canvas pixel (default 1). `canvas`
stays in canvas pixels, and `x`, `y`, `w` and `h` are in sheet pixels.
