extends Node

const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)
const EditorCoordinate := preload(
	"res://scripts/map_editor/map_editor_coordinate.gd"
)
const WorldBackgroundScript := preload("res://scripts/world_background.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const MapCoordinateMapperScript := preload("res://scripts/map_coordinate_mapper.gd")
const MapEditorRuntimeBridgeScript := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)

const TEST_RUNTIME_MAP_ID := 991001
const TEST_REGISTERED_RUNTIME_MAP_ID := 911103
const TEST_SIZE := Vector2i(4, 4)
const TEST_BUILD_SHA := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"


class BatchProbe:
	extends Node

	var batch_calls := 0
	var point_calls := 0
	var blocked := false
	var observed_center := Vector2.INF
	var observed_radius := -1.0

	func is_environment_actor_blocked(
		center_world_px: Vector2,
		collision_radius_px: float
	) -> bool:
		batch_calls += 1
		observed_center = center_world_px
		observed_radius = collision_radius_px
		return blocked

	func is_environment_point_blocked(_world_position: Vector2) -> bool:
		point_calls += 1
		return blocked


class PointProbe:
	extends Node

	var points: Array = []
	var blocked_points: Dictionary = {}

	func is_environment_point_blocked(world_position: Vector2) -> bool:
		points.append(world_position)
		return blocked_points.has(world_position)


class SegmentProbe:
	extends Node

	var calls := 0
	var blocked := false
	var last_source := Vector2.INF
	var last_target := Vector2.INF
	var last_step := -1.0

	func is_environment_segment_blocked_ground(
		source_ground_gu: Vector2,
		target_ground_gu: Vector2,
		step_gu: float
	) -> bool:
		calls += 1
		last_source = source_ground_gu
		last_target = target_ground_gu
		last_step = step_gu
		return blocked


class SegmentEnemy:
	extends EnemyActor

	func _world_direct_space_state() -> PhysicsDirectSpaceState2D:
		return null


class CollisionBuildProbe:
	extends WorldBackground

	var runtime_override: Dictionary = {}

	func _runtime_data_for(_map_id: int) -> Dictionary:
		return runtime_override


class ReferenceProfileProbe:
	extends WorldBackground

	var profile_override: Dictionary = {}

	func environment_profile() -> Dictionary:
		return profile_override


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var runtime := _make_runtime()
	var compile_result := CollisionGeometry.compile_runtime_collision(
		runtime,
		TEST_RUNTIME_MAP_ID,
	)
	assert(bool(compile_result.get("ok", false)), "valid runtime failed compilation")
	var compiled: Dictionary = compile_result.get("snapshot", {})
	assert(compiled.get("runtime_map_id", -1) == TEST_RUNTIME_MAP_ID)
	assert(compiled.get("blocked_count", -1) == 3)
	assert(compiled.get("boundary_world", PackedVector2Array()).size() == 4)
	assert(compiled.get("outer_boundary_world", PackedVector2Array()).size() == 4)
	_assert_real_formal_runtime_compiles()
	_assert_cell_run_parity(runtime, compiled)
	_assert_point_parity(runtime, compiled)
	_assert_segment_parity(runtime, compiled)
	_assert_formal_invalid_fail_closed(runtime)
	_assert_manual_shapes_are_not_authority(runtime)
	_assert_reference_segment_uses_absolute_projection()
	_assert_build_rebuild_invalidates_collision_authority()
	_assert_actor_batch_priority()
	_assert_actor_legacy_order()
	_assert_background_actor_and_segment(compiled)
	_assert_enemy_segment_path()
	_assert_hot_path_structure()
	print(
		"MONSTER_ENVIRONMENT_COLLISION_BATCH_PASS "
		+ "compiled=1 point_parity=random+boundary segment_parity=1 "
		+ "actor_batch_calls=1 enemy_segment_calls=1 invalid_fail_closed=1"
	)
	get_tree().quit(0)


func _make_runtime() -> Dictionary:
	return {
		"build_sha256": TEST_BUILD_SHA,
		"source": {
			"map_id": "r3_environment_collision_test",
			"runtime_map_id": TEST_RUNTIME_MAP_ID,
		},
		"design": {"design_size": [TEST_SIZE.x, TEST_SIZE.y]},
		"collision": {
			"coordinate_contract_id": CollisionGeometry.CONTRACT_ID,
			"physics_source_id": CollisionGeometry.PHYSICS_SOURCE_ID,
			"blocked_tiles": ["1,1", "2,0", "0,3"],
			"blocked_count": 3,
			"manual_shapes": [{"kind": "rect", "x": 0, "y": 0}],
			"erased_cells": [],
		},
	}


