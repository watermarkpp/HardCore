extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const ARCHIVE := "user://save_upgrades/framework_identity_v1"
const EXPECTED := "user://default_root_archived_expected.json"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	check(not PlayerState.test_mode and PlayerState.profile_directory == "user://characters","actual global owner keeps isolated stock user root")
	var seed: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://default_root_upgrade_seed_fingerprint.json"))
	check(seed is Dictionary and seed.get("archive_sha256") == "18989f8b6d0f672b653cb0237ebeb33913f46885a508b716fe8c2b1ae5ffd7de","prelaunch copy is bound to the known archived device source")
	if not seed is Dictionary: _finish(); return
	check(seed.files.size() == 13 and not FileAccess.file_exists(ARCHIVE.path_join("manifest.json")),"all thirteen archived files predate the first upgrade")
	var profiles := {}
	for relative: String in seed.files:
		check(FileAccess.get_sha256("user://"+relative) == seed.files[relative],"autoload preserves exact prelaunch archive bytes "+relative)
		if relative.begins_with("characters/") and relative.ends_with(".json"):
			var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://"+relative))
			profiles[original.profile_id] = {"level":original.level,"gold":original.gold,"experience":original.experience}
	check(profiles.size() == 3,"actual archive contains all three prior characters")
	var warehouse_before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PlayerState.shared_warehouse_path))
	if not failures.is_empty(): _finish(); return
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade(),"nonempty default root completes real migration "+str(PlayerState.startup_save_upgrade_result))
	if not bool(PlayerState.startup_save_upgrade_result.get("success",false)): _finish(); return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ARCHIVE.path_join("manifest.json")))
	check(manifest.files.size() == 13,"default-root archive contains every original and no injected marker")
	for relative: String in seed.files:
		check(manifest.files.get(relative,{}).get("sha256") == seed.files[relative],"manifest owns exact historical relative path "+relative)
		check(FileAccess.get_sha256(ARCHIVE.path_join("original").path_join(relative)) == seed.files[relative],"original device bytes preserved under default source prefix "+relative)
	var warehouse_after: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PlayerState.shared_warehouse_path))
	for field: String in ["bank_gold","bank_transaction_high_water","bank_transactions","revision","legacy_migration"]:
		check(warehouse_after.get(field) == warehouse_before.get(field),"real bank/warehouse ownership field preserved "+field)
	for id: String in profiles:
		check(PlayerState.select_character(id),"canonical service loads migrated archive role "+id)
		check(PlayerState.level == int(profiles[id].level) and PlayerState.gold == int(profiles[id].gold) and PlayerState.experience == int(profiles[id].experience),"historical economy and progression preserved "+id)
	check(PlayerState._json_persistence.pending_count() == 0 and PlayerState._world_json_persistence.pending_count() == 0,"migration and official role loads consume all writer receipts")
	var expected := {"originals":seed.files,"profiles":profiles,"bank_gold":warehouse_before.bank_gold,
		"manifest_sha256":FileAccess.get_sha256(ARCHIVE.path_join("manifest.json")),"completed_sha256":FileAccess.get_sha256(ARCHIVE.path_join("completed.json")),
		"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),"producer_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID")}
	if failures.is_empty():
		var file := FileAccess.open(EXPECTED,FileAccess.WRITE)
		check(file != null,"write cold expectation only after successful live migration")
		if file != null: file.store_string(JSON.stringify(expected)); file.close()
	PlayerState.active_profile_id = ""
	_finish()
func _finish() -> void:
	if not proof.write_receipt("default_root_upgrade_archived_test",checks,failures.size()): failures.append("receipt")
	print("DEFAULT_ROOT_UPGRADE_ARCHIVED_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
