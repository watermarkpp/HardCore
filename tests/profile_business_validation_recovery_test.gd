extends Node

const ROOT_PREFIX := "user://profile_business_validation_recovery"

var _root := ""
var _saved: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_capture_state()
	_root = "%s_%d" % [ROOT_PREFIX, Time.get_ticks_usec()]
	PlayerState.test_mode = false
	_test_profile_primary_backup_matrix()
	_test_future_profile_blocks_fallback_and_save()
	_test_profile_index_validation_and_recovery()
	_test_profile_index_update_preserves_unloadable_entries()
	_test_profile_scalar_validation_and_high_level_compatibility()
	_test_invalid_profile_id_cannot_escape_profile_directory()
	_test_shared_warehouse_validation_and_recovery()
	_test_legacy_versions_and_shapes_migrate()
	_restore_state()
	print("PROFILE_BUSINESS_VALIDATION_RECOVERY_PASS")
	get_tree().quit(0)


func _test_profile_primary_backup_matrix() -> void:
	_configure_case("profile_matrix")
	var profile_id := "matrix_profile"
	var profile_path := PlayerState._profile_path(profile_id)
	var good := _valid_profile(profile_id, 111)
	var good_text := JSON.stringify(good)
	_write_raw(profile_path, "{}")
	_write_raw(profile_path + ".bak", good_text)
	PlayerState.active_profile_id = profile_id
	PlayerState.gold = 999
	PlayerState.load_save()
	assert(bool(PlayerState.last_load_result.get("success", false)), str(PlayerState.last_load_result))
	assert(str(PlayerState.last_load_result.get("reason", "")) == "recovered_from_backup")
	assert(PlayerState.gold == 111, "业务无效主档阻挡了有效备份")
	assert(int(PlayerState._read_json(profile_path + ".bak").get("gold", -1)) == 111)
	_assert_one_quarantine_with_bytes(profile_path, "{}")

	_clear_profile_files(profile_path)
	_write_raw(profile_path, JSON.stringify({
		"save_version": PlayerState.SAVE_VERSION,
		"profile_id": profile_id,
		"inventory": {},
	}))
	_write_raw(profile_path + ".bak", good_text)
	PlayerState.gold = 999
	PlayerState.load_save()
	assert(bool(PlayerState.last_load_result.get("success", false)))
	assert(PlayerState.gold == 111)

	_clear_profile_files(profile_path)
	_write_raw(profile_path, JSON.stringify({
		"save_version": PlayerState.SAVE_VERSION,
		"profile_id": profile_id,
		"inventory": [{"name": "太阳水", "count": 0}],
	}))
	_write_raw(profile_path + ".bak", good_text)
	PlayerState.gold = 999
	PlayerState.load_save()
	assert(bool(PlayerState.last_load_result.get("success", false)))
	assert(PlayerState.gold == 111, "无效占用 count 未回退有效备份")

	_clear_profile_files(profile_path)
	var wrong_id := good.duplicate(true)
	wrong_id["profile_id"] = "other_profile"
	_write_raw(profile_path, JSON.stringify(wrong_id))
	_write_raw(profile_path + ".bak", good_text)
	PlayerState.gold = 999
	PlayerState.load_save()
	assert(bool(PlayerState.last_load_result.get("success", false)))
	assert(PlayerState.gold == 111)

	_clear_profile_files(profile_path)
	var primary := _valid_profile(profile_id, 222)
	var primary_text := JSON.stringify(primary)
	_write_raw(profile_path, primary_text)
	_write_raw(profile_path + ".bak", "not-json")
	PlayerState.gold = 999
	PlayerState.load_save()
	assert(bool(PlayerState.last_load_result.get("success", false)))
	assert(str(PlayerState.last_load_result.get("reason", "")) == "primary")
	assert(PlayerState.gold == 222)
	assert(int(PlayerState._read_json(profile_path).get("gold", -1)) == 222)
	assert(int(PlayerState._read_json(profile_path + ".bak").get("gold", -1)) == 222)

	_clear_profile_files(profile_path)
	_write_raw(profile_path, "{}")
	_write_raw(profile_path + ".bak", "[]")
	PlayerState.gold = 777
	PlayerState.inventory = [{"name": "保留物品", "count": 1}]
	PlayerState.load_save()
	assert(not bool(PlayerState.last_load_result.get("success", false)))
	assert(PlayerState.gold == 777 and PlayerState.inventory.size() == 1)
	assert(FileAccess.get_file_as_string(profile_path) == "{}")
	assert(FileAccess.get_file_as_string(profile_path + ".bak") == "[]")
	assert(_quarantine_paths(profile_path).is_empty())