func _make_runtime_for_map(runtime_map_id: int) -> Dictionary:
	var runtime := _make_runtime()
	runtime["source"]["runtime_map_id"] = runtime_map_id
	return runtime


func _assert_real_formal_runtime_compiles() -> void:
	var loaded := MapEditorRuntimeMapService.load_runtime(
		"res://assets/data/runtime/map_editor/bich_corpse_king_hall.runtime.json"
	)
	assert(bool(loaded.get("ok", false)), "formal runtime fixture failed to load")
	var runtime: Dictionary = loaded.get("runtime", {})
	var expected_runtime_map_id := int(runtime.get("source", {}).get(
		"runtime_map_id", -1
	))
	var result := CollisionGeometry.compile_runtime_collision(
		runtime,
		expected_runtime_map_id,
	)
	assert(
		bool(result.get("ok", false)),
		"formal runtime failed collision compilation: %s" % [result.get("errors", [])],
	)
	var background := WorldBackgroundScript.new()
	var descriptors := background.build_collision_descriptors({
		"mapId": expected_runtime_map_id,
	})
	assert(not background._editor_runtime_collision_snapshot.is_empty())
	assert(background._editor_runtime_size != Vector2i.ZERO)
	assert(descriptors.size() >= 4, "formal collision descriptors were not built")
	background.free()


func _assert_point_parity(runtime: Dictionary, compiled: Dictionary) -> void:
	var collision: Dictionary = runtime.get("collision", {})
	var boundary: PackedVector2Array = compiled.get(
		"boundary_world", PackedVector2Array()
	)
	for point: Vector2 in boundary:
		_assert_point_result(runtime, collision, compiled, point)
	for y: int in range(TEST_SIZE.y):
		for x: int in range(TEST_SIZE.x):
			_assert_point_result(
				runtime,
				collision,
				compiled,
				EditorCoordinate.grid_cell_to_screen_position_px(
					Vector2(x, y),
					TEST_SIZE,
				),
			)
	var random := RandomNumberGenerator.new()
	random.seed = 1337
	for _index: int in range(256):
		_assert_point_result(
			runtime,
			collision,
			compiled,
			Vector2(
				random.randf_range(-180.0, 180.0),
				random.randf_range(-120.0, 120.0),
			),
		)


func _assert_point_result(
	runtime: Dictionary,
	collision: Dictionary,
	compiled: Dictionary,
	world_position: Vector2,
) -> void:
	var expected := CollisionGeometry.runtime_collision_contains_world(
		collision,
		world_position,
		TEST_SIZE,
	)
	var actual := CollisionGeometry.compiled_collision_contains_world(
		compiled,
		world_position,
	)
	assert(
		expected == actual,
		"compiled point parity mismatch at %s old=%s cell=%s ids=%s"
			% [
				world_position,
				expected,
				CollisionGeometry.world_cell(world_position, TEST_SIZE),
				compiled.get("blocked_cell_ids", {}),
			],
	)


func _assert_cell_run_parity(runtime: Dictionary, compiled: Dictionary) -> void:
	var old_runs := CollisionGeometry.blocked_cell_runs(runtime.collision)
	var new_runs := CollisionGeometry.compiled_collision_blocked_cell_runs(compiled)
	assert(old_runs == new_runs, "compiled blocked run parity mismatch")


func _assert_segment_parity(runtime: Dictionary, compiled: Dictionary) -> void:
	var background := WorldBackgroundScript.new()
	background._editor_runtime_size = TEST_SIZE
	background._editor_runtime_collision_snapshot = compiled
	background._editor_runtime_collision_invalid = false
	var cases: Array[Dictionary] = [
		{
			"source": Vector2(0.5, 0.5),
			"target": Vector2(0.5, 0.5),
		},
		{
			"source": Vector2(0.5, 0.5),
			"target": Vector2(0.6, 0.5),
		},
		{
			"source": Vector2(0.5, 1.5),
			"target": Vector2(2.5, 1.5),
		},
		{
			"source": Vector2(-0.1, 0.5),
			"target": Vector2(0.5, 0.5),
		},
		{
			"source": Vector2(3.5, 3.5),
			"target": Vector2(4.1, 3.5),
		},
	]
	for case: Dictionary in cases:
		var source: Vector2 = case.source
		var target: Vector2 = case.target
		var expected := _old_segment_result(runtime.collision, source, target, 0.25)
		var actual := background.is_environment_segment_blocked_ground(
			source,
			target,
			0.25,
		)
		assert(expected == actual, "compiled segment parity mismatch %s -> %s" % [source, target])
	assert(
		background.is_environment_segment_blocked_ground(
			Vector2.ZERO,
			Vector2.ONE,
			0.0,
		),
		"invalid segment step did not fail closed",
	)
	background.free()


