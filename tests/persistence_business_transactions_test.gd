extends Node

const DomainRuntimeServicesScript := preload(
	"res://scripts/layers/runtime/domain_runtime_services.gd"
)
const EquipmentRulesScript := preload("res://scripts/equipment_rules.gd")

const ROOT_PREFIX := "user://persistence_business_transactions_isolated"

var _root := ""
var _profile_path := ""
var _saved: Dictionary = {}
var _inventory_signal_count := 0
var _equipment_signal_count := 0
var _quick_item_signal_count := 0
var _quick_skill_signal_count := 0
var _skills_signal_count := 0
var _profile_signal_count := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_capture_state()
	_configure_isolated_state()
	_test_blessing_oil_success_persists_one_complete_state()
	_test_persistence_failures_restore_runtime_and_files()
	_restore_state()
	_cleanup_files()
	print("PERSISTENCE_BUSINESS_TRANSACTIONS_PASS")
	get_tree().quit(0)


func _test_blessing_oil_success_persists_one_complete_state() -> void:
	_set_blessing_fixture(2, 0)
	assert(PlayerState.save_game(false), str(PlayerState.last_save_result))
	var invalid_probe_rng := RandomNumberGenerator.new()
	var invalid_expected_rng := RandomNumberGenerator.new()
	invalid_probe_rng.seed = 176
	invalid_expected_rng.seed = 176
	var invalid_result := PlayerState.use_blessing_oil_inventory_index(
		PlayerState.inventory.size(),
		invalid_probe_rng
	)
	assert(not bool(invalid_result.get("ok", false)))
	assert(
		invalid_probe_rng.randi() == invalid_expected_rng.randi(),
		"无效祝福油入口不应提前消耗 RNG"
	)
	var expected_rng := RandomNumberGenerator.new()
	var actual_rng := RandomNumberGenerator.new()
	expected_rng.seed = 176
	actual_rng.seed = 176
	var expected_unlucky := expected_rng.randi_range(
		0,
		EquipmentRulesScript.BLESSING_UNLUCKY_RATE - 1
	)
	var expected_success := 0
	if expected_unlucky != 1:
		var item := GameData.get_item("命运之刃")
		var denominator := EquipmentRulesScript.blessing_success_denominator(
			0,
			int(item.get("attackMin", 0)),
			int(item.get("attackMax", 0))
		)
		expected_success = (
			expected_rng.randi_range(0, denominator - 1)
			if denominator > 1
			else 0
		)
	var expected_outcome := EquipmentRulesScript.blessing_outcome(
		0,
		0,
		int(GameData.get_item("命运之刃").get("attackMin", 0)),
		int(GameData.get_item("命运之刃").get("attackMax", 0)),
		expected_unlucky,
		expected_success
	)
	PlayerState.configure_blessing_oil_rng(actual_rng)
	var message := PlayerState.use_inventory_index(0)
	assert(message.begins_with("使用：祝福油"), message)
	assert(actual_rng.randi() == expected_rng.randi(), "祝福油改变了既有 RNG 抽样顺序")
	assert(PlayerState.item_count("祝福油") == 1)
	assert(
		int(PlayerState.equipment["武器"].get("weapon_luck", -1))
		== int(expected_outcome.get("luck", -1))
	)
	var stored := PlayerState._read_json(_profile_path)
	assert(int((stored.get("inventory", []) as Array)[0].get("count", -1)) == 1)
	assert(
		int(stored.get("equipment", {}).get("武器", {}).get("weapon_luck", -1))
		== int(expected_outcome.get("luck", -1))
	)


