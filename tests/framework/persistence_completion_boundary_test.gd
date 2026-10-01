extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()

const Job := preload("res://scripts/json_persistence_job.gd")
const Service := preload("res://scripts/json_persistence_service.gd")
var checks := 0
var failures: Array[String] = []

class PublishBeforeExit extends Job:
	var published := Semaphore.new()
	var release := Semaphore.new()
	var event_mutex := Mutex.new()
	var release_event := false

	func _perform(_stage: String) -> void:
		_mutex.lock()
		_stage_result = {"success": true, "marker": 1}
		_stage_finished = true
		_mutex.unlock()
		published.post()
		release.wait()

	func release_later() -> void:
		# Independent finite releaser makes the old blocking poll observable
		# without hanging the test. Event order is the correctness assertion.
		OS.delay_msec(250)
		event_mutex.lock()
		release_event = true
		event_mutex.unlock()
		release.post()

	func has_release_event() -> bool:
		event_mutex.lock()
		var value := release_event
		event_mutex.unlock()
		return value

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	_proof.record(value, label)
	checks += 1
	if not value:
		failures.append(label)

func _run() -> void:
	PlayerState.test_mode = true
	var job := PublishBeforeExit.new()
	job.run_stage("PREPARE")
	while not job.published.try_wait():
		await get_tree().process_frame
	var releaser := Thread.new()
	check(releaser.start(job.release_later) == OK, "finite independent releaser starts")
	var polled: Dictionary = job.stage_result(false)
	check(not job.has_release_event(), "ordinary poll returns before worker release event")
	check(not bool(polled.finished), "published result is pending until actual task completion")
	releaser.wait_to_finish()
	var joined: Dictionary = job.stage_result(true)
	check(bool(joined.finished) and int(joined.result.marker) == 1,
		"explicit lifecycle barrier consumes the completed result")
	check(job._task_id == -1, "completed WorkerThreadPool task is reclaimed")
	_verify_writer_completion_reentry()
	if not _proof.write_receipt("persistence_completion_boundary_test", checks, failures.size()):
		failures.append("framework assertion receipt failed")
	print(("FRAMEWORK_PERSISTENCE_BOUNDARY_PASS" if failures.is_empty()
		else "FRAMEWORK_PERSISTENCE_BOUNDARY_FAIL") + " checks=" + str(checks)
		+ " failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _verify_writer_completion_reentry() -> void:
	var service := Service.new()
	var events: Array[String] = []
	var second: Array = [null]
	var directory := "user://framework_writer_boundary_%d" % Time.get_ticks_usec()
	var validator := func(_document: Dictionary) -> Dictionary:
		return {"valid": true, "terminal": false}
	var complete_first := func(_receipt: Dictionary) -> void:
		events.append("first_begin")
		second[0] = service.submit(directory.path_join("second.json"), {"sequence": 2},
			{"value": 2}, validator, Callable(), false, null,
			func(_second_receipt: Dictionary) -> void: events.append("second"))
		check(second[0] != null, "callback may enqueue a second request")
		if second[0] != null:
			check(int(second[0]._task_id) == -1 and str(service._queue[0].phase) == "NEW",
				"callback submit cannot start the next writer")
			var blocked: Dictionary = service.finish(second[0], true)
			check(not bool(blocked.get("finished", false))
				and str(blocked.get("reason", "")) == "writer_reentrant_barrier",
				"reentrant synchronous barrier returns an explicit pending result")
			var drained: Variant = service.call("drain")
			check(drained is bool and not bool(drained),
				"reentrant drain does not advance or loop the writer")
		events.append("first_end")
	var first := service.submit(directory.path_join("first.json"), {"sequence": 1},
		{"value": 1}, validator, Callable(), false, null, complete_first)
	check(first != null, "first ordered request is accepted")
	if first == null:
		return
	var receipt: Dictionary = service.finish(first, true)
	check(bool(receipt.get("success", false)), "first real JSON commit succeeds")
	if second[0] != null:
		var second_receipt: Dictionary = service.finish(second[0], true)
		check(bool(second_receipt.get("success", false)), "second commit completes after callback returns")
	check(events == ["first_begin", "first_end", "second"], "each receipt runs once in domain order")
	check(service.pending_count() == 0, "ordered writer drains completely")
