extends Node

## Q3-B: the formal GameRoot entry builds exactly ONE canonical plan object
## through SkillRuntimeRouter.build_canonical_plan; the plan is immutable and
## the result carries a skill_execution_result.v1.

const Plan := preload("res://scripts/skills/skill_execution_plan.gd")


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

	Plan.reset_sentinels_for_tests()
	var result: Dictionary = game._execute_canonical_skill(
		"火墙",
		caster.global_position,
		Vector2.RIGHT,
		0,
		{"primary_stat_roll": 8}
	)
	assert(bool(result.get("accepted", false)), "火墙 formal entry rejected")
	var plan: Dictionary = result.get("canonical_plan", {})
	assert(
		str(plan.get("contract", "")) == "skill_execution_plan.v1",
		"canonical plan contract missing"
	)
	assert(
		str(plan.get("created_by", "")) == "canonical_planner.v1",
		"plan must be built by the canonical planner"
	)
	assert(
		str(result.get("plan_hash_before", "")) == str(plan.get("plan_hash", "")),
		"plan_hash_before must equal the emitted plan hash"
	)
	assert(
		bool(result.get("plan_immutable", {}).get("valid", false)),
		"plan immutability must verify after consumption"
	)
	var execution_result: Dictionary = result.get("execution_result", {})
	assert(
		str(execution_result.get("contract", "")) == "skill_execution_result.v1",
		"execution result contract missing"
	)
	assert(
		str(execution_result.get("plan_id", "")) == str(plan.get("plan_id", "")),
		"execution result must reference the canonical plan id"
	)
	assert(
		Plan.sentinel_diagnostics().canonical_plan_build_count == 1,
		"formal entry must build exactly one canonical plan"
	)
	assert(
		Plan.sentinel_diagnostics().release_id_generation_count == 1,
		"formal entry must generate exactly one release id"
	)
	var field_count := 0
	for child: Node in game.get_children():
		if child is FireWallFieldController:
			field_count += 1
			assert(
				(child as FireWallFieldController).visual_cells.size() == 4,
				"fire wall must own exactly 4 pure-visual cells"
			)
	assert(field_count == 1, "fire wall must create exactly one controller")
	await get_tree().process_frame
	print("SKILL_PRODUCTION_CANONICAL_ENTRY_PASS plan=%s" % str(plan.get("plan_id", "")))
	get_tree().quit(0)


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({
		"name": "canonical_entry_target",
		"hp": 9999,
		"attackMin": 1,
		"attackMax": 1,
		"level": 1,
		"anti_magic_points": 0,
		"magic_defense_min": 0,
		"magic_defense_max": 0,
	}, caster, false)
	enemy.global_position = position
	enemy.control_time = 60.0
	game.add_child(enemy)
	return enemy
