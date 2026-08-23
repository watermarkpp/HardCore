extends Node

## Q3-B/Q3-C: the formal production chain never builds a second visual/runtime
## plan. Releasing fire wall, lightning and laser through the GameRoot entry
## must produce exactly one canonical plan (the legacy visual-plan path was
## removed in Q3-C; the static surface is asserted by
## skill_runtime_no_legacy_api_test).

const Plan := preload("res://scripts/skills/skill_execution_plan.gd")

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
	PlayerState.learned_skills = {"火墙": 3, "雷电术": 3, "疾光电影": 3}
	PlayerState.recalculate_stats()
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_caster = _game.player
	_caster.current_mp = 500
	_target = _make_enemy(_game, _caster, _caster.global_position + Vector2(40, 0))
	await get_tree().process_frame

	_release_case("火墙", true)
	_release_case("雷电术", true)
	_release_case("疾光电影", false)
	await get_tree().process_frame
	print("SKILL_PRODUCTION_NO_VISUAL_PLAN_PASS cases=3")
	get_tree().quit(0)


func _release_case(skill_name: String, needs_target: bool) -> void:
	if needs_target:
		_game._set_magic_locked_target(_target, true)
		_game._skill_cast_target = _target
	Plan.reset_sentinels_for_tests()
	var result: Dictionary = _game._execute_canonical_skill(
		skill_name,
		_caster.global_position,
		Vector2.RIGHT,
		12
	)
	assert(bool(result.get("accepted", false)), "%s formal release rejected" % skill_name)
	var diag := Plan.sentinel_diagnostics()
	assert(
		diag.canonical_plan_build_count == 1,
		"%s must build exactly one canonical plan" % skill_name
	)
	assert(
		diag.release_id_generation_count == 1,
		"%s must generate exactly one release id" % skill_name
	)


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
