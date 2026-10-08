extends Node

const ItemDropInstanceRulesScript := preload("res://scripts/item_drop_instance_rules.gd")
const MysteryRules := preload("res://scripts/mystery_equipment_instance_rules.gd")
const Detail := preload("res://scripts/item_detail_presenter.gd")
const ROOT := "user://mystery_equipment_formal_flow"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GameData.ensure_loaded()
	_configure_isolated_storage()
	_run_requirement_priority_cases()
	for item_id: int in [218, 219, 220]:
		_run_item(item_id)
	_finish()


func _run_item(item_id: int) -> void:
	var catalog := GameData.get_item_record({"item_id": item_id})
	_check(int(catalog.get("itemId", -1)) == item_id, "canonical item missing: %d" % item_id)
	_check(MysteryRules.is_mystery_item(catalog), "canonical item is not mystery: %d" % item_id)
	if catalog.is_empty():
		return
	var identity := _identity_record(catalog)
	var source_record: Dictionary = {}
	var instance: Dictionary = {}
	for attempt in range(200):
		source_record = PlayerState.create_drop_item_instance(identity, "formal:mystery:%d:%d" % [item_id, attempt])
		instance = source_record.get("item_instance", {})
		var requirement := MysteryRules.requirement(instance)
		if not instance.is_empty() and str(requirement.get("type", "")) == "level" and int(requirement.get("value", 999)) <= 50:
			break
	_check(not instance.is_empty(), "formal mystery instance construction failed: %d" % item_id)
	if instance.is_empty():
		return
	_check(ItemDropInstanceRulesScript.validate_instance(instance, catalog), "ItemDrop validation failed: %d" % item_id)
	_check(GameData.validate_item_drop_instance(instance), "GameData validation failed: %d" % item_id)
	var roundtrip: Variant = JSON.parse_string(JSON.stringify(instance))
	_check(roundtrip is Dictionary and GameData.validate_item_drop_instance(roundtrip), "JSON save codec changed mystery instance: %d" % item_id)
	_check(_instance_signature(roundtrip as Dictionary) == _instance_signature(instance), "JSON roundtrip rerolled mystery instance: %d" % item_id)

	var requirement := MysteryRules.requirement(instance)
	_check(not requirement.is_empty(), "mystery requirement missing: %d" % item_id)
	var detail := Detail.format_item(catalog, instance)
	_check("穿戴要求" in detail, "formatter omitted mystery requirement: %d" % item_id)
	for modifier: Dictionary in MysteryRules.modifiers(instance):
		_check(_formatter_mentions_stat(detail, str(modifier.get("stat", ""))), "formatter omitted mystery stat: %d" % item_id)

	# The generated roll is level-legal at 50; the same real equip path must
	# reject it when the character is below that canonical requirement.
	_reset_runtime()
	PlayerState.level = 1
	PlayerState.recalculate_stats(false)
	var low_receive := PlayerState.receive_record(instance, false)
	_check(bool(low_receive.get("success", false)), "low-level fixture could not receive mystery instance: %d" % item_id)
	if bool(low_receive.get("success", false)):
		for low_index in range(PlayerState.inventory.size()):
			if str(PlayerState.inventory[low_index].get("instance_id", "")) == str(instance.get("instance_id", "")):
				var rejected := PlayerState.equip_inventory_index_result(low_index, _slot_for_item(item_id), str(instance.get("instance_id", "")))
				_check(not bool(rejected.get("success", false)), "below-requirement mystery equip was accepted: %d" % item_id)
				break

	_reset_runtime()
	var baseline := PlayerState.computed_stats.duplicate(true)
	_check(_receive_and_equip(instance), "real mystery equip failed: %d" % item_id)
	var expected_delta := _expected_delta(catalog, instance)
	for stat: String in expected_delta:
		_check(int(PlayerState.computed_stats.get(stat, 0)) - int(baseline.get(stat, 0)) == int(expected_delta[stat]), "mystery stat delta mismatch %d %s" % [item_id, stat])

	var equipped: Dictionary = PlayerState.equipment.get(_slot_for_item(item_id), {})
	PlayerState.damage_equipment_durability(_slot_for_item(item_id), int(equipped.get("max_durability", 1)))
	var frozen := _instance_signature(PlayerState.equipment.get(_slot_for_item(item_id), {}) as Dictionary)
	for stat: String in expected_delta:
		_check(int(PlayerState.computed_stats.get(stat, 0)) == int(baseline.get(stat, 0)), "zero durability retained mystery stat %d %s" % [item_id, stat])
	_check(PlayerState.save_game(false, false, false), "mystery save failed: %d" % item_id)
	PlayerState.load_save()
	_check(bool(PlayerState.last_load_result.get("success", false)), "mystery load failed: %d" % item_id)
	_check(_instance_signature(PlayerState.equipment.get(_slot_for_item(item_id), {}) as Dictionary) == frozen, "mystery load rerolled instance: %d" % item_id)
	var unequipped := PlayerState.unequip_slot(_slot_for_item(item_id))
	_check(unequipped.begins_with("已卸下"), "mystery unequip failed: %d" % item_id)
	_check(PlayerState.equipment.get(_slot_for_item(item_id), {}).is_empty(), "mystery slot remained occupied: %d" % item_id)
	for record: Variant in PlayerState.inventory:
		if record is Dictionary and str(record.get("instance_id", "")) == str(frozen.get("instance_id", "")):
			_check(not record.has("weapon_curse"), "mystery unequip introduced weapon curse: %d" % item_id)


