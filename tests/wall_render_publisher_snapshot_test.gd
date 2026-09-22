extends Node

## Runs the complete publisher against one existing runtime release. Only
## derived output goes to a unique test directory; catalog drift is in memory.
const Publisher := preload("res://scripts/map_editor/map_editor_wall_render_publish_service.gd")
const Geometry := preload("res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd")
const Compiler := preload("res://scripts/map_editor/map_editor_wall_render_compiler.gd")
const MAP_KEY := "bich_corpse_king_hall"
const ASSET_ID := "cave_granite_straight_x_l3_v03"
const RUNTIME_PATH := "res://assets/data/runtime/map_editor/bich_corpse_king_hall.runtime.json"
const FORMAL_PLAN_PATH := "res://assets/data/runtime/map_editor/wall_render_plans/bich_corpse_king_hall.wall_render_plan.json"
const TEST_PARENT := "res://outputs/test_logs"

var _failures: Array[String] = []
var _protected_hashes: Dictionary = {}
var _fixture_root := ""
var _fixture_owned := false
var _original_catalog_asset: Dictionary = {}
var _catalog_changed := false
var _plan_sha := ""


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_failures.append(message)
	return condition


func _run() -> void:
	_run_checks()
	# Do not assert before cleanup: failed publication or the negative control
	# must still restore the shared catalog and remove only our own outputs.
	if _catalog_changed:
		MapAssetCatalogService._asset_index[ASSET_ID] = _original_catalog_asset
	_cleanup_fixture()
	for path: String in _protected_hashes:
		_check(FileAccess.get_sha256(path) == str(_protected_hashes[path]),
			"formal input/artifact changed: %s" % path)
	for failure: String in _failures:
		push_error("WALL_RENDER_PUBLISHER_SNAPSHOT: " + failure)
	if _failures.is_empty():
		print("WALL_RENDER_PUBLISHER_SNAPSHOT_PASS map=%s live_catalog_negative_control=true repeat_plan_sha=%s formal_files_unchanged=%d fixture_removed=true" % [
			MAP_KEY, _plan_sha, _protected_hashes.size(),
		])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _run_checks() -> void:
	for path: String in [
		RUNTIME_PATH,
		FORMAL_PLAN_PATH,
		"res://assets/data/runtime/map_editor/map_runtime_release_registry.json",
		"res://map_editor_workspace/bich_corpse_king_hall/bich_corpse_king_hall.editor.json",
	]:
		if not _protect(path):
			return
	var runtime_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(RUNTIME_PATH))
	if not _check(runtime_value is Dictionary, "published runtime must parse"):
		return
	var runtime: Dictionary = runtime_value
	var snapshot: Dictionary = runtime.get("visual_asset_snapshot", {})
	if not _check(snapshot.get("assets", {}).has(ASSET_ID), "published fixture wall must have a frozen snapshot"):
		return
	var formal_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(FORMAL_PLAN_PATH))
	if not _check(formal_value is Dictionary, "formal plan must parse"):
		return
	var formal_plan: Dictionary = formal_value
	for record: Dictionary in (formal_plan.get("atlas_pages", []) + formal_plan.get("shadow_chunks", [])):
		if not _protect(_resource_path(str(record.get("path", "")))):
			return
	for path: String in formal_plan.get("source_image_sha256", {}):
		if not _protect(_resource_path(path)):
			return
	var instances: Array = runtime.get("instances", [])
	var expected_digest := Compiler.commands_digest(Geometry.sorted_draw_commands(instances, snapshot))
	_check(expected_digest == str(formal_plan.get("source_commands_sha256", "")),
		"formal plan must bind the production runtime snapshot")
	_fixture_root = "%s/wall_render_publisher_snapshot_%d_%d" % [
		TEST_PARENT, OS.get_process_id(), Time.get_ticks_usec(),
	]
	if not _check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_fixture_root)),
		"test output directory must not already exist"):
		return
	_fixture_owned = true
	var publisher := Publisher.new()
	publisher.plan_directory = _fixture_root.path_join("plans")
	publisher.store_directory = _fixture_root.path_join("store")
	publisher.staging_directory = _fixture_root.path_join("staging")
	var first_result := publisher.publish_map(MAP_KEY)
	if not _check(not first_result.has("error"), "first publication failed: %s" % first_result):
		return
	var plan_path := publisher.plan_directory.path_join(MAP_KEY + ".wall_render_plan.json")
	var first_bytes := FileAccess.get_file_as_bytes(plan_path)
	var first_value: Variant = JSON.parse_string(first_bytes.get_string_from_utf8())
	if not _check(first_value is Dictionary and not first_bytes.is_empty(), "first committed plan must parse"):
		return
	var first_plan: Dictionary = first_value
	_check(str(first_plan.get("source_runtime_json_sha256", "")) == str(_protected_hashes[RUNTIME_PATH]),
		"published plan must bind exact runtime bytes")
	_check(str(first_plan.get("source_commands_sha256", "")) == expected_digest,
		"published plan must use production snapshot command digest")
	var first_store_files := DirAccess.get_files_at(publisher.store_directory)
	first_store_files.sort()
	# The negative control proves the drift changes the old one-argument
	# command builder. No catalog or calibration file is changed on disk.
	MapAssetCatalogService.load_catalog()
	if not _check(MapAssetCatalogService._asset_index.has(ASSET_ID), "live fixture wall must be indexed"):
		return
	_original_catalog_asset = MapAssetCatalogService._asset_index[ASSET_ID]
	var changed_asset := _original_catalog_asset.duplicate(true)
	var parts: Array = changed_asset.get("render_parts", [])
	if not _check(not parts.is_empty(), "fixture wall must have real render parts"):
		return
	var first_part: Dictionary = parts[0]
	var anchor: Array = first_part.get("anchor", [])
	if not _check(anchor.size() == 2, "fixture wall part must have a two-axis anchor"):
		return
	first_part["anchor"] = [float(anchor[0]) + 37.0, float(anchor[1]) + 19.0]
	MapAssetCatalogService._asset_index[ASSET_ID] = changed_asset
	_catalog_changed = true
	var unpinned_digest := Compiler.commands_digest(Geometry.sorted_draw_commands(instances))
	_check(unpinned_digest != expected_digest, "negative control must expose live-catalog command drift")
	_check(Compiler.commands_digest(Geometry.sorted_draw_commands(instances, snapshot)) == expected_digest,
		"production snapshot commands must remain unchanged under catalog drift")
	var second_result := publisher.publish_map(MAP_KEY)
	if not _check(not second_result.has("error"), "second publication failed: %s" % second_result):
		return
	var second_bytes := FileAccess.get_file_as_bytes(plan_path)
	_check(first_bytes == second_bytes, "republication changed final plan bytes after live catalog drift")
	var second_store_files := DirAccess.get_files_at(publisher.store_directory)
	second_store_files.sort()
	_check(first_store_files == second_store_files, "republication emitted different derived PNGs")
	_check(not FileAccess.file_exists(plan_path + ".tmp"), "successful publication left an uncommitted plan")
	_plan_sha = FileAccess.get_sha256(plan_path)


