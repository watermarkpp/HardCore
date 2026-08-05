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
	var max_items := int(ProjectSettings.get_setting(
		"world/loading/max_items_per_frame",
		WorldBootstrapCoordinator.DEFAULT_MAX_ITEMS_PER_FRAME
	))
	game.travel_to_map(217)
	assert(game._map_transition_in_progress)
	game.hud.loading_transition_covered.emit({
		"contract_id": LOADING_CONTRACT_ID,
		"transition_id": game._active_map_transition_id,
	})
	assert(await _wait_for_transition(game), "transition did not finish")
	assert(game.current_map_id == 217)

	var coord = game._world_bootstrap_coordinator
	assert(coord.planned_collision_count > max_items, "fixture must exceed single-frame budget")
	assert(coord.collision_slice_count > 1, "collision build must be sliced across frames")
	assert(
		coord.built_collision_count == coord.planned_collision_count,
		"collisions must all be built: %d/%d" % [
			coord.built_collision_count, coord.planned_collision_count,
		]
	)
	assert(coord.failed_collision_count == 0, "failed collisions must be 0")
	assert(coord._collision_build_queue.is_empty(), "collision queue must be drained")
	assert(coord.collision_max_items_in_slice <= max_items, "slice must respect per-frame cap")
	assert(game.background.source_collision_shape_count() >= 4, "hard boundary must exist")

	game.queue_free()
	print(
		"WORLD_BACKGROUND_STAGED_COLLISION_PASS planned=%d built=%d failed=%d slices=%d max_items_in_slice=%d" % [
			coord.planned_collision_count,
			coord.built_collision_count,
			coord.failed_collision_count,
			coord.collision_slice_count,
			coord.collision_max_items_in_slice,
		]
	)
	get_tree().quit(0)
