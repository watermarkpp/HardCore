extends Node

## Q3-C: in a normal mapped world (expected_runtime_map_id >= 0) every formal
## spatial release must keep STRICT_V2 snapshot validation - the unmapped
## fallback must never leak into production maps.

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const FIXTURE_MONSTER_ID := 19
const FormalFixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")


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
	assert(
		game.current_map_id >= 0,
		"booted world must carry a real runtime map id"
	)
	var caster: PlayerCharacter = game.player
	caster.current_mp = 500
	var target: EnemyActor = await FormalFixture.prepare_target(
		self,
		game,
		caster,
		FIXTURE_MONSTER_ID,
		"skill_runtime_mapped_world_strict_snapshot",
	)
	game._set_magic_locked_target(target, true)
	assert(game.magic_locked_target == target, "mapped snapshot target was rejected by the formal WORLD gate")
	game._skill_cast_target = target
	await get_tree().process_frame
	var result: Dictionary = game._execute_canonical_skill(
		"火墙",
		game.player.global_position,
		Vector2.RIGHT,
		0,
		{"primary_stat_roll": 8}
	)
	assert(bool(result.get("accepted", false)), "formal release rejected")
	var plan: Dictionary = result.get("canonical_plan", {})
	var snapshot: Dictionary = plan.get("canonical_snapshot", {})
	assert(
		int(snapshot.get("runtime_map_id", -1)) == game.current_map_id,
		"snapshot must carry the live runtime map id"
	)
	var validation_context: Dictionary = game._canonical_snapshot_validation_context(
		game._canonical_screen_px_to_ground_gu(game.player.global_position)
	)
	assert(
		int(validation_context.get("expected_runtime_map_id", -1)) >= 0,
		"formal validation context must be map-bound"
	)
	assert(
		bool(Snapshot.validate_for_consumer(
			snapshot,
			validation_context,
			Snapshot.VALIDATION_STRICT_V2
		).get("valid", false)),
		"formal mapped-world snapshot must pass STRICT_V2"
	)
	await get_tree().process_frame
	print("SKILL_RUNTIME_MAPPED_WORLD_STRICT_SNAPSHOT_PASS")
	get_tree().quit(0)
