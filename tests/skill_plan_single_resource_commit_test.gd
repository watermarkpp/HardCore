extends Node

## Q3-A: one successful release spends the resource exactly once (MP drop ==
## one cost) and the canonical plan quotes the identical cost.

const Fixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Plan := preload("res://scripts/skills/skill_execution_plan.gd")
const DataLoader := preload("res://scripts/skills/skill_data_loader.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 35
	PlayerState.profession = "法师"
	PlayerState.learned_skills = {"火墙": 1}
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	for _i: int in range(5):
		await get_tree().process_frame
	game.player.current_mp = 500
	var target := EnemyActor.new()
	target.setup(
		{"name": "q3a_mp", "hp": 9999, "attackMin": 1, "attackMax": 1, "level": 1},
		game.player,
		false
	)
	target.global_position = game.player.global_position + Vector2(18, 0)
	game.add_child(target)
	target.set_physics_process(false)
	target.apply_control(10.0)
	await get_tree().process_frame
	game._set_magic_locked_target(target, true)
	game._skill_cast_target = target
	await get_tree().process_frame

	var definition := DataLoader.skill("wizard.fire_wall")
	var mp_cost := int((definition.get("mp_cost_by_rank", [0, 0, 0, 0]) as Array)[1])
	var mp_before: int = game.player.current_mp
	var result: Dictionary = game._execute_canonical_skill(
		"火墙",
		game.player.global_position,
		Vector2.RIGHT,
		12
	)
	assert(
		bool(result.get("accepted", false)),
		"fire wall must be accepted: %s" % str(result)
	)
	var mp_after: int = game.player.current_mp
	assert(
		mp_before - mp_after == mp_cost,
		"resource must be committed exactly once (%d spent, expected %d)"
		% [mp_before - mp_after, mp_cost]
	)
	# Canonical plan quotes the identical cost.
	var request := Fixtures.make_request(
		"wizard.fire_wall",
		1,
		35,
		Vector2i.ZERO,
		Vector2i.DOWN,
		Fixtures.default_target_context(true),
		Fixtures.default_resource_context(500)
	)
	var snapshot := Fixtures.circle_snapshot(
		self,
		"wizard.fire_wall",
		"q3a:mp:1",
		1,
		Vector2(0, 0),
		2.0
	)
	var plan: Dictionary = Router.build_canonical_plan(
		request,
		Fixtures.canonical_context(1, "q3a:mp:1", 0, 0, snapshot)
	)
	assert(
		int(plan.get("resource_cost", {}).get("mp_cost", 0)) == mp_cost,
		"canonical plan must quote the same mp cost"
	)
	_cleanup(game, target)
	await get_tree().process_frame
	print("SKILL_PLAN_SINGLE_RESOURCE_COMMIT_PASS mp=%d" % mp_cost)
	get_tree().quit(0)


func _cleanup(game: Node, target: EnemyActor) -> void:
	if is_instance_valid(target):
		target.queue_free()
	if is_instance_valid(game):
		game.queue_free()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)

const Router := preload("res://scripts/skills/skill_runtime_router.gd")
