extends RefCounted
const Original := preload("res://scripts/map_editor/map_diamond_camera_constraint_service.gd")
const SOURCE_PATH := "res://scripts/map_editor/map_diamond_camera_constraint_service.gd"
const ORIGINAL_FIELDS: Array[String] = ["_cached_design_size", "_cached_viewport_half", "_cached_zoom", "_cached_entry", "_cache_valid", "_strict_cache_builds", "_last_visibility_conflict", "_clip_scratch_a", "_clip_scratch_b"]
static func capture_original_main() -> Dictionary:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	var fields: Dictionary = {}
	var original_script: Script = Original
	for field: String in ORIGINAL_FIELDS: fields[field] = original_script.get(field)
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var captured: Dictionary = graph.capture({"contract_id":"world.camera.constraint.original_handoff.v1", "source_sha256":FileAccess.get_sha256(SOURCE_PATH),"fields":fields},true,false)
	return captured.value if captured.success else {}
