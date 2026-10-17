extends RefCounted
## Narrow first-Root representation adapter. Only the two original infinity
## cache sentinels and empty former actor scratch arrays are encoded.
## It does not relax Native transport, JSON, content, gameplay or save schemas.
const Working := preload("res://scripts/gameplay/world/world_runtime_working_graph.gd")
const CONTRACT := "world.source.constructor_values.v1"
const ROOT_SHA := "e148e75952a3dfae5b2256075ccdd00253e5f8eecc575d6823c83084edd06121"
const INF_PATHS := [["_world_camera_presented_center"],["_player_safe_zone_cache","ground_position_gu"]]
const ACTOR_ARRAYS := ["_safe_zone_candidate_scratch","_safe_zone_query_scratch","_passive_wake_candidates","_target_spatial_query_scratch","_aoe_candidate_scratch","_aoe_target_scratch","_pending_main_pet_arrivals"]
static func encode(fields: Dictionary, actual_source_sha: String) -> Dictionary:
	if actual_source_sha != ROOT_SHA: return _fail("original_constructor_source_changed")
	var cloned: Dictionary = Working.restore_runtime_roots(fields)
	if cloned.get("ok") != true: return cloned
	var values: Dictionary = cloned.value
	var sentinels: Array = []
	for path: Array in INF_PATHS:
		var parent: Dictionary = values
		if path.size() == 2:
			if not values.get(path[0]) is Dictionary: return _fail("original_constructor_cache_missing")
			parent = values[path[0]]
		var key: String = path[-1]
		if not parent.has(key): return _fail("original_constructor_cache_key_missing")
		if parent[key] is Vector2 and parent[key] == Vector2.INF:
			parent[key] = null
			sentinels.append(path.duplicate())
	var arrays: Array[String] = []
	var originals: Array = []
	var replacements: Array = []
	for name: String in ACTOR_ARRAYS:
		if not values.has(name): continue
		var value: Variant = values[name]
		if not value is Array: return _fail("original_constructor_actor_array_type")
		if value.get_typed_builtin() != TYPE_OBJECT: continue
		if not value.is_empty(): return _fail("original_constructor_has_live_actor_values")
		var replacement: Array = []
		for index: int in range(originals.size()):
			if is_same(value,originals[index]): replacement = replacements[index]; break
		originals.append(value); replacements.append(replacement)
		values[name] = replacement
		arrays.append(name)
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var checked: Dictionary = graph.capture({"fields":values,"constructor_values":{"contract_id":CONTRACT,"source_sha256":ROOT_SHA,"vector2_inf_paths":sentinels,"empty_actor_arrays":arrays}},true,false)
	if checked.get("success") != true: return {"ok":false,"errors":["unsupported_original_constructor_value"],"details":checked}
	return {"ok":true,"value":checked.value}
static func decode(publication: Dictionary) -> Dictionary:
	if not publication.get("fields") is Dictionary: return _fail("constructor_fields_required")
	if not publication.has("constructor_values"): return Working.restore_runtime_roots(publication.fields)
	var metadata: Variant = publication.constructor_values
	if not metadata is Dictionary or metadata.size() != 4 or metadata.get("contract_id") != CONTRACT or metadata.get("source_sha256") != ROOT_SHA or not metadata.get("vector2_inf_paths") is Array or not metadata.get("empty_actor_arrays") is Array: return _fail("constructor_value_metadata_invalid")
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	if graph.validate(publication,false).get("success") != true: return _fail("constructor_transport_not_plain")
	var restored: Dictionary = Working.restore_runtime_roots(publication.fields)
	if restored.get("ok") != true: return restored
	var values: Dictionary = restored.value
	var seen: Array = []
	for raw: Variant in metadata.vector2_inf_paths:
		if not raw is Array or raw not in INF_PATHS or raw in seen: return _fail("constructor_sentinel_path_invalid")
		seen.append(raw)
		var parent: Dictionary = values
		if raw.size() == 2:
			if not values.get(raw[0]) is Dictionary: return _fail("constructor_sentinel_parent_missing")
			parent = values[raw[0]]
		if not parent.has(raw[-1]) or parent[raw[-1]] != null: return _fail("constructor_sentinel_slot_changed")
		parent[raw[-1]] = Vector2.INF
	seen.clear()
	var originals: Array = []
	var replacements: Array = []
	for raw: Variant in metadata.empty_actor_arrays:
		if not raw is String or raw not in ACTOR_ARRAYS or raw in seen: return _fail("constructor_actor_array_name_invalid")
		seen.append(raw)
		var value: Variant = values.get(raw)
		if not value is Array or not value.is_empty() or value.is_typed(): return _fail("constructor_actor_array_not_empty_wire")
		var replacement: Array[Object] = []
		for index: int in range(originals.size()):
			if is_same(value,originals[index]): replacement = replacements[index]; break
		originals.append(value); replacements.append(replacement)
		values[raw] = replacement
	return {"ok":true,"value":values}
static func _fail(reason: String) -> Dictionary: return {"ok":false,"errors":[reason]}
