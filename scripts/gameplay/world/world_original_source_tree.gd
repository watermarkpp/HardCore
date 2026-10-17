extends RefCounted

## Only the original parent/children and callback membership ledger. Scope and
## Handle remain the single source of process/life/queued qualification.
var _owner := OS.get_thread_caller_id()
var _world_ref: WeakRef
var _root_key := ""
var _rows: Dictionary = {}
var _ids: Dictionary = {}
var _actor_templates: Dictionary
var _service_templates: Dictionary
var _next_stable_order: int

func owner_thread_id() -> int: return _owner
func configure_owner(world: RefCounted, publication: Dictionary) -> bool:
	if _world_ref != null or _owner == OS.get_main_thread_id() or world.owner_thread_id() != _owner: return false
	if publication.get("contract_id") != "world.source_tree.original.v1": return false
	for field: String in ["rows", "actor_birth_templates", "service_callback_templates", "next_stable_combat_order", "root_source_key"]:
		if not publication.has(field): return false
	if not publication.rows is Array or not publication.actor_birth_templates is Dictionary or not publication.service_callback_templates is Dictionary: return false
	if not publication.next_stable_combat_order is int or publication.next_stable_combat_order < 0 or not publication.root_source_key is String: return false
	_root_key = publication.root_source_key
	for source: Variant in publication.rows:
		if not source is Dictionary or not source.get("source_key") is String or not source.get("parent_source_key") is String or not source.get("kind") is String or not source.get("callbacks") is Dictionary: return false
		var key: String = source.source_key
		if key.is_empty() or _rows.has(key) or (key != _root_key and not _rows.has(source.parent_source_key)): return false
		if key == _root_key and not source.parent_source_key.is_empty(): return false
		_rows[key] = {"kind":source.kind,"parent":source.parent_source_key,"children":[],"callbacks":source.callbacks,"runtime_id":0}
		if key != _root_key: _rows[source.parent_source_key].children.append(key)
	if not _rows.has(_root_key): return false
	_actor_templates = publication.actor_birth_templates
	_service_templates = publication.service_callback_templates
	_next_stable_order = publication.next_stable_combat_order
	_world_ref = weakref(world)
	return bind_existing(_root_key, world.parent_scope_id())

func bind_existing(key: String, id: int) -> bool:
	if OS.get_thread_caller_id() != _owner or id == 0 or not _rows.has(key) or _ids.has(id) or _rows[key].runtime_id != 0: return false
	_rows[key].runtime_id = id
	_ids[id] = key
	return true

func source_key_for_id(id: int) -> String: return _ids.get(id, "")
func reserve_actor_birth(kind: StringName, parent_id: int, template_key: StringName = &"") -> Dictionary:
	var key := String(kind if template_key == &"" else template_key)
	if key != String(kind) and not (kind == &"field" and key in ["fire_wall","enemy_target_magic"]) and not (kind==&"projectile" and key=="enemy_projectile"): return {}
	if OS.get_thread_caller_id() != _owner or not _ids.has(parent_id) or not _actor_templates.has(key): return {}
	var value: Dictionary = _actor_templates[key].duplicate(true)
	if value.get("contract_id") != "world.actor.original_birth.v1" or not value.get("scope") is Dictionary or not value.get("metadata") is Dictionary or not value.get("source_callbacks") is Dictionary: return {}
	if value.scope.get("inside_world") != false or value.scope.get("queued_for_retirement") != false: return {}
	value.scope.parent_scope_id = parent_id
	value.stable_combat_order = _next_stable_order
	_next_stable_order += 1
	# Birth does not enter the tree. The actual add_child boundary attaches it.
	value.source_parent_key = _ids[parent_id]
	value.source_kind = String(kind)
	var prospective: Array[String] = []
	_append_preorder(_root_key,prospective)
	var parent_key: String = _ids[parent_id]
	var siblings_after_parent: Array[String] = []
	_append_preorder(parent_key,siblings_after_parent)
	var ordinal: int = prospective.find(parent_key) + siblings_after_parent.size()
	value.process_source_order = ordinal * 2 + 1
	value.physics_source_order = ordinal * 2 + 1
	return value

