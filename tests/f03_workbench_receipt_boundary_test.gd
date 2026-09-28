extends Node

class FixtureState extends "res://scripts/player_state.gd":
	func _ready() -> void:
		set_process(false)

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	for operation: String in ["place", "take"]:
		await _case(operation)
	await _live_case()
	await _live_commit_case()
	for failure: String in failures:
		printerr("F03_WORKBENCH_RECEIPT_BOUNDARY_FAIL ", failure)
	print("F03_WORKBENCH_RECEIPT_BOUNDARY_PASS" if failures.is_empty() else "F03_WORKBENCH_RECEIPT_BOUNDARY_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)


func _case(operation: String) -> void:
	var state := FixtureState.new()
	var root := "user://f03_workbench_%d_%d_%s" % [
		OS.get_process_id(), Time.get_ticks_usec(), operation,
	]
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
	var item := ItemDropInstanceRules.create_instance(
		GameData.get_item_record({"item_id": 81}), "f03-workbench-" + operation
	)
	assert(not item.is_empty() and not str(item.get("instance_id", "")).is_empty())
	state.inventory = [item] if operation == "place" else []
	state.forge_tray = state._empty_workbench_tray()
	state._shared_warehouse_initialized = true
	if operation == "take":
		state.forge_tray[0] = item
	var shared := {
		"schema_version": state.SHARED_WAREHOUSE_SCHEMA_VERSION,
		"contract_id": state.SHARED_WAREHOUSE_CONTRACT_ID,
		"revision": 1,
		"warehouse_inventory": [],
		"legacy_migration": {"completed": true, "contract_id": state.SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID, "sources": {}},
	}
	assert(state._write_json_atomic(state.shared_warehouse_path, shared))
	assert(state.save_game(false), str(state.last_save_result))
	var profile_path: String = state._profile_path("owner")
	var plan: Dictionary = state.prepare_loot_save([{"gold": true, "amount": 17}])
	assert(plan.has("writer") and plan.writer.result(true).success)
	# Drive the real coordinator exactly to PROMOTING, then wait for its real
	# worker. The file is durable while the main-thread receipt remains unread.
	state._json_persistence.authorize(plan.writer.job)
	for _step: int in range(5):
		if str(state._json_persistence._queue[0].phase) == "PROMOTING":
			break
		assert(state._json_persistence.pump(true))
	assert(str(state._json_persistence._queue[0].phase) == "PROMOTING")
	assert(bool(plan.writer.job.stage_result(true).result.success))
	assert(not plan.writer.job.response.finished and state.gold == 0)
	assert(int(_read(profile_path).gold) == 17)
	var result: Dictionary = (
		state.place_workbench_item("forge", 0, 0)
		if operation == "place" else state.take_workbench_item("forge", 0)
	)
	state._json_persistence.drain()
	var receipt: Dictionary = state.finish_prepared_loot_save(plan)
	var disk: Dictionary = _read(profile_path)
	var item_id: String = str(item.instance_id)
	var live_inventory := _ids(state.inventory)
	var live_tray := _ids(state.forge_tray)
	var disk_inventory := _ids(disk.inventory)
	var disk_tray := _ids(disk.forge_tray)
	_expect(bool(result.get("success", false)), operation + ": workbench operation rejected")
	_expect(bool(receipt.get("success", false)), operation + ": older receipt was not consumed")
	_expect(state.gold == 17 and int(disk.gold) == 17, operation + ": older gold receipt was lost")
	_expect(live_inventory == disk_inventory and live_tray == disk_tray, operation + ": live and durable ownership differ")
	_expect(live_inventory.count(item_id) + live_tray.count(item_id) == 1, operation + ": unique item lost or duplicated")
	_expect(live_tray == ([item_id] if operation == "place" else []), operation + ": wrong tray outcome")
	state.free()


func _read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary)
	return parsed


