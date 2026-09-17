extends SceneTree
## WALL-P1R Core R2 validation (advisor 2026-09-17 review, 10 checks):
## 1 exact accounting closure  2 single-layer coverage  3 region bounds
## 4 page pixels  5 entry pixels  6 composite reconstruction
## 7 oversized demote  8 missing image demote  9 transformed static demote
## 10 digest sensitivity.

const COMPILER := preload(
	"res://scripts/map_editor/map_editor_wall_render_compiler.gd"
)
const GEOMETRY_SERVICE := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)

var _image_cache := {}
var _failures: PackedStringArray = []


func _init() -> void:
	var service := load(
		"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
	)
	for map_key: String in ["mengzhong_dark_area", "chiyue_valley"]:
		_run_map(map_key, service)
	_run_fixture_oversized()
	_run_fixture_missing_image()
	_run_fixture_transformed_static()
	_run_fixture_ordinary_static_in_span()
	_run_fixture_transformed_decoration_in_span()
	_run_fixture_ordinary_static_outside_span()
	_run_digest_sensitivity()
	if _failures.is_empty():
		print("WCOMPILER_RESULT PASS")
		quit(0)
	else:
		for failure: String in _failures:
			print("WCOMPILER_FAIL ", failure)
		print("WCOMPILER_RESULT FAIL")
		quit(1)


func _run_map(map_key: String, service: Script) -> void:
	var runtime_path := (
		"res://assets/data/runtime/map_editor/%s.runtime.json" % map_key
	)
	var raw := _read_json(runtime_path)
	if raw.is_empty():
		_failures.append("%s runtime missing" % map_key)
		return
	var instances: Array = raw.get("instances", [])
	var commands: Array = service.sorted_draw_commands(instances)
	var plan: Dictionary = COMPILER.compile_plan(
		commands,
		Vector2i(
			int(raw.get("design_size", [64, 64])[0]),
			int(raw.get("design_size", [64, 64])[1])
		),
		func(path: String) -> Vector2i:
			var image: Image = _load_image(path)
			return Vector2i.ZERO if image == null else image.get_size()
	)
	if plan.get("contract_violation", false):
		_failures.append("%s contract violation" % map_key)
		return
	# Check 1: exact set closure.
	var seen := {}
	var pairwise_ok := true
	for bucket: String in [
		"atlas_command_indices", "shadow_chunk_command_indices",
		"legacy_command_indices",
	]:
		for index: int in plan[bucket]:
			if seen.has(index):
				pairwise_ok = false
			seen[index] = true
	var union_ok := seen.size() == commands.size()
	for index: int in commands.size():
		if not seen.has(index):
			union_ok = false
	if not (pairwise_ok and union_ok):
		_failures.append("%s closure pairwise=%s union=%s" % [
			map_key, pairwise_ok, union_ok,
		])
	# Check 2: every atlas entry has full authority fields.
	for entry: Dictionary in plan["atlas_entries"]:
		if (
			entry["layers"].is_empty() or entry["group_keys"].is_empty()
			or entry["command_indices"].is_empty()
			or int(entry["composite_size"][0]) <= 0
			or int(entry["composite_size"][1]) <= 0
			or int(entry["page"]) < 0 or entry["region"].size() != 4
		):
			_failures.append("%s incomplete entry %s" % [
				map_key, str(entry.get("key", "")),
			])
			break
	# Check 2b: single-layer coverage == distinct groups (chiyue 511).
	var atlas_groups := {}
	for entry: Dictionary in plan["atlas_entries"]:
		for group_key: String in entry["group_keys"]:
			atlas_groups[group_key] = true
	var groups_expected := {}
	for command: Dictionary in commands:
		if (
			int(command.get("image_pass", -1)) > 0
			and not str(command.get("actor_sort_group", "")).is_empty()
		):
			groups_expected[str(command.get("actor_sort_group"))] = true
	if atlas_groups.size() != groups_expected.size():
		_failures.append("%s atlas groups %d != expected %d" % [
			map_key, atlas_groups.size(), groups_expected.size(),
		])
	# Check 3: regions within page bounds.
	var heights: Array = plan["atlas_page_heights"]
	for page_height: int in heights:
		if page_height > COMPILER.PAGE_MAX_HEIGHT:
			_failures.append("%s page height overflow" % map_key)
	for entry: Dictionary in plan["atlas_entries"]:
		var region: Array = entry["region"]
		if (
			int(region[0]) < 0 or int(region[1]) < 0
			or int(region[0]) + int(region[2]) > COMPILER.PAGE_WIDTH
			or int(region[1]) + int(region[3]) > int(
				heights[int(entry["page"])]
			)
		):
			_failures.append("%s region out of bounds %s" % [
				map_key, str(entry["key"]),
			])
			return
	var materialized: Dictionary = COMPILER.materialize(
		plan, commands, _load_image
	)
	if materialized.has("error"):
		_failures.append("%s materialize error: %s" % [
			map_key, str(materialized["error"]),
		])
		return
	var pages: Array = materialized["atlas_pages"]
	if pages.size() != heights.size():
		_failures.append("%s page count mismatch" % map_key)
		return
	# Check 4: every page has opaque pixels.
	for page_index: int in pages.size():
		if not _has_opaque_pixel(pages[page_index], Rect2i(
			Vector2i.ZERO, pages[page_index].get_size()
		)):
			_failures.append("%s page %d empty" % [map_key, page_index])
	# Check 5+6: every entry region has pixels and matches a fresh rebuild.
	var rebuilt_composites := {}
	for entry: Dictionary in plan["atlas_entries"]:
		var region: Array = entry["region"]
		var rect := Rect2i(
			int(region[0]), int(region[1]), int(region[2]), int(region[3])
		)
		if not _has_opaque_pixel(pages[int(entry["page"])], rect):
			_failures.append("%s entry region empty %s" % [
				map_key, str(entry["key"]),
			])
			return
		if not rebuilt_composites.has(entry["key"]):
			rebuilt_composites[entry["key"]] = (
				COMPILER._composite_for_entry(entry, _load_image)
			)
		var rebuilt: Image = rebuilt_composites[entry["key"]]
		var baked: Image = pages[int(entry["page"])].get_region(rect)
		if not _images_equal(rebuilt, baked):
			_failures.append("%s composite mismatch %s" % [
				map_key, str(entry["key"]),
			])
			return
	print(
		"WCOMPILER %s entries=%d pages=%d chunks=%d groups=%d" % [
			map_key, plan["atlas_entries"].size(), pages.size(),
			materialized["shadow_chunks"].size(), atlas_groups.size(),
		]
	)


