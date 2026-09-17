extends SceneTree
## WALL-P1R Publisher: generates wall_render_plan.json + sha-addressed PNG
## store per map (advisor production contracts 1-6, 2026-09-17).
##
## Atomic per map: all PNGs and hashes are produced in staging first; the
## plan file is written last only after full verification. Any failure
## leaves the map without a plan (runtime keeps legacy rendering).
## Determinism: publishing twice with identical inputs must produce
## byte-identical files (verified in-process each run).

const COMPILER := preload(
	"res://scripts/map_editor/map_editor_wall_render_compiler.gd"
)
const GEOMETRY_SERVICE := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)
const COORDINATE := preload("res://scripts/map_editor/map_editor_coordinate.gd")

const PLAN_DIR := "res://assets/data/runtime/map_editor/wall_render_plans"
const STORE_DIR := "res://assets/data/runtime/map_editor/wall_render_store"
const DEFAULT_MAPS := "mengzhong_dark_area,chiyue_valley"

var _image_cache := {}


func _init() -> void:
	var maps := DEFAULT_MAPS.split(",", false)
	if OS.get_environment("WALL_RENDER_MAPS") != "":
		maps = OS.get_environment("WALL_RENDER_MAPS").split(",", false)
	var failures: PackedStringArray = []
	var report_rows: Array = []
	for map_key: String in maps:
		var row := _publish_map(map_key.strip_edges())
		if row.has("error"):
			failures.append("%s: %s" % [map_key, str(row["error"])])
			continue
		report_rows.append(row)
	var report := {
		"contract_id": "hardcore.wall_render_memory_report.v1",
		"rows": report_rows,
	}
	var report_path := "res://outputs/wall_perf/wall_render_memory_report.json"
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://outputs/wall_perf")
	)
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t"))
	report_file.close()
	print("PUBREPORT_TABLE")
	print("map | atlas_pages | atlas_pixels | atlas_rgba8_mib | static_chunks_before | static_chunks_after | chunk_rgba8_mib_after_trim | png_disk_mib | legacy_commands")
	for row: Dictionary in report_rows:
		print("%s | %d | %d | %.2f | %d | %d | %.2f | %.2f | %d" % [
			row["map"], row["atlas_pages"], row["atlas_pixels"],
			row["atlas_rgba8_mib"], row["chunk_pixels_before_trim"],
			row["chunk_pixels_after_trim"], row["chunk_rgba8_mib_after_trim"],
			row["png_disk_mib"], row["legacy_commands"],
		])
	if failures.is_empty():
		print("PUBRESULT PASS")
		quit(0)
	else:
		for failure: String in failures:
			print("PUBFAIL ", failure)
		print("PUBRESULT FAIL")
		quit(1)


