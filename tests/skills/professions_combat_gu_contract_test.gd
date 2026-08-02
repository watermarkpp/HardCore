extends Node

const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const DirectionSpace := preload("res://scripts/skills/combat_direction_space.gd")
const LockPolicy := preload("res://scripts/skills/spell_target_lock_policy.gd")
const Melee := preload("res://scripts/skills/warrior_melee_geometry.gd")
const CasterGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")
const Projectile := preload("res://scripts/skill_projectile.gd")
const GroundEffect := preload("res://scripts/ground_effect.gd")
const LegacyAdapter := preload("res://scripts/skills/combat_unit_legacy_adapter.gd")
const GeometryService := preload("res://scripts/skills/skill_geometry_service.gd")


func _ready() -> void:
	_test_a_projection_round_trip()
	_test_b_direction_invariant_movement()
	_test_c_euclidean_lock_and_stable_order()
	_test_d_melee_gu_ranges_and_tangency()
	_test_e_continuous_line_gu_geometry()
	_test_f_discrete_cell_footprint_resolver()
	_test_g_projectile_gu_sweep()
	_test_h_primary_source_adapters_and_units()
	_test_i_frozen_visual_contracts()
	_test_j_ground_effect_radius_gu()
	print("PROFESSIONS_COMBAT_GU_CONTRACT_PASS: audits A-J")
	get_tree().quit(0)


func _test_a_projection_round_trip() -> void:
	for sample_index: int in range(32):
		var ground_delta_gu := (
			Vector2.from_angle(TAU * float(sample_index) / 32.0)
			* (0.25 + float(sample_index) * 0.125)
		)
		var screen_delta_px := (
			GroundUnit.ground_delta_gu_to_screen_delta_px(ground_delta_gu)
		)
		assert(
			GroundUnit.screen_delta_px_to_ground_delta_gu(screen_delta_px)
			.is_equal_approx(ground_delta_gu)
		)


func _test_b_direction_invariant_movement() -> void:
	const DELTA_SECONDS := 0.125
	var expected_distance_gu := (
		LegacyAdapter.PLAYER_MOVE_SPEED_GU_PER_SEC * DELTA_SECONDS
	)
	for sample_index: int in range(32):
		var input_ground_direction := Vector2.from_angle(
			TAU * float(sample_index) / 32.0
		)
		var input_screen_direction := (
			GroundUnit.ground_delta_gu_to_screen_delta_px(input_ground_direction)
		)
		var normalized_ground_direction := (
			GroundUnit.screen_delta_px_to_ground_delta_gu(input_screen_direction)
			.normalized()
		)
		var screen_motion_px := (
			GroundUnit.desired_screen_velocity_px_per_sec(
				normalized_ground_direction,
				LegacyAdapter.PLAYER_MOVE_SPEED_GU_PER_SEC
			)
			* DELTA_SECONDS
		)
		var actual_ground_motion_gu := (
			GroundUnit.actual_ground_motion_gu_from_screen_positions(
				Vector2(13.0, -7.0),
				Vector2(13.0, -7.0) + screen_motion_px
			)
		)
		assert(is_equal_approx(
			actual_ground_motion_gu.length(), expected_distance_gu
		))


func _test_c_euclidean_lock_and_stable_order() -> void:
	assert(LockPolicy.CONTRACT_ID == "combat.spell_lock.euclidean_gu.v2")
	assert(LockPolicy.is_within_lock_range(Vector2.ZERO, Vector2(7.2, 9.6)))
	assert(not LockPolicy.is_within_lock_range(Vector2.ZERO, Vector2(8.0, 9.0)))
	var ordered := LockPolicy.ordered_candidates([
		{"origin_ground_gu": Vector2.ZERO, "target_ground_gu": Vector2(3, 4), "instance_id": 9},
		{"origin_ground_gu": Vector2.ZERO, "target_ground_gu": Vector2(-3, -4), "instance_id": 2},
		{"origin_tile": Vector2.ZERO, "target_tile": Vector2.ONE, "instance_id": 1},
	])
	assert(ordered.size() == 2)
	assert(ordered[0].instance_id == 2 and ordered[1].instance_id == 9)
	assert(ordered[0].distance_gu == 5.0)
	assert(not ordered[0].has("tile_distance"))
	assert(LockPolicy.attack_range_allows_target(Vector2.ZERO, Vector2(6, 8)))


func _test_d_melee_gu_ranges_and_tangency() -> void:
	for direction_index: int in range(8):
		var forward_gu := Melee.canonical_ground_direction_gu(direction_index)
		assert(Melee.thrust_slot_gu(
			Vector2.ZERO, forward_gu * 2.5, direction_index
		) == 2)
		assert(Melee.thrust_slot_gu(
			Vector2.ZERO, forward_gu * 2.5002, direction_index
		) == 0)
		var side_gu := Vector2(-forward_gu.y, forward_gu.x)
		assert(Melee.thrust_slot_gu(
			Vector2.ZERO,
			forward_gu * 1.0 + side_gu * 0.5,
			direction_index
		) == 1)
		assert(Melee.thrust_slot_gu(
			Vector2.ZERO,
			forward_gu * 1.0 + side_gu * 0.5002,
			direction_index
		) == 0)
	assert(Melee.maximum_targets(Melee.SKILL_NORMAL) == 1)
	assert(Melee.maximum_targets(Melee.SKILL_FIRE) == 1)
	assert(Melee.maximum_targets(Melee.SKILL_THRUST) == Melee.UNLIMITED_TARGETS)
	assert(Melee.maximum_targets(Melee.SKILL_HALF_MOON) == Melee.UNLIMITED_TARGETS)


