extends RefCounted

## Ordered persistent actor references. Enumeration borrows models only for
## the original immediate call; stored references are ActorLink leases.
var _actors: RefCounted
var _links: Array[RefCounted] = []
var _iteration := 0

func _init(actors: RefCounted) -> void:
	_actors = actors

func append(actor: Object) -> void:
	var link: RefCounted = _actors.capture(actor)
	assert(link != null, "persistent actor append has no canonical record")
	if link != null: _links.append(link)

func erase(actor: Object) -> void:
	for index: int in range(_links.size()):
		if _links[index].borrow_model() == actor:
			_links[index].dispose()
			_links.remove_at(index)
			return

func has(actor: Object) -> bool:
	for link: RefCounted in _links:
		if link.borrow_model() == actor: return true
	return false

func duplicate(_deep := false) -> Array[Object]:
	var values: Array[Object] = []
	for link: RefCounted in _links: values.append(link.borrow_model())
	return values

func size() -> int:
	return _links.size()

func is_empty() -> bool:
	return _links.is_empty()

func clear() -> void:
	for link: RefCounted in _links: link.dispose()
	_links.clear()

func _iter_init(iterator: Array) -> bool:
	iterator[0] = 0
	return not _links.is_empty()

func _iter_next(iterator: Array) -> bool:
	iterator[0] += 1
	return iterator[0] < _links.size()

func _iter_get(index: Variant) -> Object:
	return _links[int(index)].borrow_model()