func _old_segment_result(
	collision: Dictionary,
	source: Vector2,
	target: Vector2,
	step_gu: float,
) -> bool:
	var sample_count := maxi(1, int(ceil(source.distance_to(target) / step_gu)))
	for sample_index: int in range(sample_count + 1):
		var progress := float(sample_index) / float(sample_count)
		var world := EditorCoordinate.ground_position_gu_to_screen_position_px(
			source.lerp(target, progress),
			TEST_SIZE,
		)
		if CollisionGeometry.runtime_collision_contains_world(
			collision,
			world,
			TEST_SIZE,
		):
			return true
	return false


func _assert_formal_invalid_fail_closed(runtime: Dictionary) -> void:
	var invalid_runtimes: Array[Dictionary] = []
	var missing_collision := runtime.duplicate(true)
	missing_collision.erase("collision")
	invalid_runtimes.append(missing_collision)
	var bad_hash := runtime.duplicate(true)
	bad_hash["build_sha256"] = "bad"
	invalid_runtimes.append(bad_hash)
	var bad_source := runtime.duplicate(true)
	bad_source["source"].erase("runtime_map_id")
	invalid_runtimes.append(bad_source)
	var bad_contract := runtime.duplicate(true)
	bad_contract["collision"]["coordinate_contract_id"] = "manual_shapes_only"
	invalid_runtimes.append(bad_contract)
	var bad_cell := runtime.duplicate(true)
	bad_cell["collision"]["blocked_tiles"] = ["99,99"]
	bad_cell["collision"]["blocked_count"] = 1
	invalid_runtimes.append(bad_cell)
	var bad_count := runtime.duplicate(true)
	bad_count["collision"]["blocked_count"] = 99
	invalid_runtimes.append(bad_count)
	for candidate: Dictionary in invalid_runtimes:
		var result := CollisionGeometry.compile_runtime_collision(
			candidate,
			TEST_RUNTIME_MAP_ID,
		)
		assert(not bool(result.get("ok", false)), "invalid formal runtime compiled")
		assert((result.get("snapshot", {}) as Dictionary).is_empty())
	var background := WorldBackgroundScript.new()
	background._editor_runtime_collision_invalid = true
	assert(background.is_environment_point_blocked(Vector2.ZERO))
	assert(background.is_environment_segment_blocked_ground(Vector2.ZERO, Vector2.ONE))
	background.free()


func _assert_manual_shapes_are_not_authority(runtime: Dictionary) -> void:
	var manual_only := runtime.duplicate(true)
	manual_only["collision"]["blocked_tiles"] = []
	manual_only["collision"]["blocked_count"] = 0
	manual_only["collision"]["manual_shapes"] = [{
		"kind": "rect",
		"x": 1,
		"y": 1,
		"width": 1,
		"height": 1,
	}]
	var result := CollisionGeometry.compile_runtime_collision(
		manual_only,
		TEST_RUNTIME_MAP_ID,
	)
	assert(bool(result.get("ok", false)), "manual-only runtime rejected unexpectedly")
	var snapshot: Dictionary = result.get("snapshot", {})
	var manual_world := EditorCoordinate.grid_cell_to_screen_position_px(
		Vector2(1, 1),
		TEST_SIZE,
	)
	assert(
		not CollisionGeometry.compiled_collision_contains_world(snapshot, manual_world),
		"manual_shapes incorrectly became runtime authority",
	)


func _assert_actor_batch_priority() -> void:
	var probe := BatchProbe.new()
	probe.blocked = true
	var center := Vector2(18.0, -11.0)
	assert(
		WorldSpatialRulesScript.environment_blocks_actor_screen_px(
			probe,
			center,
			12.0,
		),
		"batch provider result was not used",
	)
	assert(probe.batch_calls == 1, "batch provider was called more than once")
	assert(probe.point_calls == 0, "batch provider fell through to point calls")
	assert(probe.observed_center == center)
	assert(is_equal_approx(probe.observed_radius, 12.0))
	probe.free()


