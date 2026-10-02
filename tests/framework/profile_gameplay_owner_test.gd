extends Node

const State := preload("res://scripts/player_state.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var account := "user://profile_gameplay_owner_%d" % Time.get_ticks_usec()
	var state := State.new()
	state.profile_directory = account.path_join("characters")
	state.profile_index_path = account.path_join("character_profiles.json")
	state.shared_warehouse_path = account.path_join("shared_warehouse.json")
	state.shared_warehouse_transaction_log_path = account.path_join("shared_warehouse.transaction.json")
	add_child(state)
	check(not state.test_mode, "actual profile writers used")
	check(state.create_character("角色所有者A", "hc.profession.wizard").is_empty(), "A creation has no gameplay owner")
	var profile_a: String = state.active_profile_id
	check(state.create_character("角色所有者B", "hc.profession.warrior").is_empty(), "B creation has no gameplay owner")
	var profile_b: String = state.active_profile_id
	check(state.select_character(profile_a), "character selection works before world attachment")
	var before_index := FileAccess.get_sha256(state.profile_index_path)
	var before_a := FileAccess.get_sha256(state._profile_path(profile_a))
	var before_b := FileAccess.get_sha256(state._profile_path(profile_b))
	var owner := Node.new()
	add_child(owner)
	state.register_profile_gameplay_owner(owner)
	state.register_profile_gameplay_owner(owner)
	check(not state.select_character(profile_b), "running world rejects replacing current role")
	check(state.last_load_result.get("reason") == "profile_gameplay_owner_active", "rejection has specific load reason")
	check(not state.select_character(profile_a), "same-role reload cannot reset active world state")
	check(not state.create_character("禁止切入C", "hc.profession.taoist").is_empty(), "new character cannot bypass the active world owner")
	var deletion: Dictionary = state.delete_character_profile(profile_a)
	check(not bool(deletion.success) and deletion.reason == "profile_gameplay_owner_active", "active role cannot be deleted under live world")
	deletion = state.delete_character_profile(profile_b)
	check(not bool(deletion.success), "character management remains outside live gameplay")
	check(state.active_profile_id == profile_a, "all rejected operations preserve active identity")
	check(FileAccess.get_sha256(state.profile_index_path) == before_index and FileAccess.get_sha256(state._profile_path(profile_a)) == before_a and FileAccess.get_sha256(state._profile_path(profile_b)) == before_b, "rejected operations preserve both profiles and index byte for byte")
	owner.queue_free()
	check(not state.select_character(profile_b), "queued world deletion still owns deferred callbacks")
	await get_tree().process_frame
	check(state.select_character(profile_b), "freed weak owner cannot permanently block character selection")
	var first := Node.new()
	var second := Node.new()
	add_child(first)
	add_child(second)
	state.register_profile_gameplay_owner(first)
	state.register_profile_gameplay_owner(second)
	state.unregister_profile_gameplay_owner(first)
	check(not state.select_character(profile_a), "one world cannot release another live owner's protection")
	state.unregister_profile_gameplay_owner(second)
	check(state.select_character(profile_a), "explicit lifecycle retirement releases the exact remaining owner")
	first.free()
	second.free()
	check(state.create_character("合法选角C", "hc.profession.taoist").is_empty(), "new character creation remains legal after retirement")
	var profile_c: String = state.active_profile_id
	deletion = state.delete_character_profile(profile_b)
	check(bool(deletion.success) and state.active_profile_id == profile_c, "ordinary inactive role deletion remains legal after retirement")
	check(state._json_persistence.pending_count() == 0 and state._world_json_persistence.pending_count() == 0, "real character and world receipts drained")
	state.active_profile_id = ""
	state.queue_free()
	await get_tree().process_frame
	if not proof.write_receipt("profile_gameplay_owner_test", checks, failures.size()): failures.append("receipt")
	print("PROFILE_GAMEPLAY_OWNER_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
