# External references

Art outside this repository, kept as links only; its images are not stored
here. Use each link only for the role given below. The reference images in
this folder stay canonical.

## CraftPix

Both links below are CraftPix pages, so the same licence limits apply.

- **Licence:** section 3 of the [CraftPix file licences](https://craftpix.net/file-licenses/)
  covers free and premium assets. It forbids using them "for the purposes of
  training, fine-tuning, developing, testing, validating, or improving any
  artificial intelligence" and does not mention generator inputs. To stay
  clear of it, do not upload CraftPix images to fal, Higgsfield or any other
  generator, and do not copy them into this repository. Describe the wanted
  qualities in our own words; the prompt rules in
  `source/game/art/ART_PLAN.md` already forbid naming other games or artists.
- **Not a reference for:** camera, proportions, palette or rendering. Meridius
  uses a high-angle isometric camera, realistic proportions and painterly
  detail (see `docs/plan-phase-1.md`). CraftPix sprites are mostly chibi or
  low-resolution, top-down or side-view.

### 2D sprites catalogue

<https://craftpix.net/categorys/sprites/>, all pages of the listing
(`/page/2/` onwards).

Checked on 21 October 2026: 48 pages of about 16 packs each, free packs and
premium ones ($5.50 or membership). The first two pages held character sprite
sheets (knights, swordsmen, samurai, shinobi, witch, priest, dragon, demons,
mythology figures), bosses, ghosts, a market square with NPCs, and effect
packs (magic, buffs, water, explosions). New packs are added over time, so
each page shows different packs later.

Subcategories, most relevant to Meridius first:

| Subcategory | Link |
| --- | --- |
| Medieval | <https://craftpix.net/categorys/medieval-sprites/> |
| Monster | <https://craftpix.net/categorys/monster-sprites/> |
| Effects | <https://craftpix.net/categorys/sprite-effects/> |
| Top-Down | <https://craftpix.net/categorys/top-down-sprites/> |
| Pixel Art | <https://craftpix.net/categorys/pixel-art-sprites/> |
| Tower Defense | <https://craftpix.net/categorys/tower-defense-sprites/> |
| Cartoon, Shooter, Zombie | `cartoon-sprites`, `shooter-sprites`, `zombie-character-sprites` under <https://craftpix.net/categorys/> |

- **Role for Meridius:** browsing for ideas, not for a look.
  - Animation coverage: which states each character sheet includes.
  - Effects: how magic, water and explosion effects stay readable at small
    sizes. Useful for `game-vfx-workflow`.
  - Enemy variety: bosses and monster types for later tiers.

### Swordsman 7–9 Level Pixel Top-Down Sprite Character Pack

<https://craftpix.net/product/swordsman-7-9-level-pixel-top-down-sprite-character-pack/>

Checked on 21 October 2026 from the product page and its preview images.

- **What it is:** three swordsman tiers (levels 7, 8 and 9) as chibi pixel
  sprites seen from above, four directions, PNG and layered PSD. Premium
  download (CraftPix membership); not bought for this project.
- **Animations listed:** idle, walk, attack, walk attack, run attack, heavy
  attack, run heavy attack, hurt and death. The page gives no frame counts or
  sprite sizes.
- **Role for Meridius:**
  - Animation coverage: the states a melee unit needs (idle, move, attack,
    heavy attack, hurt, death).
  - Tier progression: the same unit looks stronger at each level through
    trim, gold and silhouette (horns, crests, a second sword). Useful for unit
    upgrades.
  - Effect readability: the heavy attack's bright arc stands clear of the
    figure.
