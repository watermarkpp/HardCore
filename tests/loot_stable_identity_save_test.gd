extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded())
	var test_root := "user://loot_identity_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = test_root.path_join("characters")
	PlayerState.profile_index_path = test_root.path_join("profiles.json")
	PlayerState.shared_warehouse_path = test_root.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = test_root.path_join("shared.transaction.json")
	PlayerState._shared_warehouse_initialized = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.active_profile_id = "loot_identity_test"
	PlayerState.character_name = "物品身份回归"
	PlayerState.inventory = [{"name": "疾风药水", "count": 1}]
	# Exercise the actual profile write, not the test-mode commit stub.
	PlayerState.test_mode = false
	var result := PlayerState.receive_loot_batch_partial([
		{"item_id": 910013, "item_name": "stale_display_text"},
		{"item_id": 910013, "item_name": "疾风药水"},
	])
	assert(result.success and result.success_count == 2, "stable identity pickup failed")
	assert(PlayerState.inventory.size() == 1, "legacy and ID-bearing stacks did not merge")
	assert(int(PlayerState.inventory[0].get("item_id", -1)) == 910013)
	assert(PlayerState.inventory[0].name == "疾风药水" and PlayerState.inventory[0].count == 3)
	var before := PlayerState.inventory.duplicate(true)
	var rejected := PlayerState.receive_loot_batch_partial([
		{"item_id": 2147483647, "item_name": "疾风药水"},
	])
	assert(rejected.success_count == 0 and PlayerState.inventory == before, "invalid explicit identity fell back to display name")
	assert(GameData.get_item_record({"item_id": 2147483647, "name": "疾风药水"}).is_empty(), "public catalog fell back from invalid explicit ID")
	PlayerState.test_mode = true
	PlayerState._test_force_atomic_write_failure = true
	var failed := PlayerState.receive_loot_batch_partial([{"item_id": 910013}])
	PlayerState._test_force_atomic_write_failure = false
	assert(not failed.success and PlayerState.inventory == before, "ID-bearing pickup failed rollback")
	var saved: Dictionary = PlayerState._read_json(PlayerState._profile_path(PlayerState.active_profile_id))
	assert(int(saved.inventory[0].get("item_id", -1)) == 910013, "save dropped stable ID")
	PlayerState.test_mode = false
	PlayerState.load_save()
	PlayerState.test_mode = true
	# Godot's JSON parser restores numbers as floats; compare semantic fields.
	assert(PlayerState.inventory.size() == 1 and PlayerState.inventory[0].size() == before[0].size())
	assert(int(PlayerState.inventory[0].get("item_id", -1)) == 910013)
	assert(int(PlayerState.inventory[0].get("count", -1)) == 3)
	assert(str(PlayerState.inventory[0].get("name", "")) == "疾风药水", "save reload changed canonical name")
	var catalog := GameData.get_item_record(PlayerState.inventory[0])
	assert(int(catalog.get("itemId", -1)) == 910013)
	assert(str(catalog.art.inventoryIcon.path).ends_with("Items_00420.png"), "reloaded potion resolved placeholder")
	assert(PlayerState._inventory_records_mergeable(
		PlayerState.inventory[0], {"name": "疾风药水", "count": 1},
	), "old name-only receive cannot merge with stable stack")
	assert(not PlayerState._inventory_records_mergeable(
		PlayerState.inventory[0], {"name": "疾风药水", "count": 1, "item_id": 1},
	), "conflicting explicit IDs merged")
	assert(not PlayerState._inventory_records_mergeable(
		PlayerState.inventory[0], {"name": "疾风药水", "count": 1, "bound": true},
	), "opaque instance data was discarded during merge")
	var book := GameData.get_item_record({"item_id": 920043, "name": "stale_display"})
	assert(int(book.get("itemId", -1)) == 920043, "formal skill-book ID has no catalog bridge")
	PlayerState.test_mode = false
	var book_pickup := PlayerState.receive_loot_batch_partial([{"item_id": 920043}])
	assert(book_pickup.success_count == 1, "reserved formal skill-book ID could not enter inventory")
	assert(int(PlayerState.inventory.back().get("item_id", -1)) == 920043)
	PlayerState.load_save()
	assert(int(PlayerState.inventory.back().get("item_id", -1)) == 920043, "reserved skill-book ID lost after real reload")
	PlayerState.test_mode = true
	for stable_first: bool in [false, true]:
		var legacy := {"name": "疾风药水", "count": 1}
		var stable := {"name": "疾风药水", "count": 1, "item_id": 910013}
		PlayerState.inventory = [stable, legacy] if stable_first else [legacy, stable]
		PlayerState.sort_inventory_deterministic()
		assert(PlayerState.inventory.size() == 1)
		assert(int(PlayerState.inventory[0].get("item_id", -1)) == 910013, "sort discarded incoming stable identity")
		assert(int(PlayerState.inventory[0].get("count", 0)) == 2)
	var merged := PlayerState._build_receive_result_for_record(
		{"name": "疾风药水", "count": 1, "item_id": 910013},
		[{"name": "疾风药水", "count": 1}],
	)
	assert(merged.success and int(merged.inventory[0].get("item_id", -1)) == 910013)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var wrong: Dictionary = LootRuntime._drop_output_item_record(910013, "金创药(小量)")
	assert(not game._spawn_loot("金创药(小量)", game.player.global_position, wrong), "unresolved formal ID materialized as another item")
	var valid: Dictionary = LootRuntime._drop_output_item_record(910013, "疾风药水")
	var count_before := PlayerState.item_count("疾风药水")
	assert(game._spawn_loot("疾风药水", game.player.global_position, valid))
	var pickup: LootPickup
	for node: Node in get_tree().get_nodes_in_group("loot_pickups"):
		if node is LootPickup and node.item_id == 910013:
			pickup = node
			break
	assert(pickup != null)
	# Spawn can already request collection: use the idempotent pickup boundary.
	pickup.manager_evaluate_collection(true, 1.0)
	var ground_result: Dictionary = game._flush_loot_collections()
	assert(PlayerState.item_count("疾风药水") == count_before + 1, "formal ground pickup failed to settle: %s inventory=%s" % [ground_result, PlayerState.inventory])
	assert(int(PlayerState.inventory[0].get("item_id", -1)) == 910013)
	game.queue_free()
	await get_tree().process_frame
	print("LOOT_STABLE_IDENTITY_SAVE_TEST_PASS")
	get_tree().quit(0)
