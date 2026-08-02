extends Node

const RUNTIME_MAP_IDS := [4, 217, 218, 221, 268, 313, 314, 315, 406, 408, 1578]
const EPSILON := 0.0001
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const UnitLegacyAdapter := preload(
	"res://scripts/map_editor/map_editor_unit_legacy_adapter.gd"
)


func _ready() -> void:
	_test_32_direction_projection_roundtrip()
	_test_editor_v4_unit_adapter()
	_test_legacy_unit_names_are_confined_to_adapter()
	_test_formal_map_coordinate_apis()
	_test_all_runtime_maps_use_read_only_v1_adapter()
	_test_runtime_bridge_gu_fields()
	_test_portal_gu_distance_contract()
	_test_path_step_cost_gu()
	print("MAP_COMBAT_UNIT_CONTRACT_PASS")
	get_tree().quit()


func _test_editor_v4_unit_adapter() -> void:
	var legacy_document := MapEditorTypes.new_map(
		"legacy_unit_adapter", 990050, "Legacy", Vector2i(32, 32)
	)
	legacy_document["schema_version"] = 4
	legacy_document.layers.monster_spawn = [{
		"kind": "monster_spawn",
		"semantic_id": "monster_spawn_000001",
		"tile": [4, 5],
		"radius_tiles": 3,
	}]
	legacy_document.layers.safe_area = [{
		"kind": "safe_area",
		"semantic_id": "safe_area_000001",
		"tile": [8, 8],
		"shape": "polygon",
		"radius_tiles": 0,
		"polygon_tiles": [[7, 7], [9, 7], [9, 9], [7, 9]],
	}]
	legacy_document.layers.map_exit_points = [{
		"kind": "map_exit",
		"semantic_id": "map_exit_000001",
		"tile": [10, 10],
		"return_unlock_distance_tiles": 1.5,
	}]
	var upgraded := MapEditorTypes.upgrade_document(legacy_document)
	assert(upgraded.schema_version == MapEditorTypes.SCHEMA_VERSION)
	assert(upgraded.editor_meta.source_editor_schema_version == 4)
	assert(upgraded.editor_meta.unit_legacy_adapter_id == UnitLegacyAdapter.CONTRACT_ID)
	assert(is_equal_approx(float(upgraded.layers.monster_spawn[0].radius_gu), 3.0))
	assert(not upgraded.layers.monster_spawn[0].has("radius_tiles"))
	assert(upgraded.layers.safe_area[0].polygon_ground_gu.size() == 4)
	assert(not upgraded.layers.safe_area[0].has("polygon_tiles"))
	assert(is_equal_approx(
		float(upgraded.layers.map_exit_points[0].return_unlock_distance_gu),
		1.5
	))
	assert(not upgraded.layers.map_exit_points[0].has(
		"return_unlock_distance_tiles"
	))


func _test_legacy_unit_names_are_confined_to_adapter() -> void:
	var formal_runtime_sources := [
		"res://scripts/layers/runtime/map_editor_runtime_bridge.gd",
		"res://scripts/map_editor/map_editor_build_runtime_service.gd",
		"res://scripts/map_editor/map_editor_connection_policy_service.gd",
		"res://scripts/map_editor/map_editor_runtime_map_service.gd",
		"res://scripts/map_editor/map_portal_runtime_service.gd",
		"res://scripts/map_editor/map_portal_travel_guard.gd",
		"res://tools/map_editor/apply_bich_content_1.py",
		"res://tools/map_editor/build_bich_map_1.gd",
		"res://tools/map_editor/build_bich_map_2.gd",
		"res://tools/map_editor/clone_wooma_temple_layers.gd",
		"res://tools/map_editor/finalize_bich_wooma_connection.gd",
		"res://tools/map_editor/make_wooma_temple_route_bidirectional.gd",
		"res://tools/map_editor/resize_bich_workspace.py",
	]
	var legacy_unit_names := [
		"radius_tiles",
		"polygon_tiles",
		"return_unlock_distance_tiles",
	]
	for source_path: String in formal_runtime_sources:
		var source := _read_text(source_path)
		for legacy_name: String in legacy_unit_names:
			assert(
				not source.contains(legacy_name),
				"legacy unit bypass in %s: %s" % [source_path, legacy_name]
			)
	var adapter_source := _read_text(
		"res://scripts/map_editor/map_editor_unit_legacy_adapter.gd"
	)
	for legacy_name: String in legacy_unit_names:
		assert(adapter_source.contains(legacy_name))


