extends Node

## WALL-P1R R5 per-map memory proxy audit (headless, read-only).
## Model (R5-0..R5-11): logical plan records vs UNIQUE runtime resource
## paths (the coordinator manifest dedups by path), RGBA8 proxy =
## width*height*4 measured on the actual committed PNG bytes, legacy
## baseline = unique non-empty image_path set of sorted_draw_commands,
## P1R incremental = unique derived set. B7 rows included (zeros).
## RGBA8_PROXY_NOT_DEVICE_VRAM - a stable cross-machine texture-area
## proxy, NOT Android GPU VRAM (C11 scope).
## Usage:
##   godot --headless --path . res://tools/wall_render_memory_audit.gd

const ROLLOUT_AUTHORITY := preload("res://tools/wall_rollout_authority.gd")
const GEOMETRY_SERVICE := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)
const PLAN_DIR := "res://assets/data/runtime/map_editor/wall_render_plans"
const DARK_MAP_KEY := "mengzhong_dark_area"

var _dim_cache := {}


static func _proxy_mib(pixels: int) -> float:
	return float(pixels * 4) / 1048576.0


func _dims(path: String) -> Vector2i:
	if _dim_cache.has(path):
		return _dim_cache[path]
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	var size := Vector2i.ZERO
	if image != null:
		size = Vector2i(image.get_width(), image.get_height())
	_dim_cache[path] = size
	return size


