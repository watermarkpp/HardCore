# Half Moon Generator V1 · parameter reference

This page is for Sol/Codex. The user-facing page keeps these controls hidden by default.

## Candidate identity

`candidate_id`, `parent_id`, `preset`, `seed`, `parameter_delta`, `direction_overrides`, `favorite` and `revisions` are persisted in the project JSON. Seeds are unsigned stable 32-bit hashes. `revisions` records old parameter and direction-override values before every edit. A repeated candidate definition produces byte-identical RGBA pixels on the same Pillow/NumPy versions.

## Shape and projection

| Parameter | Effect |
| --- | --- |
| `arc_radius`, `arc_span_degrees`, `arc_thickness` | Reach, angular length and width of the blade body. |
| `inner_radius`, `outer_radius` | Derived from radius and thickness; renderer consumes these boundaries. |
| `head_taper`, `tail_taper` | Different end falloffs. |
| `edge_sharpness`, `edge_noise` | Hardness and irregularity of the body edge. |
| `ellipse_ratio`, `perspective_compression` | Isometric compression of the shared arc. |
| `rotation` | Candidate-wide artistic angle. |
| `direction_overrides.<direction>` | Auto defaults can be overridden with `rotation`, `scale_x`, `scale_y`, `offset_x`, `offset_y`, `skew`, `ellipse_ratio`. |

## Material and movement

| Parameter | Effect |
| --- | --- |
| `core_width`, `core_intensity`, `core_position`, `core_sharpness` | Bright metal edge. |
| `inner_glow_size`, `inner_glow_strength`, `outer_glow_size`, `outer_glow_strength` | Two restrained glow layers. |
| `trail_length`, `trail_width`, `trail_opacity`, `trail_falloff`, `trail_breakup` | Swept afterimage. |
| `breakup_amount`, `breakup_scale`, `breakup_seed` | Fragmented tail and deterministic edge variation. |
| `spark_count`, `spark_size`, `spark_spread`, `spark_lifetime`, `spark_velocity`, `spark_seed` | Deterministic flying highlights. |
| `gradient.core`, `.body`, `.outer`, `.trail` | Four distinct `#RRGGBB` colors. |
| `frame_envelope[0..5]` | Per-frame opacity curve. Version-2 candidates peak at F4; their angular reveal and radius schedule are separately fixed by `TEMPORAL_SWEEP`. |
| `reference_scale`, `reference_offset_x/y` | Version-3 SW source artwork size and shared placement, before direction projection. |
| `reference_fade` | Version-3 final frame opacity multiplier; the source PNG itself remains unchanged. |
| `direction_overrides.<direction>.offset_x/y` | Version-3 per-direction six-frame position adjustment, editable with arrow keys and undo. |

The default presets are `classic_heavy`, `sharp_gold`, `dark_gold`, `brutal_slash`, `minimal_classic`. New batches use a base preset plus controlled variation. Mutations use a smaller amplitude than an initial batch. Fusion copies shape from A and color/glow, trail and particles from chosen sources.

## Natural-language adjustment guide

- “太亮／像手游” → reduce core intensity, outer glow, saturation of the four gradient colors and spark count; strengthen opaque body as needed.
- “更厚／更实体” → increase arc thickness, reduce outer glow, keep a narrow core.
- “刀锋更明显” → increase core intensity and edge sharpness; adjust core width carefully.
- “尾巴短一点” → reduce trail length and trail opacity.
- “更破碎” → raise breakup amount and trail breakup while checking F4/F5 continuity.
- “东北方向太高” → change only `direction_overrides.NE.offset_y`, then inspect all eight rows before baking.

After every edit, check the animated composite over map ground as well as black and gray. Do not infer final visual quality from one isolated effect frame.
