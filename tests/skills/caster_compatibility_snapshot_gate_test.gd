extends Node

const CasterRuntime := preload("res://scripts/caster_skill_runtime.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")


func _ready() -> void:
	_verify_missing_snapshot_is_blocked()
	_verify_explicit_test_adapter_is_audited()
	_verify_valid_snapshot_filters_targets()
	print(
		"CASTER_COMPATIBILITY_SNAPSHOT_GATE_PASS: production compatibility "
		+ "entry rejects missing snapshots; explicit test adapter is audited"
	)
	get_tree().quit(0)


func _verify_missing_snapshot_is_blocked() -> void:
	var target := _target_at_ground_gu(Vector2(1.0, 0.0))
	var result := CasterRuntime.execute_cast(
		_line_plan("line:no-snapshot"),
		{
			"affected_targets": [target],
			"origin": Vector2.ZERO,
			"direction": Vector2.RIGHT,
		}
	)
	assert(result.adapter_required == "skill_footprint_snapshot")
	assert(result.spatial_snapshot_gate == "blocked_missing_release_snapshot")
	assert(result.applied_count == 0)
	assert(target.current_hp == 100)
	assert(result.nodes.is_empty())
	target.free()


func _verify_explicit_test_adapter_is_audited() -> void:
	var target := _target_at_ground_gu(Vector2(1.0, 0.0))
	var result := CasterRuntime.execute_cast(
		_line_plan("line:test-adapter"),
		{
			"affected_targets": [target],
			"origin": Vector2.ZERO,
			"direction": Vector2.RIGHT,
			"spatial_test_adapter_id": (
				CasterRuntime.NON_PRODUCTION_SPATIAL_ADAPTER_ID
			),
		}
	)
	assert(result.adapter_required.is_empty())
	assert(result.compatibility_adapter_used)
	assert(result.compatibility_adapter_id == (
		CasterRuntime.NON_PRODUCTION_SPATIAL_ADAPTER_ID
	))
	assert(result.spatial_snapshot_gate == "explicit_non_production_adapter")
	assert(result.applied_count == 1)
	assert(target.current_hp == 89)
	target.free()


func _verify_valid_snapshot_filters_targets() -> void:
	var release_id := "line:formal"
	var release_snapshot := Snapshot.create_directed_rectangle(
		"wizard.hellfire",
		release_id,
		Vector2.ZERO,
		Vector2.RIGHT,
		5.0,
		1.0
	)
	var inside := _target_at_ground_gu(Vector2(4.9, 0.45))
	var outside := _target_at_ground_gu(Vector2(4.9, 0.7))
	var plan := _line_plan(release_id)
	plan["skill_footprint_snapshot"] = release_snapshot
	var result := CasterRuntime.execute_cast(
		plan,
		{
			"affected_targets": [inside, outside],
			"origin": Vector2.ZERO,
			"direction": Vector2.RIGHT,
		}
	)
	assert(result.adapter_required.is_empty())
	assert(not result.compatibility_adapter_used)
	assert(result.spatial_snapshot_gate == "validated_release_snapshot")
	assert(result.skill_footprint_snapshot == release_snapshot)
	assert(result.applied_count == 1)
	assert(inside.current_hp == 89)
	assert(outside.current_hp == 100)
	inside.free()
	outside.free()


func _line_plan(release_id: String) -> Dictionary:
	return {
		"skill_id": "wizard.hellfire",
		"success": true,
		"operation": "line_damage",
		"damage": 11,
		"damage_before_evasion": 11,
		"maximum_range_gu": 5.0,
		"release_id": release_id,
		"visual": {"status": "no_runtime_visual"},
	}


func _target_at_ground_gu(center_ground_gu: Vector2) -> EnemyActor:
	var target := EnemyActor.new()
	target.max_hp = 100
	target.current_hp = 100
	target.combat_radius_gu = 0.0
	target.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		center_ground_gu
	)
	return target
