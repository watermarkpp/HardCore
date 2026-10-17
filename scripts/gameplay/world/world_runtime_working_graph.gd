extends RefCounted

## Restore only source runtime working containers at their original constructor
## boundary. One memo spans the selected roots, preserving original DAG aliases.
## Immutable RuntimeMap/Content/catalog identities are never passed to this API.
static func restore_runtime_roots(roots: Dictionary) -> Dictionary:
	var memo := {"sources": [], "copies": [], "stack": [], "errors": []}
	var result: Variant = _restore(roots, memo, "$", 0)
	return {"ok": memo.errors.is_empty(), "value": result, "errors": memo.errors}

static func _restore(value: Variant, memo: Dictionary, path: String, depth: int) -> Variant:
	if depth > 128:
		memo.errors.append(path + ":depth")
		return null
	if value is Object or value is Callable or value is Signal or value is RID:
		memo.errors.append(path + ":live_runtime_seed")
		return null
	if value is Dictionary or value is Array:
		for ancestor: Variant in memo.stack:
			if is_same(ancestor, value):
				memo.errors.append(path + ":cycle")
				return null
		for index: int in range(memo.sources.size()):
			if is_same(memo.sources[index], value): return memo.copies[index]
		var result: Variant = value.duplicate(false)
		result.clear()
		memo.sources.append(value)
		memo.copies.append(result)
		memo.stack.append(value)
		if value is Dictionary:
			for key: Variant in value:
				if key is Dictionary or key is Array or key is Object:
					memo.errors.append(path + ":nonvalue_key")
					continue
				result[key] = _restore(value[key], memo, path + "." + str(key), depth + 1)
		else:
			for index: int in range(value.size()):
				result.append(_restore(value[index], memo, path + "[" + str(index) + "]", depth + 1))
		memo.stack.pop_back()
		return result
	# PackedArray duplicate is COW mathematical storage; scalars retain exact
	# IEEE/source values (including intentional Vector2.INF cache sentinels).
	if typeof(value) >= TYPE_PACKED_BYTE_ARRAY and typeof(value) <= TYPE_PACKED_VECTOR4_ARRAY:
		return value.duplicate()
	return value
