extends RefCounted

# Typed identity translation only. Existing catalogs remain the rule authority.
const PATH := "res://assets/data/runtime/entity_registry_v1.json"
const CONTRACT := "hardcore.entity_identity.v1"
const NUMERIC := ["item", "service_item", "monster", "map"]
const KINDS := ["skill", "item", "service_item", "monster", "map", "profession", "slot", "currency", "item_category"]
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
static var _document: Dictionary = {}
static var _by_id: Dictionary = {}
static var _by_legacy: Dictionary = {}
static var _service_for_item: Dictionary = {}
static var _attempted := false
static var last_errors: Array[String] = []

static func ensure_loaded() -> bool:
	if not _document.is_empty():
		return true
	if _attempted:
		return false
	_attempted = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return publish(parsed)

static func publish(value: Variant) -> bool:
	var errors: Array[String] = []
	if not value is Dictionary or not _keys(value, ["schema_version", "contract_id", "source_hashes", "records", "counts"]) \
		or value.schema_version != 1 or value.contract_id != CONTRACT or not value.source_hashes is Dictionary \
		or not value.records is Array or not value.counts is Dictionary:
		last_errors = ["invalid_entity_registry_schema"]
		return false
	var expression := RegEx.new()
	expression.compile("^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)*$")
	var hashes := RegEx.new()
	hashes.compile("^[0-9a-f]{64}$")
	for path: Variant in value.source_hashes:
		if not path is String or not path.begins_with("res://assets/data/") or ".." in path \
			or not value.source_hashes[path] is String or hashes.search(value.source_hashes[path]) == null \
			or FileAccess.get_sha256(path).to_lower() != value.source_hashes[path]:
			errors.append("identity_source_hash:" + str(path))
	var ids := {}
	var legacy := {}
	var counts := {}
	for entry: Variant in value.records:
		if not entry is Dictionary or not _keys(entry, ["id", "kind", "legacy_id", "display_name", "evidence"], ["canonical_id"]) \
			or not entry.id is String or not entry.kind is String or entry.kind not in KINDS \
			or not entry.display_name is String or entry.display_name.is_empty() or not entry.evidence is Array or entry.evidence.is_empty():
			errors.append("invalid_identity_record")
			continue
		var kind: String = entry.kind
		if expression.search(entry.id) == null or not entry.id.begins_with("hc." + kind + "."):
			errors.append("invalid_entity_id:" + entry.id)
			continue
		var old: Variant = entry.legacy_id
		if kind in NUMERIC:
			if not _numeric_id(old) or entry.id != "hc." + kind + ".%06d" % int(old):
				errors.append("invalid_numeric_identity:" + entry.id)
				continue
		elif not old is String or old.is_empty() or (kind in ["skill", "item_category"] and entry.id != "hc." + kind + "." + old):
			errors.append("invalid_symbolic_identity:" + entry.id)
			continue
		for evidence: Variant in entry.evidence:
			if not evidence is Dictionary or not _keys(evidence, ["path", "pointer"]) \
				or not value.source_hashes.has(evidence.path) or not evidence.pointer is String or not evidence.pointer.begins_with("/"):
				errors.append("invalid_identity_evidence:" + entry.id)
		var key := _legacy_key(kind, old)
		if ids.has(entry.id) or legacy.has(key):
			errors.append("duplicate_entity_identity:" + entry.id)
			continue
		ids[entry.id] = entry
		legacy[key] = entry.id
		counts[kind] = int(counts.get(kind, 0)) + 1
	var services := {}
	for entry: Dictionary in ids.values():
		if entry.has("canonical_id") and (entry.kind != "service_item" or not entry.canonical_id is String \
			or ids.get(entry.canonical_id, {}).get("kind") != "item"):
			errors.append("invalid_item_alias:" + entry.id)
		elif entry.has("canonical_id"):
			if services.has(entry.canonical_id): errors.append("ambiguous_item_service_alias:" + entry.canonical_id)
			services[entry.canonical_id] = int(entry.legacy_id)
	var counts_match: bool = counts.size() == value.counts.size()
	for kind: Variant in value.counts:
		if not counts.has(kind) or not _numeric_id(value.counts[kind]) or int(value.counts[kind]) != int(counts.get(kind, -1)):
			counts_match = false
	if not counts_match or ids.is_empty():
		errors.append("identity_counts_mismatch")
	if not errors.is_empty():
		last_errors = errors
		return false
	var captured := Graph.capture(value)
	if not captured.success:
		last_errors = ["non_plain_identity_registry"]
		return false
	# Publish all indexes together only after the complete candidate validates.
	_document = captured.value
	_by_id = {}
	for entry: Dictionary in _document.records:
		_by_id[entry.id] = entry
	_by_id.make_read_only()
	legacy.make_read_only()
	_by_legacy = legacy
	services.make_read_only()
	_service_for_item = services
	last_errors = []
	return true

static func document() -> Dictionary:
	ensure_loaded()
	return _document

static func resolve(id: String, kind := "") -> Dictionary:
	if not ensure_loaded():
		return {}
	var entry: Dictionary = _by_id.get(id, {})
	return entry if kind.is_empty() or entry.get("kind") == kind else {}

static func from_legacy(kind: String, old: Variant) -> String:
	if not ensure_loaded() or kind not in KINDS:
		return ""
	if kind in NUMERIC and not _numeric_id(old):
		return ""
	if kind not in NUMERIC and not old is String:
		return ""
	return str(_by_legacy.get(_legacy_key(kind, old), ""))

static func legacy(id: String, kind: String) -> Variant:
	return resolve(id, kind).get("legacy_id")

static func canonical(id: String) -> String:
	var entry := resolve(id)
	return str(entry.get("canonical_id", entry.get("id", "")))

static func service_for_item(id: String) -> int:
	if not ensure_loaded(): return -1
	return int(_service_for_item.get(id, -1))

static func _legacy_key(kind: String, old: Variant) -> String:
	return kind + ":" + (str(int(old)) if kind in NUMERIC else str(old))

static func _numeric_id(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) == floor(float(value)) and float(value) >= 0.0 and float(value) <= 2147483647.0

static func _keys(value: Dictionary, expected: Array, optional: Array = []) -> bool:
	if value.size() < expected.size() or value.size() > expected.size() + optional.size():
		return false
	for key: String in expected:
		if not value.has(key): return false
	for key: Variant in value:
		if not key is String or (key not in expected and key not in optional):
			return false
	return true
