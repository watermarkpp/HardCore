extends Node

## Q3-A: the canonical planner shadow must never touch MP, cooldowns, target
## HP, nodes, projectiles, ground effects, summons, visuals or lock state.

const Fixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Plan := preload("res://scripts/skills/skill_execution_plan.gd")
const FIXTURE_MONSTER_ID := 19


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	for _i: int in range(5):
		await get_tree().process_frame
	game.player.current_mp = 200
	var target := EnemyActor.new()
	var canonical_data := GameData.get_monster_by_id(FIXTURE_MONSTER_ID)
	assert(
		not canonical_data.is_empty(),
		"shadow fixture monster_id=%d must exist" % FIXTURE_MONSTER_ID
	)
	target.setup(canonical_data, game.player, false)
	assert(
		target.monster_id == FIXTURE_MONSTER_ID and not target.is_boss,
		"shadow fixture must remain an ordinary exact-ID target"
	)
	target.max_hp = 500
	target.current_hp = target.max_hp
	target.global_position = game.player.global_position + Vector2(60, 0)
	game.add_child(target)
	assert(
		is_instance_valid(target)
		and not target.is_queued_for_deletion()
		and target.can_receive_damage(),
		"shadow fixture target must survive exact-ID admission"
	)
	target.set_physics_process(false)
	await get_tree().process_frame

	var mp_before: int = game.player.current_mp
	var hp_before: int = target.current_hp
	var nodes_before: int = game.get_child_count()
	var projectiles_before := _count_type(game, "SkillProjectile")
	var ground_before := _count_type(game, "GroundSkillEffect")
	var summons_before := _count_type(game, "SummonActor")
	var visuals_before := _count_type(game, "CasterSkillVisualEffect")
	var lock_before: Variant = game.get("_magic_locked_target")

	var request := Fixtures.make_request(
		"wizard.lightning",
		1,
		35,
		Vector2i.ZERO,
		Vector2i.DOWN,
		Fixtures.default_target_context(true),
		Fixtures.default_resource_context(200)
	)
	var snapshot := Fixtures.circle_snapshot(
		self,
		"wizard.lightning",
		"q3a:shadow:1",
		1,
		Vector2(0, 0),
		2.0
	)
	var plan: Dictionary = Router.build_canonical_plan(
		request,
		Fixtures.canonical_context(1, "q3a:shadow:1", 7, target.get_instance_id(), snapshot)
	)
	assert(bool(plan.get("rejection", {}).get("accepted", false)), "shadow plan accepted")
	await get_tree().process_frame
	assert(
		game.player.current_mp == mp_before,
		"shadow plan must not spend MP"
	)
	assert(target.current_hp == hp_before, "shadow plan must not damage")
	assert(game.get_child_count() == nodes_before, "shadow plan must not add nodes")
	assert(_count_type(game, "SkillProjectile") == projectiles_before, "no projectiles")
	assert(_count_type(game, "GroundSkillEffect") == ground_before, "no ground effects")
	assert(_count_type(game, "SummonActor") == summons_before, "no summons")
	assert(_count_type(game, "CasterSkillVisualEffect") == visuals_before, "no visuals")
	assert(
		game.get("_magic_locked_target") == lock_before,
		"shadow plan must not change the lock state"
	)
	assert(
		game.player.skill_cooldown_remaining_ms("wizard.lightning") == 0,
		"shadow plan must not commit cooldowns"
	)
	_cleanup(game, target)
	await get_tree().process_frame
	print("SKILL_PLAN_NO_SIDE_EFFECT_SHADOW_PASS")
	get_tree().quit(0)


func _count_type(game: Node, type_name: String) -> int:
	var count := 0
	for child: Node in game.get_children():
		var script: Variant = child.get_script()
		if (
			script != null
			and str(script.get_global_name()) == type_name
		):
			count += 1
	return count


func _cleanup(game: Node, target: EnemyActor) -> void:
	if is_instance_valid(target):
		target.queue_free()
	if is_instance_valid(game):
		game.queue_free()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)

const Router := preload("res://scripts/skills/skill_runtime_router.gd")
