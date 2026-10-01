extends RefCounted

const Registry := preload("res://scripts/identity/entity_registry.gd")
const FIELD := "item_identity"
const CONTRACT := "hardcore.item.identity.v1"
const HEADER := {"contract_id": CONTRACT, "schema_version": 1}

static func support(document: Dictionary) -> Dictionary:
	if not document.has(FIELD):
		return {"status": "KNOWN_VALID", "formal": false, "reason": ""}
	var value: Variant = document[FIELD]
	if not value is Dictionary or value.size() != 2 or not value.get("contract_id") is String or value.contract_id != CONTRACT \
		or not _integer(value.get("schema_version")) or value.schema_version != 1:
		return _failure("unsupported_item_identity_contract")
	return {"status": "KNOWN_VALID", "formal": true, "reason": ""}

static func normalize(record: Dictionary, allow_legacy: bool) -> Dictionary:
	if record.is_empty():
		return _success(record)
	var typed := record.has("item_id") or record.has("service_index")
	if not typed and not allow_legacy:
		return _failure("missing_formal_item_identity")
	# Only this explicit legacy import boundary may consult an old display name.
	# GameData rejects malformed or conflicting supplied identities first.
	var id := GameData.item_entity_id(record)
	var entry := Registry.resolve(id)
	if entry.get("kind") not in ["item", "service_item"]:
		return _failure("unknown_or_conflicting_item_identity")
	var key := "item_id" if entry.kind == "item" else "service_index"
	var other := "service_index" if entry.kind == "item" else "item_id"
	if record.has(key) and _integer(record[key]) and int(record[key]) == int(entry.legacy_id) and not record.has(other):
		return _success(record)
	var canonical := record.duplicate(true)
	canonical.erase(other)
	canonical[key] = int(entry.legacy_id)
	return _success(canonical)

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

static func _success(record: Dictionary) -> Dictionary:
	return {"status": "KNOWN_VALID", "item": record, "reason": ""}

static func _failure(reason: String) -> Dictionary:
	# Unknown identity ownership is terminal: never restore an older backup over
	# an item the current authority cannot represent, or silently discard it.
	return {"status": "OPAQUE_UNSUPPORTED", "item": {}, "document": {}, "reason": reason}
