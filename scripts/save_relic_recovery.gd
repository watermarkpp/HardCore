class_name SaveRelicRecovery
extends RefCounted
const ProfileContent := preload("res://scripts/gameplay/profile/legacy_profile_content.gd")

## Pure candidate planner for legacy flat relic/badge records.
##
## This module deliberately has no persistence authority.  The caller must
## retain the source backup and run the complete profile/account validator on
## the returned document before considering it usable.

const ItemExtensionCodec := preload("res://scripts/items/item_extension_codec.gd")
const ItemIdentityCodec := preload("res://scripts/identity/item_identity_codec.gd")
const RelicRules := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")

const KNOWN_ITEM_IDS: Array[int] = [950101, 950102, 950103, 950201, 950202, 950203]
const RELIC_CONTRACT := "equipment.relic_synthesis.v1"
const ARRAY_FIELDS: Array[String] = ["inventory", "warehouse_inventory", "forge_tray", "synthesis_tray"]
const OWNER_FIELDS: Array[String] = [
	"contract_id", "format_version", "base", "extensions", "_hc_item_extension",
	"drop_instance_contract_id", "gem_instance_contract_id", "rune_instance_contract_id",
]


static func plan(document: Dictionary, content: ProfileContent.ContentPort = null) -> Dictionary:
	var removed: Array = []
	var output := document
	for field: String in ARRAY_FIELDS:
		var value: Variant = document.get(field, null)
		if not value is Array:
			continue
		var mapped: Array = value
		var changed := false
		for index in range(value.size() - 1, -1, -1):
			var record: Variant = value[index]
			var candidate := _candidate(record, "%s[%d]" % [field, index], content)
			if bool(candidate.get("blocked", false)):
				return _blocked_result(document, str(candidate.get("reason", "unsupported_relic_owner")))
			if candidate.is_empty():
				continue
			if not changed:
				mapped = value.duplicate(true)
				changed = true
			# Inventory/warehouse/tray indices are player-authored positions.
			# Empty this slot; never slide healthy neighboring items into it.
			mapped[index] = {}
			removed.append(candidate)
		if changed:
			if is_same(output, document):
				output = document.duplicate(true)
			output[field] = mapped
	var equipment_value: Variant = document.get("equipment", null)
	if not equipment_value is Dictionary:
		return {
			"changed": not removed.is_empty(),
			"document": output,
			"removed": removed,
			"reason": "legacy_invalid_relic_instances_removed" if not removed.is_empty() else "no_safe_relic_candidate",
		}
	var equipment: Dictionary = equipment_value
	for raw_slot: Variant in equipment.keys():
		var slot := str(raw_slot)
		var candidate := _candidate(equipment.get(raw_slot), "equipment.%s" % slot, content)
		if bool(candidate.get("blocked", false)):
			return _blocked_result(document, str(candidate.get("reason", "unsupported_relic_owner")))
		if candidate.is_empty():
			continue
		if is_same(output, document):
			output = document.duplicate(true)
		var mapped_equipment: Dictionary = output.get("equipment", {}).duplicate(true)
		mapped_equipment[raw_slot] = {}
		output.equipment = mapped_equipment
		removed.append(candidate)
	return {
		"changed": not removed.is_empty(),
		"document": output,
		"removed": removed,
		"reason": "legacy_invalid_relic_instances_removed" if not removed.is_empty() else "no_safe_relic_candidate",
	}


static func _blocked_result(document: Dictionary, reason: String) -> Dictionary:
	return {
		"changed": false,
		"document": document,
		"removed": [],
		"blocked": true,
		"reason": reason,
	}


static func _candidate(raw: Variant, location: String, content: ProfileContent.ContentPort = null) -> Dictionary:
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return {}
	var record: Dictionary = raw
	if not _is_known_flat_legacy_record(record):
		return {}
	var owner_reason := _unsupported_owner_reason(record)
	if not owner_reason.is_empty():
		return {"blocked": true, "reason": owner_reason}
	var item_id := int(record.get("item_id", -1))
	var identity := ItemIdentityCodec.normalize(record, false, content)
	if str(identity.get("status", "")) != "KNOWN_VALID":
		return {}
	if not RelicRules.is_synthesis_item(item_id):
		return {}
	var roll: Variant = record.get("relic_roll", null)
	var reason := ""
	if roll == null:
		reason = "missing_relic_roll"
	elif not roll is Dictionary or str((roll as Dictionary).get("contract_id", "")) != RELIC_CONTRACT:
		# Unknown, malformed, and future owners stay opaque. The caller must
		# refuse legacy fallback rather than deleting an item it cannot classify.
		return {"blocked": true, "reason": "unsupported_relic_roll_contract"}
	elif RelicRules.valid_instance(record, item_id):
		return {}
	else:
		reason = "invalid_relic_instance"
	return {
		"item_id": item_id,
		"location": location,
		"instance_id": str(record.get("instance_id", "")),
		"reason": reason,
	}


static func _is_known_flat_legacy_record(record: Dictionary) -> bool:
	var item_id: Variant = record.get("item_id", null)
	if not (item_id is int or item_id is float) or float(item_id) != floor(float(item_id)):
		return false
	return int(item_id) in KNOWN_ITEM_IDS


static func _unsupported_owner_reason(record: Dictionary) -> String:
	# Presence itself is significant: an unknown owner must not be
	# reinterpreted as an old flat relic merely because its item_id is known.
	for field: String in OWNER_FIELDS:
		if record.has(field):
			return "unsupported_relic_owner_field:%s" % field
	if ItemExtensionCodec.has_extensions(record):
		return "unsupported_relic_owner_extension"
	return ""
