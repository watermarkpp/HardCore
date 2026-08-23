extends Node

## Q3-A: a cooldown is committed at most once - two commits never accumulate
## (overwrite semantics), and the canonical plan carries the same cooldown
## contract as the definition.

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
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	for _i: int in range(5):
		await get_tree().process_frame
	var definition := DataLoader.skill("warrior.fire_sword")
	var cooldown_ms := int(definition.get("timing", {}).get("cooldown_ms", 8000))
	game.player.commit_fire_sword_cooldown()
	var remaining_after_first: int = game.player.skill_cooldown_remaining_ms(
		"warrior.fire_sword"
	)
	game.player.commit_fire_sword_cooldown()
	var remaining_after_second: int = game.player.skill_cooldown_remaining_ms(
		"warrior.fire_sword"
	)
	assert(
		remaining_after_first > 0,
		"first cooldown commit must take effect"
	)
	assert(
		abs(remaining_after_first - remaining_after_second) <= 5,
		"second commit must not accumulate (single commit semantics): %d vs %d"
		% [remaining_after_first, remaining_after_second]
	)
	assert(
		abs(remaining_after_first - cooldown_ms) <= 5,
		"cooldown must equal the definition once, got %d expected %d"
		% [remaining_after_first, cooldown_ms]
	)
	# Canonical plan carries the same cooldown contract.
	var request := Fixtures.make_request(
		"warrior.fire_sword",
		1,
		35,
		Vector2i.ZERO,
		Vector2i.DOWN,
		Fixtures.default_target_context(true),
		Fixtures.default_resource_context(500)
	)
	var plan: Dictionary = Router.build_canonical_plan(
		request,
		Fixtures.canonical_context(1, "q3a:cooldown:1")
	)
	assert(
		int(plan.get("cooldown_contract", {}).get("cooldown_ms", 0)) == cooldown_ms,
		"canonical cooldown contract must match the definition"
	)
	_cleanup(game)
	await get_tree().process_frame
	print("SKILL_PLAN_SINGLE_COOLDOWN_COMMIT_PASS cooldown_ms=%d" % cooldown_ms)
	get_tree().quit(0)


func _cleanup(game: Node) -> void:
	if is_instance_valid(game):
		game.queue_free()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)

const Router := preload("res://scripts/skills/skill_runtime_router.gd")
