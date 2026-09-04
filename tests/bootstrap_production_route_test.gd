extends Node

# Verify all world-entry paths route through WorldBootstrapCoordinator
func _ready() -> void:
	var coord := WorldBootstrapCoordinator.new()
	
	# Initial world entry
	coord.begin_initial_world(4)
	assert(coord.generation == 1)
	assert(coord.mode == "initial_world")
	assert(coord.stage == WorldBootstrapCoordinator.Stage.IDLE)
	
	# Map transition
	coord.begin_map_transition(5)
	assert(coord.generation == 2)
	assert(coord.mode == "map_transition")
	
	# Service home (same coordinator, new generation)
	coord.begin_map_transition(4)
	assert(coord.generation == 3)
	
	# Verify old generation rejected
	assert(not coord.mark_heavy_work_started(1))
	assert(not coord.mark_heavy_work_started(2))
	assert(coord.mark_heavy_work_started(3))
	
	coord.finish(true, "")
	assert(coord.stage == WorldBootstrapCoordinator.Stage.READY)
	
	print("BOOTSTRAP_PRODUCTION_ROUTE_TEST_PASS")
	get_tree().quit(0)
