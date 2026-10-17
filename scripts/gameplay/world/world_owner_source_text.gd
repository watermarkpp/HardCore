extends RefCounted
## Exact Main-published source bytes, preserving original parser behavior.
var _owner := OS.get_thread_caller_id()
var _world: WeakRef
var _documents: Dictionary
class PublishedFile:
	extends RefCounted
	var bytes: PackedByteArray
	var closed := false
	func get_as_text() -> String:
		assert(not closed)
		return bytes.get_string_from_utf8()
	func close() -> void: closed = true
func _init(world: RefCounted, documents: Dictionary) -> void:
	assert(_owner != OS.get_main_thread_id())
	_world = weakref(world)
	_documents = documents
func owner_thread_id() -> int: return _owner
func open_published(path: String) -> RefCounted:
	if not _documents.has(path) or not _documents[path] is PackedByteArray:
		_world.get_ref().fault("original_enemy_policy_source_missing", {"path": path})
		return null
	var file := PublishedFile.new()
	file.bytes = _documents[path]
	return file
