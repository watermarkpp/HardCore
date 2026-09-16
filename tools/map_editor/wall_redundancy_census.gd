extends SceneTree

## Wall redundancy census (read-only, data level).
##
## User ruling 2026-09-16: the dark-map frame cost is handled at the CONTENT
## level - the user manually removes surplus wall modules in the editor and
## keeps collision placeholders. The renderer and the map system stay
## untouched. This tool gives that manual edit a scientific basis: for one
## formal map runtime it rebuilds the authoritative painter order, rasterizes
## every command's opaque pixels into a world coverage grid in REVERSE paint
## order, and classifies each wall instance:
##   redundant  - every opaque pixel of the instance's wall passes is already
##                covered by pixels painted after it: the instance can never
##                contribute a visible pixel, so removing it cannot change the
##                picture or the occlusion order;
##   partial    - at least half of the opaque pixels are covered;
##   essential  - contributes visible pixels.
## Coverage includes every command (walls, props, terrain fronts), so terrain
## and decorations that legitimately cover wall pixels are respected.
## Run headless:
##   godot --headless -s tools/map_editor/wall_redundancy_census.gd -- \
##       res://assets/data/runtime/map_editor/<map>.runtime.json [more...]

const ALPHA_THRESHOLD := 0.05
const SAMPLE_STEP_PX := 2.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = [
			"res://assets/data/runtime/map_editor/mengzhong_between_life_and_death.runtime.json",
			"res://assets/data/runtime/map_editor/mengzhong_dark_area.runtime.json",
		]
	for path: String in args:
		_census(path)
	print("RENDER_REDUNDANCY_DONE")
	quit(0)


func _census(runtime_path: String) -> void:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(runtime_path)
	)
	if not parsed is Dictionary:
		push_error("RENDER_REDUNDANCY parse failed: %s" % runtime_path)
		return
	var runtime: Dictionary = parsed
	var map_key := str(runtime.get("map_id", runtime_path.get_file()))
	var design_raw: Array = runtime.design.get("design_size", [64, 64])
	var design_size := Vector2i(int(design_raw[0]), int(design_raw[1]))
	var commands := MapEditorRuntimeVisualGeometryService.sorted_draw_commands(
		runtime.get("instances", [])
	)
	var image_cache := {}
	var tex_sizes: Array[Vector2i] = []
	tex_sizes.resize(commands.size())
	var world_rects: Array[Rect2i] = []
	world_rects.resize(commands.size())
	var bounds := Rect2i()
	var bounds_ready := false
	var load_failures := 0
	for prepare_index in commands.size():
		var prepare_command: Dictionary = commands[prepare_index]
		var image := _load_image(prepare_command, image_cache)
		if image == null:
			load_failures += 1
			tex_sizes[prepare_index] = Vector2i.ZERO
			world_rects[prepare_index] = Rect2i()
			continue
		var tex_size := Vector2i(image.get_width(), image.get_height())
		tex_sizes[prepare_index] = tex_size
		var rect := _command_world_rect(prepare_command, design_size, tex_size)
		world_rects[prepare_index] = rect
		if not bounds_ready:
			bounds = rect
			bounds_ready = true
		else:
			bounds = bounds.merge(rect)
	if not bounds_ready:
		print("RENDER_REDUNDANCY map=%s ERROR=no_rasterizable_commands" % map_key)
		return
	var origin := Vector2i(bounds.position) - Vector2i(64, 64)
	var grid_size := Vector2i(bounds.size) + Vector2i(128, 128)
	var coverage := PackedByteArray()
	coverage.resize(int(grid_size.x) * int(grid_size.y))
	var opaque_counts: Array[int] = []
	opaque_counts.resize(commands.size())
	var covered_counts: Array[int] = []
	covered_counts.resize(commands.size())
	var scan_index := commands.size() - 1
	while scan_index >= 0:
		if tex_sizes[scan_index] == Vector2i.ZERO:
			scan_index -= 1
			continue
		var scan_command: Dictionary = commands[scan_index]
		var opaque := _opaque_world_pixels(
			scan_command, design_size, tex_sizes[scan_index],
			world_rects[scan_index], origin, grid_size, image_cache
		)
		opaque_counts[scan_index] = opaque.size()
		var covered := 0
		for pixel: Vector2i in opaque:
			if coverage[pixel.y * grid_size.x + pixel.x] == 1:
				covered += 1
		covered_counts[scan_index] = covered
		for pixel: Vector2i in opaque:
			coverage[pixel.y * grid_size.x + pixel.x] = 1
		scan_index -= 1
	var instance_stats := {}
	for summarize_index in commands.size():
		var instance: Dictionary = commands[summarize_index].get(
			"instance", {}
		)
		var instance_id := str(instance.get("instance_id", ""))
		if instance_id.is_empty():
			continue
		if not instance_stats.has(instance_id):
			instance_stats[instance_id] = {
				"opaque": 0,
				"covered": 0,
				"name": str(instance.get("display_name", "")),
				"asset": str(instance.get("asset_id", "")),
				"tile": str(instance.get("tile", "")),
			}
		var stats: Dictionary = instance_stats[instance_id]
		stats["opaque"] = int(stats["opaque"]) + opaque_counts[summarize_index]
		stats["covered"] = int(stats["covered"]) + covered_counts[summarize_index]
	var redundant := 0
	var partial := 0
	var essential := 0
	var transparent_only := 0
	var ranked_report := []
	for instance_id: String in instance_stats:
		var stats: Dictionary = instance_stats[instance_id]
		var opaque := int(stats["opaque"])
		if opaque == 0:
			transparent_only += 1
			continue
		var ratio := float(stats["covered"]) / float(opaque)
		ranked_report.append({
			"instance_id": instance_id,
			"display_name": stats["name"],
			"asset_id": stats["asset"],
			"tile": stats["tile"],
			"covered_ratio": snappedf(ratio, 0.001),
			"opaque_samples": opaque,
		})
		if ratio >= 0.999:
			redundant += 1
		elif ratio >= 0.5:
			partial += 1
		else:
			essential += 1
	ranked_report.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["covered_ratio"] != b["covered_ratio"]:
			return a["covered_ratio"] > b["covered_ratio"]
		return int(a["opaque_samples"]) > int(b["opaque_samples"])
	)
	var report_path := "outputs/wall_redundancy_%s.json" % map_key
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({
			"map_key": map_key,
			"instances_by_covered_ratio": ranked_report,
		}, "  ") + "\n")
		file.close()
	print("RENDER_REDUNDANCY map=%s instances=%d redundant=%d partial_majority=%d essential=%d transparent_only=%d load_failures=%d report=%s" % [
		map_key,
		instance_stats.size(),
		redundant,
		partial,
		essential,
		transparent_only,
		load_failures,
		report_path,
	])


