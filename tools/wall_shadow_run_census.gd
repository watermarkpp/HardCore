extends SceneTree
## One-off census: static command sequence structure for wall-plan design.
## Prints the run structure of pass-0 wall shadows among static commands.

func _init() -> void:
	var service := load(
		"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
	)
	for map_key: String in ["mengzhong_dark_area", "chiyue_valley"]:
		var runtime_path := (
			"res://assets/data/runtime/map_editor/%s.runtime.json" % map_key
		)
		var raw := _read_json(runtime_path)
		if raw.is_empty():
			print("CENSUS missing runtime: ", map_key)
			continue
		var instances: Array = raw.get("instances", [])
		var commands: Array = service.sorted_draw_commands(instances)
		var statics := 0
		var shadows := 0
		var runs := 0
		var in_run := false
		var non_shadow_static_between := 0
		for command: Dictionary in commands:
			var domain := str(command.get("render_domain", ""))
			if domain != service.RENDER_DOMAIN_STATIC_BACKGROUND:
				in_run = false
				continue
			statics += 1
			var is_shadow := (
				str(command.get("asset", {}).get("asset_type", ""))
				== "wall_module"
				and int(command.get("image_pass", -1)) == 0
			)
			if is_shadow:
				shadows += 1
				if not in_run:
					runs += 1
					in_run = true
			else:
				if in_run:
					non_shadow_static_between += 1
				in_run = false
		print(
			"CENSUS %s commands=%d statics=%d shadows=%d shadow_runs=%d interleave_points=%d" % [
				map_key, commands.size(), statics, shadows, runs,
				non_shadow_static_between,
			]
		)
		var groups := {}
		for command: Dictionary in commands:
			var group_key := str(command.get("actor_sort_group", ""))
			if group_key.is_empty():
				continue
			if not groups.has(group_key):
				groups[group_key] = {"pass1": 0, "pass2": 0}
			if int(command.get("image_pass", -1)) == 1:
				groups[group_key]["pass1"] += 1
			elif int(command.get("image_pass", -1)) == 2:
				groups[group_key]["pass2"] += 1
		var single := 0
		var multi := 0
		for group_key: String in groups:
			var layers: int = groups[group_key]["pass1"] + groups[group_key]["pass2"]
			if layers == 1:
				single += 1
			else:
				multi += 1
		print(
			"CENSUS %s dynamic_groups=%d single_layer=%d multi_layer=%d" % [
				map_key, groups.size(), single, multi,
			]
		)
	quit(0)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