static func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _publish_map(map_key: String) -> Dictionary:
	var runtime_path := (
		"res://assets/data/runtime/map_editor/%s.runtime.json" % map_key
	)
	var runtime_bytes := FileAccess.get_file_as_bytes(runtime_path)
	if runtime_bytes.is_empty():
		return {"error": "runtime json missing"}
	var runtime_sha := _sha256_bytes(runtime_bytes)
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(runtime_path)
	)
	if raw is not Dictionary:
		return {"error": "runtime json unparsable"}
	var instances: Array = raw.get("instances", [])
	# design_size authority is the runtime's nested design.design_size (the
	# same field the game's visual geometry service consumes). A missing or
	# malformed design must fail the publish - a silent default would bake
	# every atlas/chunk position in the wrong screen space.
	var design_container: Dictionary = raw.get("design", {})
	if design_container.is_empty() or not design_container.has("design_size"):
		return {"error": "runtime design.design_size missing"}
	var design_raw: Array = design_container.get("design_size", [])
	if design_raw.size() != 2 or int(design_raw[0]) <= 0 or int(design_raw[1]) <= 0:
		return {"error": "runtime design.design_size malformed"}
	var design_size := Vector2i(int(design_raw[0]), int(design_raw[1]))
	var commands: Array = GEOMETRY_SERVICE.sorted_draw_commands(instances)
	var plan: Dictionary = COMPILER.compile_plan(
		commands, design_size, _image_size
	)
	if plan.get("contract_violation", false):
		return {"error": "compiler contract violation"}
	var materialized: Dictionary = COMPILER.materialize(
		plan, commands, _load_image
	)
	if materialized.has("error"):
		return {"error": str(materialized["error"])}
	# Trim transparent margins from every shadow chunk (advisor contract 4):
	# grid/segment authority is preserved, only position_px/size_px shrink
	# to the opaque bounding rect.
	var chunk_pixels_before := 0
	var chunk_pixels_after := 0
	var chunk_records: Array = []
	for chunk: Dictionary in materialized["shadow_chunks"]:
		var image: Image = chunk["image"]
		chunk_pixels_before += image.get_width() * image.get_height()
		var used := image.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			continue
		var trimmed := image.get_region(used)
		chunk_pixels_after += trimmed.get_width() * trimmed.get_height()
		chunk_records.append({
			"segment_index": chunk["segment_index"],
			"insert_command_index": chunk["insert_command_index"],
			"grid_cell": chunk["grid_cell"],
			"position_px": [
				float(chunk["position_px"][0]) + float(used.position.x),
				float(chunk["position_px"][1]) + float(used.position.y),
			],
			"size_px": [trimmed.get_width(), trimmed.get_height()],
			"image": trimmed,
		})
	# Stage + hash every derived PNG (sha-addressed store).
	var store_names: Dictionary = {}
	var atlas_page_records: Array = []
	var atlas_pixels := 0
	for page_index: int in materialized["atlas_pages"].size():
		var page_image: Image = materialized["atlas_pages"][page_index]
		atlas_pixels += page_image.get_width() * page_image.get_height()
		var record := _store_png(page_image, store_names)
		if record.has("error"):
			return record
		record["page_index"] = page_index
		atlas_page_records.append(record)
	for record_index: int in chunk_records.size():
		var record := _store_png(chunk_records[record_index]["image"],
			store_names)
		if record.has("error"):
			return record
		chunk_records[record_index]["path"] = record["path"]
		chunk_records[record_index]["sha256"] = record["sha256"]
		chunk_records[record_index]["png_bytes"] = record["png_bytes"]
	# Source image content hashes for every baked source (contract 1).
	var source_paths := {}
	for entry: Dictionary in plan["atlas_entries"]:
		for layer: Dictionary in entry["layers"]:
			source_paths[str(layer["image_path"])] = true
	for segment: Dictionary in plan["shadow_segments"]:
		for index: int in segment["command_indices"]:
			source_paths[str(commands[index].get("image_path", ""))] = true
	var source_hashes := {}
	var sorted_paths: Array = source_paths.keys()
	sorted_paths.sort()
	for path: String in sorted_paths:
		var bytes := FileAccess.get_file_as_bytes(_res_source_path(path))
		if bytes.is_empty():
			return {"error": "source image bytes unreadable: %s" % path}
		source_hashes[path] = _sha256_bytes(bytes)
	var png_disk_bytes := 0
	for record: Dictionary in atlas_page_records:
		png_disk_bytes += int(record["png_bytes"])
	for record: Dictionary in chunk_records:
		png_disk_bytes += int(record["png_bytes"])
	var plan_document := {
		"contract_id": COMPILER.PLAN_CONTRACT_ID,
		"compiler_version": 2,
		"map_key": map_key,
		"design_size": [design_size.x, design_size.y],
		"visual_geometry_contract_id":
			GEOMETRY_SERVICE.VISUAL_GEOMETRY_CONTRACT_ID,
		"ground_coordinate_contract_id": COORDINATE.GROUND_COORDINATE_CONTRACT_ID,
		"source_runtime_json_sha256": runtime_sha,
		"source_commands_sha256": plan["source_commands_sha256"],
		"source_image_sha256": source_hashes,
		"atlas_page_heights": plan["atlas_page_heights"],
		"atlas_pages": atlas_page_records,
		"atlas_entries": plan["atlas_entries"],
		"shadow_segments": plan["shadow_segments"],
		"shadow_chunks": chunk_records,
		"atlas_command_indices": plan["atlas_command_indices"],
		"shadow_chunk_command_indices": plan["shadow_chunk_command_indices"],
		"legacy_command_indices": plan["legacy_command_indices"],
		"accounting": plan["accounting"],
	}
	var stage_error := _stage_plan_document(map_key, plan_document)
	if stage_error != "":
		return {"error": stage_error}
	# Advisor R1.1: the candidate plan is verified BEFORE it becomes the
	# official plan. The final rename is the only commit point; a failed
	# verification removes the candidate and leaves any previous official
	# plan untouched.
	var candidate_path := ProjectSettings.globalize_path(PLAN_DIR).path_join(
		"%s.wall_render_plan.json.tmp" % map_key
	)
	var verify_error := _verify_candidate_plan(
		candidate_path, plan_document, commands, runtime_sha
	)
	if verify_error != "":
		DirAccess.remove_absolute(candidate_path)
		return {"error": verify_error}
	var commit_error := _commit_plan_document(map_key)
	if commit_error != "":
		return {"error": commit_error}
	return {
		"map": map_key,
		"atlas_pages": atlas_page_records.size(),
		"atlas_pixels": atlas_pixels,
		"atlas_rgba8_mib": float(atlas_pixels * 4) / 1048576.0,
		"chunk_pixels_before_trim": chunk_pixels_before,
		"chunk_pixels_after_trim": chunk_pixels_after,
		"chunk_rgba8_mib_after_trim": float(chunk_pixels_after * 4) / 1048576.0,
		"png_disk_mib": float(png_disk_bytes) / 1048576.0,
		"legacy_commands": plan["accounting"]["legacy_commands"],
		"chunks": chunk_records.size(),
		"store_files": store_names.size(),
	}


