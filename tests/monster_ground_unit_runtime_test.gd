extends Node2D


const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const RUNTIME_TEST_MONSTER_ID := 21


func _test_ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(value)


class CombatTarget:
	extends Node2D

	var current_hp := 10000

	func _init() -> void:
		add_to_group("combat_targets")

	func take_damage(amount: int, _attacker: Variant = null) -> void:
		current_hp -= amount


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(RUNTIME_TEST_MONSTER_ID), null, false)
	# Runtime production rejects caller-authored combat payloads. Geometry tests
	# use a real canonical identity and then configure their isolated probe state.
	enemy.move_speed_gu_per_sec = 1.0
	enemy.attack_range_gu = 1.5
	enemy.aggro_radius_gu = 12.0
	enemy.configure_runtime_map_projection(
		1,
		Callable(self, "_test_ground_to_screen")
	, GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu)
	enemy.global_position = Vector2.ZERO
	enemy.set_meta("spawn_position", Vector2.ZERO)
	enemy.set_meta("safe_zones", [])
	add_child(enemy)
	enemy.set_physics_process(false)

	_verify_aggro_and_leash_in_32_ground_directions(enemy)
	_verify_fixed_area_range_in_32_ground_directions(enemy)
	_verify_boss_circle_range_in_32_ground_directions(enemy)
	_verify_boss_cone_uses_ground_direction(enemy)
	_verify_boss_warning_projection_uses_gu(enemy)
	_verify_safe_zone_uses_relative_ground_reference(enemy)
	await _verify_enemy_equal_time_movement_in_32_ground_directions(enemy)
	_verify_visual_streaming_does_not_own_attack_state(enemy)
	_verify_runtime_source_has_no_screen_distance_fallback()

	print("MONSTER_GROUND_UNIT_RUNTIME_PASS aggro/leash/fixed-area/boss-circle/cone are direction-invariant GU geometry")
	get_tree().quit(0)


func _verify_aggro_and_leash_in_32_ground_directions(enemy: EnemyActor) -> void:
	for direction_index in range(32):
		var direction_ground := Vector2.from_angle(TAU * float(direction_index) / 32.0)
		var probe := CombatTarget.new()
		add_child(probe)
		probe.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			direction_ground * (enemy.aggro_radius_gu - 0.001)
		)
		enemy._retarget_timer = 0.0
		enemy._retarget(0.0)
		assert(enemy.target == probe, "aggro rejected inside GU boundary at direction %d" % direction_index)

		probe.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			direction_ground * (enemy.aggro_radius_gu + 0.01)
		)
		enemy._retarget_timer = 0.0
		enemy._retarget(0.0)
		assert(enemy.target == null, "aggro accepted outside GU boundary at direction %d" % direction_index)
		probe.free()


func _verify_fixed_area_range_in_32_ground_directions(enemy: EnemyActor) -> void:
	enemy.area_attack_rule = {
		"enabled": true,
		"range_gu": 4.0,
		"scope": "visible_actors",
		"targetMode": "all_combat_targets",
	}
	for direction_index in range(32):
		var direction_ground := Vector2.from_angle(TAU * float(direction_index) / 32.0)
		var probe := CombatTarget.new()
		add_child(probe)
		var chebyshev_axis := maxf(absf(direction_ground.x), absf(direction_ground.y))
		var square_boundary_distance_gu := 4.0 / chebyshev_axis
		probe.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			direction_ground * (square_boundary_distance_gu - 0.001)
		)
		assert(enemy._area_attack_targets().has(probe), "fixed-area rejected inside GU boundary at direction %d" % direction_index)
		probe.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			direction_ground * (square_boundary_distance_gu + 0.001)
		)
		assert(not enemy._area_attack_targets().has(probe), "fixed-area accepted outside GU boundary at direction %d" % direction_index)
		probe.free()


