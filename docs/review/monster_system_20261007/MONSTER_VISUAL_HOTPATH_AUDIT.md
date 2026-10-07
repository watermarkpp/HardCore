# Monster visual hot-path audit

Baseline: `codex/integration@aa75c5bc9845b49ee3ce67ce064442cc3fb3c43c`; read-only, no Godot and no production/test changes.

## Actual per-actor process path

`EnemyActor._ready` creates one `MonsterVisual` and one `Sprite2D` (`scripts/enemy.gd:2715-2721`; `scripts/monster_visual.gd:206-219`). The sprite uses one shared action atlas at a time with `region_enabled=true`; the frame is changed by `Sprite2D.region_rect`, not by creating an `AtlasTexture` per frame (`monster_visual.gd:206-212,550-552,1060-1083`).

Each visible actor whose `active_resources` is resident remains process-enabled: `_sync_process_tier()` tests only `not _has_authored_client_art or not active_resources.is_empty()` (`monster_visual.gd:596-607`). `_process()` advances action timers, exits for invalid/empty/invisible, then increments `visual_animation_updates` and calls `_update_animation_frame` (`monster_visual.gd:389-401`). This means an on-screen idle actor still performs the full animation selection path once per rendered process frame. It does not distinguish idle from moving for process scheduling.

`_update_animation_frame` does per-process state selection, facing/direction resolution, `refresh_selection_ring_direction`, frame-count lookup, elapsed/fps arithmetic, and `Rect2` construction (`monster_visual.gd:503-552`). `refresh_selection_ring_direction()` only queues a redraw when the directional offset actually changes (`monster_visual.gd:324-332`). Region assignment is guarded: `_apply_render_state` only writes texture/region when changed and increments `visual_render_state_changes` on actual change (`monster_visual.gd:1060-1076`). Therefore the repeat work is primarily CPU-side state calculation and per-actor process dispatch; ordinary idle frames do not recreate textures/materials.

The authored visual `_draw` is one contact-core polygon plus a 49-point selection ring when targeted (`monster_visual.gd:302-321,344-358`). A targeted actor with a changing facing can trigger `queue_redraw`; otherwise the CanvasItem draw list is retained. Enemy-owned dynamic redraws are separately requested from many combat/status transitions (`enemy.gd:2743-2774,7280-7282,7477-7496,7648-7693,8329-8330,8458-8459`), so engaged/damaged populations can add redraw pressure even when texture state is stable.

## Streaming/resource path

Cold activation calls `_activate_resources` and the central coordinator subscription (`monster_visual.gd:960-997`). The synchronous fallback calls `_load_client_profile_synchronously`, which loops all five action atlases and calls `_load_client_texture` (`monster_visual.gd:1033-1057`). `_load_client_texture` increments the load counter, uses `load(path)` when an imported resource exists, and only otherwise calls `Image.load_from_file` plus `ImageTexture.create_from_image` (`monster_visual.gd:1107-1123`). No `get_image`, `AtlasTexture.new`, or per-frame decode exists in this production MonsterVisual path. `AtlasTexture.new` is present in UI theme helpers, not this monster actor path.

The coordinator is a single GameRoot owner polled once per process frame (`game_root.gd:1890-1892`; `monster_visual_streaming_coordinator.gd:429-448`). It bounds profile loads to two concurrent jobs (`:28-29`), checks threaded status for each action (`:452-483`), gets each completed texture once (`:492-518`), validates and admits the profile (`:525-545`), then visits a bounded number of visual subscriptions for residency (`:1404-1429`). The cache has decoded-RGBA accounting and eviction/lease protection (`:750-764,1092-1105,1110-1136`). Repeated profile reloads are observable through `same_key_reload_count`, `sync_load_count`, `threaded_texture_request_count`, `threaded_texture_get_count`, and `resource_apply_count` (`:124,1450-1480,1606-1614`).

## Idle/paused/dormant versus moving

`MonsterVisual` has no explicit paused/dormant process-tier branch. Dormant/burrowed state affects drawing and actor logic, but a resident visible visual can still run `_process`; `_draw` returns for burrowed (`monster_visual.gd:302-306`). Invisible actors return after timer work (`:389-399`). When resources are released, processing is disabled and a wakeup timer advances timers/residency at a coarse interval (`:580-607`). Moving changes only facing/frame selection through `_hc_m30_is_walking()` and walk phase; it does not create a separate streaming or process schedule (`:511-514,545-549`).

## Evidence seam and likely bottleneck

The current seam is sufficient to separate causes without changing production: sample `visual_animation_updates`, `visual_render_state_changes`, `actor_redraw_requests`, `monster_streaming_poll_max_ms`, `resource_apply_count`, `same_key_reload_count`, sync/threaded load counts, active visual count, `Performance.TIME_PROCESS`, `TIME_PHYSICS_PROCESS`, render objects/primitives/draw calls, texture/video memory. DeviceLab already exports these engine monitors (`scripts/device_lab_runtime.gd:846-864,940-957`) and combines `total_monster_count`, `moving_count`, `engaged_count`, and `visual_resources_active` (`:877-918`).

A useful observer split is four equal-load windows: all idle, all moving, all engaged/damaged, and mixed dormant/burrowed. Record per-frame deltas:

```text
visual_animation_updates / active_visual_count
visual_render_state_changes / active_visual_count
actor_redraw_requests / total_monster_count
monster_streaming_poll_max_ms and visual_residency_visit_count
render_draw_calls / visible_actor_count
```

This can prove CPU repeated work or resource reloads. Headless physics timing cannot prove Android/GPU render cost; the draw-call, primitive, texture-memory and process-window fields need a rendered/device run.

## Minimal optimization candidates (evidence-first)

1. Add an observer counter for `_process` state (`idle`, `walk`, `attack`, `hit`, `death`) and for actual region writes, without changing scheduling. This identifies whether idle actors dominate the reported engaged-count drop.
2. If evidence shows idle CPU-only churn, cache the last state/facing/frame-count inputs and skip unchanged frame arithmetic while retaining timer advancement and logical attack deadlines. Do not disable visual processing for attack/hit/death or alter frame timing.
3. If reload counters rise during stable residency, inspect lease/world-generation transitions before touching decode/cache behavior. A reload fix must preserve the per-visual lease and world-generation gates.
4. If render counters scale with targeted/engaged actors, separate ring/dynamic redraw invalidation from body region updates; do not reduce actor content or AOE to make the metric green.

Current evidence does not show per-frame `get_image`, `AtlasTexture.new`, texture decode, material rebuild, or unconditional `queue_redraw` in MonsterVisual. The strongest confirmed hot path is per-resident-actor `_process` plus state/frame calculation, with additional redraw work from Enemy status/combat transitions. Android/GPU confirmation remains `NOT_RUN`.
