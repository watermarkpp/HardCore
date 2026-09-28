class_name AncientRelicFragment
extends RefCounted

const CONTRACT_ID := "item.ancient_relic_fragment.v1"
const AUTHORITY_PATH := "res://assets/data/ancient_relic_fragment_v1.json"
const ITEM_ID := 950001
const ITEM_NAME := "远古圣物碎片"

static var _record: Dictionary = {}
static var _load_attempted := false


static func record() -> Dictionary:
	_ensure_loaded()
	return _record.duplicate(true)


static func is_item(item: Dictionary) -> bool:
	return int(item.get("itemId", item.get("item_id", -1))) == ITEM_ID and str(item.get("name", "")) == ITEM_NAME


static func _ensure_loaded() -> void:
	if _load_attempted:
		return
	_load_attempted = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AUTHORITY_PATH))
	if not parsed is Dictionary or str(parsed.get("contract_id", "")) != CONTRACT_ID:
		return
	var inventory_icon := str(parsed.get("inventory_icon", ""))
	var ground_icon := str(parsed.get("ground_icon", ""))
	if (
		int(parsed.get("item_id", -1)) != ITEM_ID
		or str(parsed.get("name", "")) != ITEM_NAME
		or str(parsed.get("kind", "")) != "material"
		or str(parsed.get("category", "")) != "材料"
		or int(parsed.get("weight", -1)) != 1
		or bool(parsed.get("stackable", true))
		or int(parsed.get("max_stack", -1)) != 1
		or inventory_icon.is_empty() or ground_icon.is_empty()
		or not ResourceLoader.exists(inventory_icon) or not ResourceLoader.exists(ground_icon)
	):
		return
	_record = {
		"itemId": ITEM_ID,
		"name": ITEM_NAME,
		"kind": "material",
		"category": "材料",
		"stackable": false,
		"maxStack": 1,
		"weight": 1,
		"description": str(parsed.get("note", "")),
		"useEffect": "none",
		"usable": false,
		"art": {
			"inventoryIcon": {"path": inventory_icon, "displaySize": [56, 56]},
			"groundIcon": {"path": ground_icon, "displaySize": [36, 36]},
		},
		"source": {
			"contract_id": CONTRACT_ID,
			"distribution": "user.provided",
			"art_source_sha256": str(parsed.get("art_source_sha256", "")),
		},
	}