func _verify_boss_circle_range_in_32_ground_directions(enemy: EnemyActor) -> void:
	for direction_index in range(32):
		var direction_ground := Vector2.from_angle(TAU * float(direction_index) / 32.0)
		var probe := CombatTarget.new()
		add_child(probe)
		var target_radius_gu := enemy._target_combat_radius_gu(probe)
		probe.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			direction_ground * (6.0 + target_radius_gu - 0.001)
		)
		assert(enemy._boss_skill_targets(6.0).has(probe), "boss circle rejected inside GU boundary at direction %d" % direction_index)
		probe.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			direction_ground * (6.0 + target_radius_gu + 0.001)
		)
		assert(not enemy._boss_skill_targets(6.0).has(probe), "boss circle accepted outside GU boundary at direction %d" % direction_index)
		probe.free()


func _verify_boss_cone_uses_ground_direction(enemy: EnemyActor) -> void:
	const HALF_ANGLE := 0.4
	enemy.attack_min = 1
	enemy.attack_max = 1
	enemy.boss_rule = {
		"specialSkill": {
			"shape": "cone",
			"radius_gu": 5.0,
			"coneHalfAngleRadians": HALF_ANGLE,
			"damageMultiplier": 1,
		},
	}
	for direction_index in range(16):
		var center_direction_ground := Vector2.from_angle(TAU * float(direction_index) / 16.0)
		var inside_probe := CombatTarget.new()
		var outside_probe := CombatTarget.new()
		add_child(inside_probe)
		add_child(outside_probe)
		var target_radius_gu := enemy._target_combat_radius_gu(inside_probe)
		var footprint_angular_margin := asin(target_radius_gu / 4.9)
		var inside_direction_ground := center_direction_ground.rotated(
			HALF_ANGLE + footprint_angular_margin - 0.01
		)
		var outside_direction_ground := center_direction_ground.rotated(
			HALF_ANGLE + footprint_angular_margin + 0.01
		)
		inside_probe.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(inside_direction_ground * 4.9)
		outside_probe.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(outside_direction_ground * 4.9)
		enemy._boss_skill_direction_ground = center_direction_ground
		enemy.target = inside_probe
		enemy._boss_warning = 0.001
		enemy._update_boss_skill(0.002, 4.9)
		assert(inside_probe.current_hp == 9999, "boss cone rejected ground-angle interior at direction %d" % direction_index)
		assert(
			str(enemy._last_attack_footprint_snapshot.projection_relationship_id)
			== EnemyActor.PROJECTION_RELATIONSHIP_DIRECTED_CORE,
			"boss cone does not declare directed_core at direction %d" % direction_index,
		)
		enemy.target = outside_probe
		enemy._boss_warning = 0.001
		enemy._update_boss_skill(0.002, 4.9)
		assert(outside_probe.current_hp == 10000, "boss cone accepted ground-angle exterior at direction %d" % direction_index)
		inside_probe.free()
		outside_probe.free()


func _verify_boss_warning_projection_uses_gu(enemy: EnemyActor) -> void:
	const RADIUS_GU := 5.0
	assert(enemy.BOSS_WARNING_PROJECTION_CONTRACT_ID == "monster.boss.warning.ground_projection.v1")
	for shape in ["circle", "cone"]:
		var special := {
			"enabled": true,
			"shape": shape,
			"radius_gu": RADIUS_GU,
			"coneHalfAngleRadians": 0.4,
		}
		for direction_index in range(16):
			enemy._boss_skill_direction_ground = Vector2.from_angle(
				TAU * float(direction_index) / 16.0
			)
			var polygon_px := enemy.boss_warning_polygon_px(special)
			assert(polygon_px.size() >= 25, "boss warning projection lacks boundary detail")
			for point_px: Vector2 in polygon_px:
				if point_px.is_zero_approx():
					continue
				var point_ground_gu := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
					point_px
				)
				assert(
					absf(point_ground_gu.length() - RADIUS_GU) <= 0.00001,
					"boss %s warning diverged from GU gameplay radius at direction %d" % [
						shape, direction_index,
					],
				)


