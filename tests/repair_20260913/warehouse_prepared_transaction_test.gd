extends "res://tests/shared_warehouse_transaction_test.gd"


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
	set_process(true)
	await _launch("deposit", range(100), range(400, 500))
	assert(PlayerState.inventory_occupied_count() == 0 and PlayerState.warehouse_inventory.size() == 500)
	await _launch("withdraw", range(400, 500))
	assert(PlayerState.inventory_occupied_count() == 100)
	# Preparation leaves both memory and primary files unchanged until promotion.
	var before_inventory := PlayerState.inventory.duplicate(true)
	var before_shared_bytes := FileAccess.get_file_as_bytes(PlayerState.shared_warehouse_path)
	var before_profile_bytes := FileAccess.get_file_as_bytes(_profile)
	_completion = false
	_run_transfer("deposit", range(100), range(400, 500))
	assert(PlayerState.inventory == before_inventory)
	var overlap: Dictionary = await PlayerState.transfer_warehouse_prepared("deposit", [0], [400])
	assert(not overlap.success)
	PlayerState.inventory.reverse()
	while not _completion: await get_tree().process_frame
	assert(not _result.success)
	assert(FileAccess.get_file_as_bytes(PlayerState.shared_warehouse_path) == before_shared_bytes)
	assert(FileAccess.get_file_as_bytes(_profile) == before_profile_bytes)
	PlayerState.inventory = before_inventory
	# Failure after shared promotion restores BOTH primaries and preserves memory.
	PlayerState._test_fail_profile_write = true
	await _launch("deposit", range(100), range(400, 500), false)
	assert(PlayerState.inventory == before_inventory)
	assert(PlayerState._shared_digest(PlayerState._read_json(_profile).inventory) == PlayerState._shared_digest(before_inventory))
	assert(PlayerState._shared_digest(PlayerState._read_json(PlayerState.shared_warehouse_path).warehouse_inventory) == PlayerState._shared_digest(PlayerState.warehouse_inventory))
	PlayerState._test_fail_profile_write = false
	# Failed rollback leaves a valid original-contract journal for restart recovery.
	PlayerState._test_fail_profile_write = true
	PlayerState._test_fail_warehouse_rollback_write = true
	await _launch("deposit", range(100), range(400, 500), false)
	assert(PlayerState._warehouse_transaction_locked)
	var journal := PlayerState._read_json_document(PlayerState.shared_warehouse_transaction_log_path).data as Dictionary
	assert(PlayerState._warehouse_transaction_log_is_valid(journal))
	PlayerState._test_fail_profile_write = false
	PlayerState._test_fail_warehouse_rollback_write = false
	PlayerState._recover_shared_warehouse_transaction()
	assert(not PlayerState._warehouse_transaction_locked)
	assert(PlayerState._shared_digest(PlayerState._read_json(_profile).inventory) == PlayerState._shared_digest(before_inventory))
	# A new request succeeds after recovery; worker paths never enter authority.
	await _launch("deposit", range(100), range(400, 500))
	await _launch("withdraw", range(400, 500))
	# A same-size external, valid write cannot be overwritten by a prepared request.
	var profile_snapshot := PlayerState._read_json(_profile)
	profile_snapshot["gold"] = 10
	assert(PlayerState._write_json_atomic(_profile, profile_snapshot))
	_completion = false
	_run_transfer("deposit", [0], [400])
	while PlayerState._warehouse_active_preparation == null: await get_tree().process_frame
	var external_bytes := FileAccess.get_file_as_bytes(_profile).get_string_from_utf8().replace('"gold":10', '"gold":11')
	assert(external_bytes != FileAccess.get_file_as_bytes(_profile).get_string_from_utf8())
	var external_file := FileAccess.open(_profile, FileAccess.WRITE)
	external_file.store_string(external_bytes)
	external_file.close()
	while not _completion: await get_tree().process_frame
	assert(not _result.success)
	assert(int(PlayerState._read_json(_profile).gold) == 11)
	assert(PlayerState.inventory_occupied_count() == 100)
	# Destroying the initiating UI does not destroy the PlayerState transaction.
	var panel := WarehousePanel.new()
	panel.hide()
	add_child(panel)
	panel.open_panel()
	panel._change_warehouse_page(4)
	panel._select_item("bag", 0)
	panel._deposit()
	assert(PlayerState._warehouse_preparation_pending)
	panel.queue_free()
	while PlayerState._warehouse_preparation_pending: await get_tree().process_frame
	assert(PlayerState.inventory_occupied_count() == 99)
	assert(PlayerState._read_json(PlayerState.shared_warehouse_path).warehouse_inventory.size() == 401)
	var output := FileAccess.open("res://outputs/test_logs/warehouse_prepared_latency.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"rows": _measurements}, "\t"))
	output.close()
	_cleanup_isolated_files()
	_restore_player_state()
	print("WAREHOUSE_PREPARED_TRANSACTION_PASS ", JSON.stringify(_measurements))
	get_tree().quit()

var _completion := false
var _result: Dictionary = {}
var _last_frame_usec := 0
var _gaps: Array[float] = []
var _measurements: Array = []

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_frame_usec > 0 and not _completion: _gaps.append((now - _last_frame_usec) / 1000.0)
	_last_frame_usec = now

func _run_transfer(operation: String, sources: Array, targets: Array) -> void:
	_result = await PlayerState.transfer_warehouse_prepared(operation, sources, targets)
	_completion = true

func _launch(operation: String, sources: Array, targets: Array = [], expected := true) -> void:
	_completion = false
	_gaps.clear()
	_last_frame_usec = Time.get_ticks_usec()
	var start := Time.get_ticks_usec()
	_run_transfer(operation, sources, targets)
	while not _completion: await get_tree().process_frame
	_gaps.append((Time.get_ticks_usec() - _last_frame_usec) / 1000.0)
	assert(bool(_result.get("success", false)) == expected, str(_result))
	_gaps.sort()
	_measurements.append({"operation": operation, "expected_success": expected, "wall_ms": (Time.get_ticks_usec() - start) / 1000.0, "frames": _gaps.size(), "max_gap_ms": _gaps.back() if not _gaps.is_empty() else 0.0})
