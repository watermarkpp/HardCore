class_name MapEditorConnectionPolicyService
extends RefCounted

const POLICY_PATH := "res://assets/data/map_design/map_connection_policy.json"
const POLICY_ID := "map_connection_unified_bidirectional_v2"
const LEGACY_POLICY_ID := "map_connection_bidirectional_default_v1"
const DEFAULT_CONNECTION_MODE := "bidirectional"
const PORTAL_CONTRACT_ID := "unified_map_portal_endpoint_v1"
const ARRIVAL_REENTRY_POLICY_ID := "portal_arrival_guard_v2"
const RETURN_MINIMUM_SECONDS := 3.0
const RETURN_UNLOCK_DISTANCE_GU := 1.5


static func new_exit_defaults() -> Dictionary:
	return {
		"connection_policy_id": POLICY_ID,
		"portal_contract_id": PORTAL_CONTRACT_ID,
		"portal_role": "bidirectional_endpoint",
		"semantic_role": "map_portal_endpoint",
		"connection_mode": DEFAULT_CONNECTION_MODE,
		"one_way": false,
		"connection_pair_id": "",
		"target_portal_id": "",
		"reciprocal_exit_id": "",
		"reciprocal_map_key": "",
		"arrival_reentry_policy_id": ARRIVAL_REENTRY_POLICY_ID,
		"arrival_locks_current_portal": true,
		"requires_leave_before_retrigger": true,
		"return_minimum_seconds": RETURN_MINIMUM_SECONDS,
		"return_unlock_distance_gu": RETURN_UNLOCK_DISTANCE_GU,
		"return_requires_fresh_activation": true,
		"travel_request_single_flight": true,
	}


static func configure_bidirectional(
	source: Dictionary,
	source_exit_id: String,
	_source_entrance_id: String,
	target: Dictionary,
	target_entrance_id: String,
	pair_id: String,
	forward_display_name: String,
	reverse_display_name: String,
	forward_connection_id: String,
	reverse_connection_id: String
) -> Dictionary:
	if pair_id.strip_edges().is_empty():
		return {"ok": false, "errors": ["connection_pair_id_required"]}
	var source_endpoint := _entry(
		source.layers.get("map_exit_points", []), source_exit_id
	)
	if source_endpoint.is_empty():
		return {"ok": false, "errors": ["source_portal_missing"]}
	var target_endpoint := _exit_by_pair(
		target.layers.get("map_exit_points", []), pair_id, "reverse"
	)
	var consumed_entrance := _entry(
		target.layers.get("map_entrance_points", []), target_entrance_id
	)
	if target_endpoint.is_empty():
		if consumed_entrance.is_empty():
			return {"ok": false, "errors": ["target_portal_seed_missing"]}
		target_endpoint = _new_endpoint(
			target,
			_tile(consumed_entrance),
			reverse_display_name,
			pair_id,
			"reverse"
		)
	elif not consumed_entrance.is_empty():
		target_endpoint["tile"] = consumed_entrance.tile.duplicate()

	_configure_endpoint(
		source_endpoint,
		source,
		target,
		target_endpoint,
		pair_id,
		"forward",
		forward_display_name,
		forward_connection_id
	)
	_configure_endpoint(
		target_endpoint,
		target,
		source,
		source_endpoint,
		pair_id,
		"reverse",
		reverse_display_name,
		reverse_connection_id
	)
	_link_reciprocals(source, source_endpoint, target, target_endpoint)
	if not consumed_entrance.is_empty():
		_remove_entry(
			target,
			"map_entrance_points",
			str(consumed_entrance.semantic_id)
		)
	_mark_document(source)
	_mark_document(target)
	return {
		"ok": true,
		"pair_id": pair_id,
		"forward_endpoint": source_endpoint,
		"reverse_endpoint": target_endpoint,
		"consumed_entrance_id": (
			str(consumed_entrance.get("semantic_id", ""))
		),
	}


