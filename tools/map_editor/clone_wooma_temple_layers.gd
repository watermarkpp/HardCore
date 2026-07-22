extends SceneTree

const ROUTE_VERSION_ID := "wooma_temple_user_route_v1"
const FOREST_MAP_ID := "wooma_forest"
const SOURCE_MAP_ID := "wooma_temple_1"
const FOREST_DOCUMENT_PATH := (
	"res://map_editor_workspace/wooma_forest/wooma_forest.editor.json"
)
const SOURCE_DOCUMENT_PATH := (
	"res://map_editor_workspace/wooma_temple_1/wooma_temple_1.editor.json"
)
const SOURCE_GROUND_PATH := "res://map_editor_workspace/wooma_temple_1/ground"
const ROUTE_MARKER_PATH := (
	"res://assets/data/runtime/map_editor/"
	+ "wooma_temple_route.manual_ready.json"
)
const TARGETS := [
	{
		"map_id": "wooma_temple_2",
		"runtime_map_id": 314,
		"display_name": "沃玛寺庙二层",
		"target_map_id": "wooma_temple_3",
		"target_runtime_map_id": 315,
		"exit_display_name": "进入沃玛教主大厅",
	},
	{
		"map_id": "wooma_temple_3",
		"runtime_map_id": 315,
		"display_name": "沃玛教主大厅",
		"target_map_id": "",
		"target_runtime_map_id": -1,
		"exit_display_name": "",
	},
]


func _init() -> void:
	var forest := _load_document(FOREST_DOCUMENT_PATH)
	var source := _load_document(SOURCE_DOCUMENT_PATH)
	if forest.is_empty() or source.is_empty():
		return
	if str(forest.get("map_id", "")) != FOREST_MAP_ID:
		_fail("unexpected_forest_map_id")
		return
	if str(source.get("map_id", "")) != SOURCE_MAP_ID:
		_fail("unexpected_source_map_id")
		return
	var design_size := _design_size(source)
	if design_size != Vector2i(44, 44):
		_fail("unexpected_source_design_size:%s" % design_size)
		return
	var source_entrances: Array = source.layers.get(
		"map_entrance_points", []
	)
	var source_exits: Array = source.layers.get("map_exit_points", [])
	if source_entrances.size() != 1 or source_exits.size() != 1:
		_fail("source_requires_exactly_one_entrance_and_exit")
		return
	var forest_exit := _topmost_exit(
		forest.layers.get("map_exit_points", [])
	)
	if forest_exit.is_empty():
		_fail("forest_top_exit_missing")
		return
	if _tile(forest_exit) != Vector2i(51, 4):
		_fail("forest_top_exit_moved:%s" % _tile(forest_exit))
		return
	var entrance_id := str(
		source_entrances[0].get(
			"entrance_id",
			source_entrances[0].get("semantic_id", "")
		)
	)
	if entrance_id.is_empty():
		_fail("source_entrance_id_missing")
		return

	for target: Dictionary in TARGETS:
		var target_map_id := str(target.map_id)
		var target_path := MapEditorSaveService.default_path(target_map_id)
		if FileAccess.file_exists(target_path):
			var existing := _load_document(target_path)
			if (
				existing.is_empty()
				or str(
					existing.get("editor_meta", {}).get(
						"clone_source_map_id", ""
					)
				) != SOURCE_MAP_ID
			):
				_fail(
					"target_exists_but_is_not_managed_clone:%s"
					% target_map_id
				)
				return

	var clones: Array[Dictionary] = []
	for target: Dictionary in TARGETS:
		var clone := _clone_document(source, target, entrance_id)
		var errors := MapEditorTypes.validate_document(clone)
		if not errors.is_empty():
			_fail(
				"clone_validation_failed:%s:%s"
				% [target.map_id, errors]
			)
			return
		clones.append(clone)

	for clone: Dictionary in clones:
		var target_map_id := str(clone.map_id)
		if not _copy_ground_tree(
			SOURCE_GROUND_PATH,
			"res://map_editor_workspace/%s/ground" % target_map_id,
			target_map_id
		):
			return

	var floor_two: Dictionary = clones[0]
	var leader_hall: Dictionary = clones[1]
	var floor_one_entrance: Dictionary = source_entrances[0]
	var floor_two_entrance: Dictionary = (
		floor_two.layers.map_entrance_points[0]
	)
	var leader_entrance: Dictionary = (
		leader_hall.layers.map_entrance_points[0]
	)
	_configure_entrance(
		floor_one_entrance,
		"沃玛寺庙一层入口"
	)
	_configure_entrance(
		floor_two_entrance,
		"沃玛寺庙二层入口"
	)
	_configure_entrance(
		leader_entrance,
		"沃玛教主大厅入口"
	)
	_configure_exit(
		forest_exit,
		"进入沃玛寺庙一层",
		313,
		SOURCE_MAP_ID,
		floor_one_entrance,
		"wooma_forest_top_to_temple_1_v1"
	)
	_configure_exit(
		source_exits[0],
		"前往沃玛寺庙二层",
		314,
		"wooma_temple_2",
		floor_two_entrance,
		"wooma_temple_1_to_2_v1"
	)

	_mark_route_document(
		forest,
		"WOOMA-FOREST-TO-TEMPLE-1-V1"
	)
	_mark_route_document(
		source,
		"WOOMA-TEMPLE-1-TO-2-V1"
	)
	_mark_route_document(
		floor_two,
		"WOOMA-TEMPLE-2-TO-LEADER-HALL-V1"
	)
	_mark_route_document(
		leader_hall,
		"WOOMA-LEADER-HALL-CLONE-V1"
	)

	var documents: Array[Dictionary] = [
		forest,
		source,
		floor_two,
		leader_hall,
	]
	var document_paths := {
		FOREST_MAP_ID: FOREST_DOCUMENT_PATH,
		SOURCE_MAP_ID: SOURCE_DOCUMENT_PATH,
	}
	var runtimes := {}
	for document: Dictionary in documents:
		var map_id := str(document.map_id)
		var path := str(
			document_paths.get(
				map_id,
				MapEditorSaveService.default_path(map_id)
			)
		)
		var runtime := _save_approve_and_build(document, path)
		if runtime.is_empty():
			return
		runtimes[map_id] = runtime

	if not _write_route_marker(
		forest,
		source,
		floor_two,
		leader_hall,
		runtimes
	):
		return
	print(
		"WOOMA_TEMPLE_LAYER_CLONE_PASS "
		+ "source=wooma_temple_1 targets=wooma_temple_2,wooma_temple_3 "
		+ "size=44x44 route=wooma_forest->wooma_temple_1"
		+ "->wooma_temple_2->wooma_temple_3"
	)
	quit(0)


