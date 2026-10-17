extends RefCounted

## Transport every Dictionary as ordered key/value rows. Native value graph
## only admits String/Int/Float dictionary keys; original Vector2i cache keys
## are values in these rows, then restored to local mathematical dictionaries.
const MathValidator := preload("res://scripts/gameplay/world/world_environment_math_validator.gd")
const CONTRACT_ID := "world.environment.math_dictionary_wire.v1"

static func encode(value: Variant) -> Dictionary:
	var checked: Dictionary = MathValidator.copy_and_seal(value)
	if not checked.ok:
		return {"ok": false, "errors": checked.errors}
	var state := {"sources": [], "values": [], "buckets": {}}
	return {"ok": true, "errors": [], "wire": _encode(value, state)}

static func _encode(value: Variant, state: Dictionary) -> Variant:
	if not value is Dictionary and not value is Array:
		return value
	var bucket_id: int = (int(hash(value)) << 1) | (1 if value is Dictionary else 0)
	for index: int in state.buckets.get(bucket_id, []):
		if is_same(value, state.sources[index]):
			return state.values[index]
	if value is Dictionary:
		var wire := {"codec": CONTRACT_ID, "key_builtin": value.get_typed_key_builtin(),
			"value_builtin": value.get_typed_value_builtin(), "entries": []}
		if not state.buckets.has(bucket_id): state.buckets[bucket_id] = []
		state.buckets[bucket_id].append(state.sources.size())
		state.sources.append(value)
		state.values.append(wire)
		for key: Variant in value:
			wire.entries.append([key, _encode(value[key], state)])
		return wire
	var array: Array = value.duplicate(false)
	array.clear()
	if not state.buckets.has(bucket_id): state.buckets[bucket_id] = []
	state.buckets[bucket_id].append(state.sources.size())
	state.sources.append(value)
	state.values.append(array)
	for child: Variant in value:
		array.append(_encode(child, state))
	return array

static func decode(wire: Variant) -> Dictionary:
	if not ClassDB.class_exists("HardCoreContentValueGraph"):
		return {"ok": false, "errors": ["native_math_value_graph_missing"]}
	var native: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph") as RefCounted
	if native == null or not native.has_method("validate"):
		return {"ok": false, "errors": ["native_math_value_graph_invalid"]}
	var checked: Dictionary = native.call("validate", wire, false)
	if not bool(checked.get("success", false)):
		return {"ok": false, "errors": checked.get("errors", [])}
	var state := {"sources": [], "values": [], "buckets": {}, "errors": []}
	var restored: Variant = _decode(wire, state)
	if not state.errors.is_empty():
		return {"ok": false, "errors": state.errors}
	var math: Dictionary = MathValidator.copy_and_seal(restored)
	if not math.ok:
		return {"ok": false, "errors": math.errors}
	return {"ok": true, "errors": [], "value": restored}

static func _decode(value: Variant, state: Dictionary) -> Variant:
	if not value is Dictionary and not value is Array:
		return value
	var bucket_id: int = (int(hash(value)) << 1) | (1 if value is Dictionary else 0)
	for index: int in state.buckets.get(bucket_id, []):
		if is_same(value, state.sources[index]):
			return state.values[index]
	if value is Dictionary:
		if value.size() != 4 or value.get("codec") != CONTRACT_ID or not value.get("key_builtin") is int or not value.get("value_builtin") is int or not value.get("entries") is Array:
			state.errors.append("math_dictionary_wire_invalid")
			return null
		var key_type: int = value.key_builtin
		var value_type: int = value.value_builtin
		if key_type < TYPE_NIL or key_type >= TYPE_MAX or value_type < TYPE_NIL or value_type >= TYPE_MAX or key_type == TYPE_OBJECT or value_type == TYPE_OBJECT:
			state.errors.append("math_dictionary_wire_type_invalid")
			return null
		var dictionary: Dictionary = Dictionary({}, key_type, &"", null, value_type, &"", null)
		if not state.buckets.has(bucket_id): state.buckets[bucket_id] = []
		state.buckets[bucket_id].append(state.sources.size())
		state.sources.append(value)
		state.values.append(dictionary)
		for row: Variant in value.entries:
			if not row is Array or row.size() != 2:
				state.errors.append("math_dictionary_wire_row_invalid")
				return null
			if dictionary.has(row[0]):
				state.errors.append("math_dictionary_wire_duplicate_key")
				return null
			dictionary[row[0]] = _decode(row[1], state)
		dictionary.make_read_only()
		return dictionary
	var array: Array = value.duplicate(false)
	array.clear()
	if not state.buckets.has(bucket_id): state.buckets[bucket_id] = []
	state.buckets[bucket_id].append(state.sources.size())
	state.sources.append(value)
	state.values.append(array)
	for child: Variant in value:
		array.append(_decode(child, state))
	array.make_read_only()
	return array
