extends Node

## Controlled regression: same-stack hall removal before its real _ready-deferred request.
## No ResourceLoader override, synthetic request, or _ready override is used.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const HALL_PATH := "res://scenes/character_select.tscn"
const LAUNCH_PATH := "res://scenes/main.tscn"
const SCENE_ID := "hall_deferred_admission_test"
const INVALID := ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
const IN_PROGRESS := ResourceLoader.THREAD_LOAD_IN_PROGRESS
const LOADED := ResourceLoader.THREAD_LOAD_LOADED
const FAILED := ResourceLoader.THREAD_LOAD_FAILED

var proof := Proof.new()
var failures: Array[String] = []
var trace: Dictionary = {}
var hall: Node
var red_cleanup_gets := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _identity() -> Dictionary:
	return {
		"run_id": OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
		"invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
		"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
	}

func _snapshot(subject: Node) -> Dictionary:
	return {
		"process_frame": Engine.get_process_frames(),
		"ticks_msec": Time.get_ticks_msec(),
		"inside_tree": subject.is_inside_tree(),
		"queued_for_deletion": subject.is_queued_for_deletion(),
		"launch_path": subject.launch_scene_path,
		"preload_path": subject._launch_scene_preload_path,
		"preload_state": str(subject._launch_scene_preload_state),
		"request_count": subject._launch_scene_preload_request_count,
		"request_keys": subject._launch_scene_preload_requests.keys(),
		"generation": subject._launch_scene_preload_generation,
		"resource_is_packed_scene": subject._launch_scene_preload_resource is PackedScene,
		"native_status": ResourceLoader.load_threaded_get_status(LAUNCH_PATH),
	}

