extends Node

## Q3-C: the formal production surface exposes exactly ONE planner entry and
## ONE caster node entry. The legacy API definitions are gone (static scan is
## covered by skill_runtime_no_legacy_api_test); this test verifies the
## canonical surface statically and through a formal release.

const Plan := preload("res://scripts/skills/skill_execution_plan.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_assert_source_entry_counts()
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
	Plan.reset_sentinels_for_tests()
	var result: Dictionary = game._execute_canonical_skill(
		"火墙",
		game.player.global_position,
		Vector2.RIGHT,
		0,
		{"primary_stat_roll": 8}
	)
	assert(bool(result.get("accepted", false)), "formal release rejected")
	assert(
		Plan.sentinel_diagnostics().canonical_plan_build_count == 1,
		"exactly one canonical plan per release"
	)
	var plan: Dictionary = result.get("canonical_plan", {})
	assert(
		str(plan.get("contract", "")) == "skill_execution_plan.v1",
		"single planner contract"
	)
	await get_tree().process_frame
	print("SKILL_RUNTIME_SINGLE_PUBLIC_ENTRY_PASS")
	get_tree().quit(0)


func _assert_source_entry_counts() -> void:
	var router := FileAccess.open(
		"res://scripts/skills/skill_runtime_router.gd",
		FileAccess.READ
	)
	var router_source := router.get_as_text()
	assert(
		router_source.get_slice_count(
			"static func build_canonical_plan("
		) == 2,
		"router must define build_canonical_plan exactly once"
	)
	var caster := FileAccess.open(
		"res://scripts/caster_skill_runtime.gd",
		FileAccess.READ
	)
	var caster_source := caster.get_as_text()
	assert(
		caster_source.get_slice_count(
			"static func create_cast_nodes_from_canonical_plan("
		) == 2,
		"caster must define create_cast_nodes_from_canonical_plan exactly once"
	)
	assert(
		not router_source.contains("static func execute("),
		"legacy Router.execute definition must be gone"
	)
	assert(
		not caster_source.contains("static func resolve("),
		"legacy CasterSkillRuntime.resolve definition must be gone"
	)


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({
		"name": "single_entry_target",
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
