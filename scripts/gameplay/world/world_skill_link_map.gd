extends RefCounted

var _actors: RefCounted
var _links: Dictionary = {}

func _init(actors: RefCounted) -> void:
	_actors = actors

func lookup(key: Variant, fallback: Variant = null) -> Variant:
	return _links[key].borrow_model() if _links.has(key) else fallback

func store(key: Variant, actor: Object) -> void:
	var link: RefCounted = _actors.capture(actor)
	assert(link != null, "persistent effect has no canonical record")
	if link == null: return
	erase(key)
	_links[key] = link

func erase(key: Variant) -> void:
	if not _links.has(key): return
	_links[key].dispose()
	_links.erase(key)

func keys() -> Array:
	return _links.keys()

func has(key: Variant) -> bool:
	return _links.has(key)

func size() -> int:
	return _links.size()

func clear() -> void:
	for key: Variant in _links.keys(): erase(key)

func _iter_init(iterator: Array) -> bool:
	iterator[0] = 0
	return not _links.is_empty()

func _iter_next(iterator: Array) -> bool:
	iterator[0] += 1
	return iterator[0] < _links.size()

func _iter_get(index: Variant) -> Variant:
	return _links.keys()[int(index)]
