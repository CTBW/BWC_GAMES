# Meridius terrain generation workflow

## Brave execution contract

- Use the dedicated terrain tab in the logged-in Brave session. The user updated the instruction on 23 October: keep Unlimited ON (green), check before each submission and re-enable if it changes. Leave the icon tab and its Unlimited workflow untouched.
- Use the Higgsfield website, Nano Banana Pro, 2K, one image per submission. Check the aspect ratio, references, exact prompt, quantity one and Unlimited ON before each submission. Earlier 59 regular-mode submissions displayed an estimated 2 credits each; this is not a billing reconciliation. New submissions use Unlimited as now requested. Do not buy credits or change plans.
- Night edits now use only the matching reviewed daytime original, preserving its exact layout while changing lighting. Earlier three-reference jobs retain their submitted prompts in the ignored receipts. Wider road scenes use the original two style references.
- For day concepts, attach reference 1 then reference 2 from the local reference folder. Night edits use the matching reviewed daytime original alone. The full prompt states each image's role. Do not reuse the ability-icon references. Start with the six pilot prompts below and visually check their match to the supplied art; the supplied references already establish the requested direction, so routine matching corrections do not need a new user decision.
- Save originals inside workspace/2026-10-20_meridius/terrain/originals/. Use PROMPT_ID__take-01.png, then increment the take number. Keep every original. This destination is inside the writable workspace; do not change global browser download or security settings.
- Record the submitted asset ID and status immediately in .cache/terrain-art/jobs.json. Record any original download URL only in that ignored file. On a timeout, inspect that same job. Never resubmit solely because a wait expired. If submission may have succeeded but its ID was not captured, reconcile the website history before retrying.
- The fixed local downloader validates known original-image URLs, PNG dimensions and destination names. Local writes stay inside the workspace. Restricted network access may still require a narrowly scoped download-command approval; no script can remove platform approval requirements.
- Check each original at full size and at a reduced game-like size. Accept only after reviewing camera, silhouette, complete framing, material style, lighting, unwanted reference fragments and requested content. For cutouts, inspect every gap and the background edge. For scenes, inspect movement space and continuous slopes. For materials, inspect a 3-by-3 repeat before acceptance.
- Make targeted correction takes using the failed image as an additional explicitly assigned reference, preserving everything except the named defect. After three failed takes on one item, preserve the evidence and move on to the next independent item; report the unresolved item.
- No additional user approvals are needed for already-authorized prompts, reference uploads, visual corrections or workspace saves. If the tool cannot identify the page, authentication is required, or an actual permission boundary is reached, stop the dependent action and retain progress. Do not buy credits, change account settings or bypass a blocked UI tool.
- This is an agent-run queue, not an installed unattended browser service. Generation started with regular credits and now continues in Unlimited mode; the reviewed local originals are listed in this report. Recover recorded jobs before submitting new takes.

## Generation order

First: Mature green oak, Sunlit meadow battlefield, Timber and thatch cottage, Broken stone arch, Orc war pit, Ancient dragon lair. Then the remaining required prompts in catalogue order. The eight ground materials are optional companions after the requested objects and scenes; existing terrain textures remain intact.

## Delivery checks

Preserve editable prompt sources and original images. Generated art is not yet a Godot-ready sprite, seamless texture or playable map. Cutouts still require extraction, scale and anchor checks; scene designs require layout and navigation work; texture seams require verification. Keep game integration as a separate step and do not edit the frozen TypeScript game.
