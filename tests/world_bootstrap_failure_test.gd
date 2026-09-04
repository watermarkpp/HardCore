extends Node

func _ready() -> void:
	var coord := WorldBootstrapCoordinator.new()
	coord.begin_initial_world(0)

	# Simulate resource failure
	var snap := coord.finish(false, "missing: res://monsters/boss.tscn (required monster_scene)")
	assert(not snap.success)
	assert(snap.failure_reason != "")
	assert(snap.stage == "FAILED")

	# Verify lock-reason tracking: coordinator remembers failure
	assert(coord.stage == WorldBootstrapCoordinator.Stage.FAILED)

	# New attempt succeeds
	coord.begin_map_transition(1)
	snap = coord.finish(true, "")
	assert(snap.success)
	assert(coord.generation == 2)

	print("WORLD_BOOTSTRAP_FAILURE_TEST_PASS")
	get_tree().quit(0)
