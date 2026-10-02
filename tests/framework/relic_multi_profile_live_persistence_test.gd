extends Node

const State := preload("res://scripts/player_state.gd")
const Rules := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var state: Node
var trace: Array = []
var expected: Dictionary = {}

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _record(operation: String, result: Dictionary) -> void:
	var path: String = state._profile_path(state.active_profile_id)
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	trace.append({"operation":operation, "profile_id":state.active_profile_id,
		"world_generation":state._world_clock_generation, "equipment_revision":state.equipment_transaction_revision,
		"item_revision":state._item_save_revision, "saved_revision":state._item_saved_revision,
		"result":result, "save_result":state.last_save_result.duplicate(true),
		"validator":state._validate_profile_document_status(disk, state.active_profile_id, false) if disk is Dictionary else {"valid":false,"reason":"invalid_json"},
		"instance_ids":_instances(), "profile_sha256":FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""})

func _instances() -> Array[String]:
	var ids: Array[String] = []
	var records: Array = state.inventory.duplicate(true)
	records.append_array(state.equipment.values())
	records.append_array(state.synthesis_tray)
	for record: Variant in records:
		if record is Dictionary and not str(record.get("instance_id", "")).is_empty(): ids.append(record.instance_id)
	return ids

func _index(entity_id: String) -> int:
	for index in state.inventory.size():
		if state.inventory[index] is Dictionary and GameData.item_entity_id(state.inventory[index]) == entity_id:
			return index
	return -1

func _empty_slot() -> int:
	for index in state.INVENTORY_CAPACITY:
		if index >= state.inventory.size() or state.inventory[index].is_empty(): return index
	return -1

func _persist(operation: String) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline and (state._json_persistence.pending_count() > 0 or state._world_json_persistence.pending_count() > 0 or state._item_save_revision > state._item_saved_revision):
		await get_tree().process_frame
	check(state._json_persistence.pending_count() == 0 and state._world_json_persistence.pending_count() == 0, "real receipt queues drained " + operation)
	check(state._item_save_revision == state._item_saved_revision and not state._item_save_failed, "accepted item revision has durable receipt " + operation)
	check(bool(state.last_save_result.get("success", false)), "actual save success " + operation + " " + str(state.last_save_result))
	_record(operation + ":durable", {})
	check(bool(trace[-1].validator.valid), "saved business validator " + operation + " " + str(trace[-1].validator))

func _craft(item_id: int) -> Dictionary:
	var slots: Array[int] = [2,4,6,8]
	for slot in slots:
		var index := _index("hc.item.950001")
		check(index >= 0, "registered fragment present")
		if index < 0: return {}
		var placed: Dictionary = await state.transfer_workbench_immediate("synthesis", slot, index)
		check(bool(placed.get("success", false)), "production fragment transfer " + str(placed))
		_record("material:" + str(slot), placed)
	var quote: Dictionary = state.quote_relic_synthesis(item_id, slots)
	check(bool(quote.get("valid", false)), "real synthesis quote " + str(quote))
	if not bool(quote.get("valid", false)): return {}
	var committed: Dictionary = await state.commit_workbench_immediate("synthesis", quote)
	check(bool(committed.get("committed", false)), "production synthesis accepted " + str(committed))
	_record("synthesize:" + str(item_id), committed)
	await _persist("synthesize:" + str(item_id))
	if not bool(committed.get("committed", false)): return {}
	var output: Dictionary = state.synthesis_tray[0].duplicate(true)
	check(Rules.valid_instance(output, item_id), "actual produced relic/badge identity")
	var claimed: Dictionary = await state.transfer_workbench_immediate("synthesis", 0)
	check(bool(claimed.get("success", false)), "production claim into backpack " + str(claimed))
	_record("claim:" + str(item_id), claimed)
	await _persist("claim:" + str(item_id))
	var index := _index("hc.item." + str(item_id))
	check(index >= 0 and state.inventory[index].get("instance_id") == output.get("instance_id"), "claim retains exact synthesis instance")
	return output

func _equip_and_return(entity_id: String, slot: String) -> void:
	var index := _index(entity_id)
	check(index >= 0, "equip input present " + entity_id)
	if index < 0: return
	var instance_id: String = state.inventory[index].instance_id
	var previous_revision: int = state.equipment_transaction_revision
	var result: Dictionary = state.equip_inventory_index_result(index, slot, instance_id)
	check(bool(result.get("success", false)) and int(result.get("revision", 0)) == previous_revision + 1, "real equip publishes new revision " + entity_id + " " + str(result))
	_record("equip:" + entity_id, result)
	await _persist("equip:" + entity_id)
	if not bool(result.get("success", false)): return
	var returned: Dictionary = state.unequip_to_inventory_slot(slot, _empty_slot(), instance_id)
	check(bool(returned.get("success", false)), "real unequip " + entity_id + " " + str(returned))
	_record("unequip:" + entity_id, returned)
	await _persist("unequip:" + entity_id)

