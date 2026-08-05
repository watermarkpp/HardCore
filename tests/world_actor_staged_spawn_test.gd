extends Node

func _ready() -> void:
	var coord := WorldBootstrapCoordinator.new()

	for i: int in range(50):
		coord._actor_spawn_queue.append({
			"priority": 10 if i < 5 else 40,
			"source_index": i,
			"actor_type": "monster",
			"actor_id": "monster_%03d" % i,
		})

	assert(coord._actor_spawn_queue.size() == 50)

	# Deterministic order: first items are priority 10 (gates/exits)
	var first_item: Dictionary = coord._actor_spawn_queue[0]
	assert(first_item.priority == 10)
	assert(first_item.source_index == 0)

	# Last items are priority 40 (monsters) — still in source_index order
	var last_item: Dictionary = coord._actor_spawn_queue[49]
	assert(last_item.priority == 40)

	print("WORLD_ACTOR_STAGED_SPAWN_TEST_PASS")
	get_tree().quit(0)