func _ready() -> void:
	var authority := ROLLOUT_AUTHORITY.classify()
	if authority["error"] != "":
		printerr("R5_FAIL %s" % str(authority["error"]))
		get_tree().quit(1)
		return
	var b_keys := {}
	for row: Dictionary in authority["rows"]:
		if str(row["class"]) == "B":
			b_keys[str(row["map_key"])] = true
	var rows: Array = []
	var errors := 0
	for row: Dictionary in authority["rows"]:
		var map_key := str(row["map_key"])
		if str(row["class"]) != "A":
			rows.append({
				"map_key": map_key, "class": str(row["class"]),
				"plan_found": false, "unique_derived_pixels": 0,
			})
			continue
		var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
			"%s/%s.wall_render_plan.json" % [PLAN_DIR, map_key]
		))
		var records: Array = []
		for page: Dictionary in plan.get("atlas_pages", []):
			records.append({"r": page, "kind": "atlas"})
		for chunk: Dictionary in plan.get("shadow_chunks", []):
			records.append({"r": chunk, "kind": "chunk"})
		var logical_pixels := 0
		var unique := {}
		var unique_atlas := 0
		var unique_chunk := 0
		var unique_pixels := 0
		var unique_disk := 0
		var largest_pixels := 0
		var largest := {}
		var size_conflict := false
		var page_contract_fail := false
		for rec: Dictionary in records:
			var record: Dictionary = rec["r"]
			var rel := str(record.get("path", ""))
			if rel.begins_with("res://"):
				rel = rel.substr(6)
			rel = rel.lstrip("/")
			var stem := rel.get_file().replace(".png", "")
			var abs := "res://" + rel
			var expected := Vector2i.ZERO
			if rec["kind"] == "atlas":
				expected = Vector2i(
					int(record.get("width", 0)), int(record.get("height", 0))
				)
				if expected.x != 2048 or expected.y <= 0 or expected.y > 4096:
					page_contract_fail = true
			else:
				var sp: Array = record.get("size_px", [0, 0])
				expected = Vector2i(int(sp[0]), int(sp[1]))
			logical_pixels += expected.x * expected.y
			if unique.has(rel):
				if (unique[rel] as Vector2i) != expected:
					size_conflict = true
				continue
			# R5-3: actual committed PNG authority
			var context := HashingContext.new()
			context.start(HashingContext.HASH_SHA256)
			var bytes := FileAccess.get_file_as_bytes(abs)
			context.update(bytes)
			var raw_sha := context.finish().hex_encode()
			var actual := _dims(abs)
			if raw_sha != stem or actual != expected or actual == Vector2i.ZERO:
				errors += 1
				printerr("R5_FAIL %s: png authority mismatch %s" % [map_key, rel])
				continue
			unique[rel] = expected
			if rec["kind"] == "atlas":
				unique_atlas += 1
			else:
				unique_chunk += 1
			var px := actual.x * actual.y
			unique_pixels += px
			unique_disk += bytes.size()
			if px > largest_pixels:
				largest_pixels = px
				largest = {
					"path": rel, "width": actual.x, "height": actual.y,
					"pixels": px, "rgba8_proxy_mib": _proxy_mib(px),
					"kind": str(rec["kind"]),
				}
		# R5-5 legacy baseline from the runtime authority
		var runtime: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
			"res://assets/data/runtime/map_editor/%s.runtime.json" % map_key
		))
		var commands: Array = GEOMETRY_SERVICE.sorted_draw_commands(
			runtime.get("instances", [])
		)
		var legacy := {}
		for command: Dictionary in commands:
			var image_path := str(command.get("image_path", ""))
			if not image_path.is_empty():
				legacy[image_path] = true
		var legacy_pixels := 0
		for image_path: String in legacy.keys():
			var path := image_path
			if not path.begins_with("res://"):
				path = "res://" + path.lstrip("/")
			var dims := _dims(path)
			legacy_pixels += dims.x * dims.y
		rows.append({
			"map_key": map_key, "class": "A", "plan_found": true,
			"derived_record_count": records.size(),
			"logical_derived_pixels": logical_pixels,
			"logical_rgba8_proxy_mib": _proxy_mib(logical_pixels),
			"unique_derived_resource_count": unique.size(),
			"unique_atlas_resource_count": unique_atlas,
			"unique_chunk_resource_count": unique_chunk,
			"unique_derived_pixels": unique_pixels,
			"unique_derived_rgba8_proxy_mib": _proxy_mib(unique_pixels),
			"unique_png_disk_bytes": unique_disk,
			"unique_png_disk_mib": float(unique_disk) / 1048576.0,
			"dedup_saved_pixels": logical_pixels - unique_pixels,
			"dedup_saved_ratio": (
				1.0 - float(unique_pixels) / float(maxi(logical_pixels, 1))
			),
			"legacy_unique_texture_count": legacy.size(),
			"legacy_unique_texture_pixels": legacy_pixels,
			"legacy_rgba8_proxy_mib": _proxy_mib(legacy_pixels),
			"incremental_ratio_vs_legacy": float(unique_pixels)
				/ float(maxi(legacy_pixels, 1)),
			"transition_peak_proxy_pixels": legacy_pixels + unique_pixels,
			"transition_peak_rgba8_proxy_mib": _proxy_mib(
				legacy_pixels + unique_pixels
			),
			"atlas_pages": plan.get("atlas_pages", []).size(),
			"published_chunk_count": plan.get("shadow_chunks", []).size(),
			"largest_derived": largest,
			"page_contract_fail": page_contract_fail,
			"size_conflict": size_conflict,
		})
	# R5-9 outlier rules vs dark + distribution percentiles
	var dark_pixels := 0
	var uniques: Array = []
	var peaks: Array = []
	for row: Dictionary in rows:
		if str(row["class"]) != "A":
			continue
		if str(row["map_key"]) == DARK_MAP_KEY:
			dark_pixels = int(row["unique_derived_pixels"])
		uniques.append(int(row["unique_derived_pixels"]))
		peaks.append(float(row["transition_peak_rgba8_proxy_mib"]))
	uniques.sort()
	peaks.sort()
	var p95_idx := int(floor(0.95 * float(uniques.size() - 1)))
	var p95_uniques: int = uniques[p95_idx]
	var p95_peaks: float = peaks[p95_idx]
	for row: Dictionary in rows:
		if str(row["class"]) != "A":
			continue
		var triggers := []
		var pixels := int(row["unique_derived_pixels"])
		var peak := float(row["transition_peak_rgba8_proxy_mib"])
		if pixels > 2 * dark_pixels:
			triggers.append("A_gt_2x_dark")
		if float(pixels) > 1.5 * float(p95_uniques):
			triggers.append("B_gt_1.5x_p95")
		if peak > 1.5 * p95_peaks:
			triggers.append("C_gt_1.5x_p95_peak")
		if bool(row.get("page_contract_fail", false)):
			triggers.append("D_page_contract")
		if bool(row.get("size_conflict", false)):
			triggers.append("D_size_conflict")
		row["memory_review_required"] = triggers.size() > 0
		row["review_triggers"] = triggers
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://outputs/wall_perf")
	)
	var report := {
		"contract_id": "hardcore.wall_render_r5_memory_report.v1",
		"rgba8_proxy_note": "RGBA8_PROXY_NOT_DEVICE_VRAM",
		"dark_unique_derived_pixels": dark_pixels,
		"p95_unique_derived_pixels": p95_uniques,
		"p95_transition_peak_mib": p95_peaks,
		"rows": rows,
	}
	var rf := FileAccess.open(
		"res://outputs/wall_perf/wall_render_r5_memory_report.json",
		FileAccess.WRITE
	)
	rf.store_string(JSON.stringify(report, "\t"))
	rf.close()
	var review := 0
	var max_row := {}
	for row: Dictionary in rows:
		if bool(row.get("memory_review_required", false)):
			review += 1
			print("R5_REVIEW %s %s" % [
				str(row["map_key"]), str(row["review_triggers"]),
			])
		if str(row["class"]) == "A" and int(
			row.get("unique_derived_pixels", 0)
		) > int(max_row.get("unique_derived_pixels", 0)):
			max_row = row
	print("R5_DISTRIBUTION p50_unique_px=%d p95_unique_px=%d p50_peak_mib=%.2f p95_peak_mib=%.2f" % [
		uniques[int(uniques.size() / 2)], p95_uniques,
		peaks[int(peaks.size() / 2)], p95_peaks,
	])
	print("R5_MAX map=%s unique_px=%d unique_mib=%.2f peak_mib=%.2f largest=%s" % [
		str(max_row.get("map_key", "?")),
		int(max_row.get("unique_derived_pixels", 0)),
		float(max_row.get("unique_derived_rgba8_proxy_mib", 0.0)),
		float(max_row.get("transition_peak_rgba8_proxy_mib", 0.0)),
		str(max_row.get("largest_derived", {})),
	])
	print("WALL_RENDER_R5_MEMORY_PASS rows=%d review_required=%d hard_errors=%d" % [
		rows.size(), review, errors,
	])
	get_tree().quit(0 if (errors == 0 and rows.size() == 67) else 1)