func _live_case() -> void:
	var state := FixtureState.new()
	var root := "user://live_workbench_%d" % Time.get_ticks_usec()
	state.profile_directory = root.path_join("characters")
	state.profile_index_path = root.path_join("profiles.json")
	state.active_profile_id = "owner"
	add_child(state)
	state.reset_progress(false)
	state.level = 50
	state.recalculate_stats(false)
	var item := ItemDropInstanceRules.create_instance(GameData.get_item_record({"item_id": 81}), "live-tray-item")
	state.inventory = [item]
	assert(state.save_game(false))
	var path: String = state._profile_path("owner")
	var initial_bytes := FileAccess.get_file_as_bytes(path)
	var start := Time.get_ticks_usec()
	for _i in 20:
		assert((await state.transfer_workbench_immediate("forge", 4, 0)).success)
		assert(_ids(state.forge_tray) == [str(item.instance_id)])
		assert((await state.transfer_workbench_immediate("forge", 4)).success)
		assert(_ids(state.inventory) == [str(item.instance_id)])
	assert(FileAccess.get_file_as_bytes(path) == initial_bytes,
		"live tray transfer still waits for file IO")
	print("LIVE_WORKBENCH_40_MOVES_MS ", float(Time.get_ticks_usec() - start) / 1000.0)
	assert((await state.transfer_workbench_immediate("forge", 4, 0)).success)
	state._process(0.0)
	# Move again while the OLD profile snapshot is already writing.
	assert((await state.transfer_workbench_immediate("forge", 4)).success)
	state._before_state_transaction()
	assert(_ids(_read(path).inventory) == [str(item.instance_id)])
	assert(_ids(_read(path).forge_tray).is_empty())
	var plan: Dictionary = state.prepare_loot_save([{"gold": true, "amount": 17}])
	assert(plan.writer.result(true).success)
	state._json_persistence.authorize(plan.writer.job)
	while str(state._json_persistence._queue[0].phase) != "PROMOTING":
		assert(state._json_persistence.pump(true))
	assert(plan.writer.job.stage_result(true).result.success)
	assert((await state.transfer_workbench_immediate("forge", 4, 0)).success)
	assert(plan.completed and plan.completion.success and state.gold == 17)
	state.free()
	assert(_ids(_read(path).forge_tray) == [str(item.instance_id)] and _ids(_read(path).inventory).is_empty())
	assert(int(_read(path).gold) == 17)


func _ids(records: Array) -> Array[String]:
	var result: Array[String] = []
	for record: Variant in records:
		if record is Dictionary and not record.is_empty():
			result.append(str(record.get("instance_id", "")))
	return result


func _live_commit_case() -> void:
	var state := FixtureState.new()
	var root := "user://live_workbench_commit_%d" % Time.get_ticks_usec()
	state.profile_directory = root.path_join("characters")
	state.profile_index_path = root.path_join("profiles.json")
	state.active_profile_id = "owner"
	add_child(state)
	state.reset_progress(false)
	state.gold = 1000000
	for entry: Array in [[4, 81], [1, 940010], [3, 191], [5, 192]]:
		var item := GameData.get_item_record({"item_id": int(entry[1])})
		state.forge_tray[int(entry[0])] = state._make_item_instance(str(item.name), item, -1, false)
		state.forge_tray[int(entry[0])]["item_id"] = int(entry[1])
	for slot in [2, 4, 6, 8]:
		# Fragment ID is owned by the existing synthesis contract.
		var item := GameData.get_item_record({"item_id": preload("res://scripts/layers/rules/relic_synthesis_rules.gd").FRAGMENT_ID})
		state.synthesis_tray[slot] = state._make_item_instance(str(item.name), item, -1, false)
		state.synthesis_tray[slot]["item_id"] = int(item.itemId)
	assert(state.save_game(false))
	var path: String = state._profile_path("owner")
	var before := FileAccess.get_file_as_bytes(path)
	var forge: Dictionary = state.quote_forge_tray()
	assert(forge.valid, str(forge))
	assert((await state.call("commit_workbench_immediate", "forge", forge)).committed)
	assert(not (await state.call("commit_workbench_immediate", "forge", forge)).committed, "same quote committed twice")
	assert(state.gold == 900000 and state.forge_tray[1].is_empty() and not state.forge_tray[4].is_empty())
	var synthesis: Dictionary = state.quote_relic_synthesis(950101, [2, 4, 6, 8])
	assert(synthesis.valid)
	assert((await state.call("commit_workbench_immediate", "synthesis", synthesis)).committed)
	assert(state.gold == 500000 and int(state.synthesis_tray[0].item_id) == 950101)
	assert(FileAccess.get_file_as_bytes(path) == before, "workbench commit still waits for file IO")
	state.free()
	assert(int(_read(path).gold) == 500000 and int(_read(path).synthesis_tray[0].item_id) == 950101)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
