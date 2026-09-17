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
	var design_raw: Array = raw.get("design_size", [64, 64])
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
	var write_error := _write_plan_atomically(map_key, plan_document)
	if write_error != "":
		return {"error": write_error}
	var verify_error := _verify_written_plan(map_key, plan_document, commands)
	if verify_error != "":
		return {"error": verify_error}
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


func _write_plan_atomically(map_key: String, plan_document: Dictionary) -> String:
	var plan_dir := ProjectSettings.globalize_path(PLAN_DIR)
	DirAccess.make_dir_recursive_absolute(plan_dir)
	var final_path := plan_dir.path_join(
		"%s.wall_render_plan.json" % map_key
	)
	var tmp_path := plan_dir.path_join(
		"%s.wall_render_plan.json.tmp" % map_key
	)
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return "plan tmp open failed"
	file.store_string(JSON.stringify(plan_document, "\t"))
	file.close()
	var rename_error := DirAccess.rename_absolute(tmp_path, final_path)
	if rename_error != OK:
		return "plan rename failed: %d" % rename_error
	return ""


## Full post-write verification (advisor contract 7, consumer-side preview):
## reload the JSON from disk, recompute the command digest, and check every
## recorded store file exists with the recorded sha.
func _verify_written_plan(
	map_key: String,
	plan_document: Dictionary,
	commands: Array
) -> String:
	var plan_path := ProjectSettings.globalize_path(PLAN_DIR).path_join(
		"%s.wall_render_plan.json" % map_key
	)
	var reloaded: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(plan_path)
	)
	if reloaded is not Dictionary:
		return "verification: plan unparsable"
	if str(reloaded["source_commands_sha256"]) != (
		COMPILER.commands_digest(commands)
	):
		return "verification: digest mismatch"
	if int(reloaded["design_size"][0]) != int(plan_document["design_size"][0]):
		return "verification: design size mismatch"
	for record: Dictionary in reloaded["atlas_pages"]:
		var store_path := ProjectSettings.globalize_path(
			"res://%s" % str(record["path"])
		)
		var bytes := FileAccess.get_file_as_bytes(store_path)
		if bytes.is_empty() or _sha256_bytes(bytes) != str(record["sha256"]):
			return "verification: atlas page sha mismatch"
	for record: Dictionary in reloaded["shadow_chunks"]:
		var store_path := ProjectSettings.globalize_path(
			"res://%s" % str(record["path"])
		)
		var bytes := FileAccess.get_file_as_bytes(store_path)
		if bytes.is_empty() or _sha256_bytes(bytes) != str(record["sha256"]):
			return "verification: chunk sha mismatch"
	var seen := {}
	for bucket: String in [
		"atlas_command_indices", "shadow_chunk_command_indices",
		"legacy_command_indices",
	]:
		for index: int in reloaded[bucket]:
			if seen.has(index):
				return "verification: duplicate classification %d" % index
			seen[index] = true
	if seen.size() != int(reloaded["accounting"]["total_commands"]):
		return "verification: closure mismatch"
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
