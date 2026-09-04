extends Node

func _ready() -> void:
	# Verify Coordinator class exists with production-ready API
	var coord := WorldBootstrapCoordinator.new()

	# Test initial world entry
	coord.begin_initial_world(0)
	assert(coord.generation > 0)
	assert(coord.mode == "initial_world")
	assert(coord.stage == WorldBootstrapCoordinator.Stage.IDLE)

	coord.advance(WorldBootstrapCoordinator.Stage.SHOW_LOADING)
	coord.loading_barrier_completed()
	coord.advance(WorldBootstrapCoordinator.Stage.COLLECT_REQUIREMENTS)
	coord.advance(WorldBootstrapCoordinator.Stage.BUILD_MAP)
	coord.advance(WorldBootstrapCoordinator.Stage.BUILD_COLLISION)
	coord.advance(WorldBootstrapCoordinator.Stage.SPAWN_ACTORS)
	coord.advance(WorldBootstrapCoordinator.Stage.FINALIZE)

	var snap := coord.finish(true, "")
	assert(snap.success)
	assert(snap.stage == "READY")

	# Test map transition entry
	coord.begin_map_transition(1)
	assert(coord.generation == 2)
	assert(coord.mode == "map_transition")
	assert(coord._map_build_queue.is_empty())
	assert(coord._actor_spawn_queue.is_empty())

	# Verify legacy generation rejected
	assert(not coord.mark_heavy_work_started(1))

	# Verify coordinator is directly usable (not just test-only)
	assert(coord.has_method("process_queue_with_budget"))
	assert(coord.has_method("submit_actor_descriptor"))
	assert(coord.has_method("process_actor_queue"))
	assert(coord.has_method("_register_resource"))
	assert(coord.has_method("finish"))

	print("WORLD_BOOTSTRAP_PRODUCTION_ENTRY_TEST_PASS")
	get_tree().quit(0)
