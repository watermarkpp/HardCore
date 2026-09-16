extends SceneTree

## Wall-group census for the dark-map draw-load optimization. Loads a formal
## runtime, rebuilds the authoritative draw-command list, and reports how the
## atomic wall commands distribute over actor_sort_group roots. This measures
## the projected saving of baking each group's wall passes into one texture
## (one y-sort unit and one draw per group) without touching occlusion
## semantics. Read-only; prints WALL_GROUP_CENSUS lines.

const RUNTIME_PATHS := [
	"res://assets/data/runtime/map_editor/mengzhong_between_life_and_death.runtime.json",
	"res://assets/data/runtime/map_editor/world_bich_province.runtime.json",
]


func _init() -> void:
	for path: String in RUNTIME_PATHS:
		_census(path)
	print("WALL_GROUP_CENSUS_DONE")
	quit(0)


func _census(path: String) -> void:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(path)
	)
	if not parsed is Dictionary:
		push_error("CENSUS parse failed: %s" % path)
		return
	var runtime: Dictionary = parsed
	var map_key := str(runtime.get("map_key", path))
	var commands := MapEditorRuntimeVisualGeometryService.sorted_draw_commands(
		runtime.get("instances", [])
	)
	var domain_counts := {}
	var groups := {}
	var wall_commands := 0
	var non_wall_commands := 0
	var texture_set := {}
	for command: Dictionary in commands:
		var domain := str(command.get("render_domain", "?"))
		domain_counts[domain] = int(domain_counts.get(domain, 0)) + 1
		texture_set[str(command.get("image_path", ""))] = true
		var group_key := str(command.get("actor_sort_group", ""))
		if MapEditorRuntimeVisualGeometryService.is_atomic_wall_pass(command):
			wall_commands += 1
			if not groups.has(group_key):
				groups[group_key] = {"passes": {}, "tiles": {}, "instances": {}}
			var group: Dictionary = groups[group_key]
			var pass_key := str(command.get("image_pass", -1))
			group["passes"][pass_key] = int(group["passes"].get(pass_key, 0)) + 1
			group["instances"][str(command.get("instance", {}).get(
				"instance_id", ""
			))] = true
			group["tiles"][str(command.get("sort_tile"))] = true
		else:
			non_wall_commands += 1
	var sizes: Array = []
	var pass1_total := 0
	var pass2_total := 0
	var single_tile_groups := 0
	for group_key: String in groups:
		var group: Dictionary = groups[group_key]
		sizes.append(int(group["instances"].size()))
		pass1_total += int(group["passes"].get("1", 0))
		pass2_total += int(group["passes"].get("2", 0))
		if (group["tiles"] as Dictionary).size() == 1:
			single_tile_groups += 1
	sizes.sort()
	var half := int(sizes.size() / 2.0)
	print("WALL_GROUP_CENSUS map=%s commands=%d y_sort=%d static=%d textures=%d" % [
		map_key, commands.size(),
		int(domain_counts.get(
			MapEditorRuntimeVisualGeometryService.RENDER_DOMAIN_ACTOR_Y_SORT, 0
		)),
		int(domain_counts.get(
			MapEditorRuntimeVisualGeometryService.RENDER_DOMAIN_STATIC_BACKGROUND, 0
		)),
		texture_set.size(),
	])
	print("WALL_GROUP_CENSUS map=%s groups=%d wall_commands=%d p1=%d p2=%d single_tile_groups=%d median_group_instances=%d max_group_instances=%d" % [
		map_key, groups.size(), wall_commands, pass1_total, pass2_total,
		single_tile_groups,
		sizes[mini(half, sizes.size() - 1)] if not sizes.is_empty() else 0,
		sizes[sizes.size() - 1] if not sizes.is_empty() else 0,
	])
	print("WALL_GROUP_CENSUS map=%s projected_dynamic_draws_after_group_bake=%d (today %d)" % [
		map_key, non_wall_commands + groups.size(), commands.size(),
	])
