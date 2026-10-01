extends RefCounted

# The graph crossing a definition boundary contains only JSON values. This
# owns a separate immutable graph; Node, Callable and cyclic input fail closed.
static func capture(input: Variant, max_nodes := 1000000, max_depth := 64) -> Dictionary:
	var state := {"errors": [], "nodes": 0, "max_nodes": max_nodes, "max_depth": max_depth}
	var value: Variant = _copy(input, [], 0, state)
	return {"success": state.errors.is_empty(), "value": value, "errors": state.errors}

static func _copy(input: Variant, ancestors: Array, depth: int, state: Dictionary) -> Variant:
	state.nodes += 1
	if state.nodes > state.max_nodes or depth > state.max_depth:
		if state.errors.is_empty():
			state.errors.append("plain_graph_capacity")
		return null
	match typeof(input):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return input
		TYPE_FLOAT:
			if not is_finite(input):
				state.errors.append("non_finite_number")
				return null
			return input
		TYPE_ARRAY, TYPE_DICTIONARY:
			for ancestor: Variant in ancestors:
				if is_same(ancestor, input):
					state.errors.append("cyclic_plain_graph")
					return null
			ancestors.append(input)
			var result: Variant = [] if input is Array else {}
			if input is Array:
				for child: Variant in input:
					result.append(_copy(child, ancestors, depth + 1, state))
					if not state.errors.is_empty():
						break
			else:
				for key: Variant in input:
					if not key is String:
						state.errors.append("non_string_graph_key:" + type_string(typeof(key)) + ":" + str(key))
						break
					result[key] = _copy(input[key], ancestors, depth + 1, state)
					if not state.errors.is_empty():
						break
			ancestors.pop_back()
			result.make_read_only()
			return result
		_:
			state.errors.append("non_plain_value:" + type_string(typeof(input)))
			return null
