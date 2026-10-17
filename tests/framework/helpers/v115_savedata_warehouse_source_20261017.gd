extends RefCounted
## Shared assertions for the real ProfileModel. No replacement persistence owner.
static func snapshot(owner: Object) -> Dictionary:
	var out: Dictionary = {}
	for key: String in ["active_profile_id","profession_id","level","experience","gold","learned_skills","inventory","equipment","warehouse_inventory"]:
		var value: Variant = owner.get(key)
		out[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	out.skill_progression = owner.skill_progression_snapshot()
	return out
static func records(owner: Object) -> Array:
	var out: Array = []
	for bag: Array in [owner.inventory,owner.warehouse_inventory]:
		for record: Variant in bag:
			if record is Dictionary and not record.is_empty(): out.append(record.duplicate(true))
	for record: Variant in owner.equipment.values():
		if record is Dictionary and not record.is_empty(): out.append(record.duplicate(true))
	return out
static func ownership(owner: Object) -> Dictionary:
	var instances: Dictionary = {}
	var quantities := 0
	var attribute_quantities: Dictionary = {}
	var duplicate := false
	for record: Dictionary in records(owner):
		quantities += int(record.get("count",1))
		var attributes: Dictionary = record.duplicate(true)
		attributes.erase("count")
		var signature: String = JSON.stringify(_canonical(attributes))
		attribute_quantities[signature] = int(attribute_quantities.get(signature,0))+int(record.get("count",1))
		var id: String = str(record.get("instance_id",""))
		if not id.is_empty():
			if instances.has(id): duplicate = true
			instances[id] = record.duplicate(true)
	return {"instances":instances,"quantities":quantities,"has_duplicate_instances":duplicate,"records":records(owner).size(),"attribute_quantities":attribute_quantities}
static func find_instance(bag: Array,id: String) -> int:
	for index: int in bag.size():
		if bag[index] is Dictionary and str(bag[index].get("instance_id","")) == id: return index
	return -1
static func progression(owner: Object) -> Dictionary:
	var value: Dictionary = snapshot(owner)
	for key: String in ["inventory","equipment","warehouse_inventory"]: value.erase(key)
	return value

static func equal(a: Variant,b: Variant) -> bool:
	# Exact numeric equivalence only: JSON may read integral numbers as float,
	# while the unchanged formal receive path emits int. No tolerance/truncation.
	if (a is int or a is float) and (b is int or b is float):
		if typeof(a) == typeof(b): return a == b
		var integer: int = a if a is int else b
		var real: float = b if b is float else a
		return is_finite(real) and real == float(integer) and int(real) == integer
	if typeof(a) != typeof(b): return false
	if a is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not equal(a[key],b[key]): return false
		return true
	if a is Array:
		if a.size() != b.size(): return false
		for index: int in a.size():
			if not equal(a[index],b[index]): return false
		return true
	return a == b
static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary = {}
		var keys: Array = value.keys(); keys.sort()
		for key: Variant in keys: out[key] = _canonical(value[key])
		return out
	if value is Array:
		var out: Array = []
		for entry: Variant in value: out.append(_canonical(entry))
		return out
	if value is float and is_finite(value) and float(int(value)) == value: return int(value)
	return value