func _assert_actor_legacy_order() -> void:
	var probe := PointProbe.new()
	var center := Vector2(50.0, -20.0)
	var radius := 10.0
	assert(
		not WorldSpatialRulesScript.environment_blocks_actor_screen_px(
			probe,
			center,
			radius,
		),
		"clear legacy point provider unexpectedly blocked actor",
	)
	assert(probe.points.size() == 17, "legacy fallback did not query center+16 points")
	assert(probe.points[0] == center, "legacy fallback center order changed")
	var sample_radius := radius - 1.0
	for index: int in range(WorldSpatialRulesScript.ACTOR_FOOTPRINT_SEGMENTS):
		var expected := center + WorldSpatialRulesScript.actor_footprint_offset_px(
			index,
			sample_radius,
		)
		assert(
			(probe.points[index + 1] as Vector2).is_equal_approx(expected),
			"legacy footprint order changed at %d" % index,
		)
	probe.free()


func _assert_background_actor_and_segment(compiled: Dictionary) -> void:
	var background := WorldBackgroundScript.new()
	background._editor_runtime_size = TEST_SIZE
	background._editor_runtime_collision_snapshot = compiled
	background._editor_runtime_collision_invalid = false
	var open_center := EditorCoordinate.grid_cell_to_screen_position_px(
		Vector2(0, 0),
		TEST_SIZE,
	)
	assert(not background.is_environment_actor_blocked(open_center, 0.0))
	var blocked_center := EditorCoordinate.grid_cell_to_screen_position_px(
		Vector2(1, 1),
		TEST_SIZE,
	)
	assert(background.is_environment_actor_blocked(blocked_center, 18.0))
	assert(
		background.is_environment_segment_blocked_ground(
			Vector2(0.5, 1.5),
			Vector2(2.5, 1.5),
			0.25,
		),
		"compiled background segment missed blocked cell",
	)
	background.free()


func _assert_reference_segment_uses_absolute_projection() -> void:
	var background := WorldBackgroundScript.new()
	background.zone_data = {"mapId": 401}
	var source_size := Vector2i(200, 200)
	var source_mask := Image.create(
		source_size.x,
		source_size.y,
		false,
		Image.FORMAT_RGBA8,
	)
	source_mask.fill(Color.WHITE)
	source_mask.set_pixel(100, 100, Color.BLACK)
	background._source_mask_image = source_mask
	# Keep the legacy clearance cache non-empty without clearing the probe cell;
	# otherwise the profile's route/Content clearance fallback can mask it.
	background._source_clear_cell_cache[Vector2i(-1, -1)] = false
	var center_ground := Vector2(99.5, 99.5)
	var center_world := MapCoordinateMapperScript.ground_position_gu_to_screen_position_px(
		center_ground,
		source_size,
	)
	assert(
		center_world.is_equal_approx(Vector2.ZERO),
		"reference profile center did not map to absolute world origin",
	)
	assert(
		background.is_environment_segment_blocked_ground(
			center_ground,
			center_ground,
			0.25,
		),
		"reference segment did not use source-size absolute projection",
	)
	background.free()

	var invalid_profile := ReferenceProfileProbe.new()
	invalid_profile.profile_override = {"source_size": Vector2i.ZERO}
	assert(
		invalid_profile.is_environment_segment_blocked_ground(
			Vector2.ZERO,
			Vector2.ZERO,
			0.25,
		),
		"invalid reference source_size did not fail closed",
	)
	invalid_profile.profile_override = {}
	assert(
		invalid_profile.is_environment_segment_blocked_ground(
			Vector2.ZERO,
			Vector2.ZERO,
			0.25,
		),
		"missing reference source_size did not fail closed",
	)
	invalid_profile.free()


func _assert_build_rebuild_invalidates_collision_authority() -> void:
	var bridge_path := MapEditorRuntimeBridgeScript.runtime_path(
		TEST_REGISTERED_RUNTIME_MAP_ID
	)
	assert(not bridge_path.is_empty(), "registered rebuild test map is unavailable")
	var background := CollisionBuildProbe.new()
	background.runtime_override = _make_runtime_for_map(
		TEST_REGISTERED_RUNTIME_MAP_ID
	)
	var initial_revision := background.environment_collision_revision()
	var successful_descriptors := background.build_collision_descriptors({
		"mapId": TEST_REGISTERED_RUNTIME_MAP_ID,
	})
	var success_revision := background.environment_collision_revision()
	assert(success_revision > initial_revision)
	assert(not successful_descriptors.is_empty())
	assert(not background._editor_runtime_collision_snapshot.is_empty())
	assert(background._editor_runtime_size == TEST_SIZE)

	background.runtime_override = {}
	var failed_descriptors := background.build_collision_descriptors({
		"mapId": TEST_REGISTERED_RUNTIME_MAP_ID,
	})
	var failure_revision := background.environment_collision_revision()
	assert(failure_revision > success_revision)
	assert(failed_descriptors.is_empty())
	assert(background._editor_runtime_collision_snapshot.is_empty())
	assert(background._editor_runtime_size == Vector2i.ZERO)
	assert(background._editor_runtime_collision_invalid)
	assert(background.is_environment_point_blocked(Vector2.ZERO))
	assert(
		background.is_environment_segment_blocked_ground(
			Vector2.ZERO,
			Vector2.ZERO,
			0.25,
		),
		"failed rebuild did not remain fail closed",
	)
	background.free()


