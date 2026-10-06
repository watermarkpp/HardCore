extends RefCounted

const AndroidVerifier := preload("res://scripts/features/compilation/android_export_representation_verifier.gd")
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const PRODUCER_ID := "hc.code_preparation.lexical_subset.candidate.v1"
const SUPPORTED_SCOPE := "supported_gdscript_compile_inputs"
const MAX_NODES := 64
const MAX_EDGES := 1024
const MAX_PLAN_BYTES := 65536
const MAX_SOURCE_BYTES := 524288
const MAX_FILE_BYTES := 524288
const MAX_PLAN_COMPONENTS := 8192
const MAX_PLAN_DEPTH := 32
var _export_verifier: RefCounted
var _export_done := false
var _payload: Dictionary = {}
var _entry_id := ""
var _paths: Array = []
var _source_paths: Array = []
var _cursor := 0
var _verified := false
var _failed := false
var _live_tree_owner: WeakRef
var _residency_requirements: Array = []
var _residency_cursor := 0
var _residency_nodes: Dictionary = {}
var _residency_scripts: Dictionary = {}
var _publication_owner: WeakRef
var _publication: Dictionary = {}
var _signature := ""

# Only the live registered ContentLayers publisher may supply this authority.
# Caller booleans and author/player JSON cannot issue a publication witness.
# The helper validates an envelope; it does not certify a lexical producer as
# a full GDScript analyzer. Its real owner API is in the production candidate.
static func begin_verification(payload: Dictionary, entry_id: String, publication_owner: Variant, live_tree_owner: Node = null) -> Dictionary:
	if not publication_owner is Node or not is_instance_valid(publication_owner) or not is_instance_valid(live_tree_owner) or not live_tree_owner.is_inside_tree():
		return _reject("MISSING:registered_code_publication_owner")
	if not is_same(live_tree_owner.get_tree().root.get_node_or_null("ContentLayers"), publication_owner) or publication_owner.is_queued_for_deletion():
		return _reject("code_preparation_wrong_publication_owner")
	var publisher_script: Script = publication_owner.get_script() as Script
	if publisher_script == null or publisher_script.resource_path != "res://scripts/layers/runtime/content_layer_registry.gd":
		return _reject("code_preparation_wrong_publication_script")
	if not publication_owner.has_method("code_preparation_published_entry") or not publication_owner.has_method("is_code_preparation_publication_current"):
		return _reject("MISSING:registered_code_authoring_and_verified_producer")
	if payload.get("producer_id") != PRODUCER_ID or payload.get("scope") != SUPPORTED_SCOPE:
		return _reject("code_preparation_producer_or_scope_mismatch")
	if payload.get("status") != "PASS" or payload.get("errors") != []:
		return _reject("code_preparation_producer_rejected")
	if not payload.get("nodes") is Dictionary or not payload.get("edges") is Array or not payload.get("prepared_inputs") is Array:
		return _reject("code_preparation_graph_shape")
	if not payload.get("source_fingerprints") is Dictionary:
		return _reject("code_preparation_fingerprint_shape")
	var nodes: Dictionary = payload.nodes
	if nodes.size() > MAX_NODES or payload.edges.size() > MAX_EDGES:
		return _reject("code_preparation_graph_capacity")
	var target: Variant = payload.get("target_path")
	if not target is String or not nodes.has(target) or not nodes[target] is Dictionary or nodes[target].get("kind") != "script":
		return _reject("code_preparation_target_not_supported_script")
	var inputs: Array = []
	var source_bytes := 0
	for path: Variant in nodes:
		var node: Variant = nodes[path]
		if not path is String or not path.begins_with("res://") or path.simplify_path() != path or "\\" in path:
			return _reject("code_preparation_path_invalid")
		if not node is Dictionary or node.get("kind") not in ["script", "asset", "resident_script"] or not node.get("sha256") is String or node.sha256.length() != 64:
			return _reject("code_preparation_node_invalid")
		if not _integer_in_range(node.get("bytes"), 0, MAX_FILE_BYTES):
			return _reject("code_preparation_source_file_capacity")
		source_bytes += int(node.bytes)
		if source_bytes > MAX_SOURCE_BYTES:
			return _reject("code_preparation_source_set_capacity")
		if node.kind in ["script", "resident_script"] and (node.get("type") != "GDScript" or not path.ends_with(".gd")):
			return _reject("code_preparation_script_format_unsupported")
		if node.kind == "asset":
			if node.get("type") != "Shader" or not path.ends_with(".gdshader"):
				return _reject("code_preparation_asset_format_unsupported")
			inputs.append(path)
	var source_context: Variant = payload.source_fingerprints.get("source_context")
	if not source_context is Dictionary or source_context.size() != 2 or not source_context.has("res://project.godot") or not source_context.has("res://.godot/global_script_class_cache.cfg"):
		return _reject("code_preparation_authoring_context_missing")
	for path: String in source_context:
		var record: Variant = source_context[path]
		if not record is Dictionary or not record.get("sha256") is String or record.sha256.length() != 64 or not _integer_in_range(record.get("bytes"), 0, MAX_FILE_BYTES):
			return _reject("code_preparation_authoring_context_shape_or_capacity")
		source_bytes += int(record.bytes)
		if source_bytes > MAX_SOURCE_BYTES:
			return _reject("code_preparation_source_set_capacity")
	if source_context["res://project.godot"].sha256 != payload.source_fingerprints.get("project.godot") or source_context["res://.godot/global_script_class_cache.cfg"].sha256 != payload.source_fingerprints.get("class_cache"):
		return _reject("code_preparation_authoring_context_binding")
	var reachable := {target: true}
	var work: Array = [target]
	var cursor := 0
	while cursor < work.size():
		var source: String = work[cursor]
		cursor += 1
		for edge: Variant in payload.edges:
			if not edge is Dictionary or edge.get("kind") not in ["preload", "extends_script", "named_class", "autoload_symbol"]:
				return _reject("code_preparation_edge_unsupported")
			if not nodes.has(edge.get("from")) or not nodes.has(edge.get("to")):
				return _reject("code_preparation_edge_unresolved")
			if edge.from == source and not reachable.has(edge.to):
				reachable[edge.to] = true
				work.append(edge.to)
	if reachable.size() != nodes.size():
		return _reject("code_preparation_unreachable_node")
	inputs.sort()
	var claimed: Array = payload.prepared_inputs.duplicate()
	claimed.sort()
	if inputs != claimed:
		return _reject("code_preparation_input_set_mismatch")
	if not payload.get("runtime_residency_requirements") is Array:
		return _reject("code_preparation_residency_contract_missing")
	var residency_names: Dictionary = {}
	for requirement: Variant in payload.runtime_residency_requirements:
		if not requirement is Dictionary or requirement.get("kind") != "autoload_residency" or not requirement.get("autoload_name") is String:
			return _reject("code_preparation_residency_requirement_invalid")
		if requirement.get("stage") != "before_code_request" or requirement.autoload_name.is_empty() or "/" in requirement.autoload_name or "\\" in requirement.autoload_name or residency_names.has(requirement.autoload_name):
			return _reject("code_preparation_residency_identity_or_stage_invalid")
		if not nodes.has(requirement.get("script_path")) or nodes[requirement.script_path].kind != "resident_script" or requirement.get("source_sha256") != nodes[requirement.script_path].sha256:
			return _reject("code_preparation_residency_source_mismatch")
		residency_names[requirement.autoload_name] = requirement.script_path
	var referenced_residencies: Dictionary = {}
	for edge: Dictionary in payload.edges:
		if edge.kind == "autoload_symbol":
			if not residency_names.has(edge.get("class_name")) or residency_names[edge.class_name] != edge.to:
				return _reject("code_preparation_autoload_edge_without_residency")
			referenced_residencies[edge.class_name] = true
	if referenced_residencies.size() != residency_names.size():
		return _reject("code_preparation_residency_without_reference")
	var captured := Graph.capture(payload, MAX_PLAN_COMPONENTS, MAX_PLAN_DEPTH)
	if not captured.success:
		return _reject("code_preparation_nonplain_or_component_capacity")
	var serialized := JSON.stringify(captured.value, "", true)
	if serialized.to_utf8_buffer().size() > MAX_PLAN_BYTES:
		return _reject("code_preparation_plan_byte_capacity")
	var published_value: Variant = publication_owner.code_preparation_published_entry(entry_id)
	if not published_value is Dictionary:
		return _reject("code_preparation_published_entry_missing")
	var published: Dictionary = published_value
	if published.get("entry_id") != entry_id or published.get("target_path") != target or published.get("plan_sha256") != serialized.sha256_text() or published.get("producer_sha256") != payload.get("source_fingerprints", {}).get("producer") or not published.get("generation") is int or not published.get("source_revision") is String:
		return _reject("code_preparation_publication_binding_mismatch")
	if not bool(publication_owner.is_code_preparation_publication_current(entry_id, published.generation, published.source_revision, published.plan_sha256)):
		return _reject("code_preparation_publication_stale")
	var result := new()
	result._payload = captured.value
	result._entry_id = entry_id
	result._paths = inputs
	result._paths.make_read_only()
	result._source_paths = nodes.keys()
	result._source_paths.append_array(source_context.keys())
	result._source_paths.sort()
	result._residency_requirements = captured.value.runtime_residency_requirements
	result._publication_owner = weakref(publication_owner)
	result._publication = published.duplicate(true)
	result._publication.make_read_only()
	result._signature = JSON.stringify([entry_id, published.plan_sha256, published.generation, published.source_revision]).sha256_text()
	if OS.get_name() == "Android":
		if not publication_owner.has_method("code_preparation_export_identity") or published.get("runtime_mode") != "android_controller_sealed_export":
			return _reject("MISSING:controller_sealed_android_publication")
		var identity: Dictionary = publication_owner.code_preparation_export_identity(entry_id)
		if identity.get("seal_sha256") != published.get("export_seal_sha256") or not identity.get("seal") is Dictionary:
			return _reject("android_export_publication_binding")
		result._export_verifier = AndroidVerifier.begin(identity.seal, identity.seal_sha256)
		if result._export_verifier == null: return _reject("android_export_contract_rejected")
	elif OS.get_name() != "Windows":
		return _reject("code_preparation_platform_unknown")
	if is_instance_valid(live_tree_owner):
		result._live_tree_owner = weakref(live_tree_owner)
	return {"success": true, "errors": [], "plan": result}

