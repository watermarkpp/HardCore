extends Node

const Geometry := preload("res://scripts/skills/warrior_melee_geometry.gd")
const Diagnostic := preload("res://scripts/skills/warrior_melee_diagnostic.gd")
const DirectionSpace := preload("res://scripts/skills/combat_direction_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")

const TARGET_RADIUS_GU := 0.25
const SAMPLE_COUNT := 126
const AXIS_ERROR_TOLERANCE_GU := 0.0005
const MAP_ID := 4
const ORIGIN_GROUND_GU := Vector2(19.92, 46.40)


func _ready() -> void:
	assert(
		Geometry.TARGET_ALIGNED_CONTINUOUS_RELEASE_CONTRACT_ID
		== "gameplay.warrior.melee.target_aligned_continuous_release.v1"
	)
	assert(
		Geometry.TARGET_ALIGNED_CONTINUOUS_RELEASE_CONTRACT_ID
		!= Geometry.THRUST_CONTINUOUS_DAMAGE_AXIS_CONTRACT_ID
	)
	_verify_arbitrary_angle_continuous_axis_and_quantization()
	_verify_locked_target_inclusion_and_out_of_range_exclusion()
	_verify_thrust_dimensions_and_slots_unchanged()
	_verify_half_moon_sector_semantics_unchanged()
	_verify_ineligible_cases_fail_closed()
	_verify_diagnostics()
	print(
		"WARRIOR_TARGET_ALIGNED_RELEASE_GEOMETRY_PASS: %d arbitrary-angle "
		+ "samples keep the continuous locked-target release axis while the "
		+ "visual direction index stays 8-way quantized; one shared snapshot "
		+ "gates normal/fire/thrust/half-moon candidate inclusion" % SAMPLE_COUNT
	)
	get_tree().quit(0)


func _verify_arbitrary_angle_continuous_axis_and_quantization() -> void:
	for sample_index: int in range(SAMPLE_COUNT):
		var angle_deg := 360.0 * float(sample_index) / float(SAMPLE_COUNT)
		_verify_single_angle_sample(angle_deg, 1000 + sample_index)
	for direction_index: int in range(8):
		var canonical_axis := Geometry.canonical_ground_direction_gu(
			direction_index
		)
		_verify_single_angle_sample(
			rad_to_deg(canonical_axis.angle()),
			2000 + direction_index
		)


func _verify_single_angle_sample(angle_deg: float, instance_id: int) -> void:
	var axis_ground_gu := Vector2.from_angle(deg_to_rad(angle_deg))
	var locked_target_ground_gu := (
		ORIGIN_GROUND_GU + axis_ground_gu * 1.2
	)
	var release_geometry := _release_geometry(
		ORIGIN_GROUND_GU,
		locked_target_ground_gu,
		instance_id
	)
	var coordinate_context := _absolute_context(ORIGIN_GROUND_GU)
	var quantized_index := (
		DirectionSpace.direction_index_for_ground_delta_gu(
			locked_target_ground_gu - ORIGIN_GROUND_GU
		)
	)
	var angle_is_canonical := axis_ground_gu.is_equal_approx(
		Geometry.canonical_ground_direction_gu(quantized_index)
	)
	for mode: String in [
		Geometry.SKILL_NORMAL,
		Geometry.SKILL_FIRE,
		Geometry.SKILL_HALF_MOON,
		Geometry.SKILL_THRUST,
	]:
		var plan := Geometry.target_aligned_melee_release_plan_ground_gu(
			release_geometry,
			mode,
			coordinate_context
		)
		assert(bool(plan.get("target_axis_eligible", false)))
		assert(
			str(plan.get("contract_id", ""))
			== Geometry.TARGET_ALIGNED_CONTINUOUS_RELEASE_CONTRACT_ID
		)
		assert(int(plan.get("visual_direction_index", -1)) == quantized_index)
		var continuous_axis := (
			plan.get("continuous_axis_ground_gu", Vector2.ZERO) as Vector2
		)
		assert(
			continuous_axis.distance_to(axis_ground_gu)
			<= AXIS_ERROR_TOLERANCE_GU
		)
		assert(
			continuous_axis.is_equal_approx(
				Geometry.canonical_ground_direction_gu(quantized_index)
			)
			== angle_is_canonical
		)
		var expected_shape := (
			Snapshot.SHAPE_SECTOR_ARC
			if mode == Geometry.SKILL_HALF_MOON
			else Snapshot.SHAPE_DIRECTED_RECTANGLE
		)
		var raw_snapshot: Variant = plan.get("skill_footprint_snapshot")
		assert(raw_snapshot is Dictionary)
		var snapshot := raw_snapshot as Dictionary
		assert(str(snapshot.get("shape_type", "")) == expected_shape)
		assert(bool(Snapshot.validate_for_consumer(
			snapshot,
			coordinate_context,
			Snapshot.VALIDATION_STRICT_V2
		).get("valid", false)))
		assert(snapshot.is_read_only())


