extends Node

## Reproduces the user-visible Loading -> destination -> safe-home failure
## through the real staged world pipeline (test-mode travel alone bypasses it).
func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	if not await _wait_ready(game, 910001):
		get_tree().quit(1)
		return
	# First arrival exercises an ordinary level-one character, not inflated HP.
	game.player.current_hp = game.player.max_hp
	if OS.get_environment("HARDCORE_V92_PRODUCTION_LOADING") == "1":
		# Exercise the real async prefetch/actor slices/overlay readiness path.
		# The runner isolates user:// in this worktree.
		PlayerState.test_mode = false
	for target_id: int in [910007, 910003, 910005, 910006, 910001]:
		var operation := Callable(game, "_teleport_to_map_immediate").bind(
			target_id, MapTeleportRuntimePolicy.DEFAULT_CITY_ARRIVAL_ANCHOR_ID)
		if not game._begin_map_transition(operation, target_id):
			push_error("formal destination transition refused: %d" % target_id)
			get_tree().quit(1)
			return
		if not await _wait_ready(game, target_id):
			get_tree().quit(1)
			return
		assert(not game.player.combat_transition_is_active())
		assert(not game.background.is_environment_point_blocked(game.player.global_position))
		print("FORMAL_DESTINATION_READY map=%d" % target_id)
	game.queue_free()
	await get_tree().process_frame
	print("FORMAL_MAP_DESTINATION_REGRESSION_PASS")
	get_tree().quit(0)


func _wait_ready(game: Node, target_id: int) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var summary: Dictionary = game._world_bootstrap_coordinator.snapshot()
		var stage := str(summary.get("stage", ""))
		if stage == "FAILED":
			print("DESTINATION_FAILURE ", JSON.stringify(summary))
		if not bool(game._map_transition_in_progress) and stage == "READY":
			if int(game.current_map_id) == target_id:
				return true
			print("DESTINATION_WRONG_MAP expected=%d actual=%d actor_reason=%s summary=%s" % [
				target_id, game.current_map_id, game._staged_actor_spawn_failure_reason, JSON.stringify(summary)])
			return false
	print("DESTINATION_TIMEOUT expected=%d actual=%d actor_reason=%s summary=%s" % [
		target_id, game.current_map_id, game._staged_actor_spawn_failure_reason,
		JSON.stringify(game._world_bootstrap_coordinator.snapshot())])
	return false
