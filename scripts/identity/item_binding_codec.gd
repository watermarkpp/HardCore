extends RefCounted

const Registry := preload("res://scripts/identity/entity_registry.gd")
const CONTRACT := "gameplay.item.quick_slots.v2"
const SLOT_COUNT := 4

static func is_candidate(id: String) -> bool:
	var identity := Registry.resolve(id)
	if identity.get("kind", "") not in ["item", "service_item"]:
		return false
	var record := GameData.get_entity_record(id)
	return not record.is_empty() and record.get("kind", "") in ["skill_book", "consumable", "scroll"] \
		and record.get("usable", true) != false

static func encode(slots: Array) -> Dictionary:
	if slots.size() != SLOT_COUNT:
		return {}
	for id: Variant in slots:
		if not id is String or (not id.is_empty() and not is_candidate(id)):
			return {}
	var canonical: Array[String] = []
	for id: String in slots: canonical.append(Registry.canonical(id) if not id.is_empty() else "")
	return {"contract_id": CONTRACT, "slots": canonical}

static func decode(document: Dictionary) -> Dictionary:
	if not document.has("item_button_assignments"):
		return {"success": true, "slots": import_legacy(document.get("quick_item_slots", [])), "reason": ""}
	var value: Variant = document.item_button_assignments
	if not value is Dictionary or value.size() != 2 or not value.has("contract_id") or not value.has("slots") \
		or not value.contract_id is String or value.contract_id != CONTRACT or not value.slots is Array:
		return _failure("invalid_item_binding_contract")
	var canonical := encode(value.slots)
	if canonical.is_empty():
		return _failure("invalid_item_binding_identity")
	if document.has("quick_item_slots") and (not document.quick_item_slots is Array or encode(document.quick_item_slots) != canonical):
		return _failure("conflicting_item_binding_identity")
	return {"success": true, "slots": canonical.slots, "reason": ""}

static func import_legacy(value: Variant) -> Array[String]:
	var result: Array[String] = []
	var source: Array = value if value is Array else []
	for index in range(SLOT_COUNT):
		var old: Variant = source[index] if index < source.size() else null
		# The old unbound layout cleared non-candidates. A formal v2 identity
		# can never enter this display-only migration path.
		var id := GameData.item_entity_id(old) if old is String and not old.is_empty() else ""
		result.append(id if is_candidate(id) else "")
	return result

static func _failure(reason: String) -> Dictionary:
	return {"success": false, "slots": [], "reason": reason}