func _slot_for_item(item_id: int) -> String:
	return "hc.slot.helmet" if item_id == 218 else ("hc.slot.bracelet_left" if item_id == 219 else "hc.slot.ring_left")


func _run_requirement_priority_cases() -> void:
	var helmet := {"itemId": 218, "requirementValue": 18}
	_check(_requirement_case(helmet, "helmet", {}) == {"type": "level", "value": 18}, "helmet default source requirement changed")
	_check(_requirement_case(helmet, "helmet", {"defense_max": 5, "attack_max": 2}) == {"type": "attack", "value": 40}, "helmet AC priority formula changed")
	_check(_requirement_case(helmet, "helmet", {"magic_max": 2, "attack_max": 1}) == {"type": "magic", "value": 22}, "helmet MC priority formula changed")
	_check(_requirement_case(helmet, "helmet", {"tao_max": 2, "attack_max": 1}) == {"type": "tao", "value": 22}, "helmet SC priority formula changed")
	var ring := {"itemId": 220, "requirementValue": 18}
	_check(_requirement_case(ring, "ring", {"attack_max": 3}) == {"type": "attack", "value": 34}, "ring DC formula changed")
	_check(_requirement_case(ring, "ring", {"magic_max": 3}) == {"type": "magic", "value": 24}, "ring MC formula changed")
	_check(_requirement_case(ring, "ring", {"tao_max": 3}) == {"type": "tao", "value": 24}, "ring SC formula changed")
	var bracelet := {"itemId": 219, "requirementValue": 18}
	_check(_requirement_case(bracelet, "bracelet", {"defense_max": 3}) == {"type": "attack", "value": 34}, "bracelet AC priority formula changed")
	_check(_requirement_case(bracelet, "bracelet", {"attack_max": 2}) == {"type": "attack", "value": 36}, "bracelet DC priority formula changed")
	_check(_requirement_case(bracelet, "bracelet", {"magic_max": 2}) == {"type": "magic", "value": 24}, "bracelet MC priority formula changed")
	_check(_requirement_case(bracelet, "bracelet", {"tao_max": 2}) == {"type": "tao", "value": 24}, "bracelet SC priority formula changed")
	_check(_requirement_case(bracelet, "bracelet", {"attack_max": 1, "magic_max": 1}) == {"type": "level", "value": 22}, "bracelet level threshold formula changed")


func _requirement_case(catalog: Dictionary, family: String, overrides: Dictionary) -> Dictionary:
	var stats := {"defense_max": 0, "magic_defense_max": 0, "attack_max": 0, "magic_max": 0, "tao_max": 0}
	for key: String in overrides:
		stats[key] = int(overrides[key])
	return MysteryRules._requirement(catalog, family, stats)


func _reset_runtime() -> void:
	PlayerState.active_profile_id = "formal"
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "战士"
	PlayerState.recalculate_stats(false)


func _receive_and_equip(instance: Dictionary) -> bool:
	var received := PlayerState.receive_record(instance, false)
	if not bool(received.get("success", false)):
		_failures.append("receive_record: %s" % str(received))
		return false
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("instance_id", "")) == str(instance.get("instance_id", "")):
			var result := PlayerState.equip_inventory_index_result(index, _slot_for_item(int(instance.get("item_id", -1))), str(instance.get("instance_id", "")))
			if not bool(result.get("success", false)):
				_failures.append("equip: %s" % str(result))
				return false
			return true
	_failures.append("received mystery instance missing from inventory")
	return false


