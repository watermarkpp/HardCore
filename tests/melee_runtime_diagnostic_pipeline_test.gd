extends Node

const DiagnosticLog := preload("res://scripts/layers/runtime/combat_diagnostic_log.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	var previous_log_enabled := DiagnosticLog.enabled
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "战士"
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	DiagnosticLog.enabled = false
	DiagnosticLog.clear_recent_events()

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).global_position = game.player.global_position + Vector2(3000, 3000)

	game.player.global_position = game._bich_home_world_position() + Vector2(600, 0)
	var origin_tile: Vector2 = game._canonical_world_to_fractional_tile(
		game.player.global_position
	)
	var enemy := _make_enemy(
		game,
		game._canonical_fractional_tile_to_world(origin_tile + Vector2(1, 1))
	)
	game.locked_target = enemy
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0
	PlayerState.computed_stats["accuracy"] = 0
	PlayerState.test_mode = false

	var hp_before := enemy.current_hp
	assert(game._request_mobile_attack(), "real melee input was rejected before diagnostic release")
	await get_tree().create_timer(game.player.attack_hit_windup + 0.08).timeout
	assert(enemy.current_hp == hp_before, "zero accuracy should produce a formal MISS")

	var release_event := _last_release_event()
	assert(not release_event.is_empty(), "real melee release produced no diagnostic event")
	assert(
		str(release_event.get("result_code", "")) == "ACCURACY_MISS",
		"real MISS was not distinguished from geometry or damage failure"
	)
	assert(
		bool(release_event.get("visual_geometry_direction_match", false)),
		"animation row and damage direction diverged in the exact-direction fixture"
	)
	var candidate_decisions: Array = release_event.get("selection_candidate_decisions", [])
	assert(not candidate_decisions.is_empty(), "release log omitted candidate decisions")
	assert(
		(candidate_decisions[0] as Dictionary).has("angle_quantization_audit"),
		"release log omitted screen-vs-tile angle evidence"
	)
	var hit_attempts: Array = release_event.get("physical_hit_attempts", [])
	assert(
		hit_attempts.size() == 1
		and str((hit_attempts[0] as Dictionary).get("result_code", "")) == "ACCURACY_MISS",
		"physical accuracy roll was not captured exactly once"
	)

	game.queue_free()
	await get_tree().process_frame
	DiagnosticLog.clear_recent_events()
	DiagnosticLog.enabled = previous_log_enabled
	PlayerState.test_mode = previous_test_mode
	print("MELEE_RUNTIME_DIAGNOSTIC_PIPELINE_PASS: production accuracy and angle evidence are observable")
	get_tree().quit(0)


func _last_release_event() -> Dictionary:
	var events := DiagnosticLog.recent_events()
	for index in range(events.size() - 1, -1, -1):
		var event: Dictionary = events[index]
		if str(event.get("event", "")) == "attack_release_resolved":
			return event
	return {}


func _make_enemy(game: Node, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{
			"name": "diagnostic_target",
			"hp": 200,
			"attackMin": 1,
			"attackMax": 1,
			"level": 1,
			"agility": 100,
			"defMin": 0,
			"defMax": 0,
		},
		game.player,
		false
	)
	enemy.global_position = position
	enemy.control_time = 60.0
	game.add_child(enemy)
	return enemy
