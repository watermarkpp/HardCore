extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Preparation := preload("res://scripts/warehouse_prepared_transaction.gd")
var _proof := Proof.new()
var checks := 0
var failures: Array[String] = []

class PublishedBeforeReturn extends Preparation:
	var published := Semaphore.new()
	var release := Semaphore.new()
	var event_mutex := Mutex.new()
	var release_event := false

	func _prepare(_contract: String, _profile: String, _kind: String) -> void:
		_mutex.lock()
		_success = true
		_finished = true
		_mutex.unlock()
		published.post()
		release.wait()

	func release_later() -> void:
		OS.delay_msec(250)
		event_mutex.lock()
		release_event = true
		event_mutex.unlock()
		release.post()

	func was_released() -> bool:
		event_mutex.lock()
		var result := release_event
		event_mutex.unlock()
		return result

func check(value: bool, label: String) -> void:
	_proof.record(value, label)
	checks += 1
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	var directory := "user://framework_warehouse_completion_%d" % Time.get_ticks_usec()
	var paths := {"profile": directory.path_join("profile.json"),
		"shared": directory.path_join("shared.json"), "journal": directory.path_join("journal.json")}
	var probe := PublishedBeforeReturn.new()
	probe.start(paths, {}, "test.warehouse", "test_profile")
	while not probe.published.try_wait():
		await get_tree().process_frame
	var releaser := Thread.new()
	check(releaser.start(probe.release_later) == OK, "independent finite releaser starts")
	var polled: Dictionary = probe.result()
	check(not probe.was_released(), "warehouse poll returns before worker release")
	check(not bool(polled.finished), "published warehouse flags are pending until task returns")
	releaser.wait_to_finish()
	while not bool(probe.result().finished):
		await get_tree().process_frame
	check(bool(probe.result().success) and probe.task_id == -1,
		"completed worker result succeeds and its task is reclaimed")
	probe.cancel()
	check(not bool(probe.result().success), "cancelled preparation cannot be consumed again")
	await _verify_real_preparation(directory, paths)
	if not _proof.write_receipt("warehouse_completion_boundary_test", checks, failures.size()):
		failures.append("framework assertion receipt failed")
	print(("FRAMEWORK_WAREHOUSE_COMPLETION_PASS" if failures.is_empty()
		else "FRAMEWORK_WAREHOUSE_COMPLETION_FAIL") + " checks=" + str(checks)
		+ " failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _verify_real_preparation(directory: String, paths: Dictionary) -> void:
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK,
		"real worker owns an isolated directory")
	var documents := {"before_profile": {"gold": 12}, "after_profile": {"gold": 13},
		"before_shared": {"revision": 1}, "after_shared": {"revision": 2}}
	var job := Preparation.new()
	job.start(paths, documents, "test.warehouse", "test_profile")
	while not bool(job.result().finished):
		await get_tree().process_frame
	check(bool(job.result().success) and job.task_id == -1,
		"actual private-file worker completes without a synchronous polling barrier")
	for key: String in ["profile", "shared", "journal"]:
		check(FileAccess.get_file_as_bytes(job.temporary_paths[key]) == job.bytes[key],
			"private prepared bytes are exact " + key)
		check(not FileAccess.file_exists(paths[key]), "preparation never promotes authority " + key)
	job.cancel()
	for path: String in job.temporary_paths.values():
		check(not FileAccess.file_exists(path), "cancel removes only its owned private file")
