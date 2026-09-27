extends RefCounted

## Worker-side file transaction, with main-thread domain approval between
## stages. No autoload, Node, SceneTree, signal, physics or gameplay RNG access.
## The coordinator must serialize all stages and drain at lifecycle boundaries.
var identity: Dictionary = {}
var response: Dictionary = {"finished": false}
var preparation: Dictionary = {"finished": false}
var path := "" # Private TMP, exposed for diagnostics and fault tests only.
var _target := ""
var _temporary := ""
var _private_prefix := ""
var _snapshot: Dictionary = {}
var _preencoded := false
var _bytes := PackedByteArray()
var _parsed: Dictionary = {}
var _previous: Dictionary = {}
var _backup: Dictionary = {}
var _approval: Dictionary = {}
var _create_only := false
var _mutex := Mutex.new()
var _stage_finished := false
var _stage_result: Dictionary = {}
var _cancel_requested := false
var _promotion_started := false
var _task_id := -1
var _owns_temporary := false
var _worker_thread_ids: Array[int] = []
var _stage_usec: Dictionary = {}


func configure(absolute_target: String, request_identity: Dictionary, payload: Dictionary, create_only := false) -> void:
	_target = absolute_target
	_private_prefix = absolute_target + ".request-%d-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec(), get_instance_id()]
	_temporary = _private_prefix + ".tmp"
	path = _temporary
	identity = request_identity.duplicate(true)
	_snapshot = payload.duplicate(true)
	_create_only = create_only


func run_stage(stage: String, approval := {}) -> void:
	assert(_task_id < 0, "one task per request stage")
	_stage_finished = false
	_stage_result = {}
	_approval = approval.duplicate(true)
	_task_id = WorkerThreadPool.add_task(_perform.bind(stage), false, "Ordered JSON persistence: " + stage)


func configure_preencoded(absolute_temporary: String, expected_bytes: PackedByteArray) -> void:
	assert(_task_id < 0)
	_preencoded = true
	_owns_temporary = true
	_temporary = absolute_temporary
	path = _temporary
	_bytes = expected_bytes
	_snapshot = {}


func configure_temporary(absolute_temporary: String) -> void:
	assert(_task_id < 0 and not _preencoded)
	_temporary = absolute_temporary
	path = _temporary


func stage_result(wait := false) -> Dictionary:
	if wait and _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
	_mutex.lock()
	var finished := _stage_finished
	var result := _stage_result if finished else {}
	_mutex.unlock()
	if finished and _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
	return {"finished": finished, "result": result}


func request_cancel() -> bool:
	_mutex.lock()
	if _promotion_started:
		_mutex.unlock()
		return false # Already committing: caller must await and consume receipt.
	_cancel_requested = true
	_mutex.unlock()
	return true


func _cancelled() -> bool:
	_mutex.lock()
	var value := _cancel_requested
	_mutex.unlock()
	return value


func _perform(stage: String) -> void:
	var stage_started_usec := Time.get_ticks_usec()
	var thread_id := OS.get_thread_caller_id()
	assert(thread_id != OS.get_main_thread_id(), "file stages belong to workers")
	_worker_thread_ids.append(thread_id)
	var result: Dictionary
	if stage == "DISCARD":
		result = {"success": false, "reason": "cancelled", "discarded": _remove_temporary()}
	elif _cancelled():
		result = {"success": false, "reason": "cancelled", "discarded": _remove_temporary()}
	elif stage == "PREPARE":
		result = _prepare()
	elif stage == "READ_PREVIOUS":
		_previous = _read_document(_target)
		_backup = _read_document(_target + ".bak")
		result = {"success": bool(_previous.readable) and bool(_backup.readable), "reason": "", "previous": _previous, "backup": _backup}
		if not bool(result.success):
			result.reason = "previous_file_read_failed"
	elif stage == "PROMOTE":
		_mutex.lock()
		var allowed := not _cancel_requested
		if allowed:
			_promotion_started = true
		_mutex.unlock()
		result = _promote() if allowed else {"success": false, "reason": "cancelled"}
	else:
		result = {"success": false, "reason": "unsupported_persistence_stage"}
	_stage_usec[stage] = Time.get_ticks_usec() - stage_started_usec
	result["worker_stage_usec"] = _stage_usec.duplicate()
	result["worker_thread_ids"] = _worker_thread_ids.duplicate()
	_mutex.lock()
	_stage_result = result
	_stage_finished = true
	_mutex.unlock()


func _prepare() -> Dictionary:
	if _preencoded:
		if not _matches_bytes(_temporary, _bytes):
			return {"success": false, "reason": "prepared_bytes_changed"}
		var existing: Variant = _parse_document(_bytes.get_string_from_utf8())
		if not existing is Dictionary:
			return {"success": false, "reason": "prepared_document_invalid"}
		_parsed = existing
		return {"success": true, "reason": "", "document": _parsed, "bytes": _bytes}
	var serialized := JSON.stringify(_snapshot)
	_snapshot = {}
	var candidate: Variant = _parse_document(serialized)
	if not candidate is Dictionary:
		return {"success": false, "reason": "serialized_document_invalid"}
	_parsed = candidate
	_bytes = serialized.to_utf8_buffer()
	if DirAccess.make_dir_recursive_absolute(_target.get_base_dir()) != OK:
		return {"success": false, "reason": "target_directory_failed"}
	if FileAccess.file_exists(_temporary):
		return {"success": false, "reason": "temporary_already_exists"}
	var file := FileAccess.open(_temporary, FileAccess.WRITE)
	if file == null:
		return {"success": false, "reason": "temporary_open_failed"}
	_owns_temporary = true
	file.store_buffer(_bytes)
	file.flush()
	file.close()
	if not _matches_bytes(_temporary, _bytes):
		_remove_temporary()
		return {"success": false, "reason": "temporary_readback_failed"}
	return {"success": true, "reason": "", "document": _parsed, "bytes": _bytes}


