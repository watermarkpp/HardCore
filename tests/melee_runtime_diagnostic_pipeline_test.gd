extends Node

const DiagnosticLog := preload("res://scripts/layers/runtime/combat_diagnostic_log.gd")
const DirectionSpace := preload("res://scripts/skills/combat_direction_space.gd")


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

	# Phone reproduction melee:205-216. The target is only 1.31 tiles away,
	# but the former screen-angle quantizer selected direction 5 and rejected
	# all twelve attacks. The canonical 64x32 tile quantizer selects direction 4.
	game.player._attack_timer = 0.0
	game.player._attack_action_timer = 0.0
	game.player.velocity = Vector2.ZERO
	game.player.set_touch_vector(Vector2.ZERO)
	PlayerState.test_mode = true
	origin_tile = game._canonical_world_to_fractional_tile(game.player.global_position)
	game._active_safe_zones.clear()
	enemy.velocity = Vector2.ZERO
	enemy.control_time = 0.0
	enemy.global_position = game.player.global_position + (
		DirectionSpace.fractional_tile_delta_to_world_delta(Vector2(-0.56, -1.31))
	)
	enemy.apply_control(60.0)
	var measured_delta: Vector2 = (
		game._canonical_world_to_fractional_tile(enemy.global_position) - origin_tile
	)
	assert(measured_delta.is_equal_approx(Vector2(-0.56, -1.31)))
	hp_before = enemy.current_hp
	assert(game._request_mobile_attack(), "phone angle regression input was rejected")
	await get_tree().create_timer(game.player.attack_hit_windup + 0.08).timeout
	assert(enemy.current_hp < hp_before, "phone angle regression still produced an empty swing")
	release_event = _last_release_event()
	assert(release_event.result_code == "HIT_COMMITTED")
	assert(release_event.attack_direction_index_at_input == 4)
	assert(release_event.release_direction_index == 4)
	assert(release_event.input_release_direction_match)
	assert(release_event.actual_visual_row_at_release == 0)
	assert(release_event.expected_visual_row_at_release == 0)
	assert(release_event.visual_geometry_direction_match)
	assert(
		str(release_event.release_geometry.get("direction_space_contract_id", ""))
		== "gameplay.professions.combat_direction_space.iso_64x32_tile_8dir.v1"
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
