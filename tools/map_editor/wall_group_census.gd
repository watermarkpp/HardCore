extends SceneTree

## Wall draw-load census across all released formal maps.
##
## For every map in the formal release registry this rebuilds the
## authoritative painter-order draw commands and reports the numbers that
## drive the dark-map frame cost: total commands, wall base/front commands
## (the dynamic y-sort occluder draws), y-sort domain size, instance count
## and unique texture count. Read-only. The ranked report is the user's
## manual wall-thinning working list.
## Run headless:
##   godot --headless -s tools/map_editor/wall_group_census.gd -- [map.json ...]

const REGISTRY_PATH := "res://assets/data/runtime/map_editor/map_runtime_release_registry.json"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var runtime_paths: Array[String] = []
	if args.is_empty():
		var registry: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string(REGISTRY_PATH)
		)
		for entry: Dictionary in registry.get("maps", []):
			runtime_paths.append(
				"res://assets/data/runtime/map_editor/%s.runtime.json"
				% str(entry.get("map_key", ""))
			)
	else:
		for raw: String in args:
			runtime_paths.append(raw)
	var rows: Array[Dictionary] = []
	for path: String in runtime_paths:
		var row := _census(path)
		if not row.is_empty():
			rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["commands"]) != int(b["commands"]):
			return int(a["commands"]) > int(b["commands"])
		return int(a["wall_commands"]) > int(b["wall_commands"])
	)
	var rank := 1
	for row: Dictionary in rows:
		print("WALL_LOAD_RANK rank=%d map=%s(%s) id=%s commands=%d wall_commands=%d y_sort=%d instances=%d textures=%d" % [
			rank, str(row["map_key"]), str(row["display_name"]),
			str(row["runtime_map_id"]), int(row["commands"]),
			int(row["wall_commands"]), int(row["y_sort"]),
			int(row["instances"]), int(row["textures"]),
		])
		rank += 1
	var file := FileAccess.open("outputs/wall_load_ranking.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ranking": rows}, "  ") + "\n")
		file.close()
	print("WALL_LOAD_CENSUS_DONE maps=%d" % rows.size())
	quit(0)


func _census(runtime_path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(runtime_path)
	)
	if not parsed is Dictionary:
		push_error("WALL_LOAD parse failed: %s" % runtime_path)
		return {}
	var runtime: Dictionary = parsed
	var commands := MapEditorRuntimeVisualGeometryService.sorted_draw_commands(
		runtime.get("instances", [])
	)
	var y_sort := 0
	var wall_commands := 0
	var textures := {}
	for command: Dictionary in commands:
		if str(command.get("render_domain", "")) == (
			MapEditorRuntimeVisualGeometryService.RENDER_DOMAIN_ACTOR_Y_SORT
		):
			y_sort += 1
		if MapEditorRuntimeVisualGeometryService.is_atomic_wall_pass(command):
			wall_commands += 1
		textures[str(command.get("image_path", ""))] = true
	return {
		"map_key": str(runtime.get("map_id", runtime_path.get_file())),
		"display_name": str(runtime.get("source", {}).get(
			"display_name", ""
		)),
		"runtime_map_id": str(runtime.get("source", {}).get(
			"runtime_map_id", "?"
		)),
		"commands": commands.size(),
		"wall_commands": wall_commands,
		"y_sort": y_sort,
		"instances": (runtime.get("instances", []) as Array).size(),
		"textures": textures.size(),
	}