func _verify_locked_target_inclusion_and_out_of_range_exclusion() -> void:
	var checked_samples := 0
	for sample_index: int in range(SAMPLE_COUNT):
		var angle_deg := 360.0 * float(sample_index) / float(SAMPLE_COUNT)
		var axis_ground_gu := Vector2.from_angle(deg_to_rad(angle_deg))
		for mode: String in [
			Geometry.SKILL_NORMAL,
			Geometry.SKILL_FIRE,
			Geometry.SKILL_HALF_MOON,
			Geometry.SKILL_THRUST,
		]:
			var reach_gu := Geometry.reach_gu(mode)
			var in_range_target := (
				ORIGIN_GROUND_GU + axis_ground_gu * (reach_gu * 0.9)
			)
			var in_plan := Geometry.target_aligned_melee_release_plan_ground_gu(
				_release_geometry(
					ORIGIN_GROUND_GU,
					in_range_target,
					3000 + sample_index
				),
				mode,
				_absolute_context(ORIGIN_GROUND_GU)
			)
			assert(bool(in_plan.get("target_axis_eligible", false)))
			assert(Geometry.target_aligned_release_plan_intersects_target_footprint_ground_gu(
				in_plan,
				in_range_target,
				TARGET_RADIUS_GU,
				_absolute_context(ORIGIN_GROUND_GU)
			))
			var out_range_target := (
				ORIGIN_GROUND_GU
				+ axis_ground_gu * (reach_gu + TARGET_RADIUS_GU + 0.01)
			)
			var out_plan := Geometry.target_aligned_melee_release_plan_ground_gu(
				_release_geometry(
					ORIGIN_GROUND_GU,
					out_range_target,
					4000 + sample_index
				),
				mode,
				_absolute_context(ORIGIN_GROUND_GU)
			)
			assert(not bool(out_plan.get("target_axis_eligible", false)))
			assert(str(out_plan.get("ineligible_reason", "")) == "out_of_range")
			assert(not Geometry.target_aligned_release_plan_intersects_target_footprint_ground_gu(
				out_plan,
				out_range_target,
				TARGET_RADIUS_GU,
				_absolute_context(ORIGIN_GROUND_GU)
			))
			checked_samples += 1
	assert(checked_samples == SAMPLE_COUNT * 4)


