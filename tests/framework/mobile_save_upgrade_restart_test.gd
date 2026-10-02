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
	var input: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://mobile_upgrade_restart_case.json"))
	check(input is Dictionary and str(input.get("root", "")).begins_with("user://mobile_upgrade_two_profiles_"), "cold process receives previous actual-upgrade fixture")
	if input is Dictionary:
		var state := State.new()
		state.profile_directory = input.root.path_join("characters")
		state.profile_index_path = input.root.path_join("character_profiles.json")
		state.shared_warehouse_path = input.root.path_join("shared_warehouse.json")
		state.shared_warehouse_transaction_log_path = input.root.path_join("shared_warehouse.transaction.json")
		var before: Dictionary = {}
		for id: String in input.profiles:
			var path: String = state.profile_directory.path_join(id + ".json")
			before[id] = FileAccess.get_sha256(path)
		state.begin_startup_save_upgrade()
		add_child(state)
		check(not state.test_mode and state.finish_startup_save_upgrade(), "cold native process verifies completion and reopens real persistence")
		check(state.startup_save_upgrade_result.get("reason") == "already_completed", "cold restart does not repeat conversion")
		check(FileAccess.get_sha256(input.root.path_join("save_upgrades/framework_identity_v1/manifest.json")) == input.manifest_sha256, "cold restart keeps immutable source manifest")
		for id: String in input.profiles:
			check(FileAccess.get_sha256(state.profile_directory.path_join(id + ".json")) == before[id], "cold upgrade changes no completed profile bytes " + id)
			check(state.select_character(id), "cold process loads actual profile " + id)
			check(state.gold == 456789 and state.experience == 1234, "cold progress and economy unchanged " + id)
			check(state.equipment.get("hc.slot.weapon", {}).get("weapon_luck") == 3, "cold gear roll retained " + id)
		check(state._json_persistence.pending_count() == 0 and state._world_json_persistence.pending_count() == 0, "cold load persistence receipts drained")
		state.active_profile_id = ""
		state.queue_free()
	if not proof.write_receipt("mobile_save_upgrade_restart_test", checks, failures.size()): failures.append("receipt")
	print("FRAMEWORK_MOBILE_SAVE_UPGRADE_RESTART_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