func _run_fixture_oversized() -> void:
	var commands := [_dynamic_command("a.png"), _dynamic_command("b.png")]
	var plan: Dictionary = COMPILER.compile_plan(
		commands, Vector2i(8, 8),
		func(_path: String) -> Vector2i: return Vector2i(4096, 8192)
	)
	if plan.get("contract_violation", false):
		_failures.append("oversized fixture contract violation")
		return
	if not plan["atlas_entries"].is_empty():
		_failures.append("oversized fixture still has atlas entries")
	if plan["legacy_command_indices"].size() != commands.size():
		_failures.append("oversized fixture not demoted to legacy")


func _run_fixture_missing_image() -> void:
	var commands := [_dynamic_command("ghost.png")]
	var plan: Dictionary = COMPILER.compile_plan(
		commands, Vector2i(8, 8),
		func(path: String) -> Vector2i:
			return Vector2i(64, 64) if path != "ghost.png" else Vector2i.ZERO
	)
	if plan.get("contract_violation", false):
		_failures.append("missing fixture contract violation")
		return
	if plan["legacy_command_indices"].size() != commands.size():
		_failures.append("missing image fixture not demoted to legacy")


func _run_fixture_transformed_static() -> void:
	var commands := [
		_static_shadow_command(0),
		_static_command_with_scale(1),
		_static_shadow_command(2),
	]
	var plan: Dictionary = COMPILER.compile_plan(
		commands, Vector2i(8, 8),
		func(_path: String) -> Vector2i: return Vector2i(64, 64)
	)
	if plan.get("contract_violation", false):
		_failures.append("transform fixture contract violation")
		return
	var chunked: Array = plan["shadow_chunk_command_indices"]
	if chunked.has(1):
		_failures.append("transformed static baked into chunks")
	if not plan["legacy_command_indices"].has(1):
		_failures.append("transformed static not in legacy")
	if not (chunked.has(0) and chunked.has(2)):
		_failures.append("identity shadows not baked around breaker")
	for segment: Dictionary in plan["shadow_segments"]:
		if segment["command_indices"].has(1):
			_failures.append("breaker inside a bake segment")


