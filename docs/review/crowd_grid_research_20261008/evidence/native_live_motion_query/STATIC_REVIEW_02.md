# Static review 02: live motion query candidate02

Review scope: research-tree `crowd_melee_kernel.cpp` current source, compared with the stock Enemy motion-candidate suffix and the Pro9 static contract. Read-only source review; no build or test run.

## Disposition

The earlier claims that the canonical path must call `can_receive_damage()` and that the C++ `double` radius arithmetic is independently a defect are withdrawn. Pro9 defines the known canonical Enemy predicate as the five-field native predicate, and the current source uses those fields. The repository's sealed numeric contract also permits the current Float64-radius/Float32-Vector2 arrangement for this candidate.

## Current source findings

The provider-zero mismatch is fixed in the current source. At `research/native/crowd_kernel/src/crowd_melee_kernel.cpp:394-409`, a non-null blocker is rejected when `_exact_world_background_script_id == 0` or its script ID differs, and the provider fallback is counted. The cache predicate preserves the short-circuit order: callable, current screen, map, generation, blocker/provider revision, cached revision, cached callable, and cached ground (`381-417`). Unknown provider misses then execute exactly one `spatial_index_position()` callback (`420-431`). A null blocker remains the stock-compatible `current_revision == -1` case rather than being blanket-rejected.

The target pre-projection and target-radius ordering is corrected. The current target is re-read after the projection callback (`252-261`), the owner radius is read before `_target_combat_radius_gu()` (`263-268`), and owner validity is rechecked after the radius callback (`269-277`). The post-miss script replacement boundary is also handled: after a spatial callback, the current script is rechecked and the legacy `can_receive/profile/core` suffix is run without a second body-counter increment (`445-476`). The legacy suffix now short-circuits `can_receive == false` before reading `behavior_profile` (`341-364`).

Canonical filtering and counter placement remain aligned with the stock loop: candidate-count instrumentation precedes the surround/target reads (`237-240`), owner/map/self/target filters precede the body counter (`293-317`), queued deletion is checked only in the exact predicate after HP/death fields (`477-496`), and the exact path retains the five-field predicate before world collision and `core_crossed` (`477-505`).

## Remaining bounded review scope

The native loop uses indexed iteration with a live `candidates.size()` (`293-300`). A miss callback can call back into GDScript (`420-431`); if that callback aliases and mutates the input Array, the native indexed iteration must be compared with the stock GDScript `for raw: Variant in candidates` mutation behavior. This remains a contract/coverage item, not a proven source defect from static inspection.

The unknown-subclass `get_base_script()` chain (`crowd_melee_kernel.cpp:83-110`) was reviewed but no file-backed use-after-free finding is retained: the chain traverses Godot Script resources through Variant/object references, and the current request provides no concrete callback that frees or invalidates the Resource during that built-in traversal. Do not promote the earlier hypothetical raw-reference concern without such evidence.

No other P1/P2 blocker was found in the current candidate02 source. Native integration and runtime performance remain outside this static approval; no tests or builds were run.
