extends Node

## Q3-B: resources (MP and material) are committed exactly once per release
## through the canonical plan's frozen resource_cost.

const Plan := preload("res://scripts/skills/skill_execution_plan.gd")
const DataLoader := preload("res://scripts/skills/skill_data_loader.gd")

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
	PlayerState.learned_skills = {"火墙": 3}
	PlayerState.recalculate_stats()
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_caster = _game.player
	_target = _make_enemy(_game, _caster, _caster.global_position + Vector2(40, 0))
	await get_tree().process_frame

	_game._set_magic_locked_target(_target, true)
	_game._skill_cast_target = _target
	_caster.current_mp = 500
	var fire_wall_cost := int(
		(DataLoader.skill("wizard.fire_wall").get("mp_cost_by_rank", [0, 0, 0, 0]) as Array)[3]
	)
	Plan.reset_sentinels_for_tests()
	var mp_before := _caster.current_mp
	var result: Dictionary = _game._execute_canonical_skill(
		"火墙",
		_caster.global_position,
		Vector2.RIGHT,
		0,
		{"primary_stat_roll": 8}
	)
	assert(bool(result.get("accepted", false)), "fire wall release rejected")
	assert(
		mp_before - _caster.current_mp == fire_wall_cost,
		"fire wall MP must be committed exactly once (%d spent, expected %d)"
		% [mp_before - _caster.current_mp, fire_wall_cost]
	)
	assert(
		Plan.sentinel_diagnostics().resource_commit_count == 1,
		"resource_commit_count must be exactly 1"
	)

	PlayerState.select_profession("道士")
	PlayerState.learned_skills = {"施毒术": 3}
	PlayerState.inventory = [{"name": "灰色药粉", "count": 5}]
	PlayerState.recalculate_stats()
	_caster.current_mp = 500
	_game._set_magic_locked_target(_target, true)
	_game._skill_cast_target = _target
	Plan.reset_sentinels_for_tests()
	var poison_mp_before := _caster.current_mp
	var poison_cost := int(
		(DataLoader.skill("taoist.poison").get("mp_cost_by_rank", [0, 0, 0, 0]) as Array)[3]
	) * 2
	var poison_result: Dictionary = _game._execute_canonical_skill(
		"施毒术",
		_caster.global_position,
		Vector2.RIGHT,
		12
	)
	assert(bool(poison_result.get("accepted", false)), "poison release rejected")
	assert(
		poison_mp_before - _caster.current_mp == poison_cost,
		"dual poison MP must be committed exactly once"
	)
	var poison_plan: Dictionary = poison_result.get("canonical_plan", {})
	var poison_material_amount := int(
		poison_plan.get("resource_cost", {}).get("material_amount", 0)
	)
	assert(poison_material_amount > 0, "dual poison must quote powder consumption")
	assert(
		PlayerState.item_count("灰色药粉") == 5 - poison_material_amount,
		"dual poison powder must be committed exactly once"
	)
	assert(
		Plan.sentinel_diagnostics().resource_commit_count == 1,
		"poison resource_commit_count must be exactly 1"
	)
	var poison_actions: Array = poison_plan.get("gameplay_actions", [])
	assert(poison_actions.size() == 2, "dual poison must produce exactly two gameplay actions")
	assert(str(poison_actions[0].get("poison_type", "")) == "green_poison")
	assert(str(poison_actions[1].get("poison_type", "")) == "red_poison")
	assert(_target.poison_time > 0.0, "green poison must reach the production target")
	assert(_target.has_meta("canonical_red_poison"), "red poison must reach the production target")
	await get_tree().process_frame
	print(
		"SKILL_PRODUCTION_SINGLE_COMMIT_PASS fire_wall_mp=%d poison_mp=%d material=%d"
		% [fire_wall_cost, poison_cost, poison_material_amount]
	)
	get_tree().quit(0)


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({
		"name": "single_commit_target",
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