func _test_future_profile_blocks_fallback_and_save() -> void:
	_configure_case("future_profile")
	var profile_id := "future_profile"
	var profile_path := PlayerState._profile_path(profile_id)
	var future := _valid_profile(profile_id, 333)
	future["save_version"] = PlayerState.SAVE_VERSION + 1
	var future_text := JSON.stringify(future)
	var old_text := JSON.stringify(_valid_profile(profile_id, 111))
	_write_raw(profile_path, future_text)
	_write_raw(profile_path + ".bak", old_text)
	PlayerState.active_profile_id = profile_id
	PlayerState.gold = 888
	PlayerState.load_save()
	assert(not bool(PlayerState.last_load_result.get("success", false)))
	assert(str(PlayerState.last_load_result.get("reason", "")) == "future_save_version")
	assert(PlayerState.gold == 888, "future 档错误发布了旧备份或默认状态")
	assert(FileAccess.get_file_as_string(profile_path) == future_text)
	assert(FileAccess.get_file_as_string(profile_path + ".bak") == old_text)
	assert(not PlayerState.save_game(), "future 档失败后仍允许 autosave 等价写入")
	assert(str(PlayerState.last_save_result.get("reason", "")) == "profile_save_blocked_after_invalid_load")
	assert(not PlayerState._write_json_atomic(profile_path, _valid_profile(profile_id, 444)))
	assert(FileAccess.get_file_as_string(profile_path) == future_text)
	assert(FileAccess.get_file_as_string(profile_path + ".bak") == old_text)
	assert(_quarantine_paths(profile_path).is_empty())


func _test_profile_index_validation_and_recovery() -> void:
	_configure_case("profile_index")
	var profile_id := "indexed_profile"
	var profile_path := PlayerState._profile_path(profile_id)
	_write_raw(profile_path, JSON.stringify(_valid_profile(profile_id, 11)))
	var good_index := {
		"version": 1,
		"profiles": [{
			"id": profile_id, "name": "索引角色", "profession": "战士",
			"gender": "男", "level": 1, "updated_at": 1,
		}],
	}
	var good_text := JSON.stringify(good_index)
	_write_raw(PlayerState.profile_index_path, "{}")
	_write_raw(PlayerState.profile_index_path + ".bak", good_text)
	var listed := PlayerState.list_characters()
	assert(listed.size() == 1 and str(listed[0].get("id", "")) == profile_id)
	_assert_one_quarantine_with_bytes(PlayerState.profile_index_path, "{}")
	assert(FileAccess.get_file_as_string(PlayerState.profile_index_path + ".bak") == good_text)

	_clear_profile_files(PlayerState.profile_index_path)
	var malformed_entry_index := good_index.duplicate(true)
	malformed_entry_index["profiles"][0]["updated_at"] = {}
	_write_raw(PlayerState.profile_index_path, JSON.stringify(malformed_entry_index))
	_write_raw(PlayerState.profile_index_path + ".bak", good_text)
	var recovered_index := PlayerState._read_json_with_status(PlayerState.profile_index_path)
	assert(str(recovered_index.get("reason", "")) == "recovered_from_backup", "畸形索引展示字段未回退有效备份")

	_clear_profile_files(PlayerState.profile_index_path)
	var future_index := good_index.duplicate(true)
	future_index["version"] = 2
	var future_text := JSON.stringify(future_index)
	_write_raw(PlayerState.profile_index_path, future_text)
	_write_raw(PlayerState.profile_index_path + ".bak", good_text)
	assert(PlayerState.list_characters().is_empty())
	assert(not PlayerState._write_json_atomic(PlayerState.profile_index_path, good_index))
	assert(FileAccess.get_file_as_string(PlayerState.profile_index_path) == future_text)
	assert(FileAccess.get_file_as_string(PlayerState.profile_index_path + ".bak") == good_text)


