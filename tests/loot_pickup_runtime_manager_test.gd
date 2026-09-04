extends Node

const LootPickupScript := preload("res://scripts/loot_pickup.gd")
const LootManagerScript := preload("res://scripts/loot_pickup_runtime_manager.gd")
const RuntimeDiagnosticsScript := preload("res://scripts/runtime_diagnostics.gd")
const DeviceLabRuntimeScript := preload("res://scripts/device_lab_runtime.gd")

var _manager: Node
var _player: PlayerCharacter
var _collection_events: Array[int] = []
var _gold_events := 0


func _ready() -> void:
	_run.call_deferred()


func _screen_to_ground(position_px: Vector2) -> Vector2:
	return position_px


func _ground_to_screen(position_gu: Vector2) -> Vector2:
	return position_gu


func _on_item_collected(_item_name: String, pickup: LootPickup) -> void:
	_collection_events.append(pickup.get_instance_id())
	pickup.reject_collection("manager-test-reject")


func _on_gold_collected(_amount: int, pickup: LootPickup) -> void:
	_gold_events += 1
	pickup.confirm_collect()


func _new_pickup(
	position: Vector2,
	item_name := "金创药(小量)",
	gold := 0,
) -> LootPickup:
	var pickup := LootPickupScript.new()
	if gold > 0:
		pickup.setup_gold(gold, _player)
		pickup.gold_collected.connect(_on_gold_collected)
	else:
		pickup.setup(item_name, _player)
		pickup.collected.connect(_on_item_collected)
	add_child(pickup)
	pickup.global_position = position
	assert(_manager.register_pickup(pickup), "manager rejected a valid pickup")
	return pickup


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.inventory = []
	PlayerState.gold = 0
	RuntimeDiagnosticsScript.set_device_lab_performance_enabled(true)
	RuntimeDiagnosticsScript.reset_performance_window()

	_player = PlayerCharacter.new()
	_player.set_physics_process(false)
	_player.global_position = Vector2(10000.0, 10000.0)
	add_child(_player)
	_manager = LootManagerScript.new()
	add_child(_manager)
	_manager.configure_player(_player)
	assert(_manager.configure_map(
		7,
		1,
		Callable(self, "_screen_to_ground"),
		Callable(self, "_ground_to_screen"),
	))

	var near_pickups: Array[LootPickup] = []
	for index in range(82):
		var angle := TAU * float(index) / 82.0
		near_pickups.append(_new_pickup(
			Vector2(cos(angle), sin(angle)) * 0.60,
		))
	for index in range(118):
		_new_pickup(Vector2(10.0 + float(index % 20) * 4.0, 10.0 + float(index / 20) * 4.0))
	assert(_manager.diagnostics_snapshot().registered_pickup_count == 200)

	_player.global_position = Vector2.ZERO
	_manager.player_position_changed(_player.global_position)
	assert(_collection_events.size() == 82, "nearby bucket query did not return exactly 82 pickups")
	for index in range(near_pickups.size()):
		assert(
			_collection_events[index] == near_pickups[index].get_instance_id(),
			"stable registration order changed at candidate %d" % index,
		)
	assert(_manager.diagnostics_snapshot().manager_full_scan_count == 0)
	assert(_manager.diagnostics_snapshot().spatial_index.index_full_scan_count == 0)
	assert(RuntimeDiagnosticsScript.performance_counter(&"loot_pickup_process_calls") == 0)

	# A direct position update crosses a bucket and is visible on the next query.
	var moved := near_pickups[0]
	_player.global_position = Vector2(100.0, 100.0)
	_manager.player_position_changed(_player.global_position)
	moved.global_position = Vector2(8.2, 8.2)
	assert(_manager.update_pickup_position(moved), "cross-bucket update rejected")
	_player.global_position = moved.global_position
	_collection_events.clear()
	_manager.player_position_changed(_player.global_position)
	assert(_collection_events == [moved.get_instance_id()], "cross-bucket candidate missing or duplicated")

	# Strict radius boundary: equality is outside, while a point just inside is
	# accepted.  The broadphase must not widen the gameplay rule.
	_player.global_position = Vector2.ZERO
	for pickup: LootPickup in near_pickups:
		pickup._arm_collection_retry_cooldown()
	_player.global_position = Vector2(100.0, 100.0)
	var boundary := _new_pickup(Vector2(0.75, 0.0))
	_collection_events.clear()
	_player.global_position = Vector2.ZERO
	_manager.player_position_changed(Vector2.ZERO)
	assert(_collection_events.is_empty(), "0.75 GU boundary must be outside")
	boundary.global_position = Vector2(0.749, 0.0)
	assert(_manager.update_pickup_position(boundary))
	_manager.player_position_changed(Vector2.ZERO)
	assert(_collection_events == [boundary.get_instance_id()], "inside-radius pickup was not collected")

	# Gold bypasses inventory weight and the exact same signal/confirm lifecycle
	# is retained.  A rejected item remains pending-free and retries after 5s.
	_player.global_position = Vector2(100.0, 100.0)
	var gold := _new_pickup(Vector2(30.0, 30.0), "", 3000)
	var gold_before := _gold_events
	_player.global_position = Vector2(30.0, 30.0)
	_manager.player_position_changed(_player.global_position)
	assert(_gold_events == gold_before + 1 and gold.is_queued_for_deletion())

	PlayerState.inventory = [{"name": "强效太阳水", "count": 99}]
	var overweight := _new_pickup(Vector2(31.0, 30.0), "强效太阳水")
	_player.global_position = overweight.global_position
	_collection_events.clear()
	_manager.player_position_changed(_player.global_position)
	assert(_collection_events == [overweight.get_instance_id()])
	_manager._process(4.9)
	assert(_collection_events.size() == 1, "overweight retry happened before 5 seconds")
	_manager._process(0.1)
	assert(_collection_events.size() == 2, "overweight retry did not happen at deadline")
	_player.global_position = Vector2(100.0, 100.0)
	_manager.player_position_changed(_player.global_position)
	_player.global_position = overweight.global_position
	_manager.player_position_changed(_player.global_position)
	assert(_collection_events.size() == 3, "leaving range did not reset retry context")

	# Visual motion is manager-owned at 30 Hz and must skip hidden pickups.  The
	# same 200-node fixture therefore exercises the presentation gate without
	# turning collection back into a full per-pickup process loop.
	var visual_count_before := int(
		_manager.diagnostics_snapshot().manager_visual_update_count
	)
	var visible_pickup_count := 0
	for index in range(near_pickups.size()):
		near_pickups[index].visible = index % 2 == 0
		if near_pickups[index].visible:
			visible_pickup_count += 1
	_manager._process(1.0 / 30.0)
	var visual_count_after := int(
		_manager.diagnostics_snapshot().manager_visual_update_count
	)
	var visible_registered_count := (
		int(_manager.diagnostics_snapshot().registered_pickup_count)
		- near_pickups.size()
		+ visible_pickup_count
	)
	assert(
		visual_count_after - visual_count_before <= visible_registered_count,
		"hidden loot received a manager visual update",
	)
	for pickup: LootPickup in near_pickups:
		pickup.visible = true
	var fail_safe_before := int(
		_manager.diagnostics_snapshot().manager_fail_safe_check_count
	)
	_manager._process(LootManagerScript.FAIL_SAFE_INTERVAL_SECONDS * 0.5)
	_manager._process(LootManagerScript.FAIL_SAFE_INTERVAL_SECONDS * 0.5)
	assert(
		int(_manager.diagnostics_snapshot().manager_fail_safe_check_count)
		> fail_safe_before,
		"manager fail-safe cadence did not advance at its bounded interval",
	)

	# Unregister/death/map clear are index lifecycle operations, not group scans.
	var removed_id := near_pickups[1].get_instance_id()
	near_pickups[1].queue_free()
	await get_tree().process_frame
	assert(_manager.diagnostics_snapshot().registered_pickup_count == 201)
	_manager.clear_map(7)
	assert(_manager.diagnostics_snapshot().registered_pickup_count == 0)
	assert(_manager.diagnostics_snapshot().spatial_index.index_query_count > 0)

	await _run_game_root_collection_and_logout()

	RuntimeDiagnosticsScript.set_device_lab_performance_enabled(false)
	RuntimeDiagnosticsScript.refresh_performance_gate()
	print("LOOT_PICKUP_RUNTIME_MANAGER_PASS: 200 bucketed pickups, strict radius, FIFO, retries, map clear, safe logout")
	get_tree().quit(0)


