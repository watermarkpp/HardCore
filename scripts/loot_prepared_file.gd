extends RefCounted

## Worker owns a detached save snapshot and one private temporary file. It
## serializes and reads back bytes, but cannot validate gameplay rules, promote
## a save or acknowledge loot. The main thread validates before promotion.
var path := ""
var bytes: PackedByteArray
var document: Dictionary = {}
var task_id := -1
var _mutex := Mutex.new()
var _finished := false
var _success := false
var _cancelled := false
var _snapshot: Dictionary = {}

func start_document(temporary_path: String, snapshot: Dictionary) -> void:
	path = temporary_path
	_snapshot = snapshot.duplicate(true)
	task_id = WorkerThreadPool.add_task(_write, false, "Prepare durable loot save")

func _write() -> void:
	var serialized := JSON.stringify(_snapshot)
	_snapshot = {}
	var parsed: Variant = JSON.parse_string(serialized)
	var valid := parsed is Dictionary
	var encoded := serialized.to_utf8_buffer() if valid else PackedByteArray()
	var file := FileAccess.open(path, FileAccess.WRITE) if valid else null
	valid = valid and file != null
	if valid:
		file.store_buffer(encoded)
		file.flush()
		file.close()
		file = FileAccess.open(path, FileAccess.READ)
		valid = file != null
		if valid:
			valid = file.get_length() == encoded.size() and file.get_buffer(encoded.size()) == encoded
			file.close()
	_mutex.lock()
	if valid:
		bytes = encoded
		document = parsed
	_success = valid
	_finished = true
	if _cancelled: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_mutex.unlock()

func result(wait := false) -> Dictionary:
	if wait and task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(task_id)
		task_id = -1
	_mutex.lock()
	var value := {
		"finished": _finished,
		"success": _success and not _cancelled,
		"bytes": bytes if _finished and _success else PackedByteArray(),
		"document": document if _finished and _success else {},
	}
	_mutex.unlock()
	if bool(value.finished) and task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(task_id)
		task_id = -1
	return value

func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	if _finished: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_mutex.unlock()
