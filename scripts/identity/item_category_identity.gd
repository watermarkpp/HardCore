extends RefCounted

const Registry := preload("res://scripts/identity/entity_registry.gd")
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const PATH := "res://assets/data/identity/item_categories_v1.json"
const POLICY := "res://assets/data/source_priority_policy.json"
const CONTRACT := "hardcore.item_categories.v1"
const PHYSICAL_SLOTS := ["hc.slot.weapon", "hc.slot.armor", "hc.slot.helmet", "hc.slot.necklace",
	"hc.slot.bracelet_left", "hc.slot.bracelet_right", "hc.slot.ring_left", "hc.slot.ring_right", "hc.slot.relic", "hc.slot.badge"]
static var _by_id: Dictionary = {}
static var _legacy: Dictionary = {}
static var last_error := ""

static func ensure_loaded() -> bool:
	if not _by_id.is_empty(): return true
	var policy: Variant = JSON.parse_string(FileAccess.get_file_as_string(POLICY))
	if not policy is Dictionary or policy.get("routing", {}).get("item_category_identity_and_slot_relations") != "item_categories":
		return _fail("invalid_category_source_lane")
	var sources: Variant = policy.get("lanes", {}).get("item_categories", {}).get("sources")
	if not sources is Array or sources.size() != 1 or not sources[0] is Dictionary:
		return _fail("invalid_category_source_lane")
	var source: Dictionary = sources[0]
	if source.get("tier") != "primary" or source.get("eligible") != true or source.get("authority") != "project_master" \
		or source.get("sourceKind") != "tracked_authoring_source" or source.get("contractId") != CONTRACT \
		or source.get("rootPrefix") != PATH.trim_prefix("res://") or source.get("originalPath") != PATH.trim_prefix("res://") \
		or source.get("evidenceSha256") != FileAccess.get_sha256(PATH).to_upper():
		return _fail("invalid_category_source_lane")
	return publish(JSON.parse_string(FileAccess.get_file_as_string(PATH)))

static func publish(document: Variant) -> bool:
	if not document is Dictionary or not _keys(document, ["schema_version", "contract_id", "records"]) \
		or not _integer(document.schema_version) or document.schema_version != 1 or document.contract_id != CONTRACT \
		or not document.records is Array or not Registry.ensure_loaded():
		return _fail("unsupported_category_source")
	var candidate := {}
	var aliases := {}
	for row: Variant in document.records:
		if not row is Dictionary or not _keys(row, ["category_id", "display_name", "legacy_categories", "equipment_slots"]) \
			or not row.category_id is String or not row.display_name is String or row.display_name.is_empty() \
			or not row.legacy_categories is Array or row.legacy_categories.is_empty() or not row.equipment_slots is Array:
			return _fail("invalid_category_record")
		var category_id: String = "hc.item_category." + row.category_id
		if Registry.resolve(category_id, "item_category").is_empty() or candidate.has(category_id):
			return _fail("unknown_or_duplicate_category_identity")
		for old: Variant in row.legacy_categories:
			if not old is String or old.is_empty() or old.begins_with("hc.") or aliases.has(old):
				return _fail("invalid_or_duplicate_category_legacy_enum")
			aliases[old] = category_id
		var seen_slots := {}
		for slot: Variant in row.equipment_slots:
			if not slot is String or slot not in PHYSICAL_SLOTS or Registry.resolve(slot, "slot").is_empty() or seen_slots.has(slot):
				return _fail("invalid_category_slot_relation")
			seen_slots[slot] = true
		candidate[category_id] = row
	if candidate.size() != int(Registry.document().counts.get("item_category", -1)):
		return _fail("incomplete_category_source")
	var captured := Graph.capture(candidate)
	if not captured.success: return _fail("non_plain_category_source")
	# An invalid candidate cannot replace a previously accepted category table.
	_by_id = captured.value
	aliases.make_read_only()
	_legacy = aliases
	last_error = ""
	return true

static func import_legacy_category(value: Variant) -> String:
	# Explicit source / old API boundary only. Never infer a category from an item name.
	if not value is String or not ensure_loaded(): return ""
	if value.begins_with("hc."): return value if _by_id.has(value) else ""
	return str(_legacy.get(value, ""))

static func category_for_record(record: Dictionary) -> String:
	if not ensure_loaded(): return ""
	if record.has("category_id"):
		var formal: Variant = record.category_id
		return formal if formal is String and _by_id.has(formal) else ""
	return import_legacy_category(record.get("category"))

static func attach_source_category(record: Dictionary) -> bool:
	var id := category_for_record(record)
	if id.is_empty(): return false
	record["category_id"] = id
	return true

static func slots(category_id: String) -> Array[String]:
	var result: Array[String] = []
	if ensure_loaded() and _by_id.has(category_id):
		for slot: String in _by_id[category_id].equipment_slots: result.append(slot)
	return result

static func _keys(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size(): return false
	for field: String in fields:
		if not value.has(field): return false
	return true

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

static func _fail(reason: String) -> bool:
	last_error = reason
	return false
