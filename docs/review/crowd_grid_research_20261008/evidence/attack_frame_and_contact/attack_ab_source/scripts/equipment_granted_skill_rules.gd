extends RefCounted

const PATH := "res://assets/data/equipment_granted_skills.source.json"
const CONTRACT_ID := "equipment.granted_skills.source.v1"

static var _records_by_skill: Dictionary = {}
static var _records_by_item: Dictionary = {}
static var _records_by_display_name: Dictionary = {}
static var _loaded := false
static var last_errors: Array[String] = []

static func ensure_loaded() -> bool:
	if _loaded:
		return last_errors.is_empty()
	_loaded = true
	var file := FileAccess.open(PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not parsed is Dictionary or str(parsed.get("contract_id", "")) != CONTRACT_ID:
		last_errors = ["invalid_equipment_granted_skill_source"]
		return false
	var seen_items := {}
	for raw: Variant in parsed.get("records", []):
		if not raw is Dictionary:
			last_errors.append("record_not_dictionary")
			continue
		var record := (raw as Dictionary).duplicate(true)
		var skill_id := str(record.get("skill_id", ""))
		var item_id := int(record.get("item_id", -1))
		if not skill_id.begins_with("hc.skill.equipment.") or item_id < 0:
			last_errors.append("invalid_granted_identity:%s" % skill_id)
			continue
		if _records_by_skill.has(skill_id) or seen_items.has(item_id):
			last_errors.append("duplicate_granted_identity:%s" % skill_id)
			continue
		if str(record.get("activation", "")) != "click":
			last_errors.append("invalid_granted_activation:%s" % skill_id)
			continue
		if int(record.get("mana_cost", -1)) < 0:
			last_errors.append("invalid_granted_mana:%s" % skill_id)
			continue
		record["equipment_granted"] = true
		_records_by_skill[skill_id] = record
		_records_by_item[item_id] = record
		var display_name := str(record.get("display_name", ""))
		if not display_name.is_empty():
			_records_by_display_name[display_name] = record
		seen_items[item_id] = true
	return last_errors.is_empty()

static func grant_definitions() -> Array[Dictionary]:
	ensure_loaded()
	var result: Array[Dictionary] = []
	for record: Variant in _records_by_skill.values():
		result.append((record as Dictionary).duplicate(true))
	return result

static func definition(skill_id: String) -> Dictionary:
	ensure_loaded()
	if not _records_by_skill.has(skill_id) and skill_id.begins_with("equipment."):
		skill_id = "hc.skill." + skill_id
	if not _records_by_skill.has(skill_id):
		var display_record: Dictionary = _records_by_display_name.get(skill_id, {}) as Dictionary
		skill_id = str(display_record.get("skill_id", ""))
	return (_records_by_skill.get(skill_id, {}) as Dictionary).duplicate(true)

static func definition_for_item(item_id: int) -> Dictionary:
	ensure_loaded()
	return (_records_by_item.get(item_id, {}) as Dictionary).duplicate(true)

static func skill_id_for_item(item_id: int) -> String:
	return str(definition_for_item(item_id).get("skill_id", ""))

static func item_id_for_skill(skill_id: String) -> int:
	return int(definition(skill_id).get("item_id", -1))

static func effect_id_for_skill(skill_id: String) -> String:
	return str(definition(skill_id).get("effect_id", ""))
