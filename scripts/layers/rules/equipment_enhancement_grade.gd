class_name EquipmentEnhancementGrade
extends RefCounted

const CONTRACT_ID := "equipment.enhancement.grade.v1"
const AUTHORITY_PATH := "res://assets/data/equipment_enhancement_grade_v1.json"
const ACCESSORY_CATEGORIES := ["戒指", "手镯", "项链"]

static var _loaded := false
static var _by_id: Dictionary = {}


static func record_for_id(item_id: int) -> Dictionary:
	_ensure_loaded()
	var record: Variant = _by_id.get(item_id, {})
	return (record as Dictionary).duplicate(true) if record is Dictionary else {}


static func grade_for_id(item_id: int) -> int:
	return int(record_for_id(item_id).get("material_grade", -1))


static func can_use_as_accessory_material(item_id: int) -> bool:
	return bool(record_for_id(item_id).get("accessory_material_eligible", false))


static func records() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for item_id: int in _by_id:
		result.append((_by_id[item_id] as Dictionary).duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.item_id) < int(b.item_id))
	return result


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AUTHORITY_PATH))
	if not parsed is Dictionary or str(parsed.get("contract_id", "")) != CONTRACT_ID:
		return
	var rows: Variant = parsed.get("records", null)
	if not rows is Array or rows.size() != 175:
		return
	var accepted: Dictionary = {}
	for raw: Variant in rows:
		if not raw is Dictionary:
			return
		var row: Dictionary = raw
		if row.size() != 5 or not _is_integer(row.get("item_id")) or not _is_integer(row.get("material_grade")) or not row.get("accessory_material_eligible") is bool:
			return
		var item_id := int(row.item_id)
		var grade := int(row.material_grade)
		var category := str(row.get("category", ""))
		if item_id <= 0 or grade < 0 or grade > 3 or str(row.get("name", "")).is_empty() or category.is_empty() or accepted.has(item_id):
			return
		if bool(row.accessory_material_eligible) and category not in ACCESSORY_CATEGORIES:
			return
		accepted[item_id] = row.duplicate(true)
	_by_id = accepted


static func _is_integer(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floorf(value))
