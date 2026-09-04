extends Node

const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const Summon := preload("res://scripts/summon_actor.gd")


func _configure_summon_map(summon: Summon) -> void:
	summon.configure_runtime_map_projection(
		9001,
		Callable(self, "_test_ground_to_screen")
	, GroundUnit.screen_delta_px_to_ground_delta_gu)


func _test_ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _ready() -> void:
	_verify_spawn_destination_footprints()
	_verify_skeleton_release_contact()
	_verify_divine_beast_directed_core()
	print(
		"SUMMON_RELEASE_FOOTPRINT_SNAPSHOT_PASS: summon destination, skeleton "
		+ "contact and divine-beast directed core remain distinct release contracts"
	)
	get_tree().quit(0)


func _verify_spawn_destination_footprints() -> void:
	var owner := PlayerCharacter.new()
	for skill_id: String in [
		"taoist.summon_skeleton",
		"taoist.summon_divine_beast",
	]:
		var summon := Summon.new()
		summon.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
			Vector2(6.5, -4.25)
		)
		summon.setup(owner, skill_id, 20, 3, skill_id, 35)
		_configure_summon_map(summon)
		summon.configure_spawn_release_footprint("%s:release:4" % skill_id)
		var snapshot: Dictionary = summon.summon_spawn_footprint_snapshot
		assert(Snapshot.has_legacy_base_contract(snapshot))
		assert(snapshot.is_read_only())
		assert(snapshot.shape_type == Snapshot.SHAPE_TARGET_FOOTPRINT)
		assert(snapshot.release_id == "%s:release:4" % skill_id)
		assert((snapshot.target_center_ground_gu as Vector2).is_equal_approx(
			Vector2(6.5, -4.25)
		))
		summon.free()
	owner.free()


func _verify_skeleton_release_contact() -> void:
	var owner := PlayerCharacter.new()
	var skeleton := Summon.new()
	skeleton.setup(owner, "skeleton", 20, 3, "taoist.summon_skeleton", 35)
	_configure_summon_map(skeleton)
	skeleton.combat_radius_gu = 0.30
	skeleton.attack_range_gu = 1.00
	var target := _target_at_ground_gu(Vector2(1.50, 0.0), 0.20)
	var snapshot := skeleton.create_attack_release_footprint_snapshot(target)
	assert(Snapshot.has_legacy_base_contract(snapshot))
	assert(snapshot.shape_type == Snapshot.SHAPE_CIRCLE)
	assert(skeleton.last_attack_relation == "release_contact")
	assert(is_equal_approx(float(snapshot.radius_gu), 1.30))
	assert(skeleton.attack_release_snapshot_intersects_target(snapshot, target))
	target.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		Vector2(1.501, 0.0)
	)
	assert(not skeleton.attack_release_snapshot_intersects_target(snapshot, target))
	skeleton.free()
	target.free()
	owner.free()


func _verify_divine_beast_directed_core() -> void:
	var owner := PlayerCharacter.new()
	var divine := Summon.new()
	divine.setup(
		owner,
		"divine_beast",
		20,
		3,
		"taoist.summon_divine_beast",
		35
	)
	_configure_summon_map(divine)
	divine.combat_radius_gu = 0.45
	divine.attack_range_gu = 1.55
	var direction_ground_gu := Vector2(0.6, 0.8).normalized()
	var target := _target_at_ground_gu(direction_ground_gu * 2.20, 0.20)
	var snapshot := divine.create_attack_release_footprint_snapshot(target)
	assert(Snapshot.has_legacy_base_contract(snapshot))
	assert(snapshot.shape_type == Snapshot.SHAPE_DIRECTED_RECTANGLE)
	assert(divine.last_attack_relation == "directed_core")
	assert(is_equal_approx(float(snapshot.effect_length_gu), 2.0))
	assert(is_equal_approx(float(snapshot.effect_width_gu), 0.90))
	assert((snapshot.direction_ground_gu as Vector2).is_equal_approx(
		direction_ground_gu
	))
	assert(divine.attack_release_snapshot_intersects_target(snapshot, target))
	target.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		direction_ground_gu * 2.201
	)
	assert(not divine.attack_release_snapshot_intersects_target(snapshot, target))
	divine.free()
	target.free()
	owner.free()


func _target_at_ground_gu(center_ground_gu: Vector2, radius_gu: float) -> EnemyActor:
	var target := EnemyActor.new()
	target.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		center_ground_gu
	)
	target.combat_radius_gu = radius_gu
	return target