func _test_persistence_failures_restore_runtime_and_files() -> void:
	_set_blessing_fixture(2, 0)
	var valid_backup := PlayerState._read_json(_profile_path)
	valid_backup["inventory"] = PlayerState.inventory.duplicate(true)
	valid_backup["equipment"] = PlayerState.equipment.duplicate(true)
	var future := valid_backup.duplicate(true)
	future["save_version"] = PlayerState.SAVE_VERSION + 1
	var future_bytes := JSON.stringify(future)
	var backup_bytes := JSON.stringify(valid_backup)
	_write_raw(_profile_path, future_bytes)
	_write_raw(_profile_path + ".bak", backup_bytes)
	_connect_counters()
	_reset_counters()
	var inventory_before := PlayerState.inventory.duplicate(true)
	var equipment_before := PlayerState.equipment.duplicate(true)
	var stats_before := PlayerState.computed_stats.duplicate(true)
	var blessing_result: Dictionary = (
		PlayerState.use_blessing_oil_inventory_index_with_rolls(0, 0, 0)
	)
	assert(not bool(blessing_result.get("ok", false)))
	assert(str(blessing_result.get("reason", "")) == "save_failed")
	assert(PlayerState.inventory == inventory_before)
	assert(PlayerState.equipment == equipment_before)
	assert(PlayerState.computed_stats == stats_before)
	_assert_no_success_signals()
	_assert_profile_files_unchanged(future_bytes, backup_bytes)

	PlayerState.quick_item_slots = ["", "", "", ""]
	_reset_counters()
	var quick_item_result := PlayerState.assign_quick_item_slot(0, "祝福油")
	assert(not bool(quick_item_result.get("ok", false)), str(quick_item_result))
	assert(str(quick_item_result.get("reason", "")) == "save_failed")
	assert(PlayerState.quick_item_slots == ["", "", "", ""])
	_assert_no_success_signals()
	_assert_profile_files_unchanged(future_bytes, backup_bytes)

	PlayerState.learned_skills = {"烈火剑法": 1}
	PlayerState.attack_skill_slots = [""]
	PlayerState.attack_ring_slots = ["", "", "", "", "", ""]
	PlayerState._sync_legacy_quick_slots_from_ring()
	var assignments_before := PlayerState.skill_button_assignments_snapshot()
	var assignment_result := {
		"ok": true,
		"change": {"contract_id": PlayerState.SKILL_BUTTON_ASSIGNMENTS_CONTRACT_ID},
		"assignments": {
			"contract_id": PlayerState.SKILL_BUTTON_ASSIGNMENTS_CONTRACT_ID,
			PlayerState.SKILL_SLOT_GROUP_ATTACK: [""],
			PlayerState.SKILL_SLOT_GROUP_ATTACK_RING: ["烈火剑法", "", "", "", "", ""],
		},
	}
	_reset_counters()
	assert(not PlayerState.apply_skill_button_assignment(assignment_result))
	assert(PlayerState.skill_button_assignments_snapshot() == assignments_before)
	_assert_no_success_signals()
	_assert_profile_files_unchanged(future_bytes, backup_bytes)

	PlayerState.gold = 100
	_reset_counters()
	var add_result: Variant = PlayerState.add_gold(5)
	assert(add_result is bool and not bool(add_result))
	assert(PlayerState.gold == 100)
	_assert_no_success_signals()
	var spend_result: Variant = PlayerState.spend_gold(10)
	assert(spend_result is bool and not bool(spend_result))
	assert(PlayerState.gold == 100)
	_assert_no_success_signals()
	var domain_runtime := DomainRuntimeServicesScript.new()
	var domain_save_result: Variant = domain_runtime.save()
	assert(domain_save_result is bool and not bool(domain_save_result))
	_assert_profile_files_unchanged(future_bytes, backup_bytes)
	_disconnect_counters()


func _set_blessing_fixture(oil_count: int, weapon_luck: int) -> void:
	PlayerState.inventory = [{"name": "祝福油", "count": oil_count}]
	PlayerState.equipment = PlayerState._empty_equipment()
	PlayerState.equipment["武器"] = {
		"name": "命运之刃",
		"count": 1,
		"instance_id": "atomic-blessing-weapon",
		"durability": 20,
		"max_durability": 20,
		"durability_raw": 20000,
		"max_durability_raw": 20000,
		"durability_contract_id": PlayerState.DURABILITY_CONTRACT_ID,
		"weapon_luck": weapon_luck,
		"weapon_curse": 0,
	}
	PlayerState.recalculate_stats(false)


func _configure_isolated_state() -> void:
	_root = "%s_%d" % [ROOT_PREFIX, Time.get_ticks_usec()]
	PlayerState.profile_directory = _root.path_join("characters")
	PlayerState.profile_index_path = _root.path_join("profiles.json")
	PlayerState.shared_warehouse_path = _root.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = _root.path_join("shared.transaction.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.test_mode = false
	PlayerState.reset_progress(false)
	PlayerState.active_profile_id = "transaction_profile"
	PlayerState.character_name = "事务测试"
	PlayerState.level = 50
	PlayerState.profession = "战士"
	PlayerState.gender = "男"
	PlayerState._save_blocked_profile_id = ""
	PlayerState._save_blocked_reason = ""
	PlayerState._shared_warehouse_initialized = true
	_profile_path = PlayerState._profile_path(PlayerState.active_profile_id)


func _connect_counters() -> void:
	PlayerState.inventory_changed.connect(_on_inventory_changed)
	PlayerState.equipment_changed.connect(_on_equipment_changed)
	PlayerState.quick_item_slots_changed.connect(_on_quick_item_slots_changed)
	PlayerState.quick_slots_changed.connect(_on_quick_slots_changed)
	PlayerState.skills_changed.connect(_on_skills_changed)
	PlayerState.profile_changed.connect(_on_profile_changed)


func _disconnect_counters() -> void:
	PlayerState.inventory_changed.disconnect(_on_inventory_changed)
	PlayerState.equipment_changed.disconnect(_on_equipment_changed)
	PlayerState.quick_item_slots_changed.disconnect(_on_quick_item_slots_changed)
	PlayerState.quick_slots_changed.disconnect(_on_quick_slots_changed)
	PlayerState.skills_changed.disconnect(_on_skills_changed)
	PlayerState.profile_changed.disconnect(_on_profile_changed)


func _reset_counters() -> void:
	_inventory_signal_count = 0
	_equipment_signal_count = 0
	_quick_item_signal_count = 0
	_quick_skill_signal_count = 0
	_skills_signal_count = 0
	_profile_signal_count = 0


func _assert_no_success_signals() -> void:
	assert(_inventory_signal_count == 0)
	assert(_equipment_signal_count == 0)
	assert(_quick_item_signal_count == 0)
	assert(_quick_skill_signal_count == 0)
	assert(_skills_signal_count == 0)
	assert(_profile_signal_count == 0)


func _assert_profile_files_unchanged(main_bytes: String, backup_bytes: String) -> void:
	assert(FileAccess.get_file_as_string(_profile_path) == main_bytes)
	assert(FileAccess.get_file_as_string(_profile_path + ".bak") == backup_bytes)


func _write_raw(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(contents)
	file.close()


func _cleanup_files() -> void:
	for path: String in [
		_profile_path, _profile_path + ".bak", _profile_path + ".tmp",
		PlayerState.profile_index_path, PlayerState.profile_index_path + ".bak",
		PlayerState.shared_warehouse_path, PlayerState.shared_warehouse_path + ".bak",
		PlayerState.shared_warehouse_transaction_log_path,
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var characters := _root.path_join("characters")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(characters)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(characters))
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_root)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_root))


