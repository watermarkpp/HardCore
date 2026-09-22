extends "res://tests/repair_20260913/warehouse_prepared_transaction_test.gd"

func _run() -> void:
	_capture_player_state()
	assert(GameData.ensure_loaded())
	_root = "user://shared_warehouse_transaction_isolated_bank_latency_%d" % Time.get_ticks_usec()
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
	assert(PlayerState._write_json_atomic(_other_profile,{"profile_id":"q","inventory":[]}))
	_reset_documents("bank")
	PlayerState.inventory = []
	PlayerState.warehouse_inventory = []
	var item := GameData.get_item_rules_record({"item_id":159})
	for i in range(500):
		var instance := ItemDropInstanceRules.create_instance(item,"bank-latency-%d" % i)
		assert(not instance.is_empty())
		if i < 100: PlayerState.inventory.append(instance)
		else: PlayerState.warehouse_inventory.append(instance)
	PlayerState.gold = 300000
	assert(PlayerState._write_json_atomic(_profile,{"profile_id":"p","inventory":PlayerState.inventory.duplicate(true),"gold":300000}))
	assert(PlayerState._write_json_atomic(PlayerState.shared_warehouse_path,_shared_document(PlayerState.warehouse_inventory)))
	# Same 500 actual v3 instances and storage backend for before/after timing.
	for seq in [1,2]:
		var begin := Time.get_ticks_usec()
		var sync := PlayerState.transfer_shared_gold(seq==1,"baseline-%d" % seq,seq)
		assert(sync.success)
		_measurements.append({"operation":"synchronous_bank","wall_ms":(Time.get_ticks_usec()-begin)/1000.0})
	set_process(true)
	await _launch_bank(true,"prepared-3",3)
	assert(PlayerState.gold==200000 and PlayerState.shared_gold_balance()==100000)
	await _launch_bank(false,"prepared-4",4)
	assert(PlayerState.gold==300000 and PlayerState.shared_gold_balance()==0)
	assert(not (await PlayerState.transfer_shared_gold_prepared(true,"prepared-3",3)).success)
	for fail in ["journal","shared","profile"]:
		PlayerState._test_force_atomic_write_failure = fail=="journal"
		PlayerState._test_fail_shared_write = fail=="shared"
		PlayerState._test_fail_profile_write = fail=="profile"
		await _launch_bank(true,"failed-5",5,false)
		PlayerState._test_force_atomic_write_failure = false
		PlayerState._test_fail_shared_write = false
		PlayerState._test_fail_profile_write = false
		assert(PlayerState.gold==300000 and PlayerState.shared_gold_balance()==0)
	# An overlapping inventory request cannot mutate the prepared bank snapshot.
	_completion = false
	_run_bank(true,"overlap-5",5)
	var overlap: Dictionary = await PlayerState.transfer_warehouse_prepared("deposit",[0],[400])
	assert(not overlap.success)
	PlayerState.gold += 1
	while not _completion: await get_tree().process_frame
	assert(not _result.success and PlayerState.shared_gold_balance()==0)
	PlayerState.gold = 300000
	# Persisted bank WAL remains recoverable with the original bank validator.
	PlayerState._test_fail_profile_write = true
	PlayerState._test_fail_warehouse_rollback_write = true
	await _launch_bank(true,"recover-5",5,false)
	assert(PlayerState._warehouse_transaction_locked)
	var journal: Dictionary = PlayerState._read_json_document(PlayerState.shared_warehouse_transaction_log_path).data
	assert(journal.operation_kind=="bank" and PlayerState._warehouse_transaction_log_is_valid(journal))
	PlayerState._test_fail_profile_write = false
	PlayerState._test_fail_warehouse_rollback_write = false
	PlayerState._recover_shared_warehouse_transaction()
	assert(not PlayerState._warehouse_transaction_locked)
	assert(PlayerState.shared_gold_balance()==0 and int(PlayerState._read_json(_profile).gold)==300000)
	# UI destruction does not cancel an already-owned PlayerState transaction.
	var panel := WarehousePanel.new()
	panel.hide()
	add_child(panel)
	panel.open_panel()
	# Production HUD prewarms all grid/layout construction before gameplay.
	for frame in range(8): await get_tree().process_frame
	_completion = false
	_gaps.clear()
	_last_frame_usec = Time.get_ticks_usec()
	var stale_view: Dictionary = panel._bank_view_snapshot.duplicate()
	var view_reads := panel._ui_l1_bank_read_count
	var ui_begin := Time.get_ticks_usec()
	panel._on_bank_transfer_pressed(true)
	var ui_submit_ms := (Time.get_ticks_usec()-ui_begin)/1000.0
	assert(panel._ui_l1_bank_read_count == view_reads, "Submitting the displayed request must not reread the warehouse on the input frame")
	while PlayerState._warehouse_preparation_pending or panel._bank_transfer_pending: await get_tree().process_frame
	_completion = true
	_gaps.append((Time.get_ticks_usec()-_last_frame_usec)/1000.0)
	_gaps.sort()
	_measurements.append({"operation":"actual_bank_button","synchronous_submit_ms":ui_submit_ms,"wall_ms":(Time.get_ticks_usec()-ui_begin)/1000.0,"frames":_gaps.size(),"max_gap_ms":_gaps.back()})
	assert(PlayerState.gold==200000 and PlayerState.shared_gold_balance()==100000)
	assert(panel._ui_l1_bank_read_count == view_reads + 1, "Completion refreshes the bank view once")
	# An outdated displayed snapshot never authorizes money movement or an
	# automatic replay with a freshly allocated sequence.
	panel._bank_view_snapshot = stale_view
	panel._on_bank_transfer_pressed(true)
	while PlayerState._warehouse_preparation_pending or panel._bank_transfer_pending: await get_tree().process_frame
	assert(not panel._last_bank_transfer_result.success and panel._last_bank_transfer_result.reason=="duplicate_transaction")
	assert(PlayerState.gold==200000 and PlayerState.shared_gold_balance()==100000)
	assert(int(panel._bank_view_snapshot.next_sequence)==6)
	panel._submit_bank_transfer(false,"ui-6",6)
	assert(PlayerState._warehouse_preparation_pending)
	panel.queue_free()
	while PlayerState._warehouse_preparation_pending: await get_tree().process_frame
	assert(PlayerState.gold==300000 and PlayerState.shared_gold_balance()==0)
	assert(PlayerState.inventory.size()==100 and PlayerState.warehouse_inventory.size()==400)
	var output := FileAccess.open("res://outputs/test_logs/bank_prepared_latency.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"rows":_measurements},"\t"))
	output.close()
	_cleanup_isolated_files()
	_restore_player_state()
	print("BANK_PREPARED_TRANSACTION_PASS ",JSON.stringify(_measurements))
	get_tree().quit()

func _run_bank(deposit: bool, id: String, seq: int) -> void:
	_result = await PlayerState.transfer_shared_gold_prepared(deposit,id,seq)
	_completion = true

func _launch_bank(deposit: bool, id: String, seq: int, expected := true) -> void:
	_completion = false
	_gaps.clear()
	_last_frame_usec = Time.get_ticks_usec()
	var begin := Time.get_ticks_usec()
	_run_bank(deposit,id,seq)
	var synchronous_submit_ms := (Time.get_ticks_usec()-begin)/1000.0
	while not _completion: await get_tree().process_frame
	_gaps.append((Time.get_ticks_usec()-_last_frame_usec)/1000.0)
	assert(bool(_result.success)==expected,str(_result))
	_gaps.sort()
	_measurements.append({"operation":"prepared_bank","expected_success":expected,"synchronous_submit_ms":synchronous_submit_ms,"wall_ms":(Time.get_ticks_usec()-begin)/1000.0,"frames":_gaps.size(),"max_gap_ms":_gaps.back()})
