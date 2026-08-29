class_name StartupLoading
extends Control

const TARGET_SCENE_PATH := "res://scenes/character_select.tscn"
const LOADING_CONTRACT_ID := "startup.loading.character_select.v1"
const LAUNCH_SCENE_PATH := "res://scenes/main.tscn"
const LAUNCH_PRELOAD_TIMING_META := &"hardcore.startup.launch_preload_timing.v1"
const LAUNCH_PRELOAD_IDLE := &"idle"
const LAUNCH_PRELOAD_REQUESTED := &"requested"
const LAUNCH_PRELOAD_READY := &"ready"
const LAUNCH_PRELOAD_FAILED := &"failed"

@export var auto_start := true
@onready var brand_intro: Control = $BrandIntro

var _target_scene: PackedScene
var _resource_ready := false
var _authoritative_data_ready := false
var _authoritative_data_failed := false
var _animation_finished := false
var _transition_started := false
var _target_prepare_started := false
var _target_scene_ready := false
var _load_requested := false
var _target_scene_instance: Node
var _launch_scene_preload_path := ""
var _launch_scene_preload_state: StringName = LAUNCH_PRELOAD_IDLE
var _launch_scene_preload_resource: PackedScene
var _launch_scene_preload_request_count := 0
@export var suppress_scene_handoff_for_test := false


func _ready() -> void:
	if not auto_start:
		return
	# The authored intro plays independently while character selection loads.
	# If loading takes longer, BrandIntro remains on its completed final frame.
	_run_finite_loading_phase.call_deferred()
	_begin_target_load()
	# Start the world-scene request while the authored intro and character hall
	# scene are loading. CharacterSelect observes the same ResourceLoader request
	# later instead of starting a second cold dependency walk on click.
	_begin_launch_scene_preload()
	_prepare_authoritative_data.call_deferred()


func _begin_launch_scene_preload() -> void:
	if _launch_scene_preload_state in [LAUNCH_PRELOAD_REQUESTED, LAUNCH_PRELOAD_READY]:
		return
	_launch_scene_preload_path = LAUNCH_SCENE_PATH
	_launch_scene_preload_state = LAUNCH_PRELOAD_IDLE
	_launch_scene_preload_resource = null
	_launch_scene_preload_request_count += 1
	_record_launch_timing(&"startup_preload_request_started")
	var request_error := ResourceLoader.load_threaded_request(
		LAUNCH_SCENE_PATH,
		"PackedScene"
	)
	var existing_status := ResourceLoader.load_threaded_get_status(LAUNCH_SCENE_PATH)
	if (
		request_error != OK
		and existing_status not in [
			ResourceLoader.THREAD_LOAD_IN_PROGRESS,
			ResourceLoader.THREAD_LOAD_LOADED,
		]
	):
		_mark_launch_scene_preload_failed(request_error)
		return
	_launch_scene_preload_state = LAUNCH_PRELOAD_REQUESTED
	_record_launch_timing(&"startup_preload_request_accepted")
	_monitor_launch_scene_preload.call_deferred()


func _monitor_launch_scene_preload() -> void:
	while is_inside_tree() and _launch_scene_preload_state == LAUNCH_PRELOAD_REQUESTED:
		var progress: Array[float] = []
		var status := ResourceLoader.load_threaded_get_status(
			LAUNCH_SCENE_PATH,
			progress
		)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var resource := ResourceLoader.load_threaded_get(LAUNCH_SCENE_PATH)
			if resource is PackedScene:
				_launch_scene_preload_resource = resource
				_launch_scene_preload_state = LAUNCH_PRELOAD_READY
				_record_launch_timing(&"startup_preload_ready")
				_print_launch_preload_timing()
			else:
				_mark_launch_scene_preload_failed(ERR_FILE_CORRUPT)
			return
		if status in [
			ResourceLoader.THREAD_LOAD_FAILED,
			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		]:
			_mark_launch_scene_preload_failed(ERR_CANT_OPEN)
			return
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_record_launch_timing_once(&"startup_preload_first_pending")
		await get_tree().process_frame


func _mark_launch_scene_preload_failed(error: Error) -> void:
	_launch_scene_preload_resource = null
	_launch_scene_preload_state = LAUNCH_PRELOAD_FAILED
	_record_launch_timing(&"startup_preload_failed")
	if OS.is_debug_build():
		print("[StartupLaunchTiming] stage=main_scene_preload failed_error=%d" % int(error))


func launch_preload_timing_snapshot() -> Dictionary:
	if not is_inside_tree():
		return {}
	var raw: Variant = get_tree().root.get_meta(LAUNCH_PRELOAD_TIMING_META, {})
	return raw.duplicate(true) if raw is Dictionary else {}


func _record_launch_timing(event_name: StringName) -> void:
	if not is_inside_tree():
		return
	var raw: Variant = get_tree().root.get_meta(LAUNCH_PRELOAD_TIMING_META, {})
	var timing: Dictionary = raw.duplicate(true) if raw is Dictionary else {}
	timing[String(event_name)] = Time.get_ticks_usec()
	get_tree().root.set_meta(LAUNCH_PRELOAD_TIMING_META, timing)


