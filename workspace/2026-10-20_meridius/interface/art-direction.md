# Meridius interface art direction

Updated 23 October 2026. Implemented in `source/godot` on `godot-migration`.

## The Nordmark frontier

The interface should feel like equipment belonging to the Amberfeld Company:
warm vellum, blue cloth, dark iron and worn brass fittings. Warcraft III informs
the substantial, readable frames and clear action hierarchy; Diablo II informs
the restrained metalwork and tactile surfaces. These are original procedural
frames, not extracted interface assets.

The title shows a bright early-morning forest overlook with a visible rising sun,
mist in the valley, a river and a modest timber garrison. Its greens and painted
terrain follow `references/backgrounds/Battlefield 1.png`. The campaign map,
style references and blue-armoured unit references supplied the surrounding
palette. The darker gate-and-torch title study was superseded at the user's request.

**Do not add heraldic symbols.** Frames use abstract lines, corner fittings,
rivets and small lozenges. Existing unit art and gameplay icons are unchanged.

## Material and hierarchy contract

| Element | Treatment |
| --- | --- |
| Main panels | Warm vellum, dark ink, substantial iron binding with brass highlights |
| Screen and building headings | Blue cloth-like band with cream Cinzel lettering |
| Battle and campaign HUD | Opaque charcoal-blue surface, narrow metal rim, clear light text |
| Primary march/combat actions | Muted red enamel; brighter rim for hover/pressed/focus |
| Continue and blue actions | Blue enamel, cream text |
| Hire/build and selected cards | Warm gold, dark ink on gold faces |
| Secondary actions | Dark iron or quiet inset parchment according to context |
| Portraits | Fine metal surround; original portrait image remains inside |
| Separators | Fine engraved lines and abstract diamond details |
| Status tags | Preserve blue/red/gold/green semantics on both theme surfaces |

Small controls receive simple rims. Major panels receive corner fittings and
subtle centre inlays. Ornament stays out of the text area. Corners are drawn in
screen pixels rather than stretched with the panel. Existing HP, morale and
soldier-count cues keep their meanings.

The title backdrop uses aspect-cover scaling. There is no screen-wide dark
overlay: the menu panel and local text shadows provide contrast. Its sun,
garrison and forest remain visible in the reviewed desktop crops.

## Editable sources

- `source/godot/scripts/ui/styles/forged_style.gd`: reusable metal geometry,
  based on the existing paper texture style.
- `source/godot/scripts/ui/theme_builder.gd`: materials, palette, states and
  spacing. `theme_build_cli.gd` rebuilds both saved theme resources.
- `source/godot/scripts/ui/widgets/title_regalia.gd`: symbol-free title frame.
- `source/godot/scripts/ui/widgets/flourish.gd`: engraved separators.
- `source/godot/scripts/ui/screens/title_screen.gd`: title composition.
- `source/godot/assets/ui/frontier_title.png`: original generated sunrise PNG,
  also used directly as the runtime backdrop. No destructive paint edits.
- `source/godot/art/ui/frontier-title.md`: art provenance and generation direction.

`UI.theme_stylebox()` preserves explicit overrides before resolving an
unparented control's theme. This prevents custom padding from disappearing when
a panel receives additional decoration. A regression test covers the case.

## Review and reproduction

Run `tools/import.sh` after replacing artwork, then `tools/review_ui.sh` from
`source/godot`. The latter rebuilds the themes, captures 23 real game scenarios
at 1920×1080 and repeats title, roster, preparation and live battle at 1440×900
and 2560×1080. It then runs the existing input-driven playthrough with dummy
audio. The review uses a separate save and restores preferences.

Native framebuffer captures are in `tests/visual/out/ui-art-review/` and the
input playthrough evidence is in `tests/visual/out/playthrough/`. Selected
unchanged PNGs and logs are delivered in
`workspace/2026-10-20_meridius/interface/`, with a review in `interface.html`.

The input harness tracks physical window enter/exit notifications separately
from its synthetic pointer and reasserts that pointer before querying hover.
This prevents a physical mouse leaving the window from invalidating a synthetic
button hit test. Normal GUI hit testing and game-state assertions remain active;
no button signals are emitted directly by the playthrough.

The captured baseline was the existing dirty working tree at commit `8adca51`;
unrelated audio, squad, terrain and content work was preserved. Before/after menu
comparisons use the same capture scenario and seed. Animated world details can
differ between frames. The title deliberately changes the background composition.

The final quick suite passed 364 tests, with zero failures and 10 long tests
skipped, in 201.6 seconds. The final native pass captured 31 scenarios with zero
rendering/runtime errors.
The input-driven expedition passed 184 checks with zero failures, errors or
warnings, including a complete battle and a return to title. The HTML review was
checked at 1440 and 1024 pixels wide in both report themes, including image
enlargement, download and close controls.

Agent visual review is complete for the delivered captures; aesthetic acceptance
remains the user's judgment. This review does not claim a Windows export or a
complete AI campaign regression run.
