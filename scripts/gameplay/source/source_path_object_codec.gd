extends RefCounted
## Value-only transfer of the two original polygon cache object classes.
## Objects are reconstructed on the receiving owner, never shared across threads.
## Joint roots, exact aliases, typed containers and original mutability survive.
const Index := preload("res://scripts/map_editor/polygon/poly_index.gd")
const Nav := preload("res://scripts/map_editor/polygon/poly_nav_graph.gd")
const CONTRACT := "hardcore.path.original_object_graph.v1"
const FIELDS := {
	"index":["design_size","parts","boxes","_padded_boxes","_first_buckets","buckets","ready"],
	"navigation":["radius_key","radius_gu","vertices","faces","centers","links","buckets","ready"]}

static func capture(roots: Dictionary) -> Dictionary:
	var native: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var state := {"native":native,"memo":{},"gray":{},"sources":[],"objects":[],"object_ids":{},"slots":[],"modes":[],"errors":[]}
	var copied: Variant = _copy(roots,["roots"],state,0)
	if not state.errors.is_empty(): return _fail(state.errors[0])
	var wire := {"contract_id":CONTRACT,"roots":copied,"objects":state.objects,"object_slots":state.slots,"container_modes":state.modes}
	var sealed: Dictionary = native.capture(wire,true,false)
	return {"ok":true,"value":sealed.value} if sealed.get("success") == true else _fail("nonplain_path_object_descriptor")

static func _copy(value: Variant,path: Array,state: Dictionary,depth: int) -> Variant:
	if depth > 64: state.errors.append("path_object_depth"); return null
	if value is Object:
		if not is_instance_valid(value) or (value.get_script() != Index and value.get_script() != Nav) or not value.get_meta_list().is_empty():
			state.errors.append("unsupported_path_object"); return null
		var id: int = value.get_instance_id()
		if not state.object_ids.has(id):
			var kind: String = "index" if value.get_script() == Index else "navigation"
			if not _exact_fields(value,kind): state.errors.append("path_object_field_schema_changed"); return null
			var ordinal: int = state.objects.size()
			state.object_ids[id] = ordinal
			state.objects.append({"kind":kind,"source_sha256":value.get_script().get_source_code().sha256_text(),"fields":{}})
			var fields: Dictionary = {}
			for key: String in FIELDS[kind]: fields[key] = value.get(key)
			state.objects[ordinal].fields = _copy(fields,["objects",ordinal,"fields"],state,depth+1)
		state.slots.append({"path":path,"object":state.object_ids[id]})
		return null
	if value is Dictionary or value is Array:
		if (value is Array and value.get_typed_builtin() == TYPE_OBJECT) or (value is Dictionary and (value.get_typed_key_builtin() == TYPE_OBJECT or value.get_typed_value_builtin() == TYPE_OBJECT)):
			state.errors.append("unsupported_path_object_container_type"); return null
		var key := str(typeof(value))+":"+str(state.native.container_identity_for_local_copy(value))
		if state.gray.has(key): state.errors.append("cyclic_path_object_graph"); return null
		if state.memo.has(key): return state.memo[key]
		# Descriptor field envelopes are temporary containers. Keep each source
		# alive for this capture so allocator address reuse cannot alias two
		# distinct Index/NavGraph envelopes in the identity memo (ABA).
		state.sources.append(value)
		var out: Variant = value.duplicate(false)
		out.clear(); state.memo[key] = out; state.gray[key] = true
		if value is Dictionary:
			for field: Variant in value:
				var next: Array = path.duplicate(); next.append(field)
				out[field] = _copy(value[field],next,state,depth+1)
		else:
			for index: int in range(value.size()):
				var next: Array = path.duplicate(); next.append(index)
				out.append(_copy(value[index],next,state,depth+1))
		state.gray.erase(key)
		state.modes.append({"path":path,"read_only":value.is_read_only()})
		return out
	return value

