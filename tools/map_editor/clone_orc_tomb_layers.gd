extends SceneTree

const SOURCE_MAP_ID := "orc_tomb_1"
const SOURCE_DOCUMENT_PATH := "res://map_editor_workspace/orc_tomb_1/orc_tomb_1.editor.json"
const SOURCE_GROUND_PATH := "res://map_editor_workspace/orc_tomb_1/ground"
const SOURCE_STRUCTURE_ID := "orc_tomb_1.hui_ring.v1"
const TARGETS := [
	{
		"map_id": "orc_tomb_2",
		"runtime_map_id": 218,
		"display_name": "兽人古墓二层",
		"target_map_id": "orc_tomb_3",
	},
	{
		"map_id": "orc_tomb_3",
		"runtime_map_id": 221,
		"display_name": "兽人古墓三层",
		"target_map_id": "",
	},
]


func _init() -> void:
	var loaded := MapEditorLoadService.load_document(SOURCE_DOCUMENT_PATH)
	if not bool(loaded.get("ok", false)):
		_fail("source_load_failed:%s" % loaded.get("errors", []))
		return
	var source: Dictionary = loaded.document
	if str(source.get("map_id", "")) != SOURCE_MAP_ID:
		_fail("unexpected_source_map_id")
		return
	var design_size: Array = source.get("design", {}).get("design_size", [])
	if design_size.size() != 2 or Vector2i(int(design_size[0]), int(design_size[1])) != Vector2i(38, 38):
		_fail("unexpected_source_design_size:%s" % [design_size])
		return
	var entrances: Array = source.get("layers", {}).get("map_entrance_points", [])
	var exits: Array = source.get("layers", {}).get("map_exit_points", [])
	if entrances.size() != 1 or exits.size() != 1:
		_fail("source_requires_exactly_one_entrance_and_exit")
		return
	var entrance_id := str(entrances[0].get("entrance_id", entrances[0].get("semantic_id", "")))
	if entrance_id.is_empty():
		_fail("source_entrance_id_missing")
		return
	for target: Dictionary in TARGETS:
		var target_map_id := str(target.map_id)
		var target_document_path := MapEditorSaveService.default_path(target_map_id)
		if FileAccess.file_exists(target_document_path):
			var existing := MapEditorLoadService.load_document(target_document_path)
			if (
				not bool(existing.get("ok", false))
				or str(existing.document.get("editor_meta", {}).get("clone_source_map_id", "")) != SOURCE_MAP_ID
			):
				_fail("target_exists_but_is_not_this_clone:%s" % target_map_id)
				return
		elif DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path("res://map_editor_workspace/%s" % target_map_id)
		):
			_fail("target_directory_exists_without_document:%s" % target_map_id)
			return

	var clones: Array[Dictionary] = []
	for target: Dictionary in TARGETS:
		var clone := _clone_document(source, target, entrance_id)
		var validation_errors := MapEditorTypes.validate_document(clone)
		if not validation_errors.is_empty():
			_fail("clone_validation_failed:%s:%s" % [target.map_id, validation_errors])
			return
		clones.append(clone)

	for clone: Dictionary in clones:
		var target_map_id := str(clone.map_id)
		var target_ground_path := "res://map_editor_workspace/%s/ground" % target_map_id
		var copied := _copy_ground_tree(SOURCE_GROUND_PATH, target_ground_path, target_map_id)
		if not copied:
			return
		var saved := MapEditorSaveService.save_document(clone)
		if not bool(saved.get("ok", false)):
			_fail("target_save_failed:%s:%s" % [target_map_id, saved.get("errors", [])])
			return
		# A second atomic save gives every new editable map the same valid current
		# document and automatic backup from the moment it is first opened.
		saved = MapEditorSaveService.save_document(clone)
		if not bool(saved.get("ok", false)):
			_fail("target_backup_failed:%s:%s" % [target_map_id, saved.get("errors", [])])
			return

	var source_exit: Dictionary = exits[0]
	source_exit["target_map_id"] = "orc_tomb_2"
	source_exit["target_entrance_id"] = entrance_id
	exits[0] = source_exit
	source.layers["map_exit_points"] = exits
	source.editor_meta["revision"] = int(source.editor_meta.get("revision", 1)) + 1
	source.editor_meta["connection_milestone"] = "ORC-TOMB-1-TO-2-V1"
	var source_saved := MapEditorSaveService.save_document(source, SOURCE_DOCUMENT_PATH)
	if not bool(source_saved.get("ok", false)):
		_fail("source_connection_save_failed:%s" % source_saved.get("errors", []))
		return
	source_saved = MapEditorSaveService.save_document(source, SOURCE_DOCUMENT_PATH)
	if not bool(source_saved.get("ok", false)):
		_fail("source_connection_backup_failed:%s" % source_saved.get("errors", []))
		return

	for map_id: String in [SOURCE_MAP_ID, "orc_tomb_2", "orc_tomb_3"]:
		var verified := MapEditorLoadService.load_document(MapEditorSaveService.default_path(map_id))
		if not bool(verified.get("ok", false)):
			_fail("post_save_load_failed:%s:%s" % [map_id, verified.get("errors", [])])
			return
	print(
		(
			"ORC_TOMB_LAYER_CLONE_PASS source=%s targets=orc_tomb_2,orc_tomb_3 "
			+ "size=38x38 entrance=%s links=orc_tomb_1->orc_tomb_2,orc_tomb_2->orc_tomb_3"
		)
		% [SOURCE_MAP_ID, entrance_id]
	)
	quit(0)