func _run_digest_sensitivity() -> void:
	var base := [_dynamic_command("a.png")]
	var base_digest: String = COMPILER.commands_digest(base)
	var scale_variant := [_dynamic_command("a.png")]
	scale_variant[0]["instance"]["scale"] = [2.0, 1.0]
	var rotation_variant := [_dynamic_command("a.png")]
	rotation_variant[0]["instance"]["rotation_deg"] = 90.0
	var offset_variant := [_dynamic_command("a.png")]
	offset_variant[0]["instance"]["offset_px"] = [3, 4]
	var path_variant := [_dynamic_command("other.png")]
	var variants := {
		"scale": scale_variant, "rotation": rotation_variant,
		"offset": offset_variant, "path": path_variant,
	}
	for variant_key: String in variants:
		if COMPILER.commands_digest(variants[variant_key]) == base_digest:
			_failures.append("digest insensitive to %s" % variant_key)


static func _dynamic_command(image_path: String) -> Dictionary:
	return {
		"image_path": image_path,
		"image_pass": 1,
		"render_domain": GEOMETRY_SERVICE.RENDER_DOMAIN_ACTOR_Y_SORT,
		"actor_sort_group": "wall_part:inst:0:0",
		"instance": {
			"instance_id": "inst", "asset_id": "asset",
			"scale": [1.0, 1.0], "rotation_deg": 0.0,
			"offset_px": [0, 0], "flip_x": false, "flip_y": false,
		},
		"asset": {"asset_id": "asset", "asset_type": "wall_module"},
		"sort_tile": [1, 1], "sort_baseline_tile": [1, 1],
		"layer_index": 0, "part_order": 0, "sequence": 0,
		"anchor": [32, 32],
	}


static func _static_command_with_scale(index: int) -> Dictionary:
	var command := _static_shadow_command(index)
	command["instance"]["scale"] = [1.5, 1.5]
	return command


## Ordinary static decoration (asset_type != wall_module) - the command
## class that must be classified exactly once by the static-span planner
## and never pre-attributed by the first scan pass.
static func _static_decoration_command(
	index: int,
	scale: Array = [1.0, 1.0]
) -> Dictionary:
	return {
		"image_path": "fixture_deco_%d.png" % index,
		"image_pass": 0,
		"render_domain": GEOMETRY_SERVICE.RENDER_DOMAIN_STATIC_BACKGROUND,
		"actor_sort_group": "",
		"instance": {
			"instance_id": "d%d" % index, "asset_id": "deco",
			"scale": scale, "rotation_deg": 0.0,
			"offset_px": [0, 0], "flip_x": false, "flip_y": false,
			"foot_tile": [index + 1, 2],
		},
		"asset": {
			"asset_id": "deco", "asset_type": "static_decoration",
			"foot_tile": [index + 1, 2],
		},
		"sort_tile": [index + 1, 2], "sort_baseline_tile": [index + 1, 2],
		"layer_index": 0, "part_order": 0, "sequence": index,
		"anchor": [32, 32],
	}


func _assert_exact_sets(
	plan: Dictionary,
	expected_chunk: Array,
	expected_legacy: Array,
	label: String
) -> void:
	if plan.get("contract_violation", false):
		_failures.append("%s contract violation" % label)
		return
	var seen := {}
	for bucket: Array in [
		plan["atlas_command_indices"],
		plan["shadow_chunk_command_indices"],
		plan["legacy_command_indices"],
	]:
		for index: int in bucket:
			if seen.has(index):
				_failures.append(
					"%s duplicate classification %d" % [label, index]
				)
			seen[index] = true
	if seen.size() != expected_chunk.size() + expected_legacy.size():
		_failures.append("%s closure size %d != expected %d" % [
			label, seen.size(),
			expected_chunk.size() + expected_legacy.size(),
		])
	for index: int in expected_chunk:
		if not plan["shadow_chunk_command_indices"].has(index):
			_failures.append("%s index %d not chunked" % [label, index])
	for index: int in expected_legacy:
		if not plan["legacy_command_indices"].has(index):
			_failures.append("%s index %d not legacy" % [label, index])


func _fixture_image(path: String) -> Image:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	if path.contains("deco"):
		image.fill(Color(0.5, 0.5, 0.5, 1.0))
	else:
		image.fill(Color(0.0, 0.0, 0.0, 0.6))
	return image


