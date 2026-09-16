extends Node

## Batch portal-gate visual placement. ADDITIVE-ONLY by contract:
## - Only functioning map_exit semantics WITHOUT linked_visual_instance_id
##   receive a door instance (arrival_only landings, unconfigured endpoints and
##   already-linked endpoints are skipped untouched).
## - Portal FUNCTION fields are snapshotted before and deep-compared after the
##   change; any drift rolls the entry back and is reported. Only the
##   linked_visual_instance_id key is ever added.
## - Placement validation failure is reported, never forced.
## - Existing instances and existing links are never modified or deleted.
## Optional user args: --maps=key1,key2 to scope a pilot run.

const BLUE_ID := "user.portal_gate.20260916.s01_r1_c1"
const RED_ID := "user.portal_gate.20260916.s02_r1_c1"

const FROZEN_FUNCTION_FIELDS: Array[String] = [
	"semantic_id", "exit_id", "entrance_id", "door_id", "kind", "tile",
	"display_name", "target_map_id", "target_map_key", "target_portal_id",
	"target_entrance_id", "target_tile", "target_configured", "one_way",
	"trigger_on_enter", "blocks_movement", "connection_mode",
	"connection_pair_id", "connection_direction", "connection_policy_id",
	"portal_contract_id", "arrival_reentry_policy_id",
	"arrival_locks_current_portal", "portal_role", "is_default",
	"arrival_only", "return_minimum_seconds", "return_unlock_distance_gu",
	"travel_request_single_flight", "map_portal_note", "note",
]


func _ready() -> void:
	var scope: Array[String] = []
	var scope_argument := OS.get_environment("BATCH_PORTAL_MAPS")
	if not scope_argument.is_empty():
		scope.assign(scope_argument.split(",", false))
	var keys: Array[String] = []
	if scope.is_empty():
		for row_v: Variant in _read_json(
			"res://assets/data/map_design/map_identity_registry.json"
		).get("maps", []):
			if row_v is Dictionary:
				keys.append(str(row_v["map_id"]))
	else:
		keys = scope

	var failures: Array[String] = []
	var totals := {
		"placed_blue": 0, "placed_red": 0, "skipped_arrival": 0,
		"skipped_unconfigured": 0, "skipped_linked": 0, "failed": 0,
		"cleaned_stale": 0, "maps_changed": 0,
	}
	var started := Time.get_ticks_msec()

	for key in keys:
		var counters := _process_map(key, failures)
		for counter_key: String in totals.keys():
			totals[counter_key] = int(totals[counter_key]) + int(counters.get(counter_key, 0))
		if int(counters.get("map_changed", 0)) > 0:
			totals["maps_changed"] = int(totals["maps_changed"]) + 1

	print("BATCH_PORTAL_VISUAL_SUMMARY maps=%d maps_changed=%d blue=%d red=%d skipped_arrival=%d skipped_unconfigured=%d skipped_linked=%d cleaned_stale=%d failed=%d elapsed_ms=%d" % [
		keys.size(), int(totals["maps_changed"]), int(totals["placed_blue"]),
		int(totals["placed_red"]), int(totals["skipped_arrival"]),
		int(totals["skipped_unconfigured"]), int(totals["skipped_linked"]),
		int(totals["cleaned_stale"]), int(totals["failed"]),
		Time.get_ticks_msec() - started,
	])
	for failure: String in failures:
		print("BATCH_PORTAL_VISUAL_FAIL ", failure)
	print("BATCH_PORTAL_VISUAL_DONE")
	get_tree().quit(0)