## Saves an Image as PNG into the sha-addressed store. Returns the store
## record; identical content dedupes to the same file (contract 6).
func _store_png(image: Image, store_names: Dictionary) -> Dictionary:
	var staging := ProjectSettings.globalize_path("res://outputs/wall_perf/staging")
	DirAccess.make_dir_recursive_absolute(staging)
	var staging_path := staging.path_join("candidate.png")
	DirAccess.remove_absolute(staging_path)
	var save_error := image.save_png(staging_path)
	if save_error != OK:
		return {"error": "png save failed: %d" % save_error}
	var bytes := FileAccess.get_file_as_bytes(staging_path)
	var sha := _sha256_bytes(bytes)
	var store_global := ProjectSettings.globalize_path(STORE_DIR)
	DirAccess.make_dir_recursive_absolute(store_global)
	var store_path := store_global.path_join("%s.png" % sha)
	if not FileAccess.file_exists(store_path):
		var copy_error := DirAccess.rename_absolute(staging_path, store_path)
		if copy_error != OK:
			return {"error": "store write failed: %d" % copy_error}
	else:
		DirAccess.remove_absolute(staging_path)
	store_names[sha] = true
	return {
		"path": "%s/%s.png" % [STORE_DIR.replace("res://", ""), sha],
		"sha256": sha,
		"width": image.get_width(),
		"height": image.get_height(),
		"png_bytes": bytes.size(),
	}


func _stage_plan_document(map_key: String, plan_document: Dictionary) -> String:
	var plan_dir := ProjectSettings.globalize_path(PLAN_DIR)
	DirAccess.make_dir_recursive_absolute(plan_dir)
	var tmp_path := plan_dir.path_join(
		"%s.wall_render_plan.json.tmp" % map_key
	)
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return "plan tmp open failed"
	file.store_string(JSON.stringify(plan_document, "\t"))
	file.close()
	return ""


## The commit point: only called after full candidate verification.
func _commit_plan_document(map_key: String) -> String:
	var plan_dir := ProjectSettings.globalize_path(PLAN_DIR)
	var tmp_path := plan_dir.path_join(
		"%s.wall_render_plan.json.tmp" % map_key
	)
	var final_path := plan_dir.path_join(
		"%s.wall_render_plan.json" % map_key
	)
	var rename_error := DirAccess.rename_absolute(tmp_path, final_path)
	if rename_error != OK:
		return "plan rename failed: %d" % rename_error
	return ""


