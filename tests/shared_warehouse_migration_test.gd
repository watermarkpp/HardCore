extends Node

const TEST_ROOT_PREFIX := "user://shared_warehouse_migration_isolated"

var _root := ""
var _saved: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_capture_player_state()
	_root = "%s_%d" % [TEST_ROOT_PREFIX, Time.get_ticks_usec()]
	PlayerState.test_mode = true
	PlayerState._test_force_atomic_write_failure = false
	PlayerState._test_fail_shared_write = false
	var production_existed := FileAccess.file_exists(PlayerState.SHARED_WAREHOUSE_DEFAULT_PATH)
	var production_bytes := (
		FileAccess.get_file_as_bytes(PlayerState.SHARED_WAREHOUSE_DEFAULT_PATH)
		if production_existed
		else PackedByteArray()
	)
	_test_sparse_merge_idempotence_delete_and_create()
	_test_capacity_boundaries()
	_test_migration_write_failure_and_digest_guard()
	assert(FileAccess.file_exists(PlayerState.SHARED_WAREHOUSE_DEFAULT_PATH) == production_existed)
	if production_existed:
		assert(FileAccess.get_file_as_bytes(PlayerState.SHARED_WAREHOUSE_DEFAULT_PATH) == production_bytes)
	_restore_player_state()
	print("SHARED_WAREHOUSE_MIGRATION_TEST_PASS")
	get_tree().quit()


func _test_sparse_merge_idempotence_delete_and_create() -> void:
	_configure_case("merge")
	_write_profile("z", [{}, {"name": "强效太阳水", "count": 2, "instance_id": "z-slot-1"}, {}, {"name": "修复油", "count": 1, "instance_id": "z-slot-3"}])
	_write_profile("a", [{"name": "太阳水", "count": 3, "instance_id": "a-slot-0"}])
	_write_index(["z", "a"])
	assert(PlayerState._initialize_shared_warehouse(), "稀疏旧仓库迁移失败")
	assert(_instance_ids(PlayerState.warehouse_inventory) == ["a-slot-0", "z-slot-1", "z-slot-3"])
	var shared_bytes := FileAccess.get_file_as_bytes(PlayerState.shared_warehouse_path)
	var sources: Dictionary = PlayerState._read_json(PlayerState.shared_warehouse_path).get("legacy_migration", {}).get("sources", {})
	assert(int(sources.get("a", {}).get("occupied_count", -1)) == 1)
	assert(int(sources.get("z", {}).get("occupied_count", -1)) == 2)
	for _iteration in range(10):
		PlayerState._shared_warehouse_initialized = false
		assert(PlayerState._initialize_shared_warehouse(), "重复初始化失败")
		assert(FileAccess.get_file_as_bytes(PlayerState.shared_warehouse_path) == shared_bytes)
		assert(_instance_ids(PlayerState.warehouse_inventory) == ["a-slot-0", "z-slot-1", "z-slot-3"])
	assert(bool(PlayerState.delete_character_profile("a").get("success", false)))
	assert(FileAccess.get_file_as_bytes(PlayerState.shared_warehouse_path) == shared_bytes)
	assert(bool(PlayerState.delete_character_profile("z").get("success", false)))
	assert(FileAccess.get_file_as_bytes(PlayerState.shared_warehouse_path) == shared_bytes)
	assert(PlayerState._read_json(PlayerState.shared_warehouse_path).get("legacy_migration", {}).get("sources", {}).size() == 2)
	PlayerState.reset_progress(false)
	assert(FileAccess.get_file_as_bytes(PlayerState.shared_warehouse_path) == shared_bytes)
	assert(_instance_ids(PlayerState.warehouse_inventory) == ["a-slot-0", "z-slot-1", "z-slot-3"])
	var create_error := PlayerState.create_character("公共仓库新角色", "战士", "男")
	assert(create_error.is_empty(), "创建新人物失败：%s" % create_error)
	var first_new_profile_id := PlayerState.active_profile_id
	assert(FileAccess.get_file_as_bytes(PlayerState.shared_warehouse_path) == shared_bytes)
	assert(_instance_ids(PlayerState.warehouse_inventory) == ["a-slot-0", "z-slot-1", "z-slot-3"])
	create_error = PlayerState.create_character("公共仓库第二角色", "法师", "女")
	assert(create_error.is_empty(), "创建第二个人物失败：%s" % create_error)
	assert(PlayerState.select_character(first_new_profile_id), "切回第一个新人物失败")
	assert(FileAccess.get_file_as_bytes(PlayerState.shared_warehouse_path) == shared_bytes)
	assert(_instance_ids(PlayerState.warehouse_inventory) == ["a-slot-0", "z-slot-1", "z-slot-3"])


func _test_capacity_boundaries() -> void:
	_configure_case("capacity_500")
	_write_profile("p500", _items("p500", 500))
	_write_index(["p500"])
	assert(PlayerState._initialize_shared_warehouse(), "500 件公共仓库迁移应成功")
	assert(PlayerState.warehouse_inventory.size() == 500)
	_configure_case("capacity_501")
	_write_profile("a300", _items("a", 300))
	_write_profile("b201", _items("b", 201))
	_write_index(["b201", "a300"])
	var a_bytes := FileAccess.get_file_as_bytes(PlayerState._profile_path("a300"))
	var b_bytes := FileAccess.get_file_as_bytes(PlayerState._profile_path("b201"))
	assert(not PlayerState._initialize_shared_warehouse(), "501 件迁移必须整体拒绝")
	assert(not FileAccess.file_exists(PlayerState.shared_warehouse_path))
	assert(FileAccess.get_file_as_bytes(PlayerState._profile_path("a300")) == a_bytes)
	assert(FileAccess.get_file_as_bytes(PlayerState._profile_path("b201")) == b_bytes)