func _destroy(entity_id: String) -> String:
	var index := _index(entity_id)
	check(index >= 0, "destroy input present " + entity_id)
	if index < 0: return ""
	var instance_id: String = str(state.inventory[index].get("instance_id", ""))
	var result: Dictionary = state.destroy_inventory_indices([index])
	check(bool(result.get("success", false)) and int(result.get("destroyed", 0)) == 1, "real destruction " + entity_id + " " + str(result))
	_record("destroy:" + entity_id, result)
	await _persist("destroy:" + entity_id)
	check(instance_id.is_empty() or not _instances().has(instance_id), "destroyed instance no longer owned")
	return instance_id

func _profile(label: String) -> void:
	var created: String = state.create_character("持久化验证" + label)
	check(created.is_empty(), "production create/switch " + label + " " + created)
	if not created.is_empty(): return
	var id: String = state.active_profile_id
	state.level = 35
	state.gold = 2500000
	state.recalculate_stats()
	for input: Dictionary in [{"entity_id":"hc.item.950001", "count":16}, {"entity_id":"hc.item.000081", "count":1}, {"entity_id":"hc.item.920017", "count":2}]:
		var received: Dictionary = state.receive(str(input.entity_id), int(input.count), false)
		check(bool(received.get("success", false)), "registered fixture item intake " + str(received))
	check(state.save_game(true, true, true), "fixture uses real profile/world/index writers " + str(state.last_save_result))
	var deleted: Array[String] = []
	await _craft(950101)
	await _craft(950201)
	# Both outputs remain in the backpack while unrelated items are exercised.
	await _equip_and_return("hc.item.000081", "hc.slot.weapon")
	await _destroy("hc.item.920017")
	for pair: Array in [[950101,"hc.slot.relic"],[950201,"hc.slot.badge"]]:
		await _equip_and_return("hc.item." + str(pair[0]), pair[1])
		deleted.append(await _destroy("hc.item." + str(pair[0])))
	var retained := {}
	for pair: Array in [[950101,"hc.slot.relic"],[950201,"hc.slot.badge"]]:
		var output: Dictionary = await _craft(int(pair[0]))
		retained[pair[1]] = output
		var index := _index("hc.item." + str(pair[0]))
		var result: Dictionary = state.equip_inventory_index_result(index, pair[1], str(output.get("instance_id", "")))
		check(bool(result.get("success", false)), "keep exact crafted equipment " + str(result))
		_record("keep_equipped:" + str(pair[0]), result)
		await _persist("keep_equipped:" + str(pair[0]))
	check(state.gold == 900000, "four actual synthesis costs applied once " + label)
	check(state.save_game(true, true, true), "final production checkpoint " + label)
	await _persist("final:" + label)
	expected[label] = {"profile_id":id, "gold":state.gold, "retained":retained, "deleted":deleted,
		"equipment_revision":state.equipment_transaction_revision, "generation":state._world_clock_generation}

func _run() -> void:
	var root := "user://relic_multi_profile_live_%d" % Time.get_ticks_usec()
	state = State.new()
	state.profile_directory = root.path_join("characters")
	state.profile_index_path = root.path_join("character_profiles.json")
	state.shared_warehouse_path = root.path_join("shared_warehouse.json")
	state.shared_warehouse_transaction_log_path = root.path_join("shared_warehouse.transaction.json")
	add_child(state)
	check(not state.test_mode, "A/B use actual production persistence, test_mode=false")
	await _profile("A")
	await _profile("B")
	check(expected.size() == 2 and expected.A.profile_id != expected.B.profile_id, "two actual separate profiles")
	for label: String in expected:
		check(state.select_character(expected[label].profile_id), "production directed reload " + label + " " + str(state.last_load_result))
		for slot: String in expected[label].retained:
			check(state.equipment[slot].get("instance_id") == expected[label].retained[slot].get("instance_id"), "live reload keeps role-specific instance " + label + "/" + slot)
	var pointer := {"root":root, "profiles":expected}
	var file := FileAccess.open("user://relic_multi_profile_live_restart_case.json", FileAccess.WRITE)
	check(file != null, "cold-process fixture pointer")
	if file != null: file.store_string(JSON.stringify(pointer)); file.close()
	file = FileAccess.open(root.path_join("production_trace.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(trace, "\t")); file.close()
	print("RELIC_MULTI_PROFILE_PRODUCTION_TRACE " + JSON.stringify(trace))
	state.active_profile_id = ""
	state.queue_free()
	if not proof.write_receipt("relic_multi_profile_live_persistence_test", checks, failures.size()): failures.append("receipt")
	print("FRAMEWORK_RELIC_MULTI_PROFILE_LIVE_PERSISTENCE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