func _test_profile_index_update_preserves_unloadable_entries() -> void:
	_configure_case("profile_index_preservation")
	var active_id := "normal_profile"
	var future_id := "future_indexed_profile"
	var corrupt_id := "corrupt_indexed_profile"
	var active_path := PlayerState._profile_path(active_id)
	var future_path := PlayerState._profile_path(future_id)
	var corrupt_path := PlayerState._profile_path(corrupt_id)
	_write_raw(active_path, JSON.stringify(_valid_profile(active_id, 10)))
	var future := _valid_profile(future_id, 20)
	future["save_version"] = PlayerState.SAVE_VERSION + 1
	var future_main_bytes := JSON.stringify(future)
	var future_backup_bytes := JSON.stringify(_valid_profile(future_id, 19))
	var corrupt_main_bytes := "{}"
	var corrupt_backup_bytes := "[]"
	_write_raw(future_path, future_main_bytes)
	_write_raw(future_path + ".bak", future_backup_bytes)
	_write_raw(corrupt_path, corrupt_main_bytes)
	_write_raw(corrupt_path + ".bak", corrupt_backup_bytes)
	var future_entry := {
		"id": future_id, "name": "未来角色", "profession": "法师",
		"gender": "女", "level": 88, "updated_at": 102, "marker": "keep-future",
	}
	var corrupt_entry := {
		"id": corrupt_id, "name": "损坏角色", "profession": "道士",
		"gender": "男", "level": 77, "updated_at": 101, "marker": "keep-corrupt",
	}
	_write_raw(PlayerState.profile_index_path, JSON.stringify({
		"version": 1,
		"profiles": [
			{"id": active_id, "name": "正常角色", "profession": "战士", "gender": "男", "level": 1, "updated_at": 100},
			future_entry,
			corrupt_entry,
		],
	}))
	var original_index := PlayerState._read_json(PlayerState.profile_index_path)
	var original_future_entry := _index_entry(original_index, future_id)
	var original_corrupt_entry := _index_entry(original_index, corrupt_id)
	PlayerState.active_profile_id = active_id
	PlayerState.load_save()
	assert(bool(PlayerState.last_load_result.get("success", false)), str(PlayerState.last_load_result))
	PlayerState.gold = 11
	assert(PlayerState.save_game(), str(PlayerState.last_save_result))
	assert(bool(PlayerState.last_save_result.get("profile_index_updated", false)), str(PlayerState.last_save_result))
	var updated_index := PlayerState._read_json(PlayerState.profile_index_path)
	assert(_index_entry(updated_index, future_id) == original_future_entry, "保存 A 删除或改写了 future B 索引行")
	assert(_index_entry(updated_index, corrupt_id) == original_corrupt_entry, "保存 A 删除或改写了 corrupt B 索引行")
	assert(FileAccess.get_file_as_string(future_path) == future_main_bytes)
	assert(FileAccess.get_file_as_string(future_path + ".bak") == future_backup_bytes)
	assert(FileAccess.get_file_as_string(corrupt_path) == corrupt_main_bytes)
	assert(FileAccess.get_file_as_string(corrupt_path + ".bak") == corrupt_backup_bytes)
	assert(_quarantine_paths(future_path).is_empty())
	assert(_quarantine_paths(corrupt_path).is_empty())


