extends RefCounted

## Deletes only event files already covered by both durable checkpoints.
## The worker owns immutable paths and does not inspect gameplay state.
var _task_id := -1
var _mutex := Mutex.new()
var _finished := false
var _removed := 0
var _directory := ""
var _through_sequence := 0


func start(event_directory: String, through_sequence: int) -> void:
	_directory = event_directory
	_through_sequence = through_sequence
	_task_id = WorkerThreadPool.add_task(_run, false, "Clean checkpointed death events")


func _run() -> void:
	var removed := 0
	var directory := DirAccess.open(_directory)
	if directory != null:
		directory.list_dir_begin()
		var name := directory.get_next()
		while not name.is_empty():
			if not directory.current_is_dir() and name.ends_with(".json"):
				var sequence_text := name.get_basename()
				if sequence_text.is_valid_int():
					var sequence := int(sequence_text)
					if (
						sequence > 0
						and sequence <= _through_sequence
						and name == "%012d.json" % sequence
					):
						if DirAccess.remove_absolute(
							ProjectSettings.globalize_path(_directory.path_join(name))
						) == OK:
							removed += 1
			name = directory.get_next()
		directory.list_dir_end()
	_mutex.lock()
	_removed = removed
	_finished = true
	_mutex.unlock()


func result() -> Dictionary:
	_mutex.lock()
	var value := {"finished": _finished, "removed": _removed}
	_mutex.unlock()
	if bool(value.finished) and _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
	return value
