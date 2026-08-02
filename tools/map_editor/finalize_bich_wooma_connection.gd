extends SceneTree

const CONNECTION_VERSION_ID := "bich_wooma_connection_v1"
const BICH_PATH := "res://map_editor_workspace/bich_province/bich_province.editor.json"
const WOOMA_PATH := "res://map_editor_workspace/wooma_forest/wooma_forest.editor.json"
const TOMB_PATH := "res://map_editor_workspace/orc_tomb_1/orc_tomb_1.editor.json"
const BICH_MARKER := "res://assets/data/runtime/map_editor/bich_province.manual_ready.json"
const WOOMA_MARKER := "res://assets/data/runtime/map_editor/wooma_forest.manual_ready.json"


func _init() -> void:
	var bich := _load(BICH_PATH)
	var wooma := _load(WOOMA_PATH)
	var tomb := _load(TOMB_PATH)
	if bich.is_empty() or wooma.is_empty() or tomb.is_empty():
		return

	var north_exit := _entry(bich.layers.map_exit_points, "map_exit_000001")
	var east_exit := _entry(bich.layers.map_exit_points, "map_exit_000002")
	var wooma_entrance := _entry(
		wooma.layers.map_entrance_points,
		"map_entrance_000001"
	)
	var tomb_entrance := _entry(
		tomb.layers.map_entrance_points,
		"map_entrance_000001"
	)
	if (
		north_exit.is_empty()
		or east_exit.is_empty()
		or wooma_entrance.is_empty()
		or tomb_entrance.is_empty()
	):
		_fail("required_portal_marker_missing")
		return
	if _tile(north_exit) != Vector2i(6, 5):
		_fail("bich_north_exit_moved:%s" % north_exit.tile)
		return
	if _tile(east_exit) != Vector2i(72, 5):
		_fail("bich_east_exit_moved:%s" % east_exit.tile)
		return
	if _tile(wooma_entrance) != Vector2i(3, 52):
		_fail("wooma_entrance_moved:%s" % wooma_entrance.tile)
		return
	if _tile(tomb_entrance) != Vector2i(3, 35):
		_fail("orc_tomb_entrance_moved:%s" % tomb_entrance.tile)
		return

	_configure_exit(
		north_exit,
		"前往沃玛森林",
		int(wooma.runtime_map_id),
		str(wooma.map_id),
		wooma_entrance,
		"bich_north_to_wooma_forest_v1"
	)
	_configure_exit(
		east_exit,
		"进入兽人古墓一层",
		int(tomb.runtime_map_id),
		str(tomb.map_id),
		tomb_entrance,
		"bich_east_to_orc_tomb_1_v2"
	)
	wooma_entrance["display_name"] = "沃玛森林入口"
	for map_exit: Dictionary in wooma.layers.map_exit_points:
		if str(map_exit.get("target_map_id", "")).strip_edges().is_empty():
			map_exit["target_configured"] = false
			map_exit["target_map_id"] = -1
			map_exit["target_entrance_id"] = ""

	_mark_official(bich, "BICH-WOOMA-CONNECTION-V1")
	_mark_official(wooma, "WOOMA-FOREST-USER-MAP-READY")

	var bich_runtime := _save_and_build(bich, BICH_PATH)
	if bich_runtime.is_empty():
		return
	var wooma_runtime := _save_and_build(wooma, WOOMA_PATH)
	if wooma_runtime.is_empty():
		return
	if not _write_bich_marker(bich, bich_runtime):
		return
	if not _write_wooma_marker(wooma, wooma_runtime, north_exit):
		return

	print(
		"BICH_WOOMA_CONNECTION_FINALIZED "
		+ "bich_north=6,5->268:map_entrance_000001 "
		+ "bich_east=72,5->217:map_entrance_000001 "
		+ "wooma_instances=%d wooma_spawns=%d"
		% [
			wooma_runtime.instances.size(),
			wooma_runtime.semantics.monster_spawn.size(),
		]
	)
	quit(0)


func _load(path: String) -> Dictionary:
	var loaded := MapEditorLoadService.load_document(path)
	if not bool(loaded.get("ok", false)):
		_fail("load_failed:%s:%s" % [path, loaded.get("errors", [])])
		return {}
	return loaded.document