func _test_profile_scalar_validation_and_high_level_compatibility() -> void:
	var high_level := _minimal_legacy("high_level_legacy", 9)
	high_level["level"] = 999
	assert(
		bool(PlayerState._validate_profile_document_status(high_level, "high_level_legacy", false).get("valid", false)),
		"无正式合同的 255 上限拒绝了合法高等级旧档"
	)
	var malformed := _valid_profile("malformed_scalar", 12)
	malformed["gold"] = {}
	assert(
		not bool(PlayerState._validate_profile_document_status(malformed, "malformed_scalar", false).get("valid", false)),
		"load_save 消费的畸形 gold 越过业务门禁"
	)
	for malformed_field: String in [
		"character_name", "profession", "gender", "game_mode_id",
		"later_content_enabled", "experience", "content_schema_version",
	]:
		var malformed_known_field := _valid_profile("malformed_known_field", 12)
		malformed_known_field[malformed_field] = {}
		assert(
			not bool(PlayerState._validate_profile_document_status(
				malformed_known_field, "malformed_known_field", false
			).get("valid", false)),
			"load_save 消费的畸形字段越过业务门禁: %s" % malformed_field
		)
	var hollow_current := {
		"save_version": PlayerState.SAVE_VERSION,
		"profile_id": "hollow_current",
		"character_name": "空壳角色",
	}
	assert(
		not bool(PlayerState._validate_profile_document_status(hollow_current, "hollow_current", false).get("valid", false)),
		"当前 v10 仅靠一个身份字段即被当作可信存档"
	)
	_configure_case("malformed_scalar_no_publish")
	var profile_id := "malformed_scalar"
	var profile_path := PlayerState._profile_path(profile_id)
	_write_raw(profile_path, JSON.stringify(malformed))
	_write_raw(profile_path + ".bak", "[]")
	PlayerState.active_profile_id = profile_id
	PlayerState.level = 123
	PlayerState.profession = "道士"
	PlayerState.gold = 456
	PlayerState.load_save()
	assert(not bool(PlayerState.last_load_result.get("success", false)))
	assert(PlayerState.level == 123 and PlayerState.profession == "道士" and PlayerState.gold == 456)
	assert(FileAccess.get_file_as_string(profile_path) == JSON.stringify(malformed))
	assert(FileAccess.get_file_as_string(profile_path + ".bak") == "[]")


func _test_invalid_profile_id_cannot_escape_profile_directory() -> void:
	_configure_case("invalid_profile_id")
	var malicious_id := "../outside_sentinel"
	var sentinel_path := PlayerState.profile_directory.get_base_dir().path_join("outside_sentinel.json")
	var sentinel_backup_path := sentinel_path + ".bak"
	var sentinel_bytes := JSON.stringify(_valid_profile(malicious_id, 987))
	var sentinel_backup_bytes := "outside-backup-sentinel"
	_write_raw(sentinel_path, sentinel_bytes)
	_write_raw(sentinel_backup_path, sentinel_backup_bytes)
	PlayerState.level = 123
	PlayerState.gold = 456
	assert(not PlayerState.select_character(malicious_id), "非法 profile_id 越界读取隔离 sentinel")
	assert(PlayerState.level == 123 and PlayerState.gold == 456)
	assert(FileAccess.get_file_as_string(sentinel_path) == sentinel_bytes)
	assert(FileAccess.get_file_as_string(sentinel_backup_path) == sentinel_backup_bytes)
	PlayerState.active_profile_id = malicious_id
	PlayerState.load_save()
	assert(not bool(PlayerState.last_load_result.get("success", false)))
	assert(str(PlayerState.last_load_result.get("reason", "")) == "invalid_profile_id")
	assert(PlayerState.level == 123 and PlayerState.gold == 456)
	assert(not PlayerState.save_game(), "非法 profile_id 越界写入隔离 sentinel")
	assert(str(PlayerState.last_save_result.get("reason", "")) == "invalid_profile_id")
	assert(FileAccess.get_file_as_string(sentinel_path) == sentinel_bytes)
	assert(FileAccess.get_file_as_string(sentinel_backup_path) == sentinel_backup_bytes)


