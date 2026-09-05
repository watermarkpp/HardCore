extends Node

const LootPickupScript := preload("res://scripts/loot_pickup.gd")
const LootManagerScript := preload("res://scripts/loot_pickup_runtime_manager.gd")


func _screen_to_ground(position_px: Vector2) -> Vector2:
	return position_px


func _ground_to_screen(position_gu: Vector2) -> Vector2:
	return position_gu


func _build_manager_fixture() -> Dictionary:
	var player := PlayerCharacter.new()
	player.set_process(false)
	player.set_physics_process(false)
	player.global_position = Vector2.ZERO
	add_child(player)
	var manager := LootManagerScript.new()
	manager.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(manager)
	manager.configure_player(player)
	assert(
		manager.configure_map(
			7,
			1,
			Callable(self, "_screen_to_ground"),
			Callable(self, "_ground_to_screen"),
		),
		"visual clock fixture projection failed",
	)
	var pickup := LootPickupScript.new()
	pickup.setup("金创药(小量)", player)
	pickup.global_position = Vector2(100.0, 100.0)
	add_child(pickup)
	assert(manager.register_pickup(pickup), "visual clock pickup registration failed")
	return {"manager": manager, "pickup": pickup, "player": player}


func _run_visual_sequence(deltas: Array[float]) -> Dictionary:
	var fixture := _build_manager_fixture()
	var manager: LootPickupRuntimeManager = fixture["manager"]
	var pickup: LootPickup = fixture["pickup"]
	var elapsed := 0.0
	for delta in deltas:
		manager._process(delta)
		elapsed += delta
	var result := {
		"elapsed": elapsed,
		"bob_time": pickup._bob_time,
		"visual_updates": manager.manager_visual_update_count,
		"registry_entries": manager.manager_visual_registry_entry_count,
	}
	for key in ["manager", "pickup", "player"]:
		var node: Variant = fixture[key]
		if is_instance_valid(node):
			node.free()
	return result


func _uniform_deltas(frame_rate: int, seconds := 1.0) -> Array[float]:
	var result: Array[float] = []
	for _frame in range(int(seconds * frame_rate)):
		result.append(1.0 / float(frame_rate))
	return result


func _mixed_deltas(seconds := 1.0) -> Array[float]:
	var pattern: Array[float] = [0.005, 0.011, 0.041, 0.016, 0.027]
	var result: Array[float] = []
	var elapsed := 0.0
	var index := 0
	while elapsed < seconds:
		var delta := minf(pattern[index % pattern.size()], seconds - elapsed)
		result.append(delta)
		elapsed += delta
		index += 1
	return result


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()

	var at_30: Dictionary = _run_visual_sequence(_uniform_deltas(30))
	var at_60: Dictionary = _run_visual_sequence(_uniform_deltas(60))
	var at_120: Dictionary = _run_visual_sequence(_uniform_deltas(120))
	var mixed: Dictionary = _run_visual_sequence(_mixed_deltas())
	var bob_times: Array[float] = [
		float(at_30["bob_time"]),
		float(at_60["bob_time"]),
		float(at_120["bob_time"]),
		float(mixed["bob_time"]),
	]
	var min_bob: float = float(bob_times.min())
	var max_bob: float = float(bob_times.max())
	assert(
		max_bob - min_bob <= 0.06,
		"30/60/120/mixed FPS visual elapsed diverged: %s" % [bob_times],
	)
	assert(min_bob >= 0.96, "visual clock dropped too much game time: %s" % [bob_times])
	for snapshot: Dictionary in [at_30, at_60, at_120, mixed]:
		assert(
			int(snapshot["visual_updates"]) <= 31,
			"visual scheduler exceeded the existing 30Hz bound: %s" % [snapshot],
		)
	print(
		"LOOT_VISUAL_CLOCK_PASS: 30/60/120/mixed delta bob parity and 30Hz bound %s"
		% [bob_times],
	)
	get_tree().quit(0)
