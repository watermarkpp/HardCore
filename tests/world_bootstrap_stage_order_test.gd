extends Node

func _ready() -> void:
	var coord := WorldBootstrapCoordinator.new()

	# Initial state
	assert(coord.stage == WorldBootstrapCoordinator.Stage.IDLE)
	assert(coord.generation == 0)

	# Begin initial world
	coord.begin_initial_world(0)
	assert(coord.generation == 1)
	assert(coord.mode == "initial_world")

	# Advance through stages
	coord.advance(WorldBootstrapCoordinator.Stage.SHOW_LOADING)
	coord.loading_barrier_completed()
	assert(coord.diagnostic.loading_barrier_completed)

	coord.advance(WorldBootstrapCoordinator.Stage.COLLECT_REQUIREMENTS)
	coord.advance(WorldBootstrapCoordinator.Stage.REQUEST_RESOURCES)
	coord.advance(WorldBootstrapCoordinator.Stage.WAIT_RESOURCES)
	coord.advance(WorldBootstrapCoordinator.Stage.BUILD_MAP)
	coord.advance(WorldBootstrapCoordinator.Stage.BUILD_COLLISION)
	coord.advance(WorldBootstrapCoordinator.Stage.SPAWN_ACTORS)
	coord.advance(WorldBootstrapCoordinator.Stage.FINALIZE)

	var snap := coord.finish(true, "")
	assert(snap.success)
	assert(snap.stage == "READY")
	assert(snap.generation == 1)
	var stage_elapsed_ms: Dictionary = snap.get("stage_elapsed_ms", {})
	assert(stage_elapsed_ms.has("SHOW_LOADING"))
	assert(stage_elapsed_ms.has("FINALIZE"))
	assert(
		float(stage_elapsed_ms.get("SHOW_LOADING", -1.0))
		<= float(stage_elapsed_ms.get("FINALIZE", -1.0))
	)

	# Begin new transition → new generation
	coord.begin_map_transition(1)
	assert(coord.generation == 2)
	assert(coord.mode == "map_transition")

	snap = coord.finish(false, "resource_missing")
	assert(not snap.success)
	assert(snap.stage == "FAILED")

	print("WORLD_BOOTSTRAP_STAGE_ORDER_TEST_PASS")
	get_tree().quit(0)