func _clone_document(
	source: Dictionary,
	target: Dictionary,
	entrance_id: String
) -> Dictionary:
	var target_map_id := str(target.map_id)
	var clone: Dictionary = source.duplicate(true)
	clone["map_id"] = target_map_id
	clone["runtime_map_id"] = int(target.runtime_map_id)
	clone["display_name"] = str(target.display_name)
	clone["ground"] = _replace_map_paths(
		clone.get("ground", {}),
		target_map_id
	)
	clone["source_reference"] = {
		"audit_status": "derived_editor_clone",
		"coordinate_system": "mir2_48x32",
		"source_map_path": source.get(
			"source_reference", {}
		).get("source_map_path", null),
		"clone_source_map_id": SOURCE_MAP_ID,
		"clone_source_document": SOURCE_DOCUMENT_PATH,
	}
	var layers: Dictionary = clone.get("layers", {})
	var entrances: Array = layers.get("map_entrance_points", [])
	var entrance: Dictionary = entrances[0]
	entrance["display_name"] = (
		"沃玛寺庙二层入口"
		if target_map_id == "wooma_temple_2"
		else "沃玛教主大厅入口"
	)
	entrances[0] = entrance
	layers["map_entrance_points"] = entrances
	if str(target.target_map_id).is_empty():
		layers["map_exit_points"] = []
	else:
		var exits: Array = layers.get("map_exit_points", [])
		var map_exit: Dictionary = exits[0]
		_configure_exit(
			map_exit,
			str(target.exit_display_name),
			int(target.target_runtime_map_id),
			str(target.target_map_id),
			entrance,
			"wooma_temple_2_to_leader_hall_v1"
		)
		map_exit["target_entrance_id"] = entrance_id
		exits[0] = map_exit
		layers["map_exit_points"] = exits
	clone["layers"] = layers
	var editor_meta: Dictionary = clone.get("editor_meta", {})
	editor_meta["blank_template_id"] = "blank.%s" % target_map_id
	editor_meta["workspace"] = (
		"res://map_editor_workspace/%s" % target_map_id
	)
	editor_meta["template_kind"] = "cloned_map"
	editor_meta["content_policy"] = (
		"full_copy_from_wooma_temple_1"
	)
	editor_meta["clone_source_map_id"] = SOURCE_MAP_ID
	editor_meta["clone_source_revision"] = int(
		source.get("editor_meta", {}).get("revision", 1)
	)
	editor_meta["clone_size_policy"] = "exact_source_copy_44x44"
	editor_meta["revision"] = 1
	editor_meta["milestone"] = (
		"%s-CLONE-FROM-1-V1" % target_map_id.to_upper()
	)
	editor_meta.erase("runtime_approved")
	editor_meta.erase("runtime_approved_revision")
	clone["editor_meta"] = editor_meta
	return clone