func _run_game_root_collection_and_logout() -> void:
	var profile_id := "R3X5_%06d" % posmod(Time.get_ticks_msec(), 1000000)
	PlayerState.reset_progress()
	PlayerState.create_character(profile_id, "战士", "男")
	PlayerState.inventory = []
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.set_process(false)
	game.set_physics_process(false)
	var manager: Node = game.get("_loot_pickup_runtime_manager")
	manager.set_process(false)
	var player: PlayerCharacter = game.get("player")
	# GameRoot startup may restore the persisted profile while the bootstrap
	# finishes.  Establish the deterministic fixture after that lifecycle has
	# settled, leaving one free slot while making the next item overweight.
	PlayerState.level = 1
	PlayerState.profession = "战士"
	PlayerState.inventory = [{"name": "强效太阳水", "count": 99}]
	PlayerState.recalculate_stats()
	assert(
		PlayerState.inventory_weight() > PlayerState.max_inventory_weight(),
		"overweight fixture did not exceed the authoritative bag limit",
	)
	PlayerState.inventory = []
	PlayerState.recalculate_stats()
	var loot_position := Vector2(12000.0, 12000.0)
	player.global_position = loot_position + Vector2(50.0, 0.0)
	manager.player_position_changed(player.global_position)
	assert(game._spawn_loot("强效太阳水", loot_position))
	player.global_position = loot_position
	manager.player_position_changed(loot_position)
	var device_snapshot := DeviceLabRuntimeScript.build_snapshot(game)
	var loot_runtime: Dictionary = device_snapshot.get("loot_runtime", {})
	var performance_diagnostics: Dictionary = device_snapshot.get(
		"performance_diagnostics", {}
	)
	var performance_context: Dictionary = performance_diagnostics.get("context", {})
	assert(
		str(loot_runtime.get("contract_id", "")) == LootManagerScript.CONTRACT_ID,
		"Device Lab snapshot omitted the loot runtime contract",
	)
	assert(
		performance_context.has("loot_registered_pickup_count")
		and performance_context.has("loot_spatial_query_count")
		and performance_context.has("loot_spatial_candidate_count")
		and performance_context.has("loot_full_scan_count"),
		"Device Lab performance context omitted loot spatial fields",
	)
	PlayerState._test_force_atomic_write_failure = true
	var failed: Dictionary = game._prepare_safe_logout()
	PlayerState._test_force_atomic_write_failure = false
	assert(not bool(failed.get("success", true)), "loot save failure must reject safe logout")
	assert(str(failed.get("reason", "")) == "safe_logout_loot_collection_failed")
	assert(PlayerState.inventory.is_empty(), "failed loot transaction changed inventory")

	# A partial batch keeps FIFO and confirm/reject semantics: the overweight
	# item is rejected while the later gold candidate succeeds exactly once.
	PlayerState.level = 1
	PlayerState.profession = "战士"
	PlayerState.inventory = [{"name": "强效太阳水", "count": 99}]
	PlayerState.recalculate_stats()
	assert(
		PlayerState.inventory_weight() > PlayerState.max_inventory_weight(),
		"partial fixture did not exceed the authoritative bag limit",
	)
	var partial_inventory_before := PlayerState.inventory.duplicate(true)
	player.global_position = loot_position + Vector2(100.0, 0.0)
	manager.player_position_changed(player.global_position)
	assert(game._spawn_loot("强效太阳水", loot_position))
	assert(game._spawn_gold_loot(77, loot_position))
	player.global_position = loot_position
	manager.player_position_changed(loot_position)
	var gold_before := PlayerState.gold
	var success: Dictionary = game._prepare_safe_logout()
	assert(bool(success.get("success", false)), "safe logout did not flush pending loot")
	assert(PlayerState.gold == gold_before + 77, "gold partial outcome missing")
	assert(PlayerState.inventory == partial_inventory_before, "overweight item was incorrectly committed")
	var gold_after := PlayerState.gold
	var repeat: Dictionary = game._prepare_safe_logout()
	assert(bool(repeat.get("success", false)))
	assert(PlayerState.gold == gold_after, "safe logout repeated a confirmed reward")
	assert(game._pending_loot_collections.is_empty(), "safe logout left deferred loot candidates")

	game.queue_free()
	await get_tree().process_frame