func _test_migration_write_failure_and_digest_guard() -> void:
	_configure_case("write_failure")
	_write_profile("p", [{"name": "太阳水", "count": 1, "instance_id": "write-fail"}])
	_write_index(["p"])
	var source_bytes := FileAccess.get_file_as_bytes(PlayerState._profile_path("p"))
	PlayerState._test_fail_shared_write = true
	assert(not PlayerState._initialize_shared_warehouse())
	PlayerState._test_fail_shared_write = false
	assert(not FileAccess.file_exists(PlayerState.shared_warehouse_path))
	assert(FileAccess.get_file_as_bytes(PlayerState._profile_path("p")) == source_bytes)
	assert(PlayerState._initialize_shared_warehouse())
	var shared_bytes := FileAccess.get_file_as_bytes(PlayerState.shared_warehouse_path)
	_write_profile("p", [{"name": "太阳水", "count": 2, "instance_id": "changed-after-migration"}])
	PlayerState._shared_warehouse_initialized = false
	assert(not PlayerState._initialize_shared_warehouse(), "迁移源摘要变化必须 fail-closed")
	assert(FileAccess.get_file_as_bytes(PlayerState.shared_warehouse_path) == shared_bytes)
	assert(not bool(PlayerState.delete_character_profile("p").get("success", false)))
	assert(FileAccess.file_exists(PlayerState._profile_path("p")))


func _configure_case(name: String) -> void:
	var case_root := _root.path_join(name)
	PlayerState.profile_directory = case_root.path_join("characters")
	PlayerState.profile_index_path = case_root.path_join("index.json")
	PlayerState.shared_warehouse_path = case_root.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = case_root.path_join("shared.transaction.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState._shared_warehouse_initialized = false
	PlayerState._warehouse_transaction_locked = false
	PlayerState._persistence_transaction_in_progress = false
	PlayerState.active_profile_id = ""
	PlayerState.character_name = ""
	PlayerState.warehouse_inventory = []
	PlayerState.inventory = []


func _write_profile(profile_id: String, warehouse: Array) -> void:
	assert(PlayerState._write_json_atomic(PlayerState._profile_path(profile_id), {
		"save_version": PlayerState.SAVE_VERSION, "profile_id": profile_id,
		"character_name": profile_id, "level": 1, "profession": "战士", "gender": "男",
		"inventory": [], "warehouse_inventory": warehouse,
		"equipment": PlayerState._empty_equipment(), "learned_skills": {}, "quest_states": {},
	}))


func _write_index(profile_ids: Array) -> void:
	var profiles: Array = []
	for profile_id: String in profile_ids:
		profiles.append({"id": profile_id, "name": profile_id, "profession": "战士", "gender": "男", "level": 1, "updated_at": 0})
	assert(PlayerState._write_json_atomic(PlayerState.profile_index_path, {"version": 1, "profiles": profiles}))


func _items(prefix: String, count: int) -> Array:
	var result: Array = []
	for index in range(count):
		result.append({"name": "太阳水", "count": 1, "instance_id": "%s-%03d" % [prefix, index]})
	return result


func _instance_ids(records: Array) -> Array:
	var result: Array = []
	for record: Variant in records:
		if record is Dictionary and not (record as Dictionary).is_empty():
			result.append(str((record as Dictionary).get("instance_id", "")))
	return result


func _capture_player_state() -> void:
	_saved = {
		"profile_directory": PlayerState.profile_directory, "profile_index_path": PlayerState.profile_index_path,
		"shared_warehouse_path": PlayerState.shared_warehouse_path, "transaction_path": PlayerState.shared_warehouse_transaction_log_path,
		"active_profile_id": PlayerState.active_profile_id, "character_name": PlayerState.character_name,
		"warehouse_inventory": PlayerState.warehouse_inventory.duplicate(true), "inventory": PlayerState.inventory.duplicate(true),
		"test_mode": PlayerState.test_mode, "initialized": PlayerState._shared_warehouse_initialized,
		"locked": PlayerState._warehouse_transaction_locked, "in_progress": PlayerState._persistence_transaction_in_progress,
		"force_failure": PlayerState._test_force_atomic_write_failure, "shared_failure": PlayerState._test_fail_shared_write,
		"profile_failure": PlayerState._test_fail_profile_write, "rollback_failure": PlayerState._test_fail_warehouse_rollback_write,
	}


func _restore_player_state() -> void:
	PlayerState.profile_directory = str(_saved.profile_directory)
	PlayerState.profile_index_path = str(_saved.profile_index_path)
	PlayerState.shared_warehouse_path = str(_saved.shared_warehouse_path)
	PlayerState.shared_warehouse_transaction_log_path = str(_saved.transaction_path)
	PlayerState.active_profile_id = str(_saved.active_profile_id)
	PlayerState.character_name = str(_saved.character_name)
	PlayerState.warehouse_inventory = (_saved.warehouse_inventory as Array).duplicate(true)
	PlayerState.inventory = (_saved.inventory as Array).duplicate(true)
	PlayerState.test_mode = bool(_saved.test_mode)
	PlayerState._shared_warehouse_initialized = bool(_saved.initialized)
	PlayerState._warehouse_transaction_locked = bool(_saved.locked)
	PlayerState._persistence_transaction_in_progress = bool(_saved.in_progress)
	PlayerState._test_force_atomic_write_failure = bool(_saved.force_failure)
	PlayerState._test_fail_shared_write = bool(_saved.shared_failure)
	PlayerState._test_fail_profile_write = bool(_saved.profile_failure)
	PlayerState._test_fail_warehouse_rollback_write = bool(_saved.rollback_failure)
