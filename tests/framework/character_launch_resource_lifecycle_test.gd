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
	proof.write_receipt("character_launch_resource_lifecycle_test", proof.records.size(), failures.size())
	print("CHARACTER_LAUNCH_RESOURCE_LIFECYCLE_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
