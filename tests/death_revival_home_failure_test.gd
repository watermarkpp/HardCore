extends Node

var _captured_error_reason := ""


func _ready() -> void:
	_run.call_deferred()


func _capture_safe_logout_error(action: StringName, reason: String) -> void:
	_captured_error_reason = "%s:%s" % [str(action), reason]


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.create_character("Q0B1复活测试", "战士", "男")
	_run_experience_penalty_contract()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(game.gameplay_input_is_enabled(), "death lifecycle test requires gameplay input enabled")
	game.set_safe_logout_error_reporter(
		Callable(self, "_capture_safe_logout_error")
	)

	game.player.global_position = Vector2(321.0, 654.0)
	game.player._dead = true
	game._test_force_home_failure = true
	game._map_transition_in_progress = true
	PlayerState.experience = 100
	game._on_player_death_requested()
	assert(PlayerState.experience == 90, "formal death did not deduct 10% experience")
	assert(game._death_experience_penalty_applied, "formal death did not latch penalty")
	game._on_player_death_requested()
	assert(PlayerState.experience == 90, "duplicate active death request deducted twice")
	# Stop the deferred retry issued by the intentionally failed home travel;
	# the duplicate callback above already crossed the enabled gameplay handler.
	game._player_input_enabled = false
	await get_tree().process_frame
	var position_before: Vector2 = game.player.global_position
	var dead_before: bool = game.player._dead

	game._finish_death_revival()
	assert(
		game.player.global_position == position_before,
		"death revival must not move the player on Home failure"
	)
	assert(
		game.player.global_position != Vector2.ZERO,
		"death revival must not write Vector2.ZERO"
	)
	assert(
		game.player._dead == dead_before,
		"death state must be preserved when revival cannot resolve Home"
	)
	assert(
		_captured_error_reason.contains("death_revival"),
		"death revival must report the home-resolution failure"
	)
	assert(game._death_experience_penalty_applied, "home failure cleared death penalty latch")
	game._player_input_enabled = false
	game._test_force_home_failure = false
	game._finish_death_revival()
	assert(not game._death_experience_penalty_applied, "successful revival did not clear latch")
	_run_automatic_revival_boundary(game)
	PlayerState.experience = 90
	game._test_force_home_failure = true
	game._player_input_enabled = true
	game._on_player_death_requested()
	assert(PlayerState.experience == 81, "next death did not deduct from revived experience")
	game._player_input_enabled = false
	await get_tree().process_frame
	game.queue_free()
	print("DEATH_REVIVAL_HOME_FAILURE_TEST_PASS")
	get_tree().quit(0)


func _run_experience_penalty_contract() -> void:
	for entry in [[0, 0], [1, 0], [9, 0], [10, 1], [101, 10]]:
		PlayerState.experience = int(entry[0])
		PlayerState.level = 7
		var signal_count := [0]
		var on_profile_changed := func() -> void: signal_count[0] += 1
		PlayerState.profile_changed.connect(on_profile_changed)
		var lost := PlayerState.apply_death_experience_penalty()
		PlayerState.profile_changed.disconnect(on_profile_changed)
		assert(lost == int(entry[1]), "death penalty rounding mismatch")
		assert(PlayerState.experience == int(entry[0]) - int(entry[1]))
		assert(PlayerState.level == 7, "death penalty changed level")
		assert(signal_count[0] == (1 if int(entry[1]) > 0 else 0), "penalty signal count mismatch exp=%d lost=%d count=%d" % [int(entry[0]), int(entry[1]), signal_count[0]])


func _run_automatic_revival_boundary(game: Node) -> void:
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.experience = 100
	PlayerState.recalculate_stats()
	PlayerState.add_item("复活戒指")
	var ring_index := -1
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == "复活戒指":
			ring_index = index
			break
	assert(ring_index >= 0, "revival ring fixture missing")
	PlayerState.equip_inventory_index(ring_index)
	assert(PlayerState.has_special_effect("revival"), "revival ring fixture not active")
	var death_signal_count := 0
	var on_death := func() -> void: death_signal_count += 1
	game.player.death_requested.connect(on_death)
	game.player.current_hp = game.player.max_hp
	game.player.take_damage(999999)
	game.player.death_requested.disconnect(on_death)
	assert(game.player.current_hp == game.player.max_hp, "automatic revival did not restore health")
	assert(PlayerState.experience == 100, "automatic revival incorrectly deducted experience")
	assert(death_signal_count == 0, "automatic revival emitted formal death_requested")
