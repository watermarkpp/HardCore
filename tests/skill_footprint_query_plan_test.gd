extends Node

const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const Plan := preload("res://scripts/skills/skill_footprint_query_plan.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")

const EPSILON := 0.0001
const RUNTIME_MAP_ID := 77


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_verify_ground_aabbs_for_all_shapes()
	_verify_cell_union_fallback_and_fail_closed_screen_geometry()
	_verify_one_plan_per_release_and_reference_identity()
	_verify_maximum_target_sentinel_contract()
	_verify_invalid_plan_is_fail_closed()
	print(
		"SKILL_FOOTPRINT_QUERY_PLAN_PASS immutable_plan=1 ground_aabb_shapes=6 "
		+ "strict_validation_once=1"
	)
	get_tree().quit(0)


func _local_context() -> Dictionary:
	return Snapshot.make_local_delta_context(
		Callable(GroundUnitSpace, "ground_delta_gu_to_screen_delta_px")
	)


func _verify_ground_aabbs_for_all_shapes() -> void:
	var context := _local_context()
	var snapshots: Array[Dictionary] = [
		Snapshot.create_directed_rectangle(
			"test.rectangle",
			"aabb.rectangle",
			Vector2.ZERO,
			Vector2.RIGHT,
			4.0,
			2.0,
			0.0,
			0.0,
			0.0,
			"",
			context,
		),
		Snapshot.create_sector_arc(
			"test.sector",
			"aabb.sector",
			Vector2(1.0, 1.0),
			Vector2.RIGHT,
			3.0,
			PI * 0.25,
			16,
			context,
		),
		Snapshot.create_circle(
			"test.circle",
			"aabb.circle",
			Vector2(10.0, -4.0),
			2.5,
			16,
			context,
		),
		Snapshot.create_swept_capsule_path(
			"test.capsule",
			"aabb.capsule",
			Vector2(-2.0, 0.0),
			Vector2(5.0, 3.0),
			1.0,
			16,
			"",
			-1,
			context,
		),
		Snapshot.create_target_footprint(
			"test.target",
			"aabb.target",
			Vector2(2.0, -3.0),
			0.75,
			123,
			context,
		),
		Snapshot.create_cell_union(
			"test.cells",
			"aabb.cells",
			Vector2.ZERO,
			[Vector2i(-2, 3), Vector2i(1, 0)],
			context,
		),
	]
	for snapshot: Dictionary in snapshots:
		assert(snapshot.is_read_only(), "formal snapshots must be immutable")
		var aabb := Snapshot.ground_aabb(snapshot)
		assert(bool(aabb.get("valid", false)), "shape AABB failed: %s" % aabb)
		var bounds: Rect2 = aabb.get("bounds_ground_gu", Rect2())
		assert(bounds.size.x >= 0.0 and bounds.size.y >= 0.0)
		assert(str(aabb.get("reason", "")).is_empty())

	var circle := snapshots[2]
	var circle_aabb := Snapshot.ground_aabb(circle)
	assert(
		circle_aabb.get("bounds_ground_gu", Rect2())
		== Rect2(Vector2(7.5, -6.5), Vector2(5.0, 5.0)),
		"circle AABB must use center +/- radius"
	)
	var rectangle_aabb := Snapshot.ground_aabb(snapshots[0])
	assert(
		rectangle_aabb.get("bounds_ground_gu", Rect2())
		== Rect2(Vector2(0.0, -1.0), Vector2(4.0, 2.0)),
		"rectangle AABB must come from ground polygon"
	)
	var cell_aabb := Snapshot.ground_aabb(snapshots[5])
	assert(
		cell_aabb.get("bounds_ground_gu", Rect2())
		== Rect2(Vector2(-2.5, -0.5), Vector2(4.0, 4.0)),
		"cell union AABB must cover every cell"
	)


func _verify_cell_union_fallback_and_fail_closed_screen_geometry() -> void:
	var context := _local_context()
	var cell_snapshot := Snapshot.create_cell_union(
		"test.cells",
		"aabb.cells.fallback",
		Vector2.ZERO,
		[Vector2i(-1, -1), Vector2i(3, 2)],
		context,
	)
	var cells_only := cell_snapshot.duplicate(true)
	cells_only["polygons_ground_gu"] = []
	cells_only["polygon_ground_gu"] = PackedVector2Array()
	var cells_only_aabb := Snapshot.ground_aabb(cells_only)
	assert(bool(cells_only_aabb.get("valid", false)))
	assert(
		cells_only_aabb.get("bounds_ground_gu", Rect2())
		== Rect2(Vector2(-1.5, -1.5), Vector2(5.0, 4.0)),
		"cell fallback must use geometry cell centers"
	)

	var circle := Snapshot.create_circle(
		"test.circle",
		"aabb.circle.center_only",
		Vector2(4.0, 5.0),
		1.25,
		16,
		context,
	)
	var center_only := circle.duplicate(true)
	center_only.erase("polygon_ground_gu")
	var center_only_aabb := Snapshot.ground_aabb(center_only)
	assert(bool(center_only_aabb.get("valid", false)))
	assert(
		center_only_aabb.get("bounds_ground_gu", Rect2())
		== Rect2(Vector2(2.75, 3.75), Vector2(2.5, 2.5)),
		"circle center/radius path must remain formal"
	)

	var visual_only := circle.duplicate(true)
	visual_only.erase("polygon_ground_gu")
	visual_only.erase("center_ground_gu")
	visual_only.erase("radius_gu")
	visual_only["polygon_screen_offset_px"] = PackedVector2Array([
		Vector2(-1000.0, -1000.0),
		Vector2(1000.0, 1000.0),
		Vector2(0.0, 0.0),
	])
	var visual_result := Snapshot.ground_aabb(visual_only)
	assert(
		not bool(visual_result.get("valid", false)),
		"screen visual bounds must never define gameplay AABB"
	)

	var missing_contract := circle.duplicate(true)
	missing_contract.erase("unit_contract_id")
	var missing_result := Snapshot.ground_aabb(missing_contract)
	assert(not bool(missing_result.get("valid", false)))


