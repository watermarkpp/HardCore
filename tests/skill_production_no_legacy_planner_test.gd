extends Node

## Q3-B/Q3-C: the formal chain must never invoke legacy planner APIs. Q3-C
## removed the legacy APIs entirely; the static surface is asserted by
## skill_runtime_no_legacy_api_test. Here the formal release must still build
## exactly one canonical plan and never a legacy plan object.

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
	assert(bool(result.get("accepted", false)), "formal release rejected")
	var diag := Plan.sentinel_diagnostics()
	assert(diag.canonical_plan_build_count == 1, "exactly one canonical plan")
	var plan: Dictionary = result.get("canonical_plan", {})
	assert(
		str(plan.get("created_by", "")) == "canonical_planner.v1",
		"formal release must be created by the canonical planner only"
	)
	assert(
		str(plan.get("legacy_planner", "")) == "skill_runtime_router.v1"
		and plan.has("contract"),
		"plan must carry the canonical contract lineage"
	)
	await get_tree().process_frame
	print("SKILL_PRODUCTION_NO_LEGACY_PLANNER_PASS")
	get_tree().quit(0)


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({
		"name": "no_legacy_planner_target",
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
