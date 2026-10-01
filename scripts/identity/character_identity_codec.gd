extends RefCounted

## Save-boundary identity translation. The registered ID is the authority;
## the old profession field is retained only as a checked display projection.
const Registry := preload("res://scripts/identity/entity_registry.gd")
const CONTRACT := "hardcore.character.identity.v1"
const KEYS := ["contract_id", "schema_version", "profession_id"]

static func encode(profession_id: String) -> Dictionary:
	if Registry.resolve(profession_id, "profession").is_empty():
		return {}
	return {"contract_id": CONTRACT, "schema_version": 1, "profession_id": profession_id}

static func decode(document: Dictionary) -> Dictionary:
	var id := ""
	if document.has("character_identity"):
		var value: Variant = document.character_identity
		if not value is Dictionary or value.size() != KEYS.size():
			return _failure("invalid_character_identity_schema")
		for key: Variant in value:
			if not key is String or key not in KEYS:
				return _failure("invalid_character_identity_schema")
		var version: Variant = value.schema_version
		if not (version is int or version is float) or not is_finite(float(version)) \
			or float(version) != 1.0 or not value.contract_id is String \
			or value.contract_id != CONTRACT or not value.profession_id is String:
			return _failure("unsupported_character_identity_contract")
		id = value.profession_id
		var record := Registry.resolve(id, "profession")
		if record.is_empty():
			return _failure("unknown_profession_identity")
		if document.has("profession") and (not document.profession is String or document.profession != record.display_name):
			return _failure("conflicting_profession_identity")
	else:
		# Historical sparse documents have an explicit warrior default. Once
		# present, the old name must match the exact registered legacy identity.
		var legacy: Variant = document.get("profession", "战士")
		if not legacy is String:
			return _failure("invalid_legacy_profession_identity")
		id = Registry.from_legacy("profession", legacy)
		if id.is_empty():
			return _failure("unknown_legacy_profession_identity")
	return {"success": true, "profession_id": id, "reason": ""}

static func _failure(reason: String) -> Dictionary:
	return {"success": false, "profession_id": "", "reason": reason}
