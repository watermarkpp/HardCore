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

	# Production path: staged map build with real frame-budget slicing.
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
	assert(coord.planned_map_item_count > max_items, "fixture must exceed single-frame budget")
	assert(coord.map_slice_count > 1, "map build must be sliced across frames")
	assert(
		coord.built_map_item_count == coord.planned_map_item_count,
		"map items must all be built: %d/%d" % [
			coord.built_map_item_count, coord.planned_map_item_count,
		]
	)
	assert(coord._map_build_queue.is_empty(), "map queue must be drained")
	assert(coord.map_max_items_in_slice <= max_items, "slice must respect per-frame cap")
	assert(coord.map_max_slice_ms >= 0.0)
	assert(
		game.background.editor_runtime_chunk_texture_count() == 5,
		"orc runtime chunks must be fully built in stable order"
	)
	var summary: Dictionary = coord.ready_contract_summary()
	assert(int(summary.get("built_map_item_count", 0)) == int(summary.get("planned_map_item_count", 0)))

	game.queue_free()
	print(
		"WORLD_BACKGROUND_STAGED_MAP_BUILD_PASS planned=%d built=%d slices=%d max_items_in_slice=%d max_slice_ms=%.3f" % [
			coord.planned_map_item_count,
			coord.built_map_item_count,
			coord.map_slice_count,
			coord.map_max_items_in_slice,
			coord.map_max_slice_ms,
		]
	)
	get_tree().quit(0)
