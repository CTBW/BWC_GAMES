# Meridius terrain and site artwork

`catalog.mjs` contains 101 requested images and 8 optional ground materials: the
original 50 subjects, four wide forest roads, three deforested landscapes, six
palisaded army camps, four corrupted landscapes, two northern forest comparisons
and 32 matching night locations. The two supplied images
remain the primary style and camera references.

The user approved the camp layouts and refined the woodland direction toward
imposing northern European forests with darker greens, denser tree layers, wild
undergrowth and drifting fog. A separate clear-day comparison uses just taller,
thicker northern forest without the fog or gloomy weather treatment.
The three earlier camp concepts also have forest-only correction prompts; keep
their approved camp geometry and use the revised versions for the night edits.

The latest user instruction supersedes the earlier credit-mode instruction:
keep Unlimited ON (green), check before each submission, and enable it if it
changes. Also compare the credit balance before and after generation. If it
falls, pause the next submission and inspect the mode; the shared account's
other activity can also affect the balance. Do not buy credits or change plans.
Leave the separate icon tab alone.

Later in the run, the account balance fell while the terrain generator still
showed Unlimited, then fell again while terrain submissions were held. The
account total therefore cannot attribute charges to a particular job. Record
each observed balance, inspect any decrease, and verify the green switch and
UNLIMITED submit button before continuing. Do not claim this session's total
cost is reconciled from the balance alone.

Use the dedicated Brave terrain tab, Higgsfield website, Nano Banana Pro, 2K,
one image per job. Clear the rich-text editor before inserting a prompt and
verify exact text: merely filling it can append to existing content. Check
reference order, model, aspect ratio, quantity and Unlimited before submission.

Day concepts use both original style references. Remaining night edits use only
the matching reviewed daytime source and preserve layout while changing lighting.
This source already carries the supplied references' style. Earlier night jobs
used three references; their actual inputs remain recorded in the job receipts.
Targeted corrections use the affected source and state the exact changes.
Preserve every original and rejected take.

All six camp night views and all three deforested night views are reviewed.
The river camp needed a strict single-source lighting correction after layout
drift; the dry basin needed one after invented cabins appeared. Wilderness night
prompts now explicitly forbid added structures and artificial lights. The remaining
night prompts use a single accepted source to reduce composition drift. Actual
submitted prompts remain in the job receipts when the catalog is revised.

Build from the repository root with:

    node projects/meridius/review/terrain-prompt-pack/build.mjs

The searchable report is workspace/2026-10-20_meridius/terrain-prompts.html.
Review notes and selected originals come from terrain/review.json. Keep related
revisions in this existing Meridius card.

The required concept set is complete: 101 reviewed subjects, 128 generated
originals and the two supplied style guides. The final clear northern forest
night view was completed after the user authorized resuming Unlimited. Its
before/after balance was unchanged; this observation covers that job only.
The eight optional ground materials remain unsubmitted. Existing isolation
limitations below still apply; concept completion is not engine integration.

Queue, job IDs, original URLs and credit checks are in .cache/terrain-art/,
excluded from Git. The first 59 submissions used the earlier regular-credit
instruction; later ones use Unlimited. Estimates are not billing reconciliation.
Record observed job IDs immediately and recover them after a timeout. The
website's Unlimited image route currently runs one image job at a time on its
shared queue; see [Higgsfield's Unlimited explanation](https://higgsfield.ai/blog/new-unlimited-more-models).
Do not repeatedly press Generate while the recorded job is pending. This queue
is an agent-run work list, not an installed unattended browser service.

A long-running "Generating" card can be stale: one frontier camp result became
visible only after a page refresh. Refresh the existing job rather than submit
a duplicate, then restore and verify Unlimited immediately because reloading
the generator resets that switch. Confirm the balance before the next job.

The normal generator's Draw option was inspected for fragment cleanup. In this
session it routed to Draw to Edit on the video page, but its media picker accepted
videos and did not load the PNG. No Draw generation was submitted. Return to the
recorded Nano Banana Pro URL and restore Unlimited after this navigation.

The fixed downloader validates observed CDN originals, PNG dimensions and local
filenames, and preserves every take. Run download-originals.mjs --check for a
read-only audit. Inspect full-size and reduced images before accepting a source.
Cutout, scale, anchor, seam and navigation preparation remain separate steps.

Background cleanup is unresolved for the moss outcrop, grassy bank, straight road,
road corner and bridge: isolated fragments persisted despite targeted prompts.
The moss sequence reached three takes, including an explicit clean-asset prompt,
without removing its fragment. Do not automatically repeat this ineffective edit
on the other sources. The lakeshore also retains a water cross-section after its
soil block was removed. The gallery labels these as concept references requiring
later preparation. They do not prevent completing the independent night scenes.

The battlefield/campaign crowd-removal change is already verified in Godot;
see terrain/map-edge-review.md. It uses existing game terrain. Generated artwork
has not been integrated.

The user requested local copies in the existing Battlefield/background and style
reference collections. After downloading and reviewing new originals, run:

    node projects/meridius/review/terrain-prompt-pack/sync-reference-library.mjs
    node projects/meridius/review/terrain-prompt-pack/build.mjs

The sync preserves every take, groups day/night versions by subject, copies the
two primary style guides, and verifies each PNG with SHA-256. It does not overwrite
different existing files. The index is projects/meridius/references/terrain-library.md;
collection folders live under references/backgrounds/terrain and references/style/terrain.
The existing terrain report exposes the collection summary and a downloadable file
manifest. Private job receipts, remote URLs and credit details stay in .cache.

Current hold: 100 of 101 required subjects are reviewed, including 31 of 32 night
views. Only road_forest_northern_clear_night remains unsubmitted. The account balance
fell again while the terrain form continued to show a green Unlimited switch and
an UNLIMITED button. The switch was reapplied, but the cause of the deductions is
unknown; the user was asked whether other credit-using generations are active.
No job is pending. Keep this final submission on hold until the discrepancy is
clarified. The matching daytime upload is staged and its receipt is in the ignored
queue. Once resolved, clear review.json's generationState and the queue hold,
finish that one night view, then sync the reference library and rebuild the report.
