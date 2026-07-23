class_name EquipmentTestLoadoutCatalog
extends RefCounted

const CONTRACT_ID := "equipment.test_loadouts.classic_three_tiers.v1"
const CATALOG_PATH := "res://assets/data/equipment_test_loadouts.json"
const REQUIRED_SLOTS: Array[String] = [
	"武器",
	"衣服",
	"头盔",
	"项链",
	"左手镯",
	"右手镯",
	"左戒指",
	"右戒指",
]
const PROFESSIONS: Array[String] = ["战士", "法师", "道士"]
const TIERS: Array[String] = ["wooma", "zuma", "chiyue"]


static func load_catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	return parsed if parsed is Dictionary else {}


static func loadouts() -> Array:
	var catalog := load_catalog()
	var records: Variant = catalog.get("loadouts", [])
	return records if records is Array else []


static func get_loadout(profession: String, tier_id: String) -> Dictionary:
	for value: Variant in loadouts():
		if not value is Dictionary:
			continue
		if str(value.get("profession", "")) == profession and str(value.get("tierId", "")) == tier_id:
			return value.duplicate(true)
	return {}


static func equipment_names(loadout: Dictionary) -> Dictionary:
	var result := {}
	var equipment: Variant = loadout.get("equipment", {})
	if not equipment is Dictionary:
		return result
	for slot: String in REQUIRED_SLOTS:
		var entry: Variant = equipment.get(slot, {})
		if entry is Dictionary:
			result[slot] = str(entry.get("itemName", ""))
	return result
