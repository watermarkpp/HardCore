extends Node

const HOME_MAP_ID := 910001


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_test_mode: bool = PlayerState.test_mode
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	assert(game != null, "GameRoot scene failed to instantiate")
	add_child(game)
	var controller: Node = game._town_music_controller
	assert(controller != null, "GameRoot did not create TownMusicController")
	var started: Array[Dictionary] = []
	controller.music_started.connect(
		func(request: Dictionary) -> void: started.append(request.duplicate(true))
	)

	for _frame: int in range(4):
		await get_tree().process_frame
	assert(game.current_map_id == HOME_MAP_ID, "initial world did not enter Bich runtime map")
	assert(not game._map_transition_in_progress, "initial world transition remained active")
	assert(
		not game.hud.loading_transition_overlay.visible,
		"Loading overlay did not finish before town music gate",
	)
	var snapshot: Dictionary = controller.state_snapshot()
	assert(snapshot.map_id == HOME_MAP_ID, "controller map context did not follow GameRoot")
	assert(snapshot.in_town, "Bich service-home safe circle was not treated as town")
	assert(snapshot.loading_finished, "HUD loading_transition_finished did not reach controller")
	assert(snapshot.delay_pending, "town music did not arm after Loading finished")
	assert(not snapshot.music_started_for_entry, "town music started before ten-second delay")
	await get_tree().create_timer(0.1).timeout
	assert(started.is_empty(), "production ten-second gate started too early")

	# Exercise the root-owned transition invalidation boundary without waiting for
	# the destination world: an old pending callback must be gone immediately.
	controller.begin_map_transition(910002, "test:leave-town")
	assert(not controller.is_delay_pending(), "map transition left a stale town delay")
	await get_tree().create_timer(0.1).timeout
	assert(started.is_empty(), "stale town callback crossed a map transition")

	game.queue_free()
	await get_tree().process_frame
	PlayerState.test_mode = previous_test_mode
	print("TOWN_MUSIC_RUNTIME_PASS: READY/HUD finish gate, Bich safe-circle entry, 10s boundary and transition invalidation")
	get_tree().quit(0)
