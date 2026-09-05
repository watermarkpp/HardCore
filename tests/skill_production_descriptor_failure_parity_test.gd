extends Node

## Q3-B: descriptor creation happens after the single resource commit and does
## not roll back resources, touch cooldown or mutate the canonical plan. A
## failed descriptor leaves the other consumers and the execution result
## intact (frozen pre-migration semantics).

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
	PlayerState.learned_skills = {"火球术": 3, "雷电术": 3, "召唤骷髅": 3}
	PlayerState.recalculate_stats()
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_caster = _game.player
	_caster.current_mp = 500
	_target = _make_enemy(_game, _caster, _caster.global_position + Vector2(40, 0))
	await get_tree().process_frame

	_projectile_failure_case()
	_visual_failure_case()
	_summon_failure_case()
	await get_tree().process_frame
	print("SKILL_PRODUCTION_DESCRIPTOR_FAILURE_PARITY_PASS cases=3")
	get_tree().quit(0)


func _projectile_failure_case() -> void:
	_game._set_magic_locked_target(_target, true)
	_game._skill_cast_target = _target
	_caster.current_mp = 500
	Plan.reset_sentinels_for_tests()
	var result: Dictionary = _game._execute_canonical_skill(
		"火球术",
		_caster.global_position,
		Vector2.RIGHT,
		12
	)
	assert(bool(result.get("accepted", false)), "fireball release rejected")
	assert(
		Plan.sentinel_diagnostics().resource_commit_count == 1,
		"fireball resource must be committed exactly once"
	)
	var plan: Dictionary = result.get("canonical_plan", {})
	var hash_before := str(plan.get("plan_hash", ""))
	var variant: Dictionary = plan.duplicate(true)
	variant["projectile_descriptors"] = []
	var nodes: Array[Node2D] = _game._spawn_canonical_cast_nodes_from_plan(
		variant,
		_caster.global_position,
		Vector2.RIGHT,
		_target,
		_caster.global_position + Vector2(40, 0)
	)
	assert(nodes.is_empty(), "failed projectile descriptor must create no node")
	assert(
		str(plan.get("plan_hash", "")) == hash_before,
		"consumer failure must not mutate the canonical plan"
	)
	assert(
		Plan.sentinel_diagnostics().resource_commit_count == 1,
		"descriptor failure must not roll back committed resources"
	)
	var execution_result: Dictionary = result.get("execution_result", {})
	assert(
		(execution_result.get("spawned_projectile_ids", []) as Array).size() == 1,
		"execution result must record the successful release projectile"
	)


func _visual_failure_case() -> void:
	_game._set_magic_locked_target(_target, true)
	_game._skill_cast_target = _target
	_caster.current_mp = 500
	Plan.reset_sentinels_for_tests()
	var result: Dictionary = _game._execute_canonical_skill(
		"雷电术",
		_caster.global_position,
		Vector2.RIGHT,
		12
	)
	assert(bool(result.get("accepted", false)), "lightning release rejected")
	assert(
		Plan.sentinel_diagnostics().resource_commit_count == 1,
		"lightning resource must be committed exactly once"
	)
	var plan: Dictionary = result.get("canonical_plan", {})
	var hash_before := str(plan.get("plan_hash", ""))
	var variant: Dictionary = plan.duplicate(true)
	variant["presentation_actions"] = []
	var nodes: Array[Node2D] = _game._spawn_canonical_cast_nodes_from_plan(
		variant,
		_caster.global_position,
		Vector2.RIGHT,
		_target,
		_caster.global_position + Vector2(40, 0)
	)
	assert(nodes.is_empty(), "failed visual descriptor must create no node")
	assert(
		str(plan.get("plan_hash", "")) == hash_before,
		"visual failure must not mutate the canonical plan"
	)
	assert(
		Plan.sentinel_diagnostics().resource_commit_count == 1,
		"visual failure must not roll back committed resources"
	)


func _summon_failure_case() -> void:
	PlayerState.select_profession("道士")
	PlayerState.learned_skills = {"召唤骷髅": 3}
	PlayerState.inventory = [{"name": "护身符", "count": 5}]
	PlayerState.recalculate_stats()
	_caster.current_mp = 500
	Plan.reset_sentinels_for_tests()
	var result: Dictionary = _game._execute_canonical_skill(
		"召唤骷髅",
		_caster.global_position,
		Vector2.DOWN,
		0
	)
	assert(bool(result.get("accepted", false)), "summon release rejected")
	assert(_game._canonical_main_pet() != null, "summon pet must exist")
	var plan: Dictionary = result.get("canonical_plan", {})
	var hash_before := str(plan.get("plan_hash", ""))
	var variant: Dictionary = plan.duplicate(true)
	variant["summon_descriptors"] = []
	var nodes: Array[Node2D] = _game._spawn_canonical_cast_nodes_from_plan(
		variant,
		_caster.global_position,
		Vector2.DOWN,
		_target,
		_caster.global_position + Vector2(40, 0)
	)
	assert(nodes.is_empty(), "failed summon descriptor must create no node")
	assert(
		str(plan.get("plan_hash", "")) == hash_before,
		"summon failure must not mutate the canonical plan"
	)
	assert(
		_game._canonical_main_pet() != null,
		"successful descriptors from the real release must be preserved"
	)
	assert(
		Plan.sentinel_diagnostics().resource_commit_count == 1,
		"summon failure must not roll back committed resources"
	)


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	var canonical_data := GameData.get_monster_by_id(FIXTURE_MONSTER_ID)
	assert(
		not canonical_data.is_empty(),
		"descriptor failure fixture monster_id=%d must exist" % FIXTURE_MONSTER_ID
	)
	enemy.setup(canonical_data, caster, false)
	assert(
		enemy.monster_id == FIXTURE_MONSTER_ID and not enemy.is_boss,
		"descriptor failure fixture must remain an ordinary exact-ID target"
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
		"descriptor failure fixture target must survive exact-ID admission"
	)
	return enemy
