extends RefCounted

const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const PATH := "res://assets/data/features/resource_registry.json"
static var _loaded := false
static var _result: Dictionary = {}

static func declarations() -> Dictionary:
	if _loaded: return _result
	_loaded = true
	var input: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var errors: Array[String] = []
	var records := {}
	var identities := {}
	if not input is Dictionary or input.get("schema_version") != 1 or not input.get("resources") is Array or input.size() != 2:
		return _reject(["feature_resource_registry_invalid"])
	for entry: Variant in input.resources:
		if not entry is Dictionary or entry.size() != 4 or not entry.get("resource_id") is String \
			or not entry.get("path") is String or entry.get("type") != "Texture2D" or not entry.get("origin") is Dictionary:
			errors.append("feature_resource_declaration_invalid")
			continue
		var path: String = entry.path
		var id: String = entry.resource_id
		var origin: Dictionary = entry.origin
		if not _identity_valid(id) or identities.has(id) or records.has(path):
			errors.append("feature_resource_identity_invalid:" + id)
		if not path.begins_with("res://assets/art/") or not path.ends_with(".png") or path.simplify_path() != path or "\\" in path:
			errors.append("feature_resource_path_untrusted:" + path)
		# This declaration points to the existing primary art authority. It does
		# not copy item attributes or authorize arbitrary project/script paths.
		if origin.size() != 3 or origin.get("lane") != "client_assets" \
			or not origin.get("entity_id") is String or origin.get("surface") not in ["inventoryIcon", "dropIcon"] \
			or GameData.get_entity_record(origin.get("entity_id", "")).is_empty() \
			or GameData.get_item_art_path(origin.get("entity_id", ""), origin.get("surface", "")) != path:
			errors.append("feature_resource_primary_origin_mismatch:" + id)
		if not ResourceLoader.exists(path, "Texture2D"):
			errors.append("feature_resource_missing:" + id)
		identities[id] = true
		records[path] = entry
	if not errors.is_empty(): return _reject(errors)
	var owned := Graph.capture(records)
	if not owned.success: return _reject(owned.errors)
	_result = {"success":true, "records":owned.value, "errors":[]}
	return _result

static func _reject(errors: Array) -> Dictionary:
	_result = {"success":false, "records":{}, "errors":errors}
	return _result

static func _identity_valid(value: String) -> bool:
	if not value.begins_with("hc.resource."): return false
	for character: String in value:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789._": return false
	return true