static func restore(publication: Dictionary) -> Dictionary:
	if publication.get("contract_id") != CONTRACT or not publication.get("roots") is Dictionary or not publication.get("objects") is Array or not publication.get("object_slots") is Array or not publication.get("container_modes") is Array: return _fail("invalid_path_object_publication")
	var native: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var copied: Dictionary = native.capture(publication,false,false)
	if copied.get("success") != true: return _fail("nonplain_path_object_publication")
	var wire: Dictionary = copied.value
	var objects: Array[RefCounted] = []
	# Construct only exact reviewed RefCounted types, with no tree/IO/callbacks.
	for raw: Variant in wire.objects:
		if not raw is Dictionary or raw.size() != 3 or not raw.get("kind") is String or not FIELDS.has(raw.kind) or not raw.get("fields") is Dictionary: return _fail("invalid_path_object_descriptor")
		var code: Script = Index if raw.kind == "index" else Nav
		if raw.get("source_sha256") != code.get_source_code().sha256_text(): return _fail("path_object_source_changed")
		var actual: Array = raw.fields.keys(); var expected: Array = FIELDS[raw.kind].duplicate()
		actual.sort(); expected.sort()
		if actual != expected: return _fail("path_object_fields_changed")
		var object: RefCounted = code.new()
		if not _exact_fields(object,raw.kind): return _fail("path_object_schema_changed")
		for key: String in FIELDS[raw.kind]:
			if typeof(object.get(key)) != typeof(raw.fields[key]): return _fail("path_object_field_type_changed")
		objects.append(object)
	var touched: Dictionary = {}
	for raw: Variant in wire.object_slots:
		if not raw is Dictionary or raw.size() != 2 or not raw.get("path") is Array or not raw.get("object") is int or raw.object < 0 or raw.object >= objects.size(): return _fail("invalid_path_object_slot")
		var parent: Variant = _parent(wire,raw.path)
		if parent == null or not _has(parent,raw.path[-1]) or parent[raw.path[-1]] != null: return _fail("path_object_slot_changed")
		parent[raw.path[-1]] = objects[raw.object]; touched[raw.object] = true
	if touched.size() != objects.size(): return _fail("unreferenced_path_object_descriptor")
	# Seal original containers only after the exact object slots are restored.
	var seen: Dictionary = {}
	for raw: Variant in wire.container_modes:
		if not raw is Dictionary or raw.size() != 2 or not raw.get("path") is Array or not raw.get("read_only") is bool: return _fail("invalid_path_container_mode")
		var parent: Variant = _parent(wire,raw.path)
		if parent == null or not _has(parent,raw.path[-1]): return _fail("path_container_missing")
		var value: Variant = parent[raw.path[-1]]
		if not (value is Array or value is Dictionary): return _fail("path_container_type_changed")
		var id: int = native.container_identity_for_local_copy(value)
		if seen.has(id): return _fail("duplicate_path_container_mode")
		seen[id] = true
		if raw.read_only: value.make_read_only()
	for index: int in range(objects.size()):
		for key: String in FIELDS[wire.objects[index].kind]: objects[index].set(key,wire.objects[index].fields[key])
	return {"ok":true,"value":wire.roots,"objects":objects}

static func _parent(wire: Dictionary,path: Array) -> Variant:
	if path.is_empty() or path[0] not in ["roots","objects"]: return null
	var current: Variant = wire
	for index: int in range(path.size()-1):
		if not _has(current,path[index]): return null
		current = current[path[index]]
	return current if current is Dictionary or current is Array else null
static func _has(container: Variant,key: Variant) -> bool:
	return container.has(key) if container is Dictionary else (container is Array and key is int and key >= 0 and key < container.size())
static func _exact_fields(object: RefCounted,kind: String) -> bool:
	var names: Array = []
	for property: Dictionary in object.get_script().get_script_property_list():
		if int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE: names.append(str(property.name))
	var expected: Array = FIELDS[kind].duplicate(); expected.sort(); names.sort()
	return names == expected
static func _fail(reason: String) -> Dictionary: return {"ok":false,"errors":[reason]}
