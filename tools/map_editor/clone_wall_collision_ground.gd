extends SceneTree

## Clone wall/collision/ground transfer between sibling formal maps.
##
## User order 2026-09-16: for mengzhong_terror_space, mengzhong_thin_sky_passage,
## mengzhong_death_coffin and mengzhong_between_life_and_death, replace their
## wall instances (terrain_base), manual collision (collision + collision_erase)
## with mengzhong_dark_area's edited sets, and mirror dark_area's ground
## deletion pattern onto their ground workspace. Everything else in each target
## document (objects, monster spawns, doors, regions, design, identity) stays
## untouched.
##
## Verified preconditions (PowerShell census, same session):
## - all five maps share design_size 32x64 and the same 6-chunk grid
## - all four target ground operation streams are byte-identical to
##   dark_area's PRE-edit stream, so replacing the stream with dark_area's
##   current operations applies exactly the user's deletions
## - instance_id namespaces are per-map inst_NNNNNN ranges, so copied wall
##   instances get remapped above the target's current maximum id
##
## Run headless:
##   godot --headless -s tools/map_editor/clone_wall_collision_ground.gd

const SOURCE_MAP := "mengzhong_dark_area"
const TARGETS := [
	"mengzhong_terror_space",
	"mengzhong_thin_sky_passage",
	"mengzhong_death_coffin",
	"mengzhong_between_life_and_death",
]
const WORKSPACE := "res://map_editor_workspace"


func _init() -> void:
	# Usage: godot --headless -s tools/map_editor/clone_wall_collision_ground.gd
	#   -- <source_map> [<target_map> ...]
	# Defaults preserved for the original dark-zone run.
	var args := OS.get_cmdline_user_args()
	var source := SOURCE_MAP
	var targets: Array = TARGETS
	if args.size() >= 1:
		source = args[0]
	if args.size() >= 2:
		targets = args.slice(1)
	var source_doc: Dictionary = _load_doc(source)
	# layers maps collection names (terrain_base, collision, ...) to arrays.
	var source_layer: Dictionary = source_doc["layers"]
	for target: String in targets:
		_apply_to_target(target, source_layer, source)
	print("CLONE_TRANSFER_DONE")
	quit(0)


func _load_doc(map_key: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"%s/%s/%s.editor.json" % [WORKSPACE, map_key, map_key]
	))
	assert(parsed != null, "parse failed for %s" % map_key)
	var doc: Dictionary = parsed[0] if parsed is Array else parsed
	return doc


func _save_doc(map_key: String, doc: Dictionary) -> void:
	# Root is the document object itself (no array wrapper).
	var path := ProjectSettings.globalize_path(
		"%s/%s/%s.editor.json" % [WORKSPACE, map_key, map_key]
	)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "cannot open %s" % path)
	file.store_string(JSON.stringify(doc, "  ") + "\n")
	file.close()


func _apply_to_target(target: String, source_layer: Dictionary, source: String) -> void:
	var doc: Dictionary = _load_doc(target)
	var layer: Dictionary = doc["layers"]
	var max_id := _max_instance_number(layer)
	var next_id := max_id + 1
	var walls: Array = []
	for instance: Dictionary in source_layer["terrain_base"]:
		var copy: Dictionary = instance.duplicate(true)
		copy["instance_id"] = "inst_%06d" % next_id
		next_id += 1
		walls.append(copy)
	var walls_before := (layer["terrain_base"] as Array).size()
	var collision_before := (layer["collision"] as Array).size()
	layer["terrain_base"] = walls
	layer["collision"] = (source_layer["collision"] as Array).duplicate(true)
	layer["collision_erase"] = (
		(source_layer["collision_erase"] as Array).duplicate(true)
	)
	if doc.has("editor_meta") and doc["editor_meta"] is Dictionary:
		var meta: Dictionary = doc["editor_meta"]
		meta["revision"] = float(int(meta.get("revision", 0.0))) + 1.0
	_save_doc(target, doc)
	_transfer_ground(target, source)
	print(
		"CLONE_TRANSFER map=%s walls %d->%d collision %d->%d erase->%d ground_stream=source_current ids=%d..%d" % [
			target, walls_before, walls.size(), collision_before,
			(source_layer["collision"] as Array).size(),
			(source_layer["collision_erase"] as Array).size(),
			max_id + 1, next_id - 1,
		]
	)
	_rebake_ground(target, doc)


func _max_instance_number(layer: Dictionary) -> int:
	var numbers: Array[int] = []
	_collect_instance_numbers(layer, numbers)
	numbers.sort()
	return numbers.back() if not numbers.is_empty() else 0


func _collect_instance_numbers(node: Variant, numbers: Array[int]) -> void:
	if node is Dictionary:
		for key: String in node:
			var value: Variant = node[key]
			if key == "instance_id" and value is String:
				var matched := RegEx.create_from_string(
					"^inst_(\\d+)$"
				).search(value)
				if matched != null:
					numbers.append(int(matched.get_string(1)))
			else:
				_collect_instance_numbers(value, numbers)
	elif node is Array:
		for item: Variant in node:
			_collect_instance_numbers(item, numbers)


func _transfer_ground(target: String, source: String) -> void:
	var source_state_path := ProjectSettings.globalize_path(
		"%s/%s/ground/ground_state.json" % [WORKSPACE, source]
	)
	var target_state_path := ProjectSettings.globalize_path(
		"%s/%s/ground/ground_state.json" % [WORKSPACE, target]
	)
	var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		source_state_path
	))
	state["map_id"] = target
	# Mark every chunk present in the source workspace dirty so the bake
	# regenerates all previews from the transferred stream.
	var dirty: Array = []
	var source_chunk_dir := DirAccess.open(ProjectSettings.globalize_path(
		"%s/%s/ground/chunks" % [WORKSPACE, source]
	))
	assert(source_chunk_dir != null, "source chunk dir missing")
	for chunk_file: String in source_chunk_dir.get_files():
		if chunk_file.ends_with(".json"):
			dirty.append(chunk_file.get_basename())
	state["dirty_chunks"] = dirty
	var file := FileAccess.open(target_state_path, FileAccess.WRITE)
	assert(file != null, "cannot open %s" % target_state_path)
	file.store_string(JSON.stringify(state, "  ") + "\n")
	file.close()
	var target_chunk_dir := DirAccess.open(ProjectSettings.globalize_path(
		"%s/%s/ground/chunks" % [WORKSPACE, target]
	))
	assert(target_chunk_dir != null, "target chunk dir missing")
	for chunk_file: String in source_chunk_dir.get_files():
		if not chunk_file.ends_with(".json"):
			continue
		var content := FileAccess.get_file_as_string(
			source_chunk_dir.get_current_dir() + "/" + chunk_file
		)
		var out := FileAccess.open(
			target_chunk_dir.get_current_dir() + "/" + chunk_file,
			FileAccess.WRITE
		)
		assert(out != null, "cannot write chunk %s" % chunk_file)
		out.store_string(content)
		out.close()


func _rebake_ground(target: String, doc: Dictionary) -> void:
	var result: Dictionary = MapEditorChunkBakeService.bake_dirty_chunks(doc)
	assert(
		bool(result.get("ok", false)),
		"bake failed for %s: %s" % [target, str(result.get("errors", []))]
	)
	print(
		"CLONE_BAKE map=%s baked_chunks=%s" % [
			target, str(result.get("baked_chunks", [])),
		]
	)
