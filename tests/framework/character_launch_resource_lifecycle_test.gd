extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var launcher: Node = load("res://scenes/character_select.tscn").instantiate()
	add_child(launcher)
	launcher._request_launch_scene_preload()
	var path: String = launcher._launch_scene_preload_path
	check(path == "res://scenes/main.tscn" and launcher._launch_scene_preload_state == launcher.LAUNCH_PRELOAD_REQUESTED,
		"actual hall requests the real production PackedScene before a native exit")
	var before := ResourceLoader.load_threaded_get_status(path)
	launcher.free()
	check(not is_instance_valid(launcher), "native owner deletion has actually completed")
	var after := ResourceLoader.load_threaded_get_status(path)
	check(after != ResourceLoader.THREAD_LOAD_IN_PROGRESS,
		"native owner exit joins its actual outstanding scene load before resources can be unmounted")
	# A failing implementation is explicitly drained here so the negative
	# control exits cleanly and records the actual ownership failure once.
	if after in [ResourceLoader.THREAD_LOAD_IN_PROGRESS, ResourceLoader.THREAD_LOAD_LOADED]:
		var loaded: Resource = ResourceLoader.load_threaded_get(path)
		check(loaded is PackedScene, "real preloaded production resource remains valid")
	print("CHARACTER_LAUNCH_RESOURCE_TRACE ", JSON.stringify({"path": path, "before": before, "after_exit": after}))
	# Replacing a requested path invalidates its monitor, not its native load.
	# Tree exit must close both accepted requests even if display state failed.
	var replacement: Node = load("res://scenes/character_select.tscn").instantiate()
	add_child(replacement)
	replacement._request_launch_scene_preload()
	replacement.launch_scene_path = "res://scenes/character_select.tscn"
	replacement._request_launch_scene_preload()
	var outstanding: Array = replacement._launch_scene_preload_requests.keys()
	check(outstanding.size() == 2 and replacement._launch_scene_preload_request_count == 2,
		"replaced real PackedScene path retains both accepted native requests")
	var generation: int = replacement._launch_scene_preload_generation
	remove_child(replacement)
	for requested: String in outstanding:
		check(ResourceLoader.load_threaded_get_status(requested) not in [ResourceLoader.THREAD_LOAD_IN_PROGRESS, ResourceLoader.THREAD_LOAD_LOADED],
			"actual tree exit consumes the tracked native request: " + requested)
	check(replacement._launch_scene_preload_requests.is_empty() and replacement._launch_scene_preload_resource == null
		and replacement._launch_scene_preload_state == replacement.LAUNCH_PRELOAD_IDLE
		and replacement._launch_scene_preload_generation == generation + 1,
		"exit clears ownership and invalidates prior monitors without disabling future prewarm")
	replacement.free()
	_run_same_stack_path_return()
	proof.write_receipt("character_launch_resource_lifecycle_test", proof.records.size(), failures.size())
	print("CHARACTER_LAUNCH_RESOURCE_LIFECYCLE_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)

func _run_same_stack_path_return() -> void:
	var path_a := "res://scenes/main.tscn"
	var path_b := "res://scenes/character_select.tscn"
	var paths: Array[String] = [path_a, path_b]
	var baseline := _native_statuses(paths)
	var clean_baseline := int(baseline[path_a]) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE \
		and int(baseline[path_b]) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	check(clean_baseline, "same-stack path-return case starts without another owner's native retrieval rights")
	if not clean_baseline:
		print("CHARACTER_LAUNCH_PATH_RETURN_TRACE ", JSON.stringify(_identity().merged({"baseline": baseline, "case_started": false})))
		return
	var owner: Node = load(path_b).instantiate()
	owner.launch_scene_path = path_a
	add_child(owner)
	# No await or deferred monitor runs between these three production requests.
	owner._request_launch_scene_preload()
	var after_a := _owner_snapshot(owner, paths)
	owner.launch_scene_path = path_b
	owner._request_launch_scene_preload()
	var after_b := _owner_snapshot(owner, paths)
	owner.launch_scene_path = path_a
	owner._request_launch_scene_preload()
	var before_exit := _owner_snapshot(owner, paths)
	check(owner._launch_scene_preload_path == path_a and owner._launch_scene_preload_state == owner.LAUNCH_PRELOAD_REQUESTED,
		"same-stack A-to-B-to-A returns to the actual outstanding production main scene")
	var keys: Array = owner._launch_scene_preload_requests.keys()
	check(keys.size() == 2 and keys.has(path_a) and keys.has(path_b)
		and owner._launch_scene_preload_request_count == 2,
		"same-stack A-to-B-to-A owns exactly two distinct native requests without reacquiring A")
	var generation: int = owner._launch_scene_preload_generation
	remove_child(owner)
	var after_exit := _owner_snapshot(owner, paths)
	for requested: String in paths:
		# Assert the native boundary before any negative-control cleanup.
		check(int(after_exit.native_statuses[requested]) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
			"same-stack owner exit leaves no native retrieval token: " + requested)
	check(owner._launch_scene_preload_requests.is_empty() and owner._launch_scene_preload_resource == null
		and owner._launch_scene_preload_state == owner.LAUNCH_PRELOAD_IDLE
		and owner._launch_scene_preload_generation == generation + 1,
		"same-stack exit clears ownership and invalidates every prior monitor")
	# The known negative control can leave one extra A token. Retrieve only that
	# owned surplus once, after the failing boundary checks have been recorded.
	var cleanup_gets := 0
	var surplus_status := ResourceLoader.load_threaded_get_status(path_a)
	if surplus_status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS, ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED]:
		var surplus: Resource = ResourceLoader.load_threaded_get(path_a)
		cleanup_gets = 1
		check(surplus is PackedScene, "owned path-return negative control still contains the actual valid main PackedScene")
	var after_cleanup := _native_statuses(paths)
	check(int(after_cleanup[path_a]) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
		and int(after_cleanup[path_b]) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"one owned surplus retrieval cleans the negative control without hiding its original assertions")
	print("CHARACTER_LAUNCH_PATH_RETURN_TRACE ", JSON.stringify(_identity().merged({
		"baseline": baseline, "after_a": after_a, "after_b": after_b, "before_exit": before_exit,
		"after_exit": after_exit, "red_cleanup_gets": cleanup_gets, "after_cleanup": after_cleanup})))
	owner.free()

func _native_statuses(paths: Array[String]) -> Dictionary:
	var statuses := {}
	for requested: String in paths:
		statuses[requested] = ResourceLoader.load_threaded_get_status(requested)
	return statuses

func _owner_snapshot(owner: Node, paths: Array[String]) -> Dictionary:
	return {"generation": owner._launch_scene_preload_generation, "request_count": owner._launch_scene_preload_request_count,
		"path": owner._launch_scene_preload_path, "state": str(owner._launch_scene_preload_state),
		"tracked_paths": owner._launch_scene_preload_requests.keys(), "native_statuses": _native_statuses(paths)}

func _identity() -> Dictionary:
	return {"run_id": OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
		"invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
		"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256")}
