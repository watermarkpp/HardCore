extends Node

const MAP_IDS := ["orc_tomb_2", "orc_tomb_3"]
const RUNTIME_IDS := [218, 221]


func _ready() -> void:
	var runtimes: Array[Dictionary] = []
	for index in MAP_IDS.size():
		var map_id: String = MAP_IDS[index]
		var loaded := MapEditorRuntimeMapService.load_runtime(
			MapEditorBuildRuntimeService.default_runtime_path(map_id)
		)
		assert(loaded.ok, "%s:%s" % [map_id, loaded.get("errors", [])])
		var runtime: Dictionary = loaded.runtime
		assert(str(runtime.source.map_id) == map_id)
		assert(int(runtime.design.design_size[0]) == 38)
		assert(int(runtime.design.design_size[1]) == 38)
		assert(runtime.semantics.map_entrance_points.is_empty())
		assert(runtime.semantics.map_exit_points.size() == [2, 1][index])
		assert(runtime.instances.size() > 0)
		runtimes.append(runtime)
		var source := MapEditorLoadService.load_document(
			MapEditorSaveService.default_path(map_id)
		)
		assert(source.ok)
		assert(int(source.document.runtime_map_id) == RUNTIME_IDS[index])
		assert(bool(source.document.editor_meta.runtime_approved))
		if map_id == "orc_tomb_3":
			assert(source.document.design.wall_loops.size() == 1)
			assert(
				str(source.document.design.wall_loops[0].visual_render_contract)
				== "segmented_isometric_depth_v1"
			)
	var forward := _pair_endpoint(runtimes[0], "orc_tomb_2_3_pair_v1")
	var reverse := _pair_endpoint(runtimes[1], "orc_tomb_2_3_pair_v1")
	assert(str(forward.target_map_key) == "orc_tomb_3")
	assert(str(forward.target_portal_id) == str(reverse.semantic_id))
	assert(str(reverse.target_map_key) == "orc_tomb_2")
	assert(str(reverse.target_portal_id) == str(forward.semantic_id))
	print("ORC_TOMB_EDITOR_RUNTIME_INTEGRATION_PASS maps=2 pair=bidirectional")
	get_tree().quit(0)


func _pair_endpoint(runtime: Dictionary, pair_id: String) -> Dictionary:
	for endpoint: Dictionary in runtime.semantics.map_exit_points:
		if str(endpoint.get("connection_pair_id", "")) == pair_id:
			return endpoint
	assert(false, pair_id)
	return {}
