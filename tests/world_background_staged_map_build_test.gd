extends Node

const LOADING_CONTRACT_ID := "ui.loading.transition.v1"


func _ready() -> void:
	_run.call_deferred()


func _wait_for_transition(game: Node) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while bool(game._map_transition_in_progress) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return not bool(game._map_transition_in_progress)


func _wait_for_initial_world(game: Node) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while not bool(game.gameplay_input_is_enabled()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(game.gameplay_input_is_enabled())


func _run() -> void:
	# Standalone/editor-style callers keep the legacy _ready build by default.
	var legacy_background := WorldBackground.new()
	legacy_background.zone_name = "staged-build-contract-test-empty"
	add_child(legacy_background)
	await get_tree().process_frame
	assert(
		legacy_background.legacy_ready_rebuild_count() == 1,
		"default WorldBackground attachment must retain the legacy _ready build"
	)
	assert(
		bool(legacy_background._staged_build_complete),
		"default legacy build must still finish its environment contract"
	)
	legacy_background.queue_free()
	await get_tree().process_frame

	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	assert(await _wait_for_initial_world(game), "initial staged world did not finish")
	var initial_bootstrap_deadline := Time.get_ticks_msec() + 15000
	while (
		bool(game._world_bootstrap_in_progress)
		and Time.get_ticks_msec() < initial_bootstrap_deadline
	):
		await get_tree().process_frame
	assert(
		not bool(game._world_bootstrap_in_progress),
		"initial staged bootstrap must finish before the transition fixture starts"
	)
	assert(
		game.background.legacy_ready_rebuild_count() == 0,
		"GameRoot initial staged entry must skip the legacy _ready build"
	)
	assert(
		bool(game.background.get_meta("initial_legacy_build_skipped", false)),
		"GameRoot must declare the staged initial-build contract before attachment"
	)
	game._monster_prefetch_enabled = false

	# Production path: staged map build with real frame-budget slicing.
	PlayerState.test_mode = false
	var max_items := int(ProjectSettings.get_setting(
		"world/loading/max_items_per_frame",
		WorldBootstrapCoordinator.DEFAULT_MAX_ITEMS_PER_FRAME
	))
	var travel_requested := bool(game._request_map_travel(911001))
	assert(
		travel_requested and game._map_transition_in_progress,
		"staged travel request failed: %s" % JSON.stringify(game.gameplay_input_gate_snapshot())
	)
	game.hud.loading_transition_covered.emit({
		"contract_id": LOADING_CONTRACT_ID,
		"transition_id": game._active_map_transition_id,
	})
	assert(await _wait_for_transition(game), "transition did not finish")
	assert(game.current_map_id == 911001)

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