func _assert_enemy_segment_path() -> void:
	var probe := SegmentProbe.new()
	var enemy := SegmentEnemy.new()
	enemy.environment_blocker = probe
	var source := Vector2(0.0, 0.0)
	var target := Vector2(2.0, 0.0)
	assert(
		enemy._world_attack_path_is_clear_uncached(source, target),
		"clear segment provider path was rejected",
	)
	assert(probe.calls == 1, "Enemy made more than one segment provider call")
	assert(probe.last_source == source and probe.last_target == target)
	assert(is_equal_approx(probe.last_step, 0.25))
	probe.blocked = true
	assert(
		not enemy._world_attack_path_is_clear_uncached(source, target),
		"blocked segment provider path was accepted",
	)
	assert(probe.calls == 2, "Enemy blocked segment did not use one call")
	enemy.free()
	probe.free()


func _assert_hot_path_structure() -> void:
	var collision_source := FileAccess.get_file_as_string(
		"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
	)
	var compiled_source := _function_slice(
		collision_source,
		"static func compiled_collision_contains_world",
		"static func compiled_collision_contains_ground",
	)
	assert(compiled_source.find("split(\"") < 0)
	assert(compiled_source.find("%d,%d") < 0)
	assert(compiled_source.find("map_actor_boundary_world") < 0)

	var background_source := FileAccess.get_file_as_string(
		"res://scripts/world_background.gd"
	)
	var actor_source := _function_slice(
		background_source,
		"func is_environment_actor_blocked",
		"func is_environment_segment_blocked_ground",
	)
	assert(actor_source.find("PackedVector2Array") < 0)
	assert(actor_source.find("ACTOR_FOOTPRINT_SEGMENTS") >= 0)
	var segment_source := _function_slice(
		background_source,
		"func is_environment_segment_blocked_ground",
		"func bich_collision_count",
	)
	assert(segment_source.find("compiled_collision_contains_ground") >= 0)
	assert(segment_source.find("environment_blocker.call") < 0)

	var enemy_source := FileAccess.get_file_as_string("res://scripts/enemy.gd")
	var los_source := _function_slice(
		enemy_source,
		"func _world_attack_path_is_clear_uncached",
		"func _finish_attack_los_diagnostic",
	)
	var segment_branch_start := los_source.find("if has_map_segment_query:")
	var segment_branch_end := los_source.find(
		"elif has_map_query:",
		segment_branch_start,
	)
	assert(segment_branch_start >= 0 and segment_branch_end > segment_branch_start)
	var segment_branch := los_source.substr(
		segment_branch_start,
		segment_branch_end - segment_branch_start,
	)
	assert(segment_branch.find("is_environment_segment_blocked_ground") >= 0)
	assert(segment_branch.find("is_environment_point_blocked") < 0)
	assert(segment_branch.find("environment_blocker.call") >= 0)

	var spatial_source := FileAccess.get_file_as_string(
		"res://scripts/world_spatial_rules.gd"
	)
	var actor_rule_source := _function_slice(
		spatial_source,
		"static func environment_blocks_actor_screen_px",
		"static func actor_footprint_radii_px",
	)
	var batch_branch_end := actor_rule_source.find(
		"if not provider.has_method(\"is_environment_point_blocked\")",
	)
	assert(batch_branch_end > 0)
	var batch_branch := actor_rule_source.substr(0, batch_branch_end)
	assert(batch_branch.find("is_environment_actor_blocked") >= 0)


func _function_slice(source: String, start_marker: String, end_marker: String) -> String:
	var start := source.find(start_marker)
	var end := source.find(end_marker, start + start_marker.length())
	if start < 0 or end < 0:
		return ""
	return source.substr(start, end - start)
