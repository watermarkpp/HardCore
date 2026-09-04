class_name MonsterVisualLegacyStreamingReference
extends RefCounted

## Q2-D: test-only reference for the pre-coordinator MonsterVisual streaming
## semantics (per-instance poll + static request table + cache). Production
## code must never call this helper.


static func old_request_plan(
	visual_resource_keys: Array,
	completion_order: Array
) -> Dictionary:
	## Old behavior: same-key requests dedup into one table entry; requests are
	## enqueued in first-request order; prefetch commits in caller order and
	## proximity commits on completion in request order.
	var request_order: Array[String] = []
	var unique: Dictionary = {}
	var duplicate := 0
	for raw_key: Variant in visual_resource_keys:
		var key := str(raw_key)
		if unique.has(key):
			duplicate += 1
			continue
		unique[key] = true
		request_order.append(key)
	var apply_order: Array[String] = []
	for raw_key: Variant in completion_order:
		var key := str(raw_key)
		if unique.has(key) and not apply_order.has(key):
			apply_order.append(key)
	return {
		"request_order": request_order,
		"unique_request_count": unique.size(),
		"duplicate_request_count": duplicate,
		"apply_order": apply_order,
	}


static func expected_animation_after_apply(
	action: String,
	direction: int,
	playing: bool,
	death_remaining: float
) -> Dictionary:
	## Frozen contract: applying a resource through _activate_resources resets
	## _last_state and applies the idle frame; the very next _process frame
	## recomputes action/direction/frame from the actor state and preserved
	## action timers (attack/hit/death progress never restarts).
	return {
		"action": action,
		"direction": direction,
		"playing": playing,
		"death_remaining": death_remaining,
	}