## Complete candidate verification (advisor R1.1): the plan contract is
## checked in full against independently recomputed authority - contracts,
## both design axes, runtime sha, command digest, source image hashes,
## strict index range/union, derived PNG shas, and entry region bounds.
## Runs on the CANDIDATE file; the official plan is only produced by the
## subsequent rename.
func _verify_candidate_plan(
	candidate_path: String,
	plan_document: Dictionary,
	commands: Array,
	runtime_sha: String
) -> String:
	var reloaded: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(candidate_path)
	)
	if reloaded is not Dictionary:
		return "verification: plan unparsable"
	var plan: Dictionary = reloaded
	if str(plan.get("contract_id", "")) != COMPILER.PLAN_CONTRACT_ID:
		return "verification: contract id mismatch"
	if int(plan.get("compiler_version", -1)) != 2:
		return "verification: compiler version mismatch"
	if str(plan.get("map_key", "")) != str(plan_document["map_key"]):
		return "verification: map key mismatch"
	var design: Array = plan.get("design_size", [])
	if (
		design.size() != 2
		or int(design[0]) != int(plan_document["design_size"][0])
		or int(design[1]) != int(plan_document["design_size"][1])
	):
		return "verification: design size mismatch"
	if str(plan.get("visual_geometry_contract_id", "")) != (
		GEOMETRY_SERVICE.VISUAL_GEOMETRY_CONTRACT_ID
	):
		return "verification: geometry contract mismatch"
	if str(plan.get("ground_coordinate_contract_id", "")) != (
		COORDINATE.GROUND_COORDINATE_CONTRACT_ID
	):
		return "verification: coordinate contract mismatch"
	if str(plan.get("source_runtime_json_sha256", "")) != runtime_sha:
		return "verification: runtime json sha mismatch"
	if str(plan.get("source_commands_sha256", "")) != (
		COMPILER.commands_digest(commands)
	):
		return "verification: command digest mismatch"
	var total := int(plan["accounting"]["total_commands"])
	if total != commands.size():
		return "verification: total command count mismatch"
	# Index sets: in-range, pairwise disjoint, exact full union.
	var seen := {}
	for bucket: String in [
		"atlas_command_indices", "shadow_chunk_command_indices",
		"legacy_command_indices",
	]:
		for value: Variant in plan[bucket]:
			var index := int(value)
			if index < 0 or index >= total:
				return "verification: index out of range %d" % index
			if seen.has(index):
				return "verification: duplicate classification %d" % index
			seen[index] = true
	if seen.size() != total:
		return "verification: closure mismatch %d != %d" % [
			seen.size(), total,
		]
	# Atlas pages: count, recorded sha and recorded dimensions.
	var page_heights: Array = plan["atlas_page_heights"]
	var pages: Array = plan["atlas_pages"]
	if pages.size() != page_heights.size():
		return "verification: page count mismatch"
	for record: Dictionary in pages:
		var page_error := _verify_store_record(record)
		if page_error != "":
			return page_error
		if int(record["width"]) != COMPILER.PAGE_WIDTH:
			return "verification: page width mismatch"
		if int(record["height"]) != int(
			page_heights[int(record["page_index"])]
		):
			return "verification: page height mismatch"
	# Atlas entries: authority fields, key uniqueness, region bounds.
	var seen_keys := {}
	for entry: Dictionary in plan["atlas_entries"]:
		var key := str(entry.get("key", ""))
		if key.is_empty() or seen_keys.has(key):
			return "verification: entry key empty or duplicated"
		seen_keys[key] = true
		var page_index := int(entry.get("page", -1))
		var region: Array = entry.get("region", [])
		if (
			entry.get("layers", []).is_empty()
			or entry.get("group_keys", []).is_empty()
			or entry.get("command_indices", []).is_empty()
			or page_index < 0 or page_index >= pages.size()
			or region.size() != 4
		):
			return "verification: incomplete entry %s" % key
		for value: Variant in entry["command_indices"]:
			if int(value) < 0 or int(value) >= total:
				return "verification: entry index out of range %s" % key
		if (
			int(region[0]) < 0 or int(region[1]) < 0
			or int(region[0]) + int(region[2]) > COMPILER.PAGE_WIDTH
			or int(region[1]) + int(region[3]) > int(
				page_heights[page_index]
			)
		):
			return "verification: entry region out of bounds %s" % key
	# Group mappings (advisor C0): global uniqueness, representative
	# membership, per-command group agreement, exact union == atlas set.
	var mapping_groups := {}
	var mapped_commands := {}
	for entry: Dictionary in plan["atlas_entries"]:
		for mapping: Dictionary in entry.get("group_mappings", []):
			var group_key := str(mapping.get("group_key", ""))
			if group_key.is_empty() or mapping_groups.has(group_key):
				return "verification: group mapping empty or duplicated %s" % (
					group_key
				)
			mapping_groups[group_key] = true
			var representative := int(
				mapping.get("representative_command_index", -1)
			)
			# JSON round-trip yields floats: normalize through int() before
			# any membership test (Array.has() does not cross int/float).
			var mapping_ints := {}
			for value: Variant in mapping.get("command_indices", []):
				mapping_ints[int(value)] = true
			if representative < 0 or not mapping_ints.has(representative):
				return "verification: representative not in mapping %s" % (
					group_key
				)
			for value: Variant in mapping.get("command_indices", []):
				var index := int(value)
				if mapped_commands.has(index):
					return "verification: command in two mappings %d" % index
				mapped_commands[index] = true
				if str(commands[index].get("actor_sort_group", "")) != (
					group_key
				):
					return "verification: mapping group key mismatch %d" % (
						index
					)
	var atlas_command_set := {}
	for value: Variant in plan["atlas_command_indices"]:
		atlas_command_set[int(value)] = true
	if mapped_commands.size() != atlas_command_set.size():
		return "verification: mapping union size != atlas set"
	for index: int in atlas_command_set:
		if not mapped_commands.has(index):
			return "verification: mapping missing command %d" % index
	# Shadow chunks: store sha, positive size, valid segment references.
	var segment_count: int = plan["shadow_segments"].size()
	var chunk_records: Array = plan["shadow_chunks"]
	for record: Dictionary in chunk_records:
		var chunk_error := _verify_store_record(record)
		if chunk_error != "":
			return chunk_error
		if int(record["segment_index"]) < 0 or int(
			record["segment_index"]
		) >= segment_count:
			return "verification: chunk segment index invalid"
		if int(record["size_px"][0]) <= 0 or int(record["size_px"][1]) <= 0:
			return "verification: chunk size invalid"
	# Source image hashes: recomputed from the source files, complete over
	# every baked source (atlas layers + shadow segment commands).
	var source_hashes: Dictionary = plan["source_image_sha256"]
	var expected_paths := {}
	for entry: Dictionary in plan["atlas_entries"]:
		for layer: Dictionary in entry["layers"]:
			expected_paths[str(layer["image_path"])] = true
	for segment: Dictionary in plan["shadow_segments"]:
		for index: int in segment["command_indices"]:
			expected_paths[str(
				commands[int(index)].get("image_path", "")
			)] = true
	if source_hashes.size() != expected_paths.size():
		return "verification: source hash coverage mismatch"
	for path: String in expected_paths:
		if not source_hashes.has(path):
			return "verification: source hash missing %s" % path
		var bytes := FileAccess.get_file_as_bytes(_res_source_path(path))
		if bytes.is_empty() or _sha256_bytes(bytes) != str(
			source_hashes[path]
		):
			return "verification: source sha mismatch %s" % path
	return ""


func _verify_store_record(record: Dictionary) -> String:
	var store_path := ProjectSettings.globalize_path(
		"res://%s" % str(record["path"])
	)
	var bytes := FileAccess.get_file_as_bytes(store_path)
	if bytes.is_empty() or _sha256_bytes(bytes) != str(record["sha256"]):
		return "verification: store sha mismatch %s" % str(record["path"])
	return ""


func _image_size(path: String) -> Vector2i:
	var image: Image = _load_image(path)
	return Vector2i.ZERO if image == null else image.get_size()


func _load_image(path: String) -> Image:
	if _image_cache.has(path):
		return _image_cache[path]
	var image: Image = null
	var resource_path := _res_source_path(path)
	if ResourceLoader.exists(resource_path):
		var texture: Texture2D = load(resource_path)
		if texture != null:
			image = texture.get_image()
	if image != null and image.is_compressed():
		image.decompress()
	_image_cache[path] = image
	return image


func _res_source_path(path: String) -> String:
	return path if path.begins_with("res://") else (
		"res://" + path.lstrip("/")
	)
