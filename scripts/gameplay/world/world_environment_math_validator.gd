extends RefCounted

## Explicit mathematical value boundary. No Object, Resource, Node or Callable.
## Packed containers use copy-on-write values; Dictionary/Array graphs are copied
## and made read-only. Dictionary vector keys and typed arrays retain their types.
static func copy_and_seal(value: Variant) -> Dictionary:
	var state := {"errors": [], "stack": []}
	var result: Variant = _copy(value, state, "$", 0)
	return {"ok": state.errors.is_empty(), "errors": state.errors, "value": result}

static func _copy(value: Variant, state: Dictionary, path: String, depth: int) -> Variant:
	if depth > 128:
		state.errors.append(path + ":depth")
		return null
	if value is Object or value is Callable or value is Signal or value is RID:
		state.errors.append(path + ":live_value")
		return null
	if value is Dictionary or value is Array:
		for ancestor: Variant in state.stack:
			if is_same(value, ancestor):
				state.errors.append(path + ":cycle")
				return null
		state.stack.append(value)
		var out: Variant = value.duplicate(false)
		out.clear()
		if value is Dictionary:
			for key: Variant in value:
				if key is Dictionary or key is Array or key is Object or key is Callable or key is Signal or key is RID:
					state.errors.append(path + ":nonvalue_key")
					continue
				var copied_key: Variant = _copy(key, state, path + ".key", depth + 1)
				out[copied_key] = _copy(value[key], state, path + "." + str(key), depth + 1)
		else:
			for index: int in range(value.size()):
				out.append(_copy(value[index], state, path + "[" + str(index) + "]", depth + 1))
		state.stack.pop_back()
		out.make_read_only()
		return out
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			return value
		TYPE_FLOAT:
			if not is_finite(value):
				state.errors.append(path + ":nonfinite")
			return value
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4:
			if not value.is_finite():
				state.errors.append(path + ":nonfinite")
			return value
		TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I:
			return value
		TYPE_RECT2:
			if not value.position.is_finite() or not value.size.is_finite():
				state.errors.append(path + ":nonfinite")
			return value
		TYPE_RECT2I:
			return value
		TYPE_TRANSFORM2D:
			if not value.x.is_finite() or not value.y.is_finite() or not value.origin.is_finite():
				state.errors.append(path + ":nonfinite")
			return value
		TYPE_COLOR:
			if not is_finite(value.r) or not is_finite(value.g) or not is_finite(value.b) or not is_finite(value.a):
				state.errors.append(path + ":nonfinite")
			return value
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return value.duplicate()
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			for index: int in range(value.size()):
				_copy(value[index], state, path + "[" + str(index) + "]", depth + 1)
			return value.duplicate()
	state.errors.append(path + ":unsupported_type_" + str(typeof(value)))
	return null