static func configure_bidirectional_endpoints(
	source: Dictionary,
	source_exit_id: String,
	target: Dictionary,
	target_exit_id: String,
	pair_id: String,
	forward_display_name: String,
	reverse_display_name: String,
	forward_connection_id: String,
	reverse_connection_id: String
) -> Dictionary:
	if pair_id.strip_edges().is_empty():
		return {"ok": false, "errors": ["connection_pair_id_required"]}
	var source_endpoint := _entry(
		source.layers.get("map_exit_points", []), source_exit_id
	)
	var target_endpoint := _entry(
		target.layers.get("map_exit_points", []), target_exit_id
	)
	if source_endpoint.is_empty():
		return {"ok": false, "errors": ["source_portal_missing"]}
	if target_endpoint.is_empty():
		return {"ok": false, "errors": ["target_portal_missing"]}
	_configure_endpoint(
		source_endpoint,
		source,
		target,
		target_endpoint,
		pair_id,
		"forward",
		forward_display_name,
		forward_connection_id
	)
	_configure_endpoint(
		target_endpoint,
		target,
		source,
		source_endpoint,
		pair_id,
		"reverse",
		reverse_display_name,
		reverse_connection_id
	)
	_link_reciprocals(source, source_endpoint, target, target_endpoint)
	_mark_document(source)
	_mark_document(target)
	return {
		"ok": true,
		"pair_id": pair_id,
		"forward_endpoint": source_endpoint,
		"reverse_endpoint": target_endpoint,
	}


static func configure_one_way_to_arrival(
	source: Dictionary,
	source_exit_id: String,
	target: Dictionary,
	target_arrival_id: String,
	display_name: String,
	connection_id: String,
	reason: String
) -> Dictionary:
	var source_endpoint := _entry(
		source.layers.get("map_exit_points", []), source_exit_id
	)
	var target_arrival := _entry(
		target.layers.get("map_exit_points", []), target_arrival_id
	)
	if source_endpoint.is_empty():
		return {"ok": false, "errors": ["source_portal_missing"]}
	if target_arrival.is_empty():
		return {"ok": false, "errors": ["target_arrival_missing"]}
	var one_way := configure_explicit_one_way(source_endpoint, reason)
	if not bool(one_way.get("ok", false)):
		return one_way
	source_endpoint["display_name"] = display_name
	source_endpoint["target_configured"] = true
	source_endpoint["target_map_id"] = int(target.runtime_map_id)
	source_endpoint["target_map_key"] = str(target.map_id)
	source_endpoint["target_portal_id"] = str(target_arrival.semantic_id)
	source_endpoint["target_entrance_id"] = str(target_arrival.semantic_id)
	source_endpoint["target_tile"] = target_arrival.tile.duplicate()
	source_endpoint["official_connection_id"] = connection_id
	source_endpoint["source_map_key"] = str(source.map_id)

	target_arrival.merge(new_exit_defaults(), true)
	for field: String in [
		"connection_pair_id",
		"reciprocal_exit_id",
		"reciprocal_map_key",
		"target_portal_id",
		"target_entrance_id",
		"target_tile",
		"official_connection_id",
	]:
		target_arrival.erase(field)
	# Preserve the human-authored terminal label.  Corpse King Hall was the
	# original one-way fixture, but this helper is shared by every terminal
	# dungeon and must not rename their accepted arrival anchors.
	var arrival_display_name := str(target_arrival.get("display_name", "")).strip_edges()
	if arrival_display_name.is_empty():
		arrival_display_name = "地图入口（仅到达）"
	target_arrival["display_name"] = arrival_display_name
	target_arrival["portal_role"] = "arrival_only_endpoint"
	target_arrival["semantic_role"] = "map_portal_arrival_anchor"
	target_arrival["connection_mode"] = "arrival_only"
	target_arrival["one_way"] = false
	target_arrival["arrival_only"] = true
	target_arrival["trigger_on_enter"] = false
	target_arrival["target_configured"] = false
	target_arrival["target_map_id"] = -1
	target_arrival["explicit_one_way_reason"] = reason.strip_edges()
	target_arrival["exit_policy"] = "town_scroll_or_death_only"
	_mark_document(source)
	_mark_document(target)
	return {
		"ok": true,
		"source_endpoint": source_endpoint,
		"target_arrival": target_arrival,
	}


