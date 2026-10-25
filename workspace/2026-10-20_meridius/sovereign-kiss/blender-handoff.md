# Sovereign Kiss — Blender handoff

**Succubus–German squad · Proposed design · 30 fps · 23 October 2026**

The squad blows an oversized magical heart from their lips. It travels as a rose core with an amber edge and two trailing violet ribbons. Contact opens the heart into two arcs, then a small hovering heart-crown identifies the enthralled opponent.

This document and the construction SVG define the proposed technical blockout. The painted schematic defines the visual finish. It is not a frame-accurate animation or a ready-to-import effect.

## Existing character and rig

Start from a separate working copy of `projects/meridius/source/godot/art/succubus_3d/succubus_anim.blend`; preserve the existing actions. The reviewed build/rig scripts specify a 1.95 m character, Z up, front toward -Y, body bones named `mixamorig:*`, six `Tail_*` bones, wing chains and a whip parented to the left hand.

Use the **free right hand** for the blown-kiss gesture. Keep the left-hand whip lowered outside the silhouette. The generated board's two-handed gather pose is only illustrative: the production animation keeps the left hand on the whip throughout. Confirm bone names and dimensions in the actual working file before authoring; this pass inspected the scripts, not the live scene.

The current rig script has no finger skeleton and defines no facial shape keys. Add a non-destructive `Kiss_Pucker` shape key, a small `Exhale` mouth/jaw shape if topology allows, and optional right-finger controls for the close shot. The main battle pose must also read with the current fixed hand. Do not assume the existing head bone can pucker the lips.

Create a `KissSocket` empty or exportable socket bone attached to `mixamorig:Head`. Place it at the center of the lips, with its forward axis facing out of the mouth. Calibrate against the mesh instead of guessing a head-bone offset. Test head turns and the pucker shape. The projectile starts about 0.12 m ahead of the lips to prevent face intersections; a short breath strand visually bridges the gap.

## Cast action: `Succubus_SovereignKiss`

Frame 1 is time zero. Time in seconds is `(frame - 1) / 30`. All values below are proposed authoring markers; they are not verified gameplay clocks.

| Frames | Time | Pose and effect |
| --- | --- | --- |
| 01–12 | 0.00–0.37 s | Plant feet. Raise the right hand toward the mouth. Lift the chest subtly. Wings draw back to clear head and elbow; tail counterbalances. Left whip stays low. |
| 13–18 | 0.40–0.57 s | Right fingertips approach but do not intersect lips. Pucker builds. A tiny rose spark gathers at the mouth socket. No projectile yet. |
| 19–21 | 0.60–0.67 s | Hold the readable kiss silhouette for three frames. Pink eyes focus on target. Slight torso lean; heels stay planted. |
| **22** | **0.70 s** | **`kiss_release`**. Begin the exhale. Free hand opens away from the lips. Spawn one projectile at the socket's current world transform and release its parent. |
| 23–28 | 0.73–0.90 s | Heart grows from 0.08 m to 0.90 m wide during early travel, using ease-out. The socket breath strand fades within six frames. Hand and sternum follow the exhale. |
| 29–36 | 0.93–1.17 s | Hand reaches its outward open pose; wings give one restrained outward pulse. Small torso recoil, no forward foot slide. |
| 37–48 | 1.20–1.57 s | Hand lowers, wings and tail settle, character returns to the starting stance. Blend into idle on completion. |

Keep the action in place; turn the squad toward the target before the windup. Do not animate root translation toward the enemy. Use overlapping motion: wrist follows elbow by 1–2 frames, wing tips and tail settle 3–5 frames behind the torso. Preserve clear space between right hand, mouth, horns and wing edges.

## Heart construction

The schematic hero exaggerates scale for clarity. Start the actual blockout at **0.90 m width × 0.92 m height × 0.22 m depth** for the 1.95 m reference character (about 46% of full character height in width). These are visual scale suggestions, not collision dimensions. Put the origin at the heart's visual center.

Author the heart broad face in local XZ, with the point downward (-Z), top cleft upward and forward normal -Y. Its travel follows -Y in the neutral authoring setup. A heart can travel horizontally while its tip remains downward. Do not rotate it point-first like an arrow. At the game camera, a visual-only yaw bias may turn the heart's broad face toward the camera; never rotate the gameplay path or collider to achieve that.

| Layer / suggested object | Blender construction | Space and lifetime |
| --- | --- | --- |
| `SK_HeartCore` | Symmetric closed Bezier heart outline, filled and shallowly extruded, bevelled into a soft lens. Make a mesh copy for export. Deep rose center, brighter pink shoulders; preserve a dark middle so bloom does not erase the silhouette. | Child of projectile; lifetime ends at hit, miss expiry or projectile despawn. |
| `SK_HeartRim` | Duplicate the outline as a thin bevelled curve, amber-to-ivory emission. Two tiny backward curls can echo the horns; keep them secondary. Convert to mesh if needed. | Projectile-local; fades with core. |
| `SK_Breath` | Short tapered curve or two-sided ribbon from mouth to launch point. | Mouth-local during windup; stop and fade over six frames after release. |
| `SK_Trail_A/B` | Two tapered ribbon strips with violet-to-rose gradients. Slow opposing wave offsets, maximum trail length about 1.4 m. | Store world-space history; released ribbon sections do not follow the caster. Fade over 0.25 s. |
| `SK_Impact_Arc_L/R` | Two half-heart curves opening outward around upper torso. Animate scale and opacity. | Spawn at confirmed contact point; follow target anchor only while the impact envelope is active. |
| `SK_EnthrallCrown` | Small open heart with two detached arcs, about 0.28 m wide, above the target head with 0.18 m clearance. Restrained pulse, point downward. | Target-head anchor; one instance per affected target. Lives only while the gameplay status exists. |