func _test_shared_warehouse_validation_and_recovery() -> void:
	_configure_case("shared_warehouse")
	var good := _valid_shared([{"name": "未知但可保留的旧物品", "count": 1}])
	var good_text := JSON.stringify(good)
	_write_raw(PlayerState.shared_warehouse_path, "{}")
	_write_raw(PlayerState.shared_warehouse_path + ".bak", good_text)
	PlayerState._shared_warehouse_initialized = false
	assert(PlayerState._initialize_shared_warehouse())
	assert(PlayerState.warehouse_inventory.size() == 1)
	_assert_one_quarantine_with_bytes(PlayerState.shared_warehouse_path, "{}")
	assert(FileAccess.get_file_as_string(PlayerState.shared_warehouse_path + ".bak") == good_text)

	_clear_profile_files(PlayerState.shared_warehouse_path)
	var invalid_schema_type := good.duplicate(true)
	invalid_schema_type["schema_version"] = {}
	_write_raw(PlayerState.shared_warehouse_path, JSON.stringify(invalid_schema_type))
	_write_raw(PlayerState.shared_warehouse_path + ".bak", good_text)
	PlayerState._shared_warehouse_initialized = false
	assert(PlayerState._initialize_shared_warehouse(), "畸形 shared schema 未安全回退有效备份")

	_clear_profile_files(PlayerState.shared_warehouse_path)
	var invalid_count := _valid_shared([{"name": "太阳水", "count": 0}])
	_write_raw(PlayerState.shared_warehouse_path, JSON.stringify(invalid_count))
	_write_raw(PlayerState.shared_warehouse_path + ".bak", good_text)
	PlayerState._shared_warehouse_initialized = false
	assert(PlayerState._initialize_shared_warehouse())
	assert(PlayerState.warehouse_inventory.size() == 1)

	_clear_profile_files(PlayerState.shared_warehouse_path)
	var future := good.duplicate(true)
	future["schema_version"] = PlayerState.SHARED_WAREHOUSE_SCHEMA_VERSION + 1
	var future_text := JSON.stringify(future)
	_write_raw(PlayerState.shared_warehouse_path, future_text)
	_write_raw(PlayerState.shared_warehouse_path + ".bak", good_text)
	PlayerState._shared_warehouse_initialized = false
	assert(not PlayerState._initialize_shared_warehouse())
	assert(not PlayerState._write_json_atomic(PlayerState.shared_warehouse_path, good))
	assert(FileAccess.get_file_as_string(PlayerState.shared_warehouse_path) == future_text)
	assert(FileAccess.get_file_as_string(PlayerState.shared_warehouse_path + ".bak") == good_text)


