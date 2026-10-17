extends RefCounted

const Graph := preload("res://scripts/gameplay/content/content_value_graph.gd")
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
var _catalog_lease: Dictionary
var _values: Dictionary
var _owner := OS.get_thread_caller_id()

func _init(published_fields: Dictionary, catalog_lease: Dictionary) -> void:
	_catalog_lease = catalog_lease
	var copied := Graph.capture(published_fields, false)
	assert(copied.success, "content fields must be an independent value graph")
	_values = copied.value if copied.success else {}

func read_field(name: String) -> Variant:
	if not _owned(): return null
	return _values[name]

func write_field(name: String, value: Variant) -> void:
	if not _owned(): return
	_values[name] = value

func _owned() -> bool:
	return _owner == OS.get_thread_caller_id() and Gate.owns_reader(_catalog_lease)
