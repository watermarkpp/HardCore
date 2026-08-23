extends Node

## Q3-C: the formal production chain must not construct a second visual plan.
## The legacy visual-plan path was deleted; this test statically guards the
## production scripts and verifies a formal release builds exactly one
## canonical plan with no presentation-only plan object.

const Plan := preload("res://scripts/skills/skill_execution_plan.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for path: String in [
		"res://scripts/game_root.gd",
		"res://scripts/caster_skill_runtime.gd",
		"res://scripts/skills/skill_runtime_router.gd",
	]:
		var file := FileAccess.open(path, FileAccess.READ)
		assert(file != null, "script missing: %s" % path)
		assert(
			not file.get_as_text().contains("visual_plan"),
			"%s must not construct a legacy visual plan" % path
		)
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "法师"
	PlayerState.learned_skills = {"雷电术": 3}
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
	Plan.reset_sentinels_for_tests()
	var result: Dictionary = game._execute_canonical_skill(
		"雷电术",
		game.player.global_position,
		Vector2.RIGHT,
		12
	)
	assert(bool(result.get("accepted", false)), "formal release rejected")
	assert(
		Plan.sentinel_diagnostics().canonical_plan_build_count == 1,
		"exactly one canonical plan; no second presentation plan"
	)
	var plan: Dictionary = result.get("canonical_plan", {})
	assert(
		(plan.get("presentation_actions", []) as Array).size() == 1,
		"presentation data must live in the canonical plan only"
	)
	await get_tree().process_frame
	print("SKILL_RUNTIME_NO_VISUAL_PLAN_PASS")
	get_tree().quit(0)


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({
		"name": "no_visual_plan_target",
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
