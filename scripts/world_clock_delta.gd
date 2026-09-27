class_name WorldClockDelta
extends RefCounted

## Detached journal patches. Dictionary order is retained; this module never
## touches SceneTree, wall clocks, PlayerState, GameData or a random generator.
const WorldState := preload("res://scripts/world_monster_respawn_state.gd")
const RespawnPolicy := preload("res://scripts/monster_respawn_policy.gd")


static func patch_from_changes(changes: Dictionary) -> Dictionary:
	var upserts := {}
	var removals: Array[String] = []
	for key: String in changes:
		if changes[key] == null:
			removals.append(key)
		else:
			upserts[key] = (changes[key] as Dictionary).duplicate(true)
	return {"upserts": upserts, "removals": removals}


static func valid_patch(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var patch: Dictionary = value
	if patch.size() != 2 or not patch.get("upserts", null) is Dictionary or not patch.get("removals", null) is Array:
		return false
	var upserts: Dictionary = patch.upserts
	for key: Variant in upserts:
		if not key is String or key.is_empty() or not upserts[key] is Dictionary:
			return false
	var removed := {}
	for key: Variant in patch.removals:
		if not key is String or key.is_empty() or removed.has(key) or upserts.has(key):
			return false
		removed[key] = true
	return true


static func valid_world_patch(value: Variant) -> bool:
	if not valid_patch(value):
		return false
	var patch: Dictionary = value
	for key: String in patch.upserts:
		if not valid_world_entry(key, patch.upserts[key]):
			return false
	for key: String in patch.removals:
		var delimiter := key.find("|")
		if delimiter <= 0:
			return false
		var map_text := key.substr(0, delimiter)
		if not map_text.is_valid_int() or str(int(map_text)) != map_text:
			return false
		if WorldState.slot_key(int(map_text), key.substr(delimiter + 1)) != key:
			return false
	return true


static func valid_world_entry(key: String, value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var entry: Dictionary = value
	var map_id: Variant = entry.get("runtime_map_id", null)
	var monster_id: Variant = entry.get("monster_id", null)
	var slot: Variant = entry.get("spawn_slot_id", null)
	var policy: Variant = entry.get("policy_id", null)
	var deadline: Variant = entry.get("respawn_at_unix", null)
	return (
		_nonnegative_integer(map_id)
		and _nonnegative_integer(monster_id) and int(monster_id) > 0
		and slot is String and WorldState.slot_key(int(map_id), slot) == key
		and policy is String and RespawnPolicy.is_known(policy)
		and (deadline is int or deadline is float)
		and is_finite(float(deadline)) and float(deadline) > 0.0
	)


static func apply_patch_owned(values: Dictionary, patch: Dictionary) -> void:
	## Caller owns the destination and has validated the patch. Replay applies
	## patches to its detached snapshot, never to a live character dictionary.
	for key: String in patch.removals:
		values.erase(key)
	for key: String in patch.upserts:
		values[key] = (patch.upserts[key] as Dictionary).duplicate(true)


static func _nonnegative_integer(value: Variant) -> bool:
	return (
		(value is int or (value is float and is_finite(value) and floorf(value) == value))
		and int(value) >= 0
	)
