extends RefCounted

const Graph := preload("res://scripts/features/contracts/plain_graph.gd")

# Only explicitly permitted numeric leaves may change. Delivery, identity,
# profession, relations and source reaction family have no override operation.
static func build(base: Dictionary, operations: Array, allowed_fields: Array) -> Dictionary:
	if base.is_empty():
		return {"success": false, "reason": "unknown_base_definition", "definition": {}}
	var candidate := base.duplicate(true)
	var grouped := {}
	for operation: Variant in operations:
		if not operation is Dictionary or operation.get("field") not in allowed_fields \
			or operation.get("op") not in ["add", "multiply"] \
			or not (operation.get("value") is int or operation.get("value") is float) \
			or not is_finite(float(operation.value)):
			return {"success": false, "reason": "invalid_skill_operation", "definition": {}}
		var field: String = operation.field
		var existing: Array = grouped.get(field, [])
		existing.append(operation)
		grouped[field] = existing
	for field: String in grouped:
		var found := _find_leaf(candidate, field)
		if not bool(found.success):
			return {"success": false, "reason": "missing_numeric_skill_leaf:" + field, "definition": {}}
		var base_value: Variant = found.value
		var number := float(base_value)
		for operation: Dictionary in grouped[field]:
			if operation.op == "add":
				number += float(operation.value)
		for operation: Dictionary in grouped[field]:
			if operation.op == "multiply":
				number *= float(operation.value)
		if not is_finite(number) or number < 0.0 or number > 2147483647.0:
			return {"success": false, "reason": "skill_numeric_range:" + field, "definition": {}}
		found.container[found.key] = roundi(number) if base_value is int else number
	var frozen := Graph.capture(candidate)
	if not bool(frozen.success):
		return {"success": false, "reason": "non_plain_skill_definition", "definition": {}}
	return {"success": true, "reason": "", "definition": frozen.value}

static func _find_leaf(root: Dictionary, path: String) -> Dictionary:
	var parts := path.split(".")
	if parts.is_empty():
		return {"success": false}
	var current: Variant = root
	for index: int in range(parts.size()):
		var key: Variant = parts[index]
		if current is Array:
			if not str(key).is_valid_int() or int(key) < 0 or int(key) >= current.size():
				return {"success": false}
			key = int(key)
		elif not current is Dictionary or not current.has(key):
			return {"success": false}
		var value: Variant = current[key]
		if index == parts.size() - 1:
			return {"success": value is int or value is float, "container": current, "key": key, "value": value}
		current = value
	return {"success": false}
