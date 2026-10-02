extends Node
const State := preload("res://scripts/player_state.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const PROFILE := "user://characters/default_root_A.json"
const INDEX := "user://character_profiles.json"
const ARCHIVE := "user://save_upgrades/framework_identity_v1"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var exists := FileAccess.file_exists("user://default_root_upgrade_expected.json") and FileAccess.file_exists("res://outputs/test_logs/framework/default_root_upgrade_existing_test.result.json")
	check(exists,"independent process receives real default upgrade expectation and receipt")
	if not exists: _finish(); return
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://default_root_upgrade_expected.json"))
	var producer: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://outputs/test_logs/framework/default_root_upgrade_existing_test.result.json"))
	check(producer.get("status") == "PASS" and producer.get("run_id") == expected.producer_run_id and expected.source_content_sha256 == OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),"cold expectation binds successful producer and exact source")
	if not failures.is_empty(): _finish(); return
	var state := State.new()
	check(not state.test_mode and state.profile_directory == "user://characters","cold owner retains default production authority")
	state.begin_startup_save_upgrade(); add_child(state)
	check(state.finish_startup_save_upgrade() and state.startup_save_upgrade_result.get("reason") == "already_completed","cold default startup verifies completed archive without reconversion")
	check(FileAccess.get_sha256(PROFILE) == expected.profile_sha256 and FileAccess.get_sha256(INDEX) == expected.index_sha256,"cold gate preserves completed primary bytes")
	for relative: String in expected.originals:
		check(FileAccess.get_sha256(ARCHIVE.path_join("original").path_join(relative)) == expected.originals[relative],"cold original before-image hash "+relative)
	check(FileAccess.get_sha256(ARCHIVE.path_join("manifest.json")) == expected.manifest_sha256 and FileAccess.get_sha256(ARCHIVE.path_join("completed.json")) == expected.completed_sha256,"cold immutable manifest and completion receipt")
	check(state.select_character(expected.profile) and state.gold == 456789 and state.experience == 1234,"independent process loads preserved default progress")
	var primary_hash := FileAccess.get_sha256(PROFILE)
	var index_hash := FileAccess.get_sha256(INDEX)
	var warehouse_hash := FileAccess.get_sha256(state.shared_warehouse_path)
	var archived := ARCHIVE.path_join("original/characters/default_root_A.json")
	var file := FileAccess.open(archived,FileAccess.WRITE)
	check(file != null,"owned synthetic archive fault is exact and writable")
	if file == null: state.active_profile_id = ""; state.queue_free(); _finish(); return
	file.store_string("synthetic owned before-image damage"); file.close()
	state.begin_startup_save_upgrade()
	check(not state.finish_startup_save_upgrade() and state.startup_save_upgrade_result.get("reason") == "upgrade_backup_hash_mismatch","damaged default archive closes actual admission despite completion marker")
	check(not state.select_character(expected.profile),"damaged before-image cannot admit profile or recover an old primary")
	check(FileAccess.get_sha256(PROFILE) == primary_hash and FileAccess.get_sha256(INDEX) == index_hash and FileAccess.get_sha256(state.shared_warehouse_path) == warehouse_hash,"failed default backup verification changes no account primary bytes")
	check(FileAccess.get_sha256(ARCHIVE.path_join("manifest.json")) == expected.manifest_sha256 and FileAccess.get_sha256(ARCHIVE.path_join("completed.json")) == expected.completed_sha256,"failed gate does not replace original manifest or completion receipt")
	check(state._json_persistence.pending_count() == 0 and state._world_json_persistence.pending_count() == 0,"cold verification and failure leave no accepted writer receipt")
	print("DEFAULT_ROOT_UPGRADE_EXISTING_COLD_TRACE "+JSON.stringify({"originals":expected.originals,"failure":state.startup_save_upgrade_result,"profile_sha256":FileAccess.get_sha256(PROFILE)}))
	state.active_profile_id = ""; state.queue_free(); await get_tree().process_frame
	_finish()
func _finish() -> void:
	if not proof.write_receipt("default_root_upgrade_existing_cold_test",checks,failures.size()): failures.append("receipt")
	print("DEFAULT_ROOT_UPGRADE_EXISTING_COLD_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
