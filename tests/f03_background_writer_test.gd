extends Node

const Job := preload("res://scripts/json_persistence_job.gd")
const Service := preload("res://scripts/json_persistence_service.gd")
var approvals := 0
var completions: Array[Dictionary] = []
var current_profile := "owner"
var sandbox := ""
var polling_usec: Array[int] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	sandbox = "user://f03_writer_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(sandbox)) == OK)
	var service := Service.new()
	var path := sandbox.path_join("owner.json")
	var identity := {"profile_id": "owner", "generation": "0123456789abcdef0123456789abcdef", "sequence": 1}
	var payload := {"value": 10, "sequence": 1}
	var first: RefCounted = service.submit(path, identity, payload, _validate, _guard, false, null, _complete)
	identity.profile_id = "foreign"
	payload.value = -1
	await _finish(service, first)
	assert(first.response.success and first.response.identity.profile_id == "owner")
	assert(_read(path).value == 10)
	assert(first.response.worker_thread_ids.size() == 3)
	for thread_id: int in first.response.worker_thread_ids:
		assert(thread_id != OS.get_main_thread_id())
	assert(completions.size() == 1 and approvals >= 1)
	# FIFO commits preserve the actual immediately preceding primary as backup.
	var second: RefCounted = service.submit(path, {"profile_id": "owner", "sequence": 2}, {"value": 20, "sequence": 2}, _validate, _guard)
	var third: RefCounted = service.submit(path, {"profile_id": "owner", "sequence": 3}, {"value": 30, "sequence": 3}, _validate, _guard)
	await _finish(service, third)
	assert(second.response.success and third.response.success)
	assert(_read(path).value == 30 and _read(path + ".bak").value == 20)
	assert(third.response.backup_document.sequence == 2)
	var before := FileAccess.get_file_as_bytes(path)
	var backup := FileAccess.get_file_as_bytes(path + ".bak")
	var rejected: RefCounted = service.submit(path, {"profile_id": "owner"}, {"value": -5}, _validate, _guard)
	await _finish(service, rejected)
	assert(not rejected.response.success and FileAccess.get_file_as_bytes(path) == before)
	assert(FileAccess.get_file_as_bytes(path + ".bak") == backup)
	# Delayed completion cannot cross a changed request identity.
	var denied: RefCounted = service.submit(path, {"profile_id": "owner"}, {"value": 40}, _validate, _guard, false, null, Callable(), true)
	assert(service.finish_preparation(denied, true).success)
	current_profile = "other"
	await _finish(service, denied)
	assert(not denied.response.success and FileAccess.get_file_as_bytes(path) == before)
	current_profile = "owner"
	# A prepared but unapproved file is private and cannot become authority.
	var cancelled: RefCounted = service.submit(path, {"profile_id": "owner"}, {"value": 50}, _validate, _guard, false, null, Callable(), true)
	assert(service.finish_preparation(cancelled, true).success)
	assert(service.cancel(cancelled))
	await _finish(service, cancelled)
	assert(not cancelled.response.success and not FileAccess.file_exists(cancelled.path))
	assert(FileAccess.get_file_as_bytes(path) == before)
	# Actual TMP tampering: records are never filtered to manufacture failure.
	var tampered: RefCounted = service.submit(path, {"profile_id": "owner"}, {"value": 60}, _validate, _guard, false, null, Callable(), true)
	assert(service.finish_preparation(tampered, true).success)
	_write(tampered.path, {"value": 999})
	await _finish(service, tampered)
	assert(not tampered.response.success and FileAccess.get_file_as_bytes(path) == before)
	# Atomic create-only events cannot replace an existing journal sequence.
	var journal := sandbox.path_join("event-1.json")
	var create: RefCounted = service.submit(journal, {"profile_id": "owner"}, {"value": 1}, _validate, _guard, true)
	assert(service.finish(create, true).success)
	var duplicate: RefCounted = service.submit(journal, {"profile_id": "owner"}, {"value": 2}, _validate, _guard, true)
	assert(not service.finish(duplicate, true).success and _read(journal).value == 1)
	# Corrupt primary is quarantined and never rotated over a good old backup.
	_write_text(path, "{broken")
	var recover: RefCounted = service.submit(path, {"profile_id": "owner"}, {"value": 70, "sequence": 7}, _validate, _guard)
	assert(service.finish(recover, true).success)
	assert(not recover.response.backup_rotated and recover.response.backup_document.sequence == 2)
	assert(FileAccess.get_file_as_bytes(path + ".bak") == backup)
	# Synchronous compatibility reuses <target>.tmp, but quarantine/backup holds
	# must remain unique per request. Two corrupt-primary recoveries reproduce
	# a collision if these paths are derived only from that reused TMP.
	for index in range(2):
		_write_text(path, "{broken-again")
		var fixed_tmp: RefCounted = service.submit(path, {"profile_id": "owner"}, {"value": 71 + index}, _validate, _guard, false, null, Callable(), false, null, path + ".tmp")
		assert(service.finish(fixed_tmp, true).success)
		assert(FileAccess.get_file_as_bytes(path + ".bak") == backup)
	# A terminal business failure is not repaired by replacing it with a new save.
	_write(path, {"value": 80, "terminal": true})
	var terminal_bytes := FileAccess.get_file_as_bytes(path)
	var terminal: RefCounted = service.submit(path, {"profile_id": "owner"}, {"value": 90}, _validate, _guard)
	assert(not service.finish(terminal, true).success)
	assert(FileAccess.get_file_as_bytes(path) == terminal_bytes)
	_write(path, {"value": 100})
	# CAS checks previous and backup bytes again in the committing worker.
	var raced: RefCounted = service.submit(path, {"profile_id": "owner"}, {"value": 110}, _validate, _guard, false, null, Callable(), true)
	assert(service.finish_preparation(raced, true).success)
	service.authorize(raced)
	service.pump() # Start READ_PREVIOUS.
	assert(raced.stage_result(true).result.success)
	_write(path, {"value": 101})
	assert(not service.finish(raced, true).success and _read(path).value == 101)
	# The exact known-previous optimization must reject changed external bytes.
	var stale_known: RefCounted = service.submit(path, {"profile_id": "owner"}, {"value": 120}, _validate, _guard, false, before, Callable(), false, null, "", true)
	assert(not service.finish(stale_known, true).success and _read(path).value == 101)
	# A sync barrier cancels old unapproved preparations before its own commit.
	var unapproved: RefCounted = service.submit(path, {"profile_id": "owner"}, {"value": 130}, _validate, _guard, false, null, Callable(), true)
	assert(service.finish_preparation(unapproved, true).success)
	var authoritative: RefCounted = service.submit(path, {"profile_id": "owner"}, {"value": 140}, _validate, _guard)
	assert(service.finish(authoritative, true).success and not unapproved.response.success)
	assert(_read(path).value == 140 and not FileAccess.file_exists(unapproved.path))
	# Already executing promotion cannot claim it cancelled the durable write.
	var committing: RefCounted = service.submit(path, {"profile_id": "owner"}, {"value": 150}, _validate, _guard, false, null, Callable(), true)
	assert(service.finish_preparation(committing, true).success)
	service.authorize(committing)
	service.pump()
	service.pump(true) # Read receipt starts PROMOTE.
	assert(committing.stage_result(true).result.success)
	assert(not service.cancel(committing))
	assert(service.finish(committing, true).success and _read(path).value == 150)
	assert(service.pending_count() == 0)
	var forbidden := Node.new()
	assert(service.submit(path, {"profile_id": "owner"}, {"node": forbidden}, _validate) == null)
	forbidden.free()
	assert(service.submit(path, {"profile_id": "owner"}, {"invalid_float": NAN}, _validate) == null)
	# A foreign file at a colliding private path is never deleted on failure.
	var collision := Job.new()
	collision.configure(ProjectSettings.globalize_path(path), {}, {"value": 160})
	_write(collision.path, {"value": 999})
	var foreign_bytes := FileAccess.get_file_as_bytes(collision.path)
	collision.run_stage("PREPARE")
	assert(not collision.stage_result(true).result.success)
	collision.run_stage("DISCARD")
	collision.stage_result(true)
	assert(FileAccess.get_file_as_bytes(collision.path) == foreign_bytes)
	print("F03_WRITER_METRICS " + JSON.stringify({"validation_calls": approvals, "nonblocking_poll_usec": polling_usec}))
	print("F03_BACKGROUND_WRITER_PASS")
	get_tree().quit(0)

func _finish(service: RefCounted, job: RefCounted) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while not bool(job.response.get("finished", false)):
		assert(Time.get_ticks_msec() < deadline, "ordered writer must terminate")
		var start := Time.get_ticks_usec()
		service.finish(job)
		polling_usec.append(Time.get_ticks_usec() - start)
		if not bool(job.response.get("finished", false)):
			await get_tree().process_frame

func _validate(document: Dictionary) -> Dictionary:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	approvals += 1
	return {"valid": not bool(document.get("terminal", false)) and float(document.get("value", -1)) >= 0, "terminal": bool(document.get("terminal", false))}

func _guard(identity: Dictionary) -> bool:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	return identity.profile_id == current_profile

func _complete(receipt: Dictionary) -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	completions.append(receipt)

func _read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _write(path: String, value: Dictionary) -> void:
	_write_text(path, JSON.stringify(value))

func _write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(value)
	file.close()
