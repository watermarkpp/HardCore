extends Node

func _ready() -> void:
	var coord := WorldBootstrapCoordinator.new()

	# Initial world
	coord.begin_initial_world(0)
	var gen_init := coord.generation
	assert(gen_init == 1)
	assert(coord.mode == "initial_world")

	# Map transition reuses same coordinator
	coord.begin_map_transition(1)
	var gen_trans := coord.generation
	assert(gen_trans == gen_init + 1)
	assert(coord.mode == "map_transition")

	# Old generation marked as stale
	assert(not coord.mark_heavy_work_started(gen_init))
	assert(coord.mark_heavy_work_started(gen_trans))

	# Verify queues were cleared for new generation
	assert(coord._map_build_queue.is_empty())
	assert(coord._actor_spawn_queue.is_empty())

	coord.finish(true, "")
	assert(coord.stage == WorldBootstrapCoordinator.Stage.READY)

	print("MAP_TRANSITION_BOOTSTRAP_REUSE_TEST_PASS")
	get_tree().quit(0)