func _run_fixture_ordinary_static_in_span() -> void:
	var commands := [
		_static_shadow_command(0),
		_static_decoration_command(1),
		_static_shadow_command(2),
	]
	var plan: Dictionary = COMPILER.compile_plan(
		commands, Vector2i(8, 8),
		func(_path: String) -> Vector2i: return Vector2i(64, 64)
	)
	_assert_exact_sets(plan, [0, 1, 2], [], "deco-in-span")
	if plan["shadow_segments"].size() != 1:
		_failures.append("deco-in-span expected one segment")
	var materialized: Dictionary = COMPILER.materialize(
		plan, commands, _fixture_image
	)
	if materialized.has("error"):
		_failures.append("deco-in-span materialize: %s" % str(
			materialized["error"]
		))
		return
	var decoration_pixels := 0
	for chunk: Dictionary in materialized["shadow_chunks"]:
		var chunk_image: Image = chunk["image"]
		for y in range(chunk_image.get_height()):
			for x in range(chunk_image.get_width()):
				var pixel := chunk_image.get_pixel(x, y)
				# Fixture stack: shadow (black a=0.6) <- gray decoration
				# (a=1.0) <- shadow. A decoration-influenced pixel is fully
				# opaque with r == 0.5 * (1 - 0.6) = 0.2; shadows alone
				# stay r == 0 with a < 1.
				if pixel.a > 0.9 and pixel.r > 0.15 and pixel.r < 0.35:
					decoration_pixels += 1
	if decoration_pixels <= 0:
		_failures.append("deco-in-span decoration pixels missing")


func _run_fixture_transformed_decoration_in_span() -> void:
	var commands := [
		_static_shadow_command(0),
		_static_decoration_command(1, [1.5, 1.0]),
		_static_shadow_command(2),
	]
	var plan: Dictionary = COMPILER.compile_plan(
		commands, Vector2i(8, 8),
		func(_path: String) -> Vector2i: return Vector2i(64, 64)
	)
	_assert_exact_sets(plan, [0, 2], [1], "transformed-deco-in-span")
	if plan["shadow_segments"].size() != 2:
		_failures.append("transformed-deco-in-span expected two segments")
	for segment: Dictionary in plan["shadow_segments"]:
		if segment["command_indices"].has(1):
			_failures.append(
				"transformed-deco-in-span breaker inside segment"
			)


func _run_fixture_ordinary_static_outside_span() -> void:
	var commands := [
		_static_decoration_command(0),
		_static_shadow_command(1),
		_static_shadow_command(2),
		_static_decoration_command(3),
	]
	var plan: Dictionary = COMPILER.compile_plan(
		commands, Vector2i(8, 8),
		func(_path: String) -> Vector2i: return Vector2i(64, 64)
	)
	_assert_exact_sets(plan, [1, 2], [0, 3], "deco-outside-span")


static func _static_shadow_command(index: int) -> Dictionary:
	return {
		"image_path": "shadow_%d.png" % index,
		"image_pass": 0,
		"render_domain": GEOMETRY_SERVICE.RENDER_DOMAIN_STATIC_BACKGROUND,
		"actor_sort_group": "",
		"instance": {
			"instance_id": "s%d" % index, "asset_id": "asset",
			"scale": [1.0, 1.0], "rotation_deg": 0.0,
			"offset_px": [0, 0], "flip_x": false, "flip_y": false,
			"foot_tile": [index + 1, 1],
		},
		"asset": {
			"asset_id": "asset", "asset_type": "wall_module",
			"foot_tile": [index + 1, 1],
		},
		"sort_tile": [index + 1, 1], "sort_baseline_tile": [index + 1, 1],
		"layer_index": 0, "part_order": 0, "sequence": index,
		"anchor": [32, 32],
	}


static func _has_opaque_pixel(image: Image, rect: Rect2i) -> bool:
	for y in range(maxi(rect.position.y, 0), mini(rect.end.y, image.get_height())):
		for x in range(
			maxi(rect.position.x, 0), mini(rect.end.x, image.get_width())
		):
			if image.get_pixel(x, y).a > 0.01:
				return true
	return false


static func _images_equal(a: Image, b: Image) -> bool:
	if a.get_size() != b.get_size():
		return false
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			if a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				continue
			return false
	return true


func _load_image(path: String) -> Image:
	if _image_cache.has(path):
		return _image_cache[path]
	var image: Image = null
	var resource_path := path if path.begins_with("res://") else (
		"res://" + path.lstrip("/")
	)
	if ResourceLoader.exists(resource_path):
		var texture: Texture2D = load(resource_path)
		if texture != null:
			image = texture.get_image()
	if image != null and image.is_compressed():
		image.decompress()
	_image_cache[path] = image
	return image


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
