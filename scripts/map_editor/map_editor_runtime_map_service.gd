class_name MapEditorRuntimeMapService
extends RefCounted

const PortalRuntimeService := preload(
	"res://scripts/map_editor/map_portal_runtime_service.gd"
)
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const UnitLegacyAdapter := preload(
	"res://scripts/map_editor/map_editor_unit_legacy_adapter.gd"
)


static func load_runtime(path: String) -> Dictionary:
	# Keep virtual Godot paths virtual.  Globalizing res:// works in the desktop
	# editor, but on Android it turns a packed resource into a filesystem path;
	# FileAccess then tries (and fails) to open it through assets.sparsepck.
	var resolved := path
	if not FileAccess.file_exists(resolved):
		return {"ok": false, "errors": ["runtime_file_missing"]}
	var file := FileAccess.open(resolved, FileAccess.READ)
	if file == null:
		return {"ok": false, "errors": ["runtime_file_open_failed"]}
	var raw := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return {"ok": false, "errors": ["runtime_json_invalid"]}
	var raw_runtime: Dictionary = parsed
	var errors := validate_runtime(raw_runtime, raw)
	var runtime := raw_runtime
	if errors.is_empty() and int(raw_runtime.get(
		"runtime_schema_version", -1
	)) == MapEditorBuildRuntimeService.LEGACY_RUNTIME_SCHEMA_VERSION:
		runtime = UnitLegacyAdapter.adapt_runtime_v1_to_v2(raw_runtime)
	return {"ok": errors.is_empty(), "runtime": runtime, "errors": errors, "path": path}


static func validate_runtime(runtime: Dictionary, raw_text := "") -> Array[String]:
	var errors: Array[String] = []
	var schema_version := int(runtime.get("runtime_schema_version", -1))
	if schema_version not in [
		MapEditorBuildRuntimeService.LEGACY_RUNTIME_SCHEMA_VERSION,
		MapEditorBuildRuntimeService.RUNTIME_SCHEMA_VERSION,
	]:
		errors.append("unsupported_runtime_schema")
	if schema_version == MapEditorBuildRuntimeService.RUNTIME_SCHEMA_VERSION:
		if str(runtime.get("unit_contract_id", "")) != GroundUnitSpaceScript.CONTRACT_ID:
			errors.append("runtime_unit_contract_invalid")
		if str(runtime.get("projection_contract_id", "")) != GroundUnitSpaceScript.PROJECTION_CONTRACT_ID:
			errors.append("runtime_projection_contract_invalid")
		errors.append_array(
			UnitLegacyAdapter.validate_runtime_v2_has_no_legacy_unit_fields(
				runtime
			)
		)
		_validate_v2_semantic_units(runtime, errors)
	for field: String in ["source", "design", "ground", "instances", "collision", "semantics", "build_sha256"]:
		if not runtime.has(field): errors.append("runtime_missing_%s" % field)
	var size: Array = runtime.get("design", {}).get("design_size", [])
	if size.size() != 2 or int(size[0]) <= 0 or int(size[1]) <= 0:
		errors.append("runtime_design_size_invalid")
	var checksum_source := runtime.duplicate(true)
	var claimed_hash := str(checksum_source.get("build_sha256", ""))
	checksum_source["build_sha256"] = ""
	if claimed_hash != _sha256(MapEditorJsonCodec.encode(checksum_source)):
		errors.append("runtime_checksum_invalid")
	var serialized := raw_text if not raw_text.is_empty() else MapEditorJsonCodec.encode(runtime)
	if serialized.contains("map_editor_workspace") or serialized.contains(".editor.json"):
		errors.append("editor_workspace_reference_forbidden")
	for door: Dictionary in runtime.get("semantics", {}).get("door_points", []):
		if str(door.get("target_map_id", "")).strip_edges().is_empty():
			errors.append("runtime_door_target_missing")
	for map_exit: Dictionary in runtime.get("semantics", {}).get("map_exit_points", []):
		if str(map_exit.get("target_map_id", "")).strip_edges().is_empty():
			errors.append("runtime_map_exit_target_missing")
		if bool(map_exit.get("arrival_only", false)):
			if bool(map_exit.get("trigger_on_enter", true)):
				errors.append("runtime_arrival_only_trigger_enabled")
			if bool(map_exit.get("target_configured", true)):
				errors.append("runtime_arrival_only_target_enabled")
			continue
		if not bool(map_exit.get("target_configured", false)):
			continue
		if str(map_exit.get("portal_contract_id", "")) == PortalRuntimeService.PORTAL_CONTRACT_ID:
			for field: String in [
				"target_portal_id",
				"target_map_key",
				"arrival_reentry_policy_id",
			]:
				if str(map_exit.get(field, "")).strip_edges().is_empty():
					errors.append("runtime_portal_%s_missing" % field)
			if not bool(map_exit.get("travel_request_single_flight", false)):
				errors.append("runtime_portal_single_flight_required")
	return errors


static func _validate_v2_semantic_units(
	runtime: Dictionary,
	errors: Array[String]
) -> void:
	for layer_name: String in runtime.get("semantics", {}):
		for entry: Dictionary in runtime.semantics.get(layer_name, []):
			var kind := str(entry.get("kind", ""))
			var semantic_id := str(entry.get("semantic_id", kind))
			if kind in ["monster_spawn", "boss_spawn", "safe_area", "light", "region_trigger"]:
				if not entry.has("radius_gu"):
					errors.append("runtime_radius_gu_missing:%s" % semantic_id)
			if kind in ["safe_area", "light", "region_trigger"]:
				if not entry.has("polygon_ground_gu"):
					errors.append("runtime_polygon_ground_gu_missing:%s" % semantic_id)
			if kind in ["door", "map_exit"]:
				if not entry.has("return_unlock_distance_gu"):
					errors.append("runtime_portal_distance_gu_missing:%s" % semantic_id)


static func is_blocked(runtime: Dictionary, tile: Vector2i) -> bool:
	return runtime.get("collision", {}).get("blocked_tiles", []).has("%d,%d" % [tile.x, tile.y])


static func entries_at(runtime: Dictionary, tile: Vector2i, kind := "") -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for layer: String in runtime.get("semantics", {}):
		for entry: Dictionary in runtime.semantics[layer]:
			var raw_tile: Array = entry.get("tile", [])
			if raw_tile.size() == 2 and int(raw_tile[0]) == tile.x and int(raw_tile[1]) == tile.y and (kind.is_empty() or str(entry.get("kind", "")) == kind):
				found.append(entry)
	return found


static func _sha256(text: String) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(text.to_utf8_buffer())
	return hashing.finish().hex_encode()
