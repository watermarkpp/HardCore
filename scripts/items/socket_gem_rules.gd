extends RefCounted

const Registry := preload("res://scripts/identity/entity_registry.gd")
const Categories := preload("res://scripts/identity/item_category_identity.gd")
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const PATH := "res://assets/data/features/socketing_fixture_items.json"
const POLICY := "res://assets/data/source_priority_policy.json"
const SOURCE_CONTRACT := "hc.socketing.fixture.items.v1"
const INSTANCE_CONTRACT := "hc.socketing.fixture.gem.v1"
const MODULE := "hc.socketing_fixture"
const ITEM_ID := 990001
const ENTITY_ID := "hc.item.990001"
static var _record: Dictionary = {}

static func ensure_loaded() -> bool:
	if not _record.is_empty(): return true
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var policy: Variant = JSON.parse_string(FileAccess.get_file_as_string(POLICY))
	if not document is Dictionary or not policy is Dictionary:
		return false
	if not _keys(document, ["schema_version", "contract_id", "module_id", "default_enabled", "records"]) \
		or not _integer(document.schema_version) or int(document.schema_version) != 1 \
		or not document.contract_id is String or document.contract_id != SOURCE_CONTRACT \
		or not document.module_id is String or document.module_id != MODULE \
		or not document.default_enabled is bool or document.default_enabled != false \
		or not document.records is Array or document.records.size() != 1:
		return false
	var lanes: Variant = policy.get("lanes")
	if not lanes is Dictionary: return false
	var lane: Variant = lanes.get("framework_fixture_items", {})
	if not lane is Dictionary or not lane.get("sources") is Array or lane.sources.size() != 1:
		return false
	var source: Variant = lane.sources[0]
	if not source is Dictionary or not source.get("tier") is String or source.tier != "primary" \
		or not source.get("eligible") is bool or source.eligible != true \
		or not source.get("rootPrefix") is String or source.rootPrefix != PATH.trim_prefix("res://") \
		or not source.get("contractId") is String or source.contractId != SOURCE_CONTRACT \
		or not source.get("evidenceSha256") is String or source.evidenceSha256 != FileAccess.get_sha256(PATH).to_upper():
		return false
	var record: Variant = document.records[0]
	if not record is Dictionary or not _keys(record, ["itemId", "name", "kind", "category", "stackable", "weight", "usable", "sellable", "fixtureOnly"]) \
		or not _integer(record.itemId) or int(record.itemId) != ITEM_ID \
		or not record.name is String or record.name.is_empty() or not record.kind is String or record.kind != "socket_gem" \
		or not record.category is String or not record.stackable is bool or record.stackable != false \
		or not record.usable is bool or record.usable != false or not record.sellable is bool or record.sellable != false \
		or not record.fixtureOnly is bool or record.fixtureOnly != true or not _integer(record.weight) or int(record.weight) != 0 \
		or Registry.resolve(ENTITY_ID, "item").is_empty():
		return false
	var bound: Dictionary = record.duplicate(true)
	if not Categories.attach_source_category(bound): return false
	var captured := Graph.capture(bound, 32, 4)
	if not bool(captured.success): return false
	_record = captured.value
	return true

static func record_for_id(item_id: int) -> Dictionary:
	return _record if item_id == ITEM_ID and ensure_loaded() else {}

static func create_instance(instance_id: String, fixture_enabled := false) -> Dictionary:
	# A trusted fixture caller supplies explicit admission. Production quote /
	# commit independently checks the compiled module permission before use.
	if not fixture_enabled or not ensure_loaded(): return {}
	var instance := {"gem_instance_contract_id": INSTANCE_CONTRACT, "item_id": ITEM_ID,
		"name": _record.name, "count": 1, "instance_id": instance_id}
	return instance if valid_instance(instance) else {}

static func valid_instance(instance: Dictionary) -> bool:
	if not ensure_loaded() or not _keys(instance, ["gem_instance_contract_id", "item_id", "name", "count", "instance_id"]) \
		or not instance.gem_instance_contract_id is String or instance.gem_instance_contract_id != INSTANCE_CONTRACT \
		or not _integer(instance.item_id) or int(instance.item_id) != ITEM_ID \
		or not _integer(instance.count) or int(instance.count) != 1 \
		or not instance.name is String or instance.name.length() > 256 \
		or not instance.instance_id is String or instance.instance_id.is_empty() or instance.instance_id.length() > 128:
		return false
	var pattern := RegEx.new()
	pattern.compile("^[a-z0-9:_-]+$")
	return pattern.search(instance.instance_id) != null

static func _keys(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size(): return false
	for field: String in fields:
		if not value.has(field): return false
	return true

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))