func _clone_document(source: Dictionary, target: Dictionary, entrance_id: String) -> Dictionary:
	var target_map_id := str(target.map_id)
	var clone: Dictionary = source.duplicate(true)
	clone["map_id"] = target_map_id
	clone["runtime_map_id"] = int(target.runtime_map_id)
	clone["display_name"] = str(target.display_name)
	clone["ground"] = _replace_map_paths(clone.get("ground", {}), target_map_id)
	clone["source_reference"] = {
		"audit_status": "derived_editor_clone",
		"coordinate_system": "mir2_48x32",
		"source_map_path": source.get("source_reference", {}).get("source_map_path", null),
		"clone_source_map_id": SOURCE_MAP_ID,
		"clone_source_document": SOURCE_DOCUMENT_PATH,
	}
	var target_structure_id := "%s.hui_ring.v1" % target_map_id
	var design: Dictionary = clone.get("design", {})
	if design.has("dungeon_structure"):
		var structure: Dictionary = design.dungeon_structure
		structure["structure_id"] = target_structure_id
		structure["cloned_from_structure_id"] = SOURCE_STRUCTURE_ID
		design["dungeon_structure"] = structure
	clone["design"] = design
	var layers: Dictionary = clone.get("layers", {})
	for layer_name: String in layers:
		var entries: Array = layers[layer_name]
		for index in entries.size():
			var entry: Dictionary = entries[index]
			if str(entry.get("structure_id", "")) == SOURCE_STRUCTURE_ID:
				entry["structure_id"] = target_structure_id
				entry["cloned_from_structure_id"] = SOURCE_STRUCTURE_ID
				entries[index] = entry
		layers[layer_name] = entries
	var target_exits: Array = layers.get("map_exit_points", [])
	var target_exit: Dictionary = target_exits[0]
	target_exit["target_map_id"] = str(target.target_map_id)
	target_exit["target_entrance_id"] = entrance_id if not str(target.target_map_id).is_empty() else ""
	target_exits[0] = target_exit
	layers["map_exit_points"] = target_exits
	clone["layers"] = layers
	var editor_meta: Dictionary = clone.get("editor_meta", {})
	editor_meta["blank_template_id"] = "blank.%s" % target_map_id
	editor_meta["workspace"] = "res://map_editor_workspace/%s" % target_map_id
	editor_meta["template_kind"] = "cloned_map"
	editor_meta["content_policy"] = "full_copy_from_orc_tomb_1"
	editor_meta["clone_source_map_id"] = SOURCE_MAP_ID
	editor_meta["clone_source_revision"] = int(source.get("editor_meta", {}).get("revision", 1))
	editor_meta["clone_size_policy"] = "exact_source_copy_38x38"
	editor_meta["revision"] = 1
	editor_meta["structure_id"] = target_structure_id
	editor_meta["milestone"] = "%s-CLONE-FROM-1-V1" % target_map_id.to_upper()
	clone["editor_meta"] = editor_meta
	return clone


func _replace_map_paths(value: Variant, target_map_id: String) -> Variant:
	if value is Dictionary:
		var replaced := {}
		for key: Variant in value:
			replaced[key] = _replace_map_paths(value[key], target_map_id)
		return replaced
	if value is Array:
		var replaced: Array = []
		for item: Variant in value:
			replaced.append(_replace_map_paths(item, target_map_id))
		return replaced
	if value is String:
		return str(value).replace(SOURCE_MAP_ID, target_map_id)
	return value


func _copy_ground_tree(source_path: String, target_path: String, target_map_id: String) -> bool:
	var source_absolute := ProjectSettings.globalize_path(source_path)
	var target_absolute := ProjectSettings.globalize_path(target_path)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(target_absolute)
	if mkdir_error != OK:
		_fail("ground_mkdir_failed:%s:%d" % [target_map_id, mkdir_error])
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
				if not _copy_ground_tree(source_entry, target_entry, target_map_id):
					directory.list_dir_end()
					return false
			elif entry_name.get_extension().to_lower() == "json":
				var input := FileAccess.open(source_entry, FileAccess.READ)
				if input == null:
					_fail("ground_json_read_failed:%s" % source_entry)
					directory.list_dir_end()
					return false
				var rewritten := input.get_as_text().replace(SOURCE_MAP_ID, target_map_id)
				input.close()
				var output := FileAccess.open(target_entry, FileAccess.WRITE)
				if output == null:
					_fail("ground_json_write_failed:%s" % target_entry)
					directory.list_dir_end()
					return false
				output.store_string(rewritten)
				output.close()
			else:
				var copy_error := DirAccess.copy_absolute(source_entry, target_entry)
				if copy_error != OK:
					_fail("ground_file_copy_failed:%s:%d" % [source_entry, copy_error])
					directory.list_dir_end()
					return false
		entry_name = directory.get_next()
	directory.list_dir_end()
	return true


func _fail(message: String) -> void:
	push_error("ORC_TOMB_LAYER_CLONE_FAILED %s" % message)
	quit(1)