func _capture_state() -> void:
	_saved = {
		"profile_directory": PlayerState.profile_directory,
		"profile_index_path": PlayerState.profile_index_path,
		"shared_warehouse_path": PlayerState.shared_warehouse_path,
		"transaction_path": PlayerState.shared_warehouse_transaction_log_path,
		"test_mode": PlayerState.test_mode,
		"active_profile_id": PlayerState.active_profile_id,
		"character_name": PlayerState.character_name,
		"level": PlayerState.level,
		"profession": PlayerState.profession,
		"gender": PlayerState.gender,
		"gold": PlayerState.gold,
		"inventory": PlayerState.inventory.duplicate(true),
		"equipment": PlayerState.equipment.duplicate(true),
		"quick_item_slots": PlayerState.quick_item_slots.duplicate(),
		"attack_skill_slots": PlayerState.attack_skill_slots.duplicate(),
		"attack_ring_slots": PlayerState.attack_ring_slots.duplicate(),
		"learned_skills": PlayerState.learned_skills.duplicate(true),
		"initialized": PlayerState._shared_warehouse_initialized,
		"save_blocked_profile_id": PlayerState._save_blocked_profile_id,
		"save_blocked_reason": PlayerState._save_blocked_reason,
	}


func _restore_state() -> void:
	PlayerState.profile_directory = str(_saved.profile_directory)
	PlayerState.profile_index_path = str(_saved.profile_index_path)
	PlayerState.shared_warehouse_path = str(_saved.shared_warehouse_path)
	PlayerState.shared_warehouse_transaction_log_path = str(_saved.transaction_path)
	PlayerState.test_mode = bool(_saved.test_mode)
	PlayerState.active_profile_id = str(_saved.active_profile_id)
	PlayerState.character_name = str(_saved.character_name)
	PlayerState.level = int(_saved.level)
	PlayerState.profession = str(_saved.profession)
	PlayerState.gender = str(_saved.gender)
	PlayerState.gold = int(_saved.gold)
	PlayerState.inventory = (_saved.inventory as Array).duplicate(true)
	PlayerState.equipment = (_saved.equipment as Dictionary).duplicate(true)
	PlayerState.quick_item_slots = (_saved.quick_item_slots as Array).duplicate()
	PlayerState.attack_skill_slots = (_saved.attack_skill_slots as Array).duplicate()
	PlayerState.attack_ring_slots = (_saved.attack_ring_slots as Array).duplicate()
	PlayerState.learned_skills = (_saved.learned_skills as Dictionary).duplicate(true)
	PlayerState._sync_legacy_quick_slots_from_ring()
	PlayerState._shared_warehouse_initialized = bool(_saved.initialized)
	PlayerState._save_blocked_profile_id = str(_saved.save_blocked_profile_id)
	PlayerState._save_blocked_reason = str(_saved.save_blocked_reason)
	PlayerState.recalculate_stats(false)


func _on_inventory_changed() -> void:
	_inventory_signal_count += 1


func _on_equipment_changed() -> void:
	_equipment_signal_count += 1


func _on_quick_item_slots_changed(_change: Dictionary) -> void:
	_quick_item_signal_count += 1


func _on_quick_slots_changed(_change: Dictionary) -> void:
	_quick_skill_signal_count += 1


func _on_skills_changed() -> void:
	_skills_signal_count += 1


func _on_profile_changed() -> void:
	_profile_signal_count += 1
