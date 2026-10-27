# Unit bar: asset list

The battle's unit bar (`source/godot/scripts/ui/unit_bar/`) is a console
centred at the bottom of the battle screen, after Warcraft III's. It shows the
selected squad, or a foe the player right-clicks to look it over (its stats,
conditions and abilities). Part of it is painted art already in Git; the rest is drawn in
code as a placeholder. This list says what each piece is now and what would
replace it. Sizes are on the 1920 × 1080 canvas: the game stretches every 16:9
window to it, and an ultrawide window widens it, but the bar keeps these sizes.

The layout as of 26 October 2026, after the owner's mark-up: no battlements
and no end pillars, a 216 px high slab 1510 px wide in the bottom centre, and
no facing rose.

## Layout

| Piece | Size | Where |
| --- | --- | --- |
| Console slab | 1510 × 216 | Bottom centre; a 9 px brass rail along its top |
| Minimap window | 206 × 183 | Left |
| Portrait window | 186 × 183 | The frame (181 × 143, opening 152 × 116) stands 9 px above it; its crest reaches the rail |
| Health / morale readouts | 178 × 22, 178 × 16 | Under the portrait |
| Middle window | 638 × 183 | Name banner (376 × 30) with the level medallion; type line; six stat plaques (120 × 40) in two rows; status row (34 px icons); the men (50 × 60 each, 42 px faces; smaller for a nine-man squad) under the turn tags |
| Gear window | 132 × 183 | 2 × 3 item slots, 52 × 44 |
| Command card | 264 × 183 | 4 × 3 buttons, 56 × 56 |

## In Git already

| Asset | Path | Used for |
| --- | --- | --- |
| Command panel | `assets/ui/epic/command-panel.png` | The windows' frames (brass corners) and floors |
| Council frame | `assets/ui/epic/council-frame.png` | The portrait frame of the company's squads |
| Foe frame | `assets/ui/epic/foe-frame.png` | The portrait frame of a foe (timber, stone, rusted iron, red gems); see `art/ui/epic/README.md` |
| Painted icons | `assets/icons/painted/*.png` | Abilities on the command card, stats, conditions: `bolt`, `horn`, `shield`, `stone`, `blood`, `frost`, `growl`, `eye` and the ability icons |
| Headshots | Rendered at run time (`head_portrait.gd`) | The portrait and the men, from each man's own 3D figure. Where there is no figure, the type's baked portrait (`portrait_<type>`) is used |

## Placeholders drawn in code

| Piece | Now | Replacement wanted |
| --- | --- | --- |
| Stone slab | A shader (`console_frame.gd`, `STONE_SHADER`): bricks in running bond, moss, cracks | A painted stone wall in the battlefield's style that tiles horizontally, 512 × 216, plus a left and a right end, 16 × 216 |
| Brass rail | Bevelled rectangle with rivets every 96 px | A strip that tiles horizontally, 256 × 12, with a rivet |
| Name banner | A ribbon (`bar_style.gd`, `ribbon`), blue for the company and red for a foe | A painted ribbon in both colours that stretches as a 9-slice, 376 × 30 |
| Level medallion | Brass rings, 38 px | A painted brass medallion, 40 × 40, with an empty centre for the number |
| Stat plaques, item slots, status frames | Dark slabs with fine brass edges | Optional: a small 9-slice plaque |
| Turn tags ("Can move", "Can act") | Enamelled chips (`bar_style.gd`, `chip`) | None needed |
| Health and morale bars | Drawn bars with a damage ghost and a fill sweep | None needed |
| Minimap | Drawn from the battle's tiles and squads | None needed |
| Command marks | Drawn check, next and undo marks (undo is also a foe card's Back) | Painted icons `check`, `next`, `undo`, 64 × 64 |

## Icons without painted art

These names still fall back to the vector icon set (`scripts/ui/widgets/icon.gd`).
Each wants a 128 × 128 painted icon in the style of `assets/icons/painted/`:

- Stats: `sword` (damage and melee), `march` (move), `morale`.
- Conditions: `injury` (wounded or injured, and lasting injuries), `fatigue`.
- Gear: `bolts` (a crossbowman's bolts). Weapons and armour use the type's icon.

## Sounds

The bar plays these cues through the `Sfx` autoload (`bar_style.gd`, `SOUNDS`).
None of the bar's own events is in `assets/audio/bank/bank.json` yet, so each
plays the fallback shown:

| Cue | Event wanted | Falls back to |
| --- | --- | --- |
| The bar rises | `ui_bar_open` | `page` |
| The bar sinks | `ui_bar_close` | `page` |
| Another squad in the bar | `ui_unit_swap` | `click` |
| A command used | `ui_command` | `click` |
| Hover on a plaque or slot | `ui_hover` | None |
| Hover on a command | `ui_ability_hover` | None |
| Health below a quarter | `ui_low_hp` | None |
| A refused click | `deny` | In the bank |

## Checks

- Unit tests: `tools/test.sh test_unit_bar test_battle_hud`.
- The bar in the game's 3D battle on Ashby farm, in a window, at each size:
  `tools/godot.sh --path . --resolution 1920x1080 -s res://tests/visual/unit_bar_battle.gd`.
  Also run it at 1280x720 and 2560x1080. The bar is checked only there (the
  owner's rule of 27 October 2026: no small labs).
- A foe in the bar: the capture above ends turns until a foe is in sight,
  then right-clicks it (the squad stays selected), goes back with Esc and
  left-clicks it with nothing selected.