func _verify_thrust_dimensions_and_slots_unchanged() -> void:
	var axis_ground_gu := Vector2.from_angle(deg_to_rad(11.0))
	var plan := Geometry.target_aligned_melee_release_plan_ground_gu(
		_release_geometry(
			ORIGIN_GROUND_GU,
			ORIGIN_GROUND_GU + axis_ground_gu * 2.0,
			5001
		),
		Geometry.SKILL_THRUST,
		_absolute_context(ORIGIN_GROUND_GU)
	)
	var snapshot := plan.get("skill_footprint_snapshot") as Dictionary
	assert(is_equal_approx(float(snapshot.get("effect_length_gu", 0.0)), 2.5))
	assert(is_equal_approx(float(snapshot.get("effect_width_gu", 0.0)), 1.0))
	assert(is_equal_approx(float(snapshot.get("start_offset_gu", -1.0)), 0.0))
	assert(
		(snapshot.get("direction_ground_gu", Vector2.ZERO) as Vector2)
		.is_equal_approx(axis_ground_gu)
	)
	var side_ground_gu := Vector2(-axis_ground_gu.y, axis_ground_gu.x)
	var coordinate_context := _absolute_context(ORIGIN_GROUND_GU)
	assert(Geometry.target_aligned_thrust_slot_for_plan_gu(
		plan,
		ORIGIN_GROUND_GU + axis_ground_gu * 1.0,
		TARGET_RADIUS_GU,
		coordinate_context
	) == 1)
	assert(Geometry.target_aligned_thrust_slot_for_plan_gu(
		plan,
		ORIGIN_GROUND_GU + axis_ground_gu * 2.2,
		TARGET_RADIUS_GU,
		coordinate_context
	) == 2)
	assert(Geometry.target_aligned_thrust_slot_for_plan_gu(
		plan,
		ORIGIN_GROUND_GU + axis_ground_gu * 2.751,
		TARGET_RADIUS_GU,
		coordinate_context
	) == 0)
	assert(Geometry.target_aligned_thrust_slot_for_plan_gu(
		plan,
		ORIGIN_GROUND_GU + axis_ground_gu * 2.0 + side_ground_gu * 0.751,
		TARGET_RADIUS_GU,
		coordinate_context
	) == 0)


func _verify_half_moon_sector_semantics_unchanged() -> void:
	var axis_ground_gu := Vector2(1.0, 1.0).normalized()
	var plan := Geometry.target_aligned_melee_release_plan_ground_gu(
		_release_geometry(
			ORIGIN_GROUND_GU,
			ORIGIN_GROUND_GU + axis_ground_gu * 1.2,
			6001
		),
		Geometry.SKILL_HALF_MOON,
		_absolute_context(ORIGIN_GROUND_GU)
	)
	var coordinate_context := _absolute_context(ORIGIN_GROUND_GU)
	var expected_codes := {
		-45.0: 7,
		0.0: 0,
		45.0: 1,
		90.0: 2,
	}
	for offset_deg: float in [-45.0, 0.0, 45.0, 90.0]:
		var sector_direction := axis_ground_gu.rotated(deg_to_rad(offset_deg))
		var target_ground_gu := (
			ORIGIN_GROUND_GU + sector_direction * 1.2
		)
		assert(Geometry.target_aligned_half_moon_relative_sector_for_plan_gu(
			plan,
			target_ground_gu,
			TARGET_RADIUS_GU,
			coordinate_context
		) == int(expected_codes[offset_deg]))
	var outside_target_ground_gu := (
		ORIGIN_GROUND_GU
		+ axis_ground_gu.rotated(deg_to_rad(-82.0)) * 1.2
	)
	assert(Geometry.target_aligned_half_moon_relative_sector_for_plan_gu(
		plan,
		outside_target_ground_gu,
		TARGET_RADIUS_GU,
		coordinate_context
	) == -1)
	var inside_edge_target_ground_gu := (
		ORIGIN_GROUND_GU
		+ axis_ground_gu.rotated(deg_to_rad(-66.5)) * 1.2
	)
	assert(Geometry.target_aligned_half_moon_relative_sector_for_plan_gu(
		plan,
		inside_edge_target_ground_gu,
		TARGET_RADIUS_GU,
		coordinate_context
	) == 7)
	# Legacy parity: when the continuous axis equals canonical N (index 4),
	# the continuous sector codes must match the old 8-way footprint function.
	var north_axis := Geometry.canonical_ground_direction_gu(4)
	var north_plan := Geometry.target_aligned_melee_release_plan_ground_gu(
		_release_geometry(
			ORIGIN_GROUND_GU,
			ORIGIN_GROUND_GU + north_axis * 1.2,
			6002
		),
		Geometry.SKILL_HALF_MOON,
		coordinate_context
	)
	for direction_index: int in [3, 4, 5, 6]:
		var target_direction := Geometry.canonical_ground_direction_gu(
			direction_index
		)
		var target_ground_gu := (
			ORIGIN_GROUND_GU + target_direction * 1.2
		)
		var continuous_code := (
			Geometry.target_aligned_half_moon_relative_sector_for_plan_gu(
				north_plan,
				target_ground_gu,
				TARGET_RADIUS_GU,
				coordinate_context
			)
		)
		var legacy_code := Geometry.half_moon_footprint_relative_sector_gu(
			ORIGIN_GROUND_GU,
			target_ground_gu,
			TARGET_RADIUS_GU,
			4
		)
		assert(continuous_code == legacy_code)


