extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const REGISTRY := "res://assets/data/features/validation/creation_rollback_registry.json"
const OWNED_ROOT := "user://feature_creation_rollback"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var notifications := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _observe() -> void:
	notifications += 1

func _run() -> void:
	var owned_root := OWNED_ROOT + "_" + OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID").replace("-", "")
	PlayerState.profile_directory = owned_root + "/profiles"
	PlayerState.profile_index_path = owned_root + "/index.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.test_mode = false
	check(PlayerState.create_character("RollbackA", "战士", "男").is_empty(), "real production creates isolated warrior A")
	check(int(PlayerState.computed_stats.max_mp) == 15, "level one warrior has independently expected MP 15")
	check(ContentLayers.reload_feature_catalog(REGISTRY), "register rollback probe through trusted production loader")
	check(ContentLayers.set_feature_module_enabled("hc.publication_probe", true), "valid feature is active before creation transaction")
	var profile_id: String = PlayerState.active_profile_id
	var profile_path: String = PlayerState.profile_directory.path_join(profile_id + ".json")
	var profile_bytes := FileAccess.get_file_as_bytes(profile_path)
	var index_bytes := FileAccess.get_file_as_bytes(PlayerState.profile_index_path)
	var stats := PlayerState.computed_stats.duplicate(true)
	var base_stats := PlayerState._feature_base_stats.duplicate(true)
	var bundle := PlayerState.feature_bundle()
	var loadout: RefCounted = PlayerState._feature_loadout
	var compile_count: int = loadout.compile_count
	var feature_errors: Array = PlayerState.feature_errors.duplicate()
	PlayerState.test_mode = true
	PlayerState._test_force_atomic_write_failure = true
	var error: String = PlayerState.create_character("RollbackB", "法师", "女")
	PlayerState._test_force_atomic_write_failure = false
	PlayerState.test_mode = false
	check(error == "角色存档失败，角色未创建" and PlayerState.last_save_result.reason == "atomic_character_creation_failed", "existing owned save failure triggers official creation rollback")
	check(PlayerState.active_profile_id == profile_id and PlayerState.character_name == "RollbackA" and PlayerState.computed_stats == stats, "rollback restores active A and computed stats")
	check(FileAccess.get_file_as_bytes(profile_path) == profile_bytes and FileAccess.get_file_as_bytes(PlayerState.profile_index_path) == index_bytes and PlayerState.list_characters().size() == 1, "failed B leaves A and index bytes intact without orphan character")
	check(PlayerState._feature_base_stats == base_stats, "rollback restores feature input from A instead of failed B")
	check(is_same(PlayerState._feature_loadout, loadout) and is_same(PlayerState.feature_bundle(), bundle) and loadout.compile_count == compile_count and PlayerState.feature_errors == feature_errors, "rollback restores original effective bundle and compile generation")
	ContentLayers.feature_catalog_changed.connect(_observe)
	var enabled: bool = ContentLayers.set_feature_module_enabled("hc.creation_rollback_probe", true)
	check(not enabled, "MP minus sixteen cannot enable on restored warrior MP fifteen")
	check(notifications == 0 and PlayerState.computed_stats == stats and is_same(PlayerState.feature_bundle(), bundle) and PlayerState._feature_loadout.compile_count == compile_count and PlayerState.feature_errors == feature_errors, "rejected post-rollback candidate keeps coherent publication and emits no notification")
	ContentLayers.feature_catalog_changed.disconnect(_observe)
	print("CREATION_ROLLBACK_OBSERVATION profile=" + profile_id + " base_mp=" + str(PlayerState._feature_base_stats.get("max_mp")) + " enabled=" + str(enabled) + " save_reason=" + str(PlayerState.last_save_result.get("reason")))
	check(ContentLayers.reload_feature_catalog(), "baseline catalog remains restorable")
	if not proof.write_receipt("feature_creation_rollback_test", checks, failures.size()): failures.append("receipt")
	print("FEATURE_CREATION_ROLLBACK_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
