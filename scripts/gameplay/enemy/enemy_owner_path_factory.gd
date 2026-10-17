extends RefCounted
const Search := preload("res://scripts/gameplay/enemy/enemy_owner_path_search.gd")
const Shared := preload("res://scripts/gameplay/enemy/enemy_owner_path_shared.gd")
const PolygonSearch := preload("res://scripts/gameplay/enemy/enemy_owner_polygon_path_search.gd")
var _owner := OS.get_thread_caller_id()
var _configured := false
var deps: Dictionary
var shared: RefCounted

func owner_thread_id() -> int:
	return _owner

func configure_owner(bindings: Dictionary) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner:
		push_error("path factory configured twice or from another owner")
		return false
	for key in ["Terrain", "HCM30ContextTokenScript", "Time"]:
		if not bindings.get(key) is RefCounted or not bindings[key].has_method("owner_thread_id") or bindings[key].owner_thread_id() != _owner:
			push_error("path factory dependency missing: " + key)
			return false
	deps = bindings.duplicate()
	# Keep a weak factory view in each search; the owner retains the factory.
	# Search and factory do not form a RefCounted ownership cycle.
	deps.factory = FactoryView.new(self)
	shared = Shared.new()
	_configured = true
	return true

class FactoryView:
	extends RefCounted
	var reference: WeakRef
	func _init(factory: RefCounted) -> void:
		reference = weakref(factory)
	func owner_thread_id() -> int:
		return reference.get_ref().owner_thread_id()
	func create_polygon_search() -> RefCounted:
		return reference.get_ref().create_polygon_search()

func create_search() -> RefCounted:
	assert(_configured and OS.get_thread_caller_id() == _owner)
	var result := Search.new()
	if not result.configure_owner(deps, shared):
		push_error("path search construction rejected owner bindings")
		return null
	return result

func create_polygon_search() -> RefCounted:
	assert(_configured and OS.get_thread_caller_id() == _owner)
	var result := PolygonSearch.new()
	if not result.configure_owner(deps):
		push_error("polygon search construction rejected owner bindings")
		return null
	return result

func reset_diagnostics() -> void:
	assert(_configured and OS.get_thread_caller_id() == _owner)
	shared.reset_diagnostics()

func diagnostics() -> Dictionary:
	assert(_configured and OS.get_thread_caller_id() == _owner)
	return shared.diagnostics()
