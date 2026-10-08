# NATIVE_LIVE_MOTION_QUERY API feasibility design

Status: **NOT_RUN**. This is a read-only feasibility note for one bounded experiment. No native source, Enemy source, runner, DLL, build, or test was changed.

## Pinned API evidence

The research candidate is fixed107 HEAD `edae6fdef6a6551a951fab1ea8c6ade43359d603`. The pinned build profile is Godot-cpp commit `272e7f4a5fde342ea20983371fffafdccea07f20`, Godot API `4.7`, `template_debug`, with enabled generated classes `RefCounted`, `Geometry2D`, and `OS`.

The generated Godot-cpp headers provide the following usable public APIs:

| Need | Pinned API | Consequence |
|---|---|---|
| Generic live owner/candidate object | `godot::Object::get`, `set`, `call`, `has_method`, `get_script`, `get_instance_id`, `is_class`, `is_queued_for_deletion` | A finite query can accept generic `Object *`; ordinary fields can be read as `Variant`; method calls remain reentrant GDScript calls. |
| Object revalidation | `godot::ObjectDB::get_instance(uint64_t)` and `Object::get_instance_id()` | After any fallback call, reacquire by ID and compare the returned pointer; also check `is_queued_for_deletion()`. Never retain a raw pointer across a callback without this check. |
| Callable identity/validity | `Callable::is_valid()`, `get_object_id()`, `get_method()`, equality operators, `get_object()` | Cache-hit checks can compare validity, object identity, and method identity. A callable miss must remain on the original owner path. |
| Live `global_position` | `Object::get(StringName("global_position"))` | `Node2D` is not present in the pinned generated class set, so the native side must use generic `Object` and validate the returned `Variant` as `Vector2`. |
| Geometry | `Geometry2D::get_closest_point_to_segment` | Existing `HCPolicy.core_crossed` can be reproduced with the already enabled geometry API once the same values are admitted. |

`Object::is_class("EnemyActor")` is insufficient for the script identity gate: the project’s `EnemyActor` is a GDScript `class_name`, while `is_class` follows the engine class chain. The exact gate must compare `Object::get_script()` against a host supplied, prevalidated canonical Enemy script identity. A practical finite ABI passes the canonical script resource `ObjectID` once; native obtains each candidate’s script resource through `get_script()`, compares its `get_instance_id()`, and falls back before any diagnostic effect when the identity is unavailable or differs.

The pinned SDK has no generated `Node2D` header in this profile. That rules out a typed `Node2D *` ABI for this experiment and rules out private GDScript member offsets. The supported route is `Object *` plus public `Object::get`/`call` and strict `Variant` type checks.

## Actual consumer and execution boundary

The real entry is `scripts/enemy.gd:10301` `_hc_motion_candidates(a, b, candidates)`. It is reached from the existing movement path at lines 8888, 10241, and 10384. The query begins with the raw candidate count at line 10303, performs the optional surround-target crossing check, computes the `low`/`high` envelope, then iterates the already supplied `Array` in order:

1. Reject invalid/non-Enemy values.
2. Skip `self` and `target`.
3. Reject a different `runtime_map_id`.
4. Record `enemy_motion_body_checks`.
5. Obtain the candidate’s current formal position.
6. Apply the conservative envelope.
7. Apply damage eligibility and `behavior_profile.worldCollision`.
8. Apply `HCPolicy.core_crossed`; return `false` on the first blocking candidate, otherwise `true`.

The native seam must receive the real `owner`, the original `a`, `b`, and the existing candidate `Array`. It must not create a second candidate pool, packed context, retained frame cache, or private field-offset reader. The host remains responsible for the original candidate query and for invoking the existing diagnostic counter at the same logical points. A native return may be the original boolean plus bounded diagnostic counts only if the host calls the diagnostic recorder at the original points; a final bulk counter write would change event timing and is not acceptable.

A proposed finite binding is conceptually:

```text
motion_candidates_live(owner: Object,
                      a: Vector2,
                      b: Vector2,
                      candidates: Array,
                      expected_enemy_script_id: int) -> Dictionary
```

The dictionary should be a bounded result containing only the original boolean and explicit fallback/entry counters needed to prove coverage. It must not contain a copied actor snapshot or become a second state authority. The actual registered method name and return shape require a separate contract review before implementation.

## What can be native and what must fall back

### Native-safe only after exact script identity

For a candidate whose script resource matches the canonical Enemy script, these ordinary reads are feasible through `Object::get` and have no known callback by themselves:

