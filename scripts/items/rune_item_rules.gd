extends RefCounted

const Registry := preload("res://scripts/identity/entity_registry.gd")
const Categories := preload("res://scripts/identity/item_category_identity.gd")
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const PATH := "res://assets/data/features/rune_fixture_items.json"
const POLICY := "res://assets/data/source_priority_policy.json"
const SOURCE_CONTRACT := "hc.runes.fixture.items.v1"
const INSTANCE_CONTRACT := "hc.runes.fixture.rune.v1"
const MODULE := "hc.runes.fixture"
const ITEM_ID := 990002
static var _records: Dictionary={}

static func ensure_loaded() -> bool:
	if not _records.is_empty(): return true
	var document: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var policy: Variant=JSON.parse_string(FileAccess.get_file_as_string(POLICY))
	if not document is Dictionary or not policy is Dictionary or not _keys(document,["schema_version","contract_id","module_id","default_enabled","records"]) \
		or not _integer(document.schema_version) or document.schema_version!=1 or document.contract_id!=SOURCE_CONTRACT \
		or not document.module_id is String or document.module_id!=MODULE or not document.default_enabled is bool or document.default_enabled!=false \
		or not document.records is Array or document.records.is_empty(): return false
	if not Graph.capture(document,16384,8).success: return false
	var lanes: Variant=policy.get("lanes")
	if not lanes is Dictionary: return false
	var lane: Variant=lanes.get("framework_rune_fixture_items",{})
	if not lane is Dictionary or not lane.get("sources") is Array or lane.sources.size()!=1: return false
	var source: Variant=lane.sources[0]
	if not source is Dictionary or source.get("tier")!="primary" or source.get("eligible")!=true \
		or source.get("rootPrefix")!=PATH.trim_prefix("res://") or source.get("contractId")!=SOURCE_CONTRACT \
		or source.get("evidenceSha256")!=FileAccess.get_sha256(PATH).to_upper(): return false
	var records: Dictionary={}
	for record: Variant in document.records:
		if not record is Dictionary or not _keys(record,["itemId","name","kind","category","stackable","weight","usable","sellable","fixtureOnly"]) \
			or not _integer(record.itemId) or not record.name is String or record.name.is_empty() \
			or record.kind!="rune" or not record.category is String or not record.stackable is bool or record.stackable \
			or not record.usable is bool or record.usable or not record.sellable is bool or record.sellable \
			or not record.fixtureOnly is bool or not record.fixtureOnly or not _integer(record.weight) or record.weight!=0 \
			or Registry.from_legacy("item",int(record.itemId)).is_empty() or records.has(int(record.itemId)): return false
		var bound: Dictionary=record.duplicate(true)
		if not Categories.attach_source_category(bound) or bound.category_id!="hc.item_category.rune": return false
		var captured:=Graph.capture(bound,32,4)
		if not captured.success: return false
		records[int(record.itemId)]=captured.value
	_records=records; return true

static func record_for_id(item_id: int) -> Dictionary:
	return _records.get(item_id,{}).duplicate(true) if ensure_loaded() else {}
static func create_instance(instance_id: String,fixture_enabled:=false,item_id:=ITEM_ID) -> Dictionary:
	var record:=record_for_id(item_id) if fixture_enabled else {}
	if record.is_empty(): return {}
	var instance: Dictionary={"rune_instance_contract_id":INSTANCE_CONTRACT,"item_id":item_id,
		"name":record.name,"count":1,"instance_id":instance_id}
	return instance if valid_instance(instance) else {}
static func valid_instance(instance: Dictionary) -> bool:
	if not ensure_loaded() or not _keys(instance,["rune_instance_contract_id","item_id","name","count","instance_id"]) \
		or instance.rune_instance_contract_id!=INSTANCE_CONTRACT or not _integer(instance.item_id) or not _records.has(int(instance.item_id)) \
		or not _integer(instance.count) or instance.count!=1 or not instance.name is String or instance.name.length()>256 \
		or not instance.instance_id is String or instance.instance_id.is_empty() or instance.instance_id.length()>128: return false
	var pattern:=RegEx.new(); pattern.compile("^[a-z0-9:_-]+$")
	return pattern.search(instance.instance_id)!=null
static func _keys(value: Dictionary,fields: Array) -> bool:
	if value.size()!=fields.size(): return false
	for field: String in fields:
		if not value.has(field): return false
	return true
static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value))
