extends Node

const ItemDropInstanceRulesScript := preload("res://scripts/item_drop_instance_rules.gd")
const ROOT := "user://item_drop_instance_persistence"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded())
	_configure_isolated_storage()
	var catalog := GameData.get_item_record({"item_id": 80})
	var identity := _identity_record(catalog)
	var frozen_record := _find_affixed_record(identity, catalog)
	assert(not frozen_record.is_empty())
	var frozen_instance: Dictionary = frozen_record.item_instance.duplicate(true)
	var instance_id := str(frozen_instance.instance_id)

	var invalid_record := frozen_record.duplicate(true)
	invalid_record.item_instance["forged"] = true
	var inventory_before := PlayerState.inventory.duplicate(true)
	var invalid_pickup := PlayerState.receive_loot_batch_partial([invalid_record])
	assert(invalid_pickup.success_count == 0 and PlayerState.inventory == inventory_before)
	assert(str(invalid_pickup.outcomes[0].reason) == "invalid_item_instance")

	PlayerState.test_mode = true
	PlayerState._test_force_atomic_write_failure = true
	var failed := PlayerState.receive_loot_batch_partial([frozen_record])
	PlayerState._test_force_atomic_write_failure = false
	assert(not failed.success and PlayerState.inventory == inventory_before)
	PlayerState.test_mode = false
	var retried := frozen_record.duplicate(true)
	retried["item_name"] = "renamed-presentation-must-not-drive-identity"
	var retry_result := PlayerState.receive_loot_batch_partial([retried])
	assert(retry_result.success and retry_result.success_count == 1, str(retry_result))
	_assert_same_instance(PlayerState.inventory[0], frozen_instance, "pickup rebuilt the frozen ground instance")
	var saved_p := PlayerState._read_json(PlayerState._profile_path("p"))
	_assert_same_instance(saved_p.inventory[0], frozen_instance, "profile save changed the instance")

	var duplicate_before := PlayerState.inventory.duplicate(true)
	var duplicate := PlayerState.receive_loot_batch_partial([frozen_record])
	assert(duplicate.success_count == 0 and PlayerState.inventory == duplicate_before)
	assert(str(duplicate.outcomes[0].reason) == "duplicate_item_instance")
	var duplicate_record_receive := PlayerState.receive_record(frozen_instance, false)
	assert(not duplicate_record_receive.success)
	assert(str(duplicate_record_receive.reason) == "duplicate_item_instance", str(duplicate_record_receive))
	var forged_direct := frozen_instance.duplicate(true)
	forged_direct.modifiers[0]["value"] = 999
	var forged_record_receive := PlayerState.receive_record(forged_direct, false)
	assert(not forged_record_receive.success)
	assert(str(forged_record_receive.reason) == "invalid_item_instance")

	PlayerState.load_save()
	assert(PlayerState.last_load_result.success)
	_assert_same_instance(PlayerState.inventory[0], frozen_instance, "reload changed the instance")
	var legacy_result := PlayerState.receive_loot_batch_partial([{
		"item_id": 80,
		"item_name": "木剑",
	}])
	assert(legacy_result.success_count == 1, "legacy equipment pickup compatibility broke")
	assert(not PlayerState.inventory[1].has("drop_instance_contract_id"),
		"legacy pickup unexpectedly rolled a W7 affix")

	var deposit := PlayerState.deposit_to_warehouse(0, 0)
	assert(deposit.success, str(deposit))
	_assert_same_instance(PlayerState.warehouse_inventory[0], frozen_instance, "warehouse runtime changed the instance")
	var shared := PlayerState._read_json(PlayerState.shared_warehouse_path)
	_assert_same_instance(shared.warehouse_inventory[0], frozen_instance, "warehouse save changed the instance")

	_prepare_second_profile_from(saved_p)
	PlayerState.active_profile_id = "q"
	PlayerState.load_save()
	assert(PlayerState.last_load_result.success and PlayerState.inventory.is_empty())
	_assert_same_instance(PlayerState.warehouse_inventory[0], frozen_instance, "cross-profile warehouse load changed the instance")
	var withdraw := PlayerState.withdraw_from_warehouse(0)
	assert(withdraw.success, str(withdraw))
	_assert_same_instance(PlayerState.inventory[0], frozen_instance, "cross-profile withdrawal changed the instance")

	var base_instance := PlayerState._make_item_instance("木剑", catalog, 7001)
	PlayerState.equipment["武器"] = base_instance
	PlayerState.recalculate_stats(false)
	var catalog_only_attack_max := float(PlayerState.computed_stats.attack_max)
	PlayerState.equipment["武器"] = {}
	PlayerState.recalculate_stats(false)
	var equipped := PlayerState.equip_inventory_index_result(0, "武器", instance_id)
	assert(equipped.success, str(equipped))
	_assert_same_instance(PlayerState.equipment["武器"], frozen_instance, "equip changed the instance")
	assert(float(PlayerState.computed_stats.attack_max) == catalog_only_attack_max + 1.0,
		"the frozen modifiers Array was not consumed by real equipment aggregation")
	var saved_q := PlayerState._read_json(PlayerState._profile_path("q"))
	_assert_same_instance(saved_q.equipment["武器"], frozen_instance, "equipped save changed the instance")
	PlayerState.load_save()
	assert(PlayerState.last_load_result.success)
	_assert_same_instance(PlayerState.equipment["武器"], frozen_instance, "equipped instance changed after reload")
	assert(float(PlayerState.computed_stats.attack_max) == catalog_only_attack_max + 1.0)

	var duplicate_document := PlayerState._read_json(PlayerState._profile_path("q"))
	duplicate_document["inventory"] = [frozen_instance.duplicate(true)]
	assert(not bool(PlayerState._validate_profile_document_status(
		duplicate_document,
		"q",
		false,
	).get("valid", false)), "duplicate persisted instance was accepted")
	var duplicate_shared := PlayerState._read_json(PlayerState.shared_warehouse_path)
	duplicate_shared["warehouse_inventory"] = [frozen_instance.duplicate(true)]
	assert(PlayerState._write_json_atomic(PlayerState.shared_warehouse_path, duplicate_shared))
	PlayerState.load_save()
	assert(not PlayerState.last_load_result.success)
	assert(str(PlayerState.last_load_result.reason) == "duplicate_drop_instance_across_shared",
		"profile/shared duplicate persisted instance was accepted")
	_cleanup()
	print("ITEM_DROP_INSTANCE_PERSISTENCE_TEST_PASS")
	get_tree().quit(0)


