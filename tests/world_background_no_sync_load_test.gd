extends Node

const LOADING_CONTRACT_ID := "ui.loading.transition.v1"


func _ready() -> void:
	_run.call_deferred()


func _wait_for_transition(game: Node) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while bool(game._map_transition_in_progress) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return not bool(game._map_transition_in_progress)


func _production_travel(game: Node, map_id: int) -> void:
	PlayerState.test_mode = false
	game.travel_to_map(map_id)
	assert(game._map_transition_in_progress)
	game.hud.loading_transition_covered.emit({
		"contract_id": LOADING_CONTRACT_ID,
		"transition_id": game._active_map_transition_id,
	})
	assert(await _wait_for_transition(game), "transition did not finish")
	assert(game.current_map_id == map_id)


func _run() -> void:
	# Static contract: the production build path must not contain synchronous
	# resource loads. WorldBackground keeps exactly one load() call inside the
	# legacy fallback _prefetched_texture(); build stages never call it with an
	# attached coordinator because the prefetch cache always answers first.
	var background_source := FileAccess.get_file_as_string(
		"res://scripts/world_background.gd"
	)
	var load_regex := RegEx.new()
	load_regex.compile("(?<![A-Za-z_])load\\(")
	var load_count := 0
	for _match: RegExMatch in load_regex.search_all(background_source):
		load_count += 1
	assert(load_count == 1, "WorldBackground must keep a single load() fallback, got %d" % load_count)
	var coordinator_source := FileAccess.get_file_as_string(
		"res://scripts/world_bootstrap_coordinator.gd"
	)
	var coordinator_loads := 0
	for _match: RegExMatch in load_regex.search_all(coordinator_source):
		coordinator_loads += 1
	assert(
		coordinator_loads == 0
		and not coordinator_source.contains("ResourceLoader.load("),
		"Coordinator must never synchronously load"
	)
	var game_root_source := FileAccess.get_file_as_string(
		"res://scripts/game_root.gd"
	)
	var game_root_loads := 0
	for _match: RegExMatch in load_regex.search_all(game_root_source):
		game_root_loads += 1
	assert(
		game_root_loads == 0
		and not game_root_source.contains("ResourceLoader.load("),
		"GameRoot must not synchronously load during world entry"
	)

	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game._monster_prefetch_enabled = false

	await _production_travel(game, 217)
	var coord = game._world_bootstrap_coordinator
	assert(coord.unexpected_sync_load_count_build_map == 0, "BUILD_MAP sync loads must be 0")
	assert(coord.unexpected_sync_load_count_build_collision == 0, "BUILD_COLLISION sync loads must be 0")
	assert(coord.unexpected_sync_load_count_spawn_actors == 0, "SPAWN_ACTORS sync loads must be 0")
	assert(coord.unexpected_sync_load_count == 0, "no unexpected sync loads allowed")

	await _production_travel(game, 268)
	coord = game._world_bootstrap_coordinator
	assert(coord.unexpected_sync_load_count_build_map == 0, "BUILD_MAP sync loads must be 0 (wooma)")
	assert(coord.unexpected_sync_load_count_build_collision == 0, "BUILD_COLLISION sync loads must be 0 (wooma)")
	assert(coord.unexpected_sync_load_count_spawn_actors == 0, "SPAWN_ACTORS sync loads must be 0 (wooma)")
	assert(coord.unexpected_sync_load_count == 0, "no unexpected sync loads allowed (wooma)")

	game.queue_free()
	print(
		"WORLD_BACKGROUND_NO_SYNC_LOAD_PASS build_map=%d build_collision=%d spawn_actors=%d total=%d" % [
			coord.unexpected_sync_load_count_build_map,
			coord.unexpected_sync_load_count_build_collision,
			coord.unexpected_sync_load_count_spawn_actors,
			coord.unexpected_sync_load_count,
		]
	)
	get_tree().quit(0)
