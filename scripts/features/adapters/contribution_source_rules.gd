extends RefCounted

const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const PATH := "res://assets/data/features/contribution_sources.json"
const CONTRACT := "hc.feature.contribution.sources.v1"
const DROP_CONTRACTS := ["item.drop.affix.v1","item.drop.affix.v2","item.drop.affix.v3"]
static var _affixes: Dictionary = {}

# Registered selectors are views of already validated, persisted modifiers.
# They never roll an affix, edit the old item or grant an attribute twice.
static func affix_definition(id: String) -> Dictionary:
	if not _ensure_loaded(): return {}
	return _affixes.get(id,{})

static func matching_affix_indices(base: Dictionary, definition: Dictionary) -> Array[int]:
	var result: Array[int]=[]
	if definition.is_empty() or not base.get("drop_affix") is Dictionary \
		or base.drop_affix.get("contract_id")!=definition.drop_affix_contract \
		or base.drop_affix.get("applied")!=true or not base.get("modifiers") is Array: return result
	for index in base.modifiers.size():
		var modifier: Variant=base.modifiers[index]
		if modifier is Dictionary and modifier.get("stat")==definition.stat and modifier.get("op")==definition.op \
			and (modifier.get("value") is int or modifier.get("value") is float) \
			and is_finite(float(modifier.value)) and float(modifier.value)>0: result.append(index)
	return result

static func _ensure_loaded() -> bool:
	if not _affixes.is_empty(): return true
	var document: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not document is Dictionary or not _keys(document,["schema_version","contract_id","affixes"]) \
		or not (document.schema_version is int or document.schema_version is float) \
		or document.schema_version!=1 or document.contract_id!=CONTRACT \
		or not document.affixes is Array or document.affixes.is_empty() or document.affixes.size()>64: return false
	var captured:=Graph.capture(document,2048,8)
	if not captured.success: return false
	var definitions: Dictionary={}
	for record: Variant in captured.value.affixes:
		if not record is Dictionary or not _keys(record,["affix_id","drop_affix_contract","stat","op","positive_only"]) \
			or not record.affix_id is String or not record.affix_id.begins_with("hc.affix.") \
			or not Compiler._stable_id(record.affix_id) or definitions.has(record.affix_id) \
			or record.drop_affix_contract not in DROP_CONTRACTS or not record.stat is String \
			or not record.op is String or record.op!="add" or not record.positive_only is bool or record.positive_only!=true: return false
		definitions[record.affix_id]=record
	_affixes=Graph.capture(definitions,2048,8).value
	return true

static func _keys(value: Dictionary,fields: Array) -> bool:
	if value.size()!=fields.size(): return false
	for field: String in fields:
		if not value.has(field): return false
	return true