static func _reject(error: String) -> Dictionary:
	return {"success": false, "errors": [error], "plan": null}

static func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum

# Invoke once per existing feature_resources Budget quantum. All file hash
# work must be measured; no await/signal escapes with an open budget scope.
func verify_next_source() -> Dictionary:
	if not publication_current():
		_failed = true
		return {"success": false, "done": true, "errors": ["code_preparation_publication_changed"]}
	if _failed:
		return {"success": false, "done": true, "errors": ["code_preparation_verification_failed"]}
	if _export_verifier != null and not _export_done:
		var checked: Dictionary = _export_verifier.step()
		if not checked.success:
			_failed = true
			return checked
		if checked.done:
			_export_done = true
			_cursor = _source_paths.size()
		return {"success": true, "done": false, "errors": []}
	if _cursor < _source_paths.size():
		var path: String = _source_paths[_cursor]
		_cursor += 1
		var record: Dictionary = _source_record(path)
		var checkout_bytes := PackedByteArray()
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			checkout_bytes = file.get_buffer(file.get_length())
			file.close()
		var raw_matches: bool = _checkout_bytes_match_fingerprint(checkout_bytes, record)
		# A Windows core.autocrlf checkout expands LF-blob fingerprints to
		# CRLF on disk; that is a platform property, not a content change
		# (the catalog fingerprints are cut from the LF repo blobs). Before
		# failing the source, re-hash the checkout bytes normalized back to
		# LF. A real content edit still fails this normalized comparison.
		if file == null or not raw_matches:
			_failed = true
			return {"success": false, "done": true, "errors": ["code_preparation_source_changed:" + path]}
	elif _residency_cursor < _residency_requirements.size():
		var requirement: Dictionary = _residency_requirements[_residency_cursor]
		_residency_cursor += 1
		if not _capture_current_residency(requirement):
			_failed = true
			return {"success": false, "done": true, "errors": ["code_preparation_autoload_not_resident:" + requirement.autoload_name]}
	_verified = _cursor == _source_paths.size() and _residency_cursor == _residency_requirements.size()
	if _verified and not residency_current():
		_failed = true
		return {"success": false, "done": true, "errors": ["code_preparation_residency_changed"]}
	return {"success": true, "done": _verified, "errors": []}