func _verify_one_plan_per_release_and_reference_identity() -> void:
	Plan.reset_for_tests()
	var context := _local_context()
	var snapshot := Snapshot.create_directed_rectangle(
		"test.plan",
		"release-1",
		Vector2.ZERO,
		Vector2.RIGHT,
		6.0,
		1.0,
		0.0,
		0.0,
		0.0,
		"",
		context,
	)
	var release_cache: Dictionary = {}
	var options := {
		"query_kind": Plan.QUERY_KIND_AABB,
		"ordering_policy": Plan.ORDERING_STABLE_COMBAT_INSTANCE,
		"maximum_targets": 4,
		"cell_sequence": [Vector2i(0, 0), Vector2i(1, 0)],
	}
	var plan_a := Plan.build_once(
		release_cache,
		"release-1",
		"test.plan",
		RUNTIME_MAP_ID,
		snapshot,
		context,
		options,
	)
	var plan_b := Plan.build_once(
		release_cache,
		"release-1",
		"test.plan",
		RUNTIME_MAP_ID,
		snapshot,
		context,
		options,
	)
	assert(is_same(plan_a, plan_b), "release cache must return the same plan")
	assert(plan_a.is_read_only(), "query plan must be immutable")
	assert(plan_a.get("valid", false))
	assert(plan_a.get("release_id", "") == "release-1")
	assert(plan_a.get("skill_id", "") == "test.plan")
	assert(plan_a.get("runtime_map_id", -1) == RUNTIME_MAP_ID)
	assert(
		is_same(plan_a.get("validated_snapshot_reference"), snapshot),
		"plan must retain the exact snapshot reference"
	)
	assert(
		is_same(plan_a.get("validation_context_reference"), context),
		"plan must retain the exact validation context reference"
	)
	assert(not context.has("expected_runtime_map_id"))
	assert(plan_a.get("maximum_targets", -1) == 4)
	assert(plan_a.get("query_kind", "") == Plan.QUERY_KIND_AABB)
	assert(
		plan_a.get("ordering_policy", "")
		== Plan.ORDERING_STABLE_COMBAT_INSTANCE
	)
	var plan_cells: Array = plan_a.get("cell_sequence", [])
	assert(plan_cells.is_read_only())
	assert(plan_cells.size() == 2)
	assert(plan_a.get("ground_aabb", Rect2()).size.x > EPSILON)
	assert(Plan.plan_build_count == 1)
	assert(Plan.strict_validation_count == 1)

	Plan.clear_release_cache(release_cache, "release-1")
	var rebuilt := Plan.build_once(
		release_cache,
		"release-1",
		"test.plan",
		RUNTIME_MAP_ID,
		snapshot,
		context,
		options,
	)
	assert(not is_same(rebuilt, plan_a))
	assert(Plan.plan_build_count == 2)
	assert(Plan.strict_validation_count == 2)


func _verify_invalid_plan_is_fail_closed() -> void:
	var context := _local_context()
	var snapshot := Snapshot.create_circle(
		"test.invalid",
		"release-invalid",
		Vector2.ZERO,
		1.0,
		16,
		context,
	)
	var mutable_snapshot := snapshot.duplicate(true)
	var plan := Plan.build(
		"release-invalid",
		"test.invalid",
		RUNTIME_MAP_ID,
		mutable_snapshot,
		context,
	)
	assert(not plan.get("valid", true))
	assert(plan.get("failure_reason", "") == "snapshot_not_immutable")

	var missing := Plan.build(
		"release-missing",
		"test.invalid",
		RUNTIME_MAP_ID,
		{},
		context,
	)
	assert(not missing.get("valid", true))
	assert(missing.get("failure_reason", "") == "snapshot_missing")


func _verify_maximum_target_sentinel_contract() -> void:
	var unlimited := _build_with_maximum_targets(
		Plan.UNLIMITED_TARGETS,
		"release-unlimited",
	)
	assert(unlimited.get("valid", false))
	assert(
		unlimited.get("maximum_targets", 0) == Plan.UNLIMITED_TARGETS,
		"unlimited sentinel must remain -1 in the plan"
	)

	var zero := _build_with_maximum_targets(0, "release-zero")
	assert(zero.get("valid", false))
	assert(zero.get("maximum_targets", -1) == 0)

	var negative := _build_with_maximum_targets(-2, "release-negative")
	assert(not negative.get("valid", true))
	assert(negative.get("failure_reason", "") == "maximum_targets_invalid")

	var fractional := _build_with_maximum_targets(1.5, "release-fractional")
	assert(not fractional.get("valid", true))
	assert(fractional.get("failure_reason", "") == "maximum_targets_invalid")

	var non_finite := _build_with_maximum_targets(NAN, "release-non-finite")
	assert(not non_finite.get("valid", true))
	assert(non_finite.get("failure_reason", "") == "maximum_targets_invalid")


func _build_with_maximum_targets(
	maximum_targets: Variant,
	release_id: String,
) -> Dictionary:
	var context := _local_context()
	var snapshot := Snapshot.create_circle(
		"test.maximum_targets",
		release_id,
		Vector2.ZERO,
		1.0,
		16,
		context,
	)
	return Plan.build(
		release_id,
		"test.maximum_targets",
		RUNTIME_MAP_ID,
		snapshot,
		context,
		{"maximum_targets": maximum_targets},
	)