static func configure_explicit_one_way(
	map_exit: Dictionary,
	reason: String
) -> Dictionary:
	if reason.strip_edges().is_empty():
		return {"ok": false, "errors": ["one_way_reason_required"]}
	map_exit.merge(new_exit_defaults(), true)
	map_exit["connection_mode"] = "one_way"
	map_exit["one_way"] = true
	map_exit["portal_role"] = "one_way_endpoint"
	map_exit["explicit_one_way_reason"] = reason.strip_edges()
	for field: String in [
		"connection_pair_id",
		"reciprocal_exit_id",
		"reciprocal_map_key",
	]:
		map_exit.erase(field)
	return {"ok": true, "entry": map_exit}


static func validate_document(document: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var entrances: Array = document.get("layers", {}).get(
		"map_entrance_points", []
	)
	for endpoint: Dictionary in document.get("layers", {}).get(
		"map_exit_points", []
	):
		var semantic_id := str(endpoint.get("semantic_id", ""))
		if bool(endpoint.get("arrival_only", false)):
			_validate_arrival_only(endpoint, semantic_id, errors)
			continue
		if not bool(endpoint.get("target_configured", false)):
			continue
		var policy_id := str(endpoint.get("connection_policy_id", ""))
		if policy_id == LEGACY_POLICY_ID:
			errors.append(
				"legacy_overlapping_portal_policy_requires_migration:%s"
				% endpoint.get("semantic_id", "")
			)
			continue
		if policy_id != POLICY_ID:
			continue
		if str(endpoint.get("portal_contract_id", "")) != PORTAL_CONTRACT_ID:
			errors.append("unified_portal_contract_required:%s" % semantic_id)
		if bool(endpoint.get("one_way", false)):
			_validate_one_way(endpoint, semantic_id, errors)
			continue
		_validate_bidirectional(endpoint, semantic_id, errors)
		for entrance: Dictionary in entrances:
			if _tile(entrance) == _tile(endpoint):
				errors.append(
					"overlapping_entrance_and_portal:%s:%s"
					% [entrance.get("semantic_id", ""), semantic_id]
				)
	return errors


static func validate_reciprocal_pairs(
	documents_by_map_id: Dictionary
) -> Array[String]:
	var errors: Array[String] = []
	for source_map_id: String in documents_by_map_id:
		var source: Dictionary = documents_by_map_id[source_map_id]
		for endpoint: Dictionary in source.layers.get("map_exit_points", []):
			if not _is_managed_bidirectional(endpoint):
				continue
			var target_map_key := str(endpoint.get("target_map_key", ""))
			if not documents_by_map_id.has(target_map_key):
				errors.append(
					"reciprocal_target_document_missing:%s"
					% endpoint.semantic_id
				)
				continue
			var target: Dictionary = documents_by_map_id[target_map_key]
			var reciprocal := _entry(
				target.layers.get("map_exit_points", []),
				str(endpoint.get("target_portal_id", ""))
			)
			if reciprocal.is_empty():
				errors.append(
					"target_portal_missing:%s" % endpoint.semantic_id
				)
				continue
			_validate_pair_endpoint(
				source_map_id, endpoint, reciprocal, errors
			)
	return errors


static func policy() -> Dictionary:
	if not FileAccess.file_exists(POLICY_PATH):
		return {}
	var file := FileAccess.open(POLICY_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


static func _new_endpoint(
	document: Dictionary,
	tile: Vector2i,
	display_name: String,
	pair_id: String,
	direction: String
) -> Dictionary:
	var endpoint := new_exit_defaults()
	endpoint.merge({
		"kind": "map_exit",
		"tile": [tile.x, tile.y],
		"content_layer": "personal_expansion",
		"runtime_export": true,
		"semantic_id": _next_exit_id(
			document.layers.get("map_exit_points", [])
		),
		"exit_id": "",
		"semantic_role": "map_portal_endpoint",
		"trigger_on_enter": true,
		"blocks_movement": false,
		"display_name": display_name,
		"connection_pair_id": pair_id,
		"connection_direction": direction,
	}, true)
	endpoint["exit_id"] = str(endpoint.semantic_id)
	var endpoints: Array = document.layers.get("map_exit_points", [])
	endpoints.append(endpoint)
	document.layers["map_exit_points"] = endpoints
	return endpoint


static func _configure_endpoint(
	endpoint: Dictionary,
	source: Dictionary,
	target: Dictionary,
	target_endpoint: Dictionary,
	pair_id: String,
	direction: String,
	display_name: String,
	connection_id: String
) -> void:
	endpoint.merge(new_exit_defaults(), true)
	endpoint.erase("explicit_one_way_reason")
	endpoint.erase("shared_with_entrance_id")
	endpoint["display_name"] = display_name
	endpoint["target_configured"] = true
	endpoint["target_map_id"] = int(target.runtime_map_id)
	endpoint["target_map_key"] = str(target.map_id)
	endpoint["target_portal_id"] = str(target_endpoint.semantic_id)
	# Compatibility alias for the current integration bridge.  It points to the
	# same unified endpoint, not to a second overlapping entrance object.
	endpoint["target_entrance_id"] = str(target_endpoint.semantic_id)
	endpoint["target_tile"] = target_endpoint.tile.duplicate()
	endpoint["official_connection_id"] = connection_id
	endpoint["connection_pair_id"] = pair_id
	endpoint["connection_direction"] = direction
	endpoint["source_map_key"] = str(source.map_id)
	endpoint["semantic_role"] = "map_portal_endpoint"


static func _link_reciprocals(
	source: Dictionary,
	source_endpoint: Dictionary,
	target: Dictionary,
	target_endpoint: Dictionary
) -> void:
	source_endpoint["reciprocal_exit_id"] = str(target_endpoint.semantic_id)
	source_endpoint["reciprocal_map_key"] = str(target.map_id)
	target_endpoint["reciprocal_exit_id"] = str(source_endpoint.semantic_id)
	target_endpoint["reciprocal_map_key"] = str(source.map_id)


static func _validate_bidirectional(
	endpoint: Dictionary,
	semantic_id: String,
	errors: Array[String]
) -> void:
	if str(endpoint.get("connection_mode", "")) != DEFAULT_CONNECTION_MODE:
		errors.append("bidirectional_mode_required:%s" % semantic_id)
	for field: String in [
		"connection_pair_id",
		"target_portal_id",
		"reciprocal_exit_id",
		"reciprocal_map_key",
	]:
		if str(endpoint.get(field, "")).strip_edges().is_empty():
			errors.append("%s_required:%s" % [field, semantic_id])
	if str(endpoint.get("portal_role", "")) != "bidirectional_endpoint":
		errors.append("bidirectional_portal_role_required:%s" % semantic_id)
	if str(endpoint.get("arrival_reentry_policy_id", "")) != ARRIVAL_REENTRY_POLICY_ID:
		errors.append("arrival_reentry_policy_required:%s" % semantic_id)
	if not bool(endpoint.get("arrival_locks_current_portal", false)):
		errors.append("arrival_portal_lock_required:%s" % semantic_id)
	if not bool(endpoint.get("requires_leave_before_retrigger", false)):
		errors.append("leave_before_retrigger_required:%s" % semantic_id)
	if float(endpoint.get("return_minimum_seconds", 0.0)) < RETURN_MINIMUM_SECONDS:
		errors.append("return_minimum_seconds_required:%s" % semantic_id)
	if float(endpoint.get("return_unlock_distance_gu", 0.0)) < RETURN_UNLOCK_DISTANCE_GU:
		errors.append("return_unlock_distance_required:%s" % semantic_id)
	if not bool(endpoint.get("return_requires_fresh_activation", false)):
		errors.append("fresh_activation_required:%s" % semantic_id)
	if not bool(endpoint.get("travel_request_single_flight", false)):
		errors.append("single_flight_required:%s" % semantic_id)


static func _validate_one_way(
	endpoint: Dictionary,
	semantic_id: String,
	errors: Array[String]
) -> void:
	if str(endpoint.get("connection_mode", "")) != "one_way":
		errors.append("one_way_mode_mismatch:%s" % semantic_id)
	if str(endpoint.get("explicit_one_way_reason", "")).strip_edges().is_empty():
		errors.append("one_way_reason_required:%s" % semantic_id)
	if str(endpoint.get("portal_role", "")) != "one_way_endpoint":
		errors.append("one_way_portal_role_required:%s" % semantic_id)
	for field: String in [
		"target_map_key",
		"target_portal_id",
	]:
		if str(endpoint.get(field, "")).strip_edges().is_empty():
			errors.append("%s_required:%s" % [field, semantic_id])
	var target_tile: Array = endpoint.get("target_tile", [])
	if target_tile.size() != 2:
		errors.append("target_tile_required:%s" % semantic_id)


static func _validate_arrival_only(
	endpoint: Dictionary,
	semantic_id: String,
	errors: Array[String]
) -> void:
	if str(endpoint.get("portal_contract_id", "")) != PORTAL_CONTRACT_ID:
		errors.append("arrival_portal_contract_required:%s" % semantic_id)
	if str(endpoint.get("portal_role", "")) != "arrival_only_endpoint":
		errors.append("arrival_only_portal_role_required:%s" % semantic_id)
	if str(endpoint.get("connection_mode", "")) != "arrival_only":
		errors.append("arrival_only_mode_required:%s" % semantic_id)
	if bool(endpoint.get("trigger_on_enter", true)):
		errors.append("arrival_only_trigger_must_be_disabled:%s" % semantic_id)
	if bool(endpoint.get("target_configured", true)):
		errors.append("arrival_only_target_must_be_disabled:%s" % semantic_id)
	if str(endpoint.get("exit_policy", "")) != "town_scroll_or_death_only":
		errors.append("arrival_only_exit_policy_required:%s" % semantic_id)


static func _validate_pair_endpoint(
	source_map_id: String,
	endpoint: Dictionary,
	reciprocal: Dictionary,
	errors: Array[String]
) -> void:
	var semantic_id := str(endpoint.semantic_id)
	if str(reciprocal.get("target_map_key", "")) != source_map_id:
		errors.append("reciprocal_target_mismatch:%s" % semantic_id)
	if str(reciprocal.get("target_portal_id", "")) != semantic_id:
		errors.append("reciprocal_portal_id_mismatch:%s" % semantic_id)
	if str(reciprocal.get("reciprocal_exit_id", "")) != semantic_id:
		errors.append("reciprocal_id_mismatch:%s" % semantic_id)
	if str(reciprocal.get("connection_pair_id", "")) != str(
		endpoint.get("connection_pair_id", "")
	):
		errors.append("connection_pair_mismatch:%s" % semantic_id)
	if _tile_value(endpoint.get("target_tile", [])) != _tile(reciprocal):
		errors.append("target_portal_tile_mismatch:%s" % semantic_id)


static func _is_managed_bidirectional(endpoint: Dictionary) -> bool:
	return (
		bool(endpoint.get("target_configured", false))
		and not bool(endpoint.get("one_way", false))
		and str(endpoint.get("connection_policy_id", "")) == POLICY_ID
	)


static func _mark_document(document: Dictionary) -> void:
	var meta: Dictionary = document.get("editor_meta", {})
	meta["connection_policy_id"] = POLICY_ID
	meta["portal_contract_id"] = PORTAL_CONTRACT_ID
	meta["default_connection_mode"] = DEFAULT_CONNECTION_MODE
	document["editor_meta"] = meta


static func _remove_entry(
	document: Dictionary,
	layer: String,
	semantic_id: String
) -> void:
	var entries: Array = document.layers.get(layer, [])
	for index in range(entries.size() - 1, -1, -1):
		if str(entries[index].get("semantic_id", "")) == semantic_id:
			entries.remove_at(index)
	document.layers[layer] = entries


static func _exit_by_pair(
	entries: Array,
	pair_id: String,
	direction: String
) -> Dictionary:
	for entry: Dictionary in entries:
		if (
			str(entry.get("connection_pair_id", "")) == pair_id
			and str(entry.get("connection_direction", "")) == direction
		):
			return entry
	return {}


static func _entry(entries: Array, semantic_id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if str(entry.get("semantic_id", "")) == semantic_id:
			return entry
	return {}


static func _next_exit_id(entries: Array) -> String:
	var maximum := 0
	for entry: Dictionary in entries:
		var semantic_id := str(entry.get("semantic_id", ""))
		if semantic_id.begins_with("map_exit_"):
			maximum = maxi(
				maximum,
				semantic_id.trim_prefix("map_exit_").to_int()
			)
	return "map_exit_%06d" % (maximum + 1)


static func _tile(entry: Dictionary) -> Vector2i:
	return _tile_value(entry.get("tile", [0, 0]))


static func _tile_value(raw: Array) -> Vector2i:
	if raw.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(raw[0]), int(raw[1]))
