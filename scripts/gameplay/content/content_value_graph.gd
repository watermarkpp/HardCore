extends RefCounted

## Content indexes use numeric keys. This boundary owns an independent graph,
## preserves shared subgraphs, and rejects cycles and all engine objects.
static func capture(value: Variant, read_only := true) -> Dictionary:
	if ClassDB.class_exists("HardCoreContentValueGraph"):
		var native: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
		return native.call("capture", value, read_only, true)
	var checked := validate(value)
	if not checked.success: return {"success": false, "value": null, "errors": checked.errors}
	var state := {"errors": [], "memo": {}}
	var copy: Variant = _copy(value, [], state, read_only)
	return {"success": state.errors.is_empty(), "value": copy, "errors": state.errors}

static func validate(value: Variant) -> Dictionary:
	if ClassDB.class_exists("HardCoreContentValueGraph"):
		var native: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
		return native.call("validate", value, true)
	var state := {"errors": [], "nodes": 0}
	_validate(value, [], state)
	return {"success": state.errors.is_empty(), "errors": state.errors}

static func _copy(value: Variant, ancestors: Array, state: Dictionary, read_only: bool) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_FLOAT:
			if is_finite(value): return value
			state.errors.append("non_finite_content_number")
			return null
		TYPE_DICTIONARY, TYPE_ARRAY:
			for parent: Variant in ancestors:
				if is_same(parent, value):
					state.errors.append("cyclic_content_graph")
					return null
			var value_hash: int = hash(value)
			var bucket: Array = state.memo.get(value_hash, [])
			for pair: Array in bucket:
				if is_same(pair[0], value): return pair[1]
			# duplicate retains typed Array/Dictionary element types.
			var result: Variant = value.duplicate()
			result.clear()
			bucket.append([value, result])
			state.memo[value_hash] = bucket
			ancestors.append(value)
			if value is Array:
				for child: Variant in value:
					result.append(_copy(child, ancestors, state, read_only))
					if not state.errors.is_empty(): break
			else:
				for key: Variant in value:
					if not (key is String or key is int or (key is float and is_finite(key))):
						state.errors.append("non_value_content_key")
						break
					result[key] = _copy(value[key], ancestors, state, read_only)
					if not state.errors.is_empty(): break
			ancestors.pop_back()
			if read_only: result.make_read_only()
			return result
		_:
			state.errors.append("non_value_content:" + type_string(typeof(value)))
			return null

static func fingerprint(value: Variant) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(value))
	return hashing.finish().hex_encode()

static func _validate(value: Variant, ancestors: Array, state: Dictionary) -> void:
	state.nodes += 1
	if state.nodes > 8000000 or ancestors.size() > 64:
		state.errors.append("content_graph_capacity")
		return
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return
		TYPE_FLOAT:
			if not is_finite(value): state.errors.append("non_finite_content_number")
		TYPE_DICTIONARY, TYPE_ARRAY:
			for parent: Variant in ancestors:
				if is_same(parent, value):
					state.errors.append("cyclic_content_graph")
					return
			ancestors.append(value)
			for key: Variant in value:
				if value is Dictionary:
					if not (key is String or key is int or (key is float and is_finite(key))):
						state.errors.append("non_value_content_key")
						break
					_validate(value[key], ancestors, state)
				else:
					_validate(key, ancestors, state)
				if not state.errors.is_empty(): break
			ancestors.pop_back()
		_:
			state.errors.append("non_value_content:" + type_string(typeof(value)))
