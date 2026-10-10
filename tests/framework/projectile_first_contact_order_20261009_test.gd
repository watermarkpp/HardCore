extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Fixtures := preload("res://tests/helpers/combat_absolute_ground_fixtures.gd")
const Mapper := preload("res://scripts/map_coordinate_mapper.gd")
const SpatialIndexScript := preload("res://scripts/runtime_combat_spatial_index.gd")
const ProjectileScript := preload("res://scripts/skill_projectile.gd")

const SCENE_ID := "projectile_first_contact_order_20261009_test"
const MAP_ID := 9017


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var proof := Proof.new()
	var failures: Array[String] = []
	_test_pure_contact_parameters(proof, failures)
	await _test_nearest_contact_over_stable_order(proof, failures)
	await _test_nearest_contact_with_reverse_spawn_order(proof, failures)
	await _test_equal_contact_keeps_stable_order(proof, failures)
	await _test_actual_motion_can_dodge_segment(proof, failures)
	var written := proof.write_receipt(SCENE_ID, proof.records.size(), failures.size())
	if not written:
		failures.append("receipt write/validation failed")
	print(
		"PROJECTILE_FIRST_CONTACT_ORDER_20261009_%s checks=%d failures=%d"
		% ["PASS" if failures.is_empty() else "FAIL", proof.records.size(), failures.size()]
	)
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(proof: RefCounted, failures: Array[String], passed: bool, label: String) -> void:
	proof.record(passed, label)
	if not passed:
		failures.append(label)


func _test_pure_contact_parameters(proof: RefCounted, failures: Array[String]) -> void:
	var first := ProjectileScript.swept_segment_contact_parameter_gu(
		Vector2.ZERO, Vector2(10.0, 0.0), Vector2(5.0, 0.0), 0.5
	)
	_check(proof, failures, first > 0.0 and first < 0.5, "first contact precedes target centre")
	var tangent := ProjectileScript.swept_segment_contact_parameter_gu(
		Vector2.ZERO, Vector2(10.0, 0.0), Vector2(5.0, 0.5), 0.5
	)
	_check(proof, failures, tangent > 0.0 and tangent < 1.0, "tangent contact uses formal radius")
	_check(
		proof,
		failures,
		ProjectileScript.swept_segment_contact_parameter_gu(
			Vector2.ZERO, Vector2(10.0, 0.0), Vector2.ZERO, 0.1
		) == 0.0,
		"initial overlap contacts at t=0"
	)
	_check(
		proof,
		failures,
		ProjectileScript.swept_segment_contact_parameter_gu(
			Vector2(2.0, 2.0), Vector2(2.0, 2.0), Vector2(2.0, 2.0), 0.0
		) == 0.0,
		"zero-length segment inside footprint contacts"
	)
	_check(
		proof,
		failures,
		is_inf(ProjectileScript.swept_segment_contact_parameter_gu(
			Vector2(2.0, 2.0), Vector2(2.0, 2.0), Vector2(4.0, 4.0), 0.1
		)),
		"zero-length segment outside footprint misses"
	)


func _make_formal_projectile(index: SpatialIndexScript, origin: Vector2, maximum_distance := 20.0) -> SkillProjectile:
	var projectile := SkillProjectile.new()
	projectile.configure_runtime_map_projection(
		MAP_ID,
		Fixtures.ground_to_screen(Fixtures.DESIGN_256),
		Fixtures.screen_to_ground(Fixtures.DESIGN_256)
	)
	projectile.setup_ground_unit_projectile(
		Mapper.ground_position_gu_to_screen_position_px(origin, Fixtures.DESIGN_256),
		Vector2.RIGHT,
		maximum_distance,
		7,
		20.0,
		0.2,
		Vector2.ZERO,
		Color.WHITE,
		"damage",
		0,
		0.0,
		"wizard.fireball",
		"b02:first-contact"
	)
	projectile.configure_spatial_index(index)
	add_child(projectile)
	return projectile