func _verify_safe_zone_uses_relative_ground_reference(enemy: EnemyActor) -> void:
	const RADIUS_GU := 9.0
	const MAP_DESIGN_CENTER_OFFSET_PX := Vector2(731.0, -419.0)
	var center_ground_gu := Vector2(133.5, 77.5)
	var center_screen_px := (
		MAP_DESIGN_CENTER_OFFSET_PX
		+ GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(center_ground_gu)
	)
	var zone := {
		"shape": "circle",
		"center": center_screen_px,
		"center_ground_gu": center_ground_gu,
		"radius_gu": RADIUS_GU,
		# Deliberately incompatible legacy screen circle: the formal GU branch
		# must win and remain independent of the 64x32 projection anisotropy.
		"radius": 1.0,
	}
	enemy.set_meta("safe_zones", [zone])
	assert(
		enemy.SAFE_ZONE_REFERENCE_CONTRACT_ID
		== "monster.safe_zone.relative_ground_reference.v1"
	)
	assert(enemy._point_inside_safe_zone(center_screen_px), "safe-zone centre lost its map reference")
	for direction_index in range(32):
		var direction_ground := Vector2.from_angle(TAU * float(direction_index) / 32.0)
		var inside_screen_px := center_screen_px + GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			direction_ground * (RADIUS_GU - 0.001)
		)
		var outside_screen_px := center_screen_px + GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			direction_ground * (RADIUS_GU + 0.01)
		)
		assert(
			enemy._point_inside_safe_zone(inside_screen_px),
			"safe zone rejected formal GU interior at map-offset direction %d" % direction_index,
		)
		assert(
			not enemy._point_inside_safe_zone(outside_screen_px),
			"safe zone accepted formal GU exterior at map-offset direction %d" % direction_index,
		)
	var polygon_ground_gu := [
		[center_ground_gu.x - 4.0, center_ground_gu.y - 3.0],
		[center_ground_gu.x + 4.0, center_ground_gu.y - 3.0],
		[center_ground_gu.x + 4.0, center_ground_gu.y + 3.0],
		[center_ground_gu.x - 4.0, center_ground_gu.y + 3.0],
	]
	var polygon_screen_px := PackedVector2Array()
	for raw_point: Array in polygon_ground_gu:
		polygon_screen_px.append(
			MAP_DESIGN_CENTER_OFFSET_PX
			+ GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				Vector2(float(raw_point[0]), float(raw_point[1]))
			)
		)
	var polygon_zone := {
		"shape": "polygon",
		"center": center_screen_px,
		"center_ground_gu": center_ground_gu,
		"polygon": polygon_screen_px,
		# Runtime JSON retains array pairs; this guards the adapter boundary and
		# prevents a PackedVector2Array-only implementation from silently falling
		# back to a screen-space polygon.
		"polygon_ground_gu": polygon_ground_gu,
	}
	enemy.set_meta("safe_zones", [polygon_zone])
	assert(enemy._point_inside_safe_zone(center_screen_px), "formal polygon rejected its centre")
	assert(
		not enemy._point_inside_safe_zone(
			center_screen_px + GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(Vector2(4.1, 0.0))
		),
		"formal polygon accepted a point beyond its ground edge",
	)
	enemy.set_meta("safe_zones", [{
		"shape": "circle",
		"center": center_screen_px,
		"radius": 99999.0,
	}])
	assert(
		not enemy._point_inside_safe_zone(center_screen_px),
		"incomplete screen-only safe zone re-entered formal monster gameplay",
	)
	enemy.set_meta("safe_zones", [])