func _test_legacy_versions_and_shapes_migrate() -> void:
	var root_legacy := _minimal_legacy("ignored_root_identity", 6)
	root_legacy.erase("profile_id")
	assert(bool(PlayerState._validate_profile_document_status(root_legacy, "", true).get("valid", false)))
	assert(not bool(PlayerState._validate_profile_document_status(root_legacy, "normal_profile", false).get("valid", false)))
	root_legacy["save_version"] = PlayerState.SAVE_VERSION + 1
	var future_root_validation := PlayerState._validate_profile_document_status(root_legacy, "", true)
	assert(not bool(future_root_validation.get("valid", false)) and bool(future_root_validation.get("terminal", false)))

	_configure_case("legacy_v6")
	var v6_id := "legacy_v6"
	var v6 := _minimal_legacy(v6_id, 6)
	v6["map_id"] = 217
	v6["position"] = [321.5, -84.0]
	_load_fixture(v6_id, v6)
	assert(PlayerState.saved_position.is_equal_approx(Vector2(321.5, -84.0)))
	assert(not PlayerState.saved_ground_position_gu_valid)
	assert(int(PlayerState._read_json(PlayerState._profile_path(v6_id)).get("save_version", 0)) == PlayerState.SAVE_VERSION)

	_configure_case("legacy_v7")
	var v7_id := "legacy_v7"
	var v7 := _minimal_legacy(v7_id, 7)
	v7["profession"] = "道士"
	v7["learned_skills"] = {"治愈术": 2}
	v7["quick_slots"] = ["治愈术", "", "", ""]
	v7["equipment"] = {
		"武器": "木剑",
		"手镯": {"name": "铁手镯", "durability": 2, "max_durability": 4},
		"戒指": {"name": "古铜戒指", "durability": 3, "max_durability": 5},
	}
	v7["warehouse_inventory"] = [{"name": "旧库未知物品", "count": 1}]
	v7["taoist_main_pet_runtime_state"] = _legacy_pet_snapshot()
	_write_index([v7_id])
	_load_fixture(v7_id, v7)
	assert(int(PlayerState.learned_skills.get("治愈术", 0)) == 2)
	assert(str(PlayerState.equipment.get("武器", {}).get("name", "")) == "木剑")
	assert(int(PlayerState.equipment.get("左手镯", {}).get("durability_raw", 0)) == 2000)
	assert(int(PlayerState.equipment.get("左戒指", {}).get("durability_raw", 0)) == 3000)
	assert(not PlayerState.taoist_main_pet_runtime_state_for_restore("skeleton").is_empty())
	assert(PlayerState.warehouse_inventory.size() == 1)
	assert(not PlayerState._read_json(PlayerState._profile_path(v7_id)).has("warehouse_inventory"))

	_configure_case("legacy_v8")
	var v8_id := "legacy_v8"
	var v8 := _minimal_legacy(v8_id, 8)
	v8["quick_item_slots"] = ["回城卷", 123, null, "不存在物品"]
	v8.erase("equip_cycle_cursor")
	_load_fixture(v8_id, v8)
	assert(PlayerState.quick_item_slots == ["回城卷", "", "", ""])
	assert(PlayerState.equip_cycle_cursor == {"戒指": "左戒指", "手镯": "左手镯"})

	_configure_case("legacy_v9")
	var v9_id := "legacy_v9"
	var v9 := _minimal_legacy(v9_id, 9)
	v9["level"] = 999
	_load_fixture(v9_id, v9)
	assert(PlayerState.level == 999)
	assert(int(PlayerState._read_json(PlayerState._profile_path(v9_id)).get("save_version", 0)) == PlayerState.SAVE_VERSION)


