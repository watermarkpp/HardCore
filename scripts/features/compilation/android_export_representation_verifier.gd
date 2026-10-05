extends RefCounted

# Plain verifier called once per existing FeatureResourcePreparation quantum.
# No queue, loader, cache authority, target load, await, or Script instantiation.
const CHUNK_BYTES := 16384
const MAX_FILE_BYTES := 524288
const MAX_PACKED_RECORDS := 130
var _seal: Dictionary = {}
var _tasks: Array = []
var _cursor := 0
var _file: FileAccess
var _hash: HashingContext
var _buffer := PackedByteArray()
var _verified := false
var _failed := false
var _shader_text: Dictionary = {}

static func begin(seal: Dictionary, seal_sha256: String, context_only := false) -> RefCounted:
	if OS.get_name() != "Android" or OS.has_feature("editor") or seal.get("schema_version") != 1 or seal.get("contract_id") != "hc.android.controller_sealed_export.candidate.v1" or seal.get("runtime_mode") != "android_controller_sealed_export" or seal.get("runtime_native_image_sha") != "MISSING" or seal.get("native_token_device_acceptance") != "NOT_RUN":
		return null
	if seal_sha256.length() != 64 or seal.get("engine_commit") != Engine.get_version_info().get("hash") or not seal.get("build_verified_native_sha") is String or seal.build_verified_native_sha.length() != 64:
		return null
	if not seal.get("capabilities") is Dictionary or not seal.get("packed_records") is Array or not seal.get("context_records") is Array:
		return null
	var capabilities: Dictionary = seal.capabilities
	for name: String in ["classes", "constructors", "class_methods", "singletons", "singleton_methods", "variant_types"]:
		if not capabilities.get(name) is Array or capabilities[name].size() > 256:
			return null
	if capabilities.classes.is_empty() or seal.packed_records.size() > MAX_PACKED_RECORDS or seal.context_records.size() != 2:
		return null
	var result := new()
	result._seal = seal.duplicate(true)
	for name: String in capabilities.classes:
		result._tasks.append({"kind": "class", "name": name})
	for name: String in capabilities.constructors:
		result._tasks.append({"kind": "constructor", "name": name})
	for record: Dictionary in capabilities.class_methods:
		result._tasks.append({"kind": "method", "record": record})
	for name: String in capabilities.singletons:
		result._tasks.append({"kind": "singleton", "name": name})
	for record: Dictionary in capabilities.singleton_methods:
		result._tasks.append({"kind": "singleton_method", "record": record})
	for name: String in capabilities.variant_types:
		result._tasks.append({"kind": "variant", "name": name})
	var paths := {}
	for record: Dictionary in seal.context_records + ([] if context_only else seal.packed_records):
		if not record.get("path") is String or not record.path.begins_with("res://") or record.path.simplify_path() != record.path or "\\" in record.path or paths.has(record.path) or not record.get("sha256") is String or record.sha256.length() != 64 or (not record.get("bytes") is float and not record.get("bytes") is int):
			return null
		var size := int(record.bytes)
		if size <= 0 or size > MAX_FILE_BYTES or float(size) != float(record.bytes):
			return null
		paths[record.path] = true
		result._tasks.append({"kind": "file", "record": record})
	return result

func step() -> Dictionary:
	if _failed:
		return {"success": false, "done": true, "errors": ["android_export_verification_failed"]}
	if OS.get_name() != "Android" or Engine.get_version_info().get("hash") != _seal.engine_commit:
		return _refuse("android_engine_version_changed")
	if _cursor >= _tasks.size():
		_verified = true
		return {"success": true, "done": true, "errors": []}
	var task: Dictionary = _tasks[_cursor]
	match task.kind:
		"class":
			if not ClassDB.class_exists(task.name): return _refuse("android_missing_class:" + task.name)
		"constructor":
			if not ClassDB.class_exists(task.name) or not ClassDB.can_instantiate(task.name): return _refuse("android_missing_constructor:" + task.name)
		"method":
			var record: Dictionary = task.record
			if not record.get("class") is String or not record.get("method") is String or not ClassDB.class_has_method(record["class"], record.method):
				return _refuse("android_missing_class_method")
			# Enumerate the actual running ClassDB method list, including inherited
			# methods. Reflection concerns native classes only, never project Script.
			var methods: Array = ClassDB.class_get_method_list(record["class"])
			if methods.size() > 4096: return _refuse("android_method_list_capacity")
			var found := false
			for method: Dictionary in methods:
				if method.get("name") == record.method: found = true; break
			if not found: return _refuse("android_method_enumeration_mismatch")
		"singleton":
			if not Engine.has_singleton(task.name): return _refuse("android_missing_singleton:" + task.name)
		"singleton_method":
			var record: Dictionary = task.record
			if not record.get("singleton") is String or not record.get("method") is String or not Engine.has_singleton(record.singleton):
				return _refuse("android_missing_singleton_method")
			var singleton: Object = Engine.get_singleton(record.singleton)
			if singleton == null or not singleton.has_method(record.method): return _refuse("android_missing_singleton_method")
		"variant":
			var found := false
			for type: int in range(TYPE_MAX):
				if type_string(type) == task.name: found = true; break
			if not found: return _refuse("android_missing_variant_type:" + task.name)
		"file":
			return _step_file(task.record)
		_:
			return _refuse("android_unknown_verification_task")
	_cursor += 1
	return {"success": true, "done": false, "errors": []}

func _step_file(record: Dictionary) -> Dictionary:
	if _file == null:
		_file = FileAccess.open(record.path, FileAccess.READ)
		_hash = HashingContext.new()
		_buffer = PackedByteArray()
		if _file == null or _file.get_length() != int(record.bytes) or _hash.start(HashingContext.HASH_SHA256) != OK:
			return _refuse("android_export_size_or_hash_context:" + record.path)
	var remaining := _file.get_length() - _file.get_position()
	if remaining > 0:
		var count := mini(CHUNK_BYTES, remaining)
		var bytes := _file.get_buffer(count)
		if bytes.size() != count or _hash.update(bytes) != OK: return _refuse("android_export_read:" + record.path)
		if bool(record.get("capture_text", false)): _buffer.append_array(bytes)
		return {"success": true, "done": false, "errors": []}
	var actual := _hash.finish().hex_encode()
	_file.close()
	_file = null
	_hash = null
	if actual != record.sha256: return _refuse("android_export_hash:" + record.path)
	if bool(record.get("capture_text", false)): _shader_text[record.path] = _buffer.get_string_from_utf8()
	_buffer = PackedByteArray()
	_cursor += 1
	return {"success": true, "done": false, "errors": []}

func _refuse(reason: String) -> Dictionary:
	_failed = true
	cancel()
	return {"success": false, "done": true, "errors": [reason]}

func cancel() -> void:
	_failed = true
	if _file != null: _file.close()
	_file = null
	_hash = null
	_buffer = PackedByteArray()

func is_verified() -> bool:
	return _verified and not _failed and OS.get_name() == "Android" and Engine.get_version_info().get("hash") == _seal.get("engine_commit")

func valid_script(path: String, resource: Resource) -> bool:
	return is_verified() and _seal.nodes.has(path) and _seal.nodes[path].kind in ["script", "resident_script"] and resource is Script and resource.resource_path == path and not (resource as Script).has_source_code()

func valid_shader(path: String, resource: Resource) -> bool:
	return is_verified() and _shader_text.has(path) and resource is Shader and resource.resource_path == path and (resource as Shader).code == _shader_text[path]

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE: cancel()
