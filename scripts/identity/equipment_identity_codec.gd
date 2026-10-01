extends RefCounted

const Registry := preload("res://scripts/identity/entity_registry.gd")
const Categories := preload("res://scripts/identity/item_category_identity.gd")
const FIELD := "equipment_identity"
const CONTRACT := "hardcore.equipment.identity.v1"
const HEADER := {"contract_id": CONTRACT, "schema_version": 1}
const SLOTS: Array[String] = ["hc.slot.weapon", "hc.slot.armor", "hc.slot.helmet", "hc.slot.necklace",
	"hc.slot.bracelet_left", "hc.slot.bracelet_right", "hc.slot.ring_left", "hc.slot.ring_right", "hc.slot.relic", "hc.slot.badge"]
# A two-slot cycle is owned by its first registered slot, not its display category.
const CYCLES := {"hc.slot.ring_left": ["hc.slot.ring_left", "hc.slot.ring_right"],
	"hc.slot.bracelet_left": ["hc.slot.bracelet_left", "hc.slot.bracelet_right"]}

static func display_name(slot_id: String) -> String:
	return str(Registry.resolve(slot_id, "slot").get("display_name", ""))

static func import_slot(value: Variant) -> String:
	if not value is String: return ""
	if value in SLOTS: return value
	# The only name translation entrance is an explicit legacy data import.
	if value == "手镯": return "hc.slot.bracelet_left"
	if value == "戒指": return "hc.slot.ring_left"
	var id := Registry.from_legacy("slot", value)
	return id if id in SLOTS else ""

static func support(document: Dictionary) -> Dictionary:
	if not document.has(FIELD): return {"status": "KNOWN_VALID", "formal": false, "reason": ""}
	var header: Variant = document[FIELD]
	if not header is Dictionary or header.size() != 2 or not header.get("contract_id") is String \
		or header.contract_id != CONTRACT or not _integer(header.get("schema_version")) or header.schema_version != 1:
		return _failure("unsupported_equipment_identity_contract")
	return {"status": "KNOWN_VALID", "formal": true, "reason": ""}

static func normalize_document(document: Dictionary, encode: bool) -> Dictionary:
	var supported := support(document)
	if supported.status != "KNOWN_VALID": return supported
	var output: Dictionary = document
	for field: String in ["equipment", "equip_cycle_cursor"]:
		if not document.has(field): continue
		var mapped := normalize_slots(document[field], not bool(supported.formal)) if field == "equipment" \
			else normalize_cycles(document[field], not bool(supported.formal))
		if mapped.status != "KNOWN_VALID": return mapped
		if not is_same(mapped.value, document[field]):
			if is_same(output, document): output = output.duplicate()
			output[field] = mapped.value
	if encode and (document.has("equipment") or document.has("equip_cycle_cursor")) and not document.has(FIELD):
		if is_same(output, document): output = output.duplicate()
		output[FIELD] = HEADER.duplicate()
	return {"status": "KNOWN_VALID", "document": output, "reason": ""}

static func normalize_slots(value: Variant, allow_legacy: bool) -> Dictionary:
	if not value is Dictionary: return _failure("invalid_equipment_identity_owner")
	var result := {}
	var unchanged := true
	for key: Variant in value:
		if not key is String: return _failure("invalid_equipment_slot_identity")
		var slot: String = import_slot(key) if allow_legacy else key
		if slot not in SLOTS or Registry.resolve(slot, "slot").is_empty(): return _failure("unknown_equipment_slot_identity")
		if result.has(slot):
			# Old generic and explicit left slots may both describe an empty hole.
			# Two occupied owners are a conflict even if their item bytes match.
			if not _empty(result[slot]) and not _empty(value[key]): return _failure("conflicting_equipment_slot_identity")
			if not _empty(value[key]): result[slot] = value[key]
			unchanged = false
		else:
			result[slot] = value[key]
		unchanged = unchanged and key == slot
	return {"status": "KNOWN_VALID", "value": value if unchanged else result, "reason": ""}

static func normalize_cycles(value: Variant, allow_legacy: bool) -> Dictionary:
	if not value is Dictionary: return _failure("invalid_equipment_cycle_owner")
	var result := {}
	var unchanged := true
	for key: Variant in value:
		var group: String = import_slot(key) if allow_legacy else (key if key is String else "")
		var slot: String = import_slot(value[key]) if allow_legacy else (value[key] if value[key] is String else "")
		if not CYCLES.has(group) or slot not in CYCLES[group] or result.has(group): return _failure("unknown_or_conflicting_equipment_cycle_identity")
		result[group] = slot
		unchanged = unchanged and group == key and slot == value[key]
	return {"status": "KNOWN_VALID", "value": value if unchanged else result, "reason": ""}

static func default_cycles() -> Dictionary:
	return {"hc.slot.ring_left": "hc.slot.ring_left", "hc.slot.bracelet_left": "hc.slot.bracelet_left"}

static func slots_for_legacy_category(category: String) -> Array[String]:
	return slots_for_category(Categories.import_legacy_category(category))

static func slots_for_category(category_id: String) -> Array[String]:
	return Categories.slots(category_id)

static func _empty(value: Variant) -> bool:
	return (value is Dictionary or value is String) and value.is_empty()

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

static func _failure(reason: String) -> Dictionary:
	return {"status": "OPAQUE_UNSUPPORTED", "reason": reason, "document": {}, "value": {}}
