extends Node

## Q3-C: the formal production chain must not construct a second visual plan.
## The legacy visual-plan path was deleted; this test statically guards the
## production scripts and verifies a formal release builds exactly one
## canonical plan with no presentation-only plan object.

const Plan := preload("res://scripts/skills/skill_execution_plan.gd")
const FIXTURE_MONSTER_ID := 19
const FormalFixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")


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
	var caster: PlayerCharacter = game.player
	caster.current_mp = 500
	var target: EnemyActor = await FormalFixture.prepare_target(
		self,
		game,
		caster,
		FIXTURE_MONSTER_ID,
		"skill_runtime_no_visual_plan",
	)
	game._set_magic_locked_target(target, true)
	assert(game.magic_locked_target == target, "runtime no-visual-plan target was rejected by the formal WORLD gate")
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
