extends Node

const RUNTIME_MAP_IDS := [4, 217, 218, 221, 268, 313, 314, 315, 406, 408, 1578]
const EPSILON := 0.0001
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")


func _ready() -> void:
	_test_32_direction_projection_roundtrip()
	_test_all_runtime_maps_use_read_only_v1_adapter()
	_test_runtime_bridge_gu_fields()
	_test_portal_gu_distance_contract()
	_test_path_step_cost_gu()
	print("MAP_COMBAT_UNIT_CONTRACT_PASS")
	get_tree().quit()


func _test_32_direction_projection_roundtrip() -> void:
	var design_size := Vector2i(257, 193)
	var center := (Vector2(design_size) - Vector2.ONE) * 0.5
	for index in range(32):
		var angle := TAU * float(index) / 32.0
		var delta_ground_gu := Vector2(cos(angle), sin(angle))
		var expected_screen_px := Vector2(
			(delta_ground_gu.x - delta_ground_gu.y) * 32.0,
			(delta_ground_gu.x + delta_ground_gu.y) * 16.0
		)
		var screen_px := MapEditorCoordinate.ground_delta_gu_to_screen_delta_px(
			delta_ground_gu
		)
		assert(screen_px.distance_to(expected_screen_px) <= EPSILON)
		assert(MapCoordinateMapper.source_delta_to_world(
			delta_ground_gu
		).distance_to(screen_px) <= EPSILON)
		var restored_delta_gu := MapEditorCoordinate.screen_delta_px_to_ground_delta_gu(
			screen_px
		)
		assert(restored_delta_gu.distance_to(delta_ground_gu) <= EPSILON)
		var ground_position_gu := center + delta_ground_gu * 17.25
		var position_px := MapCoordinateMapper.ground_position_gu_to_screen_position_px(
			ground_position_gu, design_size
		)
		assert(MapCoordinateMapper.source_to_world(
			ground_position_gu, design_size
		).distance_to(position_px) <= EPSILON)
		assert(MapEditorCoordinate.tile_to_world(
			ground_position_gu, design_size
		).distance_to(position_px) <= EPSILON)
		var restored_position_gu := MapCoordinateMapper.screen_position_px_to_ground_position_gu(
			position_px, design_size
		)
		assert(restored_position_gu.distance_to(ground_position_gu) <= EPSILON)


func _test_all_runtime_maps_use_read_only_v1_adapter() -> void:
	for runtime_map_id: int in RUNTIME_MAP_IDS:
		var path := MapEditorRuntimeBridge.runtime_path(runtime_map_id)
		var raw_before := _read_text(path)
		assert(not raw_before.is_empty(), path)
		var raw_runtime: Variant = JSON.parse_string(raw_before)
		assert(raw_runtime is Dictionary)
		assert(int(raw_runtime.get("runtime_schema_version", -1)) == 1)
		var loaded := MapEditorRuntimeMapService.load_runtime(path)
		assert(loaded.ok, "%s:%s" % [path, loaded.errors])
		var runtime: Dictionary = loaded.runtime
		assert(runtime.runtime_schema_version == MapEditorBuildRuntimeService.RUNTIME_SCHEMA_VERSION)
		assert(runtime.source_runtime_schema_version == 1)
		assert(runtime.unit_contract_id == GroundUnitSpaceScript.CONTRACT_ID)
		assert(runtime.projection_contract_id == GroundUnitSpaceScript.PROJECTION_CONTRACT_ID)
		var raw_size: Array = runtime.design.design_size
		var size := Vector2(float(raw_size[0]), float(raw_size[1]))
		for ground_position_gu: Vector2 in [
			Vector2.ZERO,
			(size - Vector2.ONE) * 0.5,
			size - Vector2.ONE,
			Vector2(size.x * 0.271, size.y * 0.613),
		]:
			var screen_position_px := MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(
				runtime, ground_position_gu
			)
			var restored_ground_gu := MapEditorRuntimeBridge.screen_position_px_to_ground_position_gu(
				runtime, screen_position_px
			)
			assert(restored_ground_gu.distance_to(ground_position_gu) <= EPSILON)
		_assert_runtime_semantics_use_formal_units(runtime)
		assert(_read_text(path) == raw_before, "v1 runtime was modified: %s" % path)