func _configure_isolated_storage() -> void:
	PlayerState.profile_directory = ROOT.path_join("characters")
	PlayerState.profile_index_path = ROOT.path_join("profiles.json")
	PlayerState.shared_warehouse_path = ROOT.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = ROOT.path_join("shared.transaction.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.test_mode = true
	PlayerState._test_force_atomic_write_failure = false
	PlayerState._warehouse_transaction_locked = false
	PlayerState._persistence_transaction_in_progress = false
	PlayerState._shared_warehouse_initialized = false
	PlayerState.active_profile_id = "p"
	PlayerState.character_name = "W7-P"
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "战士"
	PlayerState.recalculate_stats(false)
	assert(PlayerState._write_json_atomic(PlayerState.profile_index_path, {
		"version": 1,
		"profiles": [
			{"id": "p", "name": "W7-P", "profession": "战士", "gender": "男", "level": 50},
			{"id": "q", "name": "W7-Q", "profession": "战士", "gender": "男", "level": 50},
		],
	}))
	assert(PlayerState._write_json_atomic(PlayerState._profile_path("p"), {
		"profile_id": "p", "character_name": "W7-P", "level": 50,
		"profession": "战士", "gender": "男", "inventory": [], "equipment": {},
	}))
	assert(PlayerState._write_json_atomic(PlayerState._profile_path("q"), {
		"profile_id": "q", "character_name": "W7-Q", "level": 50,
		"profession": "战士", "gender": "男", "inventory": [], "equipment": {},
	}))
	assert(PlayerState._write_json_atomic(PlayerState.shared_warehouse_path, {
		"schema_version": PlayerState.SHARED_WAREHOUSE_SCHEMA_VERSION,
		"contract_id": PlayerState.SHARED_WAREHOUSE_CONTRACT_ID,
		"revision": 1,
		"warehouse_inventory": [],
		"legacy_migration": {
			"completed": true,
			"contract_id": PlayerState.SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID,
			"sources": {},
		},
	}))
	PlayerState._shared_warehouse_initialized = true
	PlayerState.inventory = []
	PlayerState.warehouse_inventory = []
	PlayerState.equipment = PlayerState._empty_equipment()
	PlayerState.test_mode = false


func _prepare_second_profile_from(template: Dictionary) -> void:
	var profile := template.duplicate(true)
	profile["profile_id"] = "q"
	profile["character_name"] = "W7-Q"
	profile["inventory"] = []
	profile["equipment"] = PlayerState._empty_equipment()
	assert(PlayerState._write_json_atomic(PlayerState._profile_path("q"), profile))


func _find_affixed_record(identity: Dictionary, catalog: Dictionary) -> Dictionary:
	for index in range(1000):
		var record := PlayerState.create_drop_item_instance(identity, "p:death-1:%d" % index)
		if ItemDropInstanceRulesScript.is_affixed_instance(record.get("item_instance", {}), catalog):
			return record
	return {}


func _identity_record(catalog: Dictionary) -> Dictionary:
	var item_id := int(catalog.get("itemId", -1))
	var item_name := str(catalog.get("name", ""))
	return {
		"item_id": item_id,
		"canonical_item_id": item_id,
		"canonical_name": item_name,
		"source_item_id": item_id,
		"source_canonical_item_id": item_id,
		"source_canonical_name": item_name,
		"item_name": item_name,
		"name": item_name,
		"output_item_id": item_id,
		"output_record": catalog.duplicate(true),
		"identity_status": "resolved",
	}


func _assert_same_instance(actual: Dictionary, expected: Dictionary, message: String) -> void:
	assert(_instance_signature(actual) == _instance_signature(expected), message)


func _instance_signature(instance: Dictionary) -> Dictionary:
	var modifiers: Array = []
	for raw_modifier: Variant in instance.get("modifiers", []):
		var modifier: Dictionary = raw_modifier
		modifiers.append({
			"stat": str(modifier.get("stat", "")),
			"op": str(modifier.get("op", "")),
			"value": int(modifier.get("value", 0)),
		})
	var raw_affix: Dictionary = instance.get("drop_affix", {})
	return {
		"drop_instance_contract_id": str(instance.get("drop_instance_contract_id", "")),
		"drop_rules_contract_id": str(instance.get("drop_rules_contract_id", "")),
		"drop_key_digest": str(instance.get("drop_key_digest", "")),
		"item_id": int(instance.get("item_id", -1)),
		"name": str(instance.get("name", "")),
		"count": int(instance.get("count", -1)),
		"instance_id": str(instance.get("instance_id", "")),
		"durability": int(instance.get("durability", -1)),
		"max_durability": int(instance.get("max_durability", -1)),
		"durability_raw": int(instance.get("durability_raw", -1)),
		"max_durability_raw": int(instance.get("max_durability_raw", -1)),
		"durability_contract_id": str(instance.get("durability_contract_id", "")),
		"weapon_luck": int(instance.get("weapon_luck", -1)),
		"weapon_curse": int(instance.get("weapon_curse", -1)),
		"modifiers": modifiers,
		"drop_affix": {
			"contract_id": str(raw_affix.get("contract_id", "")),
			"applied": bool(raw_affix.get("applied", false)),
			"source_stat": str(raw_affix.get("source_stat", "")),
			"stat": str(raw_affix.get("stat", "")),
			"op": str(raw_affix.get("op", "")),
			"value": int(raw_affix.get("value", 0)),
		},
	}


func _cleanup() -> void:
	for base_path: String in [
		PlayerState.profile_index_path,
		PlayerState.shared_warehouse_path,
		PlayerState.shared_warehouse_transaction_log_path,
		PlayerState._profile_path("p"),
		PlayerState._profile_path("q"),
	]:
		for suffix: String in ["", ".bak", ".tmp", ".corrupt.tmp"]:
			var path := base_path + suffix
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(ROOT)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOT))
