extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const REGISTRY := "res://assets/data/features/validation/creation_rollback_registry.json"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func owned_files(root: String) -> Dictionary:
	var result := {}
	for name: String in DirAccess.get_files_at(root):
		result[root.path_join(name)] = FileAccess.get_file_as_bytes(root.path_join(name))
	for name: String in DirAccess.get_directories_at(root):
		result.merge(owned_files(root.path_join(name)))
	return result

func _run() -> void:
	var owned_root := "user://feature_creation_invalid_" + OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID").replace("-", "")
	PlayerState.profile_directory = owned_root + "/profiles"
	PlayerState.profile_index_path = owned_root + "/index.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.test_mode = false
	check(not PlayerState._test_force_atomic_write_failure, "normal I/O has no save failure injection")
	check(PlayerState.create_character("ValidWizardA", "法师", "女").is_empty(), "formal creation writes isolated wizard A")
	check(int(PlayerState.computed_stats.max_mp) == 18, "level one wizard independently has MP eighteen")
	check(ContentLayers.reload_feature_catalog(REGISTRY), "trusted registry registers existing negative MP probe")
	check(ContentLayers.set_feature_module_enabled("hc.creation_rollback_probe", true), "minus sixteen is valid for wizard A")
	check(int(PlayerState.computed_stats.max_mp) == 2, "valid wizard feature result is MP two")
	check(PlayerState.save_game(), "formal writer persists A before new transaction")
	var id: String = PlayerState.active_profile_id
	var equipment := PlayerState.equipment.duplicate(true)
	var stats := PlayerState.computed_stats.duplicate(true)
	var base := PlayerState.base_stats.duplicate(true)
	var inputs := PlayerState._feature_base_stats.duplicate(true)
	var bundle := PlayerState.feature_bundle()
	var loadout: RefCounted = PlayerState._feature_loadout
	var count: int = loadout.compile_count
	var errors: Array = PlayerState.feature_errors.duplicate()
	var disk := owned_files(owned_root)
	var error: String = PlayerState.create_character("InvalidWarriorB", "战士", "男")
	print("INVALID_CREATION_OBSERVATION " + JSON.stringify({"error":error, "active_profile":PlayerState.active_profile_id, "base_mp":PlayerState._feature_base_stats.get("max_mp"), "computed_mp":PlayerState.computed_stats.get("max_mp"), "feature_errors":PlayerState.feature_errors, "save_reason":PlayerState.last_save_result.get("reason")}))
	check(not error.is_empty(), "invalid warrior candidate rejects before normal save")
	check(PlayerState.last_save_result.get("success") == false and PlayerState.last_save_result.get("reason") == "character_stats_rejected", "caller reports explicit candidate validation failure")
	check(PlayerState.active_profile_id == id and PlayerState.character_name == "ValidWizardA" and PlayerState.profession == "法师", "rejection restores original profile and profession")
	check(PlayerState.equipment == equipment and PlayerState.computed_stats == stats and PlayerState.base_stats == base, "rejection restores original equipment and both primary stat snapshots")
	check(PlayerState._feature_base_stats == inputs, "rejection restores coherent pre-feature input")
	check(is_same(PlayerState._feature_loadout, loadout) and is_same(PlayerState.feature_bundle(), bundle) and loadout.compile_count == count and PlayerState.feature_errors == errors, "rejection restores effective bundle identity compile generation and errors")
	check(owned_files(owned_root) == disk, "normal I/O invalid candidate changes no owned file and creates no profile or sidecar")
	check(PlayerState.list_characters().size() == 1, "index still contains exactly A")
	check(ContentLayers.set_feature_module_enabled("hc.creation_rollback_probe", false), "remove probe through ordinary publication")
	check(ContentLayers.reload_feature_catalog(), "baseline registry restores")
	if not proof.write_receipt("feature_creation_invalid_candidate_test", checks, failures.size()): failures.append("receipt")
	print("FEATURE_CREATION_INVALID_CANDIDATE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
