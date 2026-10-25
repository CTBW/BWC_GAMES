# Sovereign Kiss — Pink fog Blender handoff

**Succubus–German squad · Visual direction approved · 30 fps · 24 October 2026**

The squad blows a large **heart made of pink fog** from their lips. It passes through eligible opponents, enthralling them, then becomes progressively more translucent and evaporates beyond the target formation. Contact does not break or consume the travelling heart. The user approved the revised painted schematic; technical values below remain proposed.

This replaces the earlier solid core, amber rim and split-on-impact treatment. The painted sheet defines the look; this document and the editable SVG define the blockout. No animated Blender asset or runtime implementation is included.

## Character and cast

Work in a separate copy of `projects/meridius/source/godot/art/succubus_3d/succubus_anim.blend`, preserving existing actions. Reviewed rig scripts specify a 1.95 m character, Z up, front toward -Y, `mixamorig:*` body bones, six `Tail_*` bones, wing chains and a left-hand whip. Confirm names and scale in the actual scene before authoring; this pass inspected scripts, not the live file.

The **free right hand** makes the kiss gesture. The left hand keeps the whip low. The generated gather panel is expressive reference only: do not copy its two-handed pose. Preserve blonde hair, shepherd ears and tail, horns, costume and wings.

The rig script contains no finger skeleton or facial shape keys. Add a non-destructive `Kiss_Pucker` and optional `Exhale` shape. The pose must read with the current hand silhouette; optional finger controls improve a close view. Parent a `KissSocket` to `mixamorig:Head`, calibrated to the lips with its forward axis out of the mouth. Check head turns and puckering.

Frame 1 is time zero; seconds = `(frame - 1) / 30`.

| Frames | Time | Pose and effect |
| --- | --- | --- |
| 01–12 | 0.00–0.37 s | Plant feet; raise right hand. Wings pull back to clear face and elbow. Small pink wisp at lips. |
| 13–18 | 0.40–0.57 s | Pucker builds; fingertips approach without intersection. Mist stays mouth-local. |
| 19–21 | 0.60–0.67 s | Hold readable kiss silhouette for three frames. Focus on target. |
| **22** | **0.70 s** | **`kiss_release`**: spawn one fog-heart at the socket's world transform and detach. Begin exhale; right hand opens. |
| 23–28 | 0.73–0.90 s | Heart grows while moving. Short pink breath bridge fades behind it. |
| 29–36 | 0.93–1.17 s | Open-palm follow-through, restrained wing pulse and torso recoil. Fog motion independent of caster. |
| 37–48 | 1.20–1.57 s | Lower hand and settle into idle. Fog may still be travelling. |

Keep feet planted, turn toward the target before windup and avoid root slide. Wrist follows elbow by 1–2 frames; wing tips and tail settle 3–5 frames behind torso. A release point about 0.12 m ahead of the lips prevents face intersections; the breath strand bridges the gap.

## Fog-heart construction

Start with a **0.90 m wide × 0.92 m high × 0.35 m deep** soft envelope. These are visual proposals, not collider values. Broad face in XZ, cleft up, point -Z, neutral travel -Y. Keep the heart upright during travel. A visual-only camera bias may improve readability without changing its path.

Use a hidden heart mesh as a density mask or distribution guide. The visible result is billowing vapor with feathered edges, holes and overlapping curls. There is **no visible solid shell or gold outline**. Preserve twin lobes and cleft at release, then erode the contour gradually.

| Layer | Blender construction | Ownership |
| --- | --- | --- |
| `SK_FogEnvelope` | Hidden heart-shaped proxy for distribution and masking. | Projectile-local. |
| `SK_FogBody` | Overlapping smoke lobes inside heart mask; animated noise drives density and erosion. True volume for a close preview, or alpha cards for a game-oriented study. | Projectile owns travel, density and normalized age. |
| `SK_FogEdge` | Sparse low-density wisps on lobes and point. Drift outward; avoid continuous bright border. | Release peeling wisps into world space. |
| `SK_Breath` | Short tapered pink mist connection from mouth to launch point. | Caster-owned; stop emission on release, fade within six frames. |
| `SK_Wake` | Two broad pink smoke streams with soft ragged ends. | World-space history; old sections fade independently. |
| `SK_ContactVeil` | Brief transparent pink wash across torso. No explosion, fracture or stopping motion. | Per-target contact instance. |
| `SK_EnthrallMark` | Small open pink fog heart above head; restrained pulse. | Target-head anchor, status-owned. |

Palette: raspberry `#C82777`, rose `#F44C9D`, main pink `#FF82C2`, blush `#FFC0DF`, pale highlight `#FFE3F1`, shadow plum `#2B1738`. Fog is overwhelmingly pink; plum shades it. Avoid amber, fire and a white-hot continuous rim.

