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
	game.player.current_hp = 0
	game._test_force_home_failure = true
	# Use a nonzero penalty level; level 1 now correctly floors 10% of 3 to 0.
	PlayerState.level = 7
	PlayerState.experience = 100
	var death_threshold := PlayerState.experience_to_next_level()
	var expected_death_loss := int(floor(float(death_threshold) * 0.10))
	var death_profile_signal_count := [0]
	var on_death_profile_changed := func() -> void: death_profile_signal_count[0] += 1
	PlayerState.profile_changed.connect(on_death_profile_changed)
	game._on_player_death_requested()
	assert(PlayerState.experience == 100 - expected_death_loss, "formal death did not deduct 10% of the level requirement")
	assert(game._death_experience_penalty_applied, "formal death did not latch penalty")
	assert(game.hud.death_revival_panel.visible, "formal death did not open the real death UI")
	assert(not game._map_transition_in_progress, "formal death started Loading before a revival choice")
	assert(game.player._dead and game.player.current_hp == 0, "death UI did not preserve the dead state")
	game._on_player_death_requested()
	assert(PlayerState.experience == 100 - expected_death_loss, "duplicate active death request deducted twice")
	PlayerState.profile_changed.disconnect(on_death_profile_changed)
	assert(death_profile_signal_count[0] == 1, "formal death penalty was not committed exactly once")
	game.hud.death_revival_panel.town_button.pressed.emit()
	assert(not game._map_transition_in_progress, "failed Home resolution started Loading")
	assert(game.hud.death_revival_panel.visible, "failed Home resolution closed death UI")
	assert(game.player.global_position == Vector2(321.0, 654.0), "failed revival moved the player")
	assert(game.player._dead and game.player.current_hp == 0, "failed revival cleared death state")
	assert(
		_captured_error_reason.contains("travel_to_service_home"),
		"death revival must report the home-resolution failure"
	)
	assert(game._death_experience_penalty_applied, "home failure cleared death penalty latch")
	game._test_force_home_failure = false
	game.hud.death_revival_panel.town_button.pressed.emit()
	assert(
		game._map_transition_in_progress or not game.player._dead,
		"selected revival neither began Loading nor completed the test-mode fast path"
	)
	await _wait_for_transition(game)
	assert(not game.hud.death_revival_panel.visible, "successful revival did not close death UI")
	assert(not game.player._dead and game.player.current_hp == game.player.max_hp, "successful revival did not restore player")
	assert(not game._death_experience_penalty_applied, "successful revival did not clear latch")
	_run_automatic_revival_boundary(game)
	game.queue_free()
	print("DEATH_REVIVAL_HOME_FAILURE_TEST_PASS")
	get_tree().quit(0)


func _run_experience_penalty_contract() -> void:
	PlayerState.level = 7
	var level_requirement := PlayerState.experience_to_next_level()
	assert(level_requirement == 40, "level 7 threshold must use the newly reduced source requirement")
	var expected_loss := int(floor(float(level_requirement) * 0.10))
	assert(expected_loss == 4, "death penalty must floor 10% of the current level requirement")
	for entry in [
		{"experience": 0, "expected_loss": 0},
		{"experience": 1, "expected_loss": 1},
		{"experience": 3, "expected_loss": 3},
		{"experience": 4, "expected_loss": 4},
		{"experience": 39, "expected_loss": 4},
		{"experience": 500, "expected_loss": 4},
	]:
		var starting_experience := int(entry["experience"])
		var expected_entry_loss := int(entry["expected_loss"])
		PlayerState.experience = starting_experience
		var signal_count := [0]
		var on_profile_changed := func() -> void: signal_count[0] += 1
		PlayerState.profile_changed.connect(on_profile_changed)
		var lost := PlayerState.apply_death_experience_penalty()
		PlayerState.profile_changed.disconnect(on_profile_changed)
		assert(lost == expected_entry_loss, "death penalty threshold basis mismatch exp=%d lost=%d" % [starting_experience, lost])
		assert(PlayerState.experience == starting_experience - expected_entry_loss)
		assert(PlayerState.level == 7, "death penalty changed level")
		assert(signal_count[0] == (1 if expected_entry_loss > 0 else 0), "penalty signal count mismatch exp=%d lost=%d count=%d" % [starting_experience, expected_entry_loss, signal_count[0]])

	# A failed persistence commit must roll back the mutation and must not
	# publish a profile update for an uncommitted death penalty.
	PlayerState.experience = 500
	var failed_before := PlayerState.experience
	var failed_signal_count := [0]
	var on_failed_profile_changed := func() -> void: failed_signal_count[0] += 1
	PlayerState.profile_changed.connect(on_failed_profile_changed)
	PlayerState._test_force_atomic_write_failure = true
	var failed_loss := PlayerState.apply_death_experience_penalty()
	PlayerState._test_force_atomic_write_failure = false
	PlayerState.profile_changed.disconnect(on_failed_profile_changed)
	assert(failed_loss == 0, "save failure must reject the death penalty")
	assert(PlayerState.experience == failed_before, "save failure did not roll back death penalty experience")
	assert(failed_signal_count[0] == 0, "save failure emitted an uncommitted profile update")


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
	assert(
		game.hud.death_revival_panel == null or not game.hud.death_revival_panel.visible,
		"automatic revival incorrectly opened the death UI"
	)


func _wait_for_transition(game: Node) -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while bool(game._map_transition_in_progress) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(not game._map_transition_in_progress, "death revival transition did not finish")
