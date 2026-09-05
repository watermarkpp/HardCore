extends Node

## Q3-B: every formal release produces a skill_execution_result.v1 with the
## full frozen field set; rejections carry accepted=false and zero commits.

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
	PlayerState.learned_skills = {"火墙": 3, "雷电术": 3}
	PlayerState.recalculate_stats()
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_caster = _game.player
	_target = _make_enemy(_game, _caster, _caster.global_position + Vector2(40, 0))
	await get_tree().process_frame

	_game._set_magic_locked_target(_target, true)
	_game._skill_cast_target = _target
	_caster.current_mp = 500
	var result: Dictionary = _game._execute_canonical_skill(
		"火墙",
		_caster.global_position,
		Vector2.RIGHT,
		0,
		{"primary_stat_roll": 8}
	)
	assert(bool(result.get("accepted", false)), "fire wall release rejected")
	_check_success_result(result)

	_caster.current_mp = 0
	var rejected: Dictionary = _game._execute_canonical_skill(
		"雷电术",
		_caster.global_position,
		Vector2.RIGHT,
		12
	)
	assert(
		not bool(rejected.get("accepted", true)),
		"insufficient MP must reject the release"
	)
	_check_rejection_result(rejected)
	await get_tree().process_frame
	print("SKILL_EXECUTION_RESULT_CONTRACT_PASS")
	get_tree().quit(0)


func _check_success_result(result: Dictionary) -> void:
	var plan: Dictionary = result.get("canonical_plan", {})
	var execution_result: Dictionary = result.get("execution_result", {})
	assert(
		str(execution_result.get("contract", "")) == "skill_execution_result.v1",
		"result contract"
	)
	assert(
		str(execution_result.get("plan_id", "")) == str(plan.get("plan_id", "")),
		"result plan_id"
	)
	assert(
		str(execution_result.get("release_id", ""))
			== str(plan.get("release_id", "")),
		"result release_id"
	)
	assert(bool(execution_result.get("accepted", false)), "result accepted")
	assert(
		str(execution_result.get("rejection_reason", "")) == "accepted",
		"result rejection_reason"
	)
	assert(bool(execution_result.get("resource_committed", false)), "resource committed")
	assert(
		execution_result.has("cooldown_committed"),
		"cooldown_committed field missing"
	)
	assert(execution_result.get("damage_results") is Array, "damage_results")
	assert(execution_result.get("status_results") is Array, "status_results")
	assert(
		execution_result.get("spawned_projectile_ids") is Array,
		"spawned_projectile_ids"
	)
	assert(
		execution_result.get("spawned_ground_effect_ids") is Array,
		"spawned_ground_effect_ids"
	)
	assert(
		execution_result.get("spawned_summon_ids") is Array,
		"spawned_summon_ids"
	)
	assert(
		execution_result.get("created_visual_ids") is Array,
		"created_visual_ids"
	)
	assert(
		str(execution_result.get("snapshot_id", ""))
			== str(plan.get("snapshot_id", "")),
		"result snapshot_id"
	)
	assert(
		execution_result.get("side_effect_count") is int,
		"side_effect_count"
	)


func _check_rejection_result(result: Dictionary) -> void:
	var execution_result: Dictionary = result.get("execution_result", {})
	assert(
		not bool(execution_result.get("accepted", true)),
		"rejected result accepted flag"
	)
	assert(
		not bool(execution_result.get("resource_committed", true)),
		"rejected result must not commit resources"
	)
	assert(
		not bool(execution_result.get("cooldown_committed", true)),
		"rejected result must not commit cooldown"
	)
	assert(
		str(execution_result.get("rejection_reason", "")) == "insufficient_resource",
		"rejection reason normalization"
	)


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	var canonical_data := GameData.get_monster_by_id(FIXTURE_MONSTER_ID)
	assert(
		not canonical_data.is_empty(),
		"execution-result fixture monster_id=%d must exist" % FIXTURE_MONSTER_ID
	)
	enemy.setup(canonical_data, caster, false)
	assert(
		enemy.monster_id == FIXTURE_MONSTER_ID and not enemy.is_boss,
		"execution-result fixture must remain an ordinary exact-ID target"
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
		"execution-result fixture target must survive exact-ID admission"
	)
	return enemy
