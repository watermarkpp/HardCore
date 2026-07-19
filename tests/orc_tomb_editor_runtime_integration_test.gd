extends Node

const MAP_IDS := ["orc_tomb_2", "orc_tomb_3"]
const RUNTIME_IDS := [218, 221]


func _ready() -> void:
	var runtimes: Array[Dictionary] = []
	for index in MAP_IDS.size():
		var map_id: String = MAP_IDS[index]
		var path := MapEditorBuildRuntimeService.default_runtime_path(map_id)
		var loaded := MapEditorRuntimeMapService.load_runtime(path)
		assert(loaded.ok, "%s:%s" % [map_id, loaded.get("errors", [])])
		var runtime: Dictionary = loaded.runtime
		assert(str(runtime.source.map_id) == map_id)
		assert(int(runtime.design.design_size[0]) == 38)
		assert(int(runtime.design.design_size[1]) == 38)
		assert(not str(runtime.get("build_sha256", "")).is_empty())
		assert(runtime.semantics.map_entrance_points.size() == 1)
		assert(runtime.semantics.map_exit_points.size() == (1 if index == 0 else 0))
		assert(runtime.instances.size() > 0)
		runtimes.append(runtime)
		var source := MapEditorLoadService.load_document(MapEditorSaveService.default_path(map_id))
		assert(source.ok, "%s_source:%s" % [map_id, source.get("errors", [])])
		assert(int(source.document.runtime_map_id) == RUNTIME_IDS[index])
		assert(bool(source.document.editor_meta.runtime_approved))
		if map_id == "orc_tomb_3":
			assert(source.document.design.wall_loops.size() == 1)
			var wall_loop: Dictionary = source.document.design.wall_loops[0]
			assert(
				str(wall_loop.visual_render_contract)
				== "segmented_isometric_depth_v1"
			)
			assert(
				str(wall_loop.topology_status)
				== "user_customized_opening"
			)
			assert(not bool(wall_loop.strict_closed_perimeter))

	var floor_two_exit: Dictionary = runtimes[0].semantics.map_exit_points[0]
	var floor_three_entrance: Dictionary = runtimes[1].semantics.map_entrance_points[0]
	assert(str(floor_two_exit.target_map_id) == "orc_tomb_3")
	assert(str(floor_two_exit.target_entrance_id) == str(floor_three_entrance.entrance_id))
	assert(str(runtimes[1].design.wall_loops[0].visual_render_contract) == "segmented_isometric_depth_v1")
	print("ORC_TOMB_EDITOR_RUNTIME_INTEGRATION_PASS maps=2 links=1 final_exits=0")
	get_tree().quit(0)