func _configure_case(name: String) -> void:
	var case_root := _root.path_join(name)
	PlayerState.profile_directory = case_root.path_join("characters")
	PlayerState.profile_index_path = case_root.path_join("profiles.json")
	PlayerState.shared_warehouse_path = case_root.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = case_root.path_join("shared.transaction.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.active_profile_id = ""
	PlayerState._save_blocked_profile_id = ""
	PlayerState._save_blocked_reason = ""
	PlayerState._shared_warehouse_initialized = true
	PlayerState._warehouse_transaction_locked = false
	PlayerState._persistence_transaction_in_progress = false
	PlayerState.warehouse_inventory = []
	PlayerState.inventory = []


func _load_fixture(profile_id: String, document: Dictionary) -> void:
	var path := PlayerState._profile_path(profile_id)
	_write_raw(path, JSON.stringify(document))
	PlayerState.active_profile_id = profile_id
	PlayerState._shared_warehouse_initialized = FileAccess.file_exists(PlayerState.shared_warehouse_path)
	PlayerState.load_save()
	assert(bool(PlayerState.last_load_result.get("success", false)), str(PlayerState.last_load_result))


func _minimal_legacy(profile_id: String, version: int) -> Dictionary:
	return {
		"save_version": version,
		"profile_id": profile_id,
		"character_name": profile_id,
		"level": 1,
		"profession": "战士",
		"gender": "男",
		"inventory": [],
		"equipment": {},
		"learned_skills": {},
		"quest_states": {},
		"map_id": 910001,
		"position": [0.0, 0.0],
	}


func _valid_profile(profile_id: String, saved_gold: int) -> Dictionary:
	var result := _minimal_legacy(profile_id, PlayerState.SAVE_VERSION)
	result["gold"] = saved_gold
	return result


func _valid_shared(records: Array) -> Dictionary:
	return {
		"schema_version": PlayerState.SHARED_WAREHOUSE_SCHEMA_VERSION,
		"contract_id": PlayerState.SHARED_WAREHOUSE_CONTRACT_ID,
		"revision": 1,
		"warehouse_inventory": records.duplicate(true),
		"legacy_migration": {
			"completed": true,
			"contract_id": PlayerState.SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID,
			"sources": {},
		},
	}


func _legacy_pet_snapshot() -> Dictionary:
	return {
		"contract_id": PlayerState.TAOIST_MAIN_PET_PERSISTENCE_CONTRACT_ID,
		"alive": true,
		"runtime_state": "FOLLOW_OWNER",
		"summon_id": "skeleton",
		"skill_id": "taoist.summon_skeleton",
		"skill_rank": 1,
		"owner_level": 1,
		"current_hp": 10,
		"max_hp": 10,
		"summon_exp_level": 0,
		"maximum_pet_level": 7,
		"pet_growth_exp": 0,
		"remaining_lifetime": 60.0,
	}


func _write_index(profile_ids: Array[String]) -> void:
	var profiles: Array = []
	for profile_id: String in profile_ids:
		profiles.append({"id": profile_id, "name": profile_id, "profession": "战士", "gender": "男", "level": 1})
	_write_raw(PlayerState.profile_index_path, JSON.stringify({"version": 1, "profiles": profiles}))


func _index_entry(index: Dictionary, profile_id: String) -> Dictionary:
	for raw_entry: Variant in index.get("profiles", []):
		if raw_entry is Dictionary and str((raw_entry as Dictionary).get("id", "")) == profile_id:
			return (raw_entry as Dictionary).duplicate(true)
	return {}


func _write_raw(path: String, contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "fixture write failed: %s" % path)
	file.store_string(contents)
	file.close()


func _quarantine_paths(path: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(path.get_base_dir())
	if directory == null:
		return result
	var prefix := path.get_file() + ".quarantine."
	for file_name: String in directory.get_files():
		if file_name.begins_with(prefix):
			result.append(path.get_base_dir().path_join(file_name))
	result.sort()
	return result


func _assert_one_quarantine_with_bytes(path: String, expected: String) -> void:
	var quarantines := _quarantine_paths(path)
	assert(quarantines.size() == 1, "expected one quarantine for %s: %s" % [path, quarantines])
	assert(FileAccess.get_file_as_string(quarantines[0]) == expected, "quarantine bytes changed")


func _clear_profile_files(path: String) -> void:
	for candidate: String in [path, path + ".bak", path + ".tmp"] + _quarantine_paths(path):
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func _capture_state() -> void:
	_saved = {
		"profile_directory": PlayerState.profile_directory,
		"profile_index_path": PlayerState.profile_index_path,
		"shared_warehouse_path": PlayerState.shared_warehouse_path,
		"transaction_path": PlayerState.shared_warehouse_transaction_log_path,
		"test_mode": PlayerState.test_mode,
		"active_profile_id": PlayerState.active_profile_id,
		"gold": PlayerState.gold,
		"inventory": PlayerState.inventory.duplicate(true),
		"warehouse": PlayerState.warehouse_inventory.duplicate(true),
		"initialized": PlayerState._shared_warehouse_initialized,
		"locked": PlayerState._warehouse_transaction_locked,
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
	PlayerState.gold = int(_saved.gold)
	PlayerState.inventory = (_saved.inventory as Array).duplicate(true)
	PlayerState.warehouse_inventory = (_saved.warehouse as Array).duplicate(true)
	PlayerState._shared_warehouse_initialized = bool(_saved.initialized)
	PlayerState._warehouse_transaction_locked = bool(_saved.locked)
	PlayerState._save_blocked_profile_id = str(_saved.save_blocked_profile_id)
	PlayerState._save_blocked_reason = str(_saved.save_blocked_reason)
