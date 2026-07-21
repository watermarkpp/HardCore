class_name MapEditorConnectionPolicyService
extends RefCounted

const POLICY_PATH := (
	"res://assets/data/map_design/map_connection_policy.json"
)
const POLICY_ID := "map_connection_bidirectional_default_v1"
const DEFAULT_CONNECTION_MODE := "bidirectional"
const ARRIVAL_REENTRY_POLICY_ID := "portal_leave_then_reenter_v1"


static func new_exit_defaults() -> Dictionary:
	return {
		"connection_policy_id": POLICY_ID,
		"connection_mode": DEFAULT_CONNECTION_MODE,
		"one_way": false,
		"connection_pair_id": "",
		"reciprocal_exit_id": "",
		"reciprocal_map_key": "",
		"arrival_reentry_policy_id": ARRIVAL_REENTRY_POLICY_ID,
		"requires_leave_before_retrigger": true,
	}


static func configure_bidirectional(
	source: Dictionary,
	source_exit_id: String,
	source_entrance_id: String,
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
	var source_exit := _entry(
		source.layers.get("map_exit_points", []),
		source_exit_id
	)
	var source_entrance := _entry(
		source.layers.get("map_entrance_points", []),
		source_entrance_id
	)
	var target_entrance := _entry(
		target.layers.get("map_entrance_points", []),
		target_entrance_id
	)
	if source_exit.is_empty():
		return {"ok": false, "errors": ["source_exit_missing"]}
	if source_entrance.is_empty():
		return {"ok": false, "errors": ["source_entrance_missing"]}
	if target_entrance.is_empty():
		return {"ok": false, "errors": ["target_entrance_missing"]}

	var reverse_exit := _exit_by_pair(
		target.layers.get("map_exit_points", []),
		pair_id,
		"reverse"
	)
	if reverse_exit.is_empty():
		var reverse_tile := _tile(target_entrance)
		reverse_exit = new_exit_defaults()
		reverse_exit.merge({
			"kind": "map_exit",
			"tile": [reverse_tile.x, reverse_tile.y],
			"content_layer": "personal_expansion",
			"runtime_export": true,
			"semantic_id": _next_exit_id(
				target.layers.get("map_exit_points", [])
			),
			"exit_id": "",
			"portal_role": "exit",
			"target_map_id": "",
			"target_entrance_id": "",
			"semantic_role": "map_exit_trigger",
			"trigger_on_enter": true,
			"blocks_movement": false,
			"display_name": reverse_display_name,
			"shared_with_entrance_id": target_entrance_id,
			"connection_pair_id": pair_id,
			"connection_direction": "reverse",
		}, true)
		reverse_exit["exit_id"] = str(reverse_exit.semantic_id)
		var target_exits: Array = target.layers.get("map_exit_points", [])
		target_exits.append(reverse_exit)
		target.layers["map_exit_points"] = target_exits
	else:
		var reverse_tile := _tile(target_entrance)
		reverse_exit["tile"] = [reverse_tile.x, reverse_tile.y]

	_configure_exit(
		source_exit,
		source,
		target,
		target_entrance,
		pair_id,
		"forward",
		forward_display_name,
		forward_connection_id
	)
	_configure_exit(
		reverse_exit,
		target,
		source,
		source_entrance,
		pair_id,
		"reverse",
		reverse_display_name,
		reverse_connection_id
	)
	source_exit["reciprocal_exit_id"] = str(reverse_exit.semantic_id)
	source_exit["reciprocal_map_key"] = str(target.map_id)
	reverse_exit["reciprocal_exit_id"] = str(source_exit.semantic_id)
	reverse_exit["reciprocal_map_key"] = str(source.map_id)
	reverse_exit["shared_with_entrance_id"] = target_entrance_id
	_mark_document(source)
	_mark_document(target)
	return {
		"ok": true,
		"pair_id": pair_id,
		"forward_exit": source_exit,
		"reverse_exit": reverse_exit,
	}


static func configure_explicit_one_way(
	map_exit: Dictionary,
	reason: String
) -> Dictionary:
	if reason.strip_edges().is_empty():
		return {"ok": false, "errors": ["one_way_reason_required"]}
	map_exit["connection_policy_id"] = POLICY_ID
	map_exit["connection_mode"] = "one_way"
	map_exit["one_way"] = true
	map_exit["explicit_one_way_reason"] = reason.strip_edges()
	map_exit.erase("connection_pair_id")
	map_exit.erase("reciprocal_exit_id")
	map_exit.erase("reciprocal_map_key")
	return {"ok": true, "entry": map_exit}


static func validate_document(document: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for map_exit: Dictionary in document.get("layers", {}).get(
		"map_exit_points", []
	):
		if not bool(map_exit.get("target_configured", false)):
			continue
		if str(map_exit.get("connection_policy_id", "")) != POLICY_ID:
			continue
		var semantic_id := str(map_exit.get("semantic_id", ""))
		var one_way := bool(map_exit.get("one_way", false))
		var mode := str(map_exit.get("connection_mode", ""))
		if one_way:
			if mode != "one_way":
				errors.append("one_way_mode_mismatch:%s" % semantic_id)
			if str(map_exit.get("explicit_one_way_reason", "")).strip_edges().is_empty():
				errors.append("one_way_reason_required:%s" % semantic_id)
			continue
		if mode != DEFAULT_CONNECTION_MODE:
			errors.append("bidirectional_mode_required:%s" % semantic_id)
		for field: String in [
			"connection_pair_id",
			"reciprocal_exit_id",
			"reciprocal_map_key",
		]:
			if str(map_exit.get(field, "")).strip_edges().is_empty():
				errors.append("%s_required:%s" % [field, semantic_id])
		if str(map_exit.get("arrival_reentry_policy_id", "")) != ARRIVAL_REENTRY_POLICY_ID:
			errors.append("arrival_reentry_policy_required:%s" % semantic_id)
		if not bool(map_exit.get("requires_leave_before_retrigger", false)):
			errors.append("leave_before_retrigger_required:%s" % semantic_id)
		var shared_entrance_id := str(
			map_exit.get("shared_with_entrance_id", "")
		)
		if not shared_entrance_id.is_empty():
			var entrance := _entry(
				document.get("layers", {}).get(
					"map_entrance_points", []
				),
				shared_entrance_id
			)
			if entrance.is_empty():
				errors.append(
					"shared_entrance_missing:%s" % semantic_id
				)
			elif _tile(entrance) != _tile(map_exit):
				errors.append(
					"shared_entrance_tile_mismatch:%s" % semantic_id
				)
	return errors


static func validate_reciprocal_pairs(
	documents_by_map_id: Dictionary
) -> Array[String]:
	var errors: Array[String] = []
	for source_map_id: String in documents_by_map_id:
		var source: Dictionary = documents_by_map_id[source_map_id]
		for map_exit: Dictionary in source.layers.get("map_exit_points", []):
			if bool(map_exit.get("one_way", false)):
				continue
			if str(map_exit.get("connection_policy_id", "")) != POLICY_ID:
				continue
			if not bool(map_exit.get("target_configured", false)):
				continue
			var target_map_key := str(map_exit.get("target_map_key", ""))
			if not documents_by_map_id.has(target_map_key):
				errors.append("reciprocal_target_document_missing:%s" % map_exit.semantic_id)
				continue
			var target: Dictionary = documents_by_map_id[target_map_key]
			var reciprocal := _entry(
				target.layers.get("map_exit_points", []),
				str(map_exit.get("reciprocal_exit_id", ""))
			)
			if reciprocal.is_empty():
				errors.append("reciprocal_exit_missing:%s" % map_exit.semantic_id)
				continue
			if str(reciprocal.get("target_map_key", "")) != source_map_id:
				errors.append("reciprocal_target_mismatch:%s" % map_exit.semantic_id)
			if str(reciprocal.get("reciprocal_exit_id", "")) != str(map_exit.semantic_id):
				errors.append("reciprocal_id_mismatch:%s" % map_exit.semantic_id)
			if str(reciprocal.get("connection_pair_id", "")) != str(map_exit.get("connection_pair_id", "")):
				errors.append("connection_pair_mismatch:%s" % map_exit.semantic_id)
			var target_entrance := _entry(
				target.layers.get("map_entrance_points", []),
				str(map_exit.get("target_entrance_id", ""))
			)
			if target_entrance.is_empty():
				errors.append(
					"target_entrance_missing:%s" % map_exit.semantic_id
				)
			elif _tile_value(map_exit.get("target_tile", [])) != _tile(
				target_entrance
			):
				errors.append(
					"target_entrance_tile_mismatch:%s"
					% map_exit.semantic_id
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


static func _configure_exit(
	map_exit: Dictionary,
	source: Dictionary,
	target: Dictionary,
	target_entrance: Dictionary,
	pair_id: String,
	direction: String,
	display_name: String,
	connection_id: String
) -> void:
	map_exit.erase("radius_tiles")
	map_exit.erase("explicit_one_way_reason")
	map_exit["display_name"] = display_name
	map_exit["target_configured"] = true
	map_exit["target_map_id"] = int(target.runtime_map_id)
	map_exit["target_map_key"] = str(target.map_id)
	map_exit["target_entrance_id"] = str(target_entrance.entrance_id)
	map_exit["target_tile"] = target_entrance.tile.duplicate()
	map_exit["official_connection_id"] = connection_id
	map_exit["connection_policy_id"] = POLICY_ID
	map_exit["connection_mode"] = DEFAULT_CONNECTION_MODE
	map_exit["one_way"] = false
	map_exit["connection_pair_id"] = pair_id
	map_exit["connection_direction"] = direction
	map_exit["source_map_key"] = str(source.map_id)
	map_exit["arrival_reentry_policy_id"] = ARRIVAL_REENTRY_POLICY_ID
	map_exit["requires_leave_before_retrigger"] = true


static func _mark_document(document: Dictionary) -> void:
	var meta: Dictionary = document.get("editor_meta", {})
	meta["connection_policy_id"] = POLICY_ID
	meta["default_connection_mode"] = DEFAULT_CONNECTION_MODE
	document["editor_meta"] = meta


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
	var raw: Array = entry.get("tile", [0, 0])
	return Vector2i(int(raw[0]), int(raw[1]))


static func _tile_value(raw: Array) -> Vector2i:
	if raw.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(raw[0]), int(raw[1]))
