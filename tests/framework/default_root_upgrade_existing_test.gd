extends Node
const State := preload("res://scripts/player_state.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const PROFILE := "user://characters/default_root_A.json"
const INDEX := "user://character_profiles.json"
const ARCHIVE := "user://save_upgrades/framework_identity_v1"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)
func put(path: String, value: Variant) -> void:
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) == OK,"owned default fixture parent")
	var file := FileAccess.open(path,FileAccess.WRITE)
	check(file != null,"owned default fixture file")
	if file != null: file.store_string(JSON.stringify(value,"\t")+"\n"); file.close()
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	check(not PlayerState.test_mode and PlayerState.profile_directory == "user://characters","prelaunch-isolated default production paths, test_mode=false")
	check(not FileAccess.file_exists(ARCHIVE.path_join("manifest.json")) and FileAccess.file_exists(PROFILE) and FileAccess.file_exists("user://default_root_upgrade_seed_fingerprint.json"),"old default files predate native startup and have no previous upgrade archive")
	if not failures.is_empty(): _finish(); return
	var seed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://default_root_upgrade_seed_fingerprint.json"))
	var originals: Dictionary = seed.files
	check(seed.fixture_sha256 == FileAccess.get_sha256("res://tests/framework/fixtures/default_root_upgrade_seed.json"),"prelaunch existing files bind the tracked seed fixture")
	check(FileAccess.get_sha256(PROFILE) == originals["characters/default_root_A.json"] and FileAccess.get_sha256(INDEX) == originals["character_profiles.json"],"autoload leaves both prelaunch original file hashes intact")
	var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE))
	check(before.save_version == 7 and before.profession == "战士","real old profile is still unconverted at upgrade entry")
	if not failures.is_empty(): _finish(); return
	var state := State.new()
	check(state.profile_directory == "user://characters" and state.profile_index_path == INDEX,"new real owner keeps stock default root")
	state.begin_startup_save_upgrade(); add_child(state)
	check(not state.test_mode and not state.select_character("default_root_A"),"real write/admission gate precedes conversion")
	state._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(FileAccess.get_sha256(PROFILE) == originals["characters/default_root_A.json"] and FileAccess.get_sha256(INDEX) == originals["character_profiles.json"],"blocked background save preserves upgrade-before bytes")
	check(state.finish_startup_save_upgrade(),"nonempty default root upgrades through real owner "+str(state.startup_save_upgrade_result))
	if not bool(state.startup_save_upgrade_result.get("success",false)): state.queue_free(); _finish(); return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ARCHIVE.path_join("manifest.json")))
	for relative: String in originals:
		check(manifest.files.has(relative),"exact archive-relative identity "+relative)
		check(manifest.files.get(relative,{}).get("sha256") == originals[relative],"manifest binds before-image "+relative)
		check(FileAccess.get_sha256(ARCHIVE.path_join("original").path_join(relative)) == originals[relative],"default source_prefix copies original bytes "+relative)
	var converted: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE))
	check(converted.get("save_version") == 10 and converted.get("character_identity",{}).get("profession_id") == "hc.profession.warrior","actual default legacy profile converted by canonical owner")
	check(converted.gold == 456789 and converted.experience == 1234,"conversion retains economy and progression")
	check(FileAccess.file_exists(ARCHIVE.path_join("completed.json")),"real default completion receipt durable")
	check(state.select_character("default_root_A") and state.gold == 456789 and state.experience == 1234,"default upgraded profile loads through actual service")
	check(state._json_persistence.pending_count() == 0 and state._world_json_persistence.pending_count() == 0,"actual profile/world receipts ended")
	var expected := {"profile":"default_root_A","originals":originals,
		"profile_sha256":FileAccess.get_sha256(PROFILE),"index_sha256":FileAccess.get_sha256(INDEX),
		"manifest_sha256":FileAccess.get_sha256(ARCHIVE.path_join("manifest.json")),
		"completed_sha256":FileAccess.get_sha256(ARCHIVE.path_join("completed.json")),
		"producer_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
		"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256")}
	if failures.is_empty(): put("user://default_root_upgrade_expected.json",expected)
	print("DEFAULT_ROOT_UPGRADE_EXISTING_TRACE "+JSON.stringify({"originals":originals,"result":state.startup_save_upgrade_result,"expected":expected}))
	state.active_profile_id = ""; state.queue_free(); await get_tree().process_frame
	_finish()
func _finish() -> void:
	if not proof.write_receipt("default_root_upgrade_existing_test",checks,failures.size()): failures.append("receipt")
	print("DEFAULT_ROOT_UPGRADE_EXISTING_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
