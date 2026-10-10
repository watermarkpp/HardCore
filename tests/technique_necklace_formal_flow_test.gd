extends Node

const ItemDropInstanceRulesScript := preload("res://scripts/item_drop_instance_rules.gd")
const RandomSpecialRules := preload("res://scripts/equipment_random_special_instance_rules.gd")
const ROOT := "user://technique_necklace_formal_flow"
const PASS_MARKER := "TECHNIQUE_NECKLACE_FORMAL_FLOW_PASS"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GameData.ensure_loaded()
	_configure_isolated_storage()
	var catalog := GameData.get_item_record({"item_id": 250})
	_check(int(catalog.get("itemId", -1)) == 250, "canonical catalog item 250 missing")
	_check(str(catalog.get("kind", "")) == "equipment", "item 250 is not equipment")
	if catalog.is_empty():
		_finish()
		return

	var identity := _identity_record(catalog)
	var source_record := PlayerState.create_drop_item_instance(identity, "formal:technique-necklace:001")
	var instance: Dictionary = source_record.get("item_instance", {})
	_check(not instance.is_empty(), "PlayerState drop source did not construct an instance")
	if instance.is_empty():
		_finish()
		return
	_check(str(instance.get("drop_rules_contract_id", "")) in ["item.drop.affix.rules.v3", "item.drop.affix.rules.v4"], "formal flow did not use DropV3/V4 source")
	_check(ItemDropInstanceRulesScript.validate_instance(instance, catalog), "ItemDropInstanceRules rejected DropV3/V4 instance")
	_check(GameData.validate_item_drop_instance(instance), "GameData rejected DropV3/V4 instance")
	var roll: Dictionary = instance.get("technique_roll", {})
	var skill_id := str(roll.get("skill_id", ""))
	_check(not skill_id.is_empty(), "technique roll has no stable skill id")
	_check(int(roll.get("value", 0)) == 1, "technique roll is not +1")
	_check(_strict_technique_modifier(instance, skill_id), "technique modifier is not strict skill_level +1")

	var json_copy: Variant = JSON.parse_string(JSON.stringify(instance))
	_check(json_copy is Dictionary, "JSON roundtrip did not produce a dictionary")
	if json_copy is Dictionary:
		_check(ItemDropInstanceRulesScript.validate_instance(json_copy, catalog), "JSON roundtrip failed ItemDrop validation")
		_check(GameData.validate_item_drop_instance(json_copy), "JSON roundtrip failed GameData validation")
		_check(_instance_signature(json_copy as Dictionary) == _instance_signature(instance), "JSON roundtrip changed frozen instance")

	# A valid worn instance must never teach an unlearned skill.
	_reset_runtime()
	_check(not PlayerState.is_skill_learned(skill_id), "fixture unexpectedly learned rolled skill")
	var unlearned_before := PlayerState.effective_skill_level(skill_id)
	_check(unlearned_before == 0, "unlearned skill had a nonzero base rank")
	_check(_receive_and_equip(instance), "unlearned formal instance could not be equipped")
	_check(PlayerState.effective_skill_level(skill_id) == 0, "necklace taught an unlearned skill")

	# Use the real progression service to seed one learned rank, then equip the same
	# frozen instance.  The equipment bonus may extend rank, but cannot mutate the
	# progression snapshot itself.
	_reset_runtime()
	var learned_snapshot := {
		"contract_id": "skills.progression.hardcore.v3",
		"skills": {skill_id: {"base_rank": 1, "rank": 1}},
	}
	var loaded: Dictionary = PlayerState._skill_progression.load_snapshot(learned_snapshot)
	_check(bool(loaded.get("success", false)), "real skill progression rejected learned fixture")
	PlayerState._refresh_skill_identity_projection()
	PlayerState.recalculate_stats(false)
	var base_rank := PlayerState.effective_skill_level(skill_id)
	_check(base_rank == 1, "learned fixture did not expose rank 1")
	var learned_before: Dictionary = PlayerState._skill_progression.snapshot()
	_check(_receive_and_equip(instance), "learned formal instance could not be equipped")
	_check(PlayerState.effective_skill_level(skill_id) == base_rank + 1, "necklace did not add exactly one effective rank")
	_check(PlayerState._skill_progression.snapshot() == learned_before, "equipment bonus mutated learned progression")

	var equipped: Dictionary = PlayerState.equipment.get("hc.slot.necklace", {})
	PlayerState.damage_equipment_durability("hc.slot.necklace", int(equipped.get("max_durability", 1)))
	var frozen_signature := _instance_signature(PlayerState.equipment["hc.slot.necklace"])
	_check(PlayerState.effective_skill_level(skill_id) == base_rank, "zero durability did not remove necklace bonus")
	_check(int(PlayerState.equipment["hc.slot.necklace"].get("durability_raw", 0)) == 0, "necklace durability did not reach zero")

	_check(PlayerState.save_game(false, false, false), "formal equipment save failed")
	PlayerState.load_save()
	_check(bool(PlayerState.last_load_result.get("success", false)), "formal equipment reload failed")
	var reloaded: Dictionary = PlayerState.equipment.get("hc.slot.necklace", {})
	_check(_instance_signature(reloaded) == frozen_signature, "reload rerolled or changed necklace instance")
	_check(PlayerState.effective_skill_level(skill_id) == base_rank, "reload restored a broken necklace bonus")

	_finish()


