# Boss concept and image handoff

## Current stone troll and species revision - 24 October

The user likes the ruined houses across take 4's shoulders and back, as if
people built on him while he slept. Preserve that specific feature. The new
request is a more stone-like troll, much closer to the supplied woodland
species, with no ears and the game's established character style.

The troll, Footman, Orc Warrior, goblin, Wolf Scout and mage sources were
visually compared. Species authority remains the supplied troll sheet;
Footmen anchor the grouped painted shading and controlled contours. See
stone-troll-style-review.json for sources, roles and visual acceptance checks.
Take 5 used four inputs and removed the ears, but preserved too much of the
human-like face and smooth body. Its original and honest review remain saved.
Take 6 uses the species sheet directly, the approved shoulder crop and Footmen;
the earlier full-body base is omitted to stop that unwanted anatomical pull.
Take 6 improved stone material but produced a numbered front/back sheet and
small visible ears. Take 7 narrows the inputs to the original troll species and
approved ruin crop, with one uninterrupted scene and no visible ears.
Exact prompts and reference roles are recorded in corrections.json.

Take 7 is prepared in Brave tab 1740365029, Nano Banana Pro, 2K, 16:9,
with two references and green Unlimited verified. A blank Quick check dialog
blocks submission; no take 7 job ID exists. The user was asked to complete
that verification. After it clears, inspect the feed for a new job before
submitting again. All 21 completed originals are downloaded and reviewed.
Takes 5 and 6 are intermediate results, not a completed stone-troll design.
Keep all earlier takes and the six-design roster.
The user approved the shoulder feature only, not the whole previous character.
Use .cache/boss-art/sync-stone-troll.mjs then build.mjs for this revision.

## Previous hulking troll revision - 24 October

The user requests a smaller troll with a hulking standing posture, much less
root and tree growth, and broken ruin fragments instead of complete houses.
Take 3 successfully removed the tall trees and reduced the houses to broken
walls, but retained the crouch and enormous scale. It is preserved as an
intermediate correction, with that failure explicitly recorded in reviews.json.

Take 4 uses take 3 for old face, beard, materials and ruin treatment, plus the
central standing troll in the supplied species reference for upright body and
leg proportions. It asks for a new composition at about four human heights,
with four nearby soldiers establishing scale and small low shoulder remnants.
The exact submitted prompts remain in corrections.json and canonical briefs.

The Nano Banana Pro 2K, 16:9 Unlimited posture correction is complete,
downloaded and visually reviewed. Take 4 stands upright with a hulking build,
smaller human-relative scale, broken shoulder walls and reduced roots. All 19
originals remain preserved. No jobs remain pending. Take 4 awaits user review.
Use .cache/boss-art/sync-hulking-troll.mjs and then build.mjs for this revision.
Keep all earlier troll and colossus takes and the six-design roster.

## Previous ancient woodland troll revision — 24 October

The user requests the huge troll to resemble the supplied woodland trolls and
look old, with ancient roots and ruined small houses/tree houses on his back
and shoulders. The marked giant image specifies placement only. The terrain's
selected ruined cottage supplies timber frames, cream plaster, broken thatch,
stone footings and chimney. The selected intact cottage was also inspected.

Four inputs and their roles are preserved in `ancient-troll-references.json`.
The exact take 2 prompt is in `corrections.json`. One Nano Banana Pro 2K, 16:9
Unlimited job is complete, downloaded and visually reviewed. The 2752 × 1536
original and exact submitted prompt are saved in the canonical boss folder and
byte-identical gallery copies. All 17 originals remain preserved; no jobs remain
pending. Take 2 awaits user review. Upper back-tree branches reach beyond the
frame and four troop groups appear; these are later reference-sheet limitations.

Use `.cache/boss-art/sync-ancient-troll.mjs` for this revision, then `build.mjs`.
Keep the first troll take, all colossus takes and the six-design roster.
This is concept artwork only; no gameplay or 3D work is implied.

## Previous colossus aqua-eye edit — 24 October

The user likes take 3 and requests glowing aqua eyes. That take is recorded as
the approved base. Take 4 uses it as the only reference and changes the two eye
interiors with a restrained local glow; preserve the plain mask, black body,
dark-red details and full composition.

Use `.cache/boss-art/sync-aqua-eyes.mjs` for this revision. Current completion
state is in `production.json`; exact prompts are in `corrections.json` and the
canonical prompt files. Retain every earlier take and keep the latest first.

Take 4 is complete, downloaded and visually reviewed. Both eyes glow aqua with
a small local halo; the plain mask and dark design remain consistent with the
approved base. All 16 originals are preserved. No boss-image jobs remain pending.
The new eye-colour revision awaits user review; take 3 remains the approved base.

## Previous colossus face and palette edit — 24 October