func _configure_entrance(
	entrance: Dictionary,
	display_name: String
) -> void:
	entrance["display_name"] = display_name
	entrance["is_default"] = true
	entrance["runtime_export"] = true


func _configure_exit(
	map_exit: Dictionary,
	display_name: String,
	target_runtime_map_id: int,
	target_map_key: String,
	target_entrance: Dictionary,
	connection_id: String
) -> void:
	map_exit.erase("radius_tiles")
	map_exit["display_name"] = display_name
	map_exit["target_configured"] = true
	map_exit["target_map_id"] = target_runtime_map_id
	map_exit["target_map_key"] = target_map_key
	map_exit["target_entrance_id"] = str(
		target_entrance.get(
			"entrance_id",
			target_entrance.get("semantic_id", "")
		)
	)
	map_exit["target_tile"] = (
		target_entrance.get("tile", [0, 0]).duplicate()
	)
	map_exit["official_connection_id"] = connection_id


func _mark_route_document(
	document: Dictionary,
	milestone: String
) -> void:
	var meta: Dictionary = document.get("editor_meta", {})
	if str(meta.get("route_version_id", "")) != ROUTE_VERSION_ID:
		meta["revision"] = int(meta.get("revision", 1)) + 1
	meta["route_version_id"] = ROUTE_VERSION_ID
	meta["milestone"] = milestone
	meta["official_source_authority"] = "user_saved_editor_document"
	document["editor_meta"] = meta


func _save_approve_and_build(
	document: Dictionary,
	path: String
) -> Dictionary:
	var bake := MapEditorChunkBakeService.bake_dirty_chunks(document)
	if not bool(bake.get("ok", false)):
		_fail(
			"%s_bake_failed:%s"
			% [document.map_id, bake.get("errors", [])]
		)
		return {}
	var approval := MapEditorBuildRuntimeService.approve_for_runtime(
		document
	)
	if not bool(approval.get("ok", false)):
		_fail(
			"%s_approval_failed:%s"
			% [document.map_id, approval.get("errors", [])]
		)
		return {}
	var saved := MapEditorSaveService.save_document(document, path)
	if not bool(saved.get("ok", false)):
		_fail(
			"%s_save_failed:%s"
			% [document.map_id, saved.get("errors", [])]
		)
		return {}
	if str(document.map_id) in ["wooma_temple_2", "wooma_temple_3"]:
		saved = MapEditorSaveService.save_document(document, path)
		if not bool(saved.get("ok", false)):
			_fail(
				"%s_backup_failed:%s"
				% [document.map_id, saved.get("errors", [])]
			)
			return {}
	var built := MapEditorBuildRuntimeService.build(document)
	if not bool(built.get("ok", false)):
		_fail(
			"%s_build_failed:%s"
			% [document.map_id, built.get("errors", [])]
		)
		return {}
	return built.runtime


func _write_route_marker(
	forest: Dictionary,
	floor_one: Dictionary,
	floor_two: Dictionary,
	leader_hall: Dictionary,
	runtimes: Dictionary
) -> bool:
	var marker := {
		"schema_version": 1,
		"route_version_id": ROUTE_VERSION_ID,
		"status": "user_requested_official_route",
		"source_authority": "user_saved_editor_documents",
		"maps": [
			_map_summary(forest, runtimes[FOREST_MAP_ID]),
			_map_summary(floor_one, runtimes[SOURCE_MAP_ID]),
			_map_summary(floor_two, runtimes["wooma_temple_2"]),
			_map_summary(
				leader_hall,
				runtimes["wooma_temple_3"]
			),
		],
		"connections": [
			_connection_summary(
				forest,
				forest.layers.map_exit_points[0]
			),
			_connection_summary(
				floor_one,
				floor_one.layers.map_exit_points[0]
			),
			_connection_summary(
				floor_two,
				floor_two.layers.map_exit_points[0]
			),
		],
	}
	var write := MapEditorGroundService._write_json_atomic(
		ROUTE_MARKER_PATH,
		marker
	)
	if not bool(write.get("ok", false)):
		_fail("route_marker_failed:%s" % write.get("errors", []))
		return false
	return true