Expand eddies while reducing density so the effect evaporates rather than merely dims. Fade emission with opacity. Armor and terrain must remain visible through the fog. Check without bloom: additive glow alone will not convey translucency.

## Passage and evaporation

Drive the lifecycle by **travel progress and target-zone exit**, not the first collision. Determine the formation's far edge at release and place the fade endpoint beyond it. A moving or destroyed target must not extend the effect forever; include a bounded maximum lifetime. Exact range, speed, target eligibility and status duration remain gameplay decisions.

| Stage | Appearance | Proposed controls |
| --- | --- | --- |
| Formation | Dense pink heart gathers into a clear silhouette. | Grow through F22–28; density rises from zero. |
| Approach | Billowing heart travels with small transparent gaps. | Density scalar 1.0 → 0.75; scale 1.0 → 1.05. |
| Through targets | Armor shows through pink mist; heart keeps moving. | Density 0.75 → 0.45; wider holes and detached edges. |
| Beyond formation | Heart opens into separate curls. | Suggested dissolve span 1.5–2.0 m or 0.6–0.9 s, chosen after speed is set. Density 0.45 → 0; scale 1.05 → 1.25. |
| End | Final wisps drift and vanish without a flash or cutoff. | Stop emission early, finish existing wisps, then despawn owner. |

Values are **normalized density multipliers**, not literal composited pixel opacity and not labels for an icon. Layer count, noise and lighting determine transparency. Tune at the actual game camera and reach zero before cleanup.

For wisp age `u`, begin with `density = baseDensity × (1 - smoothstep(fadeStart, 1, u))`. Increase noise erosion during this falloff, fading both opacity and emission. No lingering bright outline after the smoke vanishes.

## Enthrall on overlap

Use a piercing travelling volume. Each eligible target receives at most one application per cast: maintain an affected-target ID set. Do not reapply on every overlapping frame, destroy the projectile at first hit, reset travel age, or restore density at each target.

Contact has its own clock **H**:

| Relative time | Event |
| --- | --- |
| H+0.00 | Confirm eligible overlap; apply enthrall once. Fog continues along the path. |
| H+0.00–0.15 s | Pink veil crosses torso. On success, target lowers guard and turns attention toward casters. |
| H+0.10–0.30 s | Small pale-pink fog heart fades in above head. |
| While status exists | Mark pulses subtly; target motion follows authoritative game state. |
| Status ends | Mark fades over a proposed 0.20 s, independently of the travelling cloud. |

Resisted targets may show the transient veil but no sustained mark. Refresh an existing mark instead of stacking emitters; clear on dispel, death, status expiry or despawn. Exact crowd control, target count and eligibility during the final cosmetic fade need gameplay decisions. Visual density must never silently decide hit eligibility.

## Squad and cleanup

Squad members perform the lip gesture together. Small pink wisps converge into **one shared fog heart** at the leader's release point. Use one projectile owner and independent per-target overlap events. The representative caster and opponent in the sheet do not define a final target-count rule.

- Interrupted before release: cancel pending projectile and fade mouth-local fog.
- After release: caster motion or death cannot drag cloud or trail. Continued travel follows game rules.
- Miss: bounded travel and evaporation, no enthrall marks.
- Walls: apply the game's collision rule; passing through opponents does not imply passing through walls.
- Teleport or pooled reuse: clear trail history and affected-target set.
- Fog-of-war and scene unload: respect visibility rules and release owned instances.
- Preserve selection outlines, team colors and unrelated effects.

## Preview and game handoff

Use a separate effect collection. Animate custom controls for density, scale, noise offset, edge erosion and emission. Compare stages with a fixed camera/background, including the real isometric view. Pass the fog through an armored stand-in to check transparency and continued motion.

For runtime, bake smoke into flipbooks or prepare a small set of alpha cards plus a Godot shader. Blender volumes, procedural noise and particles do not transfer automatically through glTF. Match straight/premultiplied alpha to the material; inspect dark fringes, transparency sorting and overdraw. Share smoke textures between instances. The concept PNG is not a usable VFX atlas.

Review dark forest and pale terrain, bloom on/off, several opponents, overlapping squads, resistance, interrupted windup, refresh/expiry and targets moving out of the route. Confirm the fog crosses the final target, visibly thins and disappears without popping. Record native game captures after implementation.

The revised icons show pink vapor, lips and a heart without text or button borders. Small-size previews belong in the report. The icon represents a dense readable moment with evaporating wisps, not an opacity chart.

Save future work as `succubus_sovereign_kiss_fog.blend`. Future implementation outputs include cast and reaction clips, smoke flipbooks/cards, shader parameters, event markers and native captures. None are claimed as delivered by this concept task.