func _test_e_continuous_line_gu_geometry() -> void:
	for length_gu: float in [5.0, 8.0]:
		for sample_index: int in range(32):
			var aim_ground_gu := Vector2.from_angle(
				TAU * float(sample_index) / 32.0
			)
			var strip := CasterGeometry.continuous_line_strip(
				Vector2.ZERO,
				aim_ground_gu,
				Vector2.RIGHT,
				length_gu,
				1.0
			)
			assert(is_equal_approx(
				(strip.strip_end_ground_gu as Vector2).length(), length_gu
			))
			assert(is_equal_approx(float(strip.effect_width_gu), 1.0))
			assert(is_equal_approx(float(strip.half_width_gu), 0.5))
			for legacy_key: String in [
				"origin_fractional_tile",
				"aim_fractional_tile",
				"axis_fractional_tile",
				"length_tiles",
				"width_tiles",
				"strip_polygon_fractional_tile",
				"centerline_points_fractional_tile",
			]:
				assert(not strip.has(legacy_key))


func _test_f_discrete_cell_footprint_resolver() -> void:
	var touching := CasterGeometry.declared_cells_intersect_actor_footprint(
		[Vector2i.ZERO],
		Vector2(0.5, 0.0),
		0.0
	)
	assert(touching.contract_id == CasterGeometry.DISCRETE_CELL_FOOTPRINT_RESOLVER_CONTRACT_ID)
	assert(touching.intersects)
	var separated := CasterGeometry.declared_cells_intersect_actor_footprint(
		[Vector2i.ZERO],
		Vector2(0.5002, 0.0),
		0.0
	)
	assert(not separated.intersects)


func _test_g_projectile_gu_sweep() -> void:
	assert(Projectile.FOOTPRINT_HIT_CONTRACT_ID == "skills.projectile.ground_gu_swept_footprint_contact.v2")
	assert(Projectile.swept_segment_intersects_footprint_gu(
		Vector2.ZERO, Vector2(8, 0), Vector2(4, 0.4), 0.5
	))
	assert(not Projectile.swept_segment_intersects_footprint_gu(
		Vector2.ZERO, Vector2(8, 0), Vector2(4, 0.6), 0.5
	))
	var projectile := Projectile.new()
	projectile.setup_ground_unit_projectile(
		Vector2(100, 200),
		Vector2(3, 4),
		7.5,
		37,
		12.0,
		0.25,
		Vector2(9, -3),
		Color.CYAN,
		"slow",
		2,
		1.5,
		"wizard.fireball"
	)
	assert(
		Projectile.GROUND_UNIT_SETUP_CONTRACT_ID
		== "skills.projectile.setup_ground_unit_projectile.v1"
	)
	assert(is_equal_approx(projectile.direction_ground_gu.length(), 1.0))
	assert(is_equal_approx(projectile.max_travel_distance_gu, 7.5))
	assert(projectile.visual_muzzle_offset_px == Vector2(9, -3))
	assert(projectile.damage == 37 and projectile.effect == "slow")
	assert(projectile.effect_strength == 2)
	assert(is_equal_approx(projectile.effect_duration, 1.5))
	assert(projectile.skill_id == "wizard.fireball")
	projectile.free()


func _test_h_primary_source_adapters_and_units() -> void:
	assert(LegacyAdapter.CONTRACT_ID == "combat.unit.legacy_primary_source_adapter.v1")
	assert(LegacyAdapter.PLAYER_MOVE_SOURCE_EVIDENCE.source_tier == "primary")
	assert(LegacyAdapter.PROJECTILE_SOURCE_EVIDENCE.primary_gu_scalar_query == "missing")
	assert(LegacyAdapter.SUMMON_SPATIAL_SOURCE_EVIDENCE.primary_continuous_gu_per_sec_query == "missing")
	assert(is_equal_approx(LegacyAdapter.PLAYER_MOVE_SPEED_GU_PER_SEC, 2.0 / 0.6))
	assert(LegacyAdapter.PROJECTILE_SPEED_GU_PER_SEC > 0.0)
	assert(LegacyAdapter.PROJECTILE_RADIUS_GU > 0.0)
	assert(DirectionSpace.CONTRACT_ID == "gameplay.professions.combat_direction_space.ground_gu_8dir.v2")


func _test_i_frozen_visual_contracts() -> void:
	assert(is_equal_approx(
		CasterGeometry._stable_laser_visual_cross_extent(Vector2(64, 32)),
		sqrt(64.0 * 32.0)
	))
	for skill_id: String in ["wizard.hellfire", "wizard.laser"]:
		var domain := GeometryService.geometry_domain({"skill_id": skill_id})
		assert(domain.domain == GeometryService.DOMAIN_CONTINUOUS_GROUND_GU)
		assert(domain.unit_contract_id == GroundUnit.CONTRACT_ID)


func _test_j_ground_effect_radius_gu() -> void:
	assert(
		GroundEffect.GROUND_UNIT_SETUP_CONTRACT_ID
		== "skills.ground_effect.setup_ground_unit_effect.v1"
	)
	var effect := GroundEffect.new()
	effect.setup_ground_unit_effect(
		Vector2(320.0, 180.0), 1, 1.25, 1.0, Color.WHITE
	)
	var target := Node2D.new()
	for sample_index: int in range(32):
		var direction_ground_gu := Vector2.from_angle(
			TAU * float(sample_index) / 32.0
		)
		target.global_position = effect.global_position + (
			GroundUnit.ground_delta_gu_to_screen_delta_px(
				direction_ground_gu * 1.25
			)
		)
		assert(effect.runtime_target_is_inside(target))
		target.global_position = effect.global_position + (
			GroundUnit.ground_delta_gu_to_screen_delta_px(
				direction_ground_gu * 1.251
			)
		)
		assert(not effect.runtime_target_is_inside(target))
	target.free()
	effect.free()
