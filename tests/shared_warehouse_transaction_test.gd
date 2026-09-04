extends Node

const ROOT_PREFIX := "user://shared_warehouse_transaction_isolated"

var _root := ""
var _profile := ""
var _other_profile := ""
var _saved: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_capture_player_state()
	_root = "%s_%d" % [ROOT_PREFIX, Time.get_ticks_usec()]
	PlayerState.profile_directory = _root.path_join("characters")
	PlayerState.profile_index_path = _root.path_join("index.json")
	PlayerState.shared_warehouse_path = _root.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = _root.path_join("shared.transaction.json")
	_profile = PlayerState.profile_directory.path_join("p.json")
	_other_profile = PlayerState.profile_directory.path_join("q.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.test_mode = true
	PlayerState._test_force_atomic_write_failure = false
	PlayerState._test_fail_profile_write = false
	PlayerState._test_fail_shared_write = false
	PlayerState._test_fail_warehouse_rollback_write = false
	_write_index()
	assert(PlayerState._write_json_atomic(_other_profile, {"profile_id": "q", "inventory": [_item("q-safe")]}))
	_test_successful_deposit_and_withdraw()
	_test_sparse_batch_deposit_and_withdraw()
	_test_batch_write_failure_rolls_back_every_item()
	_test_precise_write_failures_rollback()
	_test_prepared_log_recovery_without_active_profile_coupling()
	_restore_player_state()
	print("SHARED_WAREHOUSE_TRANSACTION_TEST_PASS")
	get_tree().quit()


func _test_successful_deposit_and_withdraw() -> void:
	_reset_documents("success")
	var result := PlayerState.deposit_to_warehouse(0, 0)
	assert(bool(result.get("success", false)), str(result))
	assert(PlayerState.inventory.is_empty())
	assert(_instance_ids(PlayerState._read_json(PlayerState.shared_warehouse_path).get("warehouse_inventory", [])) == ["success"])
	assert((PlayerState._read_json(_profile).get("inventory", []) as Array).is_empty())
	assert(not FileAccess.file_exists(PlayerState.shared_warehouse_transaction_log_path))
	result = PlayerState.withdraw_from_warehouse(0)
	assert(bool(result.get("success", false)), str(result))
	assert(PlayerState.inventory.size() == 1)
	assert(str(PlayerState.inventory[0].get("name", "")) == "太阳水" and int(PlayerState.inventory[0].get("count", 0)) == 1)
	assert((PlayerState._read_json(PlayerState.shared_warehouse_path).get("warehouse_inventory", []) as Array).is_empty())
	assert((PlayerState._read_json(_profile).get("inventory", []) as Array).size() == 1)


func _test_sparse_batch_deposit_and_withdraw() -> void:
	_reset_documents("batch-a")
	PlayerState.inventory = [_equipment_item("batch-a"), _equipment_item("batch-b"), _equipment_item("bag-safe")]
	PlayerState.warehouse_inventory = [_equipment_item("stash-existing")]
	assert(PlayerState._write_json_atomic(_profile, {"profile_id": "p", "inventory": PlayerState.inventory.duplicate(true)}))
	assert(PlayerState._write_json_atomic(PlayerState.shared_warehouse_path, _shared_document(PlayerState.warehouse_inventory)))
	var revision_before := int(PlayerState._read_json(PlayerState.shared_warehouse_path).get("revision", -1))
	var result := PlayerState.deposit_to_warehouse_batch([0, 1], [100, 101])
	assert(bool(result.get("success", false)) and bool(result.get("complete", false)), str(result))
	assert(int(result.get("transferred", -1)) == 2 and result.get("completed_source_indices", []) == [0, 1], str(result))
	assert(_instance_ids(PlayerState.inventory) == ["bag-safe"])
	assert(PlayerState.inventory.size() == 3 and PlayerState.inventory[0].is_empty() and PlayerState.inventory[1].is_empty())
	var stored_shared := PlayerState._read_json(PlayerState.shared_warehouse_path)
	assert(int(stored_shared.get("revision", -1)) == revision_before + 1, "批量存入不应逐件增加仓库版本")
	assert(PlayerState._validate_shared_warehouse_document(stored_shared), "含固定槽空洞的公共仓库文档无法重新载入")
	var stored_records: Array = stored_shared.get("warehouse_inventory", [])
	assert(stored_records.size() == 102 and (stored_records[1] as Dictionary).is_empty())
	assert(str(stored_records[100].get("instance_id", "")) == "batch-a" and str(stored_records[101].get("instance_id", "")) == "batch-b")
	assert(not FileAccess.file_exists(PlayerState.shared_warehouse_transaction_log_path))

	revision_before = int(stored_shared.get("revision", -1))
	result = PlayerState.withdraw_from_warehouse_batch([0, 100])
	assert(bool(result.get("success", false)) and bool(result.get("complete", false)), str(result))
	assert(int(result.get("transferred", -1)) == 2 and result.get("completed_warehouse_slots", []) == [0, 100], str(result))
	assert(_instance_ids(PlayerState.inventory) == ["stash-existing", "batch-a", "bag-safe"])
	stored_shared = PlayerState._read_json(PlayerState.shared_warehouse_path)
	assert(int(stored_shared.get("revision", -1)) == revision_before + 1, "批量取出不应逐件增加仓库版本")
	assert(PlayerState._validate_shared_warehouse_document(stored_shared), "非尾部取出后公共仓库文档失效")
	stored_records = stored_shared.get("warehouse_inventory", [])
	assert(stored_records.size() == 102 and (stored_records[0] as Dictionary).is_empty() and (stored_records[100] as Dictionary).is_empty())
	assert(str(stored_records[101].get("instance_id", "")) == "batch-b", "批量取出移动了未选择的固定槽物品")
	PlayerState._shared_warehouse_initialized = false
	PlayerState.warehouse_inventory = []
	assert(PlayerState._initialize_shared_warehouse(), "含合法空槽的批量仓库存档无法冷载入")
	assert(PlayerState.warehouse_inventory.size() == 102 and str(PlayerState.warehouse_inventory[101].get("instance_id", "")) == "batch-b")


func _test_batch_write_failure_rolls_back_every_item() -> void:
	_reset_documents("rollback-a")
	PlayerState.inventory = [_equipment_item("rollback-a"), _equipment_item("rollback-b")]
	assert(PlayerState._write_json_atomic(_profile, {"profile_id": "p", "inventory": PlayerState.inventory.duplicate(true)}))
	var profile_before := PlayerState._read_json(_profile)
	var shared_before := PlayerState._read_json(PlayerState.shared_warehouse_path)
	PlayerState._test_fail_profile_write = true
	var result := PlayerState.deposit_to_warehouse_batch([0, 1], [100, 101])
	PlayerState._test_fail_profile_write = false
	assert(not bool(result.get("success", false)) and int(result.get("transferred", -1)) == 0, str(result))
	assert(_instance_ids(PlayerState.inventory) == ["rollback-a", "rollback-b"])
	assert(PlayerState.warehouse_inventory.is_empty())
	assert(PlayerState._shared_digest(PlayerState._read_json(_profile)) == PlayerState._shared_digest(profile_before))
	assert(PlayerState._shared_digest(PlayerState._read_json(PlayerState.shared_warehouse_path)) == PlayerState._shared_digest(shared_before))
	assert(not FileAccess.file_exists(PlayerState.shared_warehouse_transaction_log_path))
	assert(not PlayerState._warehouse_transaction_locked)


func _test_precise_write_failures_rollback() -> void:
	for failure_kind: String in ["log", "shared", "profile"]:
		_reset_documents("fail-%s" % failure_kind)
		var profile_before := PlayerState._read_json(_profile)
		var shared_before := PlayerState._read_json(PlayerState.shared_warehouse_path)
		PlayerState._test_force_atomic_write_failure = failure_kind == "log"
		PlayerState._test_fail_shared_write = failure_kind == "shared"
		PlayerState._test_fail_profile_write = failure_kind == "profile"
		var result := PlayerState.deposit_to_warehouse(0, 0)
		PlayerState._test_force_atomic_write_failure = false
		PlayerState._test_fail_shared_write = false
		PlayerState._test_fail_profile_write = false
		assert(not bool(result.get("success", false)), "%s 写失败不应提交" % failure_kind)
		assert(_instance_ids(PlayerState.inventory) == ["fail-%s" % failure_kind])
		assert(PlayerState.warehouse_inventory.is_empty())
		assert(PlayerState._shared_digest(PlayerState._read_json(_profile)) == PlayerState._shared_digest(profile_before))
		assert(PlayerState._shared_digest(PlayerState._read_json(PlayerState.shared_warehouse_path)) == PlayerState._shared_digest(shared_before))
		assert(not FileAccess.file_exists(PlayerState.shared_warehouse_transaction_log_path))
		assert(not PlayerState._warehouse_transaction_locked)

	_reset_documents("recover-rollback")
	var before_profile := PlayerState._read_json(_profile)
	var before_shared := PlayerState._read_json(PlayerState.shared_warehouse_path)
	PlayerState._test_fail_profile_write = true
	PlayerState._test_fail_warehouse_rollback_write = true
	assert(not bool(PlayerState.deposit_to_warehouse(0, 0).get("success", false)))
	PlayerState._test_fail_profile_write = false
	PlayerState._test_fail_warehouse_rollback_write = false
	assert(PlayerState._warehouse_transaction_locked)
	assert(FileAccess.file_exists(PlayerState.shared_warehouse_transaction_log_path))
	PlayerState._recover_shared_warehouse_transaction()
	assert(not PlayerState._warehouse_transaction_locked)
	assert(not FileAccess.file_exists(PlayerState.shared_warehouse_transaction_log_path))
	assert(PlayerState._shared_digest(PlayerState._read_json(_profile)) == PlayerState._shared_digest(before_profile))
	assert(PlayerState._shared_digest(PlayerState._read_json(PlayerState.shared_warehouse_path)) == PlayerState._shared_digest(before_shared))


func _test_prepared_log_recovery_without_active_profile_coupling() -> void:
	_reset_documents("prepared")
	var before_profile := PlayerState._read_json(_profile)
	var before_shared := PlayerState._read_json(PlayerState.shared_warehouse_path)
	var after_profile := before_profile.duplicate(true)
	after_profile["inventory"] = []
	var after_shared := before_shared.duplicate(true)
	after_shared["revision"] = int(before_shared.get("revision", 0)) + 1
	after_shared["warehouse_inventory"] = [_item("prepared")]
	var prepared := _prepared_log(before_profile, after_profile, before_shared, after_shared)
	assert(PlayerState._write_json_atomic(_other_profile, {"profile_id": "q", "inventory": [_item("q-safe")]}))
	PlayerState.active_profile_id = "q"
	assert(PlayerState._write_json_atomic(PlayerState.shared_warehouse_path, after_shared))
	assert(PlayerState._write_json_atomic(PlayerState.shared_warehouse_transaction_log_path, prepared))
	PlayerState._recover_shared_warehouse_transaction()
	assert(PlayerState._shared_digest(PlayerState._read_json(_profile)) == PlayerState._shared_digest(before_profile))
	assert(PlayerState._shared_digest(PlayerState._read_json(PlayerState.shared_warehouse_path)) == PlayerState._shared_digest(before_shared))
	assert(_instance_ids(PlayerState._read_json(_other_profile).get("inventory", [])) == ["q-safe"])

	assert(PlayerState._write_json_atomic(_profile, after_profile))
	assert(PlayerState._write_json_atomic(PlayerState.shared_warehouse_path, after_shared))
	assert(PlayerState._write_json_atomic(PlayerState.shared_warehouse_transaction_log_path, prepared))
	PlayerState._recover_shared_warehouse_transaction()
	assert(PlayerState._shared_digest(PlayerState._read_json(_profile)) == PlayerState._shared_digest(after_profile))
	assert(PlayerState._shared_digest(PlayerState._read_json(PlayerState.shared_warehouse_path)) == PlayerState._shared_digest(after_shared))
	assert(_instance_ids(PlayerState._read_json(_other_profile).get("inventory", [])) == ["q-safe"])
	assert(not FileAccess.file_exists(PlayerState.shared_warehouse_transaction_log_path))


func _reset_documents(instance_id: String) -> void:
	PlayerState._warehouse_transaction_locked = false
	PlayerState._persistence_transaction_in_progress = false
	PlayerState._shared_warehouse_initialized = true
	PlayerState.active_profile_id = "p"
	PlayerState.inventory = [_item(instance_id)]
	PlayerState.warehouse_inventory = []
	assert(PlayerState._write_json_atomic(_profile, {"profile_id": "p", "inventory": [_item(instance_id)]}))
	assert(PlayerState._write_json_atomic(PlayerState.shared_warehouse_path, _shared_document([])))
	PlayerState._remove_persistence_file(PlayerState.shared_warehouse_transaction_log_path)


func _write_index() -> void:
	assert(PlayerState._write_json_atomic(PlayerState.profile_index_path, {"version": 1, "profiles": [
		{"id": "p", "name": "p", "profession": "战士", "gender": "男", "level": 1},
		{"id": "q", "name": "q", "profession": "战士", "gender": "男", "level": 1},
	]}))


func _shared_document(records: Array) -> Dictionary:
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


func _prepared_log(before_profile: Dictionary, after_profile: Dictionary, before_shared: Dictionary, after_shared: Dictionary) -> Dictionary:
	return {
		"contract_id": PlayerState.WAREHOUSE_TRANSFER_CONTRACT_ID,
		"state": "PREPARED", "profile_id": "p", "profile_path": _profile,
		"before_profile": before_profile, "after_profile": after_profile,
		"before_shared": before_shared, "after_shared": after_shared,
		"before_profile_hash": PlayerState._shared_digest(before_profile),
		"after_profile_hash": PlayerState._shared_digest(after_profile),
		"before_shared_hash": PlayerState._shared_digest(before_shared),
		"after_shared_hash": PlayerState._shared_digest(after_shared),
	}


func _item(instance_id: String) -> Dictionary:
	return {"name": "太阳水", "count": 1, "instance_id": instance_id}


func _equipment_item(instance_id: String) -> Dictionary:
	return {"name": "匕首", "count": 1, "instance_id": instance_id}


func _instance_ids(records: Array) -> Array:
	var result: Array = []
	for record: Variant in records:
		if record is Dictionary and not (record as Dictionary).is_empty():
			result.append(str((record as Dictionary).get("instance_id", "")))
	return result


func _capture_player_state() -> void:
	_saved = {
		"profile_directory": PlayerState.profile_directory, "profile_index_path": PlayerState.profile_index_path,
		"shared": PlayerState.shared_warehouse_path, "log": PlayerState.shared_warehouse_transaction_log_path,
		"active": PlayerState.active_profile_id, "inventory": PlayerState.inventory.duplicate(true),
		"warehouse": PlayerState.warehouse_inventory.duplicate(true), "test_mode": PlayerState.test_mode,
		"initialized": PlayerState._shared_warehouse_initialized, "locked": PlayerState._warehouse_transaction_locked,
		"in_progress": PlayerState._persistence_transaction_in_progress, "force": PlayerState._test_force_atomic_write_failure,
		"shared_fail": PlayerState._test_fail_shared_write, "profile_fail": PlayerState._test_fail_profile_write,
		"rollback_fail": PlayerState._test_fail_warehouse_rollback_write,
	}


func _restore_player_state() -> void:
	PlayerState.profile_directory = str(_saved.profile_directory)
	PlayerState.profile_index_path = str(_saved.profile_index_path)
	PlayerState.shared_warehouse_path = str(_saved.shared)
	PlayerState.shared_warehouse_transaction_log_path = str(_saved.log)
	PlayerState.active_profile_id = str(_saved.active)
	PlayerState.inventory = (_saved.inventory as Array).duplicate(true)
	PlayerState.warehouse_inventory = (_saved.warehouse as Array).duplicate(true)
	PlayerState.test_mode = bool(_saved.test_mode)
	PlayerState._shared_warehouse_initialized = bool(_saved.initialized)
	PlayerState._warehouse_transaction_locked = bool(_saved.locked)
	PlayerState._persistence_transaction_in_progress = bool(_saved.in_progress)
	PlayerState._test_force_atomic_write_failure = bool(_saved.force)
	PlayerState._test_fail_shared_write = bool(_saved.shared_fail)
	PlayerState._test_fail_profile_write = bool(_saved.profile_fail)
	PlayerState._test_fail_warehouse_rollback_write = bool(_saved.rollback_fail)