func enter_actor(id: int, source: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or id <= 0 or not source.get("source_parent_key") is String or not source.get("source_kind") is String or not source.get("source_callbacks") is Dictionary: return false
	if _ids.has(id): return true
	return _append_child(id, source.source_parent_key, source.source_kind, source.source_callbacks)

func enter_service(id: int, kind: StringName, parent_id: int) -> bool:
	if _ids.has(id): return true
	if OS.get_thread_caller_id() != _owner or id <= 0 or not _ids.has(parent_id) or not _service_templates.has(String(kind)): return false
	var template: Variant = _service_templates[String(kind)]
	if not template is Dictionary or not template.get("callbacks") is Dictionary: return false
	return _append_child(id, _ids[parent_id], String(kind), template.callbacks)

func _append_child(id: int, parent: String, kind: String, callbacks: Dictionary) -> bool:
	if not _rows.has(parent): return false
	var key := "runtime:" + str(id)
	if _rows.has(key): return false
	_rows[key] = {"kind":kind,"parent":parent,"children":[],"callbacks":callbacks,"runtime_id":id}
	_rows[parent].children.append(key)
	_ids[id] = key
	return true

func callback_order(id: int, method: StringName) -> Dictionary:
	if OS.get_thread_caller_id() != _owner or not _ids.has(id): return {"ok":false,"reason":"source_callback_owner_not_entered","id":id}
	var key: String = _ids[id]
	var original: StringName = method
	if method == &"step_physics": original = &"_physics_process"
	elif method == &"step_process" or method == &"original_process": original = &"_process"
	elif method == &"original_physics_pump": original = &"_physics_process"
	var callbacks: Dictionary = _rows[key].callbacks
	if not callbacks.has(String(original)): return {"ok":false,"reason":"source_callback_not_captured","id":id,"method":method}
	var record: Variant = callbacks[String(original)]
	if not record is Dictionary or record.get("domain") not in ["H","P"] or not record.get("internal") is bool or not record.get("entry") is String or record.entry.is_empty(): return {"ok":false,"reason":"source_callback_schema"}
	var preorder: Array[String] = []
	_append_preorder(_root_key, preorder)
	var ordinal: int = preorder.find(key)
	if ordinal < 0: return {"ok":false,"reason":"source_callback_detached"}
	# Node::_process_group notifies INTERNAL then ordinary for each node.
	return {"ok":true,"order":ordinal * 2 + (0 if record.internal else 1),"entry":record.entry,"domain":record.domain,"source_key":key}

func _append_preorder(key: String, result: Array[String]) -> void:
	result.append(key)
	for child: String in _rows[key].children: _append_preorder(child, result)

func children_in_original_reverse_order(id: int) -> Array[int]:
	var result: Array[int] = []
	if not _ids.has(id): return result
	var children: Array = _rows[_ids[id]].children
	for index: int in range(children.size()-1,-1,-1):
		var child_id: int = _rows[children[index]].runtime_id
		if child_id != 0: result.append(child_id)
	return result

func detach_at_original_final_free(id: int) -> bool:
	if OS.get_thread_caller_id() != _owner or not _ids.has(id): return false
	var key: String = _ids[id]
	if not _rows[key].children.is_empty(): return false
	var parent: String = _rows[key].parent
	if _rows.has(parent): _rows[parent].children.erase(key)
	_rows.erase(key)
	_ids.erase(id)
	return true

func is_original_ancestor(ancestor_id: int, child_id: int) -> bool:
	if OS.get_thread_caller_id() != _owner or ancestor_id == child_id or not _ids.has(ancestor_id) or not _ids.has(child_id): return false
	var ancestor: String = _ids[ancestor_id]
	var key: String = _rows[_ids[child_id]].parent
	while not key.is_empty():
		if key == ancestor: return true
		if not _rows.has(key): return false
		key = _rows[key].parent
	return false