func _source_record(path: String) -> Dictionary:
	return _payload.nodes[path] if _payload.nodes.has(path) else _payload.source_fingerprints.source_context[path]


# Hash the checkout bytes with every CRLF pair collapsed to LF. The catalog
# fingerprints for `i/lf` sources are cut from the LF repo blobs, so a
# CRLF checkout only matches after this normalization; genuine content
# edits diverge in the normalized hash as well.
static func _normalized_lf_matches(checkout_bytes: PackedByteArray, record: Dictionary) -> bool:
	if checkout_bytes.is_empty():
		return false
	var normalized := checkout_bytes.duplicate()
	var write := 0
	for read in normalized.size():
		var b := normalized[read]
		if b == 13 and read + 1 < normalized.size() and normalized[read + 1] == 10:
			continue
		normalized[write] = b
		write += 1
	normalized.resize(write)
	return normalized.size() == record.bytes and _sha256_hex(normalized) == str(record.sha256)


# Shared admission predicate: byte-for-byte first, then the LF-normalized
# retry so a Windows autocrlf checkout of an LF-blob fingerprint still
# matches. A real content edit fails both comparisons.
static func _checkout_bytes_match_fingerprint(checkout_bytes: PackedByteArray, record: Dictionary) -> bool:
	if checkout_bytes.is_empty():
		return false
	if checkout_bytes.size() == record.bytes and _sha256_hex(checkout_bytes) == str(record.sha256):
		return true
	return _normalized_lf_matches(checkout_bytes, record)