func _map_summary(
	document: Dictionary,
	runtime: Dictionary
) -> Dictionary:
	return {
		"map_id": str(document.map_id),
		"runtime_map_id": int(document.runtime_map_id),
		"display_name": str(document.display_name),
		"design_size": document.design.design_size.duplicate(),
		"runtime_build_sha256": str(runtime.build_sha256),
	}


func _connection_summary(
	document: Dictionary,
	map_exit: Dictionary
) -> Dictionary:
	return {
		"source_map_id": str(document.map_id),
		"source_runtime_map_id": int(document.runtime_map_id),
		"exit_id": str(map_exit.semantic_id),
		"exit_tile": map_exit.tile.duplicate(),
		"target_map_id": int(map_exit.target_map_id),
		"target_map_key": str(map_exit.target_map_key),
		"target_entrance_id": str(map_exit.target_entrance_id),
		"target_tile": map_exit.target_tile.duplicate(),
		"official_connection_id": str(
			map_exit.official_connection_id
		),
	}


func _topmost_exit(entries: Array) -> Dictionary:
	var result: Dictionary = {}
	for entry: Dictionary in entries:
		if result.is_empty() or _tile(entry).y < _tile(result).y:
			result = entry
	return result


func _tile(entry: Dictionary) -> Vector2i:
	var raw: Array = entry.get("tile", [0, 0])
	return Vector2i(int(raw[0]), int(raw[1]))


func _design_size(document: Dictionary) -> Vector2i:
	var raw: Array = document.get("design", {}).get(
		"design_size", [0, 0]
	)
	return Vector2i(int(raw[0]), int(raw[1]))


func _load_document(path: String) -> Dictionary:
	var loaded := MapEditorLoadService.load_document(path)
	if not bool(loaded.get("ok", false)):
		_fail("load_failed:%s:%s" % [path, loaded.get("errors", [])])
		return {}
	return loaded.document


func _replace_map_paths(
	value: Variant,
	target_map_id: String
) -> Variant:
	if value is Dictionary:
		var replaced := {}
		for key: Variant in value:
			replaced[key] = _replace_map_paths(
				value[key],
				target_map_id
			)
		return replaced
	if value is Array:
		var replaced: Array = []
		for item: Variant in value:
			replaced.append(
				_replace_map_paths(item, target_map_id)
			)
		return replaced
	if value is String:
		return str(value).replace(SOURCE_MAP_ID, target_map_id)
	return value


func _copy_ground_tree(
	source_path: String,
	target_path: String,
	target_map_id: String
) -> bool:
	var source_absolute := ProjectSettings.globalize_path(source_path)
	var target_absolute := ProjectSettings.globalize_path(target_path)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(
		target_absolute
	)
	if mkdir_error != OK:
		_fail(
			"ground_mkdir_failed:%s:%d"
			% [target_map_id, mkdir_error]
		)
		return false
	var directory := DirAccess.open(source_absolute)
	if directory == null:
		_fail("ground_source_open_failed:%s" % source_absolute)
		return false
	directory.list_dir_begin()
	var entry_name := directory.get_next()
	while not entry_name.is_empty():
		if entry_name != "." and entry_name != "..":
			var source_entry := source_absolute.path_join(entry_name)
			var target_entry := target_absolute.path_join(entry_name)
			if directory.current_is_dir():
				if not _copy_ground_tree(
					source_entry,
					target_entry,
					target_map_id
				):
					directory.list_dir_end()
					return false
			elif entry_name.get_extension().to_lower() == "json":
				var input := FileAccess.open(
					source_entry,
					FileAccess.READ
				)
				if input == null:
					_fail(
						"ground_json_read_failed:%s"
						% source_entry
					)
					directory.list_dir_end()
					return false
				var rewritten := input.get_as_text().replace(
					SOURCE_MAP_ID,
					target_map_id
				)
				input.close()
				var output := FileAccess.open(
					target_entry,
					FileAccess.WRITE
				)
				if output == null:
					_fail(
						"ground_json_write_failed:%s"
						% target_entry
					)
					directory.list_dir_end()
					return false
				output.store_string(rewritten)
				output.close()
			else:
				var copy_error := DirAccess.copy_absolute(
					source_entry,
					target_entry
				)
				if copy_error != OK:
					_fail(
						"ground_file_copy_failed:%s:%d"
						% [source_entry, copy_error]
					)
					directory.list_dir_end()
					return false
		entry_name = directory.get_next()
	directory.list_dir_end()
	return true


func _fail(message: String) -> void:
	push_error("WOOMA_TEMPLE_LAYER_CLONE_FAILED %s" % message)
	quit(1)