Palette: deep rose `#BF165A`, rose light `#FF4FA4`, warm inner light `#FFF0D2`, amber edge `#FFB15C`, violet ribbon `#7835BC`, shadow plum `#24122F`. Keep pink on the active effect and avoid changing the entire target's team color.

Use emission and a controlled bright rim in the render. Do not rely on expensive transmission/refraction to make the effect readable. Blender procedural materials, curves, particles and compositing bloom are not automatically portable to Godot. Convert required geometry to meshes; bake textures where needed and rebuild trail/particle behavior in the engine. The reference PNG is presentation art, not a VFX atlas.

## Contact and enthrall

Contact has its own relative time **H**, independent of the cast frame. Longer travel must not delay the caster's recovery or fire a premature impact.

| Relative time | Event |
| --- | --- |
| H+0.00 | Confirmed hit: remove travelling core and stop new trail samples. Small warm flash at the upper torso. |
| H+0.00–0.10 s | Heart splits into two arcs; target reacts, opens guard and lowers its weapon. |
| H+0.10–0.30 s | Arcs spread and dissolve into a few petals. Heart-crown fades in above the head. |
| While status is active | Crown pulses subtly, e.g. a proposed 0.8 s visual loop. Target gaze and shoulders turn toward caster; optional restrained entranced locomotion is a separate clip. |
| Status ends | Crown contracts and fades over 0.20 s. Target transitions back according to authoritative state. |

The visual promise is **loss of hostile focus and attention drawn toward the squad**. Whether enthrallment disables attacks, forces approach, or affects a whole enemy squad must be decided with the game rules. The existing searched ability/rule files contain no implemented succubus/charm ability. Do not add damage, conversion, crowd-control duration or pathing as incidental VFX work.

## Squad choreography

Proposed presentation: every visible squad member performs the lip gesture, and short rose wisps converge at the leading caster's release point into **one large squad heart**. Synchronize the release marker; allow at most ±2 frames of shoulder/wing anticipation variation. A rear caster's wisp can be omitted when occluded. Keep one authoritative projectile and one contact resolution, unless a future gameplay design explicitly calls for a volley.

Do not show several independent hit crowns on an unaffected formation. Apply one crown to each target actually granted the status. The wide showcase depicts one representative caster and one recipient so the ability reads clearly.

## Ownership and cancellation contract

- Before release: the cast owns the mouth glow and breath. Interrupting or killing the caster cancels the pending release and fades local emission; no delayed projectile or hit.
- After release: the projectile owns travel and trail. Caster motion or death must not drag or teleport it. Its continued existence follows the gameplay rule. A miss or blocked hit dissolves quietly and creates no enthrall crown.
- On contact: consume the projectile once. Only a confirmed status application spawns the crown. A resisted hit may show the brief contact flash, never the sustained status indicator.
- On refresh: update the existing crown lifetime; do not stack a duplicate emitter. On dispel, status expiry, death or target despawn, clean it up.
- On hiding in fog, use the game's visibility rules for projectile and recipient. Clear world trail history on teleport or pooled reuse. Scene unload releases every owned instance.
- Restore only this effect's material contribution. Preserve selection outlines, damage flashes and team tint.

Initial visual complexity target: two ribbons, one core, one rim, at most 16 travel motes and 12 brief contact flecks per active heart. These are proposed limits, not measured performance results. Do not add dynamic lights per particle.

## Icon and delivery

Use `sovereign-kiss-icon.png` as the opaque square source master. It has no baked button frame or text. Its heart and amber edge carry the small-size identity; the lower-left lips add meaning at larger sizes. Preview it inside the actual iron/brass UI frame before shipping. The old ability prompt document mentions a 26 px slot, so the report explicitly includes 26, 32, 48, 64 and 128 px previews. At 26 px the lip detail is secondary; prefer 48–64 px for the full motif if the UI allows it. No UI sizing changes are included here.

Before implementation is accepted, review the caster at the game's real isometric angle, both directions of travel, dark forest and pale terrain, an enemy moving during flight, interrupted windup, resisted contact, status refresh/expiry, and a crowded squad. Disable bloom once to check that heart and crown silhouettes survive. Record native game captures separately from this generated concept.

Save future work to a new `succubus_sovereign_kiss.blend` and preserve the source actions. Suggested deliverables after implementation: cast action, separate target reaction/status/end clips, exported core/rim/arc meshes, textures, marker manifest and native captures. None of those animated or runtime assets are claimed as delivered by this schematic task.