func _load_image(command: Dictionary, image_cache: Dictionary) -> Image:
	var image_path := str(command.get("image_path", ""))
	if image_path.is_empty():
		return null
	var res_path: String = image_path if image_path.begins_with("res://") else (
		"res://" + image_path.lstrip("/")
	)
	if not image_cache.has(res_path):
		image_cache[res_path] = Image.load_from_file(
			ProjectSettings.globalize_path(res_path)
		)
	return image_cache[res_path]


func _command_world_rect(
	command: Dictionary,
	design_size: Vector2i,
	tex_size: Vector2i
) -> Rect2i:
	var geometry := MapEditorRuntimeVisualGeometryService.runtime_command_geometry(
		command, design_size, Vector2(tex_size)
	)
	if absf(float(geometry.get("rotation", 0.0))) > 0.001:
		return Rect2i()
	var center: Vector2 = geometry.get("center", Vector2.ZERO)
	var anchor: Vector2 = geometry.get("anchor", Vector2.ZERO)
	var visual_scale: Vector2 = geometry.get("visual_scale", Vector2.ONE)
	var top_left := center - anchor * visual_scale
	var size := Vector2(tex_size) * visual_scale
	return Rect2i(Vector2i(top_left.floor()), Vector2i(size.ceil()))


func _opaque_world_pixels(
	command: Dictionary,
	design_size: Vector2i,
	tex_size: Vector2i,
	world_rect: Rect2i,
	origin: Vector2i,
	grid_size: Vector2i,
	image_cache: Dictionary
) -> PackedVector2Array:
	var result := PackedVector2Array()
	if world_rect == Rect2i():
		return result
	var image := _load_image(command, image_cache)
	if image == null:
		return result
	var geometry := MapEditorRuntimeVisualGeometryService.runtime_command_geometry(
		command, design_size, Vector2(tex_size)
	)
	var center: Vector2 = geometry.get("center", Vector2.ZERO)
	var anchor: Vector2 = geometry.get("anchor", Vector2.ZERO)
	var visual_scale: Vector2 = geometry.get("visual_scale", Vector2.ONE)
	var top_left := center - anchor * visual_scale
	var sx := visual_scale.x
	var sy := visual_scale.y
	var texture_y := 0.0
	while texture_y < float(tex_size.y):
		var texture_x := 0.0
		while texture_x < float(tex_size.x):
			if image.get_pixel(
				int(texture_x), int(texture_y)
			).a > ALPHA_THRESHOLD:
				var world := Vector2i(
					int(top_left.x + texture_x * sx) - origin.x,
					int(top_left.y + texture_y * sy) - origin.y
				)
				if (
					world.x >= 0 and world.y >= 0
					and world.x < grid_size.x and world.y < grid_size.y
				):
					result.append(world)
			texture_x += SAMPLE_STEP_PX
		texture_y += SAMPLE_STEP_PX
	return result
