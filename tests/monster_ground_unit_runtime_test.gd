extends Node2D


const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const RUNTIME_TEST_MONSTER := {
	"monsterId": -9100,
	"name": "GU runtime probe",
	"hp": 100,
	"runtimeProjection": {
		"move_speed_gu_per_sec": 1.0,
		"attack_range_gu": 1.5,
		"aggro_radius_gu": 12.0,
	},
}


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
	enemy.setup(RUNTIME_TEST_MONSTER, null, false)
	enemy.global_position = Vector2.ZERO
	enemy.set_meta("spawn_position", Vector2.ZERO)
	enemy.set_meta("safe_zones", [])
	add_child(enemy)
	enemy.set_physics_process(false)

	_verify_aggro_and_leash_in_32_ground_directions(enemy)
	_verify_fixed_area_range_in_32_ground_directions(enemy)
	_verify_boss_circle_range_in_32_ground_directions(enemy)
	_verify_boss_cone_uses_ground_direction(enemy)
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
		probe.queue_free()
		await get_tree().process_frame


func _verify_fixed_area_range_in_32_ground_directions(enemy: EnemyActor) -> void:
	enemy.area_attack_rule = {"enabled": true, "range_gu": 4.0}
	for direction_index in range(32):
		var direction_ground := Vector2.from_angle(TAU * float(direction_index) / 32.0)
		var probe := CombatTarget.new()
		add_child(probe)
		probe.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(direction_ground * 3.999)
		assert(enemy._area_attack_targets().has(probe), "fixed-area rejected inside GU boundary at direction %d" % direction_index)
		probe.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(direction_ground * 4.01)
		assert(not enemy._area_attack_targets().has(probe), "fixed-area accepted outside GU boundary at direction %d" % direction_index)
		probe.queue_free()
		await get_tree().process_frame


func _verify_boss_circle_range_in_32_ground_directions(enemy: EnemyActor) -> void:
	for direction_index in range(32):
		var direction_ground := Vector2.from_angle(TAU * float(direction_index) / 32.0)
		var probe := CombatTarget.new()
		add_child(probe)
		probe.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(direction_ground * 5.999)
		assert(enemy._boss_skill_targets(6.0).has(probe), "boss circle rejected inside GU boundary at direction %d" % direction_index)
		probe.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(direction_ground * 6.01)
		assert(not enemy._boss_skill_targets(6.0).has(probe), "boss circle accepted outside GU boundary at direction %d" % direction_index)
		probe.queue_free()
		await get_tree().process_frame


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
		var inside_direction_ground := center_direction_ground.rotated(HALF_ANGLE - 0.01)
		var outside_direction_ground := center_direction_ground.rotated(HALF_ANGLE + 0.01)
		var inside_probe := CombatTarget.new()
		var outside_probe := CombatTarget.new()
		add_child(inside_probe)
		add_child(outside_probe)
		inside_probe.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(inside_direction_ground * 4.9)
		outside_probe.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(outside_direction_ground * 4.9)
		enemy._boss_skill_direction_ground = center_direction_ground
		enemy.target = inside_probe
		enemy._boss_warning = 0.001
		enemy._update_boss_skill(0.002, 4.9)
		assert(inside_probe.current_hp == 9999, "boss cone rejected ground-angle interior at direction %d" % direction_index)
		enemy.target = outside_probe
		enemy._boss_warning = 0.001
		enemy._update_boss_skill(0.002, 4.9)
		assert(outside_probe.current_hp == 10000, "boss cone accepted ground-angle exterior at direction %d" % direction_index)
		inside_probe.queue_free()
		outside_probe.queue_free()
		await get_tree().process_frame


func _verify_runtime_source_has_no_screen_distance_fallback() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/enemy.gd")
	assert(not source.contains("global_position.distance_to("), "monster runtime still uses screen-pixel distance_to")
	assert(not source.contains("logical_tile_distance_for_world_offset"), "monster runtime still contains old logical-tile distance")
	assert(not source.contains("world_offset_to_fractional_tile_delta"), "monster runtime still contains old screen-to-tile fallback")
	assert(not source.contains("max(abs("), "monster runtime still contains Chebyshev distance")
	for formal_field in [
		"move_speed_gu_per_sec",
		"attack_range_gu",
		"aggro_radius_gu",
		"combat_radius_gu",
		"actual_ground_motion_gu",
	]:
		assert(source.contains(formal_field), "missing formal GU runtime field %s" % formal_field)
