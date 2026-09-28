class_name EquipmentEnhancementBlackIron
extends RefCounted

const CONTRACT_ID := "equipment.enhancement.black_iron.v1"
const AUTHORITY_PATH := "res://assets/data/equipment_enhancement_black_iron_v1.json"

static var _by_id: Dictionary = {}
static var _load_attempted := false


static func records() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for item_id: int in _by_id.keys():
		result.append((_by_id[item_id] as Dictionary).duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.itemId) < int(b.itemId))
	return result


static func record_for_id(item_id: int) -> Dictionary:
	_ensure_loaded()
	var record: Variant = _by_id.get(item_id, {})
	return (record as Dictionary).duplicate(true) if record is Dictionary else {}


static func purity_for(item_ref: Dictionary) -> int:
	var item_id := int(item_ref.get("item_id", item_ref.get("itemId", -1)))
	var record := record_for_id(item_id)
	return int(record.get("purity", -1)) if str(item_ref.get("name", "")) == "黑铁矿" else -1


static func _ensure_loaded() -> void:
	if _load_attempted:
		return
	_load_attempted = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AUTHORITY_PATH))
	if not parsed is Dictionary or str(parsed.get("contract_id", "")) != CONTRACT_ID:
		return
	var minimum := int(parsed.get("min_purity", -1))
	var maximum := int(parsed.get("max_purity", -1))
	var base := int(parsed.get("item_id_base", -1))
	var icon := str(parsed.get("inventory_icon", ""))
	if (
		minimum != 10 or maximum != 20 or base <= 0 or not ResourceLoader.exists(icon)
		or str(parsed.get("name", "")) != "黑铁矿"
		or str(parsed.get("kind", "")) != "material"
		or str(parsed.get("category", "")) != "矿石"
		or int(parsed.get("weight", -1)) != 1
	):
		return
	for purity in range(minimum, maximum + 1):
		var item_id := base + purity
		_by_id[item_id] = {
			"itemId": item_id,
			"name": str(parsed.name),
			"kind": str(parsed.kind),
			"category": str(parsed.category),
			"purity": purity,
			"stackable": false,
			"maxStack": 1,
			"weight": int(parsed.weight),
			"description": str(parsed.note),
			"useEffect": "none",
			"usable": false,
			"art": {"inventoryIcon": {"path": icon}},
			"source": {"contract_id": CONTRACT_ID},
		}
