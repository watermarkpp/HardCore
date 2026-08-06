extends Node

const CasterRuntime := preload("res://scripts/caster_skill_runtime.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Projectile := preload("res://scripts/skill_projectile.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")


func _test_absolute_context() -> Dictionary:
	return Snapshot.make_absolute_runtime_context(
		"test_map",
		Vector2.ZERO,
		Vector2.ZERO,
		Callable(self, "_test_ground_to_screen")
	)


func _test_ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _ready() -> void:
	_verify_projectile_release_sweeps()
	_verify_target_single_release_footprint()
	print(
		"PROJECTILE_TARGET_RELEASE_SNAPSHOT_PASS: three formal projectiles use "
		+ "immutable GU sweeps and targeted lightning consumes one target footprint"
	)
	get_tree().quit(0)


func _verify_projectile_release_sweeps() -> void:
	var origin_ground_gu := Vector2(4.25, -1.75)
	var origin_screen_px := GroundUnit.ground_delta_gu_to_screen_delta_px(
		origin_ground_gu
	)
	var direction_ground_gu := Vector2(0.6, 0.8).normalized()
	for skill_id: String in [
		"wizard.fireball",
		"wizard.great_fireball",
		"taoist.soul_fire_talisman",
	]:
		var projectile := Projectile.new()
		projectile.setup_ground_unit_projectile(
			origin_screen_px,
			direction_ground_gu,
			9.0,
			12,
			5.0,
			0.25,
			Vector2(6.0, -2.0),
			Color.WHITE,
			"damage",
			0,
			0.0,
			skill_id,
			"%s:release:7" % skill_id
		)
		var snapshot: Dictionary = projectile.skill_footprint_snapshot
		assert(Snapshot.has_legacy_base_contract(snapshot))
		assert(snapshot.is_read_only())
		assert(snapshot.shape_type == Snapshot.SHAPE_SWEPT_CAPSULE_PATH)
		assert(snapshot.skill_id == skill_id)
		assert(snapshot.release_id == "%s:release:7" % skill_id)
		assert((snapshot.segment_start_ground_gu as Vector2).is_equal_approx(
			origin_ground_gu
		))
		assert((snapshot.segment_end_ground_gu as Vector2).is_equal_approx(
			origin_ground_gu + direction_ground_gu * 9.0
		))
		assert(is_equal_approx(float(snapshot.path_radius_gu), 0.25))
		var side_ground_gu := Vector2(
			-direction_ground_gu.y, direction_ground_gu.x
		)
		var middle_ground_gu := origin_ground_gu + direction_ground_gu * 4.5
		assert(projectile.release_snapshot_intersects_target_footprint_ground_gu(
			middle_ground_gu + side_ground_gu * 0.50, 0.25
		))
		assert(not projectile.release_snapshot_intersects_target_footprint_ground_gu(
			middle_ground_gu + side_ground_gu * 0.501, 0.25
		))
		add_child(projectile)
		projectile._physics_process(0.10)
		var segment_snapshot: Dictionary = (
			projectile.last_segment_footprint_snapshot
		)
		assert(Snapshot.has_legacy_base_contract(segment_snapshot))
		assert(segment_snapshot.is_read_only())
		assert(segment_snapshot.parent_snapshot_id == snapshot.snapshot_id)
		assert(segment_snapshot.segment_index == 0)
		assert(segment_snapshot.release_id.ends_with(":segment:0"))
		assert(is_equal_approx(
			float(segment_snapshot.effect_length_gu),
			projectile.speed_gu_per_sec * 0.10
		))
		projectile.free()


func _verify_target_single_release_footprint() -> void:
	var primary := EnemyActor.new()
	primary.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		Vector2(7.0, 3.0)
	)
	primary.combat_radius_gu = 0.35
	primary.max_hp = 100
	primary.current_hp = 100
	primary.monster_data = {"antiMagic": 0}
	var unrelated := EnemyActor.new()
	unrelated.global_position = primary.global_position
	unrelated.combat_radius_gu = 0.35
	unrelated.max_hp = 100
	unrelated.current_hp = 100
	unrelated.monster_data = {"antiMagic": 0}
	var result := CasterRuntime.execute_cast(
		{
			"skill_id": "wizard.lightning",
			"success": true,
			"operation": "target_damage",
			"damage": 10,
			"damage_before_evasion": 10,
			"visual": {},
			"release_id": "wizard.lightning:release:11",
		},
		{
			"primary_target": primary,
			"affected_targets": [primary, unrelated],
			"anti_magic_roll": 999,
			"snapshot_coordinate_context": _test_absolute_context(),
		}
	)
	var snapshot: Dictionary = result.skill_footprint_snapshot
	assert(Snapshot.has_legacy_base_contract(snapshot))
	assert(snapshot.is_read_only())
	assert(snapshot.shape_type == Snapshot.SHAPE_TARGET_FOOTPRINT)
	assert(snapshot.target_instance_id == primary.get_instance_id())
	assert(snapshot.release_id == "wizard.lightning:release:11")
	assert(result.applied_count == 1)
	assert(primary.current_hp == 90)
	assert(unrelated.current_hp == 100)
	primary.free()
	unrelated.free()
