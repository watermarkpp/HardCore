extends Node

const LOADING_CONTRACT_ID := "ui.loading.transition.v1"


func _ready() -> void:
	_run.call_deferred()


func _wait_for_transition(game: Node) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while bool(game._map_transition_in_progress) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return not bool(game._map_transition_in_progress)


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game._monster_prefetch_enabled = false

	PlayerState.test_mode = false
	game.travel_to_map(217)
	assert(game._map_transition_in_progress)
	assert(not game.gameplay_input_is_enabled(), "input must stay locked while Loading covers")
	game.hud.loading_transition_covered.emit({
		"contract_id": LOADING_CONTRACT_ID,
		"transition_id": game._active_map_transition_id,
	})

	# While the staged pipeline is mid-flight (map/collision building), gameplay
	# input must remain locked.
	var observed_build := false
	var deadline := Time.get_ticks_msec() + 15000
	while (
		bool(game._map_transition_in_progress)
		and Time.get_ticks_msec() < deadline
	):
		var stage: int = int(game._world_bootstrap_coordinator.stage)
		if (
			stage == WorldBootstrapCoordinator.Stage.BUILD_MAP
			or stage == WorldBootstrapCoordinator.Stage.BUILD_COLLISION
		):
			observed_build = true
			assert(
				not game.gameplay_input_is_enabled(),
				"gameplay input must stay closed during staged map/collision build"
			)
			break
		await get_tree().process_frame
	assert(observed_build, "staged build stages were not observed")

	assert(await _wait_for_transition(game), "transition did not finish")
	assert(game.current_map_id == 217)
	assert(not game._map_transition_in_progress)
	assert(game.gameplay_input_is_enabled(), "input must be released only after READY")

	var coord = game._world_bootstrap_coordinator
	assert(coord.stage == WorldBootstrapCoordinator.Stage.READY, "coordinator must reach READY")
	assert(
		coord.built_map_item_count == coord.planned_map_item_count,
		"READY requires complete map build"
	)
	assert(
		coord.built_collision_count == coord.planned_collision_count,
		"READY requires complete collision build"
	)
	assert(coord.failed_collision_count == 0, "READY requires zero failed collisions")
	assert(coord.unexpected_sync_load_count == 0, "READY requires zero sync loads")
	assert(
		not game.background.is_environment_point_blocked(game.player.global_position),
		"READY requires a clear player spawn"
	)

	game.queue_free()
	print(
		"WORLD_BACKGROUND_READY_COLLISION_CONTRACT_PASS input_locked_during_build=true "
		+ "collisions=%d/%d failed=%d ready=%s" % [
			coord.built_collision_count,
			coord.planned_collision_count,
			coord.failed_collision_count,
			str(coord.stage == WorldBootstrapCoordinator.Stage.READY),
		]
	)
	get_tree().quit(0)
