extends RefCounted

## Ordered coordinator: all methods execute on main; workers own detached jobs.
## Domain callbacks stay here and are never given to a worker object.
const Job := preload("res://scripts/json_persistence_job.gd")
const MAX_PENDING_REQUESTS := 64
var _queue: Array[Dictionary] = []


func submit(target: String, identity: Dictionary, snapshot: Dictionary, validator: Callable, guard := Callable(), create_only := false, known_previous_bytes: Variant = null, on_complete := Callable(), prepare_only := false, prepared_bytes: Variant = null, temporary := "", require_known_previous := false) -> RefCounted:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id(), "domain coordinator is main-thread owned")
	if _queue.size() >= MAX_PENDING_REQUESTS or not _plain_json_value(snapshot) or not _plain_json_value(identity):
		return null
	var job := Job.new()
	job.configure(ProjectSettings.globalize_path(target), identity, snapshot, create_only)
	if prepared_bytes is PackedByteArray:
		job.configure_preencoded(ProjectSettings.globalize_path(temporary), prepared_bytes)
	elif not temporary.is_empty():
		job.configure_temporary(ProjectSettings.globalize_path(temporary))
	_queue.append({
		"job": job,
		"identity": identity.duplicate(true),
		"validator": validator,
		"guard": guard,
		"on_complete": on_complete,
		"known_previous_bytes": known_previous_bytes,
		"require_known_previous": require_known_previous,
		"allow_promotion": not prepare_only,
		"phase": "NEW",
		"candidate": {},
		"failure": {},
	})
	pump()
	return job


func pending_count() -> int:
	return _queue.size()


func pump(wait := false) -> bool:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id(), "domain approval and completion stay on main")
	if _queue.is_empty():
		return false
	var entry: Dictionary = _queue[0]
	var job: RefCounted = entry.job
	var phase := str(entry.phase)
	if phase == "PREPARED":
		if job.cancellation_requested():
			_fail(entry, {"success": false, "reason": "cancelled"})
			return true
		if not bool(entry.allow_promotion):
			return false
		if not _guard_allows(entry):
			_fail(entry, {"success": false, "reason": "request_context_changed"})
			return true
		job.run_stage("READ_PREVIOUS")
		entry.phase = "READING"
		return true
	if phase == "NEW":
		job.run_stage("PREPARE")
		entry.phase = "PREPARING"
		return true
	var completed: Dictionary = job.stage_result(wait)
	if not bool(completed.finished):
		return false
	var result: Dictionary = completed.result
	if phase == "DISPOSING":
		var failure: Dictionary = entry.failure
		failure["discarded"] = bool(result.get("discarded", false))
		_complete(entry, failure)
		return true
	if not bool(result.get("success", false)):
		_fail(entry, result)
		return true
	if phase == "PREPARING":
		if job.cancellation_requested():
			_fail(entry, {"success": false, "reason": "cancelled"})
			return true
		var validation := _validate(entry.validator, result.document)
		if not bool(validation.valid):
			_fail(entry, {"success": false, "reason": "candidate_business_invalid", "validation": validation})
			return true
		entry.candidate = result
		job.preparation = result.duplicate(true)
		job.preparation["finished"] = true
		entry.phase = "PREPARED"
		return true
	if phase == "READING":
		if not _guard_allows(entry):
			_fail(entry, {"success": false, "reason": "request_context_changed"})
			return true
		var previous: Dictionary = result.previous
		var backup: Dictionary = result.backup
		if bool(entry.require_known_previous) and (not entry.known_previous_bytes is PackedByteArray or not bool(previous.exists) or previous.bytes != entry.known_previous_bytes):
			_fail(entry, {"success": false, "reason": "validated_previous_bytes_changed"})
			return true
		var previous_validation := {"valid": false, "terminal": false}
		if bool(previous.syntax_valid):
			if entry.known_previous_bytes is PackedByteArray and previous.bytes == entry.known_previous_bytes:
				previous_validation = {"valid": true, "terminal": false}
			else:
				previous_validation = _validate(entry.validator, previous.document)
		var backup_validation := {"valid": false, "terminal": false}
		if not bool(previous_validation.valid) and bool(backup.syntax_valid):
			backup_validation = _validate(entry.validator, backup.document)
		job.run_stage("PROMOTE", {
			"candidate_valid": true,
			"previous_valid": bool(previous_validation.valid),
			"previous_terminal": bool(previous_validation.get("terminal", false)),
			"backup_valid": bool(backup_validation.valid),
		})
		entry.phase = "PROMOTING"
		return true
	if phase == "PROMOTING":
		_complete(entry, result)
		return true
	_fail(entry, {"success": false, "reason": "unsupported_coordinator_phase"})
	return true