func _test_nearest_contact_over_stable_order(proof: RefCounted, failures: Array[String]) -> void:
	var index: SpatialIndexScript = SpatialIndexScript.new()
	var far := Fixtures.make_enemy(self, index, 1, MAP_ID, Vector2(6.0, 0.0), Fixtures.DESIGN_256, 0.3)
	var near := Fixtures.make_enemy(self, index, 2, MAP_ID, Vector2(2.0, 0.0), Fixtures.DESIGN_256, 0.3)
	var far_before := far.current_hp
	var near_before := near.current_hp
	var projectile := _make_formal_projectile(index, Vector2.ZERO)
	projectile._physics_process(0.5)
	_check(proof, failures, near.current_hp < near_before, "near contact wins against earlier far stable order")
	_check(proof, failures, far.current_hp == far_before, "far candidate remains untouched")
	_check(proof, failures, projectile._broadphase_exact_test_count >= 2, "both candidates pass the exact eligibility gate")
	projectile.queue_free()
	far.queue_free()
	near.queue_free()
	index = null
	await get_tree().process_frame


func _test_nearest_contact_with_reverse_spawn_order(proof: RefCounted, failures: Array[String]) -> void:
	var index: SpatialIndexScript = SpatialIndexScript.new()
	var near := Fixtures.make_enemy(self, index, 1, MAP_ID, Vector2(2.0, 0.0), Fixtures.DESIGN_256, 0.3)
	var far := Fixtures.make_enemy(self, index, 2, MAP_ID, Vector2(6.0, 0.0), Fixtures.DESIGN_256, 0.3)
	var far_before := far.current_hp
	var near_before := near.current_hp
	var projectile := _make_formal_projectile(index, Vector2.ZERO)
	projectile._physics_process(0.5)
	_check(proof, failures, near.current_hp < near_before, "near contact remains first after reverse spawn order")
	_check(proof, failures, far.current_hp == far_before, "reverse-order far candidate remains untouched")
	projectile.queue_free()
	near.queue_free()
	far.queue_free()
	index = null
	await get_tree().process_frame


func _test_equal_contact_keeps_stable_order(proof: RefCounted, failures: Array[String]) -> void:
	var index: SpatialIndexScript = SpatialIndexScript.new()
	var first := Fixtures.make_enemy(self, index, 1, MAP_ID, Vector2(4.0, 0.0), Fixtures.DESIGN_256, 0.3)
	var second := Fixtures.make_enemy(self, index, 2, MAP_ID, Vector2(4.0, 0.0), Fixtures.DESIGN_256, 0.3)
	var first_before := first.current_hp
	var second_before := second.current_hp
	var projectile := _make_formal_projectile(index, Vector2.ZERO, 12.0)
	projectile._physics_process(0.5)
	_check(proof, failures, first.current_hp < first_before, "equal contact keeps lower stable order")
	_check(proof, failures, second.current_hp == second_before, "equal contact does not hit tie loser")
	projectile.queue_free()
	first.queue_free()
	second.queue_free()
	index = null
	await get_tree().process_frame


func _test_actual_motion_can_dodge_segment(proof: RefCounted, failures: Array[String]) -> void:
	var index: SpatialIndexScript = SpatialIndexScript.new()
	var enemy := Fixtures.make_enemy(self, index, 1, MAP_ID, Vector2(3.0, 0.0), Fixtures.DESIGN_256, 0.3)
	var before := enemy.current_hp
	var projectile := _make_formal_projectile(index, Vector2.ZERO, 12.0)
	Fixtures.move_enemy_absolute(enemy, Vector2(3.0, 3.0), Fixtures.DESIGN_256)
	projectile._physics_process(0.5)
	_check(proof, failures, enemy.current_hp == before, "actual target motion can dodge the swept segment")
	projectile.queue_free()
	enemy.queue_free()
	index = null
	await get_tree().process_frame
