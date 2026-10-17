extends RefCounted
var _root_ref: WeakRef
func _init(root: Node) -> void:
	_root_ref = weakref(root)
func append(actor: Object) -> void:
	_root_ref.get_ref()._pending_main_pet_arrivals.append(actor)
func duplicate(deep := false) -> Array:
	return _root_ref.get_ref()._pending_main_pet_arrivals.duplicate(deep)
func erase(value: Variant) -> void:
	_root_ref.get_ref()._pending_main_pet_arrivals.erase(value)
func has(value: Variant) -> Variant:
	return _root_ref.get_ref()._pending_main_pet_arrivals.has(value)
func size() -> Variant:
	return _root_ref.get_ref()._pending_main_pet_arrivals.size()
func is_empty() -> Variant:
	return _root_ref.get_ref()._pending_main_pet_arrivals.is_empty()
func clear() -> void:
	_root_ref.get_ref()._pending_main_pet_arrivals.clear()
func _iter_init(iterator: Array) -> bool:
	iterator[0] = 0
	return not _root_ref.get_ref()._pending_main_pet_arrivals.is_empty()
func _iter_next(iterator: Array) -> bool:
	iterator[0] += 1
	return iterator[0] < _root_ref.get_ref()._pending_main_pet_arrivals.size()
func _iter_get(index: Variant) -> Variant:
	return _root_ref.get_ref()._pending_main_pet_arrivals[int(index)]
