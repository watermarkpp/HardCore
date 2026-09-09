extends Node

## Q3-C: the formal production surface exposes exactly ONE planner entry and
## ONE caster node entry. The legacy API definitions are gone (static scan is
## covered by skill_runtime_no_legacy_api_test); this test verifies the
## canonical surface statically and through a formal release.

const Plan := preload("res://scripts/skills/skill_execution_plan.gd")
const FIXTURE_MONSTER_ID := 19
const FormalFixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")


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
	var caster: PlayerCharacter = game.player
	caster.current_mp = 500
	var target: EnemyActor = await FormalFixture.prepare_target(
		self,
		game,
		caster,
		FIXTURE_MONSTER_ID,
		"skill_runtime_single_public_entry",
	)
	game._set_magic_locked_target(target, true)
	assert(game.magic_locked_target == target, "single-public-entry target was rejected by the formal WORLD gate")
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
