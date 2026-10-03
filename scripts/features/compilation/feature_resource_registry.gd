extends RefCounted

const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const PATH := "res://assets/data/features/resource_registry.json"
const AUDIO_SOURCE := "res://assets/data/audio/audio_bindings.source.json"
const AUDIO_RUNTIME := "res://assets/data/audio/audio_bindings.runtime.json"
const SOURCE_POLICY := "res://assets/data/source_priority_policy.json"
static var _loaded := false
static var _result: Dictionary = {}

static func declarations() -> Dictionary:
	if _loaded: return _result
	_loaded = true
	var input: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	_result = validate(input)
	return _result

static func validate(input: Variant) -> Dictionary:
	var errors: Array[String] = []
	var records := {}
	var identities := {}
	var audio_source: Variant = null
	var audio_runtime: Variant = null
	var source_policy: Variant = null
	if not input is Dictionary or input.get("schema_version") != 1 or not input.get("resources") is Array or input.size() != 2:
		return _reject(["feature_resource_registry_invalid"])
	for entry: Variant in input.resources:
		if not entry is Dictionary or entry.size() != 4 or not entry.get("resource_id") is String \
			or not entry.get("path") is String or entry.get("type") not in ["Texture2D", "AudioStream"] or not entry.get("origin") is Dictionary:
			errors.append("feature_resource_declaration_invalid")
			continue
		var path: String = entry.path
		var id: String = entry.resource_id
		var origin: Dictionary = entry.origin
		if not _identity_valid(id) or identities.has(id) or records.has(path):
			errors.append("feature_resource_identity_invalid:" + id)
		var resource_type: String = entry.type
		var trusted_path := (path.begins_with("res://assets/art/") and path.ends_with(".png")) if resource_type == "Texture2D" \
			else (path.begins_with("res://assets/audio/sfx/client/") and path.ends_with(".wav"))
		if not trusted_path or path.simplify_path() != path or "\\" in path:
			errors.append("feature_resource_path_untrusted:" + path)
		# This declaration points to the existing primary art authority. It does
		# not copy item attributes or authorize arbitrary project/script paths.
		if resource_type == "Texture2D" and (origin.size() != 3 or origin.get("lane") != "client_assets" \
			or not origin.get("entity_id") is String or origin.get("surface") not in ["inventoryIcon", "dropIcon"] \
			or GameData.get_entity_record(origin.get("entity_id", "")).is_empty() \
			or GameData.get_item_art_path(origin.get("entity_id", ""), origin.get("surface", "")) != path):
			errors.append("feature_resource_primary_origin_mismatch:" + id)
		if resource_type == "AudioStream":
			if audio_source == null:
				audio_source = JSON.parse_string(FileAccess.get_file_as_string(AUDIO_SOURCE))
				audio_runtime = JSON.parse_string(FileAccess.get_file_as_string(AUDIO_RUNTIME))
				source_policy = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_POLICY))
			if not _audio_origin_valid(path, origin, audio_source, audio_runtime, source_policy):
				errors.append("feature_resource_primary_origin_mismatch:" + id)
		if not ResourceLoader.exists(path, resource_type):
			errors.append("feature_resource_missing:" + id)
		identities[id] = true
		records[path] = entry
	if not errors.is_empty(): return _reject(errors)
	var owned := Graph.capture(records)
	if not owned.success: return _reject(owned.errors)
	var identity_paths := {}
	for path: String in owned.value: identity_paths[owned.value[path].resource_id] = path
	identity_paths.make_read_only()
	return {"success":true, "records":owned.value, "identity_paths":identity_paths, "errors":[]}

static func _reject(errors: Array) -> Dictionary:
	return {"success":false, "records":{}, "errors":errors}

static func resource_type(path: String) -> String:
	var declared := declarations()
	return str(declared.records.get(path, {}).get("type", "")) if declared.success else ""

static func record_by_id(id: String) -> Dictionary:
	var declared := declarations()
	if not declared.success: return {}
	return declared.records.get(declared.get("identity_paths", {}).get(id, ""), {})

static func valid_resource(path: String, resource: Variant) -> bool:
	if not resource is Resource or resource.resource_path != path: return false
	match resource_type(path):
		"Texture2D": return resource is Texture2D and resource.get_width() > 0 and resource.get_height() > 0
		"AudioStream": return resource is AudioStream and resource.get_length() > 0
	return false

static func _audio_origin_valid(path: String, origin: Dictionary, authoring: Variant, runtime: Variant, policy: Variant) -> bool:
	# Resolve once against the existing audited audio authoring/generation chain.
	# Display names never participate; this is the exact numeric import boundary.
	if origin.size() != 3 or origin.get("lane") != "client_assets" or not origin.get("event_id") is String \
		or not (origin.get("sound_id") is int or origin.get("sound_id") is float): return false
	if not authoring is Dictionary or authoring.get("source_priority_lane") != "client_assets" \
		or not authoring.get("events") is Array or not authoring.get("source_policy_primary") is Dictionary \
		or not runtime is Dictionary or runtime.get("source_authoring") != AUDIO_SOURCE or not runtime.get("events") is Dictionary \
		or not policy is Dictionary: return false
	var primary: Dictionary = authoring.source_policy_primary
	var authorized := false
	for source: Variant in policy.get("lanes", {}).get("client_assets", {}).get("sources", []):
		if source is Dictionary and source.get("tier") == "primary" and source.get("eligible") == true \
			and source.get("distribution") == primary.get("distribution"):
			authorized = true
	if not authorized: return false
	var event: Variant = runtime.events.get(origin.event_id)
	if not event is Dictionary or event.get("mapping_status") != "EXACT" or path not in event.get("runtime_paths", []): return false
	var matched := 0
	var valid := false
	for definition: Variant in authoring.events:
		if not definition is Dictionary or definition.get("event_id") != origin.event_id: continue
		if definition.get("mapping_status") != "EXACT" or not definition.get("samples") is Array: return false
		for sample: Variant in definition.samples:
			if not sample is Dictionary or sample.get("sound_id") != origin.sound_id: continue
			matched += 1
			valid = sample.get("runtime_path") == path and sample.get("mapping_status") == "EXACT" \
				and sample.get("source_sha256") is String and FileAccess.get_sha256(path) == sample.source_sha256
	return matched == 1 and valid

static func _identity_valid(value: String) -> bool:
	if not value.begins_with("hc.resource."): return false
	for character: String in value:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789._": return false
	return true