The latest user request removes the nose and mouth, makes the eyes hollow black,
and changes the colossus to black and charcoal with dark-red details. Take 2 uses
the canonical pale first take directly as its single reference. Its palette
succeeds, but the face retains a nasal recess and mouth-like marks. Take 3 uses
that darker image for a focused plain-mask correction. Keep the pose, armour
construction, fur, sword, bright background and every original intact.
The display name and stable `pale_colossus` ID remain unchanged.

`corrections.json` records both exact edit briefs. `production.json` carries the
current completion state; private receipts stay in `.cache/boss-art/`. Use
`sync-colossus.mjs` for this revision, then rebuild the report. The new take
appears first in the colossus section, followed by the two preserved earlier takes.
The older `sync-revision.mjs` describes the preceding two-concept delivery.
The other five active designs are outside this edit.

Take 3 is complete, downloaded and visually reviewed. The mask now contains only
two hollow black eye sockets; the nasal recess and mouth-like marks are gone.
The black/charcoal materials and dark-red details remain, and the two short
lateral head projections are restored. All 15 original images are preserved.
No generation jobs remain pending. User acceptance is still separate from this
visual check; no 3D generation or gameplay changes were made.

## Current selection revision — 24 October

The user's marked gallery removes Edratha, the Arachne variant, Oath-Eater and
the old buried Crown. Retain Delver, Rauk, Veyr and the original spider Widow.
`selection.json` controls the active roster. `revision-2026-10-24.mjs` adds a
Giant Troll and a standing Pale Colossus based on the supplied stone-and-fur
reference, with lighter beige-grey materials. These are visual concepts; no
new encounter mechanics were requested. The active report hides removed designs
while the original files, prompts and earlier report remain archived.

The canonical references are under `concepts/references/`. The marked gallery
records selection only; attach only the separate colossus image to its generation.
Current execution records remain in `.cache/boss-art/`. Use
`sync-revision.mjs` there for this revision's production status; the older
`sync-production.mjs` describes the initial eight-design pass.

The sections below retain the initial pass's execution history. The current
selection above supersedes its original roster and generation count.

Editable source: `catalog.mjs`. Build with:

    node projects/meridius/review/boss-concepts/build.mjs

Output: `projects/meridius/docs/boss-concepts.md`,
`workspace/2026-10-20_meridius/bosses.html` and eight complete text prompts in
`workspace/2026-10-20_meridius/bosses/prompts/`.

Targeted Rauk and Veyr edit briefs are in `corrections.json`. Their original
images are the edit references. Keep the initial and corrected takes together;
the gallery shows the latest take and each boss section preserves its history.

## Generation dependency

### Current continuation — 24 October

All 101 required terrain concepts are complete with no active terrain jobs.
The eight optional materials are outside that dependency. The old terrain tab
was absent from the live inventory, and a new dedicated boss tab was acquired
without an ownership refusal. Do not read the historical observations below as
the current terrain state.

The earlier Rauk job completed and was recovered from the website. Preserve its
original and exact submitted prompt. The user then requested original designs
from the written briefs, so the current initial prompts are text-only.
`production.json` and the image manifest carry current completion counts;
`reviews.json` records visual findings separately from user approval.
Private attempts and credit checks live under `.cache/boss-art/`.

All eight initial concepts are now downloaded. Targeted edits retain every
earlier take, including edits that did not fix the requested defect. The next
production step is character selection, followed by clean modeling references;
encounter illustrations alone are not verified 3D reference sheets.

Download routing is explicit in the boss downloader and Tripo collector.
The browser's global save-folder setting was not changed because browser
security policy blocked access to its settings page. The Blender connector was
unavailable, so its application defaults and live imports were not changed.
Nineteen existing Tripo exports were copied from the misplaced download folder
into `characters/tripo/` and verified by SHA-256; source files were preserved.

Run one confirmed job at a time. During this session, submissions attempted
while another job was active did not appear in the refreshed history. Reconcile
the recorded job before advancing, and do not mistake a delayed gallery update
for failure. After a submission, refresh the gallery and inspect the visible
card's `data-asset-id` and `data-job-status`; keep that ID immediately. Completed
showcase details identify the subject and expose the original image URL.

`production.json` is the public status source used by the report builder; update
it after generation, download and review. It must distinguish confirmed jobs,
downloaded images, agent review and user approval. The browser and upload IDs
are in the ignored session record. No game implementation was requested.

### Historical dependency and standing authorisation

On 23 October the user explicitly reaffirmed permission to start these images
in Higgsfield once the terrain chat finishes, taking over its released session
and using the same checks to keep Unlimited enabled. This is standing
authorisation for the eight prepared concepts, their reference uploads,
generation, downloads and routine visual corrections. Do not ask for that
permission again. It does not authorise interrupting terrain, buying credits,
switching to paid mode or bypassing a browser ownership/access boundary.