static func _sha256_hex(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func is_verified() -> bool:
	return _verified and not _failed and publication_current() and residency_current()

func publication_current() -> bool:
	var publisher: Node = _publication_owner.get_ref() if _publication_owner != null else null
	var context: Node = _live_tree_owner.get_ref() if _live_tree_owner != null else null
	if not is_instance_valid(publisher) or publisher.is_queued_for_deletion() or not publisher.is_inside_tree() or not is_instance_valid(context) or not context.is_inside_tree():
		return false
	if not is_same(context.get_tree().root.get_node_or_null("ContentLayers"), publisher):
		return false
	var script: Script = publisher.get_script() as Script
	if script == null or script.resource_path != "res://scripts/layers/runtime/content_layer_registry.gd":
		return false
	return bool(publisher.is_code_preparation_publication_current(_entry_id, _publication.generation, _publication.source_revision, _publication.plan_sha256))

# Once per code admission, inside the host's existing Loading Budget quantum,
# immediately followed by its real request without await/callback in between.
# This is deliberately not called from is_verified or a battle hot loop.
func revalidate_admission_sources() -> Dictionary:
	var began := Time.get_ticks_usec()
	var checked := 0
	if not is_verified():
		return {"success": false, "errors": ["code_preparation_admission_stale"], "elapsed_usec": Time.get_ticks_usec() - began}
	if _export_verifier != null:
		# Sealed APK res resources are immutable for this ContentLayers generation.
		# No full-source/packed-byte rehash on admission. Reject source-bearing or
		# incompatible cached Scripts without loading or instantiating any Script.
		for path: String in _payload.nodes:
			if _payload.nodes[path].kind not in ["script", "resident_script"]: continue
			var cached: Resource = ResourceLoader.get_cached_ref(path)
			if cached != null and not _export_verifier.valid_script(path, cached):
				_failed = true
				return {"success": false, "errors": ["android_cached_script_representation_changed"], "elapsed_usec": Time.get_ticks_usec() - began}
		return {"success": is_verified() and _export_verifier.is_verified(), "errors": [], "elapsed_usec": Time.get_ticks_usec() - began,
			"runtime_native_image_sha": "MISSING", "native_token_device_acceptance": "NOT_RUN"}
	for path: String in _source_paths:
		var file := FileAccess.open(path, FileAccess.READ)
		var record: Dictionary = _source_record(path)
		var checkout_bytes := PackedByteArray()
		if file != null:
			checkout_bytes = file.get_buffer(file.get_length())
			file.close()
		if not _checkout_bytes_match_fingerprint(checkout_bytes, record):
			_failed = true
			return {"success": false, "errors": ["code_preparation_admission_source_changed:" + path], "elapsed_usec": Time.get_ticks_usec() - began, "checked": checked}
		if _payload.nodes.has(path) and _payload.nodes[path].kind in ["script", "resident_script"]:
			var cached: Resource = ResourceLoader.get_cached_ref(path)
			var cached_script: Script = cached as Script
			if cached != null and (cached_script == null or cached_script.resource_path != path or cached_script.source_code != FileAccess.get_file_as_string(path)):
				_failed = true
				return {"success": false, "errors": ["code_preparation_admission_cached_source_changed:" + path], "elapsed_usec": Time.get_ticks_usec() - began, "checked": checked}
		checked += 1
	return {"success": is_verified(), "errors": [] if is_verified() else ["code_preparation_admission_publication_or_residency_changed"], "elapsed_usec": Time.get_ticks_usec() - began, "checked": checked}

func _capture_current_residency(requirement: Dictionary) -> bool:
	var context: Node = _live_tree_owner.get_ref() if _live_tree_owner != null else null
	if not is_instance_valid(context) or not context.is_inside_tree() or context.is_queued_for_deletion():
		return false
	var name: String = requirement.autoload_name
	if name.is_empty() or "/" in name or "\\" in name:
		return false
	var node: Node = context.get_tree().root.get_node_or_null(NodePath(name))
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return false
	var script: Script = node.get_script() as Script
	if script == null or script.resource_path != requirement.script_path:
		return false
	if _export_verifier != null:
		if not _export_verifier.valid_script(requirement.script_path, script): return false
	elif script.source_code != FileAccess.get_file_as_string(requirement.script_path):
		return false
	# Current tree instance and its already-owned Script, no Script load/new/get.
	_residency_nodes[name] = weakref(node)
	_residency_scripts[name] = weakref(script)
	return true

func residency_current() -> bool:
	var context: Node = _live_tree_owner.get_ref() if _live_tree_owner != null else null
	if not _residency_requirements.is_empty() and (not is_instance_valid(context) or not context.is_inside_tree() or context.is_queued_for_deletion()):
		return false
	for requirement: Dictionary in _residency_requirements:
		var name: String = requirement.autoload_name
		if not _residency_nodes.has(name) or not _residency_scripts.has(name):
			return false
		var node: Node = _residency_nodes[name].get_ref()
		var script: Script = _residency_scripts[name].get_ref()
		if not is_instance_valid(node) or not node.is_inside_tree() or node.is_queued_for_deletion() or script == null:
			return false
		if _export_verifier != null and not _export_verifier.valid_script(requirement.script_path, script): return false
		if not is_same(node.get_script(), script) or script.resource_path != requirement.script_path:
			return false
		if not is_same(context.get_tree().root.get_node_or_null(NodePath(name)), node):
			return false
	return true

func target_path() -> String:
	return _payload.get("target_path", "")

func paths() -> Array:
	return _paths

func signature() -> String:
	return _signature

func valid_asset(path: String, resource: Resource) -> bool:
	if not is_verified() or path not in _paths or not resource is Shader or resource.resource_path != path:
		return false
	if _export_verifier != null: return bool(_export_verifier.valid_shader(path, resource))
	if FileAccess.get_sha256(path) != _payload.nodes[path].sha256:
		return false
	var shader: Shader = resource as Shader
	return shader.code == FileAccess.get_file_as_string(path)

func valid_target(resource: Resource) -> bool:
	if not is_verified() or not resource is Script or resource.resource_path != target_path():
		return false
	if _export_verifier != null:
		return bool(_export_verifier.valid_script(target_path(), resource)) and is_same(ResourceLoader.get_cached_ref(target_path()), resource)
	var script: Script = resource as Script
	return FileAccess.get_sha256(target_path()) == _payload.nodes[target_path()].sha256 and script.source_code == FileAccess.get_file_as_string(target_path())


func transfer_loaded_retention_context(previous: Node, next_consumer: Node, service: Node) -> bool:
	if not is_verified() or _live_tree_owner == null or not is_same(_live_tree_owner.get_ref(), previous) or not is_instance_valid(next_consumer) or not next_consumer.is_inside_tree() or next_consumer.is_queued_for_deletion():
		return false
	var publisher: Node = _publication_owner.get_ref()
	if not is_instance_valid(service) or not is_same(publisher._feature_resources(), service) or not is_same(next_consumer.get_tree().root.get_node_or_null("ContentLayers"), publisher):
		return false
	var old_context: WeakRef = _live_tree_owner
	_live_tree_owner = weakref(next_consumer)
	if not is_verified():
		_live_tree_owner = old_context
		return false
	return true
