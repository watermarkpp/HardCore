class_name EquipmentTestLoadoutCatalog
extends RefCounted

const CONTRACT_ID := "equipment.test_loadouts.classic_three_tiers.v1"
const CATALOG_PATH := "res://assets/data/equipment_test_loadouts.json"
const Slots := preload("res://scripts/identity/equipment_identity_codec.gd")
const REQUIRED_SLOTS: Array[String] = [
	"hc.slot.weapon",
	"hc.slot.armor",
	"hc.slot.helmet",
	"hc.slot.necklace",
	"hc.slot.bracelet_left",
	"hc.slot.bracelet_right",
	"hc.slot.ring_left",
	"hc.slot.ring_right",
]
const PROFESSIONS: Array[String] = ["战士", "法师", "道士"]
const TIERS: Array[String] = ["wooma", "zuma", "chiyue"]


static func load_catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not parsed is Dictionary or not parsed.get("supportedSlots") is Array or not parsed.get("loadouts") is Array:
		return {}
	# This authoring document retains its historical presentation metadata.
	# Translate its exact slot enum once before any runtime consumer sees it.
	var supported: Array = []
	for old: Variant in parsed.supportedSlots:
		var id := Slots.import_slot(old)
		if id.is_empty() or id in supported: return {}
		supported.append(id)
	parsed.supportedSlots = supported
	for loadout: Variant in parsed.loadouts:
		if not loadout is Dictionary: return {}
		var equipment := Slots.normalize_slots(loadout.get("equipment"), true)
		if equipment.status != "KNOWN_VALID": return {}
		loadout.equipment = equipment.value
	return parsed


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
