extends Node

## Q3-B: formal rejections (unknown skill, invalid target, insufficient
## resource, invalid snapshot, map mismatch) commit no resources, no cooldown
## and create no gameplay nodes; reasons are normalized consistently.

const Plan := preload("res://scripts/skills/skill_execution_plan.gd")
const FIXTURE_MONSTER_ID := 19

var _game: Node
var _caster: PlayerCharacter
var _target: EnemyActor


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "法师"
	PlayerState.learned_skills = {"雷电术": 3, "火球术": 3}
	PlayerState.recalculate_stats()
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_caster = _game.player
	_caster.current_mp = 500
	_target = _make_enemy(_game, _caster, _caster.global_position + Vector2(40, 0))
	await get_tree().process_frame

	_rejection_case(
		"unknown_skill",
		"不存在的技能",
		{},
		Plan.REASON_UNKNOWN_SKILL,
		0
	)
	_game.auto_target_enabled = false
	_game._skill_cast_target = null
	_game._cancel_magic_target()
	_rejection_case(
		"invalid_target",
		"雷电术",
		{"auto_target_enabled": false},
		Plan.REASON_INVALID_TARGET,
		1
	)
	_game.auto_target_enabled = true
	_game._set_magic_locked_target(_target, true)
	_game._skill_cast_target = _target
	_caster.current_mp = 0
	_rejection_case(
		"insufficient_resource",
		"雷电术",
		{},
		Plan.REASON_INSUFFICIENT_RESOURCE,
		1
	)
	_caster.current_mp = 500
	_game._skill_cast_target = _target
	_rejection_case(
		"invalid_snapshot",
		"火球术",
		{
			"skill_footprint_snapshot": {
				"contract_id": "bogus.snapshot",
				"shape_type": "circle",
			},
		},
		Plan.REASON_INVALID_SNAPSHOT,
		1
	)
	var wrong_map_snapshot := {
		"contract_id": "skills.footprint_snapshot.v1",
		"shape_contract_id": "skills.footprint.circle.v1",
		"unit_contract_id": "ground.unit.space.v1",
		"projection_contract_id": "ground.unit.projection.v1",
		"snapshot_id": "wizard.fireball:map_mismatch",
		"skill_id": "wizard.fireball",
		"release_id": "map_mismatch",
		"shape_type": "circle",
		"coordinate_space": "runtime_map_absolute_ground_gu",
		"runtime_map_id": 999,
		"projection_origin_ground_gu": Vector2.ZERO,
		"origin_ground_gu": Vector2.ZERO,
		"effect_length_gu": 2.0,
		"effect_width_gu": 2.0,
		"polygon_ground_gu": PackedVector2Array([
			Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0), Vector2(0, 1),
		]),
	}
	_rejection_case(
		"map_mismatch",
		"火球术",
		{"skill_footprint_snapshot": wrong_map_snapshot},
		Plan.REASON_INVALID_SNAPSHOT,
		1
	)
	await get_tree().process_frame
	print("SKILL_PRODUCTION_REJECTION_FLOW_PASS cases=5")
	get_tree().quit(0)


func _rejection_case(
	label: String,
	skill_name: String,
	extra: Dictionary,
	expected_reason: String,
	expected_plan_count: int
) -> void:
	Plan.reset_sentinels_for_tests()
	var result: Dictionary = _game._execute_canonical_skill(
		skill_name,
		_caster.global_position,
		Vector2.RIGHT,
		12,
		extra,
		true
	)
	assert(
		not bool(result.get("accepted", true)),
		"%s must be rejected" % label
	)
	assert(
		str(result.get("reason", "")) == expected_reason,
		"%s reason mismatch: %s" % [label, str(result.get("reason", ""))]
	)
	var diag := Plan.sentinel_diagnostics()
	assert(
		diag.resource_commit_count == 0,
		"%s must not commit resources" % label
	)
	assert(
		diag.cooldown_commit_count == 0,
		"%s must not commit cooldown" % label
	)
	assert(
		diag.canonical_plan_build_count == expected_plan_count,
		"%s canonical plan build count mismatch (expected %d)"
		% [label, expected_plan_count]
	)
	var execution_result: Dictionary = result.get("execution_result", {})
	if expected_plan_count > 0:
		assert(
			not bool(execution_result.get("accepted", true)),
			"%s execution result must be rejected" % label
		)
		assert(
			not bool(execution_result.get("resource_committed", true)),
			"%s execution result resource_committed" % label
		)
		assert(
			not bool(execution_result.get("cooldown_committed", true)),
			"%s execution result cooldown_committed" % label
		)
	var projectile_nodes := _game.get_children().filter(
		func(node: Node) -> bool: return node is SkillProjectile
	)
	assert(
		(projectile_nodes as Array).is_empty(),
		"%s must create no projectile nodes" % label
	)


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	var canonical_data := GameData.get_monster_by_id(FIXTURE_MONSTER_ID)
	assert(
		not canonical_data.is_empty(),
		"rejection flow fixture monster_id=%d must exist" % FIXTURE_MONSTER_ID
	)
	enemy.setup(canonical_data, caster, false)
	assert(
		enemy.monster_id == FIXTURE_MONSTER_ID and not enemy.is_boss,
		"rejection flow fixture must remain an ordinary exact-ID target"
	)
	enemy.max_hp = 9999
	enemy.current_hp = enemy.max_hp
	enemy.global_position = position
	enemy.control_time = 60.0
	game.add_child(enemy)
	assert(
		is_instance_valid(enemy)
		and not enemy.is_queued_for_deletion()
		and enemy.can_receive_damage(),
		"rejection flow fixture target must survive exact-ID admission"
	)
	return enemy
