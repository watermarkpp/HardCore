extends Node

## Q3-B: the canonical plan is immutable across the full formal consumption:
## hash before == hash after, snapshot hash unchanged, no consumer writes back.

const Plan := preload("res://scripts/skills/skill_execution_plan.gd")
const FIXTURE_MONSTER_ID := 19


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "法师"
	PlayerState.learned_skills = {"火墙": 3}
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var caster: PlayerCharacter = game.player
	caster.current_mp = 500
	var target := _make_enemy(game, caster, caster.global_position + Vector2(40, 0))
	game._set_magic_locked_target(target, true)
	game._skill_cast_target = target
	await get_tree().process_frame

	var result: Dictionary = game._execute_canonical_skill(
		"火墙",
		caster.global_position,
		Vector2.RIGHT,
		0,
		{"primary_stat_roll": 8}
	)
	assert(bool(result.get("accepted", false)), "fire wall release rejected")
	var plan: Dictionary = result.get("canonical_plan", {})
	var hash_before := str(plan.get("plan_hash", ""))
	assert(
		str(result.get("plan_hash_before", "")) == hash_before,
		"plan_hash_before must match the emitted hash"
	)
	assert(
		bool(result.get("plan_immutable", {}).get("valid", false)),
		"immutability check must pass after formal consumption"
	)
	var verify: Dictionary = Plan.verify_immutable(plan, hash_before)
	assert(bool(verify.get("valid", false)), "plan hash unchanged after consumption")
	assert(
		str(verify.get("snapshot_hash_before", ""))
			== str(verify.get("snapshot_hash_after", "")),
		"snapshot hash unchanged after consumption"
	)
	assert(
		str(plan.get("plan_hash", "")) == hash_before,
		"plan_hash field unchanged"
	)
	await get_tree().process_frame
	print("SKILL_PRODUCTION_PLAN_IMMUTABLE_PASS")
	get_tree().quit(0)


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	var canonical_data := GameData.get_monster_by_id(FIXTURE_MONSTER_ID)
	assert(
		not canonical_data.is_empty(),
		"plan immutable fixture monster_id=%d must exist" % FIXTURE_MONSTER_ID
	)
	enemy.setup(canonical_data, caster, false)
	assert(
		enemy.monster_id == FIXTURE_MONSTER_ID and not enemy.is_boss,
		"plan immutable fixture must remain an ordinary exact-ID target"
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
		"plan immutable fixture target must survive exact-ID admission"
	)
	return enemy