func _verify_ineligible_cases_fail_closed() -> void:
	var coordinate_context := _absolute_context(ORIGIN_GROUND_GU)
	var in_range_target := (
		ORIGIN_GROUND_GU + Vector2(1.0, 1.0).normalized() * 1.2
	)
	var cases := {
		"invalid_target": _release_geometry(
			ORIGIN_GROUND_GU,
			in_range_target,
			7001,
			{"locked_target_valid_at_release": false}
		),
		"missing_lock": _release_geometry(
			ORIGIN_GROUND_GU,
			in_range_target,
			0
		),
		"zero_axis": _release_geometry(
			ORIGIN_GROUND_GU,
			in_range_target,
			7002,
			{"live_locked_target_direction_ground_gu": Vector2.ZERO}
		),
		"out_of_range": _release_geometry(
			ORIGIN_GROUND_GU,
			ORIGIN_GROUND_GU + Vector2(1.0, 1.0).normalized() * 10.0,
			7003
		),
		"same_footpoint": _release_geometry(
			ORIGIN_GROUND_GU,
			ORIGIN_GROUND_GU,
			7004
		),
	}
	for expected_reason: String in cases.keys():
		var release_geometry: Dictionary = cases[expected_reason]
		var plan := Geometry.target_aligned_melee_release_plan_ground_gu(
			release_geometry,
			Geometry.SKILL_NORMAL,
			coordinate_context
		)
		assert(not bool(plan.get("target_axis_eligible", false)))
		assert(str(plan.get("ineligible_reason", "")) == expected_reason)
		assert(
			str(plan.get("contract_id", ""))
			== Geometry.TARGET_ALIGNED_CONTINUOUS_RELEASE_CONTRACT_ID
		)
		assert(plan.get("skill_footprint_snapshot") == null)
		assert(not Geometry.target_aligned_release_plan_intersects_target_footprint_ground_gu(
			plan,
			in_range_target,
			TARGET_RADIUS_GU,
			coordinate_context
		))
		assert(Geometry.target_aligned_thrust_slot_for_plan_gu(
			plan,
			in_range_target,
			TARGET_RADIUS_GU,
			coordinate_context
		) == 0)
		assert(Geometry.target_aligned_half_moon_relative_sector_for_plan_gu(
			plan,
			in_range_target,
			TARGET_RADIUS_GU,
			coordinate_context
		) == -1)
	var blocked_plan := Geometry.target_aligned_melee_release_plan_ground_gu(
		_release_geometry(
			ORIGIN_GROUND_GU,
			in_range_target,
			7005
		),
		Geometry.SKILL_NORMAL,
		coordinate_context,
		0.0,
		true
	)
	assert(not bool(blocked_plan.get("target_axis_eligible", false)))
	assert(str(blocked_plan.get("ineligible_reason", "")) == "terrain_blocked")
	assert(blocked_plan.get("skill_footprint_snapshot") == null)
	var missing_origin := _release_geometry(
		ORIGIN_GROUND_GU,
		in_range_target,
		7006
	)
	missing_origin.erase("origin_ground_gu")
	var missing_origin_plan := (
		Geometry.target_aligned_melee_release_plan_ground_gu(
			missing_origin,
			Geometry.SKILL_NORMAL,
			coordinate_context
		)
	)
	assert(not bool(missing_origin_plan.get("target_axis_eligible", false)))
	assert(str(missing_origin_plan.get("ineligible_reason", "")) == "missing_origin")


