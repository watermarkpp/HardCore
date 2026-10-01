extends RefCounted

const CONTRACT := "hc.item.transactions.v1"
const FIELD := "item_transactions"
const LIMIT := 64
const ACTIONS := ["hc.socketing.insert", "hc.socketing.remove"]

# Durable outcomes belong to the character document and its existing writer.
# Never evict outcomes: a full journal refuses new fixture operations so an
# old operation ID cannot silently become eligible for a second consumption.
static func validate_document(document: Dictionary) -> Dictionary:
	if not document.has(FIELD): return _status(true)
	var journal: Variant = document[FIELD]
	if not journal is Dictionary: return _status(false)
	if journal.get("contract_id") is String and journal.contract_id != CONTRACT:
		return _status(false, true)
	if _integer(journal.get("schema_version")) and journal.schema_version > 1:
		return _status(false, true)
	if journal.get("entries") is Array:
		for entry: Variant in journal.entries:
			if entry is Dictionary and entry.get("action") is String and entry.action not in ACTIONS:
				return _status(false, true)
	if not _keys(journal, ["contract_id", "schema_version", "profile_id", "entries"]) \
		or journal.contract_id != CONTRACT or not _integer(journal.schema_version) or journal.schema_version != 1 \
		or not journal.profile_id is String or journal.profile_id != document.get("profile_id") \
		or not journal.entries is Array or journal.entries.size() > LIMIT:
		return _status(false)
	var seen := {}
	for raw: Variant in journal.entries:
		if not raw is Dictionary or not _keys(raw, ["operation_id", "request_digest", "action", "target_instance_id", "gem_instance_id", "rules_revision"]):
			return _status(false)
		for key: String in raw:
			if not raw[key] is String: return _status(false)
		if raw.action not in ACTIONS: return _status(false, true)
		if not identity_valid(raw.operation_id) or not identity_valid(raw.target_instance_id) or not identity_valid(raw.gem_instance_id) \
			or not _hash(raw.request_digest) or not _hash(raw.rules_revision) or seen.has(raw.operation_id):
			return _status(false)
		seen[raw.operation_id] = true
	return _status(true)

static func lookup(journal: Dictionary, operation_id: String) -> Dictionary:
	for entry: Dictionary in journal.get("entries", []):
		if entry.operation_id == operation_id: return entry.duplicate(true)
	return {}

static func appended(journal: Dictionary, profile_id: String, entry: Dictionary) -> Dictionary:
	var candidate := journal.duplicate(true) if not journal.is_empty() else {
		"contract_id": CONTRACT, "schema_version": 1, "profile_id": profile_id, "entries": []}
	if candidate.get("entries", []).size() >= LIMIT: return {}
	candidate.entries.append(entry.duplicate(true))
	return candidate if validate_document({"profile_id": profile_id, FIELD: candidate}).valid else {}

static func identity_valid(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 128: return false
	var regex := RegEx.new()
	regex.compile("^[a-z0-9:_-]+$")
	return regex.search(value) != null

static func _keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size(): return false
	for key: String in keys:
		if not value.has(key): return false
	return true

static func _hash(value: String) -> bool:
	return value.length() == 64 and value.is_valid_hex_number(false)

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

static func _status(valid: bool, terminal := false) -> Dictionary:
	return {"valid": valid, "terminal": terminal, "reason": "" if valid else (
		"unsupported_item_transaction_journal" if terminal else "invalid_item_transaction_journal")}