func _record_launch_timing_once(event_name: StringName) -> void:
	var timing := launch_preload_timing_snapshot()
	if not timing.has(String(event_name)):
		_record_launch_timing(event_name)


func _print_launch_preload_timing() -> void:
	if not OS.is_debug_build():
		return
	var timing := launch_preload_timing_snapshot()
	var started_usec := int(timing.get("startup_preload_request_started", 0))
	var ready_usec := int(timing.get("startup_preload_ready", 0))
	if started_usec <= 0 or ready_usec < started_usec:
		return
	print(
		"[StartupLaunchTiming] stage=main_scene_preload request_to_ready_ms=%.3f"
		% (float(ready_usec - started_usec) / 1000.0)
	)


func _prepare_authoritative_data() -> void:
	# The autoloads deliberately stay cold on Android. Wait for a real authored
	# CG frame, then perform their finite synchronous work while the CG continues.
	if not bool(brand_intro.get("first_frame_presented")):
		await brand_intro.intro_first_frame_presented
	if not is_inside_tree():
		return
	var success := ContentLayers.ensure_loaded()
	if success:
		success = WorldContent.ensure_loaded()
	if success:
		success = PresentationAssets.reload_skin()
	if success:
		success = GameData.ensure_loaded()
	_authoritative_data_ready = success
	_authoritative_data_failed = not success
	if not success:
		push_error("startup authoritative data preparation failed")
	_check_transition()


func _begin_target_load() -> void:
	# A scene that survived in Godot's resource cache must not be submitted as a
	# second threaded request. That request can be rejected even though the
	# resource is already usable, which used to leave the intro waiting forever.
	if ResourceLoader.has_cached(TARGET_SCENE_PATH):
		_target_scene = ResourceLoader.load(TARGET_SCENE_PATH) as PackedScene
		_resource_ready = _target_scene != null
		_check_transition()
		return
	var request_error := ResourceLoader.load_threaded_request(TARGET_SCENE_PATH)
	_load_requested = request_error == OK or request_error == ERR_BUSY
	if not _load_requested:
		# Keep the first authored frame on screen before the rare synchronous
		# recovery path. A cached/restarted launch must always remain able to reach
		# character selection.
		_recover_target_load.call_deferred(request_error)


func _recover_target_load(request_error: Error) -> void:
	await get_tree().process_frame
	if not is_inside_tree() or _resource_ready:
		return
	_target_scene = ResourceLoader.load(TARGET_SCENE_PATH) as PackedScene
	_resource_ready = _target_scene != null
	if not _resource_ready:
		push_error("startup loading request failed (%s): %s" % [request_error, TARGET_SCENE_PATH])
	_check_transition()


func _process(_delta: float) -> void:
	if not _load_requested or _resource_ready:
		return
	var progress: Array[float] = []
	var status := ResourceLoader.load_threaded_get_status(TARGET_SCENE_PATH, progress)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_target_scene = ResourceLoader.load_threaded_get(TARGET_SCENE_PATH) as PackedScene
		_resource_ready = _target_scene != null
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		_load_requested = false
		_recover_target_load.call_deferred(ERR_CANT_OPEN)
		return
	_check_transition()


func _run_finite_loading_phase() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	if not bool(brand_intro.get("animation_complete")):
		await brand_intro.intro_animation_finished
	if not is_inside_tree():
		return
	_animation_finished = true
	_check_transition()


func _check_transition() -> void:
	# Let the authored CG complete at its intended speed. Character-selection
	# construction is intentionally delayed until then; its expensive _ready()
	# work may block Android's main thread, so the already-rendered final CG frame
	# remains visible as the loading surface instead of freezing the intro near
	# its first semi-transparent logo frame.
	if not _target_prepare_started and _resource_ready and _authoritative_data_ready and _animation_finished:
		_target_prepare_started = true
		_prepare_target_scene.call_deferred()
	if _transition_started or not _target_scene_ready:
		return
	_transition_started = true
	_reveal_target_scene.call_deferred()


func _prepare_target_scene() -> void:
	if not is_inside_tree() or _target_scene == null:
		_target_prepare_started = false
		return
	_target_scene_instance = _target_scene.instantiate()
	if _target_scene_instance == null:
		_target_prepare_started = false
		return
	# Build and settle the next UI behind the completed intro. PackedScene
	# instantiation and _ready() may be expensive on Android, but the already
	# rendered final intro frame remains visible during that synchronous work.
	# change_scene_to_packed() removed the intro first and exposed a black frame.
	if _target_scene_instance is CanvasItem:
		(_target_scene_instance as CanvasItem).visible = false
	get_tree().root.add_child(_target_scene_instance)
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(_target_scene_instance):
		return
	_target_scene_ready = true
	_check_transition()


func _reveal_target_scene() -> void:
	if not is_inside_tree() or not _target_scene_ready or not is_instance_valid(_target_scene_instance):
		_transition_started = false
		return
	if _target_scene_instance is CanvasItem:
		(_target_scene_instance as CanvasItem).visible = true
	if suppress_scene_handoff_for_test:
		return
	get_tree().current_scene = _target_scene_instance
	queue_free()
