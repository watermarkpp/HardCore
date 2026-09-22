extends "res://tests/shared_warehouse_transaction_test.gd"

var timing_rows: Array[Dictionary] = []
func timed(label: String, action: Callable) -> void:
	var begin := Time.get_ticks_usec()
	action.call()
	timing_rows.append({"action": label, "ms": (Time.get_ticks_usec() - begin) / 1000.0})

func _run() -> void:
	_capture_player_state()
	assert(GameData.ensure_loaded())
	_root = "user://shared_warehouse_transaction_isolated_latency_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = _root.path_join("characters")
	PlayerState.profile_index_path = _root.path_join("index.json")
	PlayerState.shared_warehouse_path = _root.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = _root.path_join("shared.transaction.json")
	_profile = PlayerState.profile_directory.path_join("p.json")
	_other_profile = PlayerState.profile_directory.path_join("q.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.test_mode = true
	PlayerState.level = 60
	PlayerState.profession = "战士"
	PlayerState.recalculate_stats(false)
	_write_index()
	assert(PlayerState._write_json_atomic(_other_profile, {"profile_id": "q", "inventory": []}))
	_reset_documents("placeholder")
	var equipment: Array[Dictionary] = []
	var light_items: Array[Dictionary] = []
	for item: Dictionary in GameData.item_catalog:
		if item.get("kind", "") == "equipment":
			equipment.append(item)
			if int(item.get("weight", 0)) <= 1: light_items.append(item)
	PlayerState.inventory = []
	PlayerState.warehouse_inventory = []
	for i in range(500):
		var item := light_items[i % light_items.size()] if i < 100 else equipment[i % equipment.size()]
		var instance := ItemDropInstanceRules.create_instance(item, "warehouse-latency-%d" % i)
		assert(not instance.is_empty())
		if i < 100: PlayerState.inventory.append(instance)
		else: PlayerState.warehouse_inventory.append(instance)
	assert(PlayerState._write_json_atomic(_profile, {"profile_id": "p", "inventory": PlayerState.inventory.duplicate(true)}))
	assert(PlayerState._write_json_atomic(PlayerState.shared_warehouse_path, _shared_document(PlayerState.warehouse_inventory)))
	var slots: Array = range(100)
	var destinations: Array = range(400, 500)
	for round_index in range(4):
		timed("deposit.100.into.400", func() -> void:
			var result := PlayerState.deposit_to_warehouse_batch(slots, destinations)
			assert(result.get("success", false) and result.get("transferred", 0) == 100, str(result))
		)
		assert(PlayerState.inventory_occupied_count() == 0 and PlayerState.warehouse_inventory.size() == 500)
		if round_index == 0:
			var shared := PlayerState._read_json_document(PlayerState.shared_warehouse_path).get("data", {}) as Dictionary
			for repeat in range(3):
				timed("component.raw_read", func() -> void: PlayerState._read_json_document(PlayerState.shared_warehouse_path))
				timed("component.validate_shared", func() -> void: PlayerState._validate_shared_warehouse_document(shared))
				timed("component.validate_items", func() -> void: PlayerState._validate_saved_item_records(shared.warehouse_inventory, 500))
				timed("component.catalog500", func() -> void:
					for record: Dictionary in shared.warehouse_inventory: GameData.get_item_rules_record(record)
				)
				timed("component.drop500", func() -> void:
					for record: Dictionary in shared.warehouse_inventory: PlayerState._validated_drop_instance_id(record)
				)
		var panel := WarehousePanel.new()
		panel.hide()
		add_child(panel)
		for i in range(4): await get_tree().process_frame
		for i in range(3):
			timed("warehouse.open.saved500", func() -> void: panel.open_panel())
			for frame in range(2): await get_tree().process_frame
			panel.hide()
			timed("bank.read.saved500", func() -> void: assert(PlayerState.shared_gold_balance() == 0))
		panel.queue_free()
		await get_tree().process_frame
		timed("withdraw.100.from.500", func() -> void:
			var result := PlayerState.withdraw_from_warehouse_batch(destinations)
			assert(result.get("success", false) and result.get("transferred", 0) == 100, str(result))
		)
		assert(PlayerState.inventory_occupied_count() == 100)
		assert(PlayerState._validate_shared_warehouse_document(PlayerState._read_json(PlayerState.shared_warehouse_path)))
	var output := FileAccess.open("res://outputs/test_logs/warehouse_storage_latency.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"scope": "real isolated storage with 500 validated drop instances", "rows": timing_rows}, "\t"))
	output.close()
	_cleanup_isolated_files()
	_restore_player_state()
	print("WAREHOUSE_STORAGE_LATENCY_PASS ", JSON.stringify(timing_rows))
	get_tree().quit()