func _verify_enemy_equal_time_movement_in_32_ground_directions(enemy: EnemyActor) -> void:
	const SPEED_GU_PER_SEC := 3.0
	const FIXED_DELTA_SECONDS := 1.0 / 60.0
	var reference_distance_gu := -1.0
	enemy.environment_blocker = null
	enemy.set_meta("safe_zones", [])
	for direction_index in range(32):
		await get_tree().physics_frame
		var direction_ground := Vector2.from_angle(TAU * float(direction_index) / 32.0)
		enemy.global_position = Vector2(1173.0, -629.0)
		enemy._last_environment_safe_position_px = enemy.global_position
		enemy._environment_guard_timer = 10.0
		enemy.velocity = GroundUnitSpaceScript.desired_screen_velocity_px_per_sec(
			direction_ground,
			SPEED_GU_PER_SEC,
		)
		enemy._move_with_spatial_rules(FIXED_DELTA_SECONDS)
		var actual_ground_motion_gu := enemy.actual_ground_motion_gu
		var actual_distance_gu := actual_ground_motion_gu.length()
		if reference_distance_gu < 0.0:
			reference_distance_gu = actual_distance_gu
		assert(
			absf(actual_distance_gu - reference_distance_gu) <= 0.00001,
			"EnemyActor equal-time GU motion differs at direction %d" % direction_index,
		)
		assert(
			actual_ground_motion_gu.normalized().dot(direction_ground) >= 0.99999,
			"EnemyActor ground direction drifted at direction %d" % direction_index,
		)
	assert(
		absf(reference_distance_gu - SPEED_GU_PER_SEC * FIXED_DELTA_SECONDS) <= 0.00001,
		"EnemyActor movement distance does not equal speed_gu_per_sec * delta",
	)


func _verify_visual_streaming_does_not_own_attack_state(enemy: EnemyActor) -> void:
	var visual: MonsterVisual = enemy.visual
	assert(visual.RESOURCE_RESIDENCY_CONTRACT_ID == "monster.visual.resource_residency.screen_px.v1")
	visual.play_attack(1.0)
	var attack_remaining_before := visual._attack_remaining
	visual.active_resources = {"idle": null}
	visual._release_resources()
	assert(
		is_equal_approx(visual._attack_remaining, attack_remaining_before),
		"render-resource eviction changed the monster attack state",
	)
	assert(visual.is_fallback_attacking(), "render-resource eviction lost attack presentation state")


func _verify_runtime_source_has_no_screen_distance_fallback() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/enemy.gd")
	var visual_source := FileAccess.get_file_as_string("res://scripts/monster_visual.gd")
	assert(not source.contains("global_position.distance_to("), "monster runtime still uses screen-pixel distance_to")
	assert(not source.contains("logical_tile_distance_for_world_offset"), "monster runtime still contains old logical-tile distance")
	assert(not source.contains("world_offset_to_fractional_tile_delta"), "monster runtime still contains old screen-to-tile fallback")
	assert(not source.contains("max(abs("), "monster runtime still contains Chebyshev distance")
	assert(not source.contains("radius_cells"), "monster runtime still exposes relocation radius in cells")
	assert(
		source.contains("signal relocation_requested(enemy: EnemyActor, radius_gu: float)"),
		"monster relocation signal does not expose a formal GU radius",
	)
	assert(not source.contains("target_node.collision_radius\n"), "monster contact still reads summon PX radius")
	assert(not source.contains("var collision_radius:"), "monster runtime still exposes an unsuffixed collision alias")
	assert(not source.contains("var move_speed:"), "monster runtime still exposes an unsuffixed movement alias")
	assert(not source.contains("var attack_range:"), "monster runtime still exposes an unsuffixed attack-range alias")
	assert(not source.contains("var aggro_radius:"), "monster runtime still exposes an unsuffixed aggro alias")
	assert(not source.contains("special.get(\"radius\", 155.0)"), "boss warning bypasses the GU range adapter")
	assert(
		not source.contains("WorldSpatialRulesScript.point_inside_safe_zone(point_screen_px, zone)"),
		"monster safe-zone gameplay still falls back to a screen-pixel shape",
	)
	assert(not visual_source.contains("actor.velocity.length_squared()"), "monster walk state still uses screen velocity")
	assert(visual_source.contains("actor.ground_velocity_gu_per_sec()"), "monster walk state lacks formal GU velocity")
	assert(visual_source.contains("func _inside_visual_distance_px(distance_px: float)"), "render residency PX boundary is not explicit")
	assert(not visual_source.contains("actor.collision_radius\n"), "monster visual still reads an unsuffixed PX radius")
	for formal_field in [
		"move_speed_gu_per_sec",
		"attack_range_gu",
		"aggro_radius_gu",
		"combat_radius_gu",
		"actual_ground_motion_gu",
	]:
		assert(source.contains(formal_field), "missing formal GU runtime field %s" % formal_field)