func _test_formal_map_coordinate_apis() -> void:
	var bridge_source := _read_text(
		"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
	)
	for removed_signature: String in [
		"static func tile_to_world(",
		"static func world_to_tile(",
		"static func cell_to_world(",
	]:
		assert(not bridge_source.contains(removed_signature))
	assert(bridge_source.contains(
		"static func grid_cell_to_screen_position_px("
	))
	for removed_signature: String in [
		"static func home_position(",
		"static func portal_position(",
	]:
		assert(not bridge_source.contains(removed_signature))
	for formal_signature: String in [
		"static func home_screen_position_px(",
		"static func home_position_ground_gu(",
		"static func portal_screen_position_px(",
		"static func portal_position_ground_gu(",
	]:
		assert(bridge_source.contains(formal_signature))
	for removed_output_fragment: String in [
		"\"runtime_home_position\":",
		"\"map_center_world\":",
		"\"position\": grid_cell_to_screen_position_px(",
	]:
		assert(not bridge_source.contains(removed_output_fragment))
	var coordinate_source := _read_text(
		"res://scripts/map_editor/map_editor_coordinate.gd"
	)
	for removed_signature: String in [
		"static func tile_to_world(",
		"static func world_to_tile(",
		"static func cell_center_to_world(",
		"static func cell_polygon_world(",
		"static func world_to_cell(",
	]:
		assert(not coordinate_source.contains(removed_signature))
	for formal_signature: String in [
		"static func ground_position_gu_to_screen_position_px(",
		"static func screen_position_px_to_ground_position_gu(",
		"static func grid_cell_to_screen_position_px(",
		"static func grid_cell_polygon_screen_px(",
		"static func screen_position_px_to_grid_cell(",
	]:
		assert(coordinate_source.contains(formal_signature))
	for runtime_source_path: String in [
		"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd",
		"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd",
	]:
		var runtime_source := _read_text(runtime_source_path)
		for forbidden_call: String in [
			"MapEditorCoordinate.tile_to_world(",
			"MapEditorCoordinate.world_to_tile(",
			"MapEditorCoordinate.cell_center_to_world(",
			"MapEditorCoordinate.cell_polygon_world(",
			"MapEditorCoordinate.world_to_cell(",
		]:
			assert(
				not runtime_source.contains(forbidden_call),
				"ambiguous coordinate bypass in %s: %s"
				% [runtime_source_path, forbidden_call]
			)


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
		assert(MapEditorCoordinate.ground_position_gu_to_screen_position_px(
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
		assert(runtime.unit_legacy_adapter_id == UnitLegacyAdapter.CONTRACT_ID)
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
	for runtime_map_id: int in RUNTIME_MAP_IDS:
		_assert_runtime_bridge_output_units(runtime_map_id)
	var runtime := MapEditorRuntimeBridge.load_map(MapEditorRuntimeBridge.BICH_MAP_ID)
	assert(not runtime.is_empty())
	var content := MapEditorRuntimeBridge.game_content_for_map(
		MapEditorRuntimeBridge.BICH_MAP_ID
	)
	assert(not content.safe_areas.is_empty())
	var safe: Dictionary = content.safe_areas[0]
	assert(is_equal_approx(float(safe.radius_gu), 9.0))
	assert(safe.center_ground_gu is Vector2)
	assert(not safe.has("center") and not safe.has("radius") and not safe.has("radius_tiles"))
	assert(not content.spawns.is_empty())
	assert(content.runtime_home_position_ground_gu is Vector2)
	assert(MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(
		runtime, content.runtime_home_position_ground_gu
	).distance_to(content.runtime_home_screen_position_px) <= EPSILON)
	assert(MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(
		runtime, content.map_center_ground_gu
	).distance_to(content.map_center_screen_position_px) <= EPSILON)
	var spawn: Dictionary = content.spawns[0]
	assert(spawn.has("position_ground_gu"))
	assert(spawn.has("screen_position_px"))
	assert(spawn.has("radius_gu"))
	assert(not spawn.has("radius_tiles"))
	assert(MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(
		runtime, spawn.position_ground_gu
	).distance_to(spawn.screen_position_px) <= EPSILON)
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


func _assert_runtime_bridge_output_units(runtime_map_id: int) -> void:
	var runtime := MapEditorRuntimeBridge.load_map(runtime_map_id)
	var content := MapEditorRuntimeBridge.game_content_for_map(runtime_map_id)
	assert(not runtime.is_empty(), "runtime map %d" % runtime_map_id)
	assert(
		content.runtime_output_contract_id
		== MapEditorRuntimeBridge.RUNTIME_OUTPUT_CONTRACT_ID
	)
	assert(content.runtime_home_position_ground_gu is Vector2)
	assert(content.runtime_home_screen_position_px is Vector2)
	assert(content.map_center_ground_gu is Vector2)
	assert(content.map_center_screen_position_px is Vector2)
	assert(MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(
		runtime, content.map_center_ground_gu
	).distance_to(content.map_center_screen_position_px) <= EPSILON)
	for forbidden_key: String in [
		"runtime_home_position",
		"map_center_world",
	]:
		assert(not content.has(forbidden_key))
	for group_name: String in ["spawns", "bosses", "npcs", "portals"]:
		for entry: Dictionary in content[group_name]:
			assert(entry.has("position_ground_gu"), "%d/%s GU position" % [runtime_map_id, group_name])
			assert(entry.has("screen_position_px"), "%d/%s PX position" % [runtime_map_id, group_name])
			assert(not entry.has("position"), "%d/%s ambiguous position" % [runtime_map_id, group_name])
			assert(MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(
				runtime, entry.position_ground_gu
			).distance_to(entry.screen_position_px) <= EPSILON)


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
	assert(not request.has("return_unlock_distance_tiles"))
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