func _protect(path: String) -> bool:
	if not _check(FileAccess.file_exists(path), "required formal file missing: %s" % path):
		return false
	_protected_hashes[path] = FileAccess.get_sha256(path)
	return true


func _resource_path(path: String) -> String:
	return path if path.begins_with("res://") else "res://" + path


func _cleanup_fixture() -> void:
	if not _fixture_owned:
		return
	var parent_absolute := ProjectSettings.globalize_path(TEST_PARENT).simplify_path()
	var root_absolute := ProjectSettings.globalize_path(_fixture_root).simplify_path()
	if not _check(root_absolute.get_base_dir() == parent_absolute
		and root_absolute.get_file().begins_with("wall_render_publisher_snapshot_"),
		"refusing cleanup outside this test's exact output directory"):
		return
	# Three known flat directories only. Never recursively traverse a tree or
	# delete unexpected nested directories created by another process.
	for child: String in ["plans", "store", "staging"]:
		var directory := root_absolute.path_join(child)
		if not DirAccess.dir_exists_absolute(directory):
			continue
		if not _check(DirAccess.get_directories_at(directory).is_empty(), "unexpected nested test output: %s" % directory):
			continue
		for filename: String in DirAccess.get_files_at(directory):
			_check(DirAccess.remove_absolute(directory.path_join(filename)) == OK,
				"could not remove test output: %s" % filename)
		_check(DirAccess.remove_absolute(directory) == OK, "could not remove test output directory: %s" % child)
	if DirAccess.dir_exists_absolute(root_absolute):
		_check(DirAccess.remove_absolute(root_absolute) == OK, "could not remove exact test root")
	_check(not DirAccess.dir_exists_absolute(root_absolute), "test output root remains")
