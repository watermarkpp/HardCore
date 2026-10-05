extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const OWNED_PREFIX := "character_preload_owned_failure_"
const VALID_ROOT_NAME := "OwnedLawfulPackedSceneRetry"
const STATE_WAIT_MSEC := 3000
var proof := Proof.new()
var failures: Array[String] = []
var owned_path := ""
var owned_file_created := false
var trace: Dictionary = {}

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	trace = {"run_id": OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
		"invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
		"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"scope": "test-owned binary PackedScene fault and same-path lawful retry; no natural production-asset failure claim"}
	var user_root := ProjectSettings.globalize_path("user://").replace("\\", "/")
	var isolated := user_root.contains("/.godot/runtime_appdata/")
	check(isolated and not str(trace.run_id).is_empty(), "owned failure fixture uses this native run's isolated test user directory")
	if not isolated or str(trace.run_id).is_empty():
		_finish(null)
		return
	owned_path = "user://" + OWNED_PREFIX + str(trace.run_id) + "_" + str(get_instance_id()) + ".res"
	trace["path"] = owned_path
	var absent := not FileAccess.file_exists(owned_path)
	check(absent, "unique fault target did not exist before this fixture claimed it")
	if not absent:
		owned_path = ""
		_finish(null)
		return
	var save_error := _write_valid_scene()
	owned_file_created = FileAccess.file_exists(owned_path)
	check(save_error == OK and owned_file_created, "owned PackedScene serializes through the real ResourceSaver before fault injection")
	if save_error != OK or not owned_file_created:
		_finish(null)
		return
	var lawful_bytes := FileAccess.get_file_as_bytes(owned_path)
	check(lawful_bytes.size() > 4 and not ResourceLoader.has_cached(owned_path), "saved fixture is uncached and has a complete binary resource beyond its magic")
	if lawful_bytes.size() <= 4 or ResourceLoader.has_cached(owned_path):
		_finish(null)
		return
	# Preserve only this owned binary file's original magic, truncating its
	# serialized body. The engine loader, not a mock, must reject the bytes.
	var fault_file := FileAccess.open(owned_path, FileAccess.WRITE)
	check(fault_file != null, "fixture can truncate only its unique owned user resource")
	if fault_file == null:
		_finish(null)
		return
	fault_file.store_buffer(lawful_bytes.slice(0, 4))
	fault_file.close()
	check(FileAccess.get_file_as_bytes(owned_path) == lawful_bytes.slice(0, 4), "only the owned resource body was replaced with the bounded binary fault")
	var accepted_identity := ResourceLoader.exists(owned_path, "PackedScene")
	check(accepted_identity, "corrupt owned file still passes the real PackedScene existence gate, so failure occurs after request acquisition")
	if not accepted_identity:
		_finish(null)
		return
	var owner: Node = load("res://scenes/character_select.tscn").instantiate()
	owner.launch_scene_path = owned_path
	add_child(owner)
	trace["before_request"] = _snapshot(owner)
	check(int(trace.before_request.native_status) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"unique owned path starts without any prior native retrieval token")
	owner._request_launch_scene_preload()
	trace["after_request"] = _snapshot(owner)
	check(owner._launch_scene_preload_request_count == 1 and owner._launch_scene_preload_state == owner.LAUNCH_PRELOAD_REQUESTED,
		"actual hall acquired exactly one owned native request before the worker fault")
	# Observe this tiny real worker's terminal result before yielding to the
	# deferred hall monitor. This distinguishes engine FAILED from UI-only
	# missing-path/type rejection while leaving the production monitor unchanged.
	var native_deadline := Time.get_ticks_msec() + STATE_WAIT_MSEC
	var terminal_status := ResourceLoader.load_threaded_get_status(owned_path)
	while terminal_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and Time.get_ticks_msec() < native_deadline:
		OS.delay_msec(1)
		terminal_status = ResourceLoader.load_threaded_get_status(owned_path)
	trace["terminal_worker_before_monitor"] = _snapshot(owner)
	check(terminal_status == ResourceLoader.THREAD_LOAD_FAILED,
		"real accepted binary loader worker reaches terminal FAILED before the actual hall monitor handles it")
	if terminal_status != ResourceLoader.THREAD_LOAD_FAILED:
		_finish(owner)
		return
	await _wait_for_state(owner, owner.LAUNCH_PRELOAD_FAILED)
	trace["after_failed_monitor"] = _snapshot(owner)
	var failed_state: bool = owner._launch_scene_preload_state == owner.LAUNCH_PRELOAD_FAILED
	check(failed_state, "actual hall monitor receives the real terminal binary-load failure")
	var native_after_failure := ResourceLoader.load_threaded_get_status(owned_path)
	# Record the ownership assertion before any RED cleanup.
	check(native_after_failure == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"actual hall terminal FAILED handling retrieves and releases its original native user token")
	check(owner._launch_scene_preload_requests.is_empty(), "terminal failure removes the original owned request rather than retaining a stale path entry")
	var failure_cleanup_gets := 0
	if native_after_failure == ResourceLoader.THREAD_LOAD_FAILED:
		var failed_result: Resource = ResourceLoader.load_threaded_get(owned_path)
		failure_cleanup_gets = 1
		check(failed_result == null, "owned negative-control retrieval preserves the real failed worker result")
	trace["red_failure_cleanup_gets"] = failure_cleanup_gets
	trace["after_failure_cleanup"] = _snapshot(owner)
	var fresh_boundary := failed_state and ResourceLoader.load_threaded_get_status(owned_path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	check(fresh_boundary, "lawful retry begins only after the old failed native token has been consumed")
	if not fresh_boundary:
		_finish(owner)
		return
	var retry_save_error := _write_valid_scene()
	check(retry_save_error == OK and FileAccess.get_file_as_bytes(owned_path).size() > 4
		and not ResourceLoader.has_cached(owned_path), "same unique path receives a fresh valid uncached PackedScene through ResourceSaver")
	if retry_save_error != OK or ResourceLoader.has_cached(owned_path):
		_finish(owner)
		return
	var prior_generation: int = owner._launch_scene_preload_generation
	owner._request_launch_scene_preload()
	trace["after_lawful_retry_request"] = _snapshot(owner)
	check(owner._launch_scene_preload_request_count == 2 and owner._launch_scene_preload_generation == prior_generation + 1
		and owner._launch_scene_preload_state == owner.LAUNCH_PRELOAD_REQUESTED,
		"same-path lawful retry acquires its own fresh native request through the unchanged hall API")
	await _wait_for_state(owner, owner.LAUNCH_PRELOAD_READY)
	trace["after_lawful_retry_monitor"] = _snapshot(owner)
	var ready: bool = owner._launch_scene_preload_state == owner.LAUNCH_PRELOAD_READY and owner._launch_scene_preload_resource is PackedScene
	check(ready, "fresh lawful worker result reaches READY as a real usable PackedScene")
	if ready:
		var instance: Node = owner._launch_scene_preload_resource.instantiate()
		check(instance != null and instance.name == VALID_ROOT_NAME, "returned PackedScene instantiates the exact newly saved lawful fixture")
		if instance != null: instance.free()
	check(ResourceLoader.load_threaded_get_status(owned_path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
		and owner._launch_scene_preload_requests.is_empty(), "lawful retry monitor consumes its fresh native token exactly once")
	_finish(owner)

func _wait_for_state(owner: Node, desired: StringName) -> void:
	var deadline := Time.get_ticks_msec() + STATE_WAIT_MSEC
	while is_instance_valid(owner) and owner._launch_scene_preload_state != desired and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

func _write_valid_scene() -> Error:
	var root := Node.new()
	root.name = VALID_ROOT_NAME
	var packed := PackedScene.new()
	var error := packed.pack(root)
	root.free()
	if error != OK: return error
	return ResourceSaver.save(packed, owned_path)

func _snapshot(owner: Node) -> Dictionary:
	return {"generation": owner._launch_scene_preload_generation, "request_count": owner._launch_scene_preload_request_count,
		"path": owner._launch_scene_preload_path, "state": str(owner._launch_scene_preload_state),
		"tracked_paths": owner._launch_scene_preload_requests.keys(), "native_status": ResourceLoader.load_threaded_get_status(owned_path)}

func _finish(owner: Node) -> void:
	if is_instance_valid(owner):
		var generation: int = owner._launch_scene_preload_generation
		remove_child(owner)
		trace["after_exit"] = _snapshot(owner)
		check(owner._launch_scene_preload_generation == generation + 1 and owner._launch_scene_preload_requests.is_empty()
			and owner._launch_scene_preload_resource == null, "owned failure/retry owner exit closes its lifecycle and invalidates monitors")
		owner.free()
	if owned_file_created:
		var status := ResourceLoader.load_threaded_get_status(owned_path)
		check(status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "no owned native token remains before deleting the unique fault file")
		var final_cleanup_gets := 0
		if status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS, ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED]:
			ResourceLoader.load_threaded_get(owned_path)
			final_cleanup_gets = 1
		trace["final_red_cleanup_gets"] = final_cleanup_gets
		trace["final_native_status"] = ResourceLoader.load_threaded_get_status(owned_path)
		check(int(trace.final_native_status) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "bounded negative-control cleanup releases this fixture's single remaining owned request")
		var absolute := ProjectSettings.globalize_path(owned_path).replace("\\", "/")
		var user_root := ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/") + "/"
		var exact_owned_target := absolute.begins_with(user_root) and owned_path.get_file().begins_with(OWNED_PREFIX)
		check(exact_owned_target, "deletion resolves to this fixture's unique file inside isolated user data")
		if exact_owned_target:
			var remove_error := DirAccess.remove_absolute(absolute)
			check(remove_error == OK and not FileAccess.file_exists(owned_path), "fixture deletes only its unique owned file after native request cleanup")
	print("CHARACTER_LAUNCH_FAILED_RETRY_TRACE ", JSON.stringify(trace))
	var written := proof.write_receipt("character_launch_failed_preload_retry_test", proof.records.size(), failures.size())
	print("CHARACTER_LAUNCH_FAILED_PRELOAD_RETRY_%s failures=%s" % ["PASS" if written and failures.is_empty() else "FAIL", str(failures)])
	get_tree().quit(0 if written and failures.is_empty() else 1)
