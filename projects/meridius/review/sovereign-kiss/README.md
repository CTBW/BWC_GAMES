# Sovereign Kiss

24 October 2026 · Meridius · Succubus–German squad · Pink fog revision

**Delivered:** the approved pink-fog schematic, matching 2048 × 2048 ability icon, editable SVG and Blender handoff. The user approved the painted fog direction: a heart blown from the lips, passing through opponents and becoming increasingly translucent until it evaporates beyond them. The final icon was generated through the requested Higgsfield Nano Banana Pro Unlimited route. These are concept and motion specifications, not an implemented ability or animated Blender file.

## Files

- [Workspace presentation](../../../../workspace/2026-10-20_meridius/sovereign-kiss.html)
- [Approved pink fog schematic](../../../../workspace/2026-10-20_meridius/sovereign-kiss/sovereign-kiss-fog-schematic.webp)
- [Recommended pink fog icon](../../../../workspace/2026-10-20_meridius/sovereign-kiss/sovereign-kiss-icon-fog-b.png)
- [Earlier Warcraft A exploration](../../../../workspace/2026-10-20_meridius/sovereign-kiss/sovereign-kiss-icon-warcraft-a.png)
- [Editable fog construction sheet](../../../../workspace/2026-10-20_meridius/sovereign-kiss/sovereign-kiss-fog-construction.svg)
- [Blender handoff](../../../../workspace/2026-10-20_meridius/sovereign-kiss/blender-handoff-fog.md)
- [Formatted Blender handoff](../../../../workspace/2026-10-20_meridius/sovereign-kiss/blender-handoff.html)
- [Schematic revision prompt](schematic-fog-prompt.txt)
- [Final fog icon prompt](higgsfield-fog-b.txt) · [Earlier Warcraft A prompt](higgsfield-warcraft-a.txt)
- [Initial ImageGen prompts](prompts.json) · [Revision and approval record](fog-revision.json)

## Direction

The squad blows a large heart-shaped cloud of pink vapor from their lips. Twin lobes and a cleft remain clear early in travel; transparent gaps widen as the cloud passes through opponents. It continues past the target formation and dissolves into detached wisps. Each successfully enthralled target receives a small pink fog-heart marker. The earlier solid heart, amber rim and split-on-contact design are superseded.

Working title: **Sovereign Kiss**. Small squad lip wisps can converge into one shared fog heart. Apply contact once per eligible target per cast, without consuming the travelling cloud. The number of affected targets, duration, resistance, range, cost and cooldown remain gameplay decisions. No balance values or game files were changed.

The character identity comes from the existing `references/characters/succubus_idle/succubus_ref_full.png`. Existing rig sources establish a left-handed whip, Mixamo body naming, separate wing/tail controls, 1.95 m reference height and a -Y facing direction. The technical handoff specifies the free right hand for the kiss. The generated storyboard is an expressive pose reference: its gather panel uses both hands and must not override this rig-aware hand assignment. The hero heart is deliberately enlarged for presentation; use the construction sheet's proposed dimensions when blocking the animation.

The user's [Ahri reference](https://www.leagueoflegends.com/en-us/champions/ahri/) supplies the kiss/charm idea. No game textures, icon art, character model or animation were extracted from League of Legends.

## Provenance and review

Built-in ImageGen produced the first schematic and icon, then edited the schematic into the approved pink-fog version. Exact model/seed are not exposed by that tool. Source references and prompts are retained; originals were copied into the Workspace folder. Git holds WebP copies of the ImageGen boards; their full-size PNGs and the Higgsfield icons stay local. The SVG and handoff were authored locally. The revised icons use the Higgsfield website, Nano Banana Pro, 2K, square, one image per generation, with Unlimited visibly enabled. The site allows one Unlimited generation at a time. Job receipts remain in ignored `.cache/sovereign-kiss/`, outside Git. No Tripo jobs, paid fallback or subscription changes were requested.

Visual review: the revised caster preserves blonde hair, ears, horns, wings, costume and tail. Dense pink fog, passage through armor and evaporating wisps are visible. The main view exaggerates effect scale for presentation; use the technical sheet for the proposed blockout. The first Higgsfield take was rejected for an unwanted “8%” measurement label and smooth rendering. Two further tries completed: Warcraft A and pink fog B. A is a clean painted solid-heart exploration, superseded by the fog revision. B is recommended: pink rolling vapor forms a readable heart, the lips are fully framed, and no text, measurement guides or gold border are present. The center is deliberately open, emphasizing the fog. Both originals are 2048 × 2048 PNGs. No image C was submitted; its draft prompt is retained as unused exploration. Native game readability, runtime cost and animation quality require later implementation checks.

The pink-fog schematic is approved; the matching icon is recommended for user review. No existing character asset was modified. Report links and media were checked, and the image lightbox opens and closes correctly. Rebuild the report with `node projects/meridius/review/sovereign-kiss/build-report.mjs` and the formatted notes with `node projects/meridius/review/sovereign-kiss/build-handoff.mjs`.
