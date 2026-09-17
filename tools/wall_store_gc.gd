extends Node

## WALL-P1R R3 global store GC (plan-set driven, dry-run by default).
## mode=audit  - read-only preflight (sets + validation + manifest)
## mode=gc     - after a PASSING audit, delete exact set-difference orphans
## Usage:
##   godot --headless --path . res://tools/wall_store_gc.tscn -- mode=audit

const PLAN_DIR := "res://assets/data/runtime/map_editor/wall_render_plans"
const STORE_DIR_PREFIX := "assets/data/runtime/map_editor/wall_render_store/"
const STORE_DIR := "res://" + STORE_DIR_PREFIX
const HEX := "0123456789abcdef"


static func _sha256_file(path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()


static func _is_64hex(stem: String) -> bool:
	if stem.length() != 64:
		return false
	for ch: String in stem:
		if not HEX.contains(ch):
			return false
	return true


func _norm(path: String) -> String:
	var p := str(path)
	if p.begins_with("res://"):
		p = p.substr(6)
	return p.lstrip("/")


func _ready() -> void:
	var mode := "audit"
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() == 2 and pair[0] == "mode":
			mode = pair[1]
	var errors: PackedStringArray = []

	# R3-1 plan set seal
	var a60 := {}
	var maplist := FileAccess.open("res://outputs/wall_perf/a60_maplist.txt", FileAccess.READ)
	if maplist == null:
		printerr("STORE_GC_FAIL missing a60_maplist.txt")
		get_tree().quit(1)
		return
	for key: String in maplist.get_line().strip_edges().split(",", false):
		a60[key] = true
	var plan_files: PackedStringArray = []
	var dir := DirAccess.open(PLAN_DIR)
	if dir == null:
		printerr("STORE_GC_FAIL plan dir missing")
		get_tree().quit(1)
		return
	for file: String in dir.get_files():
		if file.ends_with(".wall_render_plan.json"):
			plan_files.append(file)
	var plan_keys := {}
	for file: String in plan_files:
		var key := file.replace(".wall_render_plan.json", "")
		if not a60.has(key):
			errors.append("plan not in A60: %s" % key)
		if plan_keys.has(key):
			errors.append("duplicate plan key: %s" % key)
		plan_keys[key] = true
	for key: String in a60.keys():
		if not plan_keys.has(key):
			errors.append("missing A60 plan: %s" % key)
	if plan_files.size() != 60:
		errors.append("plan count %d != 60" % plan_files.size())

	# R3-2 referenced set + per-reference validation
	var referenced := {}
	var ref_by_map := {}
	var total_refs := 0
	for file: String in plan_files:
		var key := file.replace(".wall_render_plan.json", "")
		var plan: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string(PLAN_DIR + "/" + file)
		)
		var records: Array = []
		for page: Dictionary in plan.get("atlas_pages", []):
			records.append(page)
		for chunk: Dictionary in plan.get("shadow_chunks", []):
			records.append(chunk)
		for record: Dictionary in records:
			total_refs += 1
			var rel := _norm(record.get("path", ""))
			var stem := rel.get_file().replace(".png", "")
			var ref_key := "%s|%s" % [rel, key]
			if not rel.begins_with(STORE_DIR_PREFIX):
				errors.append("%s: ref outside store: %s" % [key, rel])
				continue
			if not _is_64hex(stem):
				errors.append("%s: ref not 64hex: %s" % [key, stem])
				continue
			if str(record.get("sha256", "")) != stem:
				errors.append("%s: record sha != filename: %s" % [key, stem])
				continue
			var abs_path := "res://" + rel
			var bytes := FileAccess.get_file_as_bytes(abs_path)
			if bytes.is_empty():
				errors.append("%s: ref png missing: %s" % [key, rel])
				continue
			if _sha256_file(abs_path) != stem:
				errors.append("%s: raw sha mismatch: %s" % [key, rel])
				continue
			var image := Image.load_from_file(
				ProjectSettings.globalize_path(abs_path)
			)
			if image == null:
				errors.append("%s: png undecodable: %s" % [key, rel])
				continue
			var actual := Vector2i(image.get_width(), image.get_height())
			var expected := Vector2i.ZERO
			if record.has("width") and record.has("height"):
				expected = Vector2i(int(record["width"]), int(record["height"]))
			elif record.has("size_px"):
				var sp: Array = record["size_px"]
				expected = Vector2i(int(sp[0]), int(sp[1]))
			if actual != expected:
				errors.append("%s: size mismatch %s: %s vs %s" % [
					key, rel, str(actual), str(expected),
				])
				continue
			referenced[rel] = true
			if not ref_by_map.has(rel):
				ref_by_map[rel] = {}
			ref_by_map[rel][key] = true

	# R3-4 store scan
	var store_png := {}
	var store_import := {}
	var unexpected := []
	var sdir := DirAccess.open(STORE_DIR)
	for file: String in sdir.get_files():
		if file.ends_with(".png"):
			store_png[STORE_DIR_PREFIX + file] = true
			if not _is_64hex(file.replace(".png", "")):
				unexpected.append(file)
		elif file.ends_with(".png.import"):
			store_import[STORE_DIR_PREFIX + file] = true
		else:
			unexpected.append(file)
	if not unexpected.is_empty():
		errors.append("unexpected store files: %d (e.g. %s)" % [
			unexpected.size(), str(unexpected[0]),
		])
	var missing: PackedStringArray = []
	var orphan_png: PackedStringArray = []
	var orphan_import: PackedStringArray = []
	for rel: String in referenced.keys():
		if not store_png.has(rel):
			missing.append(rel)
	for rel: String in store_png.keys():
		if not referenced.has(rel):
			orphan_png.append(rel)
	for rel: String in store_import.keys():
		var png := rel.trim_suffix(".import")
		if not referenced.has(png):
			orphan_import.append(rel)
	if not missing.is_empty():
		errors.append("MISSING referenced png: %d (e.g. %s)" % [
			missing.size(), missing[0],
		])

	var shared_maps := 0
	var max_ref_maps := 0
	for rel: String in ref_by_map.keys():
		var count: int = ref_by_map[rel].size()
		if count > 1:
			shared_maps += 1
		max_ref_maps = maxi(max_ref_maps, count)
	# R3-6 rollback manifest
	var manifest := {
		"contract_id": "hardcore.wall_render_r3_store_gc_manifest.v1",
		"mode": mode,
		"plan_count": plan_files.size(),
		"plan_shas": {},
		"store": [],
	}
	for file: String in plan_files:
		manifest["plan_shas"][file.replace(".wall_render_plan.json", "")] = (
			_sha256_file(PLAN_DIR + "/" + file)
		)
	for rel: String in store_png.keys():
		var stem := rel.get_file().replace(".png", "")
		manifest["store"].append({
			"path": rel,
			"sha256": stem,
			"bytes": FileAccess.get_file_as_bytes("res://" + rel).size(),
			"referenced": referenced.has(rel),
			"referencing_maps": ref_by_map.get(rel, {}).keys(),
		})
	var manifest_path := "res://outputs/wall_perf/wall_store_gc_manifest.json"
	var mf := FileAccess.open(manifest_path, FileAccess.WRITE)
	mf.store_string(JSON.stringify(manifest, "\t"))
	mf.close()

	var summary := {
		"plan_count": plan_files.size(),
		"total_references": total_refs,
		"referenced_unique_png": referenced.size(),
		"store_png_before": store_png.size(),
		"store_import_before": store_import.size(),
		"shared_by_multiple_maps": shared_maps,
		"max_maps_per_png": max_ref_maps,
		"missing_png": missing.size(),
		"orphan_png": orphan_png.size(),
		"orphan_import": orphan_import.size(),
		"unexpected_files": unexpected.size(),
		"errors": errors.size(),
	}
	print("STORE_GC_PREFLIGHT %s" % JSON.stringify(summary))
	if not errors.is_empty():
		printerr("STORE_GC_FAIL errors present; zero deletions")
		get_tree().quit(1)
		return
	if mode != "gc":
		print("STORE_GC_AUDIT_PASS deletions=0")
		get_tree().quit(0)
		return
	# R3-7 exact set-difference deletion
	var deleted_png := 0
	var deleted_import := 0
	for rel: String in orphan_png:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://" + rel))
		deleted_png += 1
	for rel: String in orphan_import:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://" + rel))
		deleted_import += 1
	# R3-8 post equality re-scan
	var after_png := {}
	var after_dir := DirAccess.open(STORE_DIR)
	var after_unexpected := 0
	for file: String in after_dir.get_files():
		if file.ends_with(".png"):
			after_png[STORE_DIR_PREFIX + file] = true
		elif not file.ends_with(".png.import"):
			after_unexpected += 1
	var after_missing := 0
	var after_orphan := 0
	for rel: String in referenced.keys():
		if not after_png.has(rel):
			after_missing += 1
	for rel: String in after_png.keys():
		if not referenced.has(rel):
			after_orphan += 1
	print("STORE_GC_RESULT deleted_png=%d deleted_import=%d after_store=%d referenced=%d after_missing=%d after_orphan=%d after_unexpected=%d sets_equal=%s" % [
		deleted_png, deleted_import, after_png.size(), referenced.size(),
		after_missing, after_orphan, after_unexpected,
		str(after_png.keys() == referenced.keys()),
	])
	get_tree().quit(
		0 if (after_missing == 0 and after_orphan == 0
		and after_unexpected == 0) else 1
	)