func _entry(entries: Array, semantic_id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if str(entry.get("semantic_id", "")) == semantic_id:
			return entry
	return {}


func _tile(entry: Dictionary) -> Vector2i:
	var raw: Array = entry.get("tile", [0, 0])
	return Vector2i(int(raw[0]), int(raw[1]))


func _configure_exit(
	map_exit: Dictionary,
	display_name: String,
	target_runtime_map_id: int,
	target_map_key: String,
	target_entrance: Dictionary,
	connection_id: String
) -> void:
	map_exit["display_name"] = display_name
	map_exit["target_configured"] = true
	map_exit["target_map_id"] = target_runtime_map_id
	map_exit["target_map_key"] = target_map_key
	map_exit["target_entrance_id"] = str(
		target_entrance.get("entrance_id", target_entrance.get("semantic_id", ""))
	)
	map_exit["target_tile"] = target_entrance.get("tile", [0, 0]).duplicate()
	map_exit["official_connection_id"] = connection_id


func _mark_official(document: Dictionary, milestone: String) -> void:
	var meta: Dictionary = document.get("editor_meta", {})
	if str(meta.get("connection_version_id", "")) != CONNECTION_VERSION_ID:
		meta["revision"] = int(meta.get("revision", 1)) + 1
	meta["connection_version_id"] = CONNECTION_VERSION_ID
	meta["milestone"] = milestone
	meta["official_source_authority"] = "user_saved_editor_document"
	meta["official_runtime_map_id"] = int(document.get("runtime_map_id", 0))
	if str(document.get("map_id", "")) == "wooma_forest":
		meta["official_version_id"] = "wooma_forest_user_official_v1"
		meta["content_policy"] = "user_authored_layers"
		meta["template_status"] = "user_authored_official"
	document["editor_meta"] = meta


func _save_and_build(document: Dictionary, path: String) -> Dictionary:
	var bake := MapEditorChunkBakeService.bake_dirty_chunks(document)
	if not bool(bake.get("ok", false)):
		_fail("%s_bake_failed:%s" % [document.map_id, bake.get("errors", [])])
		return {}
	var approval := MapEditorBuildRuntimeService.approve_for_runtime(document)
	if not bool(approval.get("ok", false)):
		_fail(
			"%s_approval_failed:%s"
			% [document.map_id, approval.get("errors", [])]
		)
		return {}
	var saved := MapEditorSaveService.save_document(document, path)
	if not bool(saved.get("ok", false)):
		_fail("%s_save_failed:%s" % [document.map_id, saved.get("errors", [])])
		return {}
	var built := MapEditorBuildRuntimeService.build(document)
	if not bool(built.get("ok", false)):
		_fail("%s_build_failed:%s" % [document.map_id, built.get("errors", [])])
		return {}
	return built.runtime


func _write_bich_marker(bich: Dictionary, runtime: Dictionary) -> bool:
	var configured: Array = []
	for layer_name: String in ["door_points", "map_exit_points"]:
		for entry: Dictionary in bich.layers.get(layer_name, []):
			if not bool(entry.get("target_configured", false)):
				continue
			configured.append(_connection_summary(entry))
	var marker := {
		"schema_version": 2,
		"map_id": "bich_province",
		"runtime_map_id": int(bich.runtime_map_id),
		"source_workspace": "map_editor_workspace/bich_province",
		"status": "user_confirmed_official_80x80",
		"official_version_id": str(
			bich.editor_meta.get("official_version_id", "")
		),
		"connection_version_id": CONNECTION_VERSION_ID,
		"runtime_build_sha256": str(runtime.build_sha256),
		"content": {
			"design_size": bich.design.design_size.duplicate(),
			"instances": runtime.instances.size(),
			"monster_spawns": runtime.semantics.monster_spawn.size(),
			"npcs": runtime.semantics.npc_points.size(),
			"doors": runtime.semantics.door_points.size(),
			"map_exits": runtime.semantics.map_exit_points.size(),
			"doors_pending_target_configuration": _pending_count(
				bich.layers.door_points
			),
			"map_exits_pending_target_configuration": _pending_count(
				bich.layers.map_exit_points
			),
			"configured_connections": configured,
			"north_exit_tile": [6, 5],
			"east_exit_tile": [72, 5],
		},
	}
	var write := MapEditorGroundService._write_json_atomic(BICH_MARKER, marker)
	if not bool(write.get("ok", false)):
		_fail("bich_marker_failed:%s" % write.get("errors", []))
		return false
	return true


func _write_wooma_marker(
	wooma: Dictionary,
	runtime: Dictionary,
	bich_north_exit: Dictionary
) -> bool:
	var entrance: Dictionary = wooma.layers.map_entrance_points[0]
	var marker := {
		"schema_version": 1,
		"map_id": "wooma_forest",
		"runtime_map_id": int(wooma.runtime_map_id),
		"source_workspace": "map_editor_workspace/wooma_forest",
		"status": "user_confirmed_official",
		"official_version_id": str(wooma.editor_meta.official_version_id),
		"connection_version_id": CONNECTION_VERSION_ID,
		"runtime_build_sha256": str(runtime.build_sha256),
		"content": {
			"design_size": wooma.design.design_size.duplicate(),
			"instances": runtime.instances.size(),
			"monster_spawns": runtime.semantics.monster_spawn.size(),
			"entrance_id": str(entrance.entrance_id),
			"entrance_tile": entrance.tile.duplicate(),
			"pending_exit_targets": wooma.layers.map_exit_points.size(),
			"incoming_from": {
				"map_id": "bich_province",
				"runtime_map_id": 4,
				"exit_id": str(bich_north_exit.semantic_id),
				"exit_tile": bich_north_exit.tile.duplicate(),
			},
		},
	}
	var write := MapEditorGroundService._write_json_atomic(
		WOOMA_MARKER,
		marker
	)
	if not bool(write.get("ok", false)):
		_fail("wooma_marker_failed:%s" % write.get("errors", []))
		return false
	return true


func _connection_summary(entry: Dictionary) -> Dictionary:
	return {
		"semantic_id": str(entry.get("semantic_id", "")),
		"kind": str(entry.get("kind", "")),
		"display_name": str(entry.get("display_name", "")),
		"tile": entry.get("tile", [0, 0]).duplicate(),
		"target_map_id": int(entry.get("target_map_id", -1)),
		"target_map_key": str(entry.get("target_map_key", "")),
		"target_entrance_id": str(entry.get("target_entrance_id", "")),
		"target_tile": entry.get("target_tile", [0, 0]).duplicate(),
		"official_connection_id": str(
			entry.get("official_connection_id", "")
		),
	}


func _pending_count(entries: Array) -> int:
	var pending := 0
	for entry: Dictionary in entries:
		if not bool(entry.get("target_configured", false)):
			pending += 1
	return pending


func _fail(message: String) -> void:
	push_error("BICH_WOOMA_CONNECTION_FINALIZE_FAILED %s" % message)
	quit(1)
