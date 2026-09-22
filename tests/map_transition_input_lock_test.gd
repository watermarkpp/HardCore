extends Node

const LOADING_CONTRACT_ID := "ui.loading.transition.v1"

# Overlap test with inline lock logic
var _locks: Dictionary = {}
var _player_input_enabled := true

func _acquire(reason: StringName) -> void:
	var c: int = int(_locks.get(reason, 0))
	_locks[reason] = c + 1
	_player_input_enabled = _locks.is_empty()

func _release(reason: StringName) -> void:
	var c: int = int(_locks.get(reason, 0))
	if c <= 1:
		_locks.erase(reason)
	else:
		_locks[reason] = c - 1
	_player_input_enabled = _locks.is_empty()

func is_enabled() -> bool:
	return _player_input_enabled


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Overlap: acquire both
	_acquire("map_transition")
	_acquire("initial_world_bootstrap")
	assert(not is_enabled())

	# Release one → still disabled
	_release("initial_world_bootstrap")
	assert(not is_enabled())
	assert(_locks.has("map_transition"))

	# Release last → enabled
	_release("map_transition")
	assert(is_enabled())

	# Counted: double acquire → single release doesn't unlock
	_acquire("map_transition")
	_acquire("map_transition")
	assert(not is_enabled())
	assert(int(_locks.get("map_transition", 0)) == 2)
	_release("map_transition")
	assert(not is_enabled())
	_release("map_transition")
	assert(is_enabled())

	await _assert_transition_cancels_touch_movement()
	print(
		"MAP_TRANSITION_INPUT_LOCK_TEST_PASS release_during_lock=true "
		+ "missing_release=true stationary_frames=10 next_touch=true "
		+ "input_map_unchanged=true"
	)
	get_tree().quit(0)


func _assert_transition_cancels_touch_movement() -> void:
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await _wait_until_ready(game)
	game._monster_prefetch_enabled = false
	var joystick: TouchJoystick = game.hud.movement_joystick
	assert(joystick != null)
	var input_actions_before := InputMap.get_actions()
	var transition_operation := Callable(self, "_successful_transition_operation")

	# Release delivered after the transition lock was acquired.
	_press_joystick(joystick, 41)
	await get_tree().process_frame
	assert(not game.player.touch_vector.is_zero_approx())
	PlayerState.test_mode = false
	assert(
		game._begin_map_transition(transition_operation, game.current_map_id),
		"first transition was not accepted"
	)
	_assert_all_movement_zero(game, joystick, "acquire boundary")
	_release_joystick(joystick, 41)
	_assert_all_movement_zero(game, joystick, "release during lock")
	_cover_active_transition(game)
	await _wait_for_transition(game)
	_assert_all_movement_zero(game, joystick, "ready boundary")
	await _assert_stationary_for_physics_frames(game, 5)

	# A fresh pointer can take ownership after READY.
	_press_joystick(joystick, 42)
	await get_tree().process_frame
	var takeover := joystick.input_state_snapshot()
	assert(int(takeover.pointer_id) == 42)
	assert(not (takeover.value as Vector2).is_zero_approx())
	assert(not game.player.touch_vector.is_zero_approx())

	# No release is delivered at all. Both lifecycle boundaries must clear it.
	assert(
		game._begin_map_transition(transition_operation, game.current_map_id),
		"second transition was not accepted"
	)
	_assert_all_movement_zero(game, joystick, "missing release acquire")
	_cover_active_transition(game)
	await _wait_for_transition(game)
	_assert_all_movement_zero(game, joystick, "missing release ready")
	await _assert_stationary_for_physics_frames(game, 5)

	assert(InputMap.get_actions() == input_actions_before, "movement cancel mutated InputMap")
	var root_source := FileAccess.get_file_as_string("res://scripts/game_root.gd")
	assert("Input.action_release" not in root_source)
	PlayerState.test_mode = previous_test_mode
	game.queue_free()


func _successful_transition_operation() -> bool:
	return true


func _cover_active_transition(game: Node) -> void:
	assert(game._map_transition_in_progress)
	game.hud.loading_transition_covered.emit({
		"contract_id": LOADING_CONTRACT_ID,
		"transition_id": game._active_map_transition_id,
	})


func _press_joystick(joystick: TouchJoystick, pointer_id: int) -> void:
	var event := InputEventScreenTouch.new()
	event.index = pointer_id
	event.position = joystick.size * 0.5 + Vector2(joystick.radius * 0.8, 0.0)
	event.pressed = true
	joystick._gui_input(event)


func _release_joystick(joystick: TouchJoystick, pointer_id: int) -> void:
	var event := InputEventScreenTouch.new()
	event.index = pointer_id
	event.position = joystick.size * 0.5
	event.pressed = false
	joystick._gui_input(event)


func _assert_all_movement_zero(game: Node, joystick: TouchJoystick, context: String) -> void:
	var snapshot := joystick.input_state_snapshot()
	assert(int(snapshot.pointer_id) == -1, "%s retained joystick pointer" % context)
	assert((snapshot.value as Vector2).is_zero_approx(), "%s retained joystick value" % context)
	assert(game.player.touch_vector.is_zero_approx(), "%s retained player touch vector" % context)


func _assert_stationary_for_physics_frames(game: Node, frame_count: int) -> void:
	var origin: Vector2 = game.player.global_position
	for _frame in frame_count:
		await get_tree().physics_frame
	assert(
		game.player.global_position.is_equal_approx(origin),
		"player moved after READY without a fresh gesture"
	)


func _wait_until_ready(game: Node) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while (
		(bool(game._world_bootstrap_in_progress) or bool(game._map_transition_in_progress))
		and Time.get_ticks_msec() < deadline
	):
		await get_tree().process_frame
	assert(not game._world_bootstrap_in_progress and not game._map_transition_in_progress)


func _wait_for_transition(game: Node) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while bool(game._map_transition_in_progress) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(not game._map_transition_in_progress, "map transition did not reach READY")
