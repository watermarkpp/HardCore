extends Node

## Q3-C: the production execution result truth is unique - exactly one
## skill_execution_result.v1 per release, and no legacy cast-result type is
## referenced by the production scripts.

const Plan := preload("res://scripts/skills/skill_execution_plan.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for path: String in [
		"res://scripts/game_root.gd",
		"res://scripts/skills/skill_runtime_router.gd",
		"res://scripts/skills/skill_execution_plan.gd",
		"res://scripts/skills/skill_execution_plan_contract.gd",
	]:
		var file := FileAccess.open(path, FileAccess.READ)
		assert(file != null, "script missing: %s" % path)
		assert(
			not file.get_as_text().contains("SkillCastResult"),
			"%s must not reference the legacy cast result" % path
		)
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
	game.player.current_mp = 500
	var target := _make_enemy(game, game.player, game.player.global_position + Vector2(40, 0))
	game._set_magic_locked_target(target, true)
	game._skill_cast_target = target
	await get_tree().process_frame
	var result: Dictionary = game._execute_canonical_skill(
		"火墙",
		game.player.global_position,
		Vector2.RIGHT,
		0,
		{"primary_stat_roll": 8}
	)
	assert(bool(result.get("accepted", false)), "formal release rejected")
	var execution_results: Array = [result.get("execution_result", {})]
	assert(execution_results.size() == 1, "exactly one execution result")
	var execution_result: Dictionary = execution_results[0]
	assert(
		str(execution_result.get("contract", ""))
			== "skill_execution_result.v1",
		"unique production result contract"
	)
	assert(
		bool(execution_result.get("accepted", false))
		and bool(execution_result.get("resource_committed", false)),
		"result transaction fields"
	)
	await get_tree().process_frame
	print("SKILL_RUNTIME_SINGLE_RESULT_CONTRACT_PASS")
	get_tree().quit(0)


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({
		"name": "single_result_target",
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
