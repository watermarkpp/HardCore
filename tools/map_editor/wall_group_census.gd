extends SceneTree

## Authoritative wall draw-load census for every released formal map.
##
## Single-source recalculation (user request 2026-09-16 after a scripting bug
## in a side annotation): one tool, one pass, internal consistency checks.
## For every map in the formal release registry this rebuilds the
## authoritative painter-order draw commands via
## MapEditorRuntimeVisualGeometryService and reports:
##   commands      - total draw commands
##   wall_y_sort   - wall base/front commands (dynamic occluder draws)
##   wall_shadow   - wall pass-0 shadow commands (static domain)
##   static_total  - all static_background commands
##   y_sort_total  - all actor_y_sort commands (must equal wall_y_sort +
##                   non-wall y-sort commands; sum with static_total must
##                   equal commands - the script flags any violation)
##   l1/l2/l3/l4   - wall module instances per split level
##                   (l4=12 commands each: 4 parts x 3 passes, l3=9,
##                   l2=6, l1=3)
##   user_assets   - instances placed from user.* palette assets
##   textures      - distinct image paths
## Run headless:
##   godot --headless -s tools/map_editor/wall_group_census.gd

const REGISTRY_PATH := "res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
static var _level_regex: RegEx = null


func _init() -> void:
	_level_regex = RegEx.new()
	_level_regex.compile("_l(\\d)_")
	var registry: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(REGISTRY_PATH)
	)
	var rows: Array[Dictionary] = []
	for entry: Dictionary in registry.get("maps", []):
		var runtime_path := (
			"res://assets/data/runtime/map_editor/%s.runtime.json"
			% str(entry.get("map_key", ""))
		)
		var row := _census(runtime_path, entry)
		if not row.is_empty():
			rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["commands"]) != int(b["commands"]):
			return int(a["commands"]) > int(b["commands"])
		return int(a["wall_y_sort"]) > int(b["wall_y_sort"])
	)
	var rank := 1
	for row: Dictionary in rows:
		print("WALL_LOAD_RANK rank=%d id=%s map=%s(%s) commands=%d wall_y_sort=%d wall_shadow=%d instances=%d l4=%d l3=%d l2=%d l1=%d user=%d textures=%d consistency=%s" % [
			rank, str(row["runtime_map_id"]), str(row["map_key"]),
			str(row["display_name"]), int(row["commands"]),
			int(row["wall_y_sort"]), int(row["wall_shadow"]),
			int(row["instances"]), int(row["l4"]), int(row["l3"]),
			int(row["l2"]), int(row["l1"]), int(row["user_assets"]),
			int(row["textures"]), str(row["consistency"]),
		])
		rank += 1
	var file := FileAccess.open("outputs/wall_load_ranking.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ranking": rows}, "  ") + "\n")
		file.close()
	print("WALL_LOAD_CENSUS_DONE maps=%d" % rows.size())
	quit(0)


func _census(runtime_path: String, entry: Dictionary) -> Dictionary:
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
	var static_total := 0
	var y_sort_total := 0
	var wall_y_sort := 0
	var wall_shadow := 0
	var textures := {}
	var levels := {"1": 0, "2": 0, "3": 0, "4": 0}
	var user_assets := 0
	var other_assets := 0
	for command: Dictionary in commands:
		var domain := str(command.get("render_domain", ""))
		if domain == MapEditorRuntimeVisualGeometryService.RENDER_DOMAIN_ACTOR_Y_SORT:
			y_sort_total += 1
		else:
			static_total += 1
		var instance: Dictionary = command.get("instance", {})
		var asset_id := str(instance.get("asset_id", ""))
		var image_path := str(command.get("image_path", ""))
		textures[image_path] = true
		if MapEditorRuntimeVisualGeometryService.is_atomic_wall_pass(command):
			wall_y_sort += 1
		elif (
			domain == MapEditorRuntimeVisualGeometryService.RENDER_DOMAIN_STATIC_BACKGROUND
			and int(command.get("image_pass", -1)) == 0
			and str(command.get("asset", {}).get("asset_type", "")) == "wall_module"
		):
			wall_shadow += 1
	# Instance-level classification happens once per instance, not per command.
	var seen_instances := {}
	for instance: Dictionary in runtime.get("instances", []):
		var instance_id := str(instance.get("instance_id", ""))
		if instance_id.is_empty() or seen_instances.has(instance_id):
			continue
		seen_instances[instance_id] = true
		var asset_id := str(instance.get("asset_id", ""))
		if asset_id.begins_with("user."):
			user_assets += 1
			continue
		var level_match := _level_regex.search(asset_id)
		var level := str(level_match.get_string(1)) if level_match != null else ""
		if levels.has(level):
			levels[level] = int(levels[level]) + 1
		else:
			other_assets += 1
	var consistency := "OK"
	if static_total + y_sort_total != commands.size():
		consistency = "DOMAIN_SUM_MISMATCH"
	var wall_instances := (
		int(levels["4"]) + int(levels["3"]) + int(levels["2"]) + int(levels["1"])
	)
	if wall_instances > 0 and wall_y_sort == 0:
		consistency = "WALL_COMMANDS_MISSING"
	return {
		"map_key": str(runtime.get("map_id", runtime_path.get_file())),
		"display_name": str(entry.get("display_name", runtime.get(
			"source", {}
		).get("display_name", ""))),
		"runtime_map_id": str(runtime.get("source", {}).get(
			"runtime_map_id", "?"
		)),
		"commands": commands.size(),
		"wall_y_sort": wall_y_sort,
		"wall_shadow": wall_shadow,
		"static_total": static_total,
		"y_sort_total": y_sort_total,
		"instances": seen_instances.size(),
		"l4": int(levels["4"]),
		"l3": int(levels["3"]),
		"l2": int(levels["2"]),
		"l1": int(levels["1"]),
		"user_assets": user_assets,
		"other_assets": other_assets,
		"textures": textures.size(),
		"consistency": consistency,
	}