- `runtime_map_id`
- `current_hp`
- `combat_radius_gu`
- `_body_admission_rejected`
- `_death_pending`
- `_dying`
- `behavior_profile` followed by the `worldCollision` dictionary value
- `global_position` when the returned value is a finite `Vector2`
- the cached spatial fields `_last_spatial_index_screen_position_px`, `_last_spatial_index_ground_position_gu`, `_last_spatial_index_runtime_map_id`, `_last_spatial_index_zone_generation`, `_last_spatial_index_environment_revision`, and `_last_spatial_index_projection`, subject to the exact cache predicate below

The complete `can_receive_damage` predicate at `scripts/enemy.gd:7327` is therefore reproducible for the canonical script from those values: reject `_body_admission_rejected`, require `current_hp > 0`, reject `_death_pending`, `_dying`, and `is_queued_for_deletion()`. `is_queued_for_deletion()` is a public engine call and must be checked directly.

The native side may reproduce `spatial_index_position` only when all existing cache conditions are established from current live fields: valid projection Callable, cached screen position equals current `global_position`, same map, same `zone_generation`, same environment revision, and equal cached projection Callable. The Callable check must use public identity/validity APIs. A cache miss must invoke the original `spatial_index_position()` callee at the original loop point, or the whole owner must fall back before counters/effects if the callback path cannot be safely resumed.

### Mandatory fallback or callback boundary

These paths are not pure direct reads and must remain legacy calls or cause whole-query fallback:

- `_screen_position_px_to_ground_position_gu` for the surround-target special check: it can call `runtime_screen_to_ground_position_px`, update the target projection cache, and record projection timing.
- `_target_combat_radius_gu`: it performs script type dispatch and may call the original fallback radius authority.
- `spatial_index_position()` on a cache miss: it can call the projection Callable and write cache state.
- `can_receive_damage()` for any script identity other than the exact canonical Enemy script, including a subclass/override.
- `behavior_profile` if it is absent, not a `Dictionary`, or its `worldCollision` value is not a usable boolean under the original default rule.
- `environment_blocker.environment_collision_revision` through `_hc_environment_revision()`; this is an Object method call and is reentrant. The native cache predicate may only use a directly supplied/current revision if the host contract proves it is the same value; otherwise the original cache helper is the fallback.
- Any invalid, freed, queued-for-deletion, or type-mismatched candidate.

The owner itself must be revalidated after every legacy callback before continuing. If the callback changes the candidate Array, owner state, map, target, or runtime identity, discard native locals and return the original owner path rather than resuming with stale raw pointers. A candidate that becomes invalid after a callback must be treated exactly as the original loop would treat it on the next read; it must not be dereferenced from a stale pointer.

## Script identity and provider route

`get_script()` returns a `Variant` object resource through the public Object API. Native can accept a host-supplied canonical script `ObjectID`, obtain the live script object from the Variant, and compare IDs. It cannot derive the project’s GDScript `class_name` identity from `is_class`, and the pinned SDK has no typed `Script` requirement for this comparison. Missing script, invalid script object, or mismatched script ID is an immediate unsupported-owner/candidate result.

Callable providers are similarly finite: `Callable::is_valid`, `get_object_id`, `get_method`, and equality are available. A provider whose object or method identity differs from the current owner’s cached Callable is a miss. Calling the provider from native remains a GDScript callback; it is permitted only at the same legacy miss point and requires ObjectID revalidation afterward. The native path must not turn provider results into a retained cache or call a provider twice.

## Closure and safety decision

The entry is feasible as one bounded live query only under this closure:

- exact canonical Enemy script identity is available;
- owner and every native candidate use the public Object API;
- known direct fields and the complete pure damage predicate are read in native;
- spatial cache hits are checked from current fields and Callable identity;
- projection/provider/cache misses call the original callee once at the original point;
- unknown script, override, invalid object, callback mutation, map change, or failed type conversion aborts native continuation and uses the original owner path before diagnostic side effects;
- all original counter calls remain at their original logical points and are not bulk-replayed later.

This API is **feasible for a narrow experiment**, but coverage is not guaranteed and the likely dominant costs are per-candidate `Object::get` Variant work, script-resource identity checks, and legacy diagnostic callbacks. No performance result follows from API feasibility. The experiment must report native-entry count, whole-query fallback count, per-candidate legacy fallback count, projection-miss callback count, callback revalidation failures, and the unchanged formal trajectory/queue metrics. It cannot claim a 50% reduction or extrapolate to retarget, frontline, or other query families.
