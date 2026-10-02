extends Node

const State := preload("res://scripts/player_state.gd")
const Rules := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var trace: Array = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _index(state: Node, entity_id: String) -> int:
	for index in state.inventory.size():
		if state.inventory[index] is Dictionary and GameData.item_entity_id(state.inventory[index]) == entity_id: return index
	return -1

func _run() -> void:
	var pointer: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://relic_multi_profile_live_restart_case.json"))
	check(pointer is Dictionary and str(pointer.get("root", "")).begins_with("user://relic_multi_profile_live_"), "new native process loads precise isolated production fixture")
	if pointer is Dictionary:
		var state := State.new()
		state.profile_directory = pointer.root.path_join("characters")
		state.profile_index_path = pointer.root.path_join("character_profiles.json")
		state.shared_warehouse_path = pointer.root.path_join("shared_warehouse.json")
		state.shared_warehouse_transaction_log_path = pointer.root.path_join("shared_warehouse.transaction.json")
		add_child(state)
		check(not state.test_mode, "cold process uses actual production save/load")
		for label: String in pointer.profiles:
			var expected: Dictionary = pointer.profiles[label]
			check(state.select_character(expected.profile_id), "cold directed select " + label + " " + str(state.last_load_result))
			check(state.gold == int(expected.gold), "cold synthesis costs and role gold retained " + label)
			for slot: String in expected.retained:
				var item: Dictionary = state.equipment[slot]
				check(item.get("instance_id") == expected.retained[slot].get("instance_id") and item.get("relic_roll") == expected.retained[slot].get("relic_roll"), "cold exact role-specific relic/badge roll and identity " + label + "/" + slot)
				check(Rules.valid_instance(item, int(item.get("item_id", -1))), "cold relic/badge still business-valid " + label + "/" + slot)
			var records: Array = state.inventory.duplicate(true)
			records.append_array(state.equipment.values())
			for dead_id: String in expected.deleted:
				var found := false
				for record: Variant in records:
					if record is Dictionary and record.get("instance_id") == dead_id: found = true
				check(not dead_id.is_empty() and not found, "cold crafted deletion did not resurrect " + label)
			var index := _index(state, "hc.item.000081")
			check(index >= 0, "cold unrelated weapon remains in backpack " + label)
			if index >= 0:
				var result: Dictionary = state.equip_inventory_index_result(index, "hc.slot.weapon", str(state.inventory[index].get("instance_id", "")))
				check(bool(result.get("success", false)), "cold entire backpack still equipable " + label + " " + str(result))
				trace.append({"profile_id":state.active_profile_id,"operation":"cold_equip","result":result,"save_result":state.last_save_result.duplicate(true),"equipment_revision":state.equipment_transaction_revision})
			var starter_index := _index(state, "hc.item.000080")
			check(starter_index >= 0, "cold unrelated starter available for destruction")
			if starter_index >= 0:
				var result: Dictionary = state.destroy_inventory_indices([starter_index])
				check(bool(result.get("success", false)), "cold entire backpack still destroyable " + label + " " + str(result))
				trace.append({"profile_id":state.active_profile_id,"operation":"cold_destroy","result":result,"save_result":state.last_save_result.duplicate(true),"item_revision":state._item_save_revision,"saved_revision":state._item_saved_revision})
			check(state.save_game(true, true, true), "cold mutation actual durable checkpoint " + label)
			var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state._profile_path(state.active_profile_id)))
			var validation: Dictionary = state._validate_profile_document_status(disk, state.active_profile_id, false)
			check(bool(validation.valid), "cold disk business validator " + label + " " + str(validation))
			trace.append({"profile_id":state.active_profile_id,"operation":"cold_final","validator":validation,"save_result":state.last_save_result.duplicate(true),"generation":state._world_clock_generation})
			check(state._json_persistence.pending_count() == 0 and state._world_json_persistence.pending_count() == 0 and state._item_save_revision == state._item_saved_revision, "cold resource and persistence receipt queues drained " + label)
		state.active_profile_id = ""
		state.queue_free()
	print("RELIC_MULTI_PROFILE_COLD_TRACE " + JSON.stringify(trace))
	if not proof.write_receipt("relic_multi_profile_cold_persistence_test", checks, failures.size()): failures.append("receipt")
	print("FRAMEWORK_RELIC_MULTI_PROFILE_COLD_PERSISTENCE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