func _verify_diagnostics() -> void:
	var axis_ground_gu := Vector2.from_angle(deg_to_rad(11.0))
	var target_ground_gu := ORIGIN_GROUND_GU + axis_ground_gu * 1.2
	var release_geometry := _release_geometry(
		ORIGIN_GROUND_GU,
		target_ground_gu,
		8001
	)
	var coordinate_context := _absolute_context(ORIGIN_GROUND_GU)
	var explanation := Diagnostic.explain_target_aligned_release(
		release_geometry,
		Geometry.SKILL_NORMAL,
		coordinate_context
	)
	assert(
		str(explanation.get("result_code", ""))
		== Diagnostic.RESULT_TARGET_ALIGNED_OK
	)
	assert(bool(explanation.get("target_axis_eligible", false)))
	assert(bool(explanation.get("snapshot_built", false)))
	assert(
		str(explanation.get("geometry_contract_id", ""))
		== Geometry.TARGET_ALIGNED_CONTINUOUS_RELEASE_CONTRACT_ID
	)
	var audit := Diagnostic.audit_target_aligned_axis(
		ORIGIN_GROUND_GU,
		target_ground_gu
	)
	assert(bool(audit.get("has_direction", false)))
	assert(not bool(audit.get("continuous_matches_quantized", true)))
	assert(
		int(audit.get("quantized_direction_index", -1))
		== DirectionSpace.direction_index_for_ground_delta_gu(
			target_ground_gu - ORIGIN_GROUND_GU
		)
	)
	var canonical_audit := Diagnostic.audit_target_aligned_axis(
		ORIGIN_GROUND_GU,
		ORIGIN_GROUND_GU + Vector2(1.0, 1.0).normalized() * 1.2
	)
	assert(bool(canonical_audit.get("continuous_matches_quantized", false)))


func _release_geometry(
	origin_ground_gu: Vector2,
	locked_target_ground_gu: Vector2,
	instance_id: int,
	extra: Dictionary = {}
) -> Dictionary:
	var delta_ground_gu := locked_target_ground_gu - origin_ground_gu
	var result := {
		"origin_ground_gu": origin_ground_gu,
		"locked_target_ground_gu_at_release": locked_target_ground_gu,
		"locked_target_valid_at_release": true,
		"locked_target_instance_id": instance_id,
		"live_locked_target_direction_ground_gu": (
			delta_ground_gu.normalized()
			if delta_ground_gu.length_squared()
			> Geometry.EPSILON * Geometry.EPSILON
			else Vector2.ZERO
		),
		"direction_index": DirectionSpace.direction_index_for_ground_delta_gu(
			delta_ground_gu
		),
		"release_id": "target_aligned_test_release_%d" % instance_id,
	}
	result.merge(extra, true)
	return result


func _absolute_context(origin_ground_gu: Vector2) -> Dictionary:
	return Snapshot.make_absolute_runtime_context(
		MAP_ID,
		origin_ground_gu,
		origin_ground_gu,
		Callable(self, "_ground_gu_to_screen_px")
	)


func _ground_gu_to_screen_px(ground_gu: Vector2) -> Vector2:
	return Vector2(ground_gu.x * 64.0, ground_gu.y * 32.0)
