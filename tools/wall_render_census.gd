extends Node

## WALL-P1R R0 rollout census (headless scene run, dry-run, zero writes).
## Enumerates every formal runtime map from the release registry and runs
## the real compiler pipeline IN MEMORY (compile_plan + materialize, no
## store writes, no plan writes) to classify:
##   A OPTIMIZABLE     - atlas commands exist and the contract completes.
##   B LEGACY_NO_GAIN   - no atlas commands (R1: never publish an empty plan).
##   C BLOCKED          - contract violation / materialize error / bad design.
## Usage:
##   godot --headless --path . -s res://tools/wall_render_census.gd

const BRIDGE := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)
const GEOMETRY_SERVICE := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)
const COMPILER := preload(
	"res://scripts/map_editor/map_editor_wall_render_compiler.gd"
)


static func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _image_size(path: String) -> Vector2i:
	var image := _load_image(path)
	if image == null:
		return Vector2i.ZERO
	return Vector2i(image.get_width(), image.get_height())


func _load_image(path: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(path))


func _ready() -> void:
	var rows: Array = []
	var failures := 0
	var map_ids := BRIDGE.released_map_ids()
	map_ids.sort()
	for map_id: int in map_ids:
		var runtime_path := str(BRIDGE.runtime_path(map_id))
		if runtime_path.is_empty() or not BRIDGE.has_runtime_map(map_id):
			rows.append({"map_id": map_id, "class": "C", "error": "no runtime path"})
			failures += 1
			continue
		var map_key := runtime_path.get_file().replace(".runtime.json", "")
		var runtime_bytes := FileAccess.get_file_as_bytes(runtime_path)
		if runtime_bytes.is_empty():
			rows.append({"map_id": map_id, "map_key": map_key, "class": "C", "error": "runtime json missing"})
			failures += 1
			continue
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(runtime_path))
		if raw is not Dictionary:
			rows.append({"map_id": map_id, "map_key": map_key, "class": "C", "error": "runtime json unparsable"})
			failures += 1
			continue
		var design_container: Dictionary = raw.get("design", {})
		var design_raw: Array = design_container.get("design_size", [])
		if design_raw.size() != 2 or int(design_raw[0]) <= 0 or int(design_raw[1]) <= 0:
			rows.append({"map_id": map_id, "map_key": map_key, "class": "C", "error": "design_size missing/malformed"})
			failures += 1
			continue
		var design_size := Vector2i(int(design_raw[0]), int(design_raw[1]))
		var instances: Array = raw.get("instances", [])
		var commands: Array = GEOMETRY_SERVICE.sorted_draw_commands(instances)
		var plan: Dictionary = COMPILER.compile_plan(commands, design_size, _image_size)
		if bool(plan.get("contract_violation", false)) or plan.has("error"):
			rows.append({
				"map_id": map_id, "map_key": map_key, "class": "C",
				"error": str(plan.get("error", "compiler contract violation")),
				"total_commands": commands.size(),
			})
			failures += 1
			continue
		var atlas_commands: int = plan.get("atlas_command_indices", []).size()
		if atlas_commands == 0:
			# R1: zero-atlas maps stay plan-missing LEGACY; no empty plans.
			rows.append({
				"map_id": map_id, "map_key": map_key, "class": "B",
				"design_size": [design_size.x, design_size.y],
				"total_commands": commands.size(),
				"atlas_commands": 0,
				"static_chunk_commands": plan.get("shadow_chunk_command_indices", []).size(),
				"legacy_commands": plan.get("legacy_command_indices", []).size(),
			})
			continue
		var materialized: Dictionary = COMPILER.materialize(plan, commands, _load_image)
		if materialized.has("error"):
			rows.append({
				"map_id": map_id, "map_key": map_key, "class": "C",
				"error": str(materialized["error"]),
				"total_commands": commands.size(),
				"atlas_commands": atlas_commands,
			})
			failures += 1
			continue
		# Detail fields follow the MATERIALIZED contract: atlas_pages are
		# Images, chunk trim is measured on chunk Images, groups come from
		# per-entry group_mappings, source textures from bake inputs.
		var page_images: Array = materialized["atlas_pages"]
		var chunk_images: Array = materialized["shadow_chunks"]
		var atlas_pages := page_images.size()
		var atlas_pixels := 0
		for page_image: Image in page_images:
			atlas_pixels += page_image.get_width() * page_image.get_height()
		var dynamic_group_count := 0
		var unique_sources := {}
		for entry: Dictionary in plan.get("atlas_entries", []):
			dynamic_group_count += entry.get("group_mappings", []).size()
			for layer: Dictionary in entry.get("layers", []):
				unique_sources[str(layer.get("image_path", ""))] = true
		var chunk_pixels_before := 0
		var chunk_pixels_after := 0
		for chunk: Dictionary in chunk_images:
			var image: Image = chunk["image"]
			chunk_pixels_before += image.get_width() * image.get_height()
			var used := image.get_used_rect()
			if used.size.x > 0 and used.size.y > 0:
				chunk_pixels_after += used.size.x * used.size.y
		for segment: Dictionary in plan.get("shadow_segments", []):
			for index: int in segment.get("command_indices", []):
				unique_sources[str(commands[index].get("image_path", ""))] = true
		# Bridge candidates: the formal geometry-service authority.
		var bridge_candidates := 0
		var static_span_legacy := 0
		for index: int in commands.size():
			var command: Dictionary = commands[index]
			if not GEOMETRY_SERVICE.is_static_authored_wall_bridge_candidate(command):
				continue
			bridge_candidates += 1
			if plan.get("legacy_command_indices", []).has(index):
				static_span_legacy += 1
		var legacy_commands: int = plan.get("legacy_command_indices", []).size()
		var shadow_chunk_commands: int = plan.get(
			"shadow_chunk_command_indices", []
		).size()
		# Hard self-checks: report mapping errors fail the census.
		var page_heights: Array = plan.get("atlas_page_heights", [])
		var height_pixels := 0
		for h: int in page_heights:
			height_pixels += COMPILER.PAGE_WIDTH * int(h)
		var accounting: Dictionary = plan.get("accounting", {})
		var checks := {
			"atlas_pages_eq_heights": atlas_pages == page_heights.size(),
			"atlas_pixels_eq_heights": atlas_pixels == height_pixels,
			"groups_ge_entries": dynamic_group_count
				>= plan.get("atlas_entries", []).size(),
			"command_closure": atlas_commands + shadow_chunk_commands
				+ legacy_commands == commands.size(),
			"accounting_closure": int(accounting.get("total_commands", -1))
				== commands.size(),
		}
		for check_name: String in checks:
			if not bool(checks[check_name]):
				rows.append({
					"map_id": map_id, "map_key": map_key, "class": "C",
					"error": "census self-check failed: %s" % check_name,
				})
				failures += 1
		rows.append({
			"map_id": map_id, "map_key": map_key, "class": "A",
			"design_size": [design_size.x, design_size.y],
			"total_commands": commands.size(),
			"atlas_commands": atlas_commands,
			"dynamic_group_count": dynamic_group_count,
			"unique_atlas_entries": plan.get("atlas_entries", []).size(),
			"static_chunk_commands": shadow_chunk_commands,
			"static_chunk_count_before_trim": chunk_images.size(),
			"shadow_segments": plan.get("shadow_segments", []).size(),
			"legacy_commands": legacy_commands,
			"transformed_static_breakers": static_span_legacy,
			"bridge_candidate_count": bridge_candidates,
			"atlas_pages": atlas_pages,
			"atlas_pixel_estimate": atlas_pixels,
			"static_pixels_before_trim": chunk_pixels_before,
			"static_pixels_after_trim": chunk_pixels_after,
			"source_texture_count": unique_sources.size(),
		})
	var report := {
		"contract_id": "hardcore.wall_render_c10_rollout_census.v1",
		"released_map_count": map_ids.size(),
		"rows": rows,
	}
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://outputs/wall_perf")
	)
	var report_file := FileAccess.open(
		"res://outputs/wall_perf/wall_render_rollout_census.json", FileAccess.WRITE
	)
	report_file.store_string(JSON.stringify(report, "\t"))
	report_file.close()
	var counts := {"A": 0, "B": 0, "C": 0}
	for row: Dictionary in rows:
		counts[str(row["class"])] = int(counts[str(row["class"])]) + 1
		if str(row["class"]) == "C":
			print("CENSUS_C %s %s %s" % [
				str(row.get("map_key", row.get("map_id"))),
				str(row.get("error", "")), str(row.get("total_commands", "")),
			])
	print("CENSUS_TOTAL released=%d A=%d B=%d C=%d" % [
		map_ids.size(), counts["A"], counts["B"], counts["C"],
	])
	get_tree().quit(0 if counts["C"] == 0 else 1)
