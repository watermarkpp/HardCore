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

func put(path: String, document: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "real legacy fixture opened")
	if file != null:
		file.store_string(JSON.stringify(document, "\t") + "\n")
		file.close()

func create_state(root: String) -> State:
	var state := State.new()
	state.test_mode = false
	state.profile_directory = root.path_join("characters")
	state.profile_index_path = root.path_join("character_profiles.json")
	state.shared_warehouse_path = root.path_join("shared_warehouse.json")
	state.shared_warehouse_transaction_log_path = root.path_join("shared_warehouse.transaction.json")
	state.begin_startup_save_upgrade()
	add_child(state)
	return state

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var root := "user://v109_profile_legacy_empty_%d" % Time.get_ticks_usec()
	var legacy_path := root.path_join("player_save_v02.json")
	var legacy := {"save_version": 7, "character_name": "合法旧档角色", "profession": "战士", "gender": "男",
		"level": 25, "experience": 1234, "gold": 456789, "inventory": [], "equipment": {},
		"learned_skills": {"基本剑术": 2}, "quick_slots": ["", "", "", ""], "quest_states": {},
		"warehouse_inventory": []}
	put(legacy_path, legacy)
	var legacy_hash := FileAccess.get_sha256(legacy_path)
	var first := create_state(root)
	var first_ok := first.finish_startup_save_upgrade()
	print("FIRST_STARTUP ", first_ok, " ", first.startup_save_upgrade_result)
	check(first_ok, "first real startup imports valid legacy profile")
	check(first.list_characters().size() == 1 and first.list_characters()[0].id == "legacy_01", "first import publishes legacy_01")
	var first_index: Variant = JSON.parse_string(FileAccess.get_file_as_string(first.profile_index_path))
	check(first_index is Dictionary and bool((first_index as Dictionary).get("legacy_migration_consumed", false)), "migration decision is durable in authoritative index")
	check(first.select_character("legacy_01") and first.save_game(true, true, true), "normal profile save succeeds before final deletion")
	var after_save_index: Variant = JSON.parse_string(FileAccess.get_file_as_string(first.profile_index_path))
	check(after_save_index is Dictionary and bool((after_save_index as Dictionary).get("legacy_migration_consumed", false)), "normal index update preserves migration marker")
	var deleted := first.delete_character_profile("legacy_01")
	check(bool(deleted.get("success", false)) and first.list_characters().is_empty(), "formal delete removes final imported character")
	check(FileAccess.get_sha256(legacy_path) == legacy_hash, "legacy source remains byte-identical for backup custody")
	var empty_index: Variant = JSON.parse_string(FileAccess.get_file_as_string(first.profile_index_path))
	check(empty_index is Dictionary and (empty_index as Dictionary).get("profiles", []).is_empty() and bool((empty_index as Dictionary).get("legacy_migration_consumed", false)), "empty account keeps consumed marker after delete")
	first.queue_free()
	await get_tree().process_frame
	var second := create_state(root)
	var second_ok := second.finish_startup_save_upgrade()
	print("SECOND_STARTUP ", second_ok, " ", second.startup_save_upgrade_result)
	check(second_ok, "second real startup accepts intentionally empty migrated account")
	check(second.list_characters().is_empty(), "restart does not resurrect deleted legacy_01")
	check(not FileAccess.file_exists(second.profile_directory.path_join("legacy_01.json")), "restart creates no deleted profile file")
	check(FileAccess.get_sha256(legacy_path) == legacy_hash, "restart preserves original legacy source")
	second.queue_free()
	await get_tree().process_frame

	# Compatibility boundary: an older build may have completed migration before
	# the marker existed. A populated legacy_01 index must be sealed before the
	# user deletes its final character.
	var old_root := "user://v109_profile_legacy_existing_%d" % Time.get_ticks_usec()
	var old_legacy_path := old_root.path_join("player_save_v02.json")
	put(old_legacy_path, legacy)
	var old_first := create_state(old_root)
	check(old_first.finish_startup_save_upgrade(), "compatibility fixture imports legacy profile")
	var old_index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(old_first.profile_index_path))
	old_index.erase("legacy_migration_consumed")
	put(old_first.profile_index_path, old_index)
	old_first.queue_free()
	await get_tree().process_frame
	var old_restart := create_state(old_root)
	check(old_restart.finish_startup_save_upgrade(), "older completed migration reopens")
	var sealed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(old_restart.profile_index_path))
	check(bool(sealed.get("legacy_migration_consumed", false)), "older populated legacy index is sealed")
	var merged := old_restart._merge_background_profile_index(sealed, {
		"profile_id": "legacy_01",
		"entry": (sealed["profiles"] as Array)[0].duplicate(true),
	})
	check(bool(merged.get("legacy_migration_consumed", false)), "background index merge retains account marker")
	# Model a missing compatibility backfill. The delete transaction itself
	# must preserve the original index on failure and seal it on success.
	sealed.erase("legacy_migration_consumed")
	put(old_restart.profile_index_path, sealed)
	var index_before := FileAccess.get_file_as_bytes(old_restart.profile_index_path)
	var old_profile_path := old_restart._profile_path("legacy_01")
	var profile_before := FileAccess.get_file_as_bytes(old_profile_path)
	old_restart.test_mode = true
	old_restart._test_force_atomic_write_failure = true
	var failed_delete := old_restart.delete_character_profile("legacy_01")
	check(not bool(failed_delete.get("success", false)) and str(failed_delete.get("reason", "")) == "profile_index_write_failed", "failed final delete rejects at atomic index barrier")
	check(FileAccess.get_file_as_bytes(old_restart.profile_index_path) == index_before and FileAccess.get_file_as_bytes(old_profile_path) == profile_before, "failed final delete preserves index and character bytes")
	old_restart._test_force_atomic_write_failure = false
	old_restart.test_mode = false
	var old_deleted := old_restart.delete_character_profile("legacy_01")
	check(bool(old_deleted.get("success", false)) and old_restart.list_characters().is_empty(), "compatibility fixture deletes final profile")
	old_restart.queue_free()
	await get_tree().process_frame
	var old_final := create_state(old_root)
	check(old_final.finish_startup_save_upgrade(), "compatibility empty account reopens")
	check(old_final.list_characters().is_empty(), "older migrated account does not resurrect after final delete")
	old_final.queue_free()
	await get_tree().process_frame
	if not proof.write_receipt("v109_profile_legacy_empty_account_test", checks, failures.size()): failures.append("receipt")
	print("V109_PROFILE_LEGACY_EMPTY_ACCOUNT_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
