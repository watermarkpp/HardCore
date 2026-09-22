extends Node

const LootPickupScript := preload("res://scripts/loot_pickup.gd")
const LootManagerScript := preload("res://scripts/loot_pickup_runtime_manager.gd")

var _manager: LootManagerScript
var _player: PlayerCharacter
var _pickup: LootPickup
var _collection_event_count := 0
var _capacity_available := false


func _screen_to_ground(position_px: Vector2) -> Vector2:
	return position_px


func _ground_to_screen(position_gu: Vector2) -> Vector2:
	return position_gu


func _on_collected(_item_name: String, pickup: LootPickup) -> void:
	_collection_event_count += 1
	if _capacity_available:
		pickup.confirm_collect()
	else:
		pickup.reject_collection("测试容量已满")


func _ready() -> void:
	# Keep this fixture alive while the tree is paused, while the manager stays
	# explicitly pausable just like it is under the production GameRoot node.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()

	_player = PlayerCharacter.new()
	_player.set_process(false)
	_player.set_physics_process(false)
	_player.global_position = Vector2(100.0, 100.0)
	add_child(_player)

	_manager = LootManagerScript.new()
	_manager.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_manager)
	_manager.configure_player(_player)
	assert(
		_manager.configure_map(
			7,
			1,
			Callable(self, "_screen_to_ground"),
			Callable(self, "_ground_to_screen"),
		),
		"retry clock fixture projection failed",
	)

	_pickup = LootPickupScript.new()
	_pickup.setup("金创药(小量)", _player)
	_pickup.global_position = Vector2.ZERO
	_pickup.collected.connect(_on_collected)
	add_child(_pickup)
	assert(_manager.register_pickup(_pickup), "retry clock pickup registration failed")

	_player.global_position = Vector2.ZERO
	_manager.player_position_changed(_player.global_position)
	assert(_collection_event_count == 1, "initial capacity rejection did not occur")
	assert(
		is_equal_approx(_pickup.retry_cooldown_remaining(), 5.0),
		"initial rejection did not arm the five-second retry deadline",
	)

	# Repeated small movements are intentionally faster than the 100ms
	# fail-safe interval.  Capacity recovers after two seconds, but the player
	# never stops moving or leaves the strict collection radius.
	var simulated_elapsed := 0.0
	for _step in range(40):
		_player.global_position = Vector2(0.05 if _step % 2 == 0 else 0.0, 0.0)
		_manager.player_position_changed(_player.global_position)
		_manager._process(0.05)
		simulated_elapsed += 0.05
	assert(_collection_event_count == 1, "retry fired before the five-second deadline")
	assert(
		_pickup.retry_cooldown_remaining() > 2.9
		and _pickup.retry_cooldown_remaining() < 3.1,
		"continuous movement did not consume exactly two seconds of game time",
	)

	_capacity_available = true
	var recovery_elapsed := -1.0
	for _step in range(80):
		_player.global_position = Vector2(0.05 if _step % 2 == 0 else 0.0, 0.0)
		_manager.player_position_changed(_player.global_position)
		_manager._process(0.05)
		simulated_elapsed += 0.05
		if _collection_event_count == 2:
			recovery_elapsed = simulated_elapsed
			break
	assert(_collection_event_count == 2, "continuous movement starved the retry deadline")
	assert(
		recovery_elapsed >= 4.95 and recovery_elapsed <= 5.20,
		"capacity recovery was not consumed at the five-second game-time deadline",
	)
	assert(_pickup.is_queued_for_deletion(), "successful retry did not confirm the pickup")

	# A pause must stop this manager's game-time clock.  The test root remains
	# processable to observe paused frames, while the manager is pausable.
	var pause_pickup := LootPickupScript.new()
	pause_pickup.setup("金创药(小量)", _player)
	pause_pickup.global_position = Vector2.ZERO
	pause_pickup.collected.connect(_on_collected)
	add_child(pause_pickup)
	_capacity_available = false
	_manager.register_pickup(pause_pickup)
	_manager.player_position_changed(Vector2.ZERO)
	assert(_collection_event_count == 3, "pause fixture did not arm a retry")
	var paused_remaining := pause_pickup.retry_cooldown_remaining()
	var paused_fail_safe_checks := _manager.manager_fail_safe_check_count
	get_tree().paused = true
	for _frame in range(3):
		await get_tree().process_frame
	assert(
		is_equal_approx(pause_pickup.retry_cooldown_remaining(), paused_remaining),
		"paused tree advanced the loot retry clock",
	)
	assert(
		_manager.manager_fail_safe_check_count == paused_fail_safe_checks,
		"paused tree ran the pausable loot manager",
	)
	get_tree().paused = false

	if is_instance_valid(pause_pickup):
		pause_pickup.free()
	if is_instance_valid(_pickup):
		_pickup.free()
	if is_instance_valid(_manager):
		_manager.free()
	if is_instance_valid(_player):
		_player.free()
	print("LOOT_RETRY_CLOCK_PASS: continuous movement deadline, capacity recovery, and pause clock")
	call_deferred("free")
	get_tree().call_deferred("quit", 0)
