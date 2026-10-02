extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const ARCHIVE := "user://save_upgrades/framework_identity_v1"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://default_root_archived_expected.json")) if FileAccess.file_exists("user://default_root_archived_expected.json") else null
	check(expected is Dictionary,"cold process receives the successful archive migration expectation")
	if not expected is Dictionary: _finish(); return
	check(not PlayerState.test_mode and PlayerState.profile_directory == "user://characters","cold global owner uses actual default persistence paths")
	check(expected.source_content_sha256 == OS.get_environment("HARDCORE_R3_CONTENT_SHA256") and expected.producer_run_id != OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"independent cold receipt binds the exact same source")
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade() and PlayerState.startup_save_upgrade_result.get("reason") == "already_completed","real cold startup validates completed default-root archive")
	check(FileAccess.get_sha256(ARCHIVE.path_join("manifest.json")) == expected.manifest_sha256 and FileAccess.get_sha256(ARCHIVE.path_join("completed.json")) == expected.completed_sha256,"cold startup preserves immutable backup/completion metadata")
	for relative: String in expected.originals:
		check(FileAccess.get_sha256(ARCHIVE.path_join("original").path_join(relative)) == expected.originals[relative],"cold original archived bytes "+relative)
	for id: String in expected.profiles:
		check(PlayerState.select_character(id),"independent process selects historical role "+id)
		check(PlayerState.level == int(expected.profiles[id].level) and PlayerState.gold == int(expected.profiles[id].gold) and PlayerState.experience == int(expected.profiles[id].experience),"cold historical economy and progression "+id)
	var warehouse: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PlayerState.shared_warehouse_path))
	check(warehouse.bank_gold == expected.bank_gold,"cold shared bank balance preserved")
	check(PlayerState._json_persistence.pending_count() == 0 and PlayerState._world_json_persistence.pending_count() == 0,"cold startup and role loads leave no writer receipt")
	PlayerState.active_profile_id = ""
	_finish()
func _finish() -> void:
	if not proof.write_receipt("default_root_upgrade_archived_cold_test",checks,failures.size()): failures.append("receipt")
	print("DEFAULT_ROOT_UPGRADE_ARCHIVED_COLD_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
