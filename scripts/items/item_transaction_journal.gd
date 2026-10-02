extends RefCounted

const CONTRACT := "hc.item.transactions.v1"
const SEQUENCE_CONTRACT := "hc.item.transactions.v2"
const SEQUENCE_PREFIX := "hc:itemtx:"
const MAX_SEQUENCE := 9007199254740991
const FIELD := "item_transactions"
const LIMIT := 64
const ACTIONS := ["hc.socketing.insert", "hc.socketing.remove"]

# Legacy opaque outcomes are never retired. The separate sequenced protocol
# retains a contiguous durable watermark: an omitted old ID remains terminal.
static func validate_document(document: Dictionary) -> Dictionary:
	if not document.has(FIELD): return _status(true)
	var journal: Variant = document[FIELD]
	if not journal is Dictionary: return _status(false)
	if journal.get("contract_id") is String and journal.contract_id not in [CONTRACT,SEQUENCE_CONTRACT]:
		return _status(false, true)
	var sequenced: bool = journal.get("contract_id") == SEQUENCE_CONTRACT
	var supported := 2 if sequenced else 1
	if _integer(journal.get("schema_version")) and journal.schema_version > supported:
		return _status(false, true)
	for field: String in ["entries","legacy_entries"]:
		if journal.get(field) is Array:
			for entry: Variant in journal[field]:
				if entry is Dictionary and entry.get("action") is String and entry.action not in ACTIONS:
					return _status(false, true)
	var keys: Array = ["contract_id","schema_version","profile_id","entries"]
	if sequenced: keys.append_array(["epoch","last_sequence","retired_through","legacy_entries"])
	if not _keys(journal, keys) or not _integer(journal.schema_version) or journal.schema_version != supported \
		or journal.contract_id not in [CONTRACT,SEQUENCE_CONTRACT] \
		or not journal.profile_id is String or journal.profile_id != document.get("profile_id") \
		or not journal.entries is Array or journal.entries.size() > LIMIT:
		return _status(false)
	var seen := {}
	if sequenced:
		if not _epoch_valid(journal.epoch) or not _sequence_valid(journal.last_sequence) \
			or not _integer(journal.retired_through) or journal.retired_through != maxi(0,int(journal.last_sequence)-LIMIT) \
			or not journal.legacy_entries is Array or journal.legacy_entries.size() > LIMIT \
			or journal.entries.size() != int(journal.last_sequence)-int(journal.retired_through): return _status(false)
		var legacy_status := _entries_valid(journal.legacy_entries,seen)
		if not legacy_status.valid: return legacy_status
		for index in journal.entries.size():
			var raw: Variant = journal.entries[index]
			if not raw is Dictionary or raw.get("operation_id") != sequence_id(journal.epoch,int(journal.retired_through)+index+1):
				return _status(false)
	return _entries_valid(journal.entries,seen)

static func _entries_valid(entries: Array, seen: Dictionary) -> Dictionary:
	for raw: Variant in entries:
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
	for field: String in ["entries","legacy_entries"]:
		for entry: Dictionary in journal.get(field, []):
			if entry.operation_id == operation_id: return entry.duplicate(true)
	return {}

static func sequence_id(epoch: String, sequence: int) -> String:
	return SEQUENCE_PREFIX+epoch+":"+str(sequence) if _epoch_valid(epoch) and _sequence_valid(sequence) else ""

static func parse_sequence(value: String) -> Dictionary:
	if not value.begins_with(SEQUENCE_PREFIX): return {}
	var fields := value.trim_prefix(SEQUENCE_PREFIX).split(":")
	if fields.size() != 2 or not _epoch_valid(fields[0]) or not fields[1].is_valid_int(): return {}
	var sequence := fields[1].to_int()
	if value != sequence_id(fields[0],sequence): return {}
	return {"epoch":fields[0],"sequence":sequence}

static func admission(journal: Dictionary, operation_id: String, issued_epoch := "") -> Dictionary:
	if not journal.is_empty() and not validate_document({"profile_id":journal.get("profile_id"),FIELD:journal}).valid:
		return {"success":false,"reason":"invalid_item_transaction_journal"}
	if not operation_id.begins_with(SEQUENCE_PREFIX):
		var field := "legacy_entries" if journal.get("contract_id") == SEQUENCE_CONTRACT else "entries"
		return {"success":journal.get(field,[]).size() < LIMIT,"reason":"item_transaction_unavailable"}
	var id := parse_sequence(operation_id)
	if id.is_empty(): return {"success":false,"reason":"invalid_item_operation_sequence"}
	var sequenced: bool = journal.get("contract_id") == SEQUENCE_CONTRACT
	var epoch: String = journal.epoch if sequenced else issued_epoch
	if epoch.is_empty() or id.epoch != epoch: return {"success":false,"reason":"item_operation_epoch_mismatch"}
	var last := int(journal.last_sequence) if sequenced else 0
	if sequenced and int(id.sequence) <= int(journal.retired_through):
		return {"success":false,"reason":"item_operation_retired"}
	if last == MAX_SEQUENCE or int(id.sequence) != last+1:
		return {"success":false,"reason":"item_operation_sequence_mismatch"}
	return {"success":true,"reason":""}

static func appended(journal: Dictionary, profile_id: String, entry: Dictionary, issued_epoch := "") -> Dictionary:
	if not entry.get("operation_id") is String or not bool(admission(journal,entry.operation_id,issued_epoch).success): return {}
	var id := parse_sequence(entry.operation_id)
	var candidate := journal.duplicate(true) if not journal.is_empty() else {
		"contract_id": CONTRACT, "schema_version": 1, "profile_id": profile_id, "entries": []}
	if not id.is_empty():
		if candidate.contract_id == CONTRACT:
			candidate = {"contract_id":SEQUENCE_CONTRACT,"schema_version":2,"profile_id":profile_id,
				"epoch":id.epoch,"last_sequence":0,"retired_through":0,"legacy_entries":candidate.entries,"entries":[]}
		candidate.entries.append(entry.duplicate(true)); candidate.last_sequence = int(id.sequence)
		candidate.retired_through = maxi(0,int(id.sequence)-LIMIT)
		if candidate.entries.size() > LIMIT: candidate.entries.pop_front()
	else:
		var field := "legacy_entries" if candidate.contract_id == SEQUENCE_CONTRACT else "entries"
		candidate[field].append(entry.duplicate(true))
	return candidate if validate_document({"profile_id": profile_id, FIELD: candidate}).valid else {}

static func _epoch_valid(value: Variant) -> bool:
	if not value is String or value.length() != 32: return false
	for character in value:
		if character not in "0123456789abcdef": return false
	return true

static func _sequence_valid(value: Variant) -> bool:
	return _integer(value) and value >= 1 and value <= MAX_SEQUENCE

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