func _promote() -> Dictionary:
	if not bool(_approval.get("candidate_valid", false)):
		_remove_temporary()
		return {"success": false, "reason": "candidate_not_approved"}
	if not _matches_bytes(_temporary, _bytes):
		_remove_temporary()
		return {"success": false, "reason": "temporary_changed_before_promotion"}
	if not _same_document_bytes(_target, _previous) or not _same_document_bytes(_target + ".bak", _backup):
		_remove_temporary()
		return {"success": false, "reason": "previous_file_changed_before_promotion"}
	if _create_only and bool(_previous.exists):
		_remove_temporary()
		return {"success": false, "reason": "journal_sequence_already_exists"}
	if bool(_approval.get("previous_terminal", false)):
		_remove_temporary()
		return {"success": false, "reason": "previous_document_terminal"}
	var backup_path := _target + ".bak"
	var backup_hold := _private_prefix + ".previous-backup"
	var quarantine := _private_prefix + ".rejected-primary"
	if FileAccess.file_exists(backup_hold) or FileAccess.file_exists(quarantine) or FileAccess.file_exists(_private_prefix + ".rejected-output"):
		_remove_temporary()
		return {"success": false, "reason": "private_transaction_path_already_exists"}
	var moved_valid_main := false
	var held_backup := false
	var quarantined := false
	if bool(_previous.exists):
		if bool(_approval.get("previous_valid", false)):
			if bool(_backup.exists):
				if DirAccess.rename_absolute(backup_path, backup_hold) != OK:
					_remove_temporary()
					return {"success": false, "reason": "backup_hold_failed"}
				held_backup = true
			if DirAccess.rename_absolute(_target, backup_path) != OK:
				if held_backup:
					DirAccess.rename_absolute(backup_hold, backup_path)
				_remove_temporary()
				return {"success": false, "reason": "primary_rotation_failed"}
			moved_valid_main = true
		else:
			if DirAccess.rename_absolute(_target, quarantine) != OK:
				_remove_temporary()
				return {"success": false, "reason": "primary_quarantine_failed"}
			quarantined = true
	var promoted := DirAccess.rename_absolute(_temporary, _target) == OK
	var verified := promoted and _matches_bytes(_target, _bytes)
	if not verified:
		var restored := true
		if promoted:
			# Preserve the actual rejected output instead of leaving an unexpected
			# syntactically valid primary to become authority after restart.
			restored = DirAccess.rename_absolute(_target, _private_prefix + ".rejected-output") == OK
		if restored and moved_valid_main:
			restored = DirAccess.rename_absolute(backup_path, _target) == OK
		elif restored and quarantined:
			restored = DirAccess.rename_absolute(quarantine, _target) == OK
		if restored and held_backup:
			restored = DirAccess.rename_absolute(backup_hold, backup_path) == OK
		_remove_temporary()
		return {"success": false, "reason": "promotion_failed" if not promoted else "promoted_readback_failed", "rollback_complete": restored}
	var cleanup_warning := ""
	if held_backup and DirAccess.remove_absolute(backup_hold) != OK:
		cleanup_warning = "previous_backup_hold_retained"
	var actual_backup := _previous if moved_valid_main else _backup
	return {
		"success": true,
		"reason": "",
		"identity": identity,
		"target": _target,
		"bytes": _bytes,
		"document": _parsed,
		"backup_rotated": moved_valid_main,
		"backup_exists": bool(actual_backup.exists),
		"backup_document": actual_backup.get("document", {}),
		"backup_valid": bool(_approval.get("previous_valid", false)) if moved_valid_main else bool(_approval.get("backup_valid", false)),
		"previous_document": _previous.get("document", {}),
		"cleanup_warning": cleanup_warning,
	}


static func _read_document(target: String) -> Dictionary:
	if not FileAccess.file_exists(target):
		return {"exists": false, "readable": true, "syntax_valid": false, "bytes": PackedByteArray(), "document": {}}
	var file := FileAccess.open(target, FileAccess.READ)
	if file == null:
		return {"exists": true, "readable": false, "syntax_valid": false, "bytes": PackedByteArray(), "document": {}}
	var length := file.get_length()
	var bytes := file.get_buffer(length)
	file.close()
	var parsed: Variant = _parse_document(bytes.get_string_from_utf8())
	return {"exists": true, "readable": bytes.size() == length, "syntax_valid": parsed is Dictionary, "bytes": bytes, "document": parsed if parsed is Dictionary else {}}


static func _same_document_bytes(target: String, expected: Dictionary) -> bool:
	return _matches_bytes(target, expected.bytes) if bool(expected.exists) else not FileAccess.file_exists(target)


static func _matches_bytes(target: String, expected: PackedByteArray) -> bool:
	var file := FileAccess.open(target, FileAccess.READ)
	if file == null:
		return false
	var equal := file.get_length() == expected.size() and file.get_buffer(expected.size()) == expected
	file.close()
	return equal


func _remove_temporary() -> bool:
	return not _owns_temporary or not FileAccess.file_exists(_temporary) or DirAccess.remove_absolute(_temporary) == OK


func cancellation_requested() -> bool:
	return _cancelled()


static func _parse_document(value: String) -> Variant:
	# Expected corrupted-save tests must return data, not print engine errors.
	var parser := JSON.new()
	if parser.parse(value) != OK or not parser.data is Dictionary:
		return null
	return parser.data