func finish(job: RefCounted, wait := false) -> Dictionary:
	authorize(job)
	if wait:
		while not bool(job.response.get("finished", false)):
			assert(not _queue.is_empty(), "pending job belongs to this coordinator")
			if str(_queue[0].phase) == "PREPARED" and not bool(_queue[0].allow_promotion):
				_fail(_queue[0], {"success": false, "reason": "unapproved_preparation_cancelled_at_barrier"})
			pump(true)
	else:
		pump()
	return job.response


func drain() -> void:
	while not _queue.is_empty():
		if str(_queue[0].phase) == "PREPARED" and not bool(_queue[0].allow_promotion):
			_fail(_queue[0], {"success": false, "reason": "unapproved_preparation_cancelled_at_barrier"})
		pump(true)


func authorize(job: RefCounted) -> void:
	for entry: Dictionary in _queue:
		if entry.job == job:
			entry.allow_promotion = true
			return


func finish_preparation(job: RefCounted, wait := false) -> Dictionary:
	if wait:
		while not bool(job.preparation.get("finished", false)) and not bool(job.response.get("finished", false)):
			if not pump(true):
				return {"finished": false, "success": false, "reason": "earlier_request_awaiting_approval"}
	else:
		pump()
	return job.preparation if bool(job.preparation.get("finished", false)) else job.response


func cancel(job: RefCounted) -> bool:
	return job.request_cancel()


func _guard_allows(entry: Dictionary) -> bool:
	var guard: Callable = entry.guard
	return not guard.is_valid() or bool(guard.call(entry.identity))


func _fail(entry: Dictionary, result: Dictionary) -> void:
	entry.failure = result
	entry.job.run_stage("DISCARD")
	entry.phase = "DISPOSING"


func _complete(entry: Dictionary, result: Dictionary) -> void:
	assert(entry == _queue[0])
	var response := result.duplicate(true)
	response["finished"] = true
	response["identity"] = entry.identity.duplicate(true)
	entry.job.response = response.duplicate(true)
	if not bool(entry.job.preparation.get("finished", false)):
		entry.job.preparation = response
	_queue.pop_front()
	# The owner consumes the receipt on main before the next queue item is
	# pumped. It must commit all fields before emitting potentially reentrant
	# signals. No completion callable is stored in a worker object.
	var on_complete: Callable = entry.on_complete
	if on_complete.is_valid():
		on_complete.call(response)


func _validate(validator: Callable, document: Dictionary) -> Dictionary:
	if not validator.is_valid():
		return {"valid": true, "terminal": false}
	var result: Variant = validator.call(document.duplicate(true))
	if result is Dictionary and result.get("valid", null) is bool:
		return result
	return {"valid": false, "terminal": false, "reason": "invalid_validator_result"}


static func _plain_json_value(value: Variant, depth := 0) -> bool:
	# RefCounted/Node/Callable values must never enter a worker's snapshot graph.
	# The depth limit also rejects cyclic inputs before duplicate(true).
	if depth > 64:
		return false
	if value == null or value is String or value is bool or value is int:
		return true
	if value is float:
		return is_finite(value)
	if value is Array:
		for child: Variant in value:
			if not _plain_json_value(child, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _plain_json_value(value[key], depth + 1):
				return false
		return true
	return false
