extends RefCounted

## Prepares private files only. The main thread validates the normalized documents,
## checks current state, and alone promotes files / acknowledges the transfer.
var task_id := -1
var paths: Dictionary = {}
var documents: Dictionary = {}
var bytes: Dictionary = {}
var temporary_paths: Dictionary = {}
var _mutex := Mutex.new()
var _finished := false
var _success := false
var _cancelled := false

func start(target_paths: Dictionary, snapshots: Dictionary, contract_id: String, profile_id: String, operation_kind := "warehouse_items") -> void:
	paths = target_paths.duplicate(true)
	documents = snapshots.duplicate(true)
	var serial := str(Time.get_ticks_usec())
	for key: String in ["profile", "shared", "journal"]:
		temporary_paths[key] = str(paths[key]) + ".prepare." + serial + ".tmp"
	task_id = WorkerThreadPool.add_task(_prepare.bind(contract_id, profile_id, operation_kind), false, "Prepare warehouse transaction")

func _prepare(contract_id: String, profile_id: String, operation_kind: String) -> void:
	var valid := true
	var digests: Dictionary = {}
	for key: String in ["before_profile", "after_profile", "before_shared", "after_shared"]:
		var serialized := JSON.stringify(documents[key])
		var parsed: Variant = JSON.parse_string(serialized)
		if not parsed is Dictionary:
			valid = false
			break
		documents[key] = parsed
		digests[key] = JSON.stringify(parsed).sha256_text()
		if key.begins_with("after_"): bytes[key.trim_prefix("after_")] = serialized.to_utf8_buffer()
	if valid:
		var journal := {
			"contract_id": contract_id, "state": "PREPARED", "operation_kind": operation_kind,
			"profile_id": profile_id, "profile_path": paths.profile,
		}
		for key: String in digests:
			journal[key] = documents[key]
			journal[key + "_hash"] = digests[key]
		documents["journal"] = journal
		bytes["journal"] = JSON.stringify(journal).to_utf8_buffer()
		for key: String in ["journal", "shared", "profile"]:
			var file := FileAccess.open(temporary_paths[key], FileAccess.WRITE)
			if file == null:
				valid = false
				break
			file.store_buffer(bytes[key])
			file.flush()
			file.close()
			file = FileAccess.open(temporary_paths[key], FileAccess.READ)
			valid = file != null
			if valid:
				valid = file.get_length() == bytes[key].size() and file.get_buffer(bytes[key].size()) == bytes[key]
				file.close()
			if not valid: break
	_mutex.lock()
	_success = valid
	_finished = true
	if _cancelled: _remove_temporaries()
	_mutex.unlock()

func result() -> Dictionary:
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
	if _finished: _remove_temporaries()
	_mutex.unlock()

func _remove_temporaries() -> void:
	for path: String in temporary_paths.values():
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
