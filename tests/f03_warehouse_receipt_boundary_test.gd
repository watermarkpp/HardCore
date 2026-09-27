extends Node

class FixtureState extends "res://scripts/player_state.gd":
	func _ready() -> void:
		# Isolated paths are supplied by the fixture. Keep the older completion
		# pending until the public transaction consumes it; prepared transfers
		# still await this real SceneTree and use the actual worker and files.
		set_process(false)
var failures: Array[String] = []
var observations: Array[Dictionary] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true # Unused autoload only; each fixture uses real IO.
	assert(GameData.ensure_loaded())
	for prepared: bool in [false, true]:
		for operation: String in ["deposit", "withdraw"]:
			await _case(operation, prepared)
	_expect(observations.size() == 4, "all four public transaction cases must complete")
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/test_logs")) == OK)
	FileAccess.open("res://outputs/test_logs/f03_warehouse_receipt_boundary.json", FileAccess.WRITE).store_string(JSON.stringify({"observations": observations, "failures": failures}, "  "))
	for failure: String in failures:
		printerr("F03_WAREHOUSE_RECEIPT_BOUNDARY_FAIL ", failure)
	print("F03_WAREHOUSE_RECEIPT_BOUNDARY_PASS" if failures.is_empty() else "F03_WAREHOUSE_RECEIPT_BOUNDARY_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)

func _case(operation: String, prepared: bool) -> void:
	var label := "%s_%s" % [operation, "prepared" if prepared else "direct"]
	var state := FixtureState.new()
	var root := "user://f03_warehouse_receipt_%d_%d_%s" % [OS.get_process_id(), Time.get_ticks_usec(), label]
	state.profile_directory = root.path_join("characters")
	state.profile_index_path = root.path_join("profiles.json")
	state.shared_warehouse_path = root.path_join("shared.json")
	state.shared_warehouse_transaction_log_path = root.path_join("shared.transaction.json")
	state.active_profile_id = "owner"
	state.test_mode = false
	add_child(state)
	state.reset_progress(false)
	state.level = 50
	state.recalculate_stats(false)
	var item := ItemDropInstanceRules.create_instance(GameData.get_item_record({"item_id": 81}), "f03-warehouse-" + label)
	assert(not item.is_empty() and not str(item.get("instance_id", "")).is_empty())
	state.inventory = [item] if operation == "deposit" else []
	state.warehouse_inventory = [item] if operation == "withdraw" else []
	state._shared_warehouse_initialized = true
	var shared := {"schema_version": state.SHARED_WAREHOUSE_SCHEMA_VERSION,
		"contract_id": state.SHARED_WAREHOUSE_CONTRACT_ID, "revision": 1,
		"warehouse_inventory": state.warehouse_inventory.duplicate(true),
		"legacy_migration": {"completed": true, "contract_id": state.SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID, "sources": {}}}
	assert(state._write_json_atomic(state.shared_warehouse_path, shared))
	assert(state.save_game(false), str(state.last_save_result))
	var profile_path: String = state._profile_path("owner")
	var plan: Dictionary = state.prepare_loot_save([{"gold": true, "amount": 17}])
	assert(plan.has("writer") and plan.writer.result(true).success)
	# Real worker promotion is durable, but the main coordinator has not yet
	# consumed the completion. No observation filtering or synthetic receipt.
	state.finish_prepared_loot_save(plan)
	assert(plan.writer.job.stage_result(true).result.success)
	state.finish_prepared_loot_save(plan)
	assert(plan.writer.job.stage_result(true).result.success)
	assert(not plan.writer.job.response.finished and state.gold == 0)
	assert(int(_read(profile_path).gold) == 17)
	var result: Dictionary
	if prepared:
		result = await state.transfer_warehouse_prepared(operation, [0], [0] if operation == "deposit" else [])
	elif operation == "deposit":
		result = state.deposit_to_warehouse(0, 0)
	else:
		result = state.withdraw_from_warehouse(0)
	state._json_persistence.drain()
	var receipt: Dictionary = state.finish_prepared_loot_save(plan)
	var disk_profile := _read(profile_path)
	var disk_shared := _read(state.shared_warehouse_path)
	var inventory_ids := _ids(state.inventory)
	var warehouse_ids := _ids(state.warehouse_inventory)
	var id := str(item.instance_id)
	_expect(bool(result.get("success", false)), label + ": public transfer rejected the older approved receipt")
	_expect(bool(receipt.get("success", false)) and state.gold == 17 and int(disk_profile.gold) == 17, label + ": older gold receipt lost or duplicated")
	_expect(inventory_ids == ([] if operation == "deposit" else [id]), label + ": live inventory differs from the transfer")
	_expect(warehouse_ids == ([id] if operation == "deposit" else []), label + ": live warehouse differs from the transfer")
	_expect(_ids(disk_profile.inventory) == inventory_ids and _ids(disk_shared.warehouse_inventory) == warehouse_ids, label + ": live and durable item ownership differ")
	_expect(inventory_ids.count(id) + warehouse_ids.count(id) == 1, label + ": unique item duplicated or lost")
	observations.append({"label": label, "result": result, "receipt": receipt,
		"inventory_ids": inventory_ids, "warehouse_ids": warehouse_ids,
		"disk_inventory_ids": _ids(disk_profile.inventory), "disk_warehouse_ids": _ids(disk_shared.warehouse_inventory),
		"gold": state.gold, "disk_gold": disk_profile.gold})
	state.free()

func _read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary)
	return parsed

func _ids(records: Array) -> Array[String]:
	var result: Array[String] = []
	for record: Variant in records:
		if record is Dictionary and not record.is_empty():
			result.append(str(record.get("instance_id", "")))
	return result

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
