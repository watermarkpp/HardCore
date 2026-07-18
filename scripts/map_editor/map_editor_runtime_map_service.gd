class_name MapEditorRuntimeMapService
extends RefCounted


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
	var runtime: Dictionary = parsed
	var errors := validate_runtime(runtime, raw)
	return {"ok": errors.is_empty(), "runtime": runtime, "errors": errors, "path": path}


static func validate_runtime(runtime: Dictionary, raw_text := "") -> Array[String]:
	var errors: Array[String] = []
	if int(runtime.get("runtime_schema_version", -1)) != MapEditorBuildRuntimeService.RUNTIME_SCHEMA_VERSION:
		errors.append("unsupported_runtime_schema")
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
	return errors


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