func _expected_delta(catalog: Dictionary, instance: Dictionary) -> Dictionary:
	var result := {"attack_min": _stat_value(catalog.get("attackMin", null)), "attack_max": _stat_value(catalog.get("attackMax", null)), "magic_min": _stat_value(catalog.get("magicMin", null)), "magic_max": _stat_value(catalog.get("magicMax", null)), "tao_min": _stat_value(catalog.get("taoMin", null)), "tao_max": _stat_value(catalog.get("taoMax", null)), "defense_min": _stat_value(catalog.get("defenseMin", null)), "defense_max": _stat_value(catalog.get("defenseMax", null)), "magic_defense_min": _stat_value(catalog.get("mdefMin", null)), "magic_defense_max": _stat_value(catalog.get("mdefMax", null))}
	for modifier: Dictionary in instance.get("modifiers", []):
		var stat := str(modifier.get("stat", ""))
		if result.has(stat): result[stat] = int(result[stat]) + int(modifier.get("value", 0))
	for modifier: Dictionary in MysteryRules.modifiers(instance):
		var stat := str(modifier.get("stat", ""))
		if result.has(stat): result[stat] = int(result[stat]) + int(modifier.get("value", 0))
	return result


func _stat_value(raw: Variant) -> int:
	return 0 if raw == null else int(raw)


func _formatter_mentions_stat(detail: String, stat: String) -> bool:
	return (stat in ["attack_min", "attack_max"] and "攻击" in detail) or (stat in ["magic_min", "magic_max"] and "魔法" in detail) or (stat in ["tao_min", "tao_max"] and "道术" in detail) or (stat in ["defense_min", "defense_max"] and "防御" in detail) or (stat in ["magic_defense_min", "magic_defense_max"] and "魔防" in detail)


func _identity_record(catalog: Dictionary) -> Dictionary:
	var item_id := int(catalog.get("itemId", -1))
	var item_name := str(catalog.get("name", ""))
	return {"item_id": item_id, "canonical_item_id": item_id, "canonical_name": item_name, "source_item_id": item_id, "source_canonical_item_id": item_id, "source_canonical_name": item_name, "item_name": item_name, "name": item_name, "output_item_id": item_id, "output_record": catalog.duplicate(true), "identity_status": "resolved"}


func _instance_signature(value: Dictionary) -> Dictionary:
	return _canonical_json(value) as Dictionary


func _canonical_json(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key: Variant in value.keys():
			result[key] = _canonical_json(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry: Variant in value:
			result.append(_canonical_json(entry))
		return result
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	return value


func _check(condition: bool, message: String) -> void:
	if not condition: _failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("MYSTERY_EQUIPMENT_FORMAL_FLOW_PASS")
		get_tree().quit(0)
	else:
		for failure in _failures: push_error(failure)
		print("MYSTERY_EQUIPMENT_FORMAL_FLOW_FAIL failures=%d" % _failures.size())
		get_tree().quit(1)


func _configure_isolated_storage() -> void:
	PlayerState.profile_directory = ROOT.path_join("characters")
	PlayerState.profile_index_path = ROOT.path_join("profiles.json")
	PlayerState.shared_warehouse_path = ROOT.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = ROOT.path_join("shared.transaction.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.test_mode = true
	PlayerState._shared_warehouse_initialized = false
	PlayerState.active_profile_id = "formal"
	PlayerState.character_name = "FormalMystery"
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "战士"
	PlayerState.recalculate_stats(false)
	PlayerState._write_json_atomic(PlayerState.profile_index_path, {"version": 1, "profiles": [{"id": "formal", "name": "FormalMystery", "profession": "战士", "gender": "男", "level": 50}]})
	PlayerState._write_json_atomic(PlayerState._profile_path("formal"), {"profile_id": "formal", "character_name": "FormalMystery", "level": 50, "profession": "战士", "gender": "男", "inventory": [], "equipment": {}})
	PlayerState._write_json_atomic(PlayerState.shared_warehouse_path, {"schema_version": PlayerState.SHARED_WAREHOUSE_SCHEMA_VERSION, "contract_id": PlayerState.SHARED_WAREHOUSE_CONTRACT_ID, "revision": 1, "warehouse_inventory": [], "legacy_migration": {"completed": true, "contract_id": PlayerState.SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID, "sources": {}}})
	PlayerState._shared_warehouse_initialized = true
	PlayerState.inventory = []
	PlayerState.equipment = PlayerState._empty_equipment()
	PlayerState.test_mode = false
