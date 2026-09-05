extends Node

const LootIndexScript := preload("res://scripts/runtime_loot_spatial_index.gd")
const LootPickupScript := preload("res://scripts/loot_pickup.gd")
const LootManagerScript := preload("res://scripts/loot_pickup_runtime_manager.gd")


func _screen_to_ground(position_px: Vector2) -> Vector2:
	return position_px


func _ground_to_screen(position_gu: Vector2) -> Vector2:
	return position_gu


func _new_pickup(position_gu := Vector2.ZERO) -> LootPickup:
	var pickup := LootPickupScript.new()
	pickup.global_position = position_gu
	add_child(pickup)
	return pickup


func _measure_index_query(count: int, reverse_order: bool) -> Dictionary:
	var index := LootIndexScript.new()
	var pickups: Array[LootPickup] = []
	for item_index in range(count):
		var pickup := _new_pickup(Vector2.ZERO)
		pickups.append(pickup)
		var stable_order := count - item_index if reverse_order else item_index + 1
		assert(index.register(
			pickup.get_instance_id(),
			7,
			Vector2(0.1, 0.1),
			stable_order,
			pickup,
		))
	var output: Array = []
	var started_usec := Time.get_ticks_usec()
	index.query_nearby_into(7, Vector2.ZERO, 0.75, output)
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	assert(output.size() == count, "controlled index query lost candidates")
	for item_index in range(output.size()):
		var expected_pickup := pickups[count - item_index - 1] if reverse_order else pickups[item_index]
		assert(output[item_index] == expected_pickup, "index stable order changed")
	for pickup: LootPickup in pickups:
		if is_instance_valid(pickup):
			pickup.free()
	return {
		"count": count,
		"reverse_order": reverse_order,
		"query_usec": elapsed_usec,
		"candidate_count": output.size(),
		"estimated_worst_case_comparisons": count * (count - 1) / 2,
	}


func _measure_visual_registry(count: int) -> Dictionary:
	var player := PlayerCharacter.new()
	player.set_process(false)
	player.set_physics_process(false)
	player.global_position = Vector2.ZERO
	add_child(player)
	var manager := LootManagerScript.new()
	manager.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(manager)
	manager.configure_player(player)
	assert(manager.configure_map(
		7,
		1,
		Callable(self, "_screen_to_ground"),
		Callable(self, "_ground_to_screen"),
	))
	var pickups: Array[LootPickup] = []
	for item_index in range(count):
		var pickup := _new_pickup(Vector2(100.0 + item_index, 100.0))
		pickups.append(pickup)
		assert(manager.register_pickup(pickup))
	var scan_count := 3
	var started_usec := Time.get_ticks_usec()
	for _scan in range(scan_count):
		manager._update_visuals(1.0 / 30.0)
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	var result := {
		"count": count,
		"scan_count": scan_count,
		"registry_entries": manager.manager_visual_registry_entry_count,
		"visual_updates": manager.manager_visual_update_count,
		"scan_usec": elapsed_usec,
	}
	for pickup: LootPickup in pickups:
		if is_instance_valid(pickup):
			pickup.free()
	if is_instance_valid(manager):
		manager.free()
	if is_instance_valid(player):
		player.free()
	return result


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var index_results: Array[Dictionary] = []
	var visual_results: Array[Dictionary] = []
	for count in [100, 300, 1000]:
		index_results.append(_measure_index_query(count, false))
		index_results.append(_measure_index_query(count, true))
		visual_results.append(_measure_visual_registry(count))
	for result: Dictionary in index_results:
		assert(int(result["candidate_count"]) == int(result["count"]))
	for result: Dictionary in visual_results:
		assert(int(result["registry_entries"]) == int(result["count"]) * int(result["scan_count"]))
		assert(int(result["visual_updates"]) == int(result["registry_entries"]))
	print("LOOT_REGISTRY_BENCHMARK_PASS: O01/O02 controlled counts only")
	print("LOOT_O01_MEASUREMENTS=" + JSON.stringify(index_results))
	print("LOOT_O02_MEASUREMENTS=" + JSON.stringify(visual_results))
	get_tree().quit(0)
