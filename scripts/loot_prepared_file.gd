extends RefCounted

## Worker owns only opaque, already validated bytes and one private temporary
## file. It cannot read gameplay objects, promote a save or acknowledge loot.
var path := ""
var bytes: PackedByteArray
var task_id := -1
var _mutex := Mutex.new()
var _finished := false
var _success := false
var _cancelled := false

func start(temporary_path: String, validated_bytes: PackedByteArray) -> void:
	path = temporary_path
	bytes = validated_bytes
	task_id = WorkerThreadPool.add_task(_write, false, "Prepare durable loot save")

func _write() -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	var valid := file != null
	if valid:
		file.store_buffer(bytes)
		file.flush()
		file.close()
		file = FileAccess.open(path, FileAccess.READ)
		valid = file != null
		if valid:
			valid = file.get_length() == bytes.size() and file.get_buffer(bytes.size()) == bytes
			file.close()
	_mutex.lock()
	_success = valid
	_finished = true
	if _cancelled: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_mutex.unlock()

func result(wait := false) -> Dictionary:
	if wait and task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(task_id)
		task_id = -1
	_mutex.lock()
	var value := {"finished": _finished, "success": _success and not _cancelled}
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