func _reset_runtime() -> void:
	PlayerState.active_profile_id = "formal"
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "战士"
	PlayerState.recalculate_stats(false)


func _receive_and_equip(instance: Dictionary) -> bool:
	var received := PlayerState.receive_record(instance, false)
	if not bool(received.get("success", false)):
		_failures.append("receive_record failed: %s" % str(received))
		return false
	var index := -1
	for i in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[i].get("instance_id", "")) == str(instance.get("instance_id", "")):
			index = i
			break
	if index < 0:
		_failures.append("received instance was not in inventory")
		return false
	var equipped := PlayerState.equip_inventory_index_result(index, "hc.slot.necklace", str(instance.get("instance_id", "")))
	if not bool(equipped.get("success", false)):
		_failures.append("equip failed: %s" % str(equipped))
		return false
	return true


func _strict_technique_modifier(instance: Dictionary, skill_id: String) -> bool:
	var expected := {"stat": "skill_level", "op": "add", "scope": "skill:" + skill_id, "value": 1}
	var generated: Array = RandomSpecialRules.technique_skill_level_modifiers(instance)
	return generated.size() == 1 and generated[0] == expected


func _identity_record(catalog: Dictionary) -> Dictionary:
	var item_id := int(catalog.get("itemId", -1))
	var item_name := str(catalog.get("name", ""))
	return {
		"item_id": item_id, "canonical_item_id": item_id, "canonical_name": item_name,
		"source_item_id": item_id, "source_canonical_item_id": item_id,
		"source_canonical_name": item_name, "item_name": item_name, "name": item_name,
		"output_item_id": item_id, "output_record": catalog.duplicate(true), "identity_status": "resolved",
	}


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
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print(PASS_MARKER)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("TECHNIQUE_NECKLACE_FORMAL_FLOW_FAIL failures=%d" % _failures.size())
		get_tree().quit(1)


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
	PlayerState.active_profile_id = "formal"
	PlayerState.character_name = "FormalTechnique"
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "战士"
	PlayerState.recalculate_stats(false)
	PlayerState._write_json_atomic(PlayerState.profile_index_path, {"version": 1, "profiles": [{"id": "formal", "name": "FormalTechnique", "profession": "战士", "gender": "男", "level": 50}]})
	PlayerState._write_json_atomic(PlayerState._profile_path("formal"), {"profile_id": "formal", "character_name": "FormalTechnique", "level": 50, "profession": "战士", "gender": "男", "inventory": [], "equipment": {}})
	PlayerState._write_json_atomic(PlayerState.shared_warehouse_path, {"schema_version": PlayerState.SHARED_WAREHOUSE_SCHEMA_VERSION, "contract_id": PlayerState.SHARED_WAREHOUSE_CONTRACT_ID, "revision": 1, "warehouse_inventory": [], "legacy_migration": {"completed": true, "contract_id": PlayerState.SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID, "sources": {}}})
	PlayerState._shared_warehouse_initialized = true
	PlayerState.inventory = []
	PlayerState.warehouse_inventory = []
	PlayerState.equipment = PlayerState._empty_equipment()
	PlayerState.test_mode = false
