extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()

const Service := preload("res://scripts/json_persistence_service.gd")
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	_proof.record(value, label)
	checks += 1
	if not value:
		failures.append(label)

func _run() -> void:
	PlayerState.test_mode = true
	var rows: Array = []
	for index in range(10000):
		rows.append({"id": "record:%d" % index, "value": index, "nested": [index, {"flag": true}]})
	var payload := {"records": rows, "owner": "character:fixture"}
	var identity := {"profile_id": "character:fixture", "sequence": 1}
	var expected := JSON.stringify(payload).to_utf8_buffer()
	var callback_document: Array = [{}]
	var service := Service.new()
	var path := "user://framework_owned_transfer_%d/document.json" % Time.get_ticks_usec()
	var validator := func(document: Dictionary) -> Dictionary:
		check(OS.get_thread_caller_id() == OS.get_main_thread_id(), "domain validator stays on main")
		# Existing validators receive a detached mutable candidate; this public
		# boundary is preserved while large completion results change ownership.
		check(not document.is_read_only(), "domain validator retains a private mutable root")
		return {"valid": document.has("records"), "terminal": false}
	var callback := func(receipt: Dictionary) -> void:
		check(OS.get_thread_caller_id() == OS.get_main_thread_id(), "completion remains on main")
		callback_document[0] = receipt.document
		receipt.success = false # Only this callback's root copy changes.
	var job := service.submit(path, identity, payload, validator, Callable(), false, null,
		callback, true)
	check(job != null, "large detached JSON request is accepted")
	if job != null:
		payload.records[0].nested[1].flag = false
		identity.profile_id = "foreign:after_submit"
		var prepared: Dictionary = service.finish_preparation(job, true)
		check(bool(prepared.get("success", false)), "worker prepares all records")
		if bool(prepared.get("success", false)):
			check(is_same(prepared.document, job._parsed), "prepared document transfers without a complete deep copy")
			check(prepared.document.is_read_only() and prepared.document.records.is_read_only()
				and prepared.document.records[0].is_read_only()
				and prepared.document.records[0].nested.is_read_only()
				and prepared.document.records[0].nested[1].is_read_only(),
				"worker-owned graph is recursively immutable before transfer")
			check(bool(prepared.document.records[0].nested[1].flag), "post-submit caller mutation cannot enter worker graph")
		var completed: Dictionary = service.finish(job, true)
		check(bool(completed.get("finished", false)) and bool(completed.get("success", false)),
			"callback root edits do not change the request completion receipt")
		if bool(completed.get("success", false)):
			check(is_same(completed.document, job._parsed) and is_same(callback_document[0], completed.document),
				"completion and callback share only the immutable owned graph")
			check(completed.document.records.size() == 10000
				and str(completed.document.records[-1].id) == "record:9999", "all exact records survive promotion")
			check(str(completed.identity.profile_id) == "character:fixture", "submission identity remains detached")
			check(FileAccess.get_file_as_bytes(path) == expected and completed.bytes == expected,
				"worker ownership changes preserve exact persisted bytes")
			for thread_id: int in completed.worker_thread_ids:
				check(thread_id != OS.get_main_thread_id(), "file stage remains worker-owned")
		check(service.pending_count() == 0 and job._task_id == -1, "writer and worker tasks drain completely")
	if not _proof.write_receipt("persistence_owned_transfer_test", checks, failures.size()):
		failures.append("framework assertion receipt failed")
	print(("FRAMEWORK_PERSISTENCE_OWNED_TRANSFER_PASS" if failures.is_empty()
		else "FRAMEWORK_PERSISTENCE_OWNED_TRANSFER_FAIL") + " checks=" + str(checks)
		+ " failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
