class_name HCR6FrameProbe
extends Node

## Explicitly started TEST instrumentation; not an autoload in production.
## Measures application _process intervals, NOT display-present/GPU durations.
## Call begin_capture(metadata, 60.0), then collect user://hc_r6_frames_*.json.
## A diagnostic harness may call this from a small test-only button.
const CAPACITY := 36000
var _samples := PackedInt64Array()
var _paused := PackedByteArray()
var _count := 0
var _last_usec := 0
var _start_usec := 0
var _end_usec := 0
var _active := false
var _was_paused := false
var _next_count_usec := 0
var _engaged_min := 0
var _engaged_max := 0
var _metadata: Dictionary = {}
var last_output := ""
signal capture_finished(path: String)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func begin_capture(metadata: Dictionary, seconds: float = 60.0) -> Error:
	if _active or not is_inside_tree() or seconds < 20.0 or seconds > 120.0:
		return ERR_INVALID_PARAMETER
	for key: String in ["variant", "source_sha", "apk_sha256", "device_id", "scenario", "map", "monster_count", "monster_mix", "class", "round", "frame_cap", "warm_state", "scene_hash", "save_fixture_hash", "quality", "build_type", "thermal_band"]:
		if not metadata.has(key):
			return ERR_INVALID_PARAMETER
	if str(metadata["source_sha"]).length() != 40 or str(metadata["apk_sha256"]).length() != 64:
		return ERR_INVALID_PARAMETER
	_samples.resize(CAPACITY)
	_paused.resize(CAPACITY)
	_count = 0
	_metadata = metadata.duplicate(true)
	_metadata["sample_kind"] = "application_process_interval_usec"
	_metadata["device_model"] = OS.get_model_name()
	_metadata["os_version"] = OS.get_version()
	_metadata["viewport_size"] = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	_metadata["physics_ticks_per_second"] = Engine.physics_ticks_per_second
	_metadata["renderer"] = str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"))
	_metadata["engaged_at_start"] = _engaged_count()
	_engaged_min = int(_metadata["engaged_at_start"])
	_engaged_max = _engaged_min
	_was_paused = get_tree().paused
	_start_usec = Time.get_ticks_usec()
	_next_count_usec = _start_usec + 1000000
	_last_usec = _start_usec
	_end_usec = _start_usec + int(seconds * 1000000.0)
	_active = true
	set_process(true)
	return OK

func _process(_delta: float) -> void:
	if not _active:
		return
	var now := Time.get_ticks_usec()
	# Fixed frame storage. No per-frame allocation/JSON/sort/filesystem writes.
	_samples[_count] = now - _last_usec
	_paused[_count] = 1 if get_tree().paused or _was_paused else 0
	_was_paused = get_tree().paused
	_count += 1
	_last_usec = now
	# One count sample per second ONLY in the explicit diagnostic capture.
	if now >= _next_count_usec:
		var engaged := _engaged_count()
		_engaged_min = mini(_engaged_min, engaged)
		_engaged_max = maxi(_engaged_max, engaged)
		_next_count_usec = now + 1000000
	if now >= _end_usec or _count >= CAPACITY:
		finish_capture("complete" if now >= _end_usec else "capacity_limit")

func finish_capture(reason: String = "manual_stop") -> void:
	if not _active:
		return
	_active = false
	set_process(false)
	_metadata["stop_reason"] = reason
	_metadata["engaged_at_end"] = _engaged_count()
	_metadata["engaged_min"] = mini(_engaged_min, int(_metadata["engaged_at_end"]))
	_metadata["engaged_max"] = maxi(_engaged_max, int(_metadata["engaged_at_end"]))
	_metadata["duration_seconds"] = float(Time.get_ticks_usec() - _start_usec) / 1000000.0
	_samples.resize(_count)
	_paused.resize(_count)
	last_output = "user://hc_r6_frames_%d.json" % Time.get_ticks_msec()
	var file := FileAccess.open(last_output, FileAccess.WRITE)
	if file == null:
		push_error("HC_R6_FRAME_PROBE_WRITE_FAILED")
		return
	file.store_string(JSON.stringify({"schema": 1, "metadata": _metadata, "samples_usec": Array(_samples), "paused": Array(_paused)}))
	file.close()
	capture_finished.emit(last_output)

func _engaged_count() -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor:
			var enemy := node as EnemyActor
			if not enemy._dying and not enemy._death_pending and enemy.current_hp > 0 and is_instance_valid(enemy.target):
				count += 1
	return count

func _exit_tree() -> void:
	if _active:
		finish_capture("scene_exit")