func _run() -> void:
	trace = _identity().merged({
		"scene_id": SCENE_ID,
		"hall_scene": HALL_PATH,
		"default_launch_path": LAUNCH_PATH,
		"manual_request_calls": 0,
		"scope": "real character_select PackedScene and production default main PackedScene; same-stack removal before original _ready call_deferred, then legal request_ready reentry; isolated native runner only, not normal player navigation/APK/device",
	})
	var isolated := OS.get_environment("APPDATA").replace("\\", "/").contains("/.godot/runtime_appdata/")
	check(isolated and not PlayerState.test_mode, "production test_mode=false uses runner-isolated APPDATA")
	check(not str(trace.run_id).is_empty() and not str(trace.invocation_id).is_empty()
		and str(trace.source_content_sha256).length() == 64,
		"receipt source, run and invocation identities are present")
	check(ResourceLoader.load_threaded_get_status(LAUNCH_PATH) == INVALID,
		"default main path begins without another native request token")
	if not failures.is_empty():
		_finish()
		return
	var hall_scene: PackedScene = ResourceLoader.load(HALL_PATH) as PackedScene
	check(hall_scene != null, "real character select scene loads")
	if hall_scene == null:
		_finish()
		return
	hall = hall_scene.instantiate()
	check(hall != null and hall.launch_scene_path == LAUNCH_PATH,
		"unmodified hall starts with its production default main PackedScene path")
	if hall == null or hall.launch_scene_path != LAUNCH_PATH:
		_finish()
		return
	trace["before_first_add"] = _snapshot(hall)
	# add_child invokes the actual hall _ready and queues its production request.
	# remove_child runs in that same call stack, before any deferred callback.
	add_child(hall)
	trace["after_first_ready_same_stack"] = _snapshot(hall)
	remove_child(hall)
	trace["before_first_deferred_after_exit"] = _snapshot(hall)
	check(int(trace.after_first_ready_same_stack.process_frame)
		== int(trace.before_first_deferred_after_exit.process_frame),
		"first add and removal occur in the same process frame before deferred dispatch")
	check(int(trace.before_first_deferred_after_exit.request_count) == 0
		and trace.before_first_deferred_after_exit.request_keys.is_empty()
		and int(trace.before_first_deferred_after_exit.native_status) == INVALID,
		"same-stack exit precedes first deferred native request admission")
	# A later deferred marker on the same live Object establishes that the idle
	# queue has advanced past the original _ready callback; two more frames also
	# let any monitor scheduled by that callback run. It is never manually called.
	hall.call_deferred("set_meta", &"fixture_after_first_deferred", true)
	var deadline := Time.get_ticks_msec() + 5000
	while not hall.has_meta(&"fixture_after_first_deferred") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(hall.has_meta(&"fixture_after_first_deferred"), "deferred queue reaches the marker after original hall _ready")
	for frame in 2:
		await get_tree().process_frame
	trace["after_first_deferred_outside_tree"] = _snapshot(hall)
	var after_first: Dictionary = trace.after_first_deferred_outside_tree
	check(int(after_first.request_count) == 0,
		"out-of-tree original deferred callback admits zero native requests")
	check(after_first.request_keys.is_empty(),
		"out-of-tree original deferred callback leaves no hall request ownership")
	check(int(after_first.native_status) == INVALID,
		"out-of-tree original deferred callback leaves no default-path native token")
	check(not bool(after_first.inside_tree) and not bool(after_first.queued_for_deletion),
		"observed hall remains live and outside the scene tree after deferred callback")

	# RED cleanup runs only after the three original boundary assertions. This
	# fixture created the only main-path request in this isolated process.
	var leaked_status := ResourceLoader.load_threaded_get_status(LAUNCH_PATH)
	trace["native_before_red_cleanup"] = leaked_status
	if leaked_status in [IN_PROGRESS, LOADED, FAILED]:
		var unused: Resource = ResourceLoader.load_threaded_get(LAUNCH_PATH)
		red_cleanup_gets = 1
		trace["red_cleanup_result_is_null"] = unused == null
	trace["red_cleanup_gets"] = red_cleanup_gets
	trace["after_red_cleanup"] = _snapshot(hall)
	check(red_cleanup_gets == 0, "original hall exit requires no fixture native retrieval")
	check(ResourceLoader.load_threaded_get_status(LAUNCH_PATH) == INVALID,
		"owned native token is closed before legal reentry")

	# The same retained hall legally re-enters: request_ready makes its actual
	# _ready run again. Production _ready, not the fixture, queues the request.
	hall.request_ready()
	trace["before_reentry_add"] = _snapshot(hall)
	add_child(hall)
	trace["after_reentry_ready_same_stack"] = _snapshot(hall)
	check(hall.is_inside_tree() and hall.content_root != null,
		"request_ready reentry executes the real character hall _ready")
	deadline = Time.get_ticks_msec() + 20000
	while hall._launch_scene_preload_state in [hall.LAUNCH_PRELOAD_IDLE, hall.LAUNCH_PRELOAD_REQUESTED]:
		if Time.get_ticks_msec() >= deadline:
			break
		await get_tree().process_frame
	trace["after_reentry_terminal"] = _snapshot(hall)
	var after_reentry: Dictionary = trace.after_reentry_terminal
	check(int(after_reentry.request_count) == 1
		and str(after_reentry.preload_path) == LAUNCH_PATH,
		"legal reentry admits exactly one request for the production default path")
	check(str(after_reentry.preload_state) == str(hall.LAUNCH_PRELOAD_READY)
		and bool(after_reentry.resource_is_packed_scene),
		"legal reentry reaches READY with a real main PackedScene")
	check(after_reentry.request_keys.is_empty() and int(after_reentry.native_status) == INVALID,
		"READY hall has collected its single native request")
	remove_child(hall)
	trace["after_reentry_exit"] = _snapshot(hall)
	check(hall._launch_scene_preload_requests.is_empty()
		and ResourceLoader.load_threaded_get_status(LAUNCH_PATH) == INVALID,
		"legal reentry exit closes ownership and native token")
	hall.free()
	hall = null
	_finish()

func _finish() -> void:
	if is_instance_valid(hall):
		if hall.is_inside_tree():
			remove_child(hall)
		var final_status := ResourceLoader.load_threaded_get_status(LAUNCH_PATH)
		if final_status in [IN_PROGRESS, LOADED, FAILED]:
			var unused: Resource = ResourceLoader.load_threaded_get(LAUNCH_PATH)
			trace["final_safety_cleanup_result_is_null"] = unused == null
		hall.free()
		hall = null
	trace["final_native_status"] = ResourceLoader.load_threaded_get_status(LAUNCH_PATH)
	trace["red_cleanup_gets"] = red_cleanup_gets
	var trace_directory := "res://outputs/test_logs/framework"
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(trace_directory)) == OK,
		"bounded native trace directory is available")
	var trace_file := FileAccess.open(trace_directory.path_join(SCENE_ID.trim_suffix("_test") + "_trace.json"), FileAccess.WRITE)
	check(trace_file != null, "deferred admission trace opens")
	if trace_file != null:
		trace["checks_before_trace_write"] = proof.records
		trace["failures_before_trace_write"] = failures
		trace_file.store_string(JSON.stringify(trace, "  "))
		trace_file.flush()
		check(trace_file.get_error() == OK, "deferred admission trace writes completely")
		trace_file.close()
	var written := proof.write_receipt(SCENE_ID, proof.records.size(), failures.size())
	print("HALL_DEFERRED_ADMISSION_", "PASS" if written and failures.is_empty() else "FAIL",
		" checks=", proof.records.size(), " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