The user explicitly asked to take over generation after GPT – Terrain &
Battlefield finishes. The initial inspection found its queue still
`in_progress_unlimited`, with 55 completed items, 41 pending and one waiting.
Attempting to bind the terrain tab returned that it was already part of
another browser session. That is an active ownership boundary, not permission
to replace the tab, use native automation around the claim, submit through a
second tab, or cancel the recorded terrain job.

Keep the boss work prepared while terrain runs. Read current queue status with:

    node projects/meridius/review/boss-concepts/status.mjs

This is a **read-only status check**, not an unattended queue or browser worker.
Prepared files do not automatically start generating when terrain finishes.
Reconcile completion/release, then use the supported browser tool to acquire a
released session. If the tool still refuses the claim, retain the queue and
report that exact limitation. Do not modify the terrain queue to mark it done.

The terrain `queue-status.mjs` helper was observed to contain older Unlimited-off
text. Its latest README, direction document and queue require **Unlimited ON**.
Use the latest user direction and verify the live green switch before every
submission; do not inherit the stale helper's setting.

## Same generation flow, new subjects

- Higgsfield website in the logged-in Brave session; Nano Banana Pro, 2K,
  16:9, exactly one image per submission; Unlimited ON (green).
- Eight initial compositions for seven encounters, in `imageSubjects` order.
  The Sanguine Delver first, then Rauk, Edratha, Veyr, Widow (original spider),
  Silk-Crowned Widow (Arachne variant), Oath-Eater and Crown. Preserve both Widow
  versions. The Arachne has an adult female upper body, two human arms, a
  continuous waist-to-cephalothorax junction, eight spider legs and no human legs.
- Current initial concepts use written briefs only, with zero attachments.
  The earlier style references and crawler motif remain historical context;
  do not attach them to a prompt that says it has no image references.
- Clear the rich-text prompt editor before inserting the full prompt. Verify
  exact text, reference order/count, model, size, aspect, quantity and Unlimited.
- Compare the credit balance before and after each generation, as in terrain.
  Keep account figures in ignored `.cache/boss-art/credit-checks.json` only.
  Pause additional submissions on an unexplained decrease; inspect the live
  mode and shared-account activity. Do not buy credits or change plans.
- Immediately record the observed job ID, take, prompt ID, status and model in
  ignored `.cache/boss-art/jobs.json`. Keep original URLs only there. After a
  timeout recover that same job; if submission outcome is uncertain, reconcile
  history before retrying. Never create a duplicate merely because a wait ends.
- Save each original in `projects/meridius/references/characters/bosses/concepts/`
  as `boss_ID__take-01.png`, incrementing the take and preserving all originals.
  `download-originals.mjs` copies identical bytes to the Workspace report for
  preview. Exact submitted prompts live under `concepts/prompts/`; current
  generation briefs live under `concepts/briefs/`.
- Boss Tripo exports go in `characters/bosses/tripo/<boss>/` and editable scenes
  in `characters/bosses/blender/<boss>/`. Use
  `scripts/asset-delivery/collect-tripo.ps1 -Boss` for observed downloaded files.
  Other characters use `characters/tripo/<character>/` and `characters/blender/`.
  Never use the browser's remembered ability-icons folder as final storage.
- Inspect anatomy, scale, framing, style, the six-squad scale cue, believable
  mechanics and readable movement space at full size and reduced battle scale.
  Check that scenery has not been copied from a style reference.
- Make a targeted correction using the rejected image as a reference with an
  explicit limited change. Preserve rejection notes. After three failed takes
  on one concept, retain the evidence and continue the independent concepts.
- Keep image success, agent visual review, user acceptance and engine readiness
  distinct. Do not integrate images or gameplay automatically.

## Review emphasis

Sanguine Delver: low many-legged crawler silhouette, shell distinct from fungus,
readable stain/bloom/undercut zones, stable stone escape circuit, no piles of
corpses or random blood effects hiding anatomy.

Rauk: bell mass and believable yoke. Widow: eight coherent legs and readable
web anchors. Arachne variant: clearly adult female upper half, readable organic
torso junction, exactly two human arms and eight spider legs; never a separate
rider. Retain the original Widow's arena and rendering for comparison.
Edratha: visibly wooden corrupted dryad, one organism and one root
crown. Oath-Eater: long grasping forearms and upright wolf-man silhouette. Veyr:
four legs plus two wings, readable chest opening and shelter geometry. Crown:
body continuous with the terrain, human scale cues and two connected flanks.

## Verification scope

The report's erosion diagram is an explanatory diagram, not Godot gameplay or
a navigation simulation. Numerical dimensions and damage budgets need a later
prototype. The original game files and other agents' generated assets remain
outside this concept pass's edit scope.
