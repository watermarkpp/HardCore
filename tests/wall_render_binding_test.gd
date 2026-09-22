extends Node

const Service := preload("res://scripts/map_editor/map_editor_wall_render_plan_runtime_service.gd")
const Geometry := preload("res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd")


func _ready() -> void:
	var checked := 0
	var failures: Array[String] = []
	for map_id: int in MapEditorRuntimeBridge.released_map_ids():
		var path := MapEditorRuntimeBridge.runtime_path(map_id)
		var map_key := path.get_file().replace(".runtime.json", "")
		var plan_path := "res://assets/data/runtime/map_editor/wall_render_plans/%s.wall_render_plan.json" % map_key
		if not FileAccess.file_exists(plan_path): continue
		var runtime := MapEditorRuntimeBridge.load_map(map_id)
		var size: Array = runtime.design.design_size
		var result := Service.load_candidate(plan_path, path, map_key,
			Vector2i(int(size[0]), int(size[1])), Geometry.sorted_draw_commands(
				runtime.get("instances", []), runtime.get("visual_asset_snapshot", {})))
		checked += 1
		if not bool(result.get("ok", false)):
			failures.append("%s: %s" % [map_key, result.get("reason", "")])
	for failure: String in failures: print("WALL_BINDING_FAILURE ", failure)
	print("WALL_BINDING checked=%d failures=%d" % [checked, failures.size()])
	assert(checked == 60, "formal optimized-map coverage changed")
	if failures.is_empty():
		print("WALL_RENDER_BINDING_PASS")
		get_tree().quit(0)
	else:
		get_tree().quit(1)
