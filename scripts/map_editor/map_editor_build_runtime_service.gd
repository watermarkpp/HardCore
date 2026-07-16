class_name MapEditorBuildRuntimeService
extends RefCounted

const RUNTIME_SCHEMA_VERSION := 1
const RUNTIME_ROOT := "res://assets/data/runtime/map_editor/"


static func approve_for_runtime(document: Dictionary) -> Dictionary:
	var validation := validate_for_runtime(document)
	if not validation.ok:
		return validation
	var meta: Dictionary = document.get("editor_meta", {})
	meta["runtime_approved"] = true
	meta["runtime_approved_revision"] = int(meta.get("revision", 1))
	document["editor_meta"] = meta
	return {"ok": true, "validation": validation}


static func validate_for_runtime(document: Dictionary) -> Dictionary:
	var errors := MapEditorTypes.validate_document(document)
	var warnings: Array[String] = []
	var initialized := MapEditorGroundService.initialize(document)
	if not initialized.ok:
		errors.append_array(initialized.get("errors", []))
	else:
		if not (initialized.state.get("dirty_chunks", []) as Array).is_empty():
			errors.append("ground_dirty_chunks_must_be_baked")
		if not (initialized.manifest.get("chunks", []) as Array).all(func(chunk: Dictionary) -> bool: return str(chunk.get("state", "")) != "dirty"):
			errors.append("ground_manifest_contains_dirty_chunk")
	var seen_semantic_ids := {}
	for entry: Dictionary in MapEditorGameplaySemanticService.all_entries(document):
		var semantic_id := str(entry.get("semantic_id", ""))
		if semantic_id.is_empty() or seen_semantic_ids.has(semantic_id):
			errors.append("duplicate_or_missing_semantic_id:%s" % semantic_id)
		seen_semantic_ids[semantic_id] = true
		var tile: Array = entry.get("tile", [])
		if tile.size() != 2:
			errors.append("semantic_tile_missing:%s" % semantic_id)
		if str(entry.get("kind", "")) == "door" and str(entry.get("target_map_id", "")).strip_edges().is_empty():
			errors.append("door_target_map_required:%s" % semantic_id)
	var walkability := MapEditorCollisionService.build_walkability(document)
	if int(walkability.get("walkable_count", 0)) <= 0:
		errors.append("map_has_no_walkable_tile")
	if MapEditorInstanceService.all_instances(document).filter(func(instance: Dictionary) -> bool: return not bool(instance.get("runtime_export", true))).size() > 0:
		warnings.append("non_runtime_instances_excluded")
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings, "walkability": walkability}


static func build(document: Dictionary, output_path := "") -> Dictionary:
	if not bool(document.get("editor_meta", {}).get("runtime_approved", false)):
		return {"ok": false, "errors": ["runtime_approval_required"]}
	var validation := validate_for_runtime(document)
	if not validation.ok:
		return validation
	var runtime := _compile(document, validation.walkability)
	var normalized: Variant = JSON.parse_string(MapEditorJsonCodec.encode(runtime))
	if normalized is Dictionary:
		runtime = normalized
	runtime["build_sha256"] = ""
	runtime["build_sha256"] = _sha256(MapEditorJsonCodec.encode(runtime))
	var target := output_path if not output_path.is_empty() else default_runtime_path(str(document.get("map_id", "unknown")))
	var write := _write_atomic(target, runtime)
	if not write.ok:
		return write
	return {"ok": true, "path": target, "runtime": runtime, "warnings": validation.warnings}


static func default_runtime_path(map_id: String) -> String:
	return RUNTIME_ROOT + map_id + ".runtime.json"


static func _compile(document: Dictionary, walkability: Dictionary) -> Dictionary:
	var initialized := MapEditorGroundService.initialize(document)
	var state: Dictionary = initialized.state
	var semantic_layers := {}
	for layer: String in ["npc_points", "monster_spawn", "boss_spawn", "door_points", "safe_area", "light", "region_trigger"]:
		var runtime_entries:Array=[]
		for source_entry:Dictionary in document.layers.get(layer,[]):
			var entry:=source_entry.duplicate(true)
			for editor_key:String in ["placeholder_instance_id","editor_visual_asset_id","editor_visual_only","selection_shape","selectable","movable"]:entry.erase(editor_key)
			runtime_entries.append(entry)
		semantic_layers[layer] = runtime_entries
	var instances: Array = []
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		if bool(instance.get("runtime_export", true)):
			instances.append(instance.duplicate(true))
	var blocked: Array = walkability.get("blocked_tiles", {}).keys()
	blocked.sort()
	var output := {
		"runtime_schema_version": RUNTIME_SCHEMA_VERSION,
		"source": {"map_id": document.map_id, "editor_schema_version": document.schema_version, "revision": document.editor_meta.get("revision", 1), "content_layer": document.content_layer},
		"design": document.design.duplicate(true),
		"ground": {"ground_mode": document.ground.ground_mode, "default_fill_asset_id": document.ground.blank_fill_asset_id, "tile_overrides": MapEditorGroundService.tile_overrides(state)},
		"instances": instances,
		"collision": {"blocked_tiles": blocked, "blocked_count": blocked.size(), "manual_shapes": document.layers.get("collision", []).duplicate(true)},
		"semantics": semantic_layers,
	}
	output["build_sha256"] = ""
	return output


static func _write_atomic(path: String, value: Dictionary) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	var mkdir := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if mkdir != OK:
		return {"ok": false, "errors": ["runtime_mkdir_failed:%d" % mkdir]}
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errors": ["runtime_temp_open_failed"]}
	file.store_string(MapEditorJsonCodec.encode(value))
	file.flush()
	file.close()
	var verify := FileAccess.open(temporary, FileAccess.READ)
	if verify == null:
		return {"ok": false, "errors": ["runtime_temp_verify_failed"]}
	var parsed: Variant = JSON.parse_string(verify.get_as_text())
	verify.close()
	if not parsed is Dictionary:
		return {"ok": false, "errors": ["runtime_temp_verify_failed"]}
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
	var promote := DirAccess.rename_absolute(temporary, absolute)
	return {"ok": promote == OK, "path": path, "errors": [] if promote == OK else ["runtime_promote_failed:%d" % promote]}


static func _sha256(text: String) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(text.to_utf8_buffer())
	return hashing.finish().hex_encode()
