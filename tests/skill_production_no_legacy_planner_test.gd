extends Node

## Q3-B: the formal chain must never invoke the legacy planner APIs. After a
## formal release, formal_legacy_router_execute_count and caster_resolve_count
## stay zero; the only planner object is the canonical plan.

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
	assert(
		diag.formal_legacy_router_execute_count == 0,
		"formal chain must not call legacy Router.execute"
	)
	assert(
		diag.caster_resolve_count == 0,
		"formal chain must not call CasterSkillRuntime.resolve"
	)
	assert(
		diag.legacy_create_cast_nodes_count == 0,
		"formal chain must not call legacy create_cast_nodes"
	)
	assert(
		diag.visual_plan_build_count == 0,
		"formal chain must not construct a visual plan"
	)
	assert(
		diag.legacy_plan_build_count == 0,
		"formal chain must not build a legacy plan"
	)
	assert(diag.canonical_plan_build_count == 1, "exactly one canonical plan")
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
