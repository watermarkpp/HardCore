extends Node

const EquipmentRules := preload("res://scripts/equipment_rules.gd")
const MysteryRules := preload("res://scripts/mystery_equipment_instance_rules.gd")
const SEARCH_LIMIT := 10000

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GameData.ensure_loaded()
	var catalog := GameData.get_item_record({"item_id": 220})
	_check(int(catalog.get("itemId", -1)) == 220, "canonical mystery ring 220 is unavailable")
	if catalog.is_empty():
		_finish()
		return
	var identity := _identity_record(catalog)
	var found := {"attack": {}, "magic": {}, "tao": {}}
	var attempts := 0
	for index in range(SEARCH_LIMIT):
		attempts = index + 1
		var source_record: Dictionary = PlayerState.create_drop_item_instance(identity, "wear-requirement:%d" % index)
		var instance: Dictionary = source_record.get("item_instance", {})
		if instance.is_empty() or not MysteryRules.validate_roll(instance, catalog):
			continue
		var generated := MysteryRules.requirement(instance)
		var type_id := str(generated.get("type", ""))
		if found.has(type_id) and (found[type_id] as Dictionary).is_empty():
			found[type_id] = instance.duplicate(true)
		if not (found["attack"] as Dictionary).is_empty() and not (found["magic"] as Dictionary).is_empty() and not (found["tao"] as Dictionary).is_empty():
			break
	for type_id: String in ["attack", "magic", "tao"]:
		var instance: Dictionary = found[type_id]
		_check(not instance.is_empty(), "no real generated %s requirement within %d seeds" % [type_id, attempts])
		if instance.is_empty():
			continue
		_check(MysteryRules.validate_roll(instance, catalog), "generated %s roll failed MysteryRules validation" % type_id)
		var requirement: Dictionary = EquipmentRules.requirement_for(catalog, instance)
		var expected_type: int = int({"attack": EquipmentRules.NEED_ATTACK, "magic": EquipmentRules.NEED_MAGIC, "tao": EquipmentRules.NEED_TAO}[type_id])
		_check(int(requirement.get("type", -1)) == int(expected_type), "generated %s mapped to wrong formal need type" % type_id)
		var required := int(requirement.get("value", 0))
		_check(required > 0, "%s requirement must be positive" % type_id)
		var stat_key: String = str({"attack": "attack_max", "magic": "magic_max", "tao": "tao_max"}[type_id])
		var below := {stat_key: maxi(0, required - 1)}
		var at_threshold := {stat_key: required}
		var below_error := EquipmentRules.requirement_error(catalog, 99, below, instance)
		var threshold_error := EquipmentRules.requirement_error(catalog, 99, at_threshold, instance)
		_check(not below_error.is_empty(), "%s below-threshold wear was accepted" % type_id)
		_check(threshold_error.is_empty(), "%s at-threshold wear was rejected" % type_id)
	_finish()


func _identity_record(catalog: Dictionary) -> Dictionary:
	var item_id := int(catalog.get("itemId", -1))
	var item_name := str(catalog.get("name", ""))
	return {"item_id": item_id, "canonical_item_id": item_id, "canonical_name": item_name, "source_item_id": item_id, "source_canonical_item_id": item_id, "source_canonical_name": item_name, "item_name": item_name, "name": item_name, "output_item_id": item_id, "output_record": catalog.duplicate(true), "identity_status": "resolved"}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("MYSTERY_EQUIPMENT_WEAR_REQUIREMENTS_PASS")
		get_tree().quit(0)
	else:
		for failure in _failures: push_error(failure)
		print("MYSTERY_EQUIPMENT_WEAR_REQUIREMENTS_FAIL failures=%d" % _failures.size())
		get_tree().quit(1)
