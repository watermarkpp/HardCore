extends RefCounted
var _root_ref: WeakRef
func _init(root: Node) -> void:
	_root_ref = weakref(root)
func lookup(key: Variant, fallback: Variant = null) -> Variant:
	return _root_ref.get_ref()._fire_wall_field_registry.get(key, fallback)
func store(key: Variant, actor: Object) -> void:
	_root_ref.get_ref()._fire_wall_field_registry[key] = actor
func keys() -> Array:
	return _root_ref.get_ref()._fire_wall_field_registry.keys()
func erase(value: Variant) -> Variant:
	return _root_ref.get_ref()._fire_wall_field_registry.erase(value)
func has(value: Variant) -> Variant:
	return _root_ref.get_ref()._fire_wall_field_registry.has(value)
func size() -> Variant:
	return _root_ref.get_ref()._fire_wall_field_registry.size()
func is_empty() -> Variant:
	return _root_ref.get_ref()._fire_wall_field_registry.is_empty()
func clear() -> void:
	_root_ref.get_ref()._fire_wall_field_registry.clear()
func _iter_init(iterator: Array) -> bool:
	iterator[0] = 0
	return not _root_ref.get_ref()._fire_wall_field_registry.keys().is_empty()
func _iter_next(iterator: Array) -> bool:
	iterator[0] += 1
	return iterator[0] < _root_ref.get_ref()._fire_wall_field_registry.keys().size()
func _iter_get(index: Variant) -> Variant:
	return _root_ref.get_ref()._fire_wall_field_registry.keys()[int(index)]