func _assert_runtime_semantics_use_formal_units(runtime: Dictionary) -> void:
	for layer_name: String in runtime.semantics:
		for entry: Dictionary in runtime.semantics[layer_name]:
			var kind := str(entry.get("kind", ""))
			if kind in ["monster_spawn", "boss_spawn", "safe_area", "light", "region_trigger"]:
				assert(entry.has("radius_gu"))
				assert(not entry.has("radius_tiles"))
			if kind in ["safe_area", "light", "region_trigger"]:
				assert(entry.has("polygon_ground_gu"))
				assert(not entry.has("polygon_tiles"))
			if kind in ["door", "map_exit"]:
				assert(entry.has("return_unlock_distance_gu"))
				assert(not entry.has("return_unlock_distance_tiles"))


func _test_runtime_bridge_gu_fields() -> void:
	MapEditorRuntimeBridge._runtime_cache.clear()
	var runtime := MapEditorRuntimeBridge.load_map(MapEditorRuntimeBridge.BICH_MAP_ID)
	assert(not runtime.is_empty())
	var content := MapEditorRuntimeBridge.game_content_for_map(
		MapEditorRuntimeBridge.BICH_MAP_ID
	)
	assert(not content.safe_areas.is_empty())
	var safe: Dictionary = content.safe_areas[0]
	assert(is_equal_approx(float(safe.radius_gu), 9.0))
	assert(safe.center_ground_gu is Vector2)
	assert(safe.center is Vector2)
	assert(MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(
		runtime, safe.center_ground_gu
	).distance_to(safe.center) <= EPSILON)
	assert(not content.spawns.is_empty())
	assert(content.runtime_home_position_ground_gu is Vector2)
	assert(MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(
		runtime, content.runtime_home_position_ground_gu
	).distance_to(content.runtime_home_position) <= EPSILON)
	assert(MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(
		runtime, content.map_center_ground_gu
	).distance_to(content.map_center_world) <= EPSILON)
	var spawn: Dictionary = content.spawns[0]
	assert(spawn.has("position_ground_gu"))
	assert(spawn.has("radius_gu"))
	assert(is_equal_approx(float(spawn.radius_gu), float(spawn.radius_tiles)))
	assert(MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(
		runtime, spawn.position_ground_gu
	).distance_to(spawn.position) <= EPSILON)
	var synthetic_polygon := [[2.0, 3.0], [5.0, 3.0], [5.0, 7.0]]
	var projected := MapEditorRuntimeBridge.ground_polygon_gu_to_screen_polygon_px(
		runtime, synthetic_polygon
	)
	assert(projected.size() == synthetic_polygon.size())
	for index in projected.size():
		var expected := MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(
			runtime,
			Vector2(synthetic_polygon[index][0], synthetic_polygon[index][1])
		)
		assert(projected[index].distance_to(expected) <= EPSILON)


func _test_portal_gu_distance_contract() -> void:
	var endpoint := {
		"portal_contract_id": MapPortalRuntimeService.PORTAL_CONTRACT_ID,
		"target_configured": true,
		"target_map_id": 313,
		"target_map_key": "wooma_temple_1",
		"target_portal_id": "map_exit_000001",
		"target_tile": [1, 2],
		"return_unlock_distance_gu": 1.5,
	}
	var request := MapPortalRuntimeService.travel_request(endpoint)
	assert(request.ok)
	assert(is_equal_approx(float(request.return_unlock_distance_gu), 1.5))
	assert(is_equal_approx(float(request.return_unlock_distance_tiles), 1.5))
	var state := MapPortalTravelGuard.new_state()
	MapPortalTravelGuard.finish_arrival(state, "portal.a", 1000, Vector2.ZERO)
	assert(not MapPortalTravelGuard.can_activate(
		state, "portal.a", 1500, Vector2(1.49, 0.0), true
	))
	assert(MapPortalTravelGuard.can_activate(
		state, "portal.a", 1500, Vector2(1.5, 0.0), true
	))


func _test_path_step_cost_gu() -> void:
	assert(is_equal_approx(MapEditorCoordinate.path_step_cost_gu(Vector2i(1, 0)), 1.0))
	assert(is_equal_approx(MapCoordinateMapper.path_step_cost_gu(Vector2i(0, -1)), 1.0))
	assert(is_equal_approx(
		MapEditorCoordinate.path_step_cost_gu(Vector2i(1, 1)), sqrt(2.0)
	))


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, path)
	var value := file.get_as_text()
	file.close()
	return value
