extends "res://tests/shared_warehouse_transaction_test.gd"

func _run() -> void:
	_capture_player_state()
	assert(GameData.ensure_loaded())
	_root = "user://shared_warehouse_transaction_isolated_v80_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = _root.path_join("characters")
	PlayerState.profile_index_path = _root.path_join("index.json")
	PlayerState.shared_warehouse_path = _root.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = _root.path_join("shared.transaction.json")
	_profile = PlayerState.profile_directory.path_join("p.json")
	_other_profile = PlayerState.profile_directory.path_join("q.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.test_mode = true
	_write_index()
	assert(PlayerState._write_json_atomic(_other_profile,{"profile_id":"q","inventory":[]}))
	_reset_documents("seed")
	var water := GameData.get_item_record(910001)
	var full: Array = []
	for i in 100: full.append({"name":"回城卷","count":1})
	full[0] = {"name":water.name,"item_id":910001,"count":3}
	PlayerState.inventory = full.duplicate(true)
	PlayerState.warehouse_inventory = full.duplicate(true)
	assert(PlayerState._write_json_atomic(_profile,{"profile_id":"p","profession":"战士","level":60,"inventory":PlayerState.inventory}))
	assert(PlayerState._write_json_atomic(PlayerState.shared_warehouse_path,_shared_document(PlayerState.warehouse_inventory)))
	PlayerState.load_save()
	assert(PlayerState.last_load_result.success)
	assert(PlayerState.inventory[0].count == 3 and PlayerState.warehouse_inventory[0].count == 3)
	# A real two-file deposit frees a bag slot; the old stack splits in the same commit.
	var deposited: Dictionary = await PlayerState.transfer_warehouse_prepared("deposit",[1],[100])
	assert(deposited.success,str(deposited))
	assert(PlayerState.inventory[0].count == 2 and PlayerState.inventory[1].count == 1)
	assert(PlayerState.warehouse_inventory[0].count == 3)
	PlayerState.load_save()
	assert(PlayerState.last_load_result.success and PlayerState.inventory[1].count == 1)
	# Free a warehouse slot while preserving all quantities and page boundaries.
	PlayerState.inventory[99] = {}
	assert(PlayerState.save_game(false))
	var withdrawn: Dictionary = await PlayerState.transfer_warehouse_prepared("withdraw",[1])
	assert(withdrawn.success,str(withdrawn))
	assert(PlayerState.warehouse_inventory[0].count == 2 and PlayerState.warehouse_inventory[1].count == 1)
	assert(PlayerState._read_json(PlayerState.shared_warehouse_path).warehouse_inventory[1].count == 1)
	assert(not FileAccess.file_exists(PlayerState.shared_warehouse_transaction_log_path))
	_cleanup_isolated_files()
	_restore_player_state()
	print("LEGACY_STACK_STORAGE_PASS: full old stacks retained, split on real two-file deposit/withdraw and reload")
	get_tree().quit(0)
