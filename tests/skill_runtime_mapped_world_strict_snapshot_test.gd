extends Node

## Q3-C: in a normal mapped world (expected_runtime_map_id >= 0) every formal
## spatial release must keep STRICT_V2 snapshot validation - the unmapped
## fallback must never leak into production maps.

const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")


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
	game.player.current_mp = 500
	var target := _make_enemy(game, game.player, game.player.global_position + Vector2(40, 0))
	game._set_magic_locked_target(target, true)
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


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({
		"name": "strict_snapshot_target",
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