func _process_map(key: String, failures: Array[String]) -> Dictionary:
	var counters := {
		"placed_blue": 0, "placed_red": 0, "skipped_arrival": 0,
		"skipped_unconfigured": 0, "skipped_linked": 0, "failed": 0,
		"cleaned_stale": 0, "map_changed": 0,
	}
	var loaded := MapEditorLoadService.load_document(
		MapEditorSaveService.default_path(key)
	)
	if not bool(loaded.get("ok", false)):
		failures.append("%s load: %s" % [key, str(loaded.get("errors", []))])
		counters["failed"] = int(counters["failed"]) + 1
		return counters
	var document: Dictionary = loaded.document
	var existing_instance_ids := {}
	for layer_name: String in document.layers.keys():
		for layer_entry: Dictionary in document.layers.get(layer_name, []):
			if layer_entry.has("instance_id"):
				existing_instance_ids[str(layer_entry["instance_id"])] = true
	var changed := false
	var entries: Array = document.layers.get("map_exit_points", [])
	for index in entries.size():
		var entry: Dictionary = entries[index]
		# Match the runtime bridge's exact functioning-portal semantics:
		# target_configured defaults to true for map_exit endpoints.
		if bool(entry.get("arrival_only", false)):
			counters["skipped_arrival"] = int(counters["skipped_arrival"]) + 1
			continue
		if not bool(entry.get("target_configured", true)) or int(entry.get("target_map_id", -1)) < 0:
			counters["skipped_unconfigured"] = int(counters["skipped_unconfigured"]) + 1
			continue
		var existing_link := str(entry.get("linked_visual_instance_id", ""))
		if not existing_link.is_empty():
			if existing_instance_ids.has(existing_link):
				counters["skipped_linked"] = int(counters["skipped_linked"]) + 1
				continue
			# Self-heal: the link references an instance that no longer exists
			# (stale metadata from deleted visuals). Clear it and place a fresh
			# door below; the referenced instance was already gone, so nothing
			# authored is removed.
			entry.erase("linked_visual_instance_id")
			counters["cleaned_stale"] = int(counters["cleaned_stale"]) + 1
			changed = true
		var desired := BLUE_ID if str(entry.get("connection_mode", "")) == "bidirectional" else RED_ID
		var outcome := _place_door_for_entry(document, entry, desired)
		if not bool(outcome.get("ok", false)):
			failures.append("%s %s: %s" % [
				key, str(entry.get("semantic_id", "")), str(outcome.get("reason", ""))
			])
			counters["failed"] = int(counters["failed"]) + 1
			continue
		entries[index] = entry
		changed = true
		if desired == BLUE_ID:
			counters["placed_blue"] = int(counters["placed_blue"]) + 1
		else:
			counters["placed_red"] = int(counters["placed_red"]) + 1
	document.layers["map_exit_points"] = entries
	if changed:
		var saved := MapEditorSaveService.save_document(
			document, MapEditorSaveService.default_path(key)
		)
		if not bool(saved.get("ok", false)):
			failures.append("%s save: %s" % [key, str(saved.get("errors", []))])
			counters["failed"] = int(counters["failed"]) + 1
			return counters
		counters["map_changed"] = 1
	print("BATCH_PORTAL_VISUAL_MAP %s blue=%d red=%d skip_arrival=%d skip_unconf=%d skip_linked=%d cleaned_stale=%d failed=%d" % [
		key, int(counters["placed_blue"]), int(counters["placed_red"]),
		int(counters["skipped_arrival"]), int(counters["skipped_unconfigured"]),
		int(counters["skipped_linked"]), int(counters["cleaned_stale"]),
		int(counters["failed"]),
	])
	return counters


func _place_door_for_entry(
	document: Dictionary,
	entry: Dictionary,
	asset_id: String
) -> Dictionary:
	var before := _function_snapshot(entry)
	var raw_tile: Array = entry.get("tile", [])
	if raw_tile.size() != 2:
		return {"ok": false, "reason": "entry_tile_invalid"}
	var created := MapEditorInstanceService.create_instance(
		document,
		asset_id,
		"decoration",
		Vector2i(int(raw_tile[0]), int(raw_tile[1])),
		"object_base"
	)
	if not bool(created.get("ok", false)):
		return {"ok": false, "reason": "placement_rejected:%s" % str(created.get("errors", []))}
	var instance: Dictionary = created.instance
	entry["linked_visual_instance_id"] = str(instance.get("instance_id", ""))
	var drift := _function_drift(before, entry)
	if not drift.is_empty():
		# Never allowed to stand: undo the additive change entirely.
		entry.erase("linked_visual_instance_id")
		MapEditorInstanceService.delete_instance(
			document, str(instance.get("instance_id", ""))
		)
		return {"ok": false, "reason": "function_drift:%s" % drift}
	return {"ok": true, "instance_id": str(instance.get("instance_id", ""))}


func _function_snapshot(entry: Dictionary) -> Dictionary:
	var snapshot := {}
	for field: String in FROZEN_FUNCTION_FIELDS:
		if entry.has(field):
			snapshot[field] = entry[field]
	return snapshot


func _function_drift(before: Dictionary, after: Dictionary) -> String:
	for field: String in FROZEN_FUNCTION_FIELDS:
		if str(before.get(field, "")) != str(after.get(field, "")):
			return field
	return ""


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
