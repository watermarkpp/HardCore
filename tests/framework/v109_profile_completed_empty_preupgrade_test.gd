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
	check(file != null, "fixture file opened")
	if file != null:
		file.store_string(JSON.stringify(document, "\t") + "\n")
		file.close()

func legacy() -> Dictionary:
	return {"save_version": 7, "character_name": "完成证明旧档", "profession": "战士", "gender": "男",
		"level": 25, "experience": 1234, "gold": 456789, "inventory": [], "equipment": {},
		"learned_skills": {"基本剑术": 2}, "quick_slots": ["", "", "", ""], "quest_states": {},
		"warehouse_inventory": []}

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

func put_empty_index(root: String) -> void:
	put(root.path_join("character_profiles.json"), {"version": 1, "profiles": []})

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# A prior build completed migration, the user deleted the final profile, and
	# the old index has no marker. The durable completion proof must win over the
	# retained legacy source without making a fresh import impossible.
	var completed_root := "user://v109_profile_completed_empty_%d" % Time.get_ticks_usec()
	var legacy_path := completed_root.path_join("player_save_v02.json")
	put(legacy_path, legacy())
	var first := create_state(completed_root)
	check(first.finish_startup_save_upgrade(), "seed migration completes")
	check(first.delete_character_profile("legacy_01").success, "seed profile is deleted")
	var old_index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(first.profile_index_path))
	old_index.erase("legacy_migration_consumed")
	put(first.profile_index_path, old_index)
	var legacy_hash := FileAccess.get_sha256(legacy_path)
	first.queue_free()
	await get_tree().process_frame
	var restarted := create_state(completed_root)
	check(restarted.finish_startup_save_upgrade(), "completed empty account starts successfully")
	check(restarted.list_characters().is_empty(), "completed empty account is not resurrected")
	check(not FileAccess.file_exists(restarted.profile_directory.path_join("legacy_01.json")), "completed proof blocks legacy profile publication")
	check(FileAccess.get_sha256(legacy_path) == legacy_hash, "completed empty account preserves legacy source")
	restarted.queue_free()
	await get_tree().process_frame

	# No completion proof is the first-import boundary: an explicit empty index
	# still imports a valid legacy source exactly once.
	var first_import_root := "user://v109_profile_completed_missing_%d" % Time.get_ticks_usec()
	var first_import_legacy := first_import_root.path_join("player_save_v02.json")
	put(first_import_legacy, legacy())
	put_empty_index(first_import_root)
	var first_import := create_state(first_import_root)
	check(first_import.finish_startup_save_upgrade(), "missing proof performs first import")
	check(first_import.list_characters().size() == 1 and first_import.list_characters()[0].id == "legacy_01", "missing proof publishes legacy profile")
	first_import.queue_free()
	await get_tree().process_frame

	# A malformed completion proof is fail-closed and must not be treated as the
	# durable completed-empty case.
	var invalid_root := "user://v109_profile_completed_invalid_%d" % Time.get_ticks_usec()
	var invalid_legacy := invalid_root.path_join("player_save_v02.json")
	put(invalid_legacy, legacy())
	var invalid_seed := create_state(invalid_root)
	check(invalid_seed.finish_startup_save_upgrade(), "invalid boundary seed completes")
	check(invalid_seed.delete_character_profile("legacy_01").success, "invalid boundary seed deletes profile")
	var invalid_index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(invalid_seed.profile_index_path))
	invalid_index.erase("legacy_migration_consumed")
	put(invalid_seed.profile_index_path, invalid_index)
	var completion_path := invalid_root.path_join("save_upgrades/framework_identity_v1/completed.json")
	put(completion_path, {"contract_id": "broken", "schema_version": 1})
	invalid_seed.queue_free()
	await get_tree().process_frame
	var invalid_restart := create_state(invalid_root)
	check(not invalid_restart.finish_startup_save_upgrade(), "invalid proof fails closed")
	check(invalid_restart.list_characters().is_empty(), "invalid proof does not import before rejection")
	invalid_restart.queue_free()
	await get_tree().process_frame

	if not proof.write_receipt("v109_profile_completed_empty_preupgrade_test", checks, failures.size()): failures.append("receipt")
	print("V109_PROFILE_COMPLETED_EMPTY_PREUPGRADE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
